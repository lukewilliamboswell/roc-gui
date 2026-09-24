use crate::grant::{self, Rights};
use crate::{files, roc_host, roc_platform_abi::*};
use cap_fs_ext::{FollowSymlinks, MetadataExt, OpenOptionsFollowExt};
use cap_std::fs::{Dir, OpenOptions};
use rusqlite::{
    Connection, OpenFlags,
    config::DbConfig,
    limits::Limit,
    types::{Value, ValueRef},
};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

const MAX_QUERY_BYTES: usize = 64 * 1024;
const MAX_COLUMNS: usize = 256;
/// Rows in one unpaged result, and the largest page a caller may ask for.
const MAX_ROWS: usize = 10_000;
/// Aggregate text and blob bytes in one result, and in one parameter list.
const MAX_VALUE_BYTES: usize = 16 * 1024 * 1024;
const MAX_PARAMS: usize = 256;
/// A reader of a database another process is writing waits this long for a
/// checkpoint or recovery to finish before reporting `Busy`.
const BUSY_WAIT: Duration = Duration::from_millis(100);

/// A portable reason code and a bounded diagnostic.
type Failure = (u8, &'static str);
/// The statement's task ended while it ran.
const INTERRUPTED: Failure = (11, "query was interrupted");
/// Virtual machine steps between SQLite's polls of a running statement's task.
const PROGRESS_STEPS: std::ffi::c_int = 10_000;

/// SQLite's progress callback: nonzero stops the statement as interrupted.
extern "C" fn ended(interrupt: *mut std::ffi::c_void) -> std::ffi::c_int {
    let interrupt = unsafe { &*(interrupt as *const crate::tasks::Interrupt) };
    std::ffi::c_int::from(interrupt.requested())
}

struct Store {
    next: u64,
    /// Each connection has a lock of its own, so a statement holds only its
    /// connection while it runs, never the store every release consults.
    connections: HashMap<u64, Arc<Mutex<Connection>>>,
    allocations: HashMap<usize, u64>,
}
static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static OPERATIONS: [AtomicU64; 2] = [const { AtomicU64::new(0) }; 2];
/// What an open database may do: read, and derive a watch of itself. The
/// connection is read-only and cannot attach another file, so there is nothing
/// to write, and a watch is the one narrower thing it hands out.
const DATABASE_RIGHTS: Rights = Rights::READ.union(Rights::DERIVE);

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            connections: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}

/// A database open here never stops another program deleting or renaming over
/// it, on any platform. POSIX has no such lock; SQLite's Windows VFS opens every
/// file without `FILE_SHARE_DELETE`, so a reader would hold a capture against
/// the recorder or person replacing it. The VFS takes its `CreateFileW` from a
/// replaceable system-call table, and the replacement adds that one share
/// right. A rename over an open database then binds the name to the new file,
/// as on Linux, and the watch reports it.
#[cfg(target_os = "windows")]
pub fn share_files_like_posix() {
    use windows_sys::Win32::{
        Foundation::HANDLE,
        Security::SECURITY_ATTRIBUTES,
        Storage::FileSystem::{
            CreateFileW, FILE_CREATION_DISPOSITION, FILE_FLAGS_AND_ATTRIBUTES, FILE_SHARE_DELETE,
            FILE_SHARE_MODE,
        },
    };
    unsafe extern "system" fn create(
        name: *const u16,
        access: u32,
        share: FILE_SHARE_MODE,
        security: *const SECURITY_ATTRIBUTES,
        disposition: FILE_CREATION_DISPOSITION,
        flags: FILE_FLAGS_AND_ATTRIBUTES,
        template: HANDLE,
    ) -> HANDLE {
        unsafe {
            CreateFileW(
                name,
                access,
                share | FILE_SHARE_DELETE,
                security,
                disposition,
                flags,
                template,
            )
        }
    }
    static INSTALLED: OnceLock<()> = OnceLock::new();
    INSTALLED.get_or_init(|| unsafe {
        let vfs = rusqlite::ffi::sqlite3_vfs_find(std::ptr::null());
        let installed = vfs
            .as_ref()
            .and_then(|vfs| vfs.xSetSystemCall)
            .is_some_and(|set| {
                let replacement: rusqlite::ffi::sqlite3_syscall_ptr =
                    Some(std::mem::transmute::<
                        unsafe extern "system" fn(
                            *const u16,
                            u32,
                            FILE_SHARE_MODE,
                            *const SECURITY_ATTRIBUTES,
                            FILE_CREATION_DISPOSITION,
                            FILE_FLAGS_AND_ATTRIBUTES,
                            HANDLE,
                        ) -> HANDLE,
                        unsafe extern "C" fn(),
                    >(create));
                set(vfs, c"CreateFileW".as_ptr(), replacement) == rusqlite::ffi::SQLITE_OK
            });
        assert!(
            installed,
            "SQLite's Windows VFS refused its CreateFileW replacement"
        );
    });
}

