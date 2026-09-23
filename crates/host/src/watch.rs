//! Change notification for granted directories and databases (P8).
//!
//! A watch is derived from the grant it observes — a directory handle, or a
//! database connection opened from a folder or a file — and is recorded in the
//! grant registry as [`grant::Kind::Watch`], so withdrawing that grant ends the
//! watch at the same moment it ends everything else derived from it. Releasing
//! what it watches ends it too: a watch of a connection nobody holds reports
//! nothing anybody can read.
//!
//! A watch is a pull subscription with the shape of `Timer`: the application
//! waits for the next change in a task, and exactly one wait may be outstanding.
//! Changes are *coalesced*, never queued. A watch holds the set of names that
//! changed since the last wait returned, bounded by [`MAX_NAMES`], and whether
//! any of them was bound to a different file. A writer appending a thousand
//! transactions while nobody waits costs one name, so a watch is bounded however
//! fast its files are written, and the next wait still reports that they were.
//! Past the bound, or when the kernel's own queue overflowed, the wait says the
//! names are incomplete instead of guessing them.
//!
//! A wait returns once writing has paused for [`SETTLE`], or at most
//! [`SETTLE_LIMIT`] after the first change it reports. A reader woken on the
//! first `write` of a SQLite commit would otherwise race the writer's update of
//! the log's index and read the transaction before the one that woke it.
//!
//! On Linux one thread owns one inotify descriptor for every watch. A database
//! is watched through the *directory* that holds it rather than through its
//! file, because renaming another file over it changes what the name refers
//! to, and only the directory sees that. Watches of one directory share its
//! inotify watch descriptor, which is removed with the last of them.
//!
//! inotify is used directly through `libc`, already a dependency of this host,
//! rather than through the `notify` crate: the watch needs four system calls
//! and one read loop, and a crate that abstracts every platform's notifier
//! behind a callback thread would add a dependency tree and a second thread per
//! watcher to express less than this does.

use crate::grant::{self, Rights};
use crate::roc_host;
use crate::roc_platform_abi::*;
use std::{
    collections::{BTreeSet, HashMap},
    path::{Path, PathBuf},
    sync::{Arc, Condvar, Mutex, OnceLock},
    time::{Duration, Instant},
};

/// The most watches the process may hold at once. inotify has its own
/// per-user limit, which reaches the application as `ResourceLimit` too.
const MAX_WATCHES: usize = 64;
/// The most names one wait reports. Beyond it the wait reports that its names
/// are incomplete.
pub const MAX_NAMES: usize = 256;
/// A wait reports a change once writing has paused this long...
const SETTLE: Duration = Duration::from_millis(10);
/// ...or this long after the first change it reports, whichever is first, so a
/// writer that never pauses is still reported.
const SETTLE_LIMIT: Duration = Duration::from_millis(100);
/// How often the watcher thread asks whether a watched grant was withdrawn or
/// released.
const LIVENESS_POLL: Duration = Duration::from_millis(50);

/// What a watch may do: observe what it was derived from. It derives nothing.
const WATCH_RIGHTS: Rights = Rights::READ;

/// The answers `next` gives, as the platform's `Files.Change` decodes them.
pub const CHANGED: u8 = 0;
pub const CANCELED: u8 = 2;
pub const REVOKED: u8 = 3;
pub const GONE: u8 = 4;

/// Why a watch could not be started. Each caller maps these onto its own
/// family's portable reasons.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    Io,
    ResourceLimit,
    Revoked,
    Unsupported,
}

/// What a watch reports.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Target {
    /// Any direct child of the directory created, removed, renamed, or written.
    Directory,
    /// One database: its file and its write-ahead log.
    Database { name: String },
}

/// What one event means for one watch.
#[derive(Debug, PartialEq, Eq)]
enum Effect {
    Nothing,
    /// A name changed; `rebound` when it may now refer to another file.
    Named {
        name: String,
        rebound: bool,
    },
}

