## Private ABI declarations for directory operations. Applications use the
## operation-tagged surface in `Files`, whose handles are typed nominals; these
## declarations carry the shared `Resource` representation the host exchanges.
import Resource

InternalFiles := [].{

	## The portable failure categories, spelled as the host exchanges them.
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

	## The operation-tagged failure, spelled as the host exchanges it.
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

	## One direct child, spelled as the host exchanges it.
	Entry : { name : Str, kind : [Directory, File, Other, SymbolicLink], bytes : [None, Some(U64)] }

	pick_directory! : () => Try([Canceled, Chosen({ name : Str, directory : Resource.DirRead })], FileErr)
	dir_list! : Resource.DirRead => Try(List(Entry), FileErr)
	dir_open_read! : Resource.DirRead, Str => Try(Resource.DirRead, FileErr)
	dir_read! : Resource.DirRead, Str => Try(List(U8), FileErr)
	dir_sha256! : Resource.DirRead, Str => Try(Str, FileErr)
	dir_watch! : Resource.DirRead => Try(Resource.Watch, { code : U8, message : Str })
	watch_next! : Resource.Watch => { code : U8, names : List(Str), overflowed : Bool, replaced : Bool }
	watch_cancel! : Resource.Watch => Bool

	## One offered file type, spelled as the host exchanges it.
	FileType : { label : Str, extensions : List(Str), mime_types : List(Str) }

	pick_file! : List(FileType) => Try([Canceled, Chosen({ name : Str, file : Resource.FileRead })], FileErr)
	file_read! : Resource.FileRead => Try(List(U8), FileErr)
	file_sha256! : Resource.FileRead => Try(Str, FileErr)

	## One remembered file or folder, spelled as the host exchanges it.
	## `status` is 0 when it can be reopened, otherwise the code of the reason
	## it cannot, as `Files.decode_unavailable` reads it.
	recent! : () => List({ key : U64, name : Str, directory : Bool, status : U8 })
	reopen_file! : U64 => Try({ name : Str, file : Resource.FileRead }, { code : U8 })
	reopen_directory! : U64 => Try({ name : Str, directory : Resource.DirRead }, { code : U8 })
	forget_recent! : U64 => Bool
	remember_file! : Resource.FileRead => U8
	remember_directory! : Resource.DirRead => U8

	app_data! : () => Try(Resource.DirReadWrite, { code : U8, message : Str })
	read_utf8! : Resource.DirReadWrite, Str => Try({ found : Bool, value : Str }, { code : U8, message : Str })
	write_utf8_atomic! : Resource.DirReadWrite, Str, Str => Try({}, { code : U8, message : Str })
}
