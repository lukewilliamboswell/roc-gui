import Host
import Elem

## Bounded metadata and integrity inspection for encoded bytes already obtained
## through an explicit capability. This module never accepts a path or URL.
ImageData := [].{
	Metadata : { height : U32, width : U32 }
	Reason : [Corrupt, InvalidDimensions, ResourceLimit, Unsupported]
	ImageErr : [InspectImageErr(Reason)]

	inspect! : List(U8), Elem.ImageFormat => Try(Metadata, ImageErr)
	inspect! = |bytes, format| Host.image_inspect!(bytes, encode_format(format)).map_err(|code| InspectImageErr(decode_reason(code)))

	encode_format = |format| match format {
		Bmp => 0
		Gif => 1
		Jpeg => 2
		Png => 3
		Svg => 4
		Tiff => 5
		Webp => 6
	}
	decode_reason = |code| match code {
		0 => Corrupt
		1 => InvalidDimensions
		2 => ResourceLimit
		_ => Unsupported
	}
}
