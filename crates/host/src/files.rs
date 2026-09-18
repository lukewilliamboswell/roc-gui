use crate::grant::{self, Enforcement, Lifetime, Origin, Rights};
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
    operations: [u64; 4],
    selection: [u64; 7],
    portal_enabled: bool,
    /// Provisioned cancellation: the chooser opens and the person dismisses it.
    /// Cancelling produces no authority and is not a failure, so it is its own
    /// provisioning rather than an absent grant.
    chooser_cancels: bool,
    chooser_in_flight: bool,
    refusal_until: Option<Instant>,
    lifecycle: [u64; 6],
}

const REFUSAL_COOLDOWN: Duration = Duration::from_secs(2);

/// What a directory handle may do: read its files, enumerate its children, and
/// derive a child directory. Never write — the only read-write directory this
/// platform hands out is private application storage, which is a different
/// grant of a different kind.
const DIRECTORY_RIGHTS: Rights = Rights::READ.union(Rights::LIST).union(Rights::DERIVE);

/// What a chosen directory is worth as enforcement, and why it is one constant
/// rather than a per-platform answer.
///
/// Both hosts present the choice in a surface the operating system owns — the
/// XDG Desktop Portal on Linux, the window-owned panel on macOS — and both then
/// reach the result through [`open_selected`], which reopens the chosen path
/// with `ambient_authority()`. The portal hands back a URI and this host takes
/// the path, not the descriptor, so on neither platform does the grant carry
/// authority the process did not already hold. That is honest consent and a real
/// record of a real decision; it is not confinement, and recording it as
/// [`Enforcement::ConsentOnly`] is what stops the platform claiming otherwise.
///
/// This becomes [`Enforcement::Brokered`] when the confined-process work lands
/// and the broker returns a descriptor. Nothing in the Roc API changes with it.
const SELECTION_ENFORCEMENT: Enforcement = Enforcement::ConsentOnly;

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
            operations: [0; 4],
            selection: [0; 7],
            portal_enabled: false,
            chooser_cancels: false,
            chooser_in_flight: false,
            refusal_until: None,
            lifecycle: [0; 6],
        })
    })
}

pub fn configure(
    path: Option<&Path>,
    portal_enabled: bool,
    chooser_cancels: bool,
) -> Result<(), String> {
    if chooser_cancels && path.is_some() {
        return Err("a canceled chooser cannot also provision a directory grant".into());
    }
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
    // A provisioned cancellation is a chooser that opens, so the prompt gate
    // and its counters have to see an available chooser.
    guard.portal_enabled = portal_enabled || chooser_cancels;
    guard.chooser_cancels = chooser_cancels;
    guard.chooser_in_flight = false;
    guard.refusal_until = None;
    drop(guard);
    // Configuration replaces this resource's provisioning wholesale. The grants
    // that named the previous configuration did not have their authority taken
    // away; they ceased to exist, which is forgetting rather than revoking.
    grant::forget_kind(grant::Kind::Directory);
    let mut guard = store().lock().expect("capability store poisoned");
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
    let mut snapshot = AccessSnapshot::default();
    for entry in grant::enumerate() {
        if entry.kind != grant::Kind::Directory || entry.parent.is_some() {
            continue;
        }
        if entry.revoked {
            snapshot.revoked += 1;
        } else {
            match entry.origin {
                Origin::TrustedSelection(_) => snapshot.portal_session_read += 1,
                Origin::Provisioned | Origin::Automatic => {
                    snapshot.provisioned_session_read += 1
                }
            }
        }
    }
    snapshot
}

pub fn revoke_all_roots() -> usize {
    store().lock().expect("capability store poisoned").lifecycle[3] += 1;
    // The count is of roots, because a root is what a person revoked; the kernel
    // takes the descendants with it and counts those separately.
    let changed = grant::enumerate()
        .iter()
        .filter(|entry| {
            entry.kind == grant::Kind::Directory && entry.parent.is_none() && !entry.revoked
        })
        .count();
    grant::revoke_kind(grant::Kind::Directory);
    if changed > 0 {
        store().lock().expect("capability store poisoned").lifecycle[4] += 1;
    }
    changed
}

fn record_operation(index: usize) {
    let mut guard = store().lock().expect("capability store poisoned");
    guard.operations[index] = guard.operations[index].saturating_add(1);
}

