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
		ReadFileErr(Reason),
		WriteFileErr(Reason),
	]

	## One direct child, spelled as the host exchanges it.
	Entry : { name : Str, kind : [Directory, File, Other, SymbolicLink], bytes : [None, Some(U64)] }

	pick_directory! : () => Try([Canceled, Chosen({ name : Str, directory : Resource.DirRead })], FileErr)
	dir_list! : Resource.DirRead => Try(List(Entry), FileErr)
	dir_open_read! : Resource.DirRead, Str => Try(Resource.DirRead, FileErr)
	dir_read! : Resource.DirRead, Str => Try(List(U8), FileErr)

	app_data! : () => Try(Resource.DirReadWrite, { code : U8, message : Str })
	read_utf8! : Resource.DirReadWrite, Str => Try({ found : Bool, value : Str }, { code : U8, message : Str })
	write_utf8_atomic! : Resource.DirReadWrite, Str, Str => Try({}, { code : U8, message : Str })
}
