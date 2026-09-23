//! One chosen file.
//!
//! A document grant is the smallest thing a person can hand an application: one
//! file, read-only, and nothing beside it. It is chosen in the same trusted
//! surface a project folder is — the XDG Desktop Portal on Linux, the
//! window-owned native panel elsewhere — or provisioned by a development flag,
//! and it is recorded in the one grant registry as [`grant::Kind::Document`] so
//! it is listed, withdrawn, and described exactly as a folder is.
//!
//! The handle names the file, not a directory. The host keeps the descriptor of
//! the folder the file lies in so that it can read the file without following a
//! link and open it in place for SQLite, but no operation takes a name from the
//! application: every read resolves the one name the person chose.

use crate::files::{self, ChildReadError, FileErr, FileReason};
use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{roc_host, roc_platform_abi::*};
use cap_std::{ambient_authority, fs::Dir};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
    time::Instant,
};

const MAX_FILE_BYTES: u64 = 64 * 1024 * 1024;

/// What a chosen file may do: be read, and have a narrower grant derived from
/// it — a database connection opened in place, which must be revoked with it.
/// It lists nothing, because it has no children to list.
const DOCUMENT_RIGHTS: Rights = Rights::READ.union(Rights::DERIVE);

/// The chosen file, held as the folder it lies in and its one name there.
pub(crate) struct Chosen {
    pub(crate) dir: Dir,
    pub(crate) name: String,
}

struct Store {
    next: u64,
    initial: Option<Arc<Chosen>>,
    files: HashMap<u64, Arc<Chosen>>,
    allocations: HashMap<usize, u64>,
    chooser_enabled: bool,
    chooser_cancels: bool,
    in_flight: bool,
    refusal_until: Option<Instant>,
    counters: [u64; 5],
}

/// Indices into the counters, which are reported in this order.
const PICKS: usize = 0;
const CHOSEN: usize = 1;
const CANCELED: usize = 2;
const REFUSED: usize = 3;
const READS: usize = 4;

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            initial: None,
            files: HashMap::new(),
            allocations: HashMap::new(),
            chooser_enabled: false,
            chooser_cancels: false,
            in_flight: false,
            refusal_until: None,
            counters: [0; 5],
        })
    })
}

fn with<T>(act: impl FnOnce(&mut Store) -> T) -> T {
    act(&mut store().lock().expect("document store poisoned"))
}

/// Split a chosen path into the folder that holds it and its name there. The
/// path is resolved first: a person who chose a link chose what it names, and
/// the handle must never follow a link afterwards.
fn locate(path: &Path) -> std::io::Result<Chosen> {
    let resolved = std::fs::canonicalize(path)?;
    if !std::fs::metadata(&resolved)?.is_file() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "not an ordinary file",
        ));
    }
    let name = resolved
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "non-UTF-8 name"))?
        .to_owned();
    let parent = resolved
        .parent()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidInput, "no parent"))?;
    let dir = Dir::open_ambient_dir(parent, ambient_authority())?;
    Ok(Chosen { dir, name })
}

pub fn configure(
    path: Option<&Path>,
    chooser_enabled: bool,
    chooser_cancels: bool,
) -> Result<(), String> {
    if chooser_cancels && path.is_some() {
        return Err("a canceled chooser cannot also provision a file grant".into());
    }
    let initial = match path {
        None => None,
        Some(path) => Some(Arc::new(
            locate(path).map_err(|error| format!("cannot grant file: {error}"))?,
        )),
    };
    with(|store| {
        store.initial = initial;
        store.chooser_enabled = chooser_enabled || chooser_cancels;
        store.chooser_cancels = chooser_cancels;
        store.in_flight = false;
        store.refusal_until = None;
        store.counters = [0; 5];
    });
    grant::forget_kind(grant::Kind::Document);
    Ok(())
}

/// Picks, chosen files, cancellations, refusals, and reads, in that order.
/// Every refusal of a pick is one count whatever its reason; the reason is the
/// error the application received.
pub fn counters() -> [u64; 5] {
    with(|store| store.counters)
}

