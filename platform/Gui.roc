import Action
import Assets
import Audio
import Clipboard
import Device
import Elem
import Event
import Files
import Http
import ImageData
import Index
import Key
import KeyedSeq
import Process
import Program
import Sqlite
import Style
import SystemMonitor
import Tcp
import Timer

## The whole application-facing platform under one import. Build a tree with
## the element constructors and their property records, adjust an element
## with the modifiers on `Elem`, and answer events with the constructors on
## `Action`: `Action.none`, `Action.update`, `Action.delegate`, or `Action.task`.
Gui := [].{

	## A declarative UI tree whose event handlers transition application state.
	Elem(a) : Elem.Elem(a)

	## What an event handler asks the platform to do next.
	Action(a) : Action.Action(a)

	## The value an application's `main` provides.
	Program(state) : Program.Program(state)

	## The capability from which an application acquires host resources.
	Access : Program.Access

	Key : Key.Key
	Index(a) : Index.Index(a)
	KeyedSeq(value) : KeyedSeq.KeyedSeq(value)

	Style : Style.Style
	Align : Style.Align
	Color : Style.Color
	FontFace : Style.FontFace
	Inset : Style.Inset
	Justify : Style.Justify
	Length : Style.Length
	TextOverflow : Style.TextOverflow
	Overflow : Style.Overflow

	Assets : Assets.Assets
	Audio : Audio.Audio
	Clipboard : Clipboard.Clipboard
	Device : Device.Device
	Files : Files.Files
	Http : Http.Http
	ImageData : ImageData.ImageData
	Process : Process.Process
	Sqlite : Sqlite.Sqlite
	SystemMonitor : SystemMonitor.SystemMonitor
	Tcp : Tcp.Tcp
	Timer : Timer.Timer
	Event : Event.Event

	TranslateConfig(parent, child) : Elem.TranslateConfig(parent, child)
	TryTranslateConfig(parent, child) : Elem.TryTranslateConfig(parent, child)
	KeyedColConfig(parent, item) : Elem.KeyedColConfig(parent, item)
	VirtualListItem(a) : Elem.VirtualListItem(a)
	ScrollAxis : Elem.ScrollAxis
	ImageFormat : Elem.ImageFormat
	ImageFit : Elem.ImageFit
	CanvasEllipse : Elem.CanvasEllipse
	CanvasLine : Elem.CanvasLine
	CanvasRectangle : Elem.CanvasRectangle
	CanvasPrimitive : Elem.CanvasPrimitive

	## Construct the program value required by the platform's `main` module.
	run : Program.Config(state) -> Program.Program(state)
	run = |config| Program.run(config)

	## Construct a fixed per-side inset.
	inset : U32 -> Style.Inset
	inset = |value| Px(value)

	## Construct a fixed pixel length.
	px : U32 -> Style.Length
	px = |value| Px(value)

	## Display literal text. It inherits colour and size from its container.
	text : Str -> Elem.Elem(a)
	text = |value| Elem.text(value)

	## Display text in its own colour, size, weight, and face.
	styled_text : Elem.TextProps -> Elem.Elem(a)
	styled_text = |props| Elem.styled_text(props)

	## Display a controlled button. `caption` is its visible text and `label` its semantic locator.
	button : Elem.ButtonProps(a) -> Elem.Elem(a)
	button = |props| Elem.button(props)

	## Display a controlled checkbox.
	checkbox : Elem.CheckboxProps(a) -> Elem.Elem(a)
	checkbox = |props| Elem.checkbox(props)

	## Display a controlled single-line text editor.
	text_input : Elem.TextInputProps(a) -> Elem.Elem(a)
	text_input = |props| Elem.text_input(props)

	## Display a controlled multiline text editor.
	textarea : Elem.TextareaProps(a) -> Elem.Elem(a)
	textarea = |props| Elem.textarea(props)

	## Render encoded image bytes.
	image : Elem.ImageProps -> Elem.Elem(a)
	image = |props| Elem.image(props)

	## Paint keyed vector primitives and receive pointer gestures.
	canvas : Elem.CanvasProps(a) -> Elem.Elem(a)
	canvas = |props| Elem.canvas(props)

	## Lay out children horizontally in order.
	row : Elem.RowProps, List(Elem.Elem(a)) -> Elem.Elem(a)
	row = |props, children| Elem.row(props, children)

	## Lay out children vertically in order.
	col : Elem.ColProps, List(Elem.Elem(a)) -> Elem.Elem(a)
	col = |props, children| Elem.col(props, children)

	## Group children in a labelled, bordered vertical surface.
	panel : Elem.PanelProps, List(Elem.Elem(a)) -> Elem.Elem(a)
	panel = |props, children| Elem.panel(props, children)

	## Present one modal surface.
	dialog : Elem.DialogProps(a), List(Elem.Elem(a)) -> Elem.Elem(a)
	dialog = |props, children| Elem.dialog(props, children)

	## Constrain content to the available space and allow scrolling.
	scroll : Elem.ScrollProps(a) -> Elem.Elem(a)
	scroll = |props| Elem.scroll(props)

	## Present fixed-height rows, materializing only the visible range.
	virtual_list : Elem.VirtualListProps(a) -> Elem.Elem(a)
	virtual_list = |props| Elem.virtual_list(props)

	## Embed a renderer over a smaller part of parent state.
	translate : (child -> Elem.Elem(child)), (parent -> child), (parent, child -> parent) -> Elem.Elem(parent)
	translate = |render, get, set| Elem.translate(render, get, set)

	## Embed a keyed renderer whose lifetime survives parent renders.
	translate_with : (child -> Elem.Elem(child)), Elem.TranslateConfig(parent, child) -> Elem.Elem(parent)
	translate_with = |render, config| Elem.translate_with(render, config)

	## Embed a removable child through fallible adapters.
	try_translate : (child -> Elem.Elem(child)), Elem.TryTranslateConfig(parent, child) -> Elem.Elem(parent)
	try_translate = |render, config| Elem.try_translate(render, config)

	## Adapt a persistent keyed sequence into a native column.
	keyed_col : (item -> Elem.Elem(item)), Elem.ColProps, Elem.KeyedColConfig(parent, item) -> Elem.Elem(parent)
	keyed_col = |render_item, props, config| Elem.keyed_col(render_item, props, config)

	## A filled, optionally stroked and rounded rectangle on a canvas.
	rectangle : Elem.CanvasRectangle -> Elem.CanvasPrimitive
	rectangle = |shape| Elem.rectangle(shape)

	## A filled, optionally stroked ellipse on a canvas.
	ellipse : Elem.CanvasEllipse -> Elem.CanvasPrimitive
	ellipse = |shape| Elem.ellipse(shape)

	## A stroked line on a canvas.
	line : Elem.CanvasLine -> Elem.CanvasPrimitive
	line = |shape| Elem.line(shape)
}
