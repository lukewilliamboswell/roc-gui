## A native color, or the control's platform default. `Rgb` values use the low
## 24 bits as `0xRRGGBB`.
Color : [Default, Rgb(U32)]

## A control dimension: intrinsic size, available space, or fixed pixels.
Length : [Auto, Fill, Px(U32)]

## How content outside a control's bounds is presented on one axis.
Overflow : [Visible, Clip, Scroll]

## Native presentation values shared by element property records.
Gui := [].{
	Color : Color
	Length : Length
	Overflow : Overflow

	## Common visual properties. A zero value for `font_size` or `font_weight`
	## selects the native default, and a non-zero `font_weight` is 100 through
	## 900; `hover_bg` and `active_bg` apply during pointer interaction.
	Style := {
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		width : Length ?? Auto,
		height : Length ?? Auto,
		grow : Bool ?? False,
		bg : Color ?? Default,
		hover_bg : Color ?? Default,
		active_bg : Color ?? Default,
		fg : Color ?? Default,
		border_color : Color ?? Default,
		border_width : U32 ?? 0,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		overflow_x : Overflow ?? Visible,
		overflow_y : Overflow ?? Visible,
	}

	## Construct an RGB color from a `0xRRGGBB` integer.
	rgb : U32 -> Color
	rgb = |value| Rgb(value)

	## Construct a fixed pixel length.
	px : U32 -> Length
	px = |value| Px(value)
}
