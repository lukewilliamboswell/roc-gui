## Host-provisioned directory capabilities. Interactive hosts source project
## grants from trusted selection; development and automation may provision the
## same registry explicitly. Every later operation requires the opaque handle.

import InternalFiles
import Resource

Files := [].{

	## The result of acquiring a provisioned selection. Canceling is successful.
	Choice(a) : [Canceled, Chosen(a)]

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

		## An opaque, typed handle granting read access to one directory. It can
		## be retained in application state and cannot be constructed by
		## applications.
		Read := Resource.DirRead.{

			## List direct children without following symbolic links. Results
			## are bounded by the host's entry and metadata limits.
			list! : Read => Try(List(Entry), FileErr)
			list! = |Read.(handle)| InternalFiles.dir_list!(handle)

			## Acquire one direct ordinary child directory as a new read handle.
			## `name` must be a single ordinary entry name; traversal and links
			## are rejected.
			open_dir! : Read, Str => Try(Read, FileErr)
			open_dir! = |Read.(handle), name| InternalFiles.dir_open_read!(handle, name).map_ok(|child| Read.(child))

			## Read one direct ordinary child file without following symbolic
			## links. Reads are bounded by the host and return `ResourceLimit`
			## when the file is too large for one in-memory value.
			read! : Read, Str => Try(List(U8), FileErr)
			read! = |Read.(handle), name| InternalFiles.dir_read!(handle, name)

			## The shared representation behind this handle. It is the seam the
			## platform's own modules use to hand a directory to the host, as
			## `Sqlite` and `Audio` do. The representation is itself opaque, so
			## it grants nothing an application can act on.
			resource : Read -> Resource.DirRead
			resource = |Read.(handle)| handle
		}

		## An opaque, typed handle granting read and write access to one
		## directory. Only the host's private application-data directory is
		## reached this way.
		ReadWrite := Resource.DirReadWrite.{

			## Read one bounded UTF-8 direct child.
			read_utf8! : ReadWrite, Str => Try(ReadUtf8, FileErr)
			read_utf8! = |ReadWrite.(handle), name| InternalFiles.read_utf8!(handle, name).map_ok(|raw| if raw.found Value(raw.value) else Missing).map_err(|raw| ReadFileErr(decode_reason(raw.code)))

			## Durably replace one bounded UTF-8 direct child using an atomic
			## rename.
			write_utf8_atomic! : ReadWrite, Str, Str => Try({}, FileErr)
			write_utf8_atomic! = |ReadWrite.(handle), name, value| InternalFiles.write_utf8_atomic!(handle, name, value).map_err(|raw| WriteFileErr(decode_reason(raw.code)))
		}

		ReadUtf8 : [Missing, Value(Str)]
	}

	## A chosen directory's display name and read authority.
	Selection : { name : Str, directory : Dir.Read }

	## Acquire the read-only project grant provisioned by the host. This function
	## does not display trusted UI; interactive hosts must source the grant from
	## trusted selection. Without a provisioned grant it returns `AccessDenied`.
	pick_directory! : () => Try(Choice(Selection), FileErr)
	pick_directory! = || InternalFiles.pick_directory!().map_ok(
		|choice| match choice {
			Canceled => Canceled
			Chosen(selection) => Chosen({ name: selection.name, directory: Dir.Read.(selection.directory) })
		},
	)

	## Acquire the private read-write application-data directory granted by the host.
	app_data! : () => Try(Dir.ReadWrite, FileErr)
	app_data! = || InternalFiles.app_data!().map_ok(|handle| Dir.ReadWrite.(handle)).map_err(|raw| OpenAppDataErr(decode_reason(raw.code)))

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
