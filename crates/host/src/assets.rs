//! Read-only access to the artwork an application ships with itself.
//!
//! An asset store is the third kind of file access this host provides, and the
//! narrowest. A picked directory is user data reached through a trusted
//! chooser. Application data is private read-write durable state. An asset
//! store is the application's own read-only shipped content, so it is
//! provisioned automatically and prompts nobody.
//!
//! That automatic provisioning is exactly why the root is not a path the
//! application chooses freely. A store may be rooted beneath the executable's
//! directory or beneath the process working directory -- two places the program
//! already is -- or at a content directory the host was configured to hand it.
//! Nothing here accepts an absolute path from Roc, and nothing here calls
//! `chdir`: the host holds an open directory and resolves every asset through
//! it.
//!
//! Path resolution, symlink refusal, and the read bound are `files`'s, not a
//! second implementation.

use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{
    files::{ChildReadError, open_subdir_nofollow, read_child_bounded, relative_components},
    roc_host,
    roc_platform_abi::*,
};
use cap_std::{ambient_authority, fs::Dir};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

/// The manifest an asset set may declare about itself, read at the store root.
pub(crate) const MANIFEST_NAME: &str = "roc-assets.manifest";
const MAX_MANIFEST_BYTES: u64 = 64 * 1024;
/// One asset read into one Roc value. This is the file bound a granted
/// directory already uses; an asset store is not a reason to read more.
const MAX_ASSET_BYTES: u64 = 64 * 1024 * 1024;
const MAX_STORES: usize = 64;

/// Failure categories, in the order the Roc `Assets.Reason` decoder expects.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub(crate) enum Failure {
    AccessDenied = 0,
    InvalidCapability = 1,
    InvalidRoot = 2,
    InvalidName = 3,
    NotFound = 4,
    NotDirectory = 5,
    Io = 6,
    ResourceLimit = 7,
    Unsupported = 8,
    ManifestMissing = 9,
    ManifestUnreadable = 10,
    ManifestMalformed = 11,
    AssetSetMismatch = 12,
    SchemaMismatch = 13,
    ContentVersionMismatch = 14,
    ContentHashMismatch = 15,
    InvalidExpectation = 16,
    Unavailable = 17,
    Revoked = 18,
}

/// Deterministic, content-free evidence owned by this module. Never a path, a
/// file name, or asset bytes: six numbers.
static COUNTERS: [AtomicU64; 6] = [
    AtomicU64::new(0),
    AtomicU64::new(0),
    AtomicU64::new(0),
    AtomicU64::new(0),
    AtomicU64::new(0),
    AtomicU64::new(0),
];
const OPENS: usize = 0;
const OPEN_REFUSALS: usize = 1;
const MANIFEST_CHECKS: usize = 2;
const READS: usize = 3;
const READ_REFUSALS: usize = 4;
const BYTES_READ: usize = 5;

pub fn counters() -> [u64; 6] {
    std::array::from_fn(|index| COUNTERS[index].load(Ordering::Relaxed))
}

fn record(index: usize, amount: u64) {
    COUNTERS[index].fetch_add(amount, Ordering::Relaxed);
}

struct Registry {
    content_root: Option<PathBuf>,
    next: u64,
    stores: HashMap<u64, Arc<Dir>>,
    allocations: HashMap<usize, u64>,
}

static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();