#[cfg(not(target_os = "windows"))]
pub fn share_files_like_posix() {}

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

fn classify(err: &rusqlite::Error) -> Failure {
    use rusqlite::ErrorCode;
    match err.sqlite_error_code() {
        Some(ErrorCode::DatabaseBusy | ErrorCode::DatabaseLocked) => (1, "database is busy"),
        Some(ErrorCode::DatabaseCorrupt) => (2, "database is corrupt"),
        Some(ErrorCode::NotADatabase) => (7, "file is not a SQLite database"),
        Some(ErrorCode::ReadOnly) => (0, "database is read-only"),
        Some(ErrorCode::TooBig | ErrorCode::OutOfMemory) => (8, "SQLite resource limit exceeded"),
        Some(ErrorCode::CannotOpen | ErrorCode::SystemIoFailure) => {
            (6, "could not read database file")
        }
        Some(ErrorCode::OperationInterrupted) => INTERRUPTED,
        _ => (5, "invalid SQLite query"),
    }
}

/// The connection is derived from the directory or file grant the database
/// file was opened through, so revoking that grant revokes every database
/// opened from it. Deriving it makes that true by construction rather than by a rule
/// written twice.
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
    guard
        .connections
        .insert(id, Arc::new(Mutex::new(connection)));
    crate::register_resource_allocation(
        crate::resource_domain::SQLITE,
        &mut guard.allocations,
        base as usize,
        id,
    );
    drop(guard);
    grant::record_descendant(grant::Kind::Sqlite, id, DATABASE_RIGHTS, parent);
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

/// Where the granted directory is now. SQLite names its database, write-ahead
/// log, and shared-memory index by path, so the database is opened at the path
/// the directory descriptor currently resolves to, and the file SQLite opened
/// is then checked against the one the descriptor names (see [`open_in_place`]).
#[cfg(target_os = "linux")]
fn directory_path(dir: &Dir) -> std::io::Result<PathBuf> {
    use std::os::fd::AsRawFd;
    std::fs::read_link(format!("/proc/self/fd/{}", dir.as_raw_fd()))
}

#[cfg(target_os = "macos")]
fn directory_path(dir: &Dir) -> std::io::Result<PathBuf> {
    use std::os::{fd::AsRawFd, unix::ffi::OsStrExt};
    let mut buffer = vec![0u8; libc::PATH_MAX as usize];
    if unsafe { libc::fcntl(dir.as_raw_fd(), libc::F_GETPATH, buffer.as_mut_ptr()) } == -1 {
        return Err(std::io::Error::last_os_error());
    }
    let end = buffer
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(buffer.len());
    Ok(PathBuf::from(std::ffi::OsStr::from_bytes(&buffer[..end])))
}

#[cfg(target_os = "windows")]
pub(crate) fn directory_path(dir: &Dir) -> std::io::Result<PathBuf> {
    use std::os::windows::{ffi::OsStringExt, io::AsRawHandle};
    use windows_sys::Win32::Storage::FileSystem::{
        FILE_NAME_NORMALIZED, GetFinalPathNameByHandleW, VOLUME_NAME_DOS,
    };
    let mut buffer = vec![0u16; 1024];
    loop {
        let written = unsafe {
            GetFinalPathNameByHandleW(
                dir.as_raw_handle() as _,
                buffer.as_mut_ptr(),
                buffer.len() as u32,
                FILE_NAME_NORMALIZED | VOLUME_NAME_DOS,
            )
        } as usize;
        if written == 0 {
            return Err(std::io::Error::last_os_error());
        }
        if written < buffer.len() {
            buffer.truncate(written);
            break;
        }
        buffer.resize(written + 1, 0);
    }
    // `\\?\C:\...` names a drive path SQLite's Windows VFS accepts once the
    // verbatim prefix is removed; any other verbatim form is left for
    // `database_uri` to refuse.
    let verbatim: Vec<u16> = r"\\?\".encode_utf16().collect();
    let path = match buffer.strip_prefix(verbatim.as_slice()) {
        Some(rest) if rest.get(1) == Some(&(b':' as u16)) => rest,
        _ => buffer.as_slice(),
    };
    Ok(PathBuf::from(std::ffi::OsString::from_wide(path)))
}

