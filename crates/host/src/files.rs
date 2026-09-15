use crate::{roc_host, roc_platform_abi::*};
use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt};
use cap_std::{
    ambient_authority,
    fs::{Dir, OpenOptions},
};
use std::{
    collections::HashMap,
    io::Read,
    mem::ManuallyDrop,
    path::{Component, Path},
    sync::{Arc, Mutex, OnceLock},
};

const MAX_ENTRIES: usize = 10_000;
const MAX_NAME_BYTES: usize = 4 * 1024 * 1024;
const MAX_FILE_BYTES: u64 = 64 * 1024 * 1024;
struct Store {
    next: u64,
    initial: Option<(Arc<Dir>, String)>,
    dirs: HashMap<u64, Arc<Dir>>,
    allocations: HashMap<usize, u64>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            initial: None,
            dirs: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}

pub fn configure(path: Option<&Path>) -> Result<(), String> {
    let initial = match path {
        None => None,
        Some(path) => {
            let dir = Dir::open_ambient_dir(path, ambient_authority())
                .map_err(|error| format!("cannot grant directory: {error}"))?;
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("directory")
                .to_owned();
            Some((Arc::new(dir), name))
        }
    };
    store().lock().expect("capability store poisoned").initial = initial;
    Ok(())
}

fn capability(dir: Arc<Dir>) -> *mut u64 {
    let mut guard = store().lock().expect("capability store poisoned");
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("directory capability ids exhausted");
    let handle = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            core::mem::align_of::<u64>(),
            false,
            roc_host(),
        ) as *mut u64
    };
    unsafe { handle.write(id) };
    let allocation_base = unsafe { (handle as *mut u8).sub(core::mem::size_of::<isize>()) };
    guard.dirs.insert(id, dir);
    guard.allocations.insert(allocation_base as usize, id);
    handle
}

pub(crate) fn lookup(handle: *mut u64) -> Option<Arc<Dir>> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.dirs.get(&id).cloned()
}

pub fn route_dealloc(allocation_base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("capability store poisoned");
    if let Some(id) = guard.allocations.remove(&(allocation_base as usize)) {
        guard.dirs.remove(&id);
    }
}

fn reason(error: &std::io::Error) -> AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported{
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported as R;
    match error.kind() {
        std::io::ErrorKind::NotFound => R::NotFound,
        std::io::ErrorKind::PermissionDenied => R::AccessDenied,
        std::io::ErrorKind::NotADirectory => R::NotDirectory,
        _ => R::Io,
    }
}

fn error(
    operation: ListDirectoryOrOpenReadDirectoryOrPickDirectoryOrReadFile,
    reason: AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported,
) -> FilesPickDirectoryErr {
    FilesPickDirectoryErr { operation, reason }
}

