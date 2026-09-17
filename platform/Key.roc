## An application identity retains the complete SHA-256 digest. Names and
## numeric identities occupy separate domains; mounted IDs belong to the host.
Key := Crypto.SHA256.Digest.{
	from_str : Str -> Key
	from_str = |name| Key.(Crypto.SHA256.hash([0.U8].concat(name.to_utf8())))

	from_quote : Str -> Try(Key, [BadQuotedBytes(Str)])
	from_quote = |name| Ok(from_str(name))

	id : U64 -> Key
	id = |value| {
		var $remaining = value
		var $bytes = [1.U8]
		for _ in [0, 1, 2, 3, 4, 5, 6, 7] {
			$bytes = $bytes.append($remaining.to_u8_wrap())
			$remaining = $remaining // 256
		}
		Key.(Crypto.SHA256.hash($bytes))
	}

	is_eq : Key, Key -> Bool
	is_eq = |Key.(left), Key.(right)| left == right

	to_hash : Key, Hasher -> Hasher
	to_hash = |Key.(digest), hasher| digest.to_hash(hasher)

	to_bytes : Key -> List(U8)
	to_bytes = |Key.(digest)| digest.to_bytes()
}

expect {
	literal : Key
	literal = "left"
	literal == Key.from_str("left")
}
expect Key.id(1) != Key.from_str("1")
expect Key.to_bytes(Key.from_str("左 🦆 a long application key without a short-string limit")).len() == 32
expect Key.to_bytes(Key.id(72623859790382856)) == Crypto.SHA256.hash([1, 8, 7, 6, 5, 4, 3, 2, 1]).to_bytes()