fn registry() -> &'static Mutex<Registry> {
    REGISTRY.get_or_init(|| {
        Mutex::new(Registry {
            content_root: None,
            next: 1,
            stores: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}

/// Provision the content directory a `ContentDirectory` root resolves to. The
/// path comes from the host's own configuration, never from Roc.
/// What an asset store may do: read the application's own shipped files and
/// enumerate them. It never derives — an asset path is resolved inside the one
/// store rather than by handing out a narrower handle.
const ASSET_RIGHTS: Rights = Rights::READ.union(Rights::LIST);

/// How it arrives. Shipped assets hold no user data and carry no authority
/// beyond the one directory they are, so the contract provisions them without a
/// prompt.
const ASSET_ORIGIN: Origin = Origin::Automatic;

pub fn configure(content_root: Option<&Path>) {
    grant::forget_kind(grant::Kind::Assets);
    let mut guard = registry().lock().expect("asset registry poisoned");
    guard.content_root = content_root.map(Path::to_path_buf);
    for counter in &COUNTERS {
        counter.store(0, Ordering::Relaxed);
    }
}

fn allocate(directory: Arc<Dir>) -> Result<*mut u64, Failure> {
    let mut guard = registry().lock().map_err(|_| Failure::Unavailable)?;
    if guard.stores.len() >= MAX_STORES {
        return Err(Failure::ResourceLimit);
    }
    let id = guard.next;
    guard.next = guard.next.checked_add(1).ok_or(Failure::ResourceLimit)?;
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
    guard.stores.insert(id, directory);
    crate::register_resource_allocation(
        crate::resource_domain::ASSETS,
        &mut guard.allocations,
        base as usize,
        id,
    );
    grant::record_root(
        grant::Kind::Assets,
        id,
        ASSET_RIGHTS,
        ASSET_ORIGIN,
        Lifetime::Session,
    );
    Ok(handle)
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut released = None;
    if let Ok(mut guard) = registry().lock()
        && let Some(id) = crate::remove_resource_allocation(&mut guard.allocations, base as usize)
    {
        guard.stores.remove(&id);
        released = Some(id);
    }
    if let Some(id) = released {
        grant::release(grant::Kind::Assets, id);
    }
}

fn lookup(handle: *mut u64) -> Result<Arc<Dir>, Failure> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(Failure::InvalidCapability)?;
    grant::accept(grant::Kind::Assets, id, Rights::READ).map_err(|refusal| match refusal {
        grant::Refusal::Revoked => Failure::Revoked,
        _ => Failure::InvalidCapability,
    })?;
    let guard = registry().lock().map_err(|_| Failure::Unavailable)?;
    guard
        .stores
        .get(&id)
        .cloned()
        .ok_or(Failure::InvalidCapability)
}

/// What a required manifest is compared against.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Expectation {
    pub asset_set: String,
    pub schema: u32,
    pub content_version: u32,
    /// `None` leaves content unconstrained; `Some` is a 64-character lowercase
    /// hexadecimal SHA-256 digest the manifest must declare.
    pub content_sha256: Option<String>,
}

/// What a `roc-assets.manifest` declares about the asset set beside it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Declaration {
    pub asset_set: String,
    pub schema: u32,
    pub content_version: u32,
    pub sha256: Option<String>,
}

fn normalized_digest(value: &str) -> Option<String> {
    if value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        Some(value.to_ascii_lowercase())
    } else {
        None
    }
}

/// Parse a manifest.
///
/// The format is one `key = value` per line, with `#` comments and blank lines
/// ignored. `asset_set`, `schema`, and `content_version` are required;
/// `sha256` is optional. An unknown key, a repeated key, a missing required
/// key, a line that is not a pair, or a digest that is not 64 hexadecimal
/// characters makes the file not a manifest, rather than a manifest that
/// happens to be partly understood.
pub(crate) fn parse_manifest(text: &str) -> Result<Declaration, Failure> {
    let mut asset_set = None;
    let mut schema = None;
    let mut content_version = None;
    let mut sha256 = None;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (key, value) = line.split_once('=').ok_or(Failure::ManifestMalformed)?;
        let (key, value) = (key.trim(), value.trim());
        let taken = match key {
            "asset_set" => {
                if value.is_empty() {
                    return Err(Failure::ManifestMalformed);
                }
                asset_set.replace(value.to_owned()).is_some()
            }
            "schema" => schema
                .replace(
                    value
                        .parse::<u32>()
                        .map_err(|_| Failure::ManifestMalformed)?,
                )
                .is_some(),
            "content_version" => content_version
                .replace(
                    value
                        .parse::<u32>()
                        .map_err(|_| Failure::ManifestMalformed)?,
                )
                .is_some(),
            "sha256" => sha256
                .replace(normalized_digest(value).ok_or(Failure::ManifestMalformed)?)
                .is_some(),
            _ => return Err(Failure::ManifestMalformed),
        };
        if taken {
            return Err(Failure::ManifestMalformed);
        }
    }
    Ok(Declaration {
        asset_set: asset_set.ok_or(Failure::ManifestMalformed)?,
        schema: schema.ok_or(Failure::ManifestMalformed)?,
        content_version: content_version.ok_or(Failure::ManifestMalformed)?,
        sha256,
    })
}