pub(crate) fn valid_name(name: &str) -> bool {
    let mut parts = Path::new(name).components();
    matches!(parts.next(), Some(Component::Normal(_))) && parts.next().is_none()
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_pick_directory() -> FilesPickDirectoryResult {
    let initial = store()
        .lock()
        .expect("capability store poisoned")
        .initial
        .clone();
    match initial {
        None => FilesPickDirectoryResult {
            payload: FilesPickDirectoryResultPayload { err: ManuallyDrop::new(error(ListDirectoryOrOpenReadDirectoryOrPickDirectoryOrReadFile::PickDirectory, AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::AccessDenied)) },
            tag: FilesPickDirectoryResultTag::Err,
        },
        Some((dir, name)) => {
            let chosen = FilesPickDirectoryOkChosen { directory: capability(dir), name: RocStr::from_str(&name, roc_host()) };
            FilesPickDirectoryResult {
                payload: FilesPickDirectoryResultPayload { ok: ManuallyDrop::new(CanceledOrChosen { payload: CanceledOrChosenPayload { chosen: ManuallyDrop::new(chosen) }, tag: CanceledOrChosenTag::Chosen }) },
                tag: FilesPickDirectoryResultTag::Ok,
            }
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_list(cap: *mut u64) -> FilesDirListResult {
    let dir = lookup(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let Some(dir) = dir else {
        return FilesDirListResult { payload: FilesDirListResultPayload { err: ManuallyDrop::new(error(ListDirectoryOrOpenReadDirectoryOrPickDirectoryOrReadFile::ListDirectory, AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::InvalidCapability)) }, tag: FilesDirListResultTag::Err };
    };
    let result = (|| -> std::io::Result<Vec<AnonStruct770b9d9b3d3d255>> {
        let mut values = Vec::new();
        let mut name_bytes = 0usize;
        for item in dir.entries()? {
            if values.len() == MAX_ENTRIES {
                return Err(std::io::Error::other("entry limit"));
            }
            let item = item?;
            let name = item.file_name().into_string().map_err(|_| {
                std::io::Error::new(std::io::ErrorKind::InvalidData, "non-UTF-8 name")
            })?;
            name_bytes = name_bytes.saturating_add(name.len());
            if name_bytes > MAX_NAME_BYTES {
                return Err(std::io::Error::other("name byte limit"));
            }
            let ty = item.file_type()?;
            let kind = if ty.is_symlink() {
                DirectoryOrFileOrOtherOrSymbolicLink::SymbolicLink
            } else if ty.is_dir() {
                DirectoryOrFileOrOtherOrSymbolicLink::Directory
            } else if ty.is_file() {
                DirectoryOrFileOrOtherOrSymbolicLink::File
            } else {
                DirectoryOrFileOrOtherOrSymbolicLink::Other
            };
            let bytes = if ty.is_file() {
                NoneOrSome {
                    payload: NoneOrSomePayload {
                        some: ManuallyDrop::new(item.metadata()?.len()),
                    },
                    tag: NoneOrSomeTag::Some,
                }
            } else {
                NoneOrSome {
                    payload: NoneOrSomePayload { none: [] },
                    tag: NoneOrSomeTag::None,
                }
            };
            values.push(AnonStruct770b9d9b3d3d255 {
                bytes,
                name: RocStr::from_str(&name, roc_host()),
                kind,
            });
        }
        values.sort_by(|a, b| a.name.as_str().cmp(b.name.as_str()));
        Ok(values)
    })();
    match result {
        Ok(values) => FilesDirListResult {
            payload: FilesDirListResultPayload {
                ok: ManuallyDrop::new(unsafe { RocList::from_slice(&values, roc_host()) }),
            },
            tag: FilesDirListResultTag::Ok,
        },
        Err(io) => FilesDirListResult {
            payload: FilesDirListResultPayload {
                err: ManuallyDrop::new(error(
                    ListDirectoryOrOpenReadDirectoryOrPickDirectoryOrReadFile::ListDirectory,
                    if io.kind() == std::io::ErrorKind::InvalidData {
                        AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::InvalidUtf8
                    } else if io.kind() == std::io::ErrorKind::Other {
                        AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::ResourceLimit
                    } else {
                        reason(&io)
                    },
                )),
            },
            tag: FilesDirListResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_open_read(
    cap: *mut u64,
    name: RocStr,
) -> FilesDirOpenReadDirResult {
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let dir = lookup(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = match dir {
        None => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::InvalidCapability),
        Some(_) if !valid_name(&owned_name) => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::InvalidName),
        Some(dir) => dir.open_dir_nofollow(&owned_name).map(Arc::new).map_err(|io| reason(&io)),
    };
    match result {
        Ok(dir) => FilesDirOpenReadDirResult {
            payload: FilesDirOpenReadDirResultPayload {
                ok: ManuallyDrop::new(capability(dir)),
            },
            tag: FilesDirOpenReadDirResultTag::Ok,
        },
        Err(value) => FilesDirOpenReadDirResult {
            payload: FilesDirOpenReadDirResultPayload {
                err: ManuallyDrop::new(error(
                    ListDirectoryOrOpenReadDirectoryOrPickDirectoryOrReadFile::OpenReadDirectory,
                    value,
                )),
            },
            tag: FilesDirOpenReadDirResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_read(cap: *mut u64, name: RocStr) -> FilesDirReadResult {
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let dir = lookup(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| -> Result<Vec<u8>, AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported> {
        let dir = dir.ok_or(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::InvalidCapability)?;
        if !valid_name(&owned_name) {
            return Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::InvalidName);
        }
        let metadata = dir.symlink_metadata(&owned_name).map_err(|io| reason(&io))?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::Unsupported);
        }
        if metadata.len() > MAX_FILE_BYTES {
            return Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::ResourceLimit);
        }
        let mut options = OpenOptions::new();
        options.read(true).follow(FollowSymlinks::No);
        let file = dir.open_with(&owned_name, &options).map_err(|io| reason(&io))?;
        let mut bytes = Vec::with_capacity(metadata.len() as usize);
        file.take(MAX_FILE_BYTES + 1).read_to_end(&mut bytes).map_err(|io| reason(&io))?;
        if bytes.len() as u64 > MAX_FILE_BYTES {
            Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrUnavailableOrUnsupported::ResourceLimit)
        } else {
            Ok(bytes)
        }
    })();
    match result {
        Ok(bytes) => FilesDirReadResult {
            payload: FilesDirReadResultPayload {
                ok: ManuallyDrop::new(unsafe {
                    RocListWith::<u8, false>::from_slice(&bytes, roc_host())
                }),
            },
            tag: FilesDirReadResultTag::Ok,
        },
        Err(value) => FilesDirReadResult {
            payload: FilesDirReadResultPayload {
                err: ManuallyDrop::new(error(
                    ListDirectoryOrOpenReadDirectoryOrPickDirectoryOrReadFile::ReadFile,
                    value,
                )),
            },
            tag: FilesDirReadResultTag::Err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::valid_name;

    #[test]
    fn child_names_cannot_escape_or_add_components() {
        assert!(valid_name("child"));
        assert!(!valid_name(""));
        assert!(!valid_name("."));
        assert!(!valid_name(".."));
        assert!(!valid_name("../outside"));
        assert!(!valid_name("nested/child"));
        assert!(!valid_name("/absolute"));
    }
}
