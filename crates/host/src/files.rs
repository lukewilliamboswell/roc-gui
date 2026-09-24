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
    path::{Component, Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, Instant},
};

const MAX_ENTRIES: usize = 10_000;
const MAX_NAME_BYTES: usize = 4 * 1024 * 1024;
const MAX_FILE_BYTES: u64 = 64 * 1024 * 1024;
struct Store {
    next: u64,
    initial: Option<(Arc<Dir>, String, PathBuf)>,
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

pub(crate) const REFUSAL_COOLDOWN: Duration = Duration::from_secs(2);

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
pub(crate) const SELECTION_ENFORCEMENT: Enforcement = Enforcement::ConsentOnly;

pub(crate) fn prompt_is_allowed(
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
            let resolved = std::fs::canonicalize(path)
                .map_err(|error| format!("cannot grant directory: {error}"))?;
            Some((Arc::new(dir), name, resolved))
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
        if entry.kind() != grant::Kind::Directory || !entry.is_root() {
            continue;
        }
        if entry.is_revoked() {
            snapshot.revoked += 1;
        } else {
            match entry.origin() {
                Origin::TrustedSelection(_) | Origin::Dropped(_) => {
                    snapshot.portal_session_read += 1
                }
                Origin::Provisioned | Origin::Automatic => snapshot.provisioned_session_read += 1,
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
            entry.kind() == grant::Kind::Directory && entry.is_root() && !entry.is_revoked()
        })
        .count();
    grant::revoke_kind(grant::Kind::Directory);
    // A chosen file is withdrawn by the same seam. It keeps its own counters,
    // so the directory lifecycle still counts only folders.
    crate::document::revoke_all_roots();
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
/// A root's place, when it has one, is noted for the recent list; `lifetime`
/// is a root's own, as a derived grant shares its parent's.
fn capability(
    dir: Arc<Dir>,
    parent: Option<grant::Grant>,
    origin: Origin,
    place: Option<(&Path, Lifetime)>,
) -> *mut u64 {
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
    crate::register_resource_allocation(
        crate::resource_domain::FILES,
        &mut guard.allocations,
        allocation_base as usize,
        id,
    );
    guard.lifecycle[2] += 1;
    drop(guard);
    match parent {
        None => {
            let lifetime = place.map_or(Lifetime::Session, |(_, lifetime)| lifetime);
            grant::record_root(
                grant::Kind::Directory,
                id,
                DIRECTORY_RIGHTS,
                origin,
                lifetime,
            );
            if let Some((path, _)) = place {
                crate::recents::note_source(
                    grant::GrantId::new(grant::Kind::Directory, id),
                    crate::recents::EntryKind::Directory,
                    path,
                );
            }
        }
        Some(parent) => {
            grant::record_descendant(grant::Kind::Directory, id, DIRECTORY_RIGHTS, parent);
        }
    }
    handle
}

pub(crate) fn lookup(handle: *mut u64) -> Option<Arc<Dir>> {
    lookup_state(handle).ok()
}

/// The directory and the grant it was accepted against, for the platform's own
/// modules that derive something narrower from a directory. `Sqlite` takes a
/// snapshot this way, which is how a revoked project reaches a database opened
/// from it.
pub(crate) fn lookup_accepted(handle: *mut u64) -> Option<(Arc<Dir>, grant::Grant)> {
    accepted(handle).ok()
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
    accepted(handle).map(|(dir, _)| dir)
}

/// The directory and the grant it was accepted against. The grant is what a
/// child is derived from: `open_dir` decrefs the parent handle before the child
/// exists, so looking the parent up again could find it already released.
fn accepted(handle: *mut u64) -> Result<(Arc<Dir>, grant::Grant), LookupError> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(LookupError::Invalid)?;
    match grant::accept(grant::Kind::Directory, id, Rights::READ) {
        Err(grant::Refusal::Revoked) => {
            store().lock().expect("capability store poisoned").lifecycle[5] += 1;
            Err(LookupError::Revoked)
        }
        Err(_) => Err(LookupError::Invalid),
        Ok(entry) => store()
            .lock()
            .map_err(|_| LookupError::Invalid)?
            .dirs
            .get(&id)
            .cloned()
            .map(|dir| (dir, entry))
            .ok_or(LookupError::Invalid),
    }
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
        crate::recents::release_source(grant::GrantId::new(grant::Kind::Directory, id));
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

pub(crate) type FileReason = AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported;
pub(crate) type FileErr = InternalFilesPickDirectoryErr;
type FileErrPayload = InternalFilesPickDirectoryErrPayload;
type FileErrTag = InternalFilesPickDirectoryErrTag;

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

pub(crate) fn read_file_err(reason: FileReason) -> FileErr {
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

/// The largest file the host hashes. A hash streams the file and holds none of
/// it, so the bound is on the time one task may spend rather than on memory.
pub(crate) const MAX_HASH_BYTES: u64 = 1024 * 1024 * 1024;

/// Files hashed, hashes refused, and bytes hashed, in that order.
static HASHES: [std::sync::atomic::AtomicU64; 3] = [
    std::sync::atomic::AtomicU64::new(0),
    std::sync::atomic::AtomicU64::new(0),
    std::sync::atomic::AtomicU64::new(0),
];

/// The hash owner's totals: files hashed, hashes refused, and bytes hashed.
pub fn hash_counters() -> [u64; 3] {
    [0, 1, 2].map(|index| HASHES[index].load(std::sync::atomic::Ordering::Relaxed))
}

/// Count one hash's outcome where it was decided.
pub(crate) fn note_hash(outcome: &Result<(String, u64), ChildReadError>) {
    use std::sync::atomic::Ordering::Relaxed;
    match outcome {
        Ok((_, bytes)) => {
            HASHES[0].fetch_add(1, Relaxed);
            HASHES[2].fetch_add(*bytes, Relaxed);
        }
        Err(_) => {
            HASHES[1].fetch_add(1, Relaxed);
        }
    }
}

/// Count a hash refused before any file was reached.
pub(crate) fn note_hash_refused() {
    HASHES[1].fetch_add(1, std::sync::atomic::Ordering::Relaxed);
}

/// The SHA-256 digest of one direct ordinary child file of `dir`, as lowercase
/// hexadecimal, and the number of bytes hashed. It follows no link, streams
/// the file in fixed chunks, and answers `ResourceLimit` for a file longer
/// than `max_bytes`, whether its metadata says so or it grows while read.
pub(crate) fn hash_child_bounded(
    dir: &Dir,
    name: &str,
    max_bytes: u64,
) -> Result<(String, u64), ChildReadError> {
    use sha2::{Digest, Sha256};
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
    let mut limited = file.take(max_bytes + 1);
    let mut hash = Sha256::new();
    let mut buffer = vec![0u8; 64 * 1024];
    let mut total = 0u64;
    loop {
        let read = limited.read(&mut buffer).map_err(|_| ChildReadError::Io)?;
        if read == 0 {
            break;
        }
        total += read as u64;
        if total > max_bytes {
            return Err(ChildReadError::ResourceLimit);
        }
        hash.update(&buffer[..read]);
    }
    Ok((format!("{:x}", hash.finalize()), total))
}

/// The hosted answer to a hash: the digest, or the operation-tagged failure.
pub(crate) fn hash_result(
    outcome: Result<String, AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported>,
) -> InternalFilesDirSha256Result {
    match outcome {
        Ok(digest) => InternalFilesDirSha256Result {
            payload: InternalFilesDirSha256ResultPayload {
                ok: ManuallyDrop::new(RocStr::from_str(&digest, roc_host())),
            },
            tag: InternalFilesDirSha256ResultTag::Ok,
        },
        Err(reason) => InternalFilesDirSha256Result {
            payload: InternalFilesDirSha256ResultPayload {
                err: ManuallyDrop::new(read_file_err(reason)),
            },
            tag: InternalFilesDirSha256ResultTag::Err,
        },
    }
}

/// A child read's failure, spelled as the host exchanges it.
pub(crate) fn child_reason(
    error: ChildReadError,
) -> AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported{
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    match error {
        ChildReadError::InvalidName => R::InvalidName,
        ChildReadError::NotFound => R::NotFound,
        ChildReadError::NotDirectory => R::NotDirectory,
        ChildReadError::AccessDenied => R::AccessDenied,
        ChildReadError::Unsupported => R::Unsupported,
        ChildReadError::ResourceLimit => R::ResourceLimit,
        ChildReadError::Io => R::Io,
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

fn chosen(
    dir: Arc<Dir>,
    name: &str,
    path: &Path,
    origin: Origin,
) -> InternalFilesPickDirectoryResult {
    let directory = capability(dir, None, origin, Some((path, Lifetime::Session)));
    let value = InternalFilesPickDirectoryOkChosen {
        directory,
        name: RocStr::from_str(name, roc_host()),
    };
    InternalFilesPickDirectoryResult {
        payload: InternalFilesPickDirectoryResultPayload {
            ok: ManuallyDrop::new(InternalFilesPickDirectoryOk {
                payload: InternalFilesPickDirectoryOkPayload {
                    chosen: ManuallyDrop::new(value),
                },
                tag: InternalFilesPickDirectoryOkTag::Chosen,
            }),
        },
        tag: InternalFilesPickDirectoryResultTag::Ok,
    }
}

fn canceled() -> InternalFilesPickDirectoryResult {
    InternalFilesPickDirectoryResult {
        payload: InternalFilesPickDirectoryResultPayload {
            ok: ManuallyDrop::new(InternalFilesPickDirectoryOk {
                payload: InternalFilesPickDirectoryOkPayload { canceled: [] },
                tag: InternalFilesPickDirectoryOkTag::Canceled,
            }),
        },
        tag: InternalFilesPickDirectoryResultTag::Ok,
    }
}

enum PortalSelection {
    Chosen(Arc<Dir>, String, PathBuf),
    Canceled,
    Denied,
    Unavailable,
}

/// One outstanding trusted-chooser request. The platform window thread owns the
/// native panel, so a task thread hands it a reply channel and waits.
pub struct ChooserRequest {
    /// A folder chooser when set, otherwise a chooser of one file.
    pub directories: bool,
    pub reply: std::sync::mpsc::SyncSender<Option<std::path::PathBuf>>,
}

struct ChooserSeam {
    // Retain the sender for the application lifetime, including Linux where
    // the portal handles selections instead of reading this channel.
    #[cfg_attr(target_os = "linux", expect(dead_code))]
    requests: async_channel::Sender<ChooserRequest>,
    #[cfg(not(target_os = "linux"))]
    window_thread: std::thread::ThreadId,
}

static CHOOSER: OnceLock<Mutex<Option<Arc<ChooserSeam>>>> = OnceLock::new();

fn chooser() -> &'static Mutex<Option<Arc<ChooserSeam>>> {
    CHOOSER.get_or_init(|| Mutex::new(None))
}

/// Owns one application's registration with the process-level chooser route.
///
/// The route itself must be process-visible because Roc tasks can request a
/// directory from worker threads. Its channel, however, belongs to the GPUI
/// application that receives those requests. Keeping a second strong reference
/// here ensures that installing the next application cannot drop the previous
/// application's sender, and therefore wake its GPUI task, on the next
/// application's scheduler thread.
pub struct ChooserRegistration {
    seam: Arc<ChooserSeam>,
}

impl Drop for ChooserRegistration {
    fn drop(&mut self) {
        let active = {
            let mut chooser = chooser().lock().expect("chooser seam poisoned");
            if chooser
                .as_ref()
                .is_some_and(|active| Arc::ptr_eq(active, &self.seam))
            {
                chooser.take()
            } else {
                None
            }
        };
        // Drop the process route while the application-owned reference still
        // exists. `self.seam`, and with it the final sender, is then dropped on
        // the application thread that owns the receiving GPUI task.
        drop(active);
    }
}

/// Register the running window as the owner of the native chooser. Called from
/// the window thread, whose identity is recorded so a request made from that
/// same thread reports `Unavailable` instead of waiting for a panel that the
/// waiting thread is the one responsible for showing.
pub fn install_chooser(requests: async_channel::Sender<ChooserRequest>) -> ChooserRegistration {
    let seam = Arc::new(ChooserSeam {
        requests,
        #[cfg(not(target_os = "linux"))]
        window_thread: std::thread::current().id(),
    });
    *chooser().lock().expect("chooser seam poisoned") = Some(seam.clone());
    ChooserRegistration { seam }
}

fn open_selected(path: std::path::PathBuf) -> PortalSelection {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("directory")
        .to_owned();
    let resolved = match std::fs::canonicalize(&path) {
        Ok(resolved) => resolved,
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
            return PortalSelection::Denied;
        }
        Err(_) => return PortalSelection::Unavailable,
    };
    match Dir::open_ambient_dir(&resolved, ambient_authority()) {
        Ok(dir) => PortalSelection::Chosen(Arc::new(dir), name, resolved),
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
            PortalSelection::Denied
        }
        Err(_) => PortalSelection::Unavailable,
    }
}

/// What the window's native chooser answered.
#[cfg(not(target_os = "linux"))]
pub(crate) enum NativeAnswer {
    Chosen(std::path::PathBuf),
    Canceled,
    Unavailable,
}

/// Ask the running window for a folder, or for one file, through the operating
/// system's own chooser. Used where the host has no portal broker to ask.
#[cfg(not(target_os = "linux"))]
pub(crate) fn native_path(directories: bool) -> NativeAnswer {
    let requests = {
        let guard = chooser().lock().expect("chooser seam poisoned");
        match guard.as_ref() {
            None => return NativeAnswer::Unavailable,
            Some(seam) if seam.window_thread == std::thread::current().id() => {
                return NativeAnswer::Unavailable;
            }
            Some(seam) => seam.requests.clone(),
        }
    };
    let (reply, answer) = std::sync::mpsc::sync_channel(1);
    if requests
        .send_blocking(ChooserRequest { directories, reply })
        .is_err()
    {
        return NativeAnswer::Unavailable;
    }
    match answer.recv() {
        Err(_) => NativeAnswer::Unavailable,
        Ok(None) => NativeAnswer::Canceled,
        Ok(Some(path)) => NativeAnswer::Chosen(path),
    }
}

#[cfg(not(target_os = "linux"))]
fn native_directory() -> PortalSelection {
    match native_path(true) {
        NativeAnswer::Unavailable => PortalSelection::Unavailable,
        NativeAnswer::Canceled => PortalSelection::Canceled,
        NativeAnswer::Chosen(path) => open_selected(path),
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
        Some((dir, name, path)) => chosen(dir, &name, &path, Origin::Provisioned),
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
        PortalSelection::Chosen(dir, name, path) => chosen(
            dir,
            &name,
            &path,
            Origin::TrustedSelection(SELECTION_ENFORCEMENT),
        ),
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
    let opened = accepted(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let parent = opened.as_ref().ok().map(|(_, entry)| *entry);
    let result = match opened.map(|(dir, _)| dir) {
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
                ok: ManuallyDrop::new(capability(dir, parent, Origin::Provisioned, None)),
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

/// Hash one direct ordinary child of a granted directory. A revoked or
/// invalid handle is refused like a read.
#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_sha256(
    cap: *mut u64,
    name: RocStr,
) -> InternalFilesDirSha256Result {
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let dir = lookup_state(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let outcome = match dir {
        Err(LookupError::Invalid) => {
            note_hash_refused();
            Err(R::InvalidCapability)
        }
        Err(LookupError::Revoked) => {
            note_hash_refused();
            Err(R::Revoked)
        }
        Ok(dir) => {
            let hashed = hash_child_bounded(&dir, &owned_name, MAX_HASH_BYTES);
            note_hash(&hashed);
            hashed.map(|(digest, _)| digest).map_err(child_reason)
        }
    };
    hash_result(outcome)
}

/// Remember the chosen folder `cap` names in the recent list.
#[unsafe(no_mangle)]
pub extern "C" fn roc_files_remember_directory(cap: *mut u64) -> u8 {
    let id = unsafe { cap.as_ref().copied() };
    unsafe { decref_box(cap as RocBox, roc_host()) };
    match id {
        None => crate::recents::Unavailable::Revoked as u8,
        Some(id) => match crate::recents::remember(grant::Kind::Directory, id) {
            Ok(()) => 0,
            Err(reason) => reason as u8,
        },
    }
}

/// Reopen a remembered folder as a new grant, after the recent list checks it
/// is still the folder that was remembered.
#[unsafe(no_mangle)]
pub extern "C" fn roc_files_reopen_directory(key: u64) -> InternalFilesReopenDirectoryResult {
    use crate::recents::{EntryKind, Unavailable};
    let refused = |reason: Unavailable| InternalFilesReopenDirectoryResult {
        payload: InternalFilesReopenDirectoryResultPayload {
            err: ManuallyDrop::new(AnonStruct45708337b22b1f51 { code: reason as u8 }),
        },
        tag: InternalFilesReopenDirectoryResultTag::Err,
    };
    let (path, origin) = match crate::recents::reopen(key, EntryKind::Directory) {
        Ok(found) => found,
        Err(reason) => return refused(reason),
    };
    let dir = match Dir::open_ambient_dir(&path, ambient_authority()) {
        Ok(dir) => Arc::new(dir),
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
            return refused(Unavailable::AccessDenied);
        }
        Err(_) => return refused(Unavailable::Missing),
    };
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("directory")
        .to_owned();
    let directory = capability(dir, None, origin, Some((&path, Lifetime::Remembered)));
    let id = unsafe { directory.as_ref().copied() }.expect("a new handle holds its id");
    crate::recents::reopened(
        key,
        grant::GrantId::new(grant::Kind::Directory, id),
        EntryKind::Directory,
        &path,
    );
    InternalFilesReopenDirectoryResult {
        payload: InternalFilesReopenDirectoryResultPayload {
            ok: ManuallyDrop::new(AnonStruct4869dafad3498788 {
                directory,
                name: RocStr::from_str(&name, roc_host()),
            }),
        },
        tag: InternalFilesReopenDirectoryResultTag::Ok,
    }
}

/// Watch a granted directory's direct children. The watch is derived from the
/// directory grant, so withdrawing the folder ends it.
#[unsafe(no_mangle)]
pub extern "C" fn roc_files_dir_watch(cap: *mut u64) -> InternalFilesDirWatchResult {
    let accepted = accepted(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result = match accepted {
        Err(LookupError::Revoked) => Err((6, "directory authority was withdrawn")),
        Err(LookupError::Invalid) => Err((1, "invalid directory capability")),
        Ok((dir, parent)) => match crate::watch::descriptor_path(&dir) {
            None => Err((9, "watching is not supported on this platform")),
            Some(path) => crate::watch::start(&path, crate::watch::Target::Directory, parent)
                .map_err(|refusal| match refusal {
                    crate::watch::Refusal::Revoked => (6, "directory authority was withdrawn"),
                    crate::watch::Refusal::ResourceLimit => (4, "no watch is left to give"),
                    crate::watch::Refusal::Unsupported => {
                        (9, "watching is not supported on this platform")
                    }
                    crate::watch::Refusal::Io => (3, "the directory could not be watched"),
                }),
        },
    };
    match result {
        Ok(handle) => InternalFilesDirWatchResult {
            payload: InternalFilesDirWatchResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: InternalFilesDirWatchResultTag::Ok,
        },
        Err((code, message)) => InternalFilesDirWatchResult {
            payload: InternalFilesDirWatchResultPayload {
                err: ManuallyDrop::new(InternalFilesDirWatchErr {
                    code,
                    message: RocStr::from_str(message, roc_host()),
                }),
            },
            tag: InternalFilesDirWatchResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_watch_next(handle: *mut u64) -> InternalFilesWatchNext {
    let report = crate::watch::next(handle);
    let names: Vec<RocStr> = report
        .names
        .iter()
        .map(|name| RocStr::from_str(name, roc_host()))
        .collect();
    InternalFilesWatchNext {
        names: unsafe { RocList::from_slice(&names, roc_host()) },
        code: report.code,
        overflowed: report.overflowed,
        replaced: report.replaced,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_watch_cancel(handle: *mut u64) -> bool {
    crate::watch::cancel(handle)
}

/// The disposable copy a specification was granted, and the application
/// directory its `replace-file` sources are named relative to.
static PRIVATE_COPY: Mutex<Option<(PathBuf, Option<PathBuf>)>> = Mutex::new(None);

/// Record that the granted directory is a disposable copy. Only then may a
/// `replace-file` step change it.
pub fn set_private_copy(directory: Option<PathBuf>, application: Option<PathBuf>) {
    *PRIVATE_COPY
        .lock()
        .unwrap_or_else(|error| error.into_inner()) =
        directory.map(|directory| (directory, application));
}

/// Remove one direct child of the disposable directory grant, as a person
/// deleting a file does.
pub fn remove_in_private_copy(name: &str) -> Result<(), String> {
    let held = PRIVATE_COPY
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone();
    let Some((directory, _)) = held else {
        return Err("remove-file requires a disposable directory grant".into());
    };
    if !valid_name(name) {
        return Err("remove-file names one direct child".into());
    }
    std::fs::remove_file(directory.join(name))
        .map_err(|error| format!("cannot remove {name}: {error}"))
}

/// Replace one direct child of the disposable directory grant with a copy of
/// `source`, as a person moving a new file into place does: the copy is
/// written beside the directory, never inside it, and renamed over the child in
/// one step, so what the application sees is one name bound to a new file.
pub fn replace_in_private_copy(name: &str, source: &str) -> Result<(), String> {
    let held = PRIVATE_COPY
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone();
    let Some((directory, application)) = held else {
        return Err("replace-file requires a disposable directory grant".into());
    };
    if !valid_name(name) {
        return Err("replace-file names one direct child".into());
    }
    let application =
        application.ok_or_else(|| "replace-file has no application directory".to_string())?;
    let source = crate::resolve_grant_path(&application, source)?;
    let staging_root = directory
        .parent()
        .ok_or_else(|| "the disposable directory has no parent to stage in".to_string())?;
    let staging = staging_root.join(format!(".replace-{}-{name}", std::process::id()));
    std::fs::copy(&source, &staging)
        .map_err(|error| format!("cannot stage {}: {error}", source.display()))?;
    std::fs::rename(&staging, directory.join(name)).map_err(|error| {
        let _ = std::fs::remove_file(&staging);
        format!("cannot replace {name}: {error}")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The chooser seam is one process-wide registration; every test that
    /// installs a route holds this so none observes another's.
    static SEAM: Mutex<()> = Mutex::new(());

    /// The seam is one process-wide registration, so both of its outcomes are
    /// exercised in one test rather than racing each other.
    #[cfg(not(target_os = "linux"))]
    #[test]
    fn the_native_chooser_answers_a_waiting_task_and_refuses_the_window_thread() {
        let _seam = SEAM.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let (requests, pending) = async_channel::unbounded();
        let registration = install_chooser(requests);
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
        drop(registration);
        assert!(chooser().lock().expect("chooser seam poisoned").is_none());
    }

    #[test]
    fn replacing_a_chooser_route_does_not_close_the_previous_application_channel() {
        let _seam = SEAM.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let (first_requests, first_pending) = async_channel::unbounded();
        let first = install_chooser(first_requests);
        let (second_requests, _second_pending) = async_channel::unbounded();
        let second = install_chooser(second_requests);

        assert!(!first_pending.is_closed());
        drop(first);
        assert!(first_pending.is_closed());

        drop(second);
        assert!(chooser().lock().expect("chooser seam poisoned").is_none());
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
    fn a_hash_streams_one_child_and_refuses_links_and_oversized_files() {
        let root = std::env::temp_dir().join(format!("roc-gui-hash-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("inner")).unwrap();
        std::fs::write(root.join("spec.scm"), b"abc").unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(root.join("spec.scm"), root.join("link.scm")).unwrap();
        let dir = Dir::open_ambient_dir(&root, ambient_authority()).unwrap();
        let (digest, bytes) = hash_child_bounded(&dir, "spec.scm", MAX_HASH_BYTES)
            .ok()
            .unwrap();
        assert_eq!(
            digest,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(bytes, 3);
        assert!(matches!(
            hash_child_bounded(&dir, "spec.scm", 2),
            Err(ChildReadError::ResourceLimit)
        ));
        assert!(matches!(
            hash_child_bounded(&dir, "inner", MAX_HASH_BYTES),
            Err(ChildReadError::Unsupported)
        ));
        #[cfg(unix)]
        assert!(matches!(
            hash_child_bounded(&dir, "link.scm", MAX_HASH_BYTES),
            Err(ChildReadError::Unsupported)
        ));
        assert!(matches!(
            hash_child_bounded(&dir, "../spec.scm", MAX_HASH_BYTES),
            Err(ChildReadError::InvalidName)
        ));
        assert!(matches!(
            hash_child_bounded(&dir, "missing.scm", MAX_HASH_BYTES),
            Err(ChildReadError::NotFound)
        ));
        let _ = std::fs::remove_dir_all(&root);
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
