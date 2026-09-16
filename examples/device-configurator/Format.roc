## Shaping the few numbers this application shows.
Format := [].{
	## A USB identifier as four hexadecimal digits. Vendor and product ids are
	## published, quoted, and searched for in hexadecimal, so printing them in
	## decimal would make a device harder to recognise than not printing them.
	hex4 : U16 -> Str
	hex4 = hex4
}

digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]

digit = |value| digits.get(U16.to_u64(value)) ?? "0"

hex4 = |value| "${digit(value / 4096 % 16)}${digit(value / 256 % 16)}${digit(value / 16 % 16)}${digit(value % 16)}"

expect hex4(0x1209) == "1209"
expect hex4(0) == "0000"
expect hex4(0xffff) == "ffff"
