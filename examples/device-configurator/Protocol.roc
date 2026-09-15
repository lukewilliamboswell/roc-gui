Protocol := [].{
	Config : { controls : U16, lighting : Bool, profile : U8, sensitivity : U16 }
	Error : [Malformed, Rejected, VersionMismatch]
	read_request : List(U8)
	read_request = [0xa5, 1, 1]
	apply_request : Config -> List(U8)
	apply_request = apply_request
	decode_config : List(U8) -> Try(Config, Error)
	decode_config = decode_config
	decode_apply : List(U8) -> Try({}, Error)
	decode_apply = decode_apply
}

byte = |bytes, index| bytes.get(index) ?? 0
word = |low, high| U8.to_u16(low) + U8.to_u16(high) * 256

apply_request = |config| [0xa5, 1, 2, U16.to_u8_wrap(config.sensitivity), U16.to_u8_wrap(config.sensitivity / 256), if config.lighting 1 else 0, config.profile]

header = |bytes, op| if List.len(bytes) < 4 or byte(bytes, 0) != 0x5a or byte(bytes, 2) != op {
	Err(Malformed)
} else if byte(bytes, 1) != 1 {
	Err(VersionMismatch)
} else if byte(bytes, 3) != 0 {
	Err(Rejected)
} else {
	Ok({})
}

decode_config = |bytes| {
	header(bytes, 1)?
	if List.len(bytes) != 10 {
		Err(Malformed)
	} else {
		Ok({ controls: word(byte(bytes, 4), byte(bytes, 5)), sensitivity: word(byte(bytes, 6), byte(bytes, 7)), lighting: byte(bytes, 8) == 1, profile: byte(bytes, 9) })
	}
}

decode_apply = |bytes| {
	header(bytes, 2)?
	if List.len(bytes) == 8 Ok({}) else Err(Malformed)
}

expect decode_config([0x5a, 1, 1, 0, 12, 0, 0x20, 3, 1, 2]) == Ok({ controls: 12, sensitivity: 800, lighting: True, profile: 2 })
expect decode_config([0x5a, 2, 1, 0, 12, 0, 0x20, 3, 1, 2]) == Err(VersionMismatch)