impl Target {
    fn effect(&self, child: &str, mask: u32) -> Effect {
        let rebound = mask & sys::NAME_CHANGED != 0;
        let written = mask & sys::WRITTEN != 0;
        match self {
            Self::Directory if rebound || written => Effect::Named {
                name: child.to_owned(),
                rebound,
            },
            Self::Directory => Effect::Nothing,
            Self::Database { name } if child == name && (rebound || written) => Effect::Named {
                name: name.clone(),
                rebound,
            },
            // Only a write to the log is a commit. A reader creates the log
            // and its index beside a database it opens, and must not wake
            // itself by doing so.
            Self::Database { name }
                if written && child.strip_prefix(name.as_str()) == Some("-wal") =>
            {
                Effect::Named {
                    name: name.clone(),
                    rebound: false,
                }
            }
            Self::Database { .. } => Effect::Nothing,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum End {
    Canceled,
    Revoked,
    Gone,
}

struct Watch {
    target: Target,
    descriptor: i32,
    /// The grant this watch was derived from, which must stay held.
    parent: (grant::Kind, u64),
    state: Mutex<State>,
    wake: Condvar,
}

#[derive(Default)]
struct State {
    names: BTreeSet<String>,
    rebound: bool,
    overflowed: bool,
    first: Option<Instant>,
    last: Option<Instant>,
    waiting: bool,
    ended: Option<End>,
}

impl State {
    fn pending(&self) -> bool {
        !self.names.is_empty() || self.overflowed
    }
}

/// One wait's answer.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Report {
    pub code: u8,
    pub names: Vec<String>,
    pub replaced: bool,
    pub overflowed: bool,
}

impl Report {
    fn ended(code: u8) -> Self {
        Self {
            code,
            ..Self::default()
        }
    }
}

struct Store {
    next: u64,
    watches: HashMap<u64, Arc<Watch>>,
    allocations: HashMap<usize, u64>,
    /// Watch ids by the inotify descriptor they share.
    by_descriptor: HashMap<i32, Vec<u64>>,
    notifier: Option<i32>,
    counters: [u64; 4],
}

/// Indices into the counters, which are reported in this order.
const STARTED: usize = 0;
const CHANGES: usize = 1;
const CANCELS: usize = 2;
const REVOCATIONS: usize = 3;

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            watches: HashMap::new(),
            allocations: HashMap::new(),
            by_descriptor: HashMap::new(),
            notifier: None,
            counters: [0; 4],
        })
    })
}

fn with<T>(act: impl FnOnce(&mut Store) -> T) -> T {
    act(&mut store().lock().expect("watch store poisoned"))
}

/// Forget the previous lifecycle's counters. Live watches belong to handles
/// the previous application held; they end as those handles are released.
pub fn configure() {
    with(|store| store.counters = [0; 4]);
    grant::forget_kind(grant::Kind::Watch);
}

/// Started, changes delivered, cancelled, and ended by revocation, in that
/// order, then the watches the application is holding.
pub fn counters() -> [u64; 5] {
    with(|store| {
        let [started, changes, cancels, revocations] = store.counters;
        [
            started,
            changes,
            cancels,
            revocations,
            store.watches.len() as u64,
        ]
    })
}

