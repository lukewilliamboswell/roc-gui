## Private ABI records for application-data directory operations. Applications
## use the operation-tagged surface in `Files`.
import Resource

InternalFiles := [].{
	app_data! : () => Try(Resource.DirReadWrite, { code : U8, message : Str })
	read_utf8! : Resource.DirReadWrite, Str => Try({ found : Bool, value : Str }, { code : U8, message : Str })
	write_utf8_atomic! : Resource.DirReadWrite, Str, Str => Try({}, { code : U8, message : Str })
}