/// Hand a directory to Roc as an opaque handle, and record the grant that
/// handle is. `parent` is the handle this one was derived from, absent for a
/// root; `origin` is consulted only for a root, because a derived grant inherits
/// how its parent's authority arrived rather than asserting its own.
fn capability(dir: Arc<Dir>, parent: Option<u64>, origin: Origin) -> *mut u64 {
    let mut guard = store().lock().expect("capability store poisoned");
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("directory capability ids exhausted");
    match parent {
        None => guard.lifecycle[0] += 1,
        Some(_) => guard.lifecycle[1] += 1,
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
    crate::register_resource_allocation(crate::resource_domain::FILES, &mut guard.allocations, allocation_base as usize, id);
    guard.lifecycle[2] += 1;
    drop(guard);
    match parent {
        None => grant::record_root(
            grant::Kind::Directory,
            id,
            DIRECTORY_RIGHTS,
            origin,
            Lifetime::Session,
        ),
        Some(parent) => {
            grant::record_derived(
                grant::Kind::Directory,
                id,
                DIRECTORY_RIGHTS,
                (grant::Kind::Directory, parent),
            );
        }
    }
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

/// Every directory operation passes through here, so the kernel's acceptance
/// point is this resource's acceptance point rather than a second rule beside
/// it. Reading is the right every directory operation needs; `open_dir` needs
/// `DERIVE` as well, which [`grant::record_derived`] checks when it builds the
/// child.
fn lookup_state(handle: *mut u64) -> Result<Arc<Dir>, LookupError> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(LookupError::Invalid)?;
    match grant::accept(grant::Kind::Directory, id, Rights::READ) {
        Err(grant::Refusal::Revoked) => {
            store().lock().expect("capability store poisoned").lifecycle[5] += 1;
            Err(LookupError::Revoked)
        }
        Err(_) => Err(LookupError::Invalid),
        Ok(_) => store()
            .lock()
            .map_err(|_| LookupError::Invalid)?
            .dirs
            .get(&id)
            .cloned()
            .ok_or(LookupError::Invalid),
    }
}

fn handle_id(handle: *mut u64) -> Option<u64> {
    unsafe { handle.as_ref().copied() }
}

pub fn route_dealloc(allocation_base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("capability store poisoned");
    let released =
        crate::remove_resource_allocation(&mut guard.allocations, allocation_base as usize);
    if let Some(id) = released {
        guard.dirs.remove(&id);
        guard.lifecycle[2] = guard.lifecycle[2].saturating_sub(1);
    }
    drop(guard);
    // The application stopped holding the handle. That is releasing, not
    // revoking, and the kernel counts the two separately on purpose.
    if let Some(id) = released {
        grant::release(grant::Kind::Directory, id);
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

/// Split one relative, non-escaping path into its ordinary components.
///
/// This is the single place the host decides what a path inside an opened
/// directory may say. An absolute path, an empty path, a path holding a NUL,
/// and any `.` or `..` component are refused here rather than rewritten, so a
/// caller cannot name anything outside the directory it was given. Every
/// directory-relative operation in the host resolves its path through this
/// function; asset stores add no second resolver of their own.
pub(crate) fn relative_components(path: &str) -> Option<Vec<&str>> {
    if path.is_empty() || path.contains('\0') {
        return None;
    }
    let mut parts = Vec::new();
    for component in Path::new(path).components() {
        match component {
            Component::Normal(value) => parts.push(value.to_str()?),
            _ => return None,
        }
    }
    if parts.is_empty() { None } else { Some(parts) }
}

pub(crate) fn valid_name(name: &str) -> bool {
    relative_components(name).is_some_and(|parts| parts.len() == 1)
}

/// Walk into a subdirectory one component at a time, refusing to follow a
/// symbolic link at any step, so no link planted inside a tree can redirect the
/// walk out of it. An empty component list returns the directory itself.
pub(crate) fn open_subdir_nofollow(dir: &Dir, parts: &[&str]) -> std::io::Result<Dir> {
    let mut current = dir.try_clone()?;
    for part in parts {
        current = current.open_dir_nofollow(part)?;
    }
    Ok(current)
}

/// Why a bounded child read was refused. The categories are distinct because
/// every caller reports them as distinct application failures.
pub(crate) enum ChildReadError {
    InvalidName,
    NotFound,
    NotDirectory,
    AccessDenied,
    Unsupported,
    ResourceLimit,
    Io,
}

/// Read one direct ordinary child file of `dir`, never following a symbolic
/// link and never exceeding `max_bytes`. The size is checked against the
/// metadata first and again against what was actually read, so a file that
/// grows between the two answers `ResourceLimit` rather than an unbounded
/// value.
pub(crate) fn read_child_bounded(
    dir: &Dir,
    name: &str,
    max_bytes: u64,
) -> Result<Vec<u8>, ChildReadError> {
    if !valid_name(name) {
        return Err(ChildReadError::InvalidName);
    }
    let metadata = dir.symlink_metadata(name).map_err(|io| match io.kind() {
        std::io::ErrorKind::NotFound => ChildReadError::NotFound,
        std::io::ErrorKind::PermissionDenied => ChildReadError::AccessDenied,
        std::io::ErrorKind::NotADirectory => ChildReadError::NotDirectory,
        _ => ChildReadError::Io,
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(ChildReadError::Unsupported);
    }
    if metadata.len() > max_bytes {
        return Err(ChildReadError::ResourceLimit);
    }
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No);
    let file = dir
        .open_with(name, &options)
        .map_err(|io| match io.kind() {
            std::io::ErrorKind::NotFound => ChildReadError::NotFound,
            std::io::ErrorKind::PermissionDenied => ChildReadError::AccessDenied,
            _ => ChildReadError::Io,
        })?;
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.take(max_bytes + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| ChildReadError::Io)?;
    if bytes.len() as u64 > max_bytes {
        Err(ChildReadError::ResourceLimit)
    } else {
        Ok(bytes)
    }
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
    read_child_bounded(&dir, name, MAX_FILE_BYTES).map_err(|error| match error {
        ChildReadError::InvalidName => BoundedReadError::InvalidName,
        ChildReadError::ResourceLimit => BoundedReadError::ResourceLimit,
        _ => BoundedReadError::Io,
    })
}

fn chosen(dir: Arc<Dir>, name: &str, origin: Origin) -> InternalFilesPickDirectoryResult {
    let directory = capability(dir, None, origin);
    let value = InternalFilesPickDirectoryOkChosen {
        directory,
        name: RocStr::from_str(name, roc_host()),
    };
    InternalFilesPickDirectoryResult {
        payload: InternalFilesPickDirectoryResultPayload {
            ok: ManuallyDrop::new(CanceledOrChosen {
                payload: CanceledOrChosenPayload {
                    chosen: ManuallyDrop::new(value),
                },
                tag: CanceledOrChosenTag::Chosen,
            }),
        },
        tag: InternalFilesPickDirectoryResultTag::Ok,
    }
}

fn canceled() -> InternalFilesPickDirectoryResult {
    InternalFilesPickDirectoryResult {
        payload: InternalFilesPickDirectoryResultPayload {
            ok: ManuallyDrop::new(CanceledOrChosen {
                payload: CanceledOrChosenPayload { canceled: [] },
                tag: CanceledOrChosenTag::Canceled,
            }),
        },
        tag: InternalFilesPickDirectoryResultTag::Ok,
    }
}

enum PortalSelection {
    Chosen(Arc<Dir>, String),
    Canceled,
    Denied,
    Unavailable,
}

/// One outstanding trusted-chooser request. The platform window thread owns the
/// native panel, so a task thread hands it a reply channel and waits.
pub struct ChooserRequest {
    pub reply: std::sync::mpsc::SyncSender<Option<std::path::PathBuf>>,
}

struct ChooserSeam {
    requests: async_channel::Sender<ChooserRequest>,
    window_thread: std::thread::ThreadId,
}

static CHOOSER: OnceLock<Mutex<Option<ChooserSeam>>> = OnceLock::new();

fn chooser() -> &'static Mutex<Option<ChooserSeam>> {
    CHOOSER.get_or_init(|| Mutex::new(None))
}

/// Register the running window as the owner of the native chooser. Called from
/// the window thread, whose identity is recorded so a request made from that
/// same thread reports `Unavailable` instead of waiting for a panel that the
/// waiting thread is the one responsible for showing.
pub fn install_chooser(requests: async_channel::Sender<ChooserRequest>) {
    *chooser().lock().expect("chooser seam poisoned") = Some(ChooserSeam {
        requests,
        window_thread: std::thread::current().id(),
    });
}

fn open_selected(path: std::path::PathBuf) -> PortalSelection {
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
}

/// Ask the running window for a directory through the operating system's own
/// chooser. Used where the host has no portal broker to ask.
#[cfg(not(target_os = "linux"))]
fn native_directory() -> PortalSelection {
    let requests = {
        let guard = chooser().lock().expect("chooser seam poisoned");
        match guard.as_ref() {
            None => return PortalSelection::Unavailable,
            Some(seam) if seam.window_thread == std::thread::current().id() => {
                return PortalSelection::Unavailable;
            }
            Some(seam) => seam.requests.clone(),
        }
    };
    let (reply, answer) = std::sync::mpsc::sync_channel(1);
    if requests.send_blocking(ChooserRequest { reply }).is_err() {
        return PortalSelection::Unavailable;
    }
    match answer.recv() {
        Err(_) => PortalSelection::Unavailable,
        Ok(None) => PortalSelection::Canceled,
        Ok(Some(path)) => open_selected(path),
    }
}

fn chooser_directory() -> PortalSelection {
    #[cfg(target_os = "linux")]
    {
        portal_directory()
    }
    #[cfg(not(target_os = "linux"))]
    {
        native_directory()
    }
}

#[cfg(target_os = "linux")]
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
        open_selected(path)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_pick_directory() -> InternalFilesPickDirectoryResult {
    record_operation(0);
    let initial = store()
        .lock()
        .expect("capability store poisoned")
        .initial
        .clone();
    match initial {
        Some((dir, name)) => chosen(dir, &name, Origin::Provisioned),
        None => select_portal(),
    }
}

fn select_portal() -> InternalFilesPickDirectoryResult {
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
        return InternalFilesPickDirectoryResult {
            payload: InternalFilesPickDirectoryResultPayload {
                err: ManuallyDrop::new(pick_directory_err(R::AccessDenied)),
            },
            tag: InternalFilesPickDirectoryResultTag::Err,
        };
    }
    let cancels = store()
        .lock()
        .expect("capability store poisoned")
        .chooser_cancels;
    let result = if cancels {
        PortalSelection::Canceled
    } else {
        chooser_directory()
    };
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
        PortalSelection::Chosen(dir, name) => {
            chosen(dir, &name, Origin::TrustedSelection(SELECTION_ENFORCEMENT))
        }
        PortalSelection::Canceled => canceled(),
        PortalSelection::Denied => InternalFilesPickDirectoryResult {
            payload: InternalFilesPickDirectoryResultPayload {
                err: ManuallyDrop::new(pick_directory_err(R::AccessDenied)),
            },
            tag: InternalFilesPickDirectoryResultTag::Err,
        },
        PortalSelection::Unavailable => InternalFilesPickDirectoryResult {
            payload: InternalFilesPickDirectoryResultPayload {
                err: ManuallyDrop::new(pick_directory_err(R::Unavailable)),
            },
            tag: InternalFilesPickDirectoryResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_list(cap: *mut u64) -> InternalFilesDirListResult {
    record_operation(1);
    let dir = lookup_state(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let dir = match dir {
        Ok(dir) => dir,
        Err(error) => return InternalFilesDirListResult { payload: InternalFilesDirListResultPayload { err: ManuallyDrop::new(list_directory_err(match error { LookupError::Invalid => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidCapability, LookupError::Revoked => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::Revoked })) }, tag: InternalFilesDirListResultTag::Err },
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
        Ok(values) => InternalFilesDirListResult {
            payload: InternalFilesDirListResultPayload {
                ok: ManuallyDrop::new(unsafe { RocList::from_slice(&values, roc_host()) }),
            },
            tag: InternalFilesDirListResultTag::Ok,
        },
        Err(io) => InternalFilesDirListResult {
            payload: InternalFilesDirListResultPayload {
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
            tag: InternalFilesDirListResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_open_read(
    cap: *mut u64,
    name: RocStr,
) -> InternalFilesDirOpenReadResult {
    record_operation(2);
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let parent = handle_id(cap);
    let dir = lookup_state(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = match dir {
        Err(LookupError::Invalid) => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidCapability),
        Err(LookupError::Revoked) => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::Revoked),
        Ok(_) if !valid_name(&owned_name) => Err(AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidName),
        Ok(dir) => dir.open_dir_nofollow(&owned_name).map(Arc::new).map_err(|io| reason(&io)),
    };
    match result {
        Ok(dir) => InternalFilesDirOpenReadResult {
            payload: InternalFilesDirOpenReadResultPayload {
                // `lookup_state` already accepted the parent, so the handle is
                // live and this child is derived from it. A child with no
                // readable parent handle cannot arise here.
                ok: ManuallyDrop::new(capability(dir, parent, Origin::Provisioned)),
            },
            tag: InternalFilesDirOpenReadResultTag::Ok,
        },
        Err(value) => InternalFilesDirOpenReadResult {
            payload: InternalFilesDirOpenReadResultPayload {
                err: ManuallyDrop::new(open_read_directory_err(value)),
            },
            tag: InternalFilesDirOpenReadResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_read(cap: *mut u64, name: RocStr) -> InternalFilesDirReadResult {
    record_operation(3);
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let dir = lookup_state(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = (|| -> Result<Vec<u8>, AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported> {
        let dir = dir.map_err(|error| match error { LookupError::Invalid => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::InvalidCapability, LookupError::Revoked => AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported::Revoked })?;
        use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
        read_child_bounded(&dir, &owned_name, MAX_FILE_BYTES).map_err(|error| match error {
            ChildReadError::InvalidName => R::InvalidName,
            ChildReadError::NotFound => R::NotFound,
            ChildReadError::NotDirectory => R::NotDirectory,
            ChildReadError::AccessDenied => R::AccessDenied,
            ChildReadError::Unsupported => R::Unsupported,
            ChildReadError::ResourceLimit => R::ResourceLimit,
            ChildReadError::Io => R::Io,
        })
    })();
    match result {
        Ok(bytes) => InternalFilesDirReadResult {
            payload: InternalFilesDirReadResultPayload {
                ok: ManuallyDrop::new(unsafe {
                    RocListWith::<u8, false>::from_slice(&bytes, roc_host())
                }),
            },
            tag: InternalFilesDirReadResultTag::Ok,
        },
        Err(value) => InternalFilesDirReadResult {
            payload: InternalFilesDirReadResultPayload {
                err: ManuallyDrop::new(read_file_err(value)),
            },
            tag: InternalFilesDirReadResultTag::Err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The seam is one process-wide registration, so both of its outcomes are
    /// exercised in one test rather than racing each other.
    #[cfg(not(target_os = "linux"))]
    #[test]
    fn the_native_chooser_answers_a_waiting_task_and_refuses_the_window_thread() {
        let (requests, pending) = async_channel::unbounded();
        install_chooser(requests);
        assert!(matches!(native_directory(), PortalSelection::Unavailable));
        assert!(pending.try_recv().is_err());

        let task = std::thread::spawn(native_directory);
        let deadline = Instant::now() + Duration::from_secs(5);
        let request = loop {
            if let Ok(request) = pending.try_recv() {
                break request;
            }
            assert!(
                Instant::now() < deadline,
                "the waiting task never asked for a chooser"
            );
            std::thread::sleep(Duration::from_millis(5));
        };
        request.reply.send(None).expect("nobody was waiting");
        assert!(matches!(
            task.join().expect("task thread panicked"),
            PortalSelection::Canceled
        ));
        *chooser().lock().expect("chooser seam poisoned") = None;
    }

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
    fn a_directory_grant_reads_lists_and_derives_but_never_writes() {
        assert!(DIRECTORY_RIGHTS.contains(Rights::READ));
        assert!(DIRECTORY_RIGHTS.contains(Rights::LIST));
        assert!(DIRECTORY_RIGHTS.contains(Rights::DERIVE));
        assert!(
            !DIRECTORY_RIGHTS.contains(Rights::WRITE),
            "a chosen project is read-only; private application storage is the \
             read-write grant and it is a different kind"
        );
    }

    #[test]
    fn a_chosen_directory_is_consent_rather_than_confinement() {
        // `open_selected` reopens the chosen path with ambient authority on both
        // platforms, so neither host's chooser hands over authority the process
        // lacked. The platform must not report otherwise.
        assert_eq!(SELECTION_ENFORCEMENT, Enforcement::ConsentOnly);
        assert_eq!(
            Origin::TrustedSelection(SELECTION_ENFORCEMENT).enforcement(),
            Enforcement::ConsentOnly
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