/// Start watching `directory` for `target`, derived from `parent`. The
/// directory is named by a path the host resolved from a descriptor or a
/// connection it holds; no path reaches here from an application.
pub fn start(directory: &Path, target: Target, parent: grant::Grant) -> Result<*mut u64, Refusal> {
    if grant::is_revoked(parent.kind(), parent.number()) {
        return Err(Refusal::Revoked);
    }
    let mut guard = store().lock().expect("watch store poisoned");
    if guard.watches.len() >= MAX_WATCHES {
        return Err(Refusal::ResourceLimit);
    }
    let notifier = match guard.notifier {
        Some(fd) => fd,
        None => {
            let fd = sys::open()?;
            std::thread::Builder::new()
                .name("roc-gui-watch".into())
                .spawn(move || watch_loop(fd))
                .map_err(|_| Refusal::Io)?;
            guard.notifier = Some(fd);
            fd
        }
    };
    let descriptor = sys::add(notifier, directory)?;
    let id = guard.next;
    guard.next = guard.next.checked_add(1).expect("watch ids exhausted");
    guard.watches.insert(
        id,
        Arc::new(Watch {
            target,
            descriptor,
            parent: (parent.kind(), parent.number()),
            state: Mutex::new(State::default()),
            wake: Condvar::new(),
        }),
    );
    guard.by_descriptor.entry(descriptor).or_default().push(id);
    guard.counters[STARTED] += 1;
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
    crate::register_resource_allocation(
        crate::resource_domain::WATCH,
        &mut guard.allocations,
        base as usize,
        id,
    );
    drop(guard);
    if !grant::record_descendant(grant::Kind::Watch, id, WATCH_RIGHTS, parent) {
        // The parent was revoked between the check above and now. The handle
        // exists, so it ends as revoked rather than disappearing.
        if let Some(watch) = with(|store| store.watches.get(&id).cloned())
            && end(&watch, End::Revoked)
        {
            with(|store| store.counters[REVOCATIONS] += 1);
        }
    }
    Ok(handle)
}

fn lookup(handle: *mut u64) -> Option<(u64, Arc<Watch>)> {
    let id = unsafe { handle.as_ref().copied()? };
    with(|store| store.watches.get(&id).cloned()).map(|watch| (id, watch))
}

/// Mark a watch ended and wake its waiter. The first end is the one reported.
fn end(watch: &Watch, why: End) -> bool {
    let mut state = watch.state.lock().expect("watch state poisoned");
    if state.ended.is_some() {
        return false;
    }
    state.ended = Some(why);
    watch.wake.notify_all();
    true
}

fn code(why: End) -> u8 {
    match why {
        End::Canceled => CANCELED,
        End::Revoked => REVOKED,
        End::Gone => GONE,
    }
}

/// Wait for the next change. Consumes one reference to the handle.
pub fn next(handle: *mut u64) -> Report {
    let found = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some((id, watch)) = found else {
        return Report::ended(CANCELED);
    };
    end_if_withdrawn(id, &watch);
    let mut state = watch.state.lock().expect("watch state poisoned");
    if let Some(why) = state.ended {
        return Report::ended(code(why));
    }
    // One wait at a time. A second concurrent wait is answered at once and
    // leaves the first, and the watch, as they were.
    if state.waiting {
        return Report::ended(CANCELED);
    }
    state.waiting = true;
    let report = loop {
        if let Some(why) = state.ended {
            break Report::ended(code(why));
        }
        let now = Instant::now();
        if state.pending() {
            let quiet = state.last.is_some_and(|last| now >= last + SETTLE);
            let limit = state.first.is_some_and(|first| now >= first + SETTLE_LIMIT);
            if quiet || limit {
                let report = Report {
                    code: CHANGED,
                    names: std::mem::take(&mut state.names).into_iter().collect(),
                    replaced: std::mem::take(&mut state.rebound),
                    overflowed: std::mem::take(&mut state.overflowed),
                };
                state.first = None;
                state.last = None;
                break report;
            }
            let deadline =
                (state.last.unwrap_or(now) + SETTLE).min(state.first.unwrap_or(now) + SETTLE_LIMIT);
            let (next, _) = watch
                .wake
                .wait_timeout(state, deadline.saturating_duration_since(now))
                .expect("watch state poisoned");
            state = next;
        } else {
            state = watch.wake.wait(state).expect("watch state poisoned");
        }
    };
    state.waiting = false;
    drop(state);
    if report.code == CHANGED {
        with(|store| store.counters[CHANGES] += 1);
    }
    report
}

/// Stop a watch. Consumes one reference to the handle.
pub fn cancel(handle: *mut u64) -> bool {
    let found = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some((_, watch)) = found else {
        return false;
    };
    let changed = end(&watch, End::Canceled);
    if changed {
        with(|store| store.counters[CANCELS] += 1);
    }
    changed
}