/// A URI naming the database read-only. It is deliberately not `immutable`: a
/// write-ahead-logged database is read through its log and shared-memory
/// index, which SQLite creates beside a WAL database when no writer holds them,
/// so a reader sees every committed write, including those of a writer that is
/// still running. The database file itself is never written.
fn database_uri(path: &Path) -> Option<String> {
    fn encode(bytes: &[u8], uri: &mut String) {
        for byte in bytes {
            match byte {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => {
                    uri.push(*byte as char)
                }
                _ => uri.push_str(&format!("%{byte:02X}")),
            }
        }
    }
    let mut uri = String::from("file:");
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        let bytes = path.as_os_str().as_bytes();
        if !bytes.starts_with(b"/") {
            return None;
        }
        encode(bytes, &mut uri);
    }
    #[cfg(windows)]
    {
        let text = path.to_str()?.replace('\\', "/");
        let drive = text.as_bytes();
        if drive.len() < 3 || !drive[0].is_ascii_alphabetic() || &drive[1..3] != b":/" {
            return None;
        }
        uri.push('/');
        encode(text.as_bytes(), &mut uri);
    }
    uri.push_str("?mode=ro");
    Some(uri)
}

fn same_file(left: &impl MetadataExt, right: &impl MetadataExt) -> bool {
    left.dev() == right.dev() && left.ino() == right.ino()
}

/// Open one direct ordinary child of `dir` in place, read-only.
///
/// The file is first opened through the directory descriptor without following
/// links, which is the authority check. SQLite then opens the same name at the
/// directory's current path — it needs the path to find the write-ahead log
/// and its index beside the database — and the file it reached is compared
/// with the one the descriptor named before and after, so a rename or a link
/// planted between the two opens is refused rather than read.
fn open_in_place(dir: &Dir, name: &str) -> Result<Connection, Failure> {
    if !files::valid_name(name) {
        return Err((4, "database name must be one direct child"));
    }
    let metadata = dir
        .symlink_metadata(name)
        .map_err(|_| (6, "could not inspect database file"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err((9, "database child must be an ordinary file"));
    }
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No);
    let granted = dir
        .open_with(name, &options)
        .and_then(|file| file.metadata())
        .map_err(|_| (0, "database file is not readable"))?;
    if !granted.is_file() {
        return Err((9, "database child must be an ordinary file"));
    }
    let path = directory_path(dir)
        .map_err(|_| (9, "the granted folder has no path SQLite can open"))?
        .join(name);
    let uri = database_uri(&path).ok_or((9, "the granted folder has no path SQLite can open"))?;
    let reached = || {
        // Through cap-std, so the identity compared is the same kind on every
        // host: device and inode, or volume serial and file index on Windows.
        std::fs::File::open(&path)
            .and_then(|file| cap_std::fs::File::from_std(file).metadata())
            .is_ok_and(|opened| same_file(&granted, &opened))
    };
    if !reached() {
        return Err((0, "database file moved while it was being opened"));
    }
    let connection = Connection::open_with_flags(
        &uri,
        OpenFlags::SQLITE_OPEN_READ_ONLY
            | OpenFlags::SQLITE_OPEN_URI
            | OpenFlags::SQLITE_OPEN_NOFOLLOW
            | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|e| classify(&e))?;
    if !reached() {
        return Err((0, "database file moved while it was being opened"));
    }
    restrict(&connection)?;
    // Opening is lazy; reading the schema is what proves the file is a
    // database and that its write-ahead log, if any, can be read.
    connection
        .query_row("SELECT count(*) FROM sqlite_schema", [], |_| Ok(()))
        .map_err(|e| classify(&e))?;
    Ok(connection)
}

/// The limits and switches that keep a connection to one read-only file: no
/// attached databases, no trusted schema functions, defensive mode, and bounded
/// statements.
fn restrict(connection: &Connection) -> Result<(), Failure> {
    let limit = |kind, value: usize| {
        connection
            .set_limit(kind, value as i32)
            .map_err(|_| (8, "could not install SQLite limits"))
    };
    limit(Limit::SQLITE_LIMIT_ATTACHED, 0)?;
    limit(Limit::SQLITE_LIMIT_COLUMN, MAX_COLUMNS)?;
    limit(Limit::SQLITE_LIMIT_SQL_LENGTH, MAX_QUERY_BYTES)?;
    limit(Limit::SQLITE_LIMIT_VARIABLE_NUMBER, MAX_PARAMS)?;
    for (config, value) in [
        (DbConfig::SQLITE_DBCONFIG_DEFENSIVE, true),
        (DbConfig::SQLITE_DBCONFIG_TRUSTED_SCHEMA, false),
    ] {
        connection
            .set_db_config(config, value)
            .map_err(|_| (8, "could not restrict SQLite connection"))?;
    }
    connection
        .pragma_update(None, "query_only", true)
        .map_err(|_| (8, "could not restrict SQLite connection"))?;
    connection
        .busy_timeout(BUSY_WAIT)
        .map_err(|_| (8, "could not restrict SQLite connection"))?;
    Ok(())
}

