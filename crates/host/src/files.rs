use crate::{roc_host, roc_platform_abi::*};
use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt};
use cap_std::{
    ambient_authority,
    fs::{Dir, OpenOptions},
};
use std::{
    collections::{HashMap, HashSet},
    io::Read,
    mem::ManuallyDrop,
    path::{Component, Path},
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, Instant},
};

const MAX_ENTRIES: usize = 10_000;
const MAX_NAME_BYTES: usize = 4 * 1024 * 1024;
const MAX_FILE_BYTES: u64 = 64 * 1024 * 1024;
struct Store {
    next: u64,
    initial: Option<(Arc<Dir>, String)>,
    dirs: HashMap<u64, Arc<Dir>>,
    allocations: HashMap<usize, u64>,
    metadata: HashMap<u64, GrantMetadata>,
    revoked_roots: HashSet<u64>,
    operations: [u64; 4],
    selection: [u64; 7],
    portal_enabled: bool,
    chooser_in_flight: bool,
    refusal_until: Option<Instant>,
    lifecycle: [u64; 6],
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum GrantSource {
    Portal,
    Provisioned,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum GrantLifetime {
    Session,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct GrantMetadata {
    source: GrantSource,
    lifetime: GrantLifetime,
    parent: Option<u64>,
    root: u64,
}
const REFUSAL_COOLDOWN: Duration = Duration::from_secs(2);

fn derived_metadata(parent: u64, metadata: GrantMetadata) -> GrantMetadata {
    GrantMetadata {
        parent: Some(parent),
        ..metadata
    }
}

fn prompt_is_allowed(
    portal_enabled: bool,
    in_flight: bool,
    refusal_until: Option<Instant>,
    now: Instant,
) -> bool {
    portal_enabled && !in_flight && refusal_until.is_none_or(|until| until <= now)
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            initial: None,
            dirs: HashMap::new(),
            allocations: HashMap::new(),
            metadata: HashMap::new(),
            revoked_roots: HashSet::new(),
            operations: [0; 4],
            selection: [0; 7],
            portal_enabled: false,
            chooser_in_flight: false,
            refusal_until: None,
            lifecycle: [0; 6],
        })
    })
}

pub fn configure(path: Option<&Path>, portal_enabled: bool) -> Result<(), String> {
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
    let mut guard = store().lock().expect("capability store poisoned");
    guard.initial = initial;
    guard.operations = [0; 4];
    guard.selection = [0; 7];
    guard.portal_enabled = portal_enabled;
    guard.chooser_in_flight = false;
    guard.refusal_until = None;
    guard.revoked_roots.clear();
    guard.lifecycle = [0; 6];
    if guard.initial.is_some() {
        guard.selection[6] = 1;
    }
    Ok(())
}

pub fn selection_counts() -> [u64; 7] {
    store().lock().expect("capability store poisoned").selection
}

pub fn operation_counts() -> [u64; 4] {
    store()
        .lock()
        .expect("capability store poisoned")
        .operations
}

pub fn lifecycle_counts() -> [u64; 6] {
    store().lock().expect("capability store poisoned").lifecycle
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct AccessSnapshot {
    pub portal_session_read: u64,
    pub provisioned_session_read: u64,
    pub revoked: u64,
}

pub fn access_snapshot() -> AccessSnapshot {
    let guard = store().lock().expect("capability store poisoned");
    let mut snapshot = AccessSnapshot::default();
    for metadata in guard
        .metadata
        .values()
        .filter(|value| value.parent.is_none())
    {
        if guard.revoked_roots.contains(&metadata.root) {
            snapshot.revoked += 1;
        } else {
            match metadata.source {
                GrantSource::Portal => snapshot.portal_session_read += 1,
                GrantSource::Provisioned => snapshot.provisioned_session_read += 1,
            }
        }
    }
    snapshot
}

pub fn revoke_all_roots() -> usize {
    let mut guard = store().lock().expect("capability store poisoned");
    guard.lifecycle[3] += 1;
    let roots: Vec<u64> = guard
        .metadata
        .values()
        .filter(|value| value.parent.is_none())
        .map(|value| value.root)
        .collect();
    let mut changed = 0;
    for root in roots {
        if guard.revoked_roots.insert(root) {
            changed += 1;
        }
    }
    if changed > 0 {
        guard.lifecycle[4] += 1;
    }
    changed
}

fn record_operation(index: usize) {
    let mut guard = store().lock().expect("capability store poisoned");
    guard.operations[index] = guard.operations[index].saturating_add(1);
}

fn capability(dir: Arc<Dir>, mut metadata: GrantMetadata) -> *mut u64 {
    let mut guard = store().lock().expect("capability store poisoned");
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("directory capability ids exhausted");
    if metadata.parent.is_none() {
        metadata.root = id;
        guard.lifecycle[0] += 1;
    } else {
        guard.lifecycle[1] += 1;
    }
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
    guard.metadata.insert(id, metadata);
    guard.allocations.insert(allocation_base as usize, id);
    guard.lifecycle[2] += 1;
    handle
}

pub(crate) fn lookup(handle: *mut u64) -> Option<Arc<Dir>> {
    lookup_state(handle).ok()
}

#[derive(Clone, Copy)]
enum LookupError {
    Invalid,
    Revoked,
}

fn lookup_state(handle: *mut u64) -> Result<Arc<Dir>, LookupError> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(LookupError::Invalid)?;
    let mut guard = store().lock().map_err(|_| LookupError::Invalid)?;
    let metadata = guard.metadata.get(&id).ok_or(LookupError::Invalid)?;
    if guard.revoked_roots.contains(&metadata.root) {
        guard.lifecycle[5] += 1;
        Err(LookupError::Revoked)
    } else {
        guard.dirs.get(&id).cloned().ok_or(LookupError::Invalid)
    }
}

