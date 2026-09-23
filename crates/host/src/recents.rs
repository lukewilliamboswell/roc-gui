//! The application's recent files and folders: grants a person gave it once,
//! remembered by the host so a later run may reopen them without asking again.
//!
//! A remembered grant is a record, not authority. What the record holds is the
//! place the person chose and the identity of what was there, and the host
//! checks both before it grants anything from it: a file that is missing, that
//! something else was renamed over, or that the application may no longer read
//! is reported as exactly that, and never reopened. The record lives with the
//! host, outside the application's own storage and outside every capture, and
//! the application only ever sees an entry's key, its name, and whether it can
//! be reopened now. No path crosses into Roc.
//!
//! The list is bounded. Remembering puts an entry first; an entry past the
//! bound is forgotten, as is one the application forgets or whose grant a
//! person withdraws, so a withdrawn file does not come back at the next start.

use crate::grant::{self, Enforcement, GrantId, Origin};
use std::{
    collections::HashMap,
    io::Write,
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
};

/// How many entries the list keeps. Remembering one more forgets the oldest.
pub const MAX_ENTRIES: usize = 128;

/// The first line of the store, and its format version.
const HEADER: &str = "roc-gui recent 1";

/// What a remembered entry names.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntryKind {
    File,
    Directory,
}

/// Why an entry cannot be reopened, or a grant cannot be remembered. The
/// numeric codes are the ones `Files.decode_unavailable` reads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Unavailable {
    AccessDenied = 1,
    Forgotten = 2,
    Missing = 3,
    Replaced = 4,
    Revoked = 5,
    Unreadable = 6,
    Unsupported = 7,
}

/// What was at the place when it was remembered. Two files are the same file
/// only when the filesystem says so: a name is not an identity, and a file
/// renamed over the remembered one has the same name and a different identity.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Identity {
    device: u64,
    inode: u64,
}

#[cfg(unix)]
fn identity_of(metadata: &std::fs::Metadata) -> Identity {
    use std::os::unix::fs::MetadataExt;
    Identity {
        device: metadata.dev(),
        inode: metadata.ino(),
    }
}

/// Without an inode, the creation instant stands in: a file moved into place
/// keeps its own, so it still differs from the one it replaced.
#[cfg(not(unix))]
fn identity_of(metadata: &std::fs::Metadata) -> Identity {
    let created = metadata
        .created()
        .ok()
        .and_then(|instant| instant.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|elapsed| elapsed.as_nanos() as u64)
        .unwrap_or(0);
    Identity {
        device: 0,
        inode: created,
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Entry {
    key: u64,
    kind: EntryKind,
    /// The resolved place, never shown to the application.
    path: PathBuf,
    identity: Identity,
    /// How the grant first arrived, which a reopened grant keeps: remembering
    /// a provisioned file does not turn it into a person's decision.
    origin: Origin,
}

impl Entry {
    fn name(&self) -> String {
        self.path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| self.path.to_string_lossy().into_owned())
    }
}

/// One entry as the application sees it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Listed {
    pub key: u64,
    pub name: String,
    pub kind: EntryKind,
    pub status: Result<(), Unavailable>,
}

/// Counters, in the order they are reported: grants remembered, entries
/// reopened, reopens and remembers refused, and entries forgotten.
pub const REMEMBERED: usize = 0;
pub const REOPENED: usize = 1;
pub const REFUSED: usize = 2;
pub const FORGOTTEN: usize = 3;

#[derive(Default)]
struct Store {
    /// Most recent first.
    entries: Vec<Entry>,
    next_key: u64,
    /// Where the list persists between runs; `None` keeps it for this run only.
    backing: Option<PathBuf>,
    /// The place each root granted this session came from, so it can be
    /// remembered. Only roots that arrived from outside are here: a derived
    /// grant names no place a person chose.
    sources: HashMap<GrantId, (EntryKind, PathBuf)>,
    /// Grants remembered or reopened this session, by the entry they belong
    /// to, so withdrawing one forgets its entry.
    held: HashMap<GrantId, u64>,
    counters: [u64; 4],
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

fn with<T>(act: impl FnOnce(&mut Store) -> T) -> T {
    act(&mut STORE
        .get_or_init(|| Mutex::new(Store::default()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()))
}

/// Where an interactive run keeps its list: the user's state directory, in a
/// folder of the application's own name. The application cannot reach it; it
/// holds no grant over anything outside its private storage.
pub fn default_store(app_name: &str) -> Option<PathBuf> {
    let base = std::env::var_os("XDG_STATE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME")
                .filter(|value| !value.is_empty())
                .map(|home| PathBuf::from(home).join(".local/state"))
        })?;
    Some(base.join("roc-gui").join(app_name).join("recent"))
}

