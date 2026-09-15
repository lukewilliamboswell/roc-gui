use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    fs::OpenOptions,
    io::{Read, Write},
    mem::ManuallyDrop,
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
};

const MAX_KEY_BYTES: usize = 128;
const MAX_VALUE_BYTES: usize = 1024 * 1024;

struct Store {
    root: Option<PathBuf>,
    next: u64,
    temp: u64,
    handles: HashMap<u64, ()>,
    allocations: HashMap<usize, u64>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

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
    let root = match root {
        Some(path) => {
            std::fs::create_dir_all(path)
                .map_err(|_| "could not create preferences storage root".to_string())?;
            Some(
                std::fs::canonicalize(path)
                    .map_err(|_| "could not resolve preferences storage root".to_string())?,
            )
        }
        None => None,
    };
    store()
        .lock()
        .map_err(|_| "preferences store unavailable".to_string())?
        .root = root;
    Ok(())
}

fn valid_key(key: &str) -> bool {
    !key.is_empty()
        && key.len() <= MAX_KEY_BYTES
        && key
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
        && key != "."
        && key != ".."
}

fn error(code: u8, message: &'static str) -> HostGluePreferencesOpenErr {
    HostGluePreferencesOpenErr {
        code,
        message: RocStr::from_str(message, roc_host()),
    }
}

fn allocate_handle(guard: &mut Store) -> *mut u64 {
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("preferences ids exhausted");
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
    guard.handles.insert(id, ());
    guard.allocations.insert(base as usize, id);
    handle
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    if let Ok(mut guard) = store().lock() {
        if let Some(id) = guard.allocations.remove(&(base as usize)) {
            guard.handles.remove(&id);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_preferences_open() -> HostGluePreferencesOpenResult {
    let result = store()
        .lock()
        .map_err(|_| (5, "preferences store unavailable"))
        .and_then(|mut guard| {
            if guard.root.is_none() {
                Err((0, "preferences storage was not granted"))
            } else {
                Ok(allocate_handle(&mut guard))
            }
        });
    match result {
        Ok(handle) => HostGluePreferencesOpenResult {
            payload: HostGluePreferencesOpenResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostGluePreferencesOpenResultTag::Ok,
        },
        Err((code, message)) => HostGluePreferencesOpenResult {
            payload: HostGluePreferencesOpenResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGluePreferencesOpenResultTag::Err,
        },
    }
}

fn lookup(cap: *mut u64) -> Result<PathBuf, (u8, &'static str)> {
    let id = unsafe { cap.as_ref().copied() }.ok_or((1, "invalid preferences capability"))?;
    let guard = store()
        .lock()
        .map_err(|_| (5, "preferences store unavailable"))?;
    if !guard.handles.contains_key(&id) {
        return Err((1, "invalid preferences capability"));
    }
    guard
        .root
        .clone()
        .ok_or((0, "preferences storage was not granted"))
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_preferences_read(
    cap: *mut u64,
    key: RocStr,
) -> HostGluePreferencesReadResult {
    let key_owned = key.as_str().to_owned();
    unsafe { key.decref(roc_host()) };
    let root = lookup(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| {
        let root = root?;
        if !valid_key(&key_owned) {
            return Err((2, "invalid preferences key"));
        }
        let path = root.join(&key_owned);
        let mut options = OpenOptions::new();
        options.read(true).custom_flags(libc::O_NOFOLLOW);
        let file = match options.open(path) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok((false, String::new()));
            }
            Err(_) => return Err((3, "could not read preference")),
        };
        let mut bytes = Vec::new();
        file.take((MAX_VALUE_BYTES + 1) as u64)
            .read_to_end(&mut bytes)
            .map_err(|_| (3, "could not read preference"))?;
        if bytes.len() > MAX_VALUE_BYTES {
            return Err((4, "preference exceeds one MiB"));
        }
        let value = String::from_utf8(bytes).map_err(|_| (3, "preference is not UTF-8"))?;
        Ok((true, value))
    })();
    read_result(result)
}

fn read_result(
    result: Result<(bool, String), (u8, &'static str)>,
) -> HostGluePreferencesReadResult {
    match result {
        Ok((found, value)) => HostGluePreferencesReadResult {
            payload: HostGluePreferencesReadResultPayload {
                ok: ManuallyDrop::new(HostGluePreferencesReadOk {
                    found,
                    value: RocStr::from_str(&value, roc_host()),
                }),
            },
            tag: HostGluePreferencesReadResultTag::Ok,
        },
        Err((code, message)) => HostGluePreferencesReadResult {
            payload: HostGluePreferencesReadResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGluePreferencesReadResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_preferences_write(
    cap: *mut u64,
    key: RocStr,
    value: RocStr,
) -> HostGluePreferencesWriteResult {
    let key_owned = key.as_str().to_owned();
    let value_owned = value.as_str().to_owned();
    unsafe {
        key.decref(roc_host());
        value.decref(roc_host());
    }
    let root = lookup(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| {
        let root = root?;
        if !valid_key(&key_owned) {
            return Err((2, "invalid preferences key"));
        }
        if value_owned.len() > MAX_VALUE_BYTES {
            return Err((4, "preference exceeds one MiB"));
        }
        let temp_id = {
            let mut guard = store()
                .lock()
                .map_err(|_| (5, "preferences store unavailable"))?;
            let id = guard.temp;
            guard.temp = guard
                .temp
                .checked_add(1)
                .ok_or((5, "preferences ids exhausted"))?;
            id
        };
        let target = root.join(&key_owned);
        let temporary = root.join(format!(".prefs-{temp_id}.tmp"));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true).mode(0o600);
        let mut file = options
            .open(&temporary)
            .map_err(|_| (3, "could not create atomic preference"))?;
        let written = file
            .write_all(value_owned.as_bytes())
            .and_then(|_| file.sync_all());
        if written.is_err() {
            let _ = std::fs::remove_file(&temporary);
            return Err((3, "could not write preference"));
        }
        if std::fs::rename(&temporary, &target).is_err() {
            let _ = std::fs::remove_file(&temporary);
            return Err((3, "could not commit preference"));
        }
        if let Ok(directory) = OpenOptions::new().read(true).open(&root) {
            let _ = directory.sync_all();
        }
        Ok(())
    })();
    match result {
        Ok(()) => HostGluePreferencesWriteResult {
            payload: HostGluePreferencesWriteResultPayload { ok: [] },
            tag: HostGluePreferencesWriteResultTag::Ok,
        },
        Err((code, message)) => HostGluePreferencesWriteResult {
            payload: HostGluePreferencesWriteResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGluePreferencesWriteResultTag::Err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn keys_are_bounded_and_flat() {
        assert!(valid_key("profile-v1"));
        assert!(!valid_key("../profile"));
        assert!(!valid_key(""));
        assert!(!valid_key(&"x".repeat(129)));
    }
}
