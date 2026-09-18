use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{roc_host, roc_platform_abi::*};
use cap_fs_ext::{FollowSymlinks, OpenOptionsFollowExt};
#[cfg(unix)]
use cap_std::fs::OpenOptionsExt;
use cap_std::{
    ambient_authority,
    fs::{Dir, OpenOptions},
};
use std::{
    collections::HashMap,
    io::{Read, Write},
    mem::ManuallyDrop,
    path::Path,
    sync::{Arc, Mutex, OnceLock},
};

const MAX_NAME_BYTES: usize = 128;
const MAX_VALUE_BYTES: usize = 1024 * 1024;

struct Store {
    root: Option<Arc<Dir>>,
    next: u64,
    temp: u64,
    handles: HashMap<u64, Arc<Dir>>,
    allocations: HashMap<usize, u64>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

/// What private application storage may do. It is the one read-write directory
/// this platform hands out, and it never derives: its children are flat keys
/// rather than nested handles.
const STORAGE_RIGHTS: Rights = Rights::READ.union(Rights::WRITE).union(Rights::LIST);

/// How it arrives. It carries no user data and no authority beyond itself, so
/// the contract provisions it automatically rather than prompting for it.
const STORAGE_ORIGIN: Origin = Origin::Automatic;

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            root: None,
            next: 1,
            temp: 1,
            handles: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}

pub fn configure(root: Option<&Path>) -> Result<(), String> {
    grant::forget_kind(grant::Kind::AppData);
    let root = match root {
        Some(path) => {
            std::fs::create_dir_all(path)
                .map_err(|_| "could not create application data storage root".to_string())?;
            Some(Arc::new(
                Dir::open_ambient_dir(path, ambient_authority())
                    .map_err(|_| "could not open application data storage root".to_string())?,
            ))
        }
        None => None,
    };
    store()
        .lock()
        .map_err(|_| "application data store unavailable".to_string())?
        .root = root;
    Ok(())
}

fn valid_name(key: &str) -> bool {
    !key.is_empty()
        && key.len() <= MAX_NAME_BYTES
        && key
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
        && key != "."
        && key != ".."
}

fn error(code: u8, message: &'static str) -> InternalFilesAppDataErr {
    InternalFilesAppDataErr {
        code,
        message: RocStr::from_str(message, roc_host()),
    }
}

