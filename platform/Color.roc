## A native color, or the control's platform default. A colour is written as a
## `0xRRGGBB` literal. An adaptive colour is a pair the host chooses between by
## the window's appearance, light or dark, each time it paints, so a change of
## appearance repaints without rendering the application again.
Color := [Default, Rgb(U32), Adaptive({ light : U32, dark : U32 })].{

	## Support colour literals such as `bg: 0x24404b`.
	from_numeral : Numeral -> Try(Color, [InvalidNumeral(Str)])
	from_numeral = |numeral| match U32.from_numeral(numeral) {
		Ok(value) => if value <= 0xffffff Ok(Rgb(value)) else Err(InvalidNumeral("a colour is 0xRRGGBB, at most 0xffffff"))
		Err(_) => Err(InvalidNumeral("a colour is 0xRRGGBB, at most 0xffffff"))
	}

	## A colour for each appearance: `light` on a light window, `dark` on a
	## dark one. Both are `0xRRGGBB`.
	adaptive : U32, U32 -> Color
	adaptive = |light, dark| Adaptive({ light, dark })
}
