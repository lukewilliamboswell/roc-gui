## Host-granted, read-only directory capabilities. Acquisition is an ambient,
## host-gated powerbox; every filesystem operation afterward requires the
## opaque directory handle it returned.

import Resource

Files := [].{

	## The result of a user-facing chooser. Canceling is a successful outcome.
	Choice(a) : [Canceled, Chosen(a)]

	## A chosen directory's display name and read authority.
	Selection : { name : Str, directory : Resource.DirRead }

	## The kind of one directory entry. Symbolic links are reported, not followed.
	Kind : [Directory, File, Other, SymbolicLink]

	## One direct child. `bytes` is present for regular files when metadata is
	## available and absent for directories and other entries.
	Entry : { name : Str, kind : Kind, bytes : [None, Some(U64)] }

	## A stable, portable category for a filesystem failure.
	Reason : [
		AccessDenied,
		InvalidCapability,
		InvalidName,
		InvalidUtf8,
		Io,
		NotDirectory,
		NotFound,
		ResourceLimit,
		Unavailable,
		Unsupported,
	]

	## A filesystem failure. The tag identifies the operation that failed, so
	## callers can handle operation-specific failures directly.
	FileErr : [
		ListDirectoryErr(Reason),
		OpenReadDirectoryErr(Reason),
		PickDirectoryErr(Reason),
		ReadFileErr(Reason),
	]

	## Operations requiring read authority for a particular directory.
	Dir := [].{

		## An opaque, typed handle granting read access to one directory. It can be
		## retained in application state and cannot be constructed by applications.
		Read : Resource.DirRead

		## List direct children without following symbolic links. Results are
		## bounded by the host's entry and metadata limits.
		list! : Resource.DirRead => Try(List(Entry), FileErr)

		## Acquire one direct ordinary child directory as a new read handle. `name`
		## must be a single ordinary entry name; traversal and links are rejected.
		open_read_dir! : Resource.DirRead, Str => Try(Resource.DirRead, FileErr)

		## Read one direct ordinary child file without following symbolic links.
		## Reads are bounded by the host and return `ResourceLimit` when the file is
		## too large for one in-memory value.
		read! : Resource.DirRead, Str => Try(List(U8), FileErr)
	}

	## Acquire the directory handle granted when the application was launched.
	## Without a `--host-cap-dir PATH` grant this returns `AccessDenied`.
	pick_directory! : {} => Try(Choice(Selection), FileErr)
}
