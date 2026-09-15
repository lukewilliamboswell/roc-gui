## Host-provisioned directory capabilities. Interactive hosts source project
## grants from trusted selection; development and automation may provision the
## same registry explicitly. Every later operation requires the opaque handle.

import InternalFiles
import Resource

Files := [].{

	## The result of acquiring a provisioned selection. Canceling is successful.
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
		Revoked,
		Unavailable,
		Unsupported,
	]

	## A filesystem failure. The tag identifies the operation that failed, so
	## callers can handle operation-specific failures directly.
	FileErr : [
		OpenAppDataErr(Reason),
		ListDirectoryErr(Reason),
		OpenReadDirectoryErr(Reason),
		PickDirectoryErr(Reason),
		ReadFileErr(Reason),
		WriteFileErr(Reason),
	]

	## Operations requiring read authority for a particular directory.
	Dir := [].{

		## An opaque, typed handle granting read access to one directory. It can be
		## retained in application state and cannot be constructed by applications.
		Read : Resource.DirRead
		ReadWrite : Resource.DirReadWrite
		ReadUtf8 : [Missing, Value(Str)]

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

		## Read one bounded UTF-8 direct child.
		read_utf8! : Resource.DirReadWrite, Str => Try(ReadUtf8, FileErr)
		read_utf8! = |directory, name| InternalFiles.read_utf8!(directory, name).map_ok(|raw| if raw.found Value(raw.value) else Missing).map_err(|raw| ReadFileErr(decode_reason(raw.code)))

		## Durably replace one bounded UTF-8 direct child using an atomic rename.
		write_utf8_atomic! : Resource.DirReadWrite, Str, Str => Try({}, FileErr)
		write_utf8_atomic! = |directory, name, value| InternalFiles.write_utf8_atomic!(directory, name, value).map_err(|raw| WriteFileErr(decode_reason(raw.code)))
	}

	## Acquire the read-only project grant provisioned by the host. This function
	## does not display trusted UI; interactive hosts must source the grant from
	## trusted selection. Without a provisioned grant it returns `AccessDenied`.
	pick_directory! : () => Try(Choice(Selection), FileErr)

	## Acquire the private read-write application-data directory granted by the host.
	app_data! : () => Try(Resource.DirReadWrite, FileErr)
	app_data! = || InternalFiles.app_data!().map_err(|raw| OpenAppDataErr(decode_reason(raw.code)))

	decode_reason = |code| match code {
		0 => AccessDenied
		1 => InvalidCapability
		2 => InvalidName
		3 => Io
		4 => ResourceLimit
		6 => Revoked
		_ => Unavailable
	}
}