/// One bounded result. `more` is set only for a page, when at least one row
/// follows the last one returned.
#[derive(Debug, PartialEq)]
struct Page {
    columns: Vec<String>,
    rows: Vec<Vec<Value>>,
    more: bool,
}

/// SQLite does not check that stored text is UTF-8; a Roc `Str` must be, so
/// malformed text is presented with replacement characters.
fn owned(value: ValueRef<'_>) -> Value {
    match value {
        ValueRef::Null => Value::Null,
        ValueRef::Integer(v) => Value::Integer(v),
        ValueRef::Real(v) => Value::Real(v),
        ValueRef::Text(v) => Value::Text(String::from_utf8_lossy(v).into_owned()),
        ValueRef::Blob(v) => Value::Blob(v.to_vec()),
    }
}

fn value_bytes(value: &ValueRef<'_>) -> usize {
    match value {
        ValueRef::Text(bytes) | ValueRef::Blob(bytes) => bytes.len(),
        _ => 0,
    }
}

/// Run one read-only statement with bound parameters. `page_rows` of zero asks
/// for the whole result, which must fit in [`MAX_ROWS`]; otherwise at most
/// `page_rows` rows are returned and `more` records whether the result goes
/// on. Callers page with `LIMIT`/`OFFSET` or a keyset bound as parameters.
fn run_statement(
    connection: &Connection,
    sql: &str,
    params: &[Value],
    page_rows: u64,
    interrupted: &dyn Fn() -> bool,
) -> Result<Page, Failure> {
    if sql.is_empty() || sql.len() > MAX_QUERY_BYTES || sql.as_bytes().contains(&0) {
        return Err((5, "query text is empty or exceeds its limit"));
    }
    if page_rows > MAX_ROWS as u64 {
        return Err((8, "page exceeds the row limit"));
    }
    if params.len() > MAX_PARAMS {
        return Err((8, "query exceeds the parameter limit"));
    }
    let param_bytes = params.iter().fold(0usize, |total, value| {
        total.saturating_add(value_bytes(&ValueRef::from(value)))
    });
    if param_bytes > MAX_VALUE_BYTES {
        return Err((8, "parameters exceed the value-byte limit"));
    }
    let mut statement = connection.prepare(sql).map_err(|e| classify(&e))?;
    if !statement.readonly() {
        return Err((0, "only read-only SQLite statements are allowed"));
    }
    if statement.parameter_count() != params.len() {
        return Err((5, "query parameters do not match its placeholders"));
    }
    let count = statement.column_count();
    if count > MAX_COLUMNS {
        return Err((8, "query exceeds the column limit"));
    }
    let columns = statement
        .column_names()
        .iter()
        .map(|name| (*name).to_owned())
        .collect();
    let mut cursor = statement
        .query(rusqlite::params_from_iter(params))
        .map_err(|e| classify(&e))?;
    let limit = if page_rows == 0 {
        MAX_ROWS
    } else {
        page_rows as usize
    };
    let mut rows = Vec::new();
    let mut total = 0usize;
    let mut more = false;
    while let Some(row) = cursor.next().map_err(|e| classify(&e))? {
        // An interrupt that lands between steps, when SQLite has no statement
        // running to stop, is caught here.
        if interrupted() {
            return Err(INTERRUPTED);
        }
        if rows.len() == limit {
            if page_rows == 0 {
                return Err((8, "query exceeds the row limit"));
            }
            more = true;
            break;
        }
        let mut values = Vec::with_capacity(count);
        for index in 0..count {
            let value = row.get_ref(index).map_err(|e| classify(&e))?;
            total = total.saturating_add(value_bytes(&value));
            if total > MAX_VALUE_BYTES {
                return Err((8, "query exceeds the value-byte limit"));
            }
            values.push(owned(value));
        }
        rows.push(values);
    }
    Ok(Page {
        columns,
        rows,
        more,
    })
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
    let result = opened
        .ok_or((3, "invalid directory capability"))
        .and_then(|(dir, parent)| {
            open_in_place(&dir, &owned_name).map(|connection| capability(connection, parent))
        });
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

/// Open a granted file in place. The connection is derived from the document
/// grant, so withdrawing the file withdraws the connection, exactly as a
/// connection opened from a folder follows that folder.
#[unsafe(no_mangle)]
pub extern "C" fn roc_sqlite_open_file_read(cap: *mut u64) -> HostGlueSqliteOpenFileReadResult {
    OPERATIONS[0].fetch_add(1, Ordering::Relaxed);
    let opened = crate::document::lookup_accepted(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = match opened {
        Err(crate::document::Refused::Revoked) => Err((10, "file authority was withdrawn")),
        Err(crate::document::Refused::Invalid) => Err((3, "invalid file capability")),
        Ok((file, parent)) => {
            open_in_place(&file.dir, &file.name).map(|connection| capability(connection, parent))
        }
    };
    match result {
        Ok(handle) => HostGlueSqliteOpenFileReadResult {
            payload: HostGlueSqliteOpenFileReadResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostGlueSqliteOpenFileReadResultTag::Ok,
        },
        Err((code, message)) => HostGlueSqliteOpenFileReadResult {
            payload: HostGlueSqliteOpenFileReadResultPayload {
                err: ManuallyDrop::new(open_error(code, message)),
            },
            tag: HostGlueSqliteOpenFileReadResultTag::Err,
        },
    }
}

/// Watch the database a connection reads: the folder that holds it, filtered
/// to its file and its write-ahead log. The watch is derived from the
/// connection, and so from the grant the connection was opened through.
#[unsafe(no_mangle)]
pub extern "C" fn roc_sqlite_watch(cap: *mut u64) -> HostGlueSqliteWatchResult {
    let id = unsafe { cap.as_ref().copied() };
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| -> Result<*mut u64, Failure> {
        let id = id.ok_or((3, "invalid SQLite capability"))?;
        let parent =
            grant::accept(grant::Kind::Sqlite, id, Rights::READ).map_err(
                |refusal| match refusal {
                    grant::Refusal::Revoked => (10, "SQLite authority was withdrawn"),
                    _ => (3, "invalid SQLite capability"),
                },
            )?;
        let path = {
            let guard = store()
                .lock()
                .map_err(|_| (6, "SQLite capability store unavailable"))?;
            let held = guard
                .connections
                .get(&id)
                .cloned()
                .ok_or((3, "invalid SQLite capability"))?;
            drop(guard);
            held.lock()
                .map_err(|_| (6, "SQLite connection unavailable"))?
                .path()
                .map(PathBuf::from)
                .ok_or((9, "the database has no file to watch"))?
        };
        let (Some(folder), Some(name)) = (
            path.parent(),
            path.file_name().and_then(|name| name.to_str()),
        ) else {
            return Err((9, "the database has no file to watch"));
        };
        crate::watch::start(
            folder,
            crate::watch::Target::Database {
                name: name.to_owned(),
            },
            parent,
        )
        .map_err(|refusal| match refusal {
            crate::watch::Refusal::Revoked => (10, "SQLite authority was withdrawn"),
            crate::watch::Refusal::ResourceLimit => (8, "no watch is left to give"),
            crate::watch::Refusal::Unsupported => (9, "watching is not supported on this platform"),
            crate::watch::Refusal::Io => (6, "the database could not be watched"),
        })
    })();
    match result {
        Ok(handle) => HostGlueSqliteWatchResult {
            payload: HostGlueSqliteWatchResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostGlueSqliteWatchResultTag::Ok,
        },
        Err((code, message)) => HostGlueSqliteWatchResult {
            payload: HostGlueSqliteWatchResultPayload {
                err: ManuallyDrop::new(HostGlueSqliteWatchErr {
                    code,
                    message: RocStr::from_str(message, roc_host()),
                }),
            },
            tag: HostGlueSqliteWatchResultTag::Err,
        },
    }
}

fn param(raw: &HostGlueSqliteQueryArg1Params) -> Result<Value, Failure> {
    match raw.kind {
        0 => Ok(Value::Null),
        1 => Ok(Value::Integer(raw.integer)),
        2 => Ok(Value::Real(raw.real)),
        3 => Ok(Value::Text(raw.text.as_str().to_owned())),
        4 => Ok(Value::Blob(raw.bytes.as_slice().to_vec())),
        _ => Err((5, "invalid SQLite parameter")),
    }
}

fn cell(value: &Value) -> HostGlueSqliteQueryOkRows {
    let mut result = HostGlueSqliteQueryOkRows {
        integer: 0,
        real: 0.0,
        bytes: RocListWith::empty(),
        text: RocStr::empty(),
        kind: 0,
    };
    match value {
        Value::Null => {}
        Value::Integer(v) => {
            result.kind = 1;
            result.integer = *v;
        }
        Value::Real(v) => {
            result.kind = 2;
            result.real = *v;
        }
        Value::Text(v) => {
            result.kind = 3;
            result.text = RocStr::from_str(v, roc_host());
        }
        Value::Blob(v) => {
            result.kind = 4;
            result.bytes = unsafe { RocListWith::<u8, false>::from_slice(v, roc_host()) };
        }
    }
    result
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_sqlite_query(
    cap: *mut u64,
    request: HostGlueSqliteQueryArg1,
) -> HostGlueSqliteQueryResult {
    OPERATIONS[1].fetch_add(1, Ordering::Relaxed);
    let sql = request.sql.as_str().to_owned();
    let page_rows = request.page_rows;
    let params = if request.params.len() > MAX_PARAMS {
        Err((8, "query exceeds the parameter limit"))
    } else {
        request.params.as_slice().iter().map(param).collect()
    };
    unsafe { request.decref(roc_host()) };
    let id = unsafe { cap.as_ref().copied() };
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| -> Result<Page, Failure> {
        let params: Vec<Value> = params?;
        let held = {
            let guard = store()
                .lock()
                .map_err(|_| (6, "SQLite capability store unavailable"))?;
            let id = id.ok_or((3, "invalid SQLite capability"))?;
            grant::accept(grant::Kind::Sqlite, id, Rights::READ).map_err(
                |refusal| match refusal {
                    grant::Refusal::Revoked => (10, "SQLite authority was withdrawn"),
                    _ => (3, "invalid SQLite capability"),
                },
            )?;
            guard
                .connections
                .get(&id)
                .cloned()
                .ok_or((3, "invalid SQLite capability"))?
        };
        // Only this connection is held while the statement runs: a release,
        // or any other database's statement, does not wait for it.
        let connection = held
            .lock()
            .map_err(|_| (6, "SQLite connection unavailable"))?;
        let connection = &*connection;
        // A task that ends while its statement runs interrupts the statement
        // through this connection's own handle.
        let interrupt = {
            let handle = connection.get_interrupt_handle();
            crate::tasks::Interrupt::arm(move || handle.interrupt())
        };

        if interrupt.requested() {
            Err(INTERRUPTED)
        } else {
            // `sqlite3_interrupt` stops only a statement already running; a
            // task that ends between this check and the first step is caught
            // by the progress handler, which SQLite polls as the statement runs.
            let db = unsafe { connection.handle() };
            let polled = &interrupt as *const crate::tasks::Interrupt as *mut std::ffi::c_void;
            unsafe {
                rusqlite::ffi::sqlite3_progress_handler(db, PROGRESS_STEPS, Some(ended), polled)
            };
            let outcome = run_statement(connection, &sql, &params, page_rows, &|| {
                interrupt.requested()
            });
            unsafe { rusqlite::ffi::sqlite3_progress_handler(db, 0, None, std::ptr::null_mut()) };
            outcome
        }
    })();
    match result {
        Ok(page) => {
            let columns: Vec<RocStr> = page
                .columns
                .iter()
                .map(|name| RocStr::from_str(name, roc_host()))
                .collect();
            let rows: Vec<RocList<HostGlueSqliteQueryOkRows>> = page
                .rows
                .iter()
                .map(|row| {
                    let values: Vec<_> = row.iter().map(cell).collect();
                    unsafe { RocList::from_slice(&values, roc_host()) }
                })
                .collect();
            HostGlueSqliteQueryResult {
                payload: HostGlueSqliteQueryResultPayload {
                    ok: ManuallyDrop::new(HostGlueSqliteQueryOk {
                        columns: unsafe { RocList::from_slice(&columns, roc_host()) },
                        rows: unsafe { RocList::from_slice(&rows, roc_host()) },
                        more: page.more,
                    }),
                },
                tag: HostGlueSqliteQueryResultTag::Ok,
            }
        }
        Err((code, message)) => HostGlueSqliteQueryResult {
            payload: HostGlueSqliteQueryResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGlueSqliteQueryResultTag::Err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cap_std::ambient_authority;

    fn run(
        connection: &Connection,
        sql: &str,
        params: &[Value],
        page_rows: u64,
    ) -> Result<Page, Failure> {
        run_statement(connection, sql, params, page_rows, &|| false)
    }

    #[test]
    fn ending_the_task_interrupts_its_running_statement() {
        let connection = Connection::open_in_memory().unwrap();
        let owner = 0x5e11_0000_0001;
        let slot = crate::tasks::issue(owner, "count".into());
        assert!(crate::tasks::begin(&slot));
        let interrupt = {
            let handle = connection.get_interrupt_handle();
            crate::tasks::Interrupt::arm(move || handle.interrupt())
        };
        let canceller = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(50));
            crate::tasks::cancel(owner, "count");
        });
        let started = std::time::Instant::now();
        // Counting to a billion takes far longer than the cancellation.
        let outcome = run_statement(
            &connection,
            "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000000000) SELECT count(*) FROM n",
            &[],
            0,
            &|| interrupt.requested(),
        );
        canceller.join().unwrap();
        assert_eq!(outcome.unwrap_err(), INTERRUPTED);
        assert!(started.elapsed() < Duration::from_secs(10));
        assert!(interrupt.requested());
        drop(interrupt);
        assert!(!crate::tasks::finish(
            &slot,
            crate::tasks::Owned::new(0, |_| {})
        ));
    }

    fn scratch(label: &str) -> (PathBuf, Dir) {
        let path = std::env::temp_dir().join(format!(
            "roc-gui-sqlite-{label}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).unwrap();
        let dir = Dir::open_ambient_dir(&path, ambient_authority()).unwrap();
        (path, dir)
    }

    fn numbers(path: &Path, rows: i64, wal: bool) -> Connection {
        let writer = Connection::open(path).unwrap();
        if wal {
            writer.pragma_update(None, "journal_mode", "wal").unwrap();
        }
        writer
            .execute_batch("CREATE TABLE numbers(id INTEGER PRIMARY KEY, label TEXT);")
            .unwrap();
        let tx = writer.unchecked_transaction().unwrap();
        for id in 1..=rows {
            tx.execute(
                "INSERT INTO numbers VALUES (?1, ?2)",
                rusqlite::params![id, format!("n{id}")],
            )
            .unwrap();
        }
        tx.commit().unwrap();
        writer
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    #[test]
    fn a_database_larger_than_the_old_snapshot_cap_opens_in_place() {
        let (path, dir) = scratch("large");
        let writer = numbers(&path.join("big.db"), 1, false);
        // A 72 MiB blob puts the file well past what a whole-file copy into
        // memory could afford.
        writer
            .execute_batch(
                "CREATE TABLE padding(data BLOB); INSERT INTO padding VALUES (zeroblob(75497472));",
            )
            .unwrap();
        drop(writer);
        assert!(std::fs::metadata(path.join("big.db")).unwrap().len() > 64 * 1024 * 1024);
        let connection = open_in_place(&dir, "big.db").unwrap();
        let page = run(&connection, "SELECT length(data) FROM padding", &[], 0).unwrap();
        assert_eq!(page.rows, vec![vec![Value::Integer(75_497_472)]]);
        drop((connection, dir));
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn parameters_bind_and_must_match_the_placeholders() {
        let (path, dir) = scratch("params");
        drop(numbers(&path.join("n.db"), 20, false));
        let connection = open_in_place(&dir, "n.db").unwrap();
        let page = run(
            &connection,
            "SELECT id, label, ?3 AS blob, ?4 AS absent, ?5 AS real FROM numbers WHERE id BETWEEN ?1 AND ?2 ORDER BY id",
            &[
                Value::Integer(3),
                Value::Integer(4),
                Value::Blob(vec![1, 2]),
                Value::Null,
                Value::Real(1.5),
            ],
            0,
        )
        .unwrap();
        assert_eq!(page.columns, ["id", "label", "blob", "absent", "real"]);
        assert_eq!(page.rows.len(), 2);
        assert_eq!(page.rows[1][1], Value::Text("n4".into()));
        assert_eq!(page.rows[0][2], Value::Blob(vec![1, 2]));
        assert!(!page.more);
        // Text is bound as a value, never spliced into the statement.
        let quoted = run(
            &connection,
            "SELECT count(*) FROM numbers WHERE label = ?",
            &[Value::Text("n1' OR '1'='1".into())],
            0,
        )
        .unwrap();
        assert_eq!(quoted.rows, vec![vec![Value::Integer(0)]]);
        assert_eq!(
            run(&connection, "SELECT ?1, ?2", &[Value::Integer(1)], 0).unwrap_err(),
            (5, "query parameters do not match its placeholders")
        );
        let too_many = vec![Value::Null; MAX_PARAMS + 1];
        assert_eq!(run(&connection, "SELECT 1", &too_many, 0).unwrap_err().0, 8);
        drop((connection, dir));
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn pages_reach_every_row_beyond_the_unpaged_limit() {
        let (path, dir) = scratch("pages");
        let total = 25_000i64;
        drop(numbers(&path.join("n.db"), total, false));
        let connection = open_in_place(&dir, "n.db").unwrap();
        assert_eq!(
            run(&connection, "SELECT id FROM numbers", &[], 0).unwrap_err(),
            (8, "query exceeds the row limit")
        );
        assert_eq!(
            run(
                &connection,
                "SELECT id FROM numbers",
                &[],
                MAX_ROWS as u64 + 1
            )
            .unwrap_err()
            .0,
            8
        );
        // Keyset paging with a bound parameter.
        let mut after = 0i64;
        let mut seen = 0i64;
        loop {
            let page = run(
                &connection,
                "SELECT id FROM numbers WHERE id > ? ORDER BY id",
                &[Value::Integer(after)],
                MAX_ROWS as u64,
            )
            .unwrap();
            seen += page.rows.len() as i64;
            if let Some(Value::Integer(last)) = page.rows.last().map(|row| row[0].clone()) {
                after = last;
            }
            if !page.more {
                break;
            }
        }
        assert_eq!((seen, after), (total, total));
        // Offset paging reports the final short page without `more`.
        let last = run(
            &connection,
            "SELECT id FROM numbers ORDER BY id LIMIT ? OFFSET ?",
            &[Value::Integer(1000), Value::Integer(24_500)],
            1000,
        )
        .unwrap();
        assert_eq!((last.rows.len(), last.more), (500, false));
        drop((connection, dir));
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn a_reader_sees_a_write_ahead_log_that_is_still_being_written() {
        let (path, dir) = scratch("wal");
        let writer = numbers(&path.join("live.db"), 10, true);
        assert!(path.join("live.db-wal").exists());
        let reader = open_in_place(&dir, "live.db").unwrap();
        let count = |connection: &Connection| {
            run(connection, "SELECT count(*) FROM numbers", &[], 0)
                .unwrap()
                .rows
        };
        assert_eq!(count(&reader), vec![vec![Value::Integer(10)]]);
        writer
            .execute("INSERT INTO numbers VALUES (11, 'n11')", [])
            .unwrap();
        assert_eq!(count(&reader), vec![vec![Value::Integer(11)]]);
        drop(writer);
        drop(reader);
        drop(dir);
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn a_closed_wal_database_opens_and_its_file_is_unchanged() {
        let (path, dir) = scratch("walclosed");
        drop(numbers(&path.join("done.db"), 3, true));
        let before = std::fs::read(path.join("done.db")).unwrap();
        let reader = open_in_place(&dir, "done.db").unwrap();
        assert_eq!(
            run(&reader, "SELECT count(*) FROM numbers", &[], 0)
                .unwrap()
                .rows,
            vec![vec![Value::Integer(3)]]
        );
        drop(reader);
        assert_eq!(std::fs::read(path.join("done.db")).unwrap(), before);
        assert!(names(&path).iter().all(|name| name.starts_with("done.db")));
        drop(dir);
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn the_connection_cannot_write_attach_or_follow_a_link() {
        let (path, dir) = scratch("confine");
        drop(numbers(&path.join("n.db"), 1, false));
        drop(numbers(&path.join("other.db"), 1, false));
        let connection = open_in_place(&dir, "n.db").unwrap();
        assert_eq!(
            run(&connection, "DELETE FROM numbers", &[], 0)
                .unwrap_err()
                .0,
            0
        );
        let attach = path.join("other.db");
        assert!(
            run(
                &connection,
                "ATTACH ? AS other",
                &[Value::Text(attach.to_string_lossy().into_owned())],
                0
            )
            .is_err()
        );
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(path.join("n.db"), path.join("link.db")).unwrap();
            assert_eq!(open_in_place(&dir, "link.db").unwrap_err().0, 9);
        }
        assert_eq!(open_in_place(&dir, "../n.db").unwrap_err().0, 4);
        std::fs::write(
            path.join("text.db"),
            b"not a database at all, just some bytes",
        )
        .unwrap();
        assert_eq!(open_in_place(&dir, "text.db").unwrap_err().0, 7);
        drop((connection, dir));
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn database_uris_escape_reserved_characters() {
        #[cfg(unix)]
        assert_eq!(
            database_uri(Path::new("/tmp/a b/c?#%.db")).unwrap(),
            "file:/tmp/a%20b/c%3F%23%25.db?mode=ro"
        );
        #[cfg(unix)]
        assert!(database_uri(Path::new("relative.db")).is_none());
    }
}
