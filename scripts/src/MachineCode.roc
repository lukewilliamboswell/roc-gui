## Compiled machine code, recognised by its leading bytes alone. Binaries
## reach a release through a verified build, never through the Git index.
MachineCode := [].{

	## The kind of machine code `bytes` begin with, if they are machine code.
	kind : List(U8) -> [None, Some(Str)]
	kind = |bytes| {
		magic = bytes.take_first(4)
		if bytes.starts_with([0x7F, 0x45, 0x4C, 0x46]) {
			Some("ELF")
		} else if mach_o.contains(magic) {
			Some("Mach-O")
		} else if bytes.starts_with([0x21, 0x3C, 0x61, 0x72, 0x63, 0x68, 0x3E, 0x0A]) {
			Some("object archive")
		} else if bytes.starts_with([0x00, 0x61, 0x73, 0x6D]) {
			Some("WebAssembly")
		} else if is_pe(bytes) {
			Some("PE/COFF")
		} else {
			None
		}
	}
}

mach_o : List(List(U8))
mach_o = [
	[0xFE, 0xED, 0xFA, 0xCE],
	[0xCE, 0xFA, 0xED, 0xFE],
	[0xFE, 0xED, 0xFA, 0xCF],
	[0xCF, 0xFA, 0xED, 0xFE],
	[0xCA, 0xFE, 0xBA, 0xBE],
	[0xBE, 0xBA, 0xFE, 0xCA],
	[0xCA, 0xFE, 0xBA, 0xBF],
	[0xBF, 0xBA, 0xFE, 0xCA],
]

# A DOS stub whose little-endian offset at byte 60 points at a PE signature.
is_pe : List(U8) -> Bool
is_pe = |bytes| {
	if !bytes.starts_with([0x4D, 0x5A]) or bytes.len() < 64 {
		return False
	}
	offset = bytes.sublist({ start: 60, len: 4 }).fold_rev(0, |byte, total| total * 256 + byte.to_u64())
	bytes.sublist({ start: offset, len: 4 }) == [0x50, 0x45, 0x00, 0x00]
}

pe_image : List(U8)
pe_image = [0x4D, 0x5A].concat(List.repeat(0, 58)).concat([64, 0, 0, 0, 0x50, 0x45, 0, 0]).concat(List.repeat(0, 4))

expect MachineCode.kind([0x7F, 0x45, 0x4C, 0x46].concat(List.repeat(0, 60))) == Some("ELF")
expect MachineCode.kind([0xCF, 0xFA, 0xED, 0xFE, 0x07]) == Some("Mach-O")
expect MachineCode.kind(Str.to_utf8("!<arch>\n")) == Some("object archive")
expect MachineCode.kind([0x00, 0x61, 0x73, 0x6D, 0x01, 0, 0, 0]) == Some("WebAssembly")
expect MachineCode.kind(pe_image) == Some("PE/COFF")
expect MachineCode.kind(pe_image.take_first(64).concat([0, 0x45, 0, 0])) == None
expect MachineCode.kind(Str.to_utf8("RIFF").concat(List.repeat(0, 32)).concat(Str.to_utf8("WAVE"))) == None
expect MachineCode.kind(Str.to_utf8("SQLite format 3").concat(List.repeat(0, 65))) == None
expect MachineCode.kind(Str.to_utf8("INPUT(libasound.so.2)\n")) == None
expect MachineCode.kind([]) == None
