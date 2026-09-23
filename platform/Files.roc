## Host-provisioned directory and file capabilities. Interactive hosts source
## project and document grants from trusted selection; development and
## automation may provision the same registry explicitly. Every later operation
## requires the opaque handle.

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
		PickFileErr(Reason),
		ReadFileErr(Reason),
		WatchDirectoryErr(Reason),
		WriteFileErr(Reason),
	]

	## What one wait on a watch resolved to. `Changed` reports a change; the
	## others end the watch, and every later wait answers the same.
	##
	## * `Changed`: what the watch covers changed. `names` are the names that
	##   changed since the previous wait, each once: the direct children of a
	##   watched directory that were created, removed, renamed, or written, or
	##   a watched database's own name. `replaced` is set when one of them may
	##   now refer to a different file, because a file was renamed over it or
	##   it was removed or created; reopen it to read what it names now.
	##   `overflowed` is set when more changed than a wait can name, and then
	##   `names` is incomplete.
	## * `Canceled`: the watch was cancelled, or released, or what it watches
	##   was released.
	## * `Revoked`: the grant it was derived from was withdrawn.
	## * `Gone`: the watched directory itself was removed or moved away, so no
	##   later change can be reported.
	Change : [Canceled, Changed(Changes), Gone, Revoked]

	## The names one `Changed` wait reports.
	Changes : { names : List(Str), replaced : Bool, overflowed : Bool }

	## An opaque, cancellable subscription to changes of a granted directory or
	## database. Changes are coalesced rather than queued: one wait reports every
	## change since the previous wait returned, once writing has paused briefly,
	## so a watch holds no backlog however fast its files are written. It is
	## derived from what it watches, so withdrawing that grant, or releasing
	## what it watches, ends it.
	Watch := Resource.Watch.{

		## Wait for the next change. Call from `Action.task`; exactly one wait
		## may be outstanding, and cancelling wakes it with `Canceled`.
		next! : Watch => Change
		next! = |Watch.(handle)| {
			raw = InternalFiles.watch_next!(handle)
			match raw.code {
				0 => Changed({ names: raw.names, replaced: raw.replaced, overflowed: raw.overflowed })
				3 => Revoked
				4 => Gone
				_ => Canceled
			}
		}

		## Stop this watch. Cancellation is idempotent.
		cancel! : Watch => [AlreadyStopped, Canceled]
		cancel! = |Watch.(handle)| if InternalFiles.watch_cancel!(handle) Canceled else AlreadyStopped

		## Wrap the shared representation, for the platform's own modules that
		## derive a watch, as `Sqlite` does. An application cannot produce the
		## representation, so this grants nothing.
		from_resource : Resource.Watch -> Watch
		from_resource = |handle| Watch.(handle)
	}

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

			## The SHA-256 digest of one direct ordinary child file, as 64
			## lowercase hexadecimal digits. The host streams the file without
			## following links, so no byte of it becomes an application value;
			## a file over the host's hash bound answers `ResourceLimit`.
			sha256! : Read, Str => Try(Str, FileErr)
			sha256! = |Read.(handle), name| InternalFiles.dir_sha256!(handle, name)

			## Watch this directory's direct children: a child created,
			## removed, renamed, or written is reported by name in a `Changed`
			## wait. The watch is derived from this grant, and nothing beneath
			## a child directory is reported.
			watch! : Read => Try(Watch, FileErr)
			watch! = |Read.(handle)| InternalFiles.dir_watch!(handle).map_ok(|watch| Watch.(watch)).map_err(|raw| WatchDirectoryErr(decode_watch_reason(raw.code)))

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

	## Operations requiring read authority for one particular file.
	File := [].{

		## An opaque, typed handle granting read access to exactly one file. It
		## names no directory, so it reveals no sibling, and it can be retained
		## in application state but not constructed by applications.
		Read := Resource.FileRead.{

			## Read the whole file. Reads are bounded by the host and return
			## `ResourceLimit` when the file is too large for one in-memory
			## value.
			read! : Read => Try(List(U8), FileErr)
			read! = |Read.(handle)| InternalFiles.file_read!(handle)

			## The SHA-256 digest of the file, as 64 lowercase hexadecimal
			## digits, streamed by the host under the same bound as a
			## directory's `sha256!`.
			sha256! : Read => Try(Str, FileErr)
			sha256! = |Read.(handle)| InternalFiles.file_sha256!(handle)

			## The shared representation behind this handle, for the platform's
			## own modules, as `Sqlite` uses it. It grants nothing an
			## application can act on.
			resource : Read -> Resource.FileRead
			resource = |Read.(handle)| handle

			## Wrap the shared representation, for the platform's own modules
			## that hand a file to an application, as a drop target does. An
			## application cannot produce the representation, so this grants
			## nothing.
			from_resource : Resource.FileRead -> Read
			from_resource = |handle| Read.(handle)
		}
	}

	## A chosen directory's display name and read authority.
	Selection : { name : Str, directory : Dir.Read }

	## A chosen file's display name and read authority.
	FileSelection : { name : Str, file : File.Read }

	## One kind of file the chooser offers. `extensions` are written without a
	## leading dot, such as `"rgstats"`; `mime_types` are full types such as
	## `"application/vnd.sqlite3"`. The host checks a chosen file against the
	## extensions of every type offered, so a file of any other extension is
	## refused with `PickFileErr(Unsupported)` whichever chooser produced it.
	FileType : { label : Str, extensions : List(Str), mime_types : List(Str) }

	## Acquire the read-only project grant provisioned by the host. This function
	## does not display trusted UI; interactive hosts must source the grant from
	## trusted selection. Without a provisioned grant it returns `AccessDenied`.
	pick_directory! : Resource.Access => Try(Choice(Selection), FileErr)
	pick_directory! = |_access| InternalFiles.pick_directory!().map_ok(
		|choice| match choice {
			Canceled => Canceled
			Chosen(selection) => Chosen({ name: selection.name, directory: Dir.Read.(selection.directory) })
		},
	)

	## Acquire a read-only grant for one file the person chooses, offering only
	## `types`. An empty list offers every file. Without trusted selection or a
	## provisioned file it returns `AccessDenied`.
	pick_file! : Resource.Access, List(FileType) => Try(Choice(FileSelection), FileErr)
	pick_file! = |_access, types| InternalFiles.pick_file!(types).map_ok(
		|choice| match choice {
			Canceled => Canceled
			Chosen(selection) => Chosen({ name: selection.name, file: File.Read.(selection.file) })
		},
	)

	## Why a remembered file or folder cannot be reopened, or a grant cannot
	## be remembered.
	##
	## * `AccessDenied`: the application may no longer read it.
	## * `Forgotten`: no recent entry has this key, because it was forgotten
	##   or the list outgrew its bound.
	## * `Missing`: nothing is at its place any more.
	## * `Replaced`: something else is at its place now: another file renamed
	##   over it, or a folder where a file was. It is not what was chosen.
	## * `Revoked`: the grant being remembered was withdrawn.
	## * `Unreadable`: it could not be reached for another reason.
	## * `Unsupported`: only a file or folder a person chose, dropped, or was
	##   provisioned can be remembered, not one derived from another grant.
	Unavailable : [AccessDenied, Forgotten, Missing, Replaced, Revoked, Unreadable, Unsupported]

	## One file or folder the application remembered, most recent first.
	## `key` names it for `reopen_file!`, `reopen_directory!`, and
	## `forget_recent!`, and stays the same across restarts. `status` is what
	## the host found when the list was read: whether it can be reopened now.
	## No path is ever part of an entry.
	Recent : { key : U64, name : Str, kind : [Directory, File], status : [Available, Unavailable(Unavailable)] }

	## The application's recent files and folders, most recent first, each
	## checked against what is at its place now.
	recent! : Resource.Access => List(Recent)
	recent! = |_access| InternalFiles.recent!().map(
		|raw| {
			kind = if raw.directory Directory else File
			status = if raw.status == 0 Available else Unavailable(decode_unavailable(raw.status))
			{ key: raw.key, name: raw.name, kind, status }
		},
	)

	## Reopen a remembered file as a new read-only grant, after the host
	## checks it is still the file that was remembered.
	reopen_file! : Resource.Access, U64 => Try(FileSelection, Unavailable)
	reopen_file! = |_access, key| match InternalFiles.reopen_file!(key) {
		Ok(chosen) => Ok({ name: chosen.name, file: File.Read.(chosen.file) })
		Err(raw) => Err(decode_unavailable(raw.code))
	}

	## Reopen a remembered folder as a new read-only grant, after the host
	## checks it is still the folder that was remembered.
	reopen_directory! : Resource.Access, U64 => Try(Selection, Unavailable)
	reopen_directory! = |_access, key| match InternalFiles.reopen_directory!(key) {
		Ok(chosen) => Ok({ name: chosen.name, directory: Dir.Read.(chosen.directory) })
		Err(raw) => Err(decode_unavailable(raw.code))
	}

	## Remove one entry from the recent list. Its grants held this session
	## are not withdrawn. `Forgotten` when no entry has the key.
	forget_recent! : Resource.Access, U64 => Try({}, Unavailable)
	forget_recent! = |_access, key| if InternalFiles.forget_recent!(key) Ok({}) else Err(Forgotten)

	## Remember a chosen or dropped file, so it is listed by `recent!` in this
	## and later runs until it is forgotten or withdrawn.
	remember_file! : Resource.Access, File.Read => Try({}, Unavailable)
	remember_file! = |_access, file| decode_remembered(InternalFiles.remember_file!(File.Read.resource(file)))

	## Remember a chosen folder, as `remember_file!` remembers a file.
	remember_directory! : Resource.Access, Dir.Read => Try({}, Unavailable)
	remember_directory! = |_access, directory| decode_remembered(InternalFiles.remember_directory!(Dir.Read.resource(directory)))

	decode_remembered = |code| if code == 0 Ok({}) else Err(decode_unavailable(code))

	decode_unavailable = |code| match code {
		1 => AccessDenied
		2 => Forgotten
		3 => Missing
		4 => Replaced
		5 => Revoked
		7 => Unsupported
		_ => Unreadable
	}

	## Acquire the private read-write application-data directory granted by the host.
	app_data! : Resource.Access => Try(Dir.ReadWrite, FileErr)
	app_data! = |_access| InternalFiles.app_data!().map_ok(|handle| Dir.ReadWrite.(handle)).map_err(|raw| OpenAppDataErr(decode_reason(raw.code)))

	decode_watch_reason = |code| match code {
		0 => AccessDenied
		1 => InvalidCapability
		3 => Io
		4 => ResourceLimit
		6 => Revoked
		9 => Unsupported
		_ => Unavailable
	}

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