fn grant_metadata(handle: *mut u64) -> Option<(u64, GrantMetadata)> {
    let id = unsafe { handle.as_ref().copied()? };
    let metadata = store().lock().ok()?.metadata.get(&id).copied()?;
    Some((id, metadata))
}

pub fn route_dealloc(allocation_base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("capability store poisoned");
    if let Some(id) = guard.allocations.remove(&(allocation_base as usize)) {
        guard.dirs.remove(&id);
        guard.metadata.remove(&id);
        guard.lifecycle[2] = guard.lifecycle[2].saturating_sub(1);
    }
}

fn reason(error: &std::io::Error) -> AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported{
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    match error.kind() {
        std::io::ErrorKind::NotFound => R::NotFound,
        std::io::ErrorKind::PermissionDenied => R::AccessDenied,
        std::io::ErrorKind::NotADirectory => R::NotDirectory,
        _ => R::Io,
    }
}

type FileReason = AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported;
type FileErr = ListDirectoryErrOrOpenAppDataErrOrOpenReadDirectoryErrOrPickDirectoryErrOrReadFileErrOrWriteFileErr;
type FileErrPayload = ListDirectoryErrOrOpenAppDataErrOrOpenReadDirectoryErrOrPickDirectoryErrOrReadFileErrOrWriteFileErrPayload;
type FileErrTag = ListDirectoryErrOrOpenAppDataErrOrOpenReadDirectoryErrOrPickDirectoryErrOrReadFileErrOrWriteFileErrTag;

fn list_directory_err(reason: FileReason) -> FileErr {
    FileErr {
        payload: FileErrPayload {
            list_directory_err: ManuallyDrop::new(reason),
        },
        tag: FileErrTag::ListDirectoryErr,
    }
}

fn open_read_directory_err(reason: FileReason) -> FileErr {
    FileErr {
        payload: FileErrPayload {
            open_read_directory_err: ManuallyDrop::new(reason),
        },
        tag: FileErrTag::OpenReadDirectoryErr,
    }
}

fn pick_directory_err(reason: FileReason) -> FileErr {
    FileErr {
        payload: FileErrPayload {
            pick_directory_err: ManuallyDrop::new(reason),
        },
        tag: FileErrTag::PickDirectoryErr,
    }
}

fn read_file_err(reason: FileReason) -> FileErr {
    FileErr {
        payload: FileErrPayload {
            read_file_err: ManuallyDrop::new(reason),
        },
        tag: FileErrTag::ReadFileErr,
    }
}

pub(crate) fn valid_name(name: &str) -> bool {
    let mut parts = Path::new(name).components();
    matches!(parts.next(), Some(Component::Normal(_))) && parts.next().is_none()
}

pub(crate) enum BoundedReadError {
    InvalidCapability,
    InvalidName,
    ResourceLimit,
    Io,
}

pub(crate) fn read_bounded(handle: *mut u64, name: &str) -> Result<Vec<u8>, BoundedReadError> {
    if !valid_name(name) {
        return Err(BoundedReadError::InvalidName);
    }
    let dir = lookup(handle).ok_or(BoundedReadError::InvalidCapability)?;
    let mut options = OpenOptions::new();
    options.read(true);
    let mut file = dir
        .open_with(name, &options.follow(FollowSymlinks::No))
        .map_err(|_| BoundedReadError::Io)?;
    let length = file.metadata().map_err(|_| BoundedReadError::Io)?.len();
    if length > MAX_FILE_BYTES {
        return Err(BoundedReadError::ResourceLimit);
    }
    let mut bytes = Vec::with_capacity(length as usize);
    file.read_to_end(&mut bytes)
        .map_err(|_| BoundedReadError::Io)?;
    Ok(bytes)
}

