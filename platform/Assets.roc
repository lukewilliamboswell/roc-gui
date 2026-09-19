## Read-only access to the artwork an application ships with itself.
##
## An asset store is the third kind of file access this platform offers, and it
## is the narrowest. `Files.pick_directory!` is user data reached through a
## trusted chooser. `Files.app_data!` is private read-write durable state. An
## asset store is neither: it is the application's own shipped, read-only
## content -- a banner, a photograph, a sound of its own making -- so it is
## provisioned automatically and asks the person using the application for
## nothing.
##
## Small artwork does not need this module at all. A compile-time file import
## places the bytes in the executable, and `Elem.image` renders them:
##
## ```roc
## import "icons/folder.png" as folder : List(U8)
##
## icon = Elem.image(Elem.ImageProps.{ label: "Folder", bytes: folder, format: Png })
## ```
##
## This module is for the larger asset that should not be paid for in
## executable size: open a store once, read the file when the application wants
## it, and hand the bytes to the same `Elem.image`.
##
## Opening a store and reading an asset both touch the disk, so both belong in
## `Action.task`, which runs them on a worker thread and resolves on the UI
## thread. A renderer is pure and an event handler runs on the UI thread;
## neither is a place for a blocking read.
##
## ```roc
## Action.task({
##     pending: { ..state, banner: Loading },
##     run: || {
##         store = Assets.open!(Assets.beside_executable("assets"))?
##         store.read!("banners/hero.png")
##     },
##     resolve: |latest, result| match result {
##         Ok(bytes) => Action.update({ ..latest, banner: Loaded(bytes) })
##         Err(_) => Action.update({ ..latest, banner: Failed })
##     },
## })
## ```
import Host
import Resource

