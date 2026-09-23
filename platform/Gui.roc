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
## with the modifiers on `Elem`, and answer events with `none`, `update`,
## `delegate`, or `task`.
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

	# Types exchanged with `KeyedSeq`.
	KeyedSeqEdit(value) : KeyedSeq.Edit(value)
	KeyedSeqPlacement : KeyedSeq.Placement
	KeyedSeqTransition(value) : KeyedSeq.Transition(value)
	KeyedSeqError : KeyedSeq.Error

	# Types exchanged with `Assets`.
	AssetsStore : Assets.Store
	AssetsRoot : Assets.Root
	AssetsContent : Assets.Content
	AssetsManifest : Assets.Manifest
	AssetsManifestPolicy : Assets.ManifestPolicy
	AssetsStoreConfig : Assets.StoreConfig
	AssetsReason : Assets.Reason
	AssetsAssetErr : Assets.AssetErr

	# Types exchanged with `Audio`.
	AudioOutput : Audio.Output
	AudioTrack : Audio.Track
	AudioPlayback : Audio.Playback
	AudioStatus : Audio.Status
	AudioLoadedTrack : Audio.LoadedTrack
	AudioReason : Audio.Reason
	AudioAudioErr : Audio.AudioErr

	# Types exchanged with `Clipboard`.
	ClipboardHandle : Clipboard.Handle
	ClipboardSnapshot : Clipboard.Snapshot
	ClipboardReason : Clipboard.Reason
	ClipboardClipboardErr : Clipboard.ClipboardErr

	# Types exchanged with `Device`.
	DeviceGrant : Device.Grant
	DeviceConnection : Device.Connection
	DeviceInfo : Device.Info
	DeviceReason : Device.Reason
	DeviceDeviceErr : Device.DeviceErr

	# Types exchanged with `Event`.
	EventPress : Event.Press
	EventHover : Event.Hover
	EventCheck : Event.Check
	EventInput : Event.Input
	EventDismiss : Event.Dismiss
	EventTextChange : Event.TextChange
	EventTextSubmit : Event.TextSubmit
	EventCanvasPointer : Event.CanvasPointer
	EventCanvasHover : Event.CanvasHover
	EventCanvasWheel : Event.CanvasWheel
	EventVisibleRows : Event.VisibleRows
	EventKey : Event.Key

	# Types exchanged with `Files`.
	FilesChoice(a) : Files.Choice(a)
	FilesKind : Files.Kind
	FilesEntry : Files.Entry
	FilesReason : Files.Reason
	FilesFileErr : Files.FileErr
	FilesDirRead : Files.Dir.Read
	FilesDirReadWrite : Files.Dir.ReadWrite
	FilesDirReadUtf8 : Files.Dir.ReadUtf8
	FilesSelection : Files.Selection
	FilesFileRead : Files.File.Read
	FilesFileSelection : Files.FileSelection
	FilesFileType : Files.FileType
	FilesWatch : Files.Watch
	FilesChange : Files.Change
	FilesChanges : Files.Changes

	# Types exchanged with `Http`.
	HttpClient : Http.Client
	HttpReason : Http.Reason
	HttpHttpErr : Http.HttpErr
	HttpConfig : Http.Config

	# Types exchanged with `ImageData`.
	ImageDataMetadata : ImageData.Metadata
	ImageDataReason : ImageData.Reason
	ImageDataImageErr : ImageData.ImageErr

	# Types exchanged with `Process`.
	ProcessGrant : Process.Grant
	ProcessPty : Process.Pty
	ProcessReason : Process.Reason
	ProcessProcessErr : Process.ProcessErr
	ProcessRead : Process.Read
	ProcessCancel : Process.Cancel

	# Types exchanged with `Sqlite`.
	SqliteDb : Sqlite.Db
	SqliteValue : Sqlite.Value
	SqliteResult : Sqlite.Result
	SqlitePage : Sqlite.Page
	SqliteReason : Sqlite.Reason
	SqliteSqliteErr : Sqlite.SqliteErr

	# Types exchanged with `SystemMonitor`.
	SystemMonitorSampler : SystemMonitor.Sampler
	SystemMonitorUnavailableReason : SystemMonitor.UnavailableReason
	SystemMonitorValue(a) : SystemMonitor.Value(a)
	SystemMonitorProcess : SystemMonitor.Process
	SystemMonitorSnapshot : SystemMonitor.Snapshot
	SystemMonitorReason : SystemMonitor.Reason
	SystemMonitorSystemErr : SystemMonitor.SystemErr

	# Types exchanged with `Tcp`.
	TcpStream : Tcp.Stream
	TcpReason : Tcp.Reason
	TcpTcpErr : Tcp.TcpErr

	# Types exchanged with `Timer`.
	TimerHandle : Timer.Handle
	TimerTick : Timer.Tick
	TimerCancelResult : Timer.CancelResult
	TimerTimerErr : Timer.TimerErr

	TranslateConfig(parent, child) : Elem.TranslateConfig(parent, child)
	TryTranslateConfig(parent, child) : Elem.TryTranslateConfig(parent, child)
	KeyedColConfig(parent, item) : Elem.KeyedColConfig(parent, item)
	VirtualListItem(a) : Elem.VirtualListItem(a)
	RowAlign : Elem.RowAlign
	ScrollRequest : Elem.ScrollRequest
	ScrollAxis : Elem.ScrollAxis
	Placement : Elem.Placement
	Shortcut(a) : Elem.Shortcut(a)
	ImageFormat : Elem.ImageFormat
	ImageFit : Elem.ImageFit
	CanvasEllipse : Elem.CanvasEllipse
	CanvasLine : Elem.CanvasLine
	CanvasRectangle : Elem.CanvasRectangle
	CanvasText : Elem.CanvasText
	CanvasTextAlign : Elem.CanvasTextAlign
	CanvasPrimitive : Elem.CanvasPrimitive
	TextSpan : Elem.TextSpan

	## Construct the program value required by the platform's `main` module.
	run : Program.Config(state) -> Program.Program(state)
	run = |config| Program.run(config)

	## Leave state as it is.
	none : Action.Action(a)
	none = Action.none

	## Install the next state.
	update : a -> Action.Action(a)
	update = |value| Action.update(value)

	## Propose the next state to the enclosing boundary's `on_delegate`.
	delegate : a -> Action.Action(a)
	delegate = |value| Action.delegate(value)

	## Install `pending`, run effects off the UI thread, then resolve against
	## the latest state.
	task : { pending : a, run : (() => result), resolve : (a, result -> Action.Action(a)) } -> Action.Action(a)
	task = |config| Action.task(config)

	## A task that supersedes this component's previous task with the same
	## `key`: the superseded task is cancelled and its completion is never
	## delivered.
	keyed_task : { key : Str, pending : a, run : (() => result), resolve : (a, result -> Action.Action(a)) } -> Action.Action(a)
	keyed_task = |config| Action.keyed_task(config)

	## Install `state` and cancel this component's task with `key`.
	cancel : a, Str -> Action.Action(a)
	cancel = |state, key| Action.cancel(state, key)

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

	## One styled run of rich text: its own colour, ground, weight, underline,
	## or monospace face.
	span : Elem.SpanProps -> Elem.TextSpan
	span = |props| Elem.span(props)

	## Display several styled runs as one text element, which lays out and
	## wraps as one string and is located by the whole of it.
	rich_text : Elem.RichTextProps -> Elem.Elem(a)
	rich_text = |props| Elem.rich_text(props)

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

	## Annotate an anchor with a non-modal surface that opens on hover and focus.
	popover : Elem.PopoverProps(a), Elem.Elem(a), List(Elem.Elem(a)) -> Elem.Elem(a)
	popover = |props, anchor, content| Elem.popover(props, anchor, content)

	## Annotate an element with a short text tooltip, named by that text.
	tooltip : Elem.Elem(a), Str -> Elem.Elem(a)
	tooltip = |anchor, value| Elem.tooltip(anchor, value)

	## Answer key chords anywhere in the window while an element is mounted.
	shortcuts : Elem.Elem(a), List(Elem.Shortcut(a)) -> Elem.Elem(a)
	shortcuts = |elem, list| Elem.shortcuts(elem, list)

	## Answer key chords only while keyboard focus is inside an element.
	focus_shortcuts : Elem.Elem(a), List(Elem.Shortcut(a)) -> Elem.Elem(a)
	focus_shortcuts = |elem, list| Elem.focus_shortcuts(elem, list)

	## Focus the first enabled control inside an element once for each new serial.
	request_focus : Elem.Elem(a), U64 -> Elem.Elem(a)
	request_focus = |elem, serial| Elem.request_focus(elem, serial)

	## Constrain content to the available space and allow scrolling.
	scroll : Elem.ScrollProps(a) -> Elem.Elem(a)
	scroll = |props| Elem.scroll(props)

	## Present fixed-height rows, materializing only the visible range.
	virtual_list : Elem.VirtualListProps(a) -> Elem.Elem(a)
	virtual_list = |props| Elem.virtual_list(props)

	## Present `count` fixed-height rows, producing each on demand for the viewport.
	virtual_rows : Elem.VirtualRowsProps(a) -> Elem.Elem(a)
	virtual_rows = |props| Elem.virtual_rows(props)

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

	## A single line of text on a canvas, aligned within a box.
	canvas_text : Elem.CanvasText -> Elem.CanvasPrimitive
	canvas_text = |shape| Elem.canvas_text(shape)
}