/// Live document handles the application is holding.
pub fn live() -> usize {
    with(|store| store.files.len())
}

/// Revoke every chosen file, and what was derived from each. Returns the number
/// of roots revoked.
pub fn revoke_all_roots() -> usize {
    let changed = grant::enumerate()
        .iter()
        .filter(|entry| {
            entry.kind() == grant::Kind::Document && entry.is_root() && !entry.is_revoked()
        })
        .count();
    grant::revoke_kind(grant::Kind::Document);
    changed
}

fn count(index: usize) {
    with(|store| store.counters[index] = store.counters[index].saturating_add(1));
}

fn capability(file: Arc<Chosen>, origin: Origin) -> *mut u64 {
    let mut guard = store().lock().expect("document store poisoned");
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("document capability ids exhausted");
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
    guard.files.insert(id, file);
    crate::register_resource_allocation(
        crate::resource_domain::DOCUMENT,
        &mut guard.allocations,
        base as usize,
        id,
    );
    drop(guard);
    grant::record_root(
        grant::Kind::Document,
        id,
        DOCUMENT_RIGHTS,
        origin,
        Lifetime::Session,
    );
    handle
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let released = with(|store| {
        let released = crate::remove_resource_allocation(&mut store.allocations, base as usize);
        if let Some(id) = released {
            store.files.remove(&id);
        }
        released
    });
    if let Some(id) = released {
        grant::release(grant::Kind::Document, id);
    }
}

pub(crate) enum Refused {
    Invalid,
    Revoked,
}

/// The chosen file and the grant it was accepted against, for the platform's
/// own modules that derive something from it, as `Sqlite` does.
pub(crate) fn lookup_accepted(handle: *mut u64) -> Result<(Arc<Chosen>, grant::Grant), Refused> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(Refused::Invalid)?;
    let entry =
        grant::accept(grant::Kind::Document, id, Rights::READ).map_err(
            |refusal| match refusal {
                grant::Refusal::Revoked => Refused::Revoked,
                _ => Refused::Invalid,
            },
        )?;
    with(|store| store.files.get(&id).cloned())
        .map(|file| (file, entry))
        .ok_or(Refused::Invalid)
}

/// One offered type, as the host reads it from Roc.
#[derive(Clone, Debug, PartialEq, Eq)]
struct FileType {
    label: String,
    extensions: Vec<String>,
    mime_types: Vec<String>,
}

/// Normalize and check the offered types. An extension is one ordinary name
/// component and never a pattern, and a MIME type names a type and a subtype;
/// anything else is refused rather than passed to a chooser that would read it
/// as a glob.
fn validate(types: Vec<FileType>) -> Option<Vec<FileType>> {
    types
        .into_iter()
        .map(|mut offered| {
            for extension in &mut offered.extensions {
                let bare = extension.trim_start_matches('.').to_ascii_lowercase();
                let ordinary = !bare.is_empty()
                    && bare
                        .chars()
                        .all(|c| c.is_alphanumeric() || matches!(c, '-' | '_' | '.' | '+'));
                if !ordinary {
                    return None;
                }
                *extension = bare;
            }
            let mime_ok = offered.mime_types.iter().all(|mime| {
                let mut parts = mime.split('/');
                matches!(
                    (parts.next(), parts.next(), parts.next()),
                    (Some(kind), Some(sub), None) if !kind.is_empty() && !sub.is_empty()
                        && !mime.contains(char::is_whitespace)
                )
            });
            let offers_something = !offered.extensions.is_empty() || !offered.mime_types.is_empty();
            (mime_ok && offers_something && !offered.label.is_empty()).then_some(offered)
        })
        .collect()
}

/// Whether a chosen name is one of the offered types. A chooser's filter is
/// advice to the person; this is the check, and it is the same whichever
/// chooser — or flag — produced the file. Types offered only by MIME type are
/// left to the chooser, because the host does not sniff content.
fn admits(types: &[FileType], name: &str) -> bool {
    let extensions: Vec<&str> = types
        .iter()
        .flat_map(|offered| offered.extensions.iter().map(String::as_str))
        .collect();
    if extensions.is_empty() {
        return true;
    }
    let lower = name.to_ascii_lowercase();
    extensions.iter().any(|extension| {
        lower
            .strip_suffix(extension)
            .is_some_and(|stem| stem.len() > 1 && stem.ends_with('.'))
    })
}