Assets := [].{

	## An opened asset store: an opaque handle to one directory the host holds
	## open. Every read is made through that handle rather than through the
	## process working directory, which the host never changes.
	Store := Resource.AssetStore.{

		## The resource-free store value, for pure tests. It lets an application
		## that keeps a store in its state write that state down in an `expect`.
		## Reads through it fail; it proves nothing about asset resolution.
		stub : Store
		stub = Store.(Resource.asset_store_stub)

		## Read one asset's bytes, relative to the store's root. Call it from
		## `Action.task`; it blocks on the disk.
		##
		## `path` may name a file in a subdirectory, written with `/`
		## separators. `InvalidName` is a path that is absolute, empty, holds a
		## NUL, or contains a `.` or `..` component, and is answered before any
		## file is touched. `NotFound` is no such file beneath the root,
		## `Unsupported` is an entry that is a symbolic link or is not a regular
		## file, and `ResourceLimit` is a file larger than the host reads into
		## one value.
		read! : Store, Str => Try(List(U8), AssetErr)
		read! = |Store.(handle), path| Host.assets_read!(handle, path).map_err(|code| ReadAssetErr(decode_reason(code)))
	}

	## Where a store's root is. The three choices are separate names because
	## moving an executable, changing the working directory, and installing
	## content apart from the program are three different events, and none of
	## them may silently change what another one means.
	Root : [BesideExecutable(Str), WorkingDirectory(Str), ContentDirectory]

	## What content a manifest must declare. `AnyContent` leaves it open, which
	## is what a directory of loose files under development wants. `Sha256`
	## carries the 64-character lowercase hexadecimal digest the manifest must
	## declare.
	Content : [AnyContent, Sha256(Str)]

	## What a required manifest has to say: which asset set it describes, which
	## schema version it was written to, which content version it is, and which
	## content it declares.
	Manifest : { asset_set : Str, schema : U32, content_version : U32, content : Content }

	## Whether opening a store reads the `roc-assets.manifest` file at its root.
	## `IgnoreManifest` does not look. `RequireManifest` fails the open unless
	## the manifest is present and agrees with the expectation, so a
	## half-updated or mismatched asset set is reported at startup instead of
	## surfacing much later as one image that will not draw.
	ManifestPolicy : [IgnoreManifest, RequireManifest(Manifest)]

	## Where a store's root is and whether its manifest is checked. Build one
	## with `beside_executable`, `working_directory`, or `content_directory`,
	## and add an expectation with `with_manifest`.
	StoreConfig : { root : Root, manifest : ManifestPolicy }

	## A stable, portable category for an asset failure.
	Reason : [
		AccessDenied,
		AssetSetMismatch,
		ContentHashMismatch,
		ContentVersionMismatch,
		InvalidCapability,
		InvalidExpectation,
		InvalidName,
		InvalidRoot,
		Io,
		ManifestMalformed,
		ManifestMissing,
		ManifestUnreadable,
		NotDirectory,
		NotFound,
		ResourceLimit,
		Revoked,
		SchemaMismatch,
		Unavailable,
		Unsupported,
	]

	## An asset failure. The tag identifies the operation that failed.
	AssetErr : [OpenStoreErr(Reason), ReadAssetErr(Reason)]

	## Root the store at a directory beside the executable. This is the
	## packaged-application choice: the artwork travels with the program, so
	## the store resolves the same way however the program was launched.
	## `path` is relative to the executable's directory and may not escape it.
	beside_executable : Str -> StoreConfig
	beside_executable = |path| { root: BesideExecutable(path), manifest: IgnoreManifest }

	## Root the store at a directory relative to the process working directory.
	## This is what running an application from a project checkout wants: the
	## root follows the shell rather than the executable. `path` is relative to
	## the working directory and may not escape it.
	working_directory : Str -> StoreConfig
	working_directory = |path| { root: WorkingDirectory(path), manifest: IgnoreManifest }

	## Root the store at the content directory the host provisioned for this
	## application. This is the installed-layout choice, where the artwork lives
	## apart from the program. The application names no path: an asset store is
	## never a way to reach a directory the host did not hand it. Without a
	## provisioned content directory the open reports `AccessDenied`.
	content_directory : StoreConfig
	content_directory = { root: ContentDirectory, manifest: IgnoreManifest }

	## Require this store's `roc-assets.manifest` to match an expectation.
	##
	## The comparison is against the manifest's own declarations. Nothing walks
	## or hashes the files beneath the root, so opening a store costs the same
	## whether it holds one asset or ten thousand.
	with_manifest : StoreConfig, Manifest -> StoreConfig
	with_manifest = |config, expected| { ..config, manifest: RequireManifest(expected) }

	## Open the store a config describes, checking its manifest if one was
	## required. Call it from `Action.task`; it blocks on the disk.
	##
	## `InvalidRoot` is a root path this host will not accept -- an absolute
	## path, one holding a NUL, or a relative form that escapes its base.
	## `NotFound`, `NotDirectory`, and `AccessDenied` describe the root itself.
	## `ManifestMissing`, `ManifestUnreadable`, and `ManifestMalformed` describe
	## a required manifest that is absent, unreadable, or not a manifest.
	## `AssetSetMismatch`, `SchemaMismatch`, `ContentVersionMismatch`, and
	## `ContentHashMismatch` are the four comparisons that can disagree.
	## `InvalidExpectation` is an expectation this host cannot use, such as a
	## `Sha256` string that is not 64 hexadecimal characters.
	open! : Resource.Access, StoreConfig => Try(Store, AssetErr)
	open! = |_access, config| Host.assets_open!(encode_config(config)).map_ok(|handle| Store.(handle)).map_err(|code| OpenStoreErr(decode_reason(code)))

	encode_config : StoreConfig -> { root_kind : U8, root : Str, manifest_required : Bool, asset_set : Str, schema : U32, content_version : U32, content_mode : U8, content_hash : Str }
	encode_config = |config| {
		root = match config.root {
			BesideExecutable(path) => { kind: 0.U8, path }
			WorkingDirectory(path) => { kind: 1.U8, path }
			ContentDirectory => { kind: 2.U8, path: "" }
		}
		manifest = match config.manifest {
			IgnoreManifest => { required: Bool.False, asset_set: "", schema: 0.U32, content_version: 0.U32, mode: 0.U8, hash: "" }
			RequireManifest(expected) => {
				content = match expected.content {
					AnyContent => { mode: 0.U8, hash: "" }
					Sha256(hash) => { mode: 1.U8, hash }
				}
				{
					required: Bool.True,
					asset_set: expected.asset_set,
					schema: expected.schema,
					content_version: expected.content_version,
					mode: content.mode,
					hash: content.hash,
				}
			}
		}
		{
			root_kind: root.kind,
			root: root.path,
			manifest_required: manifest.required,
			asset_set: manifest.asset_set,
			schema: manifest.schema,
			content_version: manifest.content_version,
			content_mode: manifest.mode,
			content_hash: manifest.hash,
		}
	}

	decode_reason = |code| match code {
		0 => AccessDenied
		1 => InvalidCapability
		2 => InvalidRoot
		3 => InvalidName
		4 => NotFound
		5 => NotDirectory
		6 => Io
		7 => ResourceLimit
		8 => Unsupported
		9 => ManifestMissing
		10 => ManifestUnreadable
		11 => ManifestMalformed
		12 => AssetSetMismatch
		13 => SchemaMismatch
		14 => ContentVersionMismatch
		15 => ContentHashMismatch
		16 => InvalidExpectation
		18 => Revoked
		_ => Unavailable
	}

	expect encode_config(beside_executable("assets")).root_kind == 0
	expect encode_config(working_directory("assets")).root_kind == 1
	expect encode_config(content_directory).root_kind == 2
	expect encode_config(beside_executable("assets")).manifest_required == Bool.False
	expect encode_config(with_manifest(beside_executable("assets"), { asset_set: "gallery", schema: 1, content_version: 7, content: AnyContent })).manifest_required
	expect encode_config(with_manifest(beside_executable("assets"), { asset_set: "gallery", schema: 1, content_version: 7, content: AnyContent })).content_version == 7
	expect encode_config(with_manifest(beside_executable("assets"), { asset_set: "gallery", schema: 1, content_version: 7, content: Sha256("00") })).content_mode == 1
}