fn allocate_handle(guard: &mut Store, directory: Arc<Dir>) -> *mut u64 {
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("application data ids exhausted");
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
    guard.handles.insert(id, directory);
    crate::register_resource_allocation(crate::resource_domain::APP_DATA, &mut guard.allocations, base as usize, id);
    grant::record_root(
        grant::Kind::AppData,
        id,
        STORAGE_RIGHTS,
        STORAGE_ORIGIN,
        Lifetime::Session,
    );
    handle
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut released = None;
    if let Ok(mut guard) = store().lock()
        && let Some(id) = crate::remove_resource_allocation(&mut guard.allocations, base as usize)
    {
        guard.handles.remove(&id);
        released = Some(id);
    }
    if let Some(id) = released {
        grant::release(grant::Kind::AppData, id);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_app_data() -> InternalFilesAppDataResult {
    let result = store()
        .lock()
        .map_err(|_| (5, "application data store unavailable"))
        .and_then(|mut guard| {
            if guard.root.is_none() {
                Err((0, "application data storage was not granted"))
            } else {
                let directory = guard.root.clone().expect("checked application data root");
                Ok(allocate_handle(&mut guard, directory))
            }
        });
    match result {
        Ok(handle) => InternalFilesAppDataResult {
            payload: InternalFilesAppDataResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: InternalFilesAppDataResultTag::Ok,
        },
        Err((code, message)) => InternalFilesAppDataResult {
            payload: InternalFilesAppDataResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: InternalFilesAppDataResultTag::Err,
        },
    }
}

fn lookup(cap: *mut u64) -> Result<Arc<Dir>, (u8, &'static str)> {
    let id = unsafe { cap.as_ref().copied() }.ok_or((1, "invalid application data capability"))?;
    grant::accept(grant::Kind::AppData, id, Rights::READ)
        .map_err(|_| (1, "invalid application data capability"))?;
    let guard = store()
        .lock()
        .map_err(|_| (5, "application data store unavailable"))?;
    guard
        .handles
        .get(&id)
        .cloned()
        .ok_or((1, "invalid application data capability"))
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_read_utf8(
    cap: *mut u64,
    name: RocStr,
) -> InternalFilesReadUtf8Result {
    let name_owned = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let root = lookup(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| {
        let root = root?;
        if !valid_name(&name_owned) {
            return Err((2, "invalid application data file name"));
        }
        let mut options = OpenOptions::new();
        options.read(true).follow(FollowSymlinks::No);
        let file = match root.open_with(&name_owned, &options) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok((false, String::new()));
            }
            Err(_) => return Err((3, "could not read application data file")),
        };
        let mut bytes = Vec::new();
        file.take((MAX_VALUE_BYTES + 1) as u64)
            .read_to_end(&mut bytes)
            .map_err(|_| (3, "could not read application data file"))?;
        if bytes.len() > MAX_VALUE_BYTES {
            return Err((4, "application data file exceeds one MiB"));
        }
        let value =
            String::from_utf8(bytes).map_err(|_| (3, "application data file is not UTF-8"))?;
        Ok((true, value))
    })();
    read_result(result)
}

fn read_result(result: Result<(bool, String), (u8, &'static str)>) -> InternalFilesReadUtf8Result {
    match result {
        Ok((found, value)) => InternalFilesReadUtf8Result {
            payload: InternalFilesReadUtf8ResultPayload {
                ok: ManuallyDrop::new(InternalFilesReadUtf8Ok {
                    found,
                    value: RocStr::from_str(&value, roc_host()),
                }),
            },
            tag: InternalFilesReadUtf8ResultTag::Ok,
        },
        Err((code, message)) => InternalFilesReadUtf8Result {
            payload: InternalFilesReadUtf8ResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: InternalFilesReadUtf8ResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_write_utf8_atomic(
    cap: *mut u64,
    name: RocStr,
    value: RocStr,
) -> InternalFilesWriteUtf8AtomicResult {
    let name_owned = name.as_str().to_owned();
    let value_owned = value.as_str().to_owned();
    unsafe {
        name.decref(roc_host());
        value.decref(roc_host());
    }
    let root = lookup(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| {
        let root = root?;
        if !valid_name(&name_owned) {
            return Err((2, "invalid application data file name"));
        }
        if value_owned.len() > MAX_VALUE_BYTES {
            return Err((4, "application data file exceeds one MiB"));
        }
        let temp_id = {
            let mut guard = store()
                .lock()
                .map_err(|_| (5, "application data store unavailable"))?;
            let id = guard.temp;
            guard.temp = guard
                .temp
                .checked_add(1)
                .ok_or((5, "application data ids exhausted"))?;
            id
        };
        let temporary = format!(".app-data-{temp_id}.tmp");
        let mut options = OpenOptions::new();
        options
            .write(true)
            .create_new(true)
            .follow(FollowSymlinks::No);
        #[cfg(unix)]
        options.mode(0o600);
        let mut file = root
            .open_with(&temporary, &options)
            .map_err(|_| (3, "could not create atomic application data file"))?;
        let written = file
            .write_all(value_owned.as_bytes())
            .and_then(|_| file.sync_all());
        if written.is_err() {
            let _ = root.remove_file(&temporary);
            return Err((3, "could not write application data file"));
        }
        if root.rename(&temporary, &root, &name_owned).is_err() {
            let _ = root.remove_file(&temporary);
            return Err((3, "could not commit application data file"));
        }
        if let Ok(directory) = root.try_clone() {
            let _ = directory.into_std_file().sync_all();
        }
        Ok(())
    })();
    match result {
        Ok(()) => InternalFilesWriteUtf8AtomicResult {
            payload: InternalFilesWriteUtf8AtomicResultPayload { ok: [] },
            tag: InternalFilesWriteUtf8AtomicResultTag::Ok,
        },
        Err((code, message)) => InternalFilesWriteUtf8AtomicResult {
            payload: InternalFilesWriteUtf8AtomicResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: InternalFilesWriteUtf8AtomicResultTag::Err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn keys_are_bounded_and_flat() {
        assert!(valid_name("profile-v1"));
        assert!(!valid_name("../profile"));
        assert!(!valid_name(""));
        assert!(!valid_name(&"x".repeat(129)));
    }
}
