use crate::grant::{self, Rights};
use crate::{files, roc_host, roc_platform_abi::*};
use cap_fs_ext::{FollowSymlinks, OpenOptionsFollowExt};
use cap_std::fs::OpenOptions;
use rusqlite::{Connection, MAIN_DB, types::ValueRef};
use std::{
    collections::HashMap,
    io::Read,
    mem::ManuallyDrop,
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

const MAX_DATABASE_BYTES: u64 = 64 * 1024 * 1024;
const MAX_QUERY_BYTES: usize = 64 * 1024;
const MAX_COLUMNS: usize = 256;
const MAX_ROWS: usize = 10_000;
const MAX_VALUE_BYTES: usize = 16 * 1024 * 1024;

struct Store {
    next: u64,
    connections: HashMap<u64, Connection>,
    allocations: HashMap<usize, u64>,
}
static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static OPERATIONS: [AtomicU64; 2] = [const { AtomicU64::new(0) }; 2];
/// What a database snapshot may do. The broker copies the bytes into an
/// in-memory read-only database, so there is nothing to write and nothing
/// narrower to derive.
const SNAPSHOT_RIGHTS: Rights = Rights::READ;

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            connections: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}

pub fn configure() {
    grant::forget_kind(grant::Kind::Sqlite);
    for counter in &OPERATIONS {
        counter.store(0, Ordering::Relaxed);
    }
}

pub fn counters() -> ([u64; 2], usize) {
    let operations = std::array::from_fn(|index| OPERATIONS[index].load(Ordering::Relaxed));
    let connections = store()
        .lock()
        .expect("SQLite capability store poisoned")
        .connections
        .len();
    (operations, connections)
}

fn error(code: u8, message: &'static str) -> HostGlueSqliteQueryErr {
    HostGlueSqliteQueryErr {
        code,
        message: RocStr::from_str(message, roc_host()),
    }
}
fn open_error(code: u8, message: &'static str) -> HostGlueSqliteOpenReadErr {
    HostGlueSqliteOpenReadErr {
        code,
        message: RocStr::from_str(message, roc_host()),
    }
}

fn classify(err: &rusqlite::Error) -> (u8, &'static str) {
    use rusqlite::ErrorCode;
    match err.sqlite_error_code() {
        Some(ErrorCode::DatabaseBusy | ErrorCode::DatabaseLocked) => (1, "database is busy"),
        Some(ErrorCode::DatabaseCorrupt) => (2, "database is corrupt"),
        Some(ErrorCode::NotADatabase) => (7, "file is not a SQLite database"),
        Some(ErrorCode::ReadOnly) => (0, "database is read-only"),
        Some(ErrorCode::TooBig | ErrorCode::OutOfMemory) => (8, "SQLite resource limit exceeded"),
        _ => (5, "invalid SQLite query"),
    }
}

/// The snapshot is derived from the directory grant the database file was read
/// through, so revoking that project revokes every database opened from it. The
/// inventory recorded this as unverified; deriving it makes it true by
/// construction rather than by a rule written twice.
fn capability(connection: Connection, parent: grant::Grant) -> *mut u64 {
    let mut guard = store().lock().expect("SQLite capability store poisoned");
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("SQLite capability ids exhausted");
    let handle = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            core::mem::align_of::<u64>(),
            false,
            roc_host(),
        ) as *mut u64
    };
    unsafe { handle.write(id) };
    let base = unsafe { (handle as *mut u8).sub(core::mem::size_of::<isize>()) };
    guard.connections.insert(id, connection);
    crate::register_resource_allocation(
        crate::resource_domain::SQLITE,
        &mut guard.allocations,
        base as usize,
        id,
    );
    drop(guard);
    grant::record_descendant(grant::Kind::Sqlite, id, SNAPSHOT_RIGHTS, parent);
    handle
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("SQLite capability store poisoned");
    let released = crate::remove_resource_allocation(&mut guard.allocations, base as usize);
    if let Some(id) = released {
        guard.connections.remove(&id);
    }
    drop(guard);
    if let Some(id) = released {
        grant::release(grant::Kind::Sqlite, id);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_sqlite_open_read(
    cap: *mut u64,
    name: RocStr,
) -> HostGlueSqliteOpenReadResult {
    OPERATIONS[0].fetch_add(1, Ordering::Relaxed);
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let opened = files::lookup_accepted(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| {
        let (dir, parent) = opened.ok_or((3, "invalid directory capability"))?;
        if !files::valid_name(&owned_name) {
            return Err((4, "database name must be one direct child"));
        }
        let metadata = dir
            .symlink_metadata(&owned_name)
            .map_err(|_| (6, "could not inspect database file"))?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err((9, "database child must be an ordinary file"));
        }
        if metadata.len() > MAX_DATABASE_BYTES {
            return Err((8, "database exceeds the 64 MiB limit"));
        }
        let mut options = OpenOptions::new();
        options.read(true).follow(FollowSymlinks::No);
        let file = dir
            .open_with(&owned_name, &options)
            .map_err(|_| (0, "database file is not readable"))?;
        let mut bytes = Vec::with_capacity(metadata.len() as usize);
        file.take(MAX_DATABASE_BYTES + 1)
            .read_to_end(&mut bytes)
            .map_err(|_| (6, "could not read database file"))?;
        if bytes.len() as u64 > MAX_DATABASE_BYTES {
            return Err((8, "database exceeds the 64 MiB limit"));
        }
        let mut connection =
            Connection::open_in_memory().map_err(|_| (6, "could not initialize SQLite"))?;
        connection
            .deserialize_read_exact(MAIN_DB, bytes.as_slice(), bytes.len(), true)
            .map_err(|e| classify(&e))?;
        connection
            .set_limit(
                rusqlite::limits::Limit::SQLITE_LIMIT_COLUMN,
                MAX_COLUMNS as i32,
            )
            .map_err(|_| (8, "could not install SQLite column limit"))?;
        connection
            .set_limit(
                rusqlite::limits::Limit::SQLITE_LIMIT_SQL_LENGTH,
                MAX_QUERY_BYTES as i32,
            )
            .map_err(|_| (8, "could not install SQLite query limit"))?;
        Ok(capability(connection, parent))
    })();
    match result {
        Ok(handle) => HostGlueSqliteOpenReadResult {
            payload: HostGlueSqliteOpenReadResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostGlueSqliteOpenReadResultTag::Ok,
        },
        Err((code, message)) => HostGlueSqliteOpenReadResult {
            payload: HostGlueSqliteOpenReadResultPayload {
                err: ManuallyDrop::new(open_error(code, message)),
            },
            tag: HostGlueSqliteOpenReadResultTag::Err,
        },
    }
}