/// Replace the list for this run. With `seeds`, the list is exactly those
/// places, the first most recent, recorded as provisioned and kept for this
/// run only: provisioning never writes a person's list. Otherwise the list is
/// read from `backing`, and every change is written back to it.
pub fn configure(backing: Option<PathBuf>, seeds: &[PathBuf]) -> Result<(), String> {
    let (entries, backing) = if seeds.is_empty() {
        let entries = match &backing {
            Some(path) => load(path),
            None => Vec::new(),
        };
        (entries, backing)
    } else {
        let mut entries = Vec::new();
        for (index, seed) in seeds.iter().enumerate() {
            let path = std::fs::canonicalize(seed)
                .map_err(|error| format!("cannot remember {}: {error}", seed.display()))?;
            let metadata = std::fs::metadata(&path)
                .map_err(|error| format!("cannot remember {}: {error}", seed.display()))?;
            let kind = if metadata.is_dir() {
                EntryKind::Directory
            } else if metadata.is_file() {
                EntryKind::File
            } else {
                return Err(format!(
                    "cannot remember {}: not a file or folder",
                    seed.display()
                ));
            };
            if entries.iter().any(|entry: &Entry| entry.path == path) {
                continue;
            }
            entries.push(Entry {
                key: index as u64 + 1,
                kind,
                path,
                identity: identity_of(&metadata),
                origin: Origin::Provisioned,
            });
        }
        entries.truncate(MAX_ENTRIES);
        (entries, None)
    };
    with(|store| {
        store.next_key = entries.iter().map(|entry| entry.key).max().unwrap_or(0) + 1;
        store.entries = entries;
        store.backing = backing;
        store.sources.clear();
        store.held.clear();
        store.counters = [0; 4];
    });
    Ok(())
}

/// Remembered, reopened, refused, and forgotten, then the entries listed now.
pub fn counters() -> [u64; 5] {
    with(|store| {
        [
            store.counters[REMEMBERED],
            store.counters[REOPENED],
            store.counters[REFUSED],
            store.counters[FORGOTTEN],
            store.entries.len() as u64,
        ]
    })
}

/// Note where a root grant came from, when it is created from a place a
/// person chose, dropped, or was provisioned. The resource that creates the
/// grant is the only one that knows the place.
pub fn note_source(id: GrantId, kind: EntryKind, path: &Path) {
    with(|store| {
        store.sources.insert(id, (kind, path.to_path_buf()));
    });
}

/// Forget the place of a grant whose handle was released.
pub fn release_source(id: GrantId) {
    with(|store| {
        store.sources.remove(&id);
        store.held.remove(&id);
    });
}

/// Check what is at an entry's place now.
fn check(entry: &Entry) -> Result<(), Unavailable> {
    let metadata = std::fs::symlink_metadata(&entry.path).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => Unavailable::Missing,
        std::io::ErrorKind::PermissionDenied => Unavailable::AccessDenied,
        _ => Unavailable::Unreadable,
    })?;
    let kind_matches = match entry.kind {
        EntryKind::File => metadata.is_file(),
        EntryKind::Directory => metadata.is_dir(),
    };
    if !kind_matches || identity_of(&metadata) != entry.identity {
        return Err(Unavailable::Replaced);
    }
    // Present and the same: whether it can still be read is a separate
    // question, and permission is its most common answer.
    let readable = match entry.kind {
        EntryKind::File => std::fs::File::open(&entry.path).map(|_| ()),
        EntryKind::Directory => std::fs::read_dir(&entry.path).map(|_| ()),
    };
    readable.map_err(|error| match error.kind() {
        std::io::ErrorKind::PermissionDenied => Unavailable::AccessDenied,
        std::io::ErrorKind::NotFound => Unavailable::Missing,
        _ => Unavailable::Unreadable,
    })
}