/// Compare a declaration with an expectation, reporting the first disagreement
/// in a fixed order so the same mismatch always names the same failure.
///
/// Only the manifest's own declarations are compared. Nothing walks or hashes
/// the files beneath the root, so an open costs the same for one asset as for
/// ten thousand.
pub(crate) fn check_manifest(
    declared: &Declaration,
    expected: &Expectation,
) -> Result<(), Failure> {
    if declared.asset_set != expected.asset_set {
        return Err(Failure::AssetSetMismatch);
    }
    if declared.schema != expected.schema {
        return Err(Failure::SchemaMismatch);
    }
    if declared.content_version != expected.content_version {
        return Err(Failure::ContentVersionMismatch);
    }
    match &expected.content_sha256 {
        None => Ok(()),
        Some(digest) if declared.sha256.as_deref() == Some(digest.as_str()) => Ok(()),
        Some(_) => Err(Failure::ContentHashMismatch),
    }
}

/// Where a store's root is. `ContentDirectory` carries no path: the host, not
/// the application, decides where provisioned content lives.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Root {
    BesideExecutable(String),
    WorkingDirectory(String),
    ContentDirectory,
}

fn root_base(root: &Root) -> Result<PathBuf, Failure> {
    match root {
        Root::BesideExecutable(_) => std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(Path::to_path_buf))
            .ok_or(Failure::Unavailable),
        Root::WorkingDirectory(_) => std::env::current_dir().map_err(|_| Failure::Unavailable),
        Root::ContentDirectory => registry()
            .lock()
            .map_err(|_| Failure::Unavailable)?
            .content_root
            .clone()
            .ok_or(Failure::AccessDenied),
    }
}

fn root_relative(root: &Root) -> &str {
    match root {
        Root::BesideExecutable(path) | Root::WorkingDirectory(path) => path,
        Root::ContentDirectory => "",
    }
}

fn open_root(root: &Root) -> Result<Arc<Dir>, Failure> {
    let base = root_base(root)?;
    let relative = root_relative(root);
    // A provisioned content directory is already the root, so an empty relative
    // path is legal only there. Everywhere else the application must name a
    // subdirectory, and that name goes through the one path resolver.
    let parts = if relative.is_empty() {
        if !matches!(root, Root::ContentDirectory) {
            return Err(Failure::InvalidRoot);
        }
        Vec::new()
    } else {
        relative_components(relative).ok_or(Failure::InvalidRoot)?
    };
    let base_dir = Dir::open_ambient_dir(&base, ambient_authority()).map_err(io_failure)?;
    let directory = open_subdir_nofollow(&base_dir, &parts).map_err(io_failure)?;
    Ok(Arc::new(directory))
}

fn io_failure(error: std::io::Error) -> Failure {
    match error.kind() {
        std::io::ErrorKind::NotFound => Failure::NotFound,
        std::io::ErrorKind::PermissionDenied => Failure::AccessDenied,
        std::io::ErrorKind::NotADirectory => Failure::NotDirectory,
        _ => Failure::Io,
    }
}

fn verify_manifest(directory: &Dir, expected: &Expectation) -> Result<(), Failure> {
    record(MANIFEST_CHECKS, 1);
    let bytes =
        read_child_bounded(directory, MANIFEST_NAME, MAX_MANIFEST_BYTES).map_err(|error| {
            match error {
                ChildReadError::NotFound => Failure::ManifestMissing,
                _ => Failure::ManifestUnreadable,
            }
        })?;
    let text = String::from_utf8(bytes).map_err(|_| Failure::ManifestMalformed)?;
    check_manifest(&parse_manifest(&text)?, expected)
}