enum Selection {
    Chosen(Arc<Chosen>),
    Canceled,
    Denied,
    Unavailable,
}

fn open_chosen(path: PathBuf) -> Selection {
    match locate(&path) {
        Ok(chosen) => Selection::Chosen(Arc::new(chosen)),
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => Selection::Denied,
        Err(_) => Selection::Unavailable,
    }
}

#[cfg(target_os = "linux")]
fn chooser(types: &[FileType]) -> Selection {
    async_std::task::block_on(async {
        use ashpd::desktop::{
            ResponseError,
            file_chooser::{FileFilter, SelectedFiles},
        };
        let filters: Vec<FileFilter> = types
            .iter()
            .map(|offered| {
                let mut filter = FileFilter::new(&offered.label);
                for extension in &offered.extensions {
                    filter = filter.glob(&format!("*.{extension}"));
                }
                for mime in &offered.mime_types {
                    filter = filter.mimetype(mime);
                }
                filter
            })
            .collect();
        let request = match SelectedFiles::open_file()
            .title("Open")
            .accept_label("Open")
            .directory(false)
            .multiple(false)
            .modal(true)
            .filters(filters)
            .send()
            .await
        {
            Ok(value) => value,
            Err(_) => return Selection::Unavailable,
        };
        let files = match request.response() {
            Ok(value) => value,
            Err(ashpd::Error::Response(ResponseError::Cancelled)) => return Selection::Canceled,
            Err(ashpd::Error::Response(_)) => return Selection::Denied,
            Err(_) => return Selection::Unavailable,
        };
        let [uri] = files.uris() else {
            return Selection::Unavailable;
        };
        match uri.to_file_path() {
            Ok(path) => open_chosen(path),
            Err(_) => Selection::Unavailable,
        }
    })
}

/// The native panel GPUI presents offers no type filter, so every file is
/// offered and [`admits`] is the check.
#[cfg(not(target_os = "linux"))]
fn chooser(_types: &[FileType]) -> Selection {
    match files::native_path(false) {
        files::NativeAnswer::Unavailable => Selection::Unavailable,
        files::NativeAnswer::Canceled => Selection::Canceled,
        files::NativeAnswer::Chosen(path) => open_chosen(path),
    }
}

fn select(types: &[FileType]) -> Result<Option<(Arc<Chosen>, Origin)>, FileReason> {
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    if let Some(file) = with(|store| store.initial.clone()) {
        return Ok(Some((file, Origin::Provisioned)));
    }
    let allowed = with(|store| {
        let allowed = files::prompt_is_allowed(
            store.chooser_enabled,
            store.in_flight,
            store.refusal_until,
            Instant::now(),
        );
        store.in_flight |= allowed;
        allowed
    });
    if !allowed {
        return Err(R::AccessDenied);
    }
    let cancels = with(|store| store.chooser_cancels);
    let result = if cancels {
        Selection::Canceled
    } else {
        chooser(types)
    };
    with(|store| {
        store.in_flight = false;
        if matches!(result, Selection::Canceled | Selection::Denied) {
            store.refusal_until = Some(Instant::now() + files::REFUSAL_COOLDOWN);
        }
    });
    match result {
        Selection::Chosen(file) => Ok(Some((
            file,
            Origin::TrustedSelection(files::SELECTION_ENFORCEMENT),
        ))),
        Selection::Canceled => Ok(None),
        Selection::Denied => Err(R::AccessDenied),
        Selection::Unavailable => Err(R::Unavailable),
    }
}

