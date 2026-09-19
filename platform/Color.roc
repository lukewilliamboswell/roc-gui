## A native color, or the control's platform default. A colour is written as a
## `0xRRGGBB` literal.
Color := [Default, Rgb(U32)].{

	## Support colour literals such as `bg: 0x24404b`.
	from_numeral : Numeral -> Try(Color, [InvalidNumeral(Str)])
	from_numeral = |numeral| match U32.from_numeral(numeral) {
		Ok(value) => if value <= 0xffffff Ok(Rgb(value)) else Err(InvalidNumeral("a colour is 0xRRGGBB, at most 0xffffff"))
		Err(_) => Err(InvalidNumeral("a colour is 0xRRGGBB, at most 0xffffff"))
	}
}
