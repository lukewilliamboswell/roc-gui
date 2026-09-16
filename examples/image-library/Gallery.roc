import pf.Elem
import pf.Files
import pf.ImageData

Gallery := [].{
	Asset : { bytes : List(U8), format : Elem.ImageFormat, height : U32, name : Str, width : U32 }
	Item : [Failed({ name : Str, reason : Str }), Ready(Asset)]
	Scan : { items : List(Item) }
	format_for : Str -> Try(Elem.ImageFormat, [Unsupported])
	format_for = format_for
	scan! : Files.Dir.Read, List(Files.Entry) => Scan
	scan! = scan!
	visible : List(Item), Str -> List(Item)
	visible = |items, query| items.keep_if(|item| Str.is_empty(query) or Str.contains(name(item), query))
	name : Item -> Str
	name = name
}

name = |item| match item { Ready(asset) => asset.name, Failed(failure) => failure.name }

format_for = |file_name| if file_name.ends_with(".png") { Ok(Png) } else if file_name.ends_with(".jpg") or file_name.ends_with(".jpeg") { Ok(Jpeg) } else if file_name.ends_with(".gif") { Ok(Gif) } else if file_name.ends_with(".webp") { Ok(Webp) } else if file_name.ends_with(".svg") { Ok(Svg) } else if file_name.ends_with(".bmp") { Ok(Bmp) } else if file_name.ends_with(".tif") or file_name.ends_with(".tiff") { Ok(Tiff) } else { Err(Unsupported) }

scan! = |directory, entries| {
	var $items = []
	for entry in entries {
		if entry.kind == File {
			match format_for(entry.name) {
				Err(_) => { $items = $items.append(Failed({ name: entry.name, reason: "Unsupported format" })) }
				Ok(format) => match directory.read!(entry.name) {
					Err(_) => { $items = $items.append(Failed({ name: entry.name, reason: "Read failed" })) }
					Ok(bytes) => match ImageData.inspect!(bytes, format) {
						Err(InspectImageErr(Corrupt)) => { $items = $items.append(Failed({ name: entry.name, reason: "Corrupt image" })) }
						Err(InspectImageErr(InvalidDimensions)) => { $items = $items.append(Failed({ name: entry.name, reason: "Invalid dimensions" })) }
						Err(InspectImageErr(ResourceLimit)) => { $items = $items.append(Failed({ name: entry.name, reason: "Image exceeds safety limits" })) }
						Err(InspectImageErr(Unsupported)) => { $items = $items.append(Failed({ name: entry.name, reason: "Unsupported format" })) }
						Ok(metadata) => { $items = $items.append(Ready({ bytes, format, height: metadata.height, name: entry.name, width: metadata.width })) }
					}
				}
			}
		}
	}
	{ items: $items }
}