/// Every entry, most recent first, each checked now.
pub fn list() -> Vec<Listed> {
    let entries = with(|store| store.entries.clone());
    entries
        .iter()
        .map(|entry| Listed {
            key: entry.key,
            name: entry.name(),
            kind: entry.kind,
            status: check(entry),
        })
        .collect()
}

/// Remember the root grant `id`: its entry moves to the front, or is added
/// there, forgetting the oldest past the bound.
pub fn remember(kind: grant::Kind, id: u64) -> Result<(), Unavailable> {
    let outcome = remember_inner(kind, id);
    with(|store| {
        let index = if outcome.is_ok() { REMEMBERED } else { REFUSED };
        store.counters[index] += 1;
    });
    outcome
}

fn remember_inner(kind: grant::Kind, id: u64) -> Result<(), Unavailable> {
    let held = grant::remember(kind, id).map_err(|refusal| match refusal {
        grant::Refusal::Revoked => Unavailable::Revoked,
        grant::Refusal::Unknown => Unavailable::Revoked,
        grant::Refusal::Rights => Unavailable::Unsupported,
    })?;
    let (entry_kind, path) =
        with(|store| store.sources.get(&held.id()).cloned()).ok_or(Unavailable::Unsupported)?;
    let metadata = std::fs::metadata(&path).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => Unavailable::Missing,
        std::io::ErrorKind::PermissionDenied => Unavailable::AccessDenied,
        _ => Unavailable::Unreadable,
    })?;
    let identity = identity_of(&metadata);
    let origin = held.origin();
    let changed = with(|store| {
        let key = match store.entries.iter().position(|entry| entry.path == path) {
            Some(index) => {
                let mut entry = store.entries.remove(index);
                entry.identity = identity;
                entry.kind = entry_kind;
                entry.origin = origin;
                let key = entry.key;
                store.entries.insert(0, entry);
                key
            }
            None => {
                let key = store.next_key;
                store.next_key += 1;
                store.entries.insert(
                    0,
                    Entry {
                        key,
                        kind: entry_kind,
                        path: path.clone(),
                        identity,
                        origin,
                    },
                );
                key
            }
        };
        let dropped = store.entries.len().saturating_sub(MAX_ENTRIES);
        store.entries.truncate(MAX_ENTRIES);
        store.counters[FORGOTTEN] += dropped as u64;
        store.held.insert(held.id(), key);
        store
            .backing
            .clone()
            .map(|backing| (backing, store.entries.clone()))
    });
    if let Some((backing, entries)) = changed {
        // A list that cannot be written is still this run's list; the next
        // run reads whatever was written last, which is never a partial file.
        let _ = save(&backing, &entries);
    }
    Ok(())
}

/// The place an entry names, after checking it is still what was remembered,
/// and how its grant first arrived.
pub fn reopen(key: u64, kind: EntryKind) -> Result<(PathBuf, Origin), Unavailable> {
    let outcome = (|| {
        let entry = with(|store| store.entries.iter().find(|entry| entry.key == key).cloned())
            .ok_or(Unavailable::Forgotten)?;
        if entry.kind != kind {
            return Err(Unavailable::Unsupported);
        }
        check(&entry)?;
        Ok((entry.path, entry.origin))
    })();
    if outcome.is_err() {
        with(|store| store.counters[REFUSED] += 1);
    }
    outcome
}

/// Record that the reopened entry `key` is now held as grant `id`: counted as
/// a reopen, and its place noted so the grant can be remembered again.
pub fn reopened(key: u64, id: GrantId, kind: EntryKind, path: &Path) {
    with(|store| {
        store.counters[REOPENED] += 1;
        store.sources.insert(id, (kind, path.to_path_buf()));
        store.held.insert(id, key);
    });
}