/// The application released its last reference: the watch ends, its waiter
/// wakes cancelled, and the directory is no longer watched once no other watch
/// shares it.
pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let released = with(|store| {
        let id = crate::remove_resource_allocation(&mut store.allocations, base as usize)?;
        let watch = store.watches.remove(&id)?;
        let last = store
            .by_descriptor
            .get_mut(&watch.descriptor)
            .map(|ids| {
                ids.retain(|held| *held != id);
                ids.is_empty()
            })
            .unwrap_or(false);
        if last {
            store.by_descriptor.remove(&watch.descriptor);
            if let Some(fd) = store.notifier {
                sys::remove(fd, watch.descriptor);
            }
        }
        Some((id, watch))
    });
    if let Some((id, watch)) = released {
        end(&watch, End::Canceled);
        grant::release(grant::Kind::Watch, id);
    }
}

/// End a watch whose grant was withdrawn, or whose parent was released.
fn end_if_withdrawn(id: u64, watch: &Watch) {
    if grant::is_revoked(grant::Kind::Watch, id) {
        if end(watch, End::Revoked) {
            with(|store| store.counters[REVOCATIONS] += 1);
        }
    } else if !grant::is_held(watch.parent.0, watch.parent.1) {
        end(watch, End::Canceled);
    }
}

/// Record one event against every watch of its directory; `None` is a lost
/// event, which every watch must assume touched it.
fn deliver(descriptor: Option<i32>, child: Option<&str>, mask: u32) {
    let now = Instant::now();
    let watches: Vec<Arc<Watch>> = with(|store| {
        let ids: Vec<u64> = match descriptor {
            Some(descriptor) => store
                .by_descriptor
                .get(&descriptor)
                .cloned()
                .unwrap_or_default(),
            None => store.watches.keys().copied().collect(),
        };
        ids.into_iter()
            .filter_map(|id| store.watches.get(&id).cloned())
            .collect()
    });
    let gone = descriptor.is_some() && mask & sys::DIRECTORY_GONE != 0;
    for watch in watches {
        if gone {
            end(&watch, End::Gone);
            continue;
        }
        let effect = match (descriptor, child) {
            (None, _) => None,
            (Some(_), Some(child)) => Some(watch.target.effect(child, mask)),
            (Some(_), None) => Some(Effect::Nothing),
        };
        let mut state = watch.state.lock().expect("watch state poisoned");
        if state.ended.is_some() {
            continue;
        }
        match effect {
            Some(Effect::Nothing) => continue,
            None => {
                state.overflowed = true;
                if matches!(watch.target, Target::Database { .. }) {
                    state.rebound = true;
                }
            }
            Some(Effect::Named { name, rebound }) => {
                state.rebound |= rebound;
                if state.names.len() < MAX_NAMES || state.names.contains(&name) {
                    state.names.insert(name);
                } else {
                    state.overflowed = true;
                }
            }
        }
        state.first.get_or_insert(now);
        state.last = Some(now);
        watch.wake.notify_all();
    }
    if gone {
        with(|store| {
            if let Some(descriptor) = descriptor {
                store.by_descriptor.remove(&descriptor);
            }
        });
    }
}

/// End every watch whose grant was withdrawn or whose parent was released.
fn end_withdrawn() {
    let watches: Vec<(u64, Arc<Watch>)> = with(|store| {
        store
            .watches
            .iter()
            .map(|(id, watch)| (*id, watch.clone()))
            .collect()
    });
    for (id, watch) in watches {
        end_if_withdrawn(id, &watch);
    }
}

fn watch_loop(fd: i32) {
    let mut buffer = vec![0u8; 64 * 1024];
    loop {
        match sys::read(fd, &mut buffer, LIVENESS_POLL) {
            Ok(events) => {
                for event in events {
                    deliver(event.descriptor, event.name.as_deref(), event.mask);
                }
            }
            Err(()) => return,
        }
        end_withdrawn();
    }
}

