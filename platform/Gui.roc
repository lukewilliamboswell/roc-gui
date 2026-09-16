## A native color, or the control's platform default. `Rgb` values use the low
## 24 bits as `0xRRGGBB`.
Color : [Default, Rgb(U32)]

## A control dimension: intrinsic size, available space, or fixed pixels.
Length : [Auto, Fill, Px(U32)]

## How content outside a control's bounds is presented on one axis.
Overflow : [Visible, Clip, Scroll]

## One side's inset. `Same` takes the element's `padding` scalar.
Inset : [Same, Px(U32)]

## The typeface family a string is set in. `Default` is the host's own
## proportional face; `Monospace` is the platform's fixed-pitch face, which is
## what columnar output and changing digits need.
FontFace : [Default, Monospace]

## How a string behaves when it is wider than the space it was given. `Wrap`
## reflows onto further lines, `NoWrap` keeps one line and lets overflow decide
## what happens to the rest, and `Ellipsis` keeps one line and ends it with a
## marker so a shortened value never looks complete.
TextOverflow : [Wrap, NoWrap, Ellipsis]

## Where a container places its children across its layout axis. `Default` keeps
## the element's own native alignment.
Align : [Default, Start, Center, End, Baseline, Stretch]

## How a container distributes its children along its layout axis. `Default`
## keeps the element's own native distribution.
Justify : [Default, Start, Center, End, Between, Around]

## Native presentation values shared by element property records.
Gui := [].{
	Align : Align
	Color : Color
	FontFace : FontFace
	Inset : Inset
	Justify : Justify
	Length : Length
	TextOverflow : TextOverflow
	Overflow : Overflow

	## Common visual properties. A zero value for `font_size` or `font_weight`
	## selects the native default, and a non-zero `font_weight` is 100 through
	## 900; `hover_bg` and `active_bg` apply during pointer interaction. A
	## non-zero `shadow` is the blur radius of a soft drop shadow, offset down
	## the surface by `shadow_y` and painted in `shadow_color` at
	## `shadow_alpha` percent; `shadow: 0` paints none.
	Style := {
		gap : U32 ?? 8,
		padding : U32 ?? 0,
		padding_top : Inset ?? Same,
		padding_right : Inset ?? Same,
		padding_bottom : Inset ?? Same,
		padding_left : Inset ?? Same,
		width : Length ?? Auto,
		height : Length ?? Auto,
		min_width : Length ?? Auto,
		min_height : Length ?? Auto,
		max_width : Length ?? Auto,
		max_height : Length ?? Auto,
		grow : Bool ?? False,
		bg : Color ?? Default,
		hover_bg : Color ?? Default,
		active_bg : Color ?? Default,
		disabled_bg : Color ?? Default,
		disabled_fg : Color ?? Default,
		focus_color : Color ?? Default,
		fg : Color ?? Default,
		border_color : Color ?? Default,
		border_width : U32 ?? 0,
		border_top : Inset ?? Same,
		border_right : Inset ?? Same,
		border_bottom : Inset ?? Same,
		border_left : Inset ?? Same,
		radius : U32 ?? 0,
		font_size : U32 ?? 0,
		font_weight : U32 ?? 0,
		shadow : U32 ?? 0,
		shadow_y : U32 ?? 0,
		shadow_color : Color ?? Default,
		shadow_alpha : U32 ?? 100,
		font_face : FontFace ?? Default,
		text_overflow : TextOverflow ?? Wrap,
		overflow_x : Overflow ?? Visible,
		overflow_y : Overflow ?? Visible,
		align : Align ?? Default,
		justify : Justify ?? Default,
	}

	## Construct an RGB color from a `0xRRGGBB` integer.
	rgb : U32 -> Color
	rgb = |value| Rgb(value)

	## Construct a fixed per-side inset.
	inset : U32 -> Inset
	inset = |value| Px(value)

	## Construct a fixed pixel length.
	px : U32 -> Length
	px = |value| Px(value)
}