/// Forget one entry. Its grants held this session are not withdrawn: they
/// were given for the session, and forgetting ends only the remembering.
pub fn forget(key: u64) -> bool {
    let changed = with(|store| {
        let before = store.entries.len();
        store.entries.retain(|entry| entry.key != key);
        if store.entries.len() == before {
            return None;
        }
        store.counters[FORGOTTEN] += 1;
        store.held.retain(|_, held| *held != key);
        Some(
            store
                .backing
                .clone()
                .map(|backing| (backing, store.entries.clone())),
        )
    });
    match changed {
        None => false,
        Some(write) => {
            if let Some((backing, entries)) = write {
                let _ = save(&backing, &entries);
            }
            true
        }
    }
}

/// Forget the entries of remembered roots a person withdrew.
pub fn forget_withdrawn(roots: Vec<GrantId>) {
    if roots.is_empty() {
        return;
    }
    let keys: Vec<u64> = with(|store| {
        roots
            .iter()
            .filter_map(|root| store.held.get(root).copied())
            .collect()
    });
    for key in keys {
        forget(key);
    }
}

/// The names of every entry, for the trusted App access surface, with the key
/// its Forget control acts on.
pub fn entries_for_access() -> Vec<(u64, String, EntryKind)> {
    with(|store| {
        store
            .entries
            .iter()
            .map(|entry| (entry.key, entry.name(), entry.kind))
            .collect()
    })
}

fn origin_name(origin: Origin) -> &'static str {
    match origin {
        Origin::TrustedSelection(Enforcement::Brokered) => "trusted-selection:brokered",
        Origin::TrustedSelection(Enforcement::ConsentOnly) => "trusted-selection:consent-only",
        Origin::Dropped(Enforcement::Brokered) => "drop:brokered",
        Origin::Dropped(Enforcement::ConsentOnly) => "drop:consent-only",
        Origin::Provisioned => "provisioned",
        Origin::Automatic => "automatic",
    }
}

fn origin_from(name: &str) -> Option<Origin> {
    Some(match name {
        "trusted-selection:brokered" => Origin::TrustedSelection(Enforcement::Brokered),
        "trusted-selection:consent-only" => Origin::TrustedSelection(Enforcement::ConsentOnly),
        "drop:brokered" => Origin::Dropped(Enforcement::Brokered),
        "drop:consent-only" => Origin::Dropped(Enforcement::ConsentOnly),
        "provisioned" => Origin::Provisioned,
        _ => return None,
    })
}

#[cfg(unix)]
fn path_bytes(path: &Path) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    path.as_os_str().as_bytes().to_vec()
}

#[cfg(unix)]
fn path_from_bytes(bytes: Vec<u8>) -> PathBuf {
    use std::os::unix::ffi::OsStringExt;
    PathBuf::from(std::ffi::OsString::from_vec(bytes))
}

#[cfg(not(unix))]
fn path_bytes(path: &Path) -> Vec<u8> {
    path.to_string_lossy().as_bytes().to_vec()
}

#[cfg(not(unix))]
fn path_from_bytes(bytes: Vec<u8>) -> PathBuf {
    PathBuf::from(String::from_utf8_lossy(&bytes).into_owned())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn unhex(text: &str) -> Option<Vec<u8>> {
    if !text.len().is_multiple_of(2) {
        return None;
    }
    (0..text.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(text.get(index..index + 2)?, 16).ok())
        .collect()
}

/// One line per entry, most recent first: key, kind, identity, origin, and the
/// place as hexadecimal bytes, so no byte of a name can break the format.
fn encode(entries: &[Entry]) -> String {
    let mut text = String::from(HEADER);
    text.push('\n');
    for entry in entries {
        text.push_str(&format!(
            "{}\t{}\t{}\t{}\t{}\t{}\n",
            entry.key,
            match entry.kind {
                EntryKind::File => "file",
                EntryKind::Directory => "directory",
            },
            entry.identity.device,
            entry.identity.inode,
            origin_name(entry.origin),
            hex(&path_bytes(&entry.path)),
        ));
    }
    text
}

/// Read a list back. A line that does not parse is left out rather than
/// guessed at, and a file of another format is an empty list.
fn decode(text: &str) -> Vec<Entry> {
    let mut lines = text.lines();
    if lines.next() != Some(HEADER) {
        return Vec::new();
    }
    let mut entries: Vec<Entry> = Vec::new();
    for line in lines {
        let fields: Vec<&str> = line.split('\t').collect();
        let [key, kind, device, inode, origin, path] = fields.as_slice() else {
            continue;
        };
        let parsed = (|| {
            Some(Entry {
                key: key.parse().ok()?,
                kind: match *kind {
                    "file" => EntryKind::File,
                    "directory" => EntryKind::Directory,
                    _ => return None,
                },
                identity: Identity {
                    device: device.parse().ok()?,
                    inode: inode.parse().ok()?,
                },
                origin: origin_from(origin)?,
                path: path_from_bytes(unhex(path)?),
            })
        })();
        if let Some(entry) = parsed
            && entries
                .iter()
                .all(|held| held.key != entry.key && held.path != entry.path)
        {
            entries.push(entry);
        }
    }
    entries.truncate(MAX_ENTRIES);
    entries
}

fn load(path: &Path) -> Vec<Entry> {
    std::fs::read_to_string(path)
        .map(|text| decode(&text))
        .unwrap_or_default()
}

/// Write the list beside its store and rename it into place, so a reader
/// finds the previous list or this one, never half of either.
fn save(path: &Path, entries: &[Entry]) -> std::io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| std::io::Error::other("recent store has no folder"))?;
    std::fs::create_dir_all(parent)?;
    let staging = parent.join(format!(".recent-{}", std::process::id()));
    let mut file = std::fs::File::create(&staging)?;
    file.write_all(encode(entries).as_bytes())?;
    file.sync_all()?;
    drop(file);
    std::fs::rename(&staging, path).inspect_err(|_| {
        let _ = std::fs::remove_file(&staging);
    })
}