fn chosen(dir: Arc<Dir>, name: &str, source: GrantSource) -> FilesPickDirectoryResult {
    let directory = capability(
        dir,
        GrantMetadata {
            source,
            lifetime: GrantLifetime::Session,
            parent: None,
            root: 0,
        },
    );
    let value = FilesPickDirectoryOkChosen {
        directory,
        name: RocStr::from_str(name, roc_host()),
    };
    FilesPickDirectoryResult {
        payload: FilesPickDirectoryResultPayload {
            ok: ManuallyDrop::new(CanceledOrChosen {
                payload: CanceledOrChosenPayload {
                    chosen: ManuallyDrop::new(value),
                },
                tag: CanceledOrChosenTag::Chosen,
            }),
        },
        tag: FilesPickDirectoryResultTag::Ok,
    }
}

fn canceled() -> FilesPickDirectoryResult {
    FilesPickDirectoryResult {
        payload: FilesPickDirectoryResultPayload {
            ok: ManuallyDrop::new(CanceledOrChosen {
                payload: CanceledOrChosenPayload { canceled: [] },
                tag: CanceledOrChosenTag::Canceled,
            }),
        },
        tag: FilesPickDirectoryResultTag::Ok,
    }
}

enum PortalSelection {
    Chosen(Arc<Dir>, String),
    Canceled,
    Denied,
    Unavailable,
}