fn cell(value: ValueRef<'_>, total: &mut usize) -> Result<HostGlueSqliteQueryOkRows, ()> {
    let mut result = HostGlueSqliteQueryOkRows {
        integer: 0,
        real: 0.0,
        bytes: RocListWith::empty(),
        text: RocStr::empty(),
        kind: 0,
    };
    match value {
        ValueRef::Null => {}
        ValueRef::Integer(v) => {
            result.kind = 1;
            result.integer = v;
        }
        ValueRef::Real(v) => {
            result.kind = 2;
            result.real = v;
        }
        ValueRef::Text(v) => {
            *total = total.checked_add(v.len()).ok_or(())?;
            if *total > MAX_VALUE_BYTES {
                return Err(());
            }
            result.kind = 3;
            result.text = RocStr::from_slice(v, roc_host());
        }
        ValueRef::Blob(v) => {
            *total = total.checked_add(v.len()).ok_or(())?;
            if *total > MAX_VALUE_BYTES {
                return Err(());
            }
            result.kind = 4;
            result.bytes = unsafe { RocListWith::<u8, false>::from_slice(v, roc_host()) };
        }
    }
    Ok(result)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_sqlite_query(cap: *mut u64, query: RocStr) -> HostGlueSqliteQueryResult {
    OPERATIONS[1].fetch_add(1, Ordering::Relaxed);
    let sql = query.as_str().to_owned();
    unsafe { query.decref(roc_host()) };
    let id = unsafe { cap.as_ref().copied() };
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| -> Result<HostGlueSqliteQueryOk, (u8, &'static str)> {
        if sql.is_empty() || sql.len() > MAX_QUERY_BYTES || sql.as_bytes().contains(&0) {
            return Err((5, "query text is empty or exceeds its limit"));
        }
        let mut guard = store()
            .lock()
            .map_err(|_| (6, "SQLite capability store unavailable"))?;
        let id = id.ok_or((3, "invalid SQLite capability"))?;
        grant::accept(grant::Kind::Sqlite, id, Rights::READ).map_err(|refusal| match refusal {
            grant::Refusal::Revoked => (10, "SQLite authority was withdrawn"),
            _ => (3, "invalid SQLite capability"),
        })?;
        let connection = guard
            .connections
            .get_mut(&id)
            .ok_or((3, "invalid SQLite capability"))?;
        let mut statement = connection.prepare(&sql).map_err(|e| classify(&e))?;
        if !statement.readonly() {
            return Err((0, "only read-only SQLite statements are allowed"));
        }
        let count = statement.column_count();
        if count > MAX_COLUMNS {
            return Err((8, "query exceeds the column limit"));
        }
        let columns_vec: Vec<RocStr> = statement
            .column_names()
            .iter()
            .map(|name| RocStr::from_str(name, roc_host()))
            .collect();
        let mut cursor = statement.query([]).map_err(|e| classify(&e))?;
        let mut rows_vec = Vec::new();
        let mut value_bytes = 0usize;
        while let Some(row) = cursor.next().map_err(|e| classify(&e))? {
            if rows_vec.len() == MAX_ROWS {
                return Err((8, "query exceeds the row limit"));
            }
            let mut values = Vec::with_capacity(count);
            for index in 0..count {
                values.push(
                    cell(
                        row.get_ref(index).map_err(|e| classify(&e))?,
                        &mut value_bytes,
                    )
                    .map_err(|_| (8, "query exceeds the value-byte limit"))?,
                );
            }
            rows_vec.push(unsafe { RocList::from_slice(&values, roc_host()) });
        }
        Ok(HostGlueSqliteQueryOk {
            columns: unsafe { RocList::from_slice(&columns_vec, roc_host()) },
            rows: unsafe { RocList::from_slice(&rows_vec, roc_host()) },
        })
    })();
    match result {
        Ok(value) => HostGlueSqliteQueryResult {
            payload: HostGlueSqliteQueryResultPayload {
                ok: ManuallyDrop::new(value),
            },
            tag: HostGlueSqliteQueryResultTag::Ok,
        },
        Err((code, message)) => HostGlueSqliteQueryResult {
            payload: HostGlueSqliteQueryResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGlueSqliteQueryResultTag::Err,
        },
    }
}