/// The recent list as the application reads it, each entry checked now.
#[unsafe(no_mangle)]
pub extern "C" fn roc_files_recent()
-> crate::roc_platform_abi::RocList<crate::roc_platform_abi::AnonStruct3ef35cf67ee1fcb4> {
    use crate::roc_platform_abi::{AnonStruct3ef35cf67ee1fcb4, RocList, RocStr};
    let host = crate::roc_host();
    let values: Vec<AnonStruct3ef35cf67ee1fcb4> = list()
        .into_iter()
        .map(|entry| AnonStruct3ef35cf67ee1fcb4 {
            key: entry.key,
            name: RocStr::from_str(&entry.name, host),
            directory: entry.kind == EntryKind::Directory,
            status: match entry.status {
                Ok(()) => 0,
                Err(reason) => reason as u8,
            },
        })
        .collect();
    unsafe { RocList::from_slice(&values, host) }
}

/// Forget one entry; `false` when no entry has the key.
#[unsafe(no_mangle)]
pub extern "C" fn roc_files_forget_recent(key: u64) -> bool {
    forget(key)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grant::{Kind, Lifetime, Rights};

    /// The store and the grant registry are process-wide, as in production,
    /// so the tests that use them take the registry's turn.
    fn fresh(backing: Option<PathBuf>) -> std::sync::MutexGuard<'static, ()> {
        let guard = grant::test_turn();
        grant::reset();
        configure(backing, &[]).unwrap();
        guard
    }

    fn scratch(name: &str) -> PathBuf {
        let root =
            std::env::temp_dir().join(format!("roc-gui-recents-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        root.canonicalize().unwrap()
    }

    /// Record a chosen root the way a resource does, with its place noted.
    fn choose(kind: Kind, id: u64, path: &Path, origin: Origin) {
        grant::record_root(kind, id, Rights::READ, origin, Lifetime::Session);
        note_source(
            GrantId::new(kind, id),
            if kind == Kind::Directory {
                EntryKind::Directory
            } else {
                EntryKind::File
            },
            path,
        );
    }

    const CHOSEN: Origin = Origin::TrustedSelection(Enforcement::ConsentOnly);

    #[test]
    fn a_remembered_file_survives_a_restart_and_reopens_as_itself() {
        let root = scratch("restart");
        let store = root.join("state/recent");
        let file = root.join("one.rgstats");
        std::fs::write(&file, b"one").unwrap();
        let _turn = fresh(Some(store.clone()));
        choose(
            Kind::Document,
            1,
            &file,
            Origin::Dropped(Enforcement::ConsentOnly),
        );
        remember(Kind::Document, 1).unwrap();
        assert!(
            grant::enumerate()[0].describe().ends_with(" remembered"),
            "the grant says it is remembered"
        );
        // A new run reads the list its predecessor wrote.
        configure(Some(store.clone()), &[]).unwrap();
        let listed = list();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].name, "one.rgstats");
        assert_eq!(listed[0].kind, EntryKind::File);
        assert_eq!(listed[0].status, Ok(()));
        let (path, origin) = reopen(listed[0].key, EntryKind::File).unwrap();
        assert_eq!(path, file);
        assert_eq!(
            origin,
            Origin::Dropped(Enforcement::ConsentOnly),
            "a reopened grant keeps how it first arrived"
        );
        assert_eq!(
            reopen(listed[0].key, EntryKind::Directory),
            Err(Unavailable::Unsupported)
        );
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn a_missing_replaced_or_unreadable_entry_says_why_and_is_never_reopened() {
        let root = scratch("unavailable");
        let _turn = fresh(None);
        let names = ["gone.rgstats", "swapped.rgstats", "locked.rgstats", "kept"];
        for (index, name) in names.iter().enumerate() {
            let path = root.join(name);
            if *name == "kept" {
                std::fs::create_dir(&path).unwrap();
                choose(Kind::Directory, index as u64 + 1, &path, CHOSEN);
                remember(Kind::Directory, index as u64 + 1).unwrap();
            } else {
                std::fs::write(&path, name.as_bytes()).unwrap();
                choose(Kind::Document, index as u64 + 1, &path, CHOSEN);
                remember(Kind::Document, index as u64 + 1).unwrap();
            }
        }
        std::fs::remove_file(root.join("gone.rgstats")).unwrap();
        let staged = root.join("staged");
        std::fs::write(&staged, b"another").unwrap();
        std::fs::rename(&staged, root.join("swapped.rgstats")).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                root.join("locked.rgstats"),
                std::fs::Permissions::from_mode(0o000),
            )
            .unwrap();
        }
        let listed = list();
        let status = |name: &str| {
            listed
                .iter()
                .find(|entry| entry.name == name)
                .map(|entry| entry.status)
                .unwrap()
        };
        assert_eq!(
            listed
                .iter()
                .map(|entry| entry.name.as_str())
                .collect::<Vec<_>>(),
            vec!["kept", "locked.rgstats", "swapped.rgstats", "gone.rgstats"],
            "most recent first"
        );
        assert_eq!(status("gone.rgstats"), Err(Unavailable::Missing));
        assert_eq!(status("swapped.rgstats"), Err(Unavailable::Replaced));
        assert_eq!(status("kept"), Ok(()));
        // A privileged account reads every file whatever its mode, so the
        // permission answer is asserted only where it can be observed.
        #[cfg(unix)]
        if std::fs::File::open(root.join("locked.rgstats")).is_err() {
            assert_eq!(status("locked.rgstats"), Err(Unavailable::AccessDenied));
        }
        let gone = listed
            .iter()
            .find(|entry| entry.name == "gone.rgstats")
            .unwrap();
        assert_eq!(reopen(gone.key, EntryKind::File), Err(Unavailable::Missing));
        assert_eq!(reopen(9999, EntryKind::File), Err(Unavailable::Forgotten));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                root.join("locked.rgstats"),
                std::fs::Permissions::from_mode(0o644),
            )
            .unwrap();
        }
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn the_list_is_bounded_and_remembering_again_moves_an_entry_first() {
        let root = scratch("bounded");
        let _turn = fresh(None);
        for index in 0..(MAX_ENTRIES as u64 + 2) {
            let path = root.join(format!("{index}.rgstats"));
            std::fs::write(&path, b"x").unwrap();
            choose(Kind::Document, index + 1, &path, CHOSEN);
            remember(Kind::Document, index + 1).unwrap();
        }
        let listed = list();
        assert_eq!(listed.len(), MAX_ENTRIES);
        assert_eq!(listed[0].name, format!("{}.rgstats", MAX_ENTRIES + 1));
        assert!(
            listed.iter().all(|entry| entry.name != "0.rgstats"),
            "the oldest is forgotten past the bound"
        );
        let key_of = |name: &str| list().iter().find(|entry| entry.name == name).unwrap().key;
        let before = key_of("5.rgstats");
        remember(Kind::Document, 6).unwrap();
        assert_eq!(list()[0].name, "5.rgstats");
        assert_eq!(key_of("5.rgstats"), before, "an entry keeps its key");
        assert_eq!(counters()[FORGOTTEN], 2);
        assert_eq!(counters()[4], MAX_ENTRIES as u64);
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn only_a_live_root_that_arrived_from_outside_can_be_remembered() {
        let root = scratch("roots");
        let file = root.join("one.rgstats");
        std::fs::write(&file, b"one").unwrap();
        let _turn = fresh(None);
        choose(Kind::Directory, 1, &root, Origin::Provisioned);
        grant::record_root(
            Kind::Directory,
            1,
            Rights::READ.union(Rights::DERIVE),
            Origin::Provisioned,
            Lifetime::Session,
        );
        let parent = grant::accept(Kind::Directory, 1, Rights::READ).unwrap();
        assert!(grant::record_descendant(
            Kind::Directory,
            2,
            Rights::READ,
            parent
        ));
        assert_eq!(
            remember(Kind::Directory, 2),
            Err(Unavailable::Unsupported),
            "a derived folder names no place a person chose"
        );
        grant::record_root(
            Kind::AppData,
            1,
            Rights::READ,
            Origin::Automatic,
            Lifetime::Session,
        );
        assert_eq!(remember(Kind::AppData, 1), Err(Unavailable::Unsupported));
        choose(Kind::Document, 3, &file, CHOSEN);
        grant::revoke(Kind::Document, 3);
        assert_eq!(remember(Kind::Document, 3), Err(Unavailable::Revoked));
        assert_eq!(remember(Kind::Directory, 1), Ok(()));
        assert_eq!(counters()[..4], [1, 0, 3, 0]);
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn withdrawing_a_remembered_grant_forgets_it() {
        let root = scratch("withdrawn");
        let file = root.join("one.rgstats");
        std::fs::write(&file, b"one").unwrap();
        let _turn = fresh(None);
        choose(Kind::Document, 1, &file, CHOSEN);
        remember(Kind::Document, 1).unwrap();
        assert_eq!(list().len(), 1);
        grant::revoke(Kind::Document, 1);
        assert!(list().is_empty(), "a withdrawn file does not come back");
        assert_eq!(counters()[FORGOTTEN], 1);
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn provisioned_seeds_are_listed_in_order_and_never_written() {
        let root = scratch("seeds");
        let first = root.join("first.rgstats");
        let second = root.join("second");
        std::fs::write(&first, b"1").unwrap();
        std::fs::create_dir(&second).unwrap();
        let _turn = fresh(None);
        configure(
            Some(root.join("state/recent")),
            &[first.clone(), second.clone()],
        )
        .unwrap();
        let listed = list();
        assert_eq!(
            listed
                .iter()
                .map(|entry| (entry.name.as_str(), entry.kind))
                .collect::<Vec<_>>(),
            vec![
                ("first.rgstats", EntryKind::File),
                ("second", EntryKind::Directory)
            ]
        );
        assert!(forget(listed[0].key));
        assert!(!forget(listed[0].key));
        assert!(
            !root.join("state/recent").exists(),
            "provisioning never writes a person's list"
        );
        assert!(configure(None, &[root.join("absent")]).is_err());
        std::fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn the_store_reads_back_exactly_what_it_wrote_and_nothing_malformed() {
        let entries = vec![
            Entry {
                key: 7,
                kind: EntryKind::File,
                path: PathBuf::from("/tmp/a\tb\nc.rgstats"),
                identity: Identity {
                    device: 1,
                    inode: 2,
                },
                origin: Origin::Dropped(Enforcement::ConsentOnly),
            },
            Entry {
                key: 3,
                kind: EntryKind::Directory,
                path: PathBuf::from("/tmp/folder"),
                identity: Identity {
                    device: 1,
                    inode: 9,
                },
                origin: Origin::Provisioned,
            },
        ];
        assert_eq!(decode(&encode(&entries)), entries);
        let damaged = format!(
            "{}garbage\n7\tfile\tx\t2\tprovisioned\t00\n",
            encode(&entries)
        );
        assert_eq!(decode(&damaged), entries);
        assert!(decode("another format\n").is_empty());
    }
}