fn portal_directory() -> PortalSelection {
    async_std::task::block_on(async {
        use ashpd::desktop::{ResponseError, file_chooser::SelectedFiles};
        let request = match SelectedFiles::open_file()
            .title("Open project")
            .accept_label("Open")
            .directory(true)
            .multiple(false)
            .modal(true)
            .send()
            .await
        {
            Ok(value) => value,
            Err(_) => return PortalSelection::Unavailable,
        };
        let files = match request.response() {
            Ok(value) => value,
            Err(ashpd::Error::Response(ResponseError::Cancelled)) => {
                return PortalSelection::Canceled;
            }
            Err(ashpd::Error::Response(_)) => return PortalSelection::Denied,
            Err(_) => return PortalSelection::Unavailable,
        };
        let [uri] = files.uris() else {
            return PortalSelection::Unavailable;
        };
        let path = match uri.to_file_path() {
            Ok(value) => value,
            Err(_) => return PortalSelection::Unavailable,
        };
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("directory")
            .to_owned();
        match Dir::open_ambient_dir(path, ambient_authority()) {
            Ok(dir) => PortalSelection::Chosen(Arc::new(dir), name),
            Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
                PortalSelection::Denied
            }
            Err(_) => PortalSelection::Unavailable,
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_pick_directory() -> FilesPickDirectoryResult {
    record_operation(0);
    let initial = store()
        .lock()
        .expect("capability store poisoned")
        .initial
        .clone();
    match initial {
        Some((dir, name)) => chosen(dir, &name, GrantSource::Provisioned),
        None => select_portal(),
    }
}

fn select_portal() -> FilesPickDirectoryResult {
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    let allowed = {
        let mut guard = store().lock().expect("capability store poisoned");
        if !guard.portal_enabled {
            false
        } else if !prompt_is_allowed(
            true,
            guard.chooser_in_flight,
            guard.refusal_until,
            Instant::now(),
        ) {
            guard.selection[5] += 1;
            false
        } else {
            guard.chooser_in_flight = true;
            guard.selection[0] += 1;
            true
        }
    };
    if !allowed {
        return FilesPickDirectoryResult {
            payload: FilesPickDirectoryResultPayload {
                err: ManuallyDrop::new(pick_directory_err(R::AccessDenied)),
            },
            tag: FilesPickDirectoryResultTag::Err,
        };
    }
    let result = portal_directory();
    let mut guard = store().lock().expect("capability store poisoned");
    guard.chooser_in_flight = false;
    match &result {
        PortalSelection::Chosen(..) => guard.selection[1] += 1,
        PortalSelection::Canceled => {
            guard.selection[2] += 1;
            guard.refusal_until = Some(Instant::now() + REFUSAL_COOLDOWN);
        }
        PortalSelection::Denied => {
            guard.selection[3] += 1;
            guard.refusal_until = Some(Instant::now() + REFUSAL_COOLDOWN);
        }
        PortalSelection::Unavailable => guard.selection[4] += 1,
    }
    drop(guard);
    match result {
        PortalSelection::Chosen(dir, name) => chosen(dir, &name, GrantSource::Portal),
        PortalSelection::Canceled => canceled(),
        PortalSelection::Denied => FilesPickDirectoryResult {
            payload: FilesPickDirectoryResultPayload {
                err: ManuallyDrop::new(pick_directory_err(R::AccessDenied)),
            },
            tag: FilesPickDirectoryResultTag::Err,
        },
        PortalSelection::Unavailable => FilesPickDirectoryResult {
            payload: FilesPickDirectoryResultPayload {
                err: ManuallyDrop::new(pick_directory_err(R::Unavailable)),
            },
            tag: FilesPickDirectoryResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_list(cap: *mut u64) -> FilesDirListResult {
    record_operation(1);
    let dir = lookup_state(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let dir = match dir {
        Ok(dir) => dir,
        Err(error) => return FilesDirListResult { payload: FilesDirListResultPayload { err: ManuallyDrop::new(list_directory_err(match error { LookupError::Invalid => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidCapability, LookupError::Revoked => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::Revoked })) }, tag: FilesDirListResultTag::Err },
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
                err: ManuallyDrop::new(list_directory_err(
                    if io.kind() == std::io::ErrorKind::InvalidData {
                        AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidUtf8
                    } else if io.kind() == std::io::ErrorKind::Other {
                        AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::ResourceLimit
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
    record_operation(2);
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let inherited = grant_metadata(cap);
    let dir = lookup_state(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = match dir {
        Err(LookupError::Invalid) => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidCapability),
        Err(LookupError::Revoked) => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::Revoked),
        Ok(_) if !valid_name(&owned_name) => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidName),
        Ok(dir) => dir.open_dir_nofollow(&owned_name).map(Arc::new).map_err(|io| reason(&io)),
    };
    match result {
        Ok(dir) => FilesDirOpenReadDirResult {
            payload: FilesDirOpenReadDirResultPayload {
                ok: ManuallyDrop::new(capability(
                    dir,
                    inherited
                        .map(|(parent, value)| derived_metadata(parent, value))
                        .unwrap_or(GrantMetadata {
                            source: GrantSource::Provisioned,
                            lifetime: GrantLifetime::Session,
                            parent: None,
                            root: 0,
                        }),
                )),
            },
            tag: FilesDirOpenReadDirResultTag::Ok,
        },
        Err(value) => FilesDirOpenReadDirResult {
            payload: FilesDirOpenReadDirResultPayload {
                err: ManuallyDrop::new(open_read_directory_err(value)),
            },
            tag: FilesDirOpenReadDirResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_read(cap: *mut u64, name: RocStr) -> FilesDirReadResult {
    record_operation(3);
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let dir = lookup_state(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| -> Result<Vec<u8>, AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported> {
        let dir = dir.map_err(|error| match error { LookupError::Invalid => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidCapability, LookupError::Revoked => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::Revoked })?;
        if !valid_name(&owned_name) {
            return Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidName);
        }
        let metadata = dir.symlink_metadata(&owned_name).map_err(|io| reason(&io))?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::Unsupported);
        }
        if metadata.len() > MAX_FILE_BYTES {
            return Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::ResourceLimit);
        }
        let mut options = OpenOptions::new();
        options.read(true).follow(FollowSymlinks::No);
        let file = dir.open_with(&owned_name, &options).map_err(|io| reason(&io))?;
        let mut bytes = Vec::with_capacity(metadata.len() as usize);
        file.take(MAX_FILE_BYTES + 1).read_to_end(&mut bytes).map_err(|io| reason(&io))?;
        if bytes.len() as u64 > MAX_FILE_BYTES {
            Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::ResourceLimit)
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
                err: ManuallyDrop::new(read_file_err(value)),
            },
            tag: FilesDirReadResultTag::Err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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

    #[test]
    fn derived_grants_keep_source_and_immediate_parent() {
        let root = GrantMetadata {
            source: GrantSource::Portal,
            lifetime: GrantLifetime::Session,
            parent: None,
            root: 11,
        };
        assert_eq!(
            derived_metadata(7, root),
            GrantMetadata {
                source: GrantSource::Portal,
                lifetime: GrantLifetime::Session,
                parent: Some(7),
                root: 11,
            }
        );
    }

    #[test]
    fn prompt_policy_is_single_flight_and_cooldown_bounded() {
        let now = Instant::now();
        assert!(prompt_is_allowed(true, false, None, now));
        assert!(!prompt_is_allowed(true, true, None, now));
        assert!(!prompt_is_allowed(
            true,
            false,
            Some(now + Duration::from_secs(1)),
            now
        ));
        assert!(prompt_is_allowed(true, false, Some(now), now));
        assert!(!prompt_is_allowed(false, false, None, now));
    }
}