fn pick_file_err(reason: FileReason) -> FileErr {
    FileErr {
        payload: InternalFilesPickDirectoryErrPayload {
            pick_file_err: ManuallyDrop::new(reason),
        },
        tag: InternalFilesPickDirectoryErrTag::PickFileErr,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_pick_file(
    types: RocList<InternalFilesPickFileArg0>,
) -> InternalFilesPickFileResult {
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    count(PICKS);
    let offered: Vec<FileType> = types
        .as_slice()
        .iter()
        .map(|raw| FileType {
            label: raw.label.as_str().to_owned(),
            extensions: raw
                .extensions
                .as_slice()
                .iter()
                .map(|value| value.as_str().to_owned())
                .collect(),
            mime_types: raw
                .mime_types
                .as_slice()
                .iter()
                .map(|value| value.as_str().to_owned())
                .collect(),
        })
        .collect();
    unsafe { decref_list_of_anon_struct_da3665c9cce9a3c(types, roc_host()) };
    let outcome = match validate(offered) {
        None => Err(R::InvalidName),
        Some(offered) => select(&offered).and_then(|chosen| match chosen {
            Some((file, _)) if !admits(&offered, &file.name) => Err(R::Unsupported),
            other => Ok(other),
        }),
    };
    count(match &outcome {
        Ok(Some(_)) => CHOSEN,
        Ok(None) => CANCELED,
        Err(_) => REFUSED,
    });
    match outcome {
        Ok(Some((file, origin))) => {
            let name = RocStr::from_str(&file.name, roc_host());
            let handle = capability(file, origin);
            InternalFilesPickFileResult {
                payload: InternalFilesPickFileResultPayload {
                    ok: ManuallyDrop::new(InternalFilesPickFileOk {
                        payload: InternalFilesPickFileOkPayload {
                            chosen: ManuallyDrop::new(InternalFilesPickFileOkChosen {
                                file: handle,
                                name,
                            }),
                        },
                        tag: InternalFilesPickFileOkTag::Chosen,
                    }),
                },
                tag: InternalFilesPickFileResultTag::Ok,
            }
        }
        Ok(None) => InternalFilesPickFileResult {
            payload: InternalFilesPickFileResultPayload {
                ok: ManuallyDrop::new(InternalFilesPickFileOk {
                    payload: InternalFilesPickFileOkPayload { canceled: [] },
                    tag: InternalFilesPickFileOkTag::Canceled,
                }),
            },
            tag: InternalFilesPickFileResultTag::Ok,
        },
        Err(reason) => InternalFilesPickFileResult {
            payload: InternalFilesPickFileResultPayload {
                err: ManuallyDrop::new(pick_file_err(reason)),
            },
            tag: InternalFilesPickFileResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_files_file_read(cap: *mut u64) -> InternalFilesFileReadResult {
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    count(READS);
    let opened = lookup_accepted(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let result =
        match opened {
            Err(Refused::Invalid) => Err(R::InvalidCapability),
            Err(Refused::Revoked) => Err(R::Revoked),
            Ok((file, _)) => files::read_child_bounded(&file.dir, &file.name, MAX_FILE_BYTES)
                .map_err(|error| match error {
                    ChildReadError::InvalidName => R::InvalidName,
                    ChildReadError::NotFound => R::NotFound,
                    ChildReadError::NotDirectory => R::NotDirectory,
                    ChildReadError::AccessDenied => R::AccessDenied,
                    ChildReadError::Unsupported => R::Unsupported,
                    ChildReadError::ResourceLimit => R::ResourceLimit,
                    ChildReadError::Io => R::Io,
                }),
        };
    match result {
        Ok(bytes) => InternalFilesFileReadResult {
            payload: InternalFilesFileReadResultPayload {
                ok: ManuallyDrop::new(unsafe {
                    RocListWith::<u8, false>::from_slice(&bytes, roc_host())
                }),
            },
            tag: InternalFilesFileReadResultTag::Ok,
        },
        Err(reason) => InternalFilesFileReadResult {
            payload: InternalFilesFileReadResultPayload {
                err: ManuallyDrop::new(files::read_file_err(reason)),
            },
            tag: InternalFilesFileReadResultTag::Err,
        },
    }
}

/// Hash the chosen file under the host's hash bound, without following a link.
#[unsafe(no_mangle)]
pub extern "C" fn roc_files_file_sha256(cap: *mut u64) -> InternalFilesDirSha256Result {
    use AccessDeniedOrInvalidCapabilityOrInvalidNameOrInvalidUtf8OrIoOrNotDirectoryOrNotFoundOrResourceLimitOrRevokedOrUnavailableOrUnsupported as R;
    let opened = lookup_accepted(cap);
    unsafe { decref_box(cap as RocBox, roc_host()) };
    let outcome = match opened {
        Err(Refused::Invalid) => {
            files::note_hash_refused();
            Err(R::InvalidCapability)
        }
        Err(Refused::Revoked) => {
            files::note_hash_refused();
            Err(R::Revoked)
        }
        Ok((file, _)) => {
            let hashed = files::hash_child_bounded(&file.dir, &file.name, files::MAX_HASH_BYTES);
            files::note_hash(&hashed);
            hashed
                .map(|(digest, _)| digest)
                .map_err(files::child_reason)
        }
    };
    files::hash_result(outcome)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn offered(extensions: &[&str], mime_types: &[&str]) -> FileType {
        FileType {
            label: "Captures".into(),
            extensions: extensions.iter().map(|value| (*value).to_owned()).collect(),
            mime_types: mime_types.iter().map(|value| (*value).to_owned()).collect(),
        }
    }

    #[test]
    fn extensions_are_names_not_patterns() {
        let normalized = validate(vec![offered(&[".RGSTATS"], &[])]).expect("dot is optional");
        assert_eq!(normalized[0].extensions, vec!["rgstats".to_owned()]);
        for pattern in ["*", "", "a/b", "a b", "rg*"] {
            assert!(
                validate(vec![offered(&[pattern], &[])]).is_none(),
                "{pattern:?}"
            );
        }
        assert!(validate(vec![offered(&[], &["application/vnd.sqlite3"])]).is_some());
        assert!(validate(vec![offered(&[], &["sqlite"])]).is_none());
        assert!(
            validate(vec![offered(&[], &[])]).is_none(),
            "a type that offers nothing is a mistake, not a wildcard"
        );
        assert_eq!(
            validate(Vec::new()),
            Some(Vec::new()),
            "no types offers every file"
        );
    }

    #[test]
    fn a_chosen_file_must_be_an_offered_type() {
        let types = validate(vec![offered(&["rgstats"], &[])]).unwrap();
        assert!(admits(&types, "run.rgstats"));
        assert!(admits(&types, "RUN.RGSTATS"));
        assert!(!admits(&types, "rgstats"));
        assert!(!admits(&types, ".rgstats"));
        assert!(!admits(&types, "notes.txt"));
        assert!(!admits(&types, "run.xrgstats"));
        assert!(admits(&[], "anything"));
        assert!(
            admits(
                &validate(vec![offered(&[], &["text/plain"])]).unwrap(),
                "notes"
            ),
            "MIME-only types are the chooser's to enforce"
        );
    }

    #[test]
    fn a_document_reads_and_derives_but_never_lists_or_writes() {
        assert!(DOCUMENT_RIGHTS.contains(Rights::READ));
        assert!(DOCUMENT_RIGHTS.contains(Rights::DERIVE));
        assert!(!DOCUMENT_RIGHTS.contains(Rights::LIST));
        assert!(!DOCUMENT_RIGHTS.contains(Rights::WRITE));
    }

    #[test]
    fn a_chosen_path_resolves_to_its_folder_and_one_name() {
        let root = std::env::temp_dir().join(format!("roc-gui-document-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let file = root.join("one.rgstats");
        std::fs::write(&file, b"bytes").unwrap();
        let chosen = locate(&file).expect("an ordinary file locates");
        assert_eq!(chosen.name, "one.rgstats");
        assert_eq!(
            files::read_child_bounded(&chosen.dir, &chosen.name, 16).ok(),
            Some(b"bytes".to_vec())
        );
        assert!(locate(&root).is_err(), "a folder is not a file");
        std::fs::remove_dir_all(&root).unwrap();
    }
}