/// The directory a held descriptor names, as a path inotify can watch. On
/// Linux the descriptor's own entry in `/proc/self/fd` is that path, so nothing
/// is resolved by name that the descriptor does not already hold. Elsewhere
/// there is none, and a watch is refused as unsupported.
#[cfg(target_os = "linux")]
pub fn descriptor_path(dir: &cap_std::fs::Dir) -> Option<PathBuf> {
    use std::os::fd::AsRawFd;
    Some(PathBuf::from(format!("/proc/self/fd/{}", dir.as_raw_fd())))
}

#[cfg(not(target_os = "linux"))]
pub fn descriptor_path(_dir: &cap_std::fs::Dir) -> Option<PathBuf> {
    None
}

struct Event {
    /// `None` for a queue overflow, which names no directory.
    descriptor: Option<i32>,
    name: Option<String>,
    mask: u32,
}

#[cfg(target_os = "linux")]
mod sys {
    use super::{Event, Refusal};
    use std::{ffi::CString, os::unix::ffi::OsStrExt, path::Path, time::Duration};

    /// The name was bound to another file, or unbound.
    pub const NAME_CHANGED: u32 =
        libc::IN_CREATE | libc::IN_DELETE | libc::IN_MOVED_FROM | libc::IN_MOVED_TO;
    /// The file's contents were written.
    pub const WRITTEN: u32 = libc::IN_MODIFY;
    /// The watched directory itself is no longer where it was.
    pub const DIRECTORY_GONE: u32 =
        libc::IN_DELETE_SELF | libc::IN_MOVE_SELF | libc::IN_IGNORED | libc::IN_UNMOUNT;
    const MASK: u32 = NAME_CHANGED
        | WRITTEN
        | libc::IN_DELETE_SELF
        | libc::IN_MOVE_SELF
        | libc::IN_ONLYDIR
        | libc::IN_EXCL_UNLINK;

    pub fn open() -> Result<i32, Refusal> {
        let fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
        if fd < 0 {
            return Err(refusal());
        }
        Ok(fd)
    }

    fn refusal() -> Refusal {
        match std::io::Error::last_os_error().raw_os_error() {
            Some(libc::EMFILE | libc::ENFILE | libc::ENOSPC | libc::ENOMEM) => {
                Refusal::ResourceLimit
            }
            _ => Refusal::Io,
        }
    }

    pub fn add(fd: i32, directory: &Path) -> Result<i32, Refusal> {
        let path = CString::new(directory.as_os_str().as_bytes()).map_err(|_| Refusal::Io)?;
        let descriptor = unsafe { libc::inotify_add_watch(fd, path.as_ptr(), MASK) };
        if descriptor < 0 {
            return Err(refusal());
        }
        Ok(descriptor)
    }

    pub fn remove(fd: i32, descriptor: i32) {
        unsafe { libc::inotify_rm_watch(fd, descriptor) };
    }

    /// Wait up to `timeout` for events and decode every one available.
    pub fn read(fd: i32, buffer: &mut [u8], timeout: Duration) -> Result<Vec<Event>, ()> {
        let mut poll = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        let ready = unsafe { libc::poll(&mut poll, 1, timeout.as_millis() as i32) };
        if ready < 0 {
            return if std::io::Error::last_os_error().raw_os_error() == Some(libc::EINTR) {
                Ok(Vec::new())
            } else {
                Err(())
            };
        }
        let mut events = Vec::new();
        if ready == 0 {
            return Ok(events);
        }
        let read = unsafe { libc::read(fd, buffer.as_mut_ptr().cast(), buffer.len()) };
        if read <= 0 {
            return Ok(events);
        }
        let read = read as usize;
        let header = std::mem::size_of::<libc::inotify_event>();
        let mut offset = 0;
        while offset + header <= read {
            let event: libc::inotify_event =
                unsafe { std::ptr::read_unaligned(buffer[offset..].as_ptr().cast()) };
            let name_start = offset + header;
            let name_end = (name_start + event.len as usize).min(read);
            let name = buffer[name_start..name_end]
                .split(|byte| *byte == 0)
                .next()
                .filter(|name| !name.is_empty())
                .map(|name| String::from_utf8_lossy(name).into_owned());
            events.push(Event {
                descriptor: (event.mask & libc::IN_Q_OVERFLOW == 0).then_some(event.wd),
                name,
                mask: event.mask,
            });
            offset = name_end;
        }
        Ok(events)
    }
}