fn open_store(root: Root, expected: Option<Expectation>) -> Result<*mut u64, Failure> {
    // An unusable expectation is answered before any file is touched.
    if let Some(expectation) = &expected {
        if let Some(digest) = &expectation.content_sha256 {
            if normalized_digest(digest).as_deref() != Some(digest.as_str()) {
                return Err(Failure::InvalidExpectation);
            }
        }
    }
    let directory = open_root(&root)?;
    if let Some(expectation) = &expected {
        verify_manifest(&directory, expectation)?;
    }
    allocate(directory)
}

fn open_result(result: Result<*mut u64, Failure>) -> HostGlueAssetsOpenResult {
    match result {
        Ok(handle) => {
            record(OPENS, 1);
            HostGlueAssetsOpenResult {
                payload: HostGlueAssetsOpenResultPayload {
                    ok: ManuallyDrop::new(handle),
                },
                tag: HostGlueAssetsOpenResultTag::Ok,
            }
        }
        Err(failure) => {
            record(OPEN_REFUSALS, 1);
            HostGlueAssetsOpenResult {
                payload: HostGlueAssetsOpenResultPayload {
                    err: ManuallyDrop::new(failure as u8),
                },
                tag: HostGlueAssetsOpenResultTag::Err,
            }
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_assets_open(args: HostGlueAssetsOpenArgs) -> HostGlueAssetsOpenResult {
    let root = match args.root_kind {
        0 => Some(Root::BesideExecutable(args.root.as_str().to_owned())),
        1 => Some(Root::WorkingDirectory(args.root.as_str().to_owned())),
        2 => Some(Root::ContentDirectory),
        _ => None,
    };
    let expected = args.manifest_required.then(|| Expectation {
        asset_set: args.asset_set.as_str().to_owned(),
        schema: args.schema,
        content_version: args.content_version,
        content_sha256: (args.content_mode == 1).then(|| args.content_hash.as_str().to_owned()),
    });
    unsafe {
        args.asset_set.decref(roc_host());
        args.content_hash.decref(roc_host());
        args.root.decref(roc_host());
    }
    open_result(match root {
        None => Err(Failure::InvalidRoot),
        Some(root) => open_store(root, expected),
    })
}

fn read_bytes(handle: *mut u64, path: &str) -> Result<Vec<u8>, Failure> {
    let directory = lookup(handle)?;
    let parts = relative_components(path).ok_or(Failure::InvalidName)?;
    let (name, directories) = parts.split_last().expect("a resolved path has a last part");
    let holder = open_subdir_nofollow(&directory, directories).map_err(io_failure)?;
    read_child_bounded(&holder, name, MAX_ASSET_BYTES).map_err(|error| match error {
        ChildReadError::InvalidName => Failure::InvalidName,
        ChildReadError::NotFound => Failure::NotFound,
        ChildReadError::NotDirectory => Failure::NotDirectory,
        ChildReadError::AccessDenied => Failure::AccessDenied,
        ChildReadError::Unsupported => Failure::Unsupported,
        ChildReadError::ResourceLimit => Failure::ResourceLimit,
        ChildReadError::Io => Failure::Io,
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_assets_read(handle: *mut u64, path: RocStr) -> HostGlueAssetsReadResult {
    let owned = path.as_str().to_owned();
    unsafe { path.decref(roc_host()) };
    let result = read_bytes(handle, &owned);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    match result {
        Ok(bytes) => {
            record(READS, 1);
            record(BYTES_READ, bytes.len() as u64);
            HostGlueAssetsReadResult {
                payload: HostGlueAssetsReadResultPayload {
                    ok: ManuallyDrop::new(unsafe {
                        RocListWith::<u8, false>::from_slice(&bytes, roc_host())
                    }),
                },
                tag: HostGlueAssetsReadResultTag::Ok,
            }
        }
        Err(failure) => {
            record(READ_REFUSALS, 1);
            HostGlueAssetsReadResult {
                payload: HostGlueAssetsReadResultPayload {
                    err: ManuallyDrop::new(failure as u8),
                },
                tag: HostGlueAssetsReadResultTag::Err,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn expectation(sha: Option<&str>) -> Expectation {
        Expectation {
            asset_set: "gallery".into(),
            schema: 1,
            content_version: 7,
            content_sha256: sha.map(str::to_owned),
        }
    }

    const DIGEST: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    /// A throwaway directory tree. The repository pins its dependency set, so
    /// this leans on the standard library rather than adding a crate.
    struct Scratch(PathBuf);

    impl Scratch {
        fn new(label: &str) -> Self {
            static NEXT: AtomicU64 = AtomicU64::new(0);
            let path = std::env::temp_dir().join(format!(
                "roc-gui-assets-{}-{label}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            let _ = std::fs::remove_dir_all(&path);
            std::fs::create_dir_all(&path).expect("temporary directory");
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn fixture(label: &str) -> Scratch {
        let root = Scratch::new(label);
        std::fs::create_dir(root.path().join("banners")).expect("subdirectory");
        std::fs::write(root.path().join("banners/hero.png"), b"hero-bytes").expect("asset");
        root
    }

    fn open_at(root: &Path) -> Arc<Dir> {
        Arc::new(Dir::open_ambient_dir(root, ambient_authority()).expect("root"))
    }

    #[test]
    fn a_path_that_escapes_the_store_is_refused_rather_than_rewritten() {
        for escape in [
            "../outside.png",
            "banners/../../outside.png",
            "/etc/hosts",
            "./hero.png",
            "",
        ] {
            assert!(
                relative_components(escape).is_none(),
                "{escape} must not resolve"
            );
        }
        assert_eq!(
            relative_components("banners/hero.png"),
            Some(vec!["banners", "hero.png"])
        );
    }

    #[test]
    fn a_missing_asset_is_not_found_and_a_present_one_reads() {
        let root = fixture("read");
        let store = open_at(root.path());
        let parts = relative_components("banners/hero.png").expect("path");
        let (name, dirs) = parts.split_last().expect("last");
        let holder = open_subdir_nofollow(&store, dirs).expect("subdirectory");
        assert_eq!(
            read_child_bounded(&holder, name, MAX_ASSET_BYTES).ok(),
            Some(b"hero-bytes".to_vec())
        );
        assert!(matches!(
            read_child_bounded(&holder, "absent.png", MAX_ASSET_BYTES),
            Err(ChildReadError::NotFound)
        ));
    }

    #[test]
    fn an_asset_larger_than_the_bound_is_refused_before_it_is_returned() {
        let root = Scratch::new("bound");
        let path = root.path().join("big.bin");
        let mut file = std::fs::File::create(&path).expect("file");
        file.write_all(&[0u8; 4096]).expect("write");
        drop(file);
        let store = open_at(root.path());
        assert!(matches!(
            read_child_bounded(&store, "big.bin", 1024),
            Err(ChildReadError::ResourceLimit)
        ));
        assert!(read_child_bounded(&store, "big.bin", 4096).is_ok());
    }

    #[cfg(unix)]
    #[test]
    fn a_symbolic_link_inside_the_store_is_refused_rather_than_followed() {
        let root = Scratch::new("symlink");
        std::fs::write(root.path().join("real.png"), b"real").expect("asset");
        if std::os::unix::fs::symlink("real.png", root.path().join("link.png")).is_err() {
            return;
        }
        let store = open_at(root.path());
        assert!(matches!(
            read_child_bounded(&store, "link.png", MAX_ASSET_BYTES),
            Err(ChildReadError::Unsupported)
        ));
    }

    #[test]
    fn a_matching_manifest_opens_the_store() {
        let declared =
            parse_manifest("# gallery\nasset_set = gallery\nschema = 1\ncontent_version = 7\n")
                .expect("manifest");
        assert_eq!(declared.sha256, None);
        assert_eq!(check_manifest(&declared, &expectation(None)), Ok(()));

        let hashed = parse_manifest(&format!(
            "asset_set = gallery\nschema = 1\ncontent_version = 7\nsha256 = {DIGEST}\n"
        ))
        .expect("manifest");
        assert_eq!(check_manifest(&hashed, &expectation(Some(DIGEST))), Ok(()));
    }

    #[test]
    fn a_mismatched_manifest_names_the_declaration_that_disagreed() {
        let declared = parse_manifest(&format!(
            "asset_set = gallery\nschema = 1\ncontent_version = 7\nsha256 = {DIGEST}\n"
        ))
        .expect("manifest");
        assert_eq!(
            check_manifest(
                &declared,
                &Expectation {
                    asset_set: "icons".into(),
                    ..expectation(None)
                }
            ),
            Err(Failure::AssetSetMismatch)
        );
        assert_eq!(
            check_manifest(
                &declared,
                &Expectation {
                    schema: 2,
                    ..expectation(None)
                }
            ),
            Err(Failure::SchemaMismatch)
        );
        assert_eq!(
            check_manifest(
                &declared,
                &Expectation {
                    content_version: 8,
                    ..expectation(None)
                }
            ),
            Err(Failure::ContentVersionMismatch)
        );
        assert_eq!(
            check_manifest(&declared, &expectation(Some(&"a".repeat(64)))),
            Err(Failure::ContentHashMismatch)
        );
        let unhashed =
            parse_manifest("asset_set = gallery\nschema = 1\ncontent_version = 7\n").expect("m");
        assert_eq!(
            check_manifest(&unhashed, &expectation(Some(DIGEST))),
            Err(Failure::ContentHashMismatch)
        );
    }

    #[test]
    fn a_file_that_is_not_a_manifest_is_malformed_rather_than_partly_understood() {
        for text in [
            "asset_set = gallery\nschema = 1\n",
            "asset_set = gallery\nschema = one\ncontent_version = 7\n",
            "asset_set = gallery\nschema = 1\ncontent_version = 7\nextra = 1\n",
            "asset_set = gallery\nasset_set = icons\nschema = 1\ncontent_version = 7\n",
            "asset_set = gallery\nschema = 1\ncontent_version = 7\nsha256 = abc\n",
            "not a pair\n",
        ] {
            assert_eq!(
                parse_manifest(text),
                Err(Failure::ManifestMalformed),
                "{text}"
            );
        }
    }

    #[test]
    fn a_missing_manifest_fails_the_open_rather_than_a_later_read() {
        let root = fixture("manifest");
        let store = open_at(root.path());
        assert_eq!(
            verify_manifest(&store, &expectation(None)),
            Err(Failure::ManifestMissing)
        );
        std::fs::write(
            root.path().join(MANIFEST_NAME),
            "asset_set = gallery\nschema = 1\ncontent_version = 7\n",
        )
        .expect("manifest");
        assert_eq!(verify_manifest(&store, &expectation(None)), Ok(()));
    }

    #[test]
    fn an_unusable_expectation_is_answered_before_any_file_is_touched() {
        assert_eq!(
            open_store(
                Root::WorkingDirectory("assets".into()),
                Some(expectation(Some("not-a-digest")))
            ),
            Err(Failure::InvalidExpectation)
        );
    }

    #[test]
    fn a_root_that_escapes_its_base_is_refused_and_content_needs_provisioning() {
        assert_eq!(
            open_store(Root::BesideExecutable("../..".into()), None),
            Err(Failure::InvalidRoot)
        );
        assert_eq!(
            open_store(Root::BesideExecutable("/etc".into()), None),
            Err(Failure::InvalidRoot)
        );
        assert_eq!(
            open_store(Root::BesideExecutable(String::new()), None),
            Err(Failure::InvalidRoot)
        );
        assert_eq!(
            root_base(&Root::ContentDirectory),
            Err(Failure::AccessDenied)
        );
    }
}