/// Watching is implemented on Linux; elsewhere a watch is refused as
/// unsupported rather than silently never reporting.
#[cfg(not(target_os = "linux"))]
mod sys {
    use super::{Event, Refusal};
    use std::{path::Path, time::Duration};

    pub const NAME_CHANGED: u32 = 1;
    pub const WRITTEN: u32 = 2;
    pub const DIRECTORY_GONE: u32 = 4;

    pub fn open() -> Result<i32, Refusal> {
        Err(Refusal::Unsupported)
    }

    pub fn add(_fd: i32, _directory: &Path) -> Result<i32, Refusal> {
        Err(Refusal::Unsupported)
    }

    pub fn remove(_fd: i32, _descriptor: i32) {}

    pub fn read(_fd: i32, _buffer: &mut [u8], _timeout: Duration) -> Result<Vec<Event>, ()> {
        Err(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn named(name: &str, rebound: bool) -> Effect {
        Effect::Named {
            name: name.into(),
            rebound,
        }
    }

    #[test]
    fn a_database_watch_wakes_on_commits_and_replacement_but_not_on_readers() {
        let target = Target::Database {
            name: "live.rgstats".into(),
        };
        assert_eq!(
            target.effect("live.rgstats-wal", sys::WRITTEN),
            named("live.rgstats", false)
        );
        assert_eq!(
            target.effect("live.rgstats", sys::WRITTEN),
            named("live.rgstats", false)
        );
        assert_eq!(
            target.effect("live.rgstats", sys::NAME_CHANGED),
            named("live.rgstats", true)
        );
        // A reader creating the log and its index beside the database is not a
        // change to it, and neither is anything else in the folder.
        assert_eq!(
            target.effect("live.rgstats-wal", sys::NAME_CHANGED),
            Effect::Nothing
        );
        assert_eq!(
            target.effect("live.rgstats-shm", sys::WRITTEN),
            Effect::Nothing
        );
        assert_eq!(
            target.effect("other.rgstats", sys::WRITTEN),
            Effect::Nothing
        );
    }

    #[test]
    fn a_directory_watch_names_every_child_it_saw_change() {
        assert_eq!(
            Target::Directory.effect("a.rgstats", sys::NAME_CHANGED),
            named("a.rgstats", true)
        );
        assert_eq!(
            Target::Directory.effect("a.rgstats-shm", sys::WRITTEN),
            named("a.rgstats-shm", false)
        );
        assert_eq!(Target::Directory.effect("a", 0), Effect::Nothing);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn a_watch_reports_a_replaced_file_once_writing_pauses() {
        let root = std::env::temp_dir().join(format!("roc-gui-watch-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let fd = sys::open().unwrap();
        let descriptor = sys::add(fd, &root).unwrap();
        let watch = Watch {
            target: Target::Database {
                name: "live.rgstats".into(),
            },
            descriptor,
            parent: (grant::Kind::Directory, 0),
            state: Mutex::new(State::default()),
            wake: Condvar::new(),
        };
        std::fs::write(root.join("staged"), b"new").unwrap();
        std::fs::rename(root.join("staged"), root.join("live.rgstats")).unwrap();
        let mut buffer = vec![0u8; 4096];
        let events = sys::read(fd, &mut buffer, Duration::from_secs(1)).unwrap();
        for event in &events {
            if let Some(name) = &event.name
                && let Effect::Named { name, rebound } = watch.target.effect(name, event.mask)
            {
                let mut state = watch.state.lock().unwrap();
                state.names.insert(name);
                state.rebound |= rebound;
            }
        }
        let state = watch.state.lock().unwrap();
        assert_eq!(state.names.iter().collect::<Vec<_>>(), ["live.rgstats"]);
        assert!(state.rebound);
        drop(state);
        sys::remove(fd, descriptor);
        unsafe { libc::close(fd) };
        std::fs::remove_dir_all(root).unwrap();
    }
}
