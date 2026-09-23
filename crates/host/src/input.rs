// Adapted from GPUI 0.2.2's input example. The editor owns transient caret,
// selection, and IME preedit state; every committed value still travels through
// roc-gui's ordinary Roc event route and returns as controlled application state.
use std::{cell::RefCell, ops::Range, rc::Rc};

use gpui::{
    App, Bounds, Context, CursorStyle, Element, ElementId, ElementInputHandler, Entity,
    EntityInputHandler, FocusHandle, Focusable, GlobalElementId, KeyBinding, LayoutId, MouseButton,
    MouseDownEvent, MouseMoveEvent, MouseUpEvent, PaintQuad, Pixels, Point, ShapedLine,
    SharedString, Style, TextRun, UTF16Selection, UnderlineStyle, Window, actions, div, fill,
    point, prelude::*, px, relative, rgba, size,
};
use unicode_segmentation::UnicodeSegmentation;

actions!(
    text_input,
    [
        Backspace,
        Delete,
        Left,
        Right,
        SelectLeft,
        SelectRight,
        SelectAll,
        Home,
        End,
        Submit
    ]
);

pub const MAX_TEXT_BYTES: usize = 1024 * 1024;

pub type TextCallback = Rc<dyn Fn(String, &mut App)>;

pub struct TextInput {
    on_change: TextCallback,
    on_submit: TextCallback,
    focus: FocusHandle,
    content: SharedString,
    controlled: SharedString,
    in_flight_edit: Option<String>,
    placeholder: SharedString,
    selection: Range<usize>,
    reversed: bool,
    marked: Option<Range<usize>>,
    enabled: bool,
    selecting: bool,
    layout: Option<ShapedLine>,
    bounds: Option<Bounds<Pixels>>,
}

impl TextInput {
    pub fn new(
        value: String,
        placeholder: String,
        enabled: bool,
        on_change: TextCallback,
        on_submit: TextCallback,
        cx: &mut Context<Self>,
    ) -> Self {
        assert!(value.len() <= MAX_TEXT_BYTES, "text input exceeds one MiB");
        Self {
            on_change,
            on_submit,
            focus: cx.focus_handle().tab_stop(enabled),
            content: value.clone().into(),
            controlled: value.into(),
            in_flight_edit: None,
            placeholder: placeholder.into(),
            selection: 0..0,
            reversed: false,
            marked: None,
            enabled,
            selecting: false,
            layout: None,
            bounds: None,
        }
    }

    pub fn configure(
        &mut self,
        value: &str,
        placeholder: &str,
        enabled: bool,
        on_change: TextCallback,
        on_submit: TextCallback,
        cx: &mut Context<Self>,
    ) {
        assert!(value.len() <= MAX_TEXT_BYTES, "text input exceeds one MiB");
        self.on_change = on_change;
        self.on_submit = on_submit;
        self.placeholder = placeholder.to_owned().into();
        if self.controlled.as_ref() != value {
            self.controlled = value.to_owned().into();
            let newer_edit = self
                .in_flight_edit
                .as_ref()
                .is_some_and(|submitted| self.content.as_ref() != submitted);
            if self.content.as_ref() != value && !newer_edit {
                self.content = value.to_owned().into();
                let cursor = self.content.len();
                self.selection = cursor..cursor;
                self.reversed = false;
                self.marked = None;
            }
        }
        self.set_enabled(enabled, cx);
        cx.notify();
    }

    pub fn set_enabled(&mut self, enabled: bool, cx: &mut Context<Self>) {
        if self.enabled != enabled {
            self.enabled = enabled;
            self.focus = self.focus.clone().tab_stop(enabled);
            self.selecting = false;
            cx.notify();
        }
    }

    pub fn focus_handle(&self) -> FocusHandle {
        self.focus.clone()
    }

    /// The text the native editor displays, including an uncommitted preedit.
    #[cfg(test)]
    pub fn displayed_value(&self) -> &str {
        self.content.as_ref()
    }

    /// Settle a committed edit after its ordinary application event turn.
    /// A rejected edit can leave the controlled value unchanged, so configure
    /// alone cannot acknowledge it. A later edit or IME preedit owns its own
    /// acknowledgement and must not be overwritten by this earlier turn.
    pub fn acknowledge(&mut self, submitted: &str, cx: &mut Context<Self>) {
        self.in_flight_edit = None;
        if self.marked.is_some() || self.content.as_ref() != submitted {
            return;
        }
        if self.content != self.controlled {
            self.content = self.controlled.clone();
            let cursor = self.content.len();
            self.selection = cursor..cursor;
            self.reversed = false;
            self.layout = None;
            cx.notify();
        }
    }

    pub fn begin_acknowledgement(&mut self, submitted: &str) {
        self.in_flight_edit = Some(submitted.to_owned());
    }

    fn cursor(&self) -> usize {
        if self.reversed {
            self.selection.start
        } else {
            self.selection.end
        }
    }

    fn move_to(&mut self, offset: usize, cx: &mut Context<Self>) {
        self.selection = offset..offset;
        self.reversed = false;
        cx.notify();
    }

    fn select_to(&mut self, offset: usize, cx: &mut Context<Self>) {
        let anchor = if self.reversed {
            self.selection.end
        } else {
            self.selection.start
        };
        self.selection = anchor.min(offset)..anchor.max(offset);
        self.reversed = offset < anchor;
        cx.notify();
    }

    fn previous(&self, offset: usize) -> usize {
        self.content
            .grapheme_indices(true)
            .rev()
            .find_map(|(i, _)| (i < offset).then_some(i))
            .unwrap_or(0)
    }

    fn next(&self, offset: usize) -> usize {
        self.content
            .grapheme_indices(true)
            .find_map(|(i, _)| (i > offset).then_some(i))
            .unwrap_or(self.content.len())
    }

    fn left(&mut self, _: &Left, _: &mut Window, cx: &mut Context<Self>) {
        if self.selection.is_empty() {
            self.move_to(self.previous(self.cursor()), cx)
        } else {
            self.move_to(self.selection.start, cx)
        }
    }

    fn right(&mut self, _: &Right, _: &mut Window, cx: &mut Context<Self>) {
        if self.selection.is_empty() {
            self.move_to(self.next(self.cursor()), cx)
        } else {
            self.move_to(self.selection.end, cx)
        }
    }

    fn select_left(&mut self, _: &SelectLeft, _: &mut Window, cx: &mut Context<Self>) {
        self.select_to(self.previous(self.cursor()), cx)
    }

    fn select_right(&mut self, _: &SelectRight, _: &mut Window, cx: &mut Context<Self>) {
        self.select_to(self.next(self.cursor()), cx)
    }

    fn select_all(&mut self, _: &SelectAll, _: &mut Window, cx: &mut Context<Self>) {
        self.selection = 0..self.content.len();
        self.reversed = false;
        cx.notify();
    }

    fn home(&mut self, _: &Home, _: &mut Window, cx: &mut Context<Self>) {
        self.move_to(0, cx)
    }
    fn end(&mut self, _: &End, _: &mut Window, cx: &mut Context<Self>) {
        self.move_to(self.content.len(), cx)
    }

    fn backspace(&mut self, _: &Backspace, window: &mut Window, cx: &mut Context<Self>) {
        if !self.enabled {
            return;
        }
        if self.selection.is_empty() {
            self.select_to(self.previous(self.cursor()), cx);
        }
        self.replace_text_in_range(None, "", window, cx);
    }

    fn delete(&mut self, _: &Delete, window: &mut Window, cx: &mut Context<Self>) {
        if !self.enabled {
            return;
        }
        if self.selection.is_empty() {
            self.select_to(self.next(self.cursor()), cx);
        }
        self.replace_text_in_range(None, "", window, cx);
    }

    fn submit(&mut self, _: &Submit, _: &mut Window, cx: &mut Context<Self>) {
        if !self.enabled || self.marked.is_some() {
            return;
        }
        let callback = self.on_submit.clone();
        let value = self.content.to_string();
        cx.defer(move |cx| callback(value, cx));
    }

    fn index_at(&self, position: Point<Pixels>) -> usize {
        match (&self.bounds, &self.layout) {
            (Some(bounds), Some(line)) => line.closest_index_for_x(position.x - bounds.left()),
            _ => 0,
        }
    }

    fn mouse_down(&mut self, event: &MouseDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        if !self.enabled {
            return;
        }
        self.selecting = true;
        window.focus(&self.focus, cx);
        let index = self.index_at(event.position);
        if event.modifiers.shift {
            self.select_to(index, cx)
        } else {
            self.move_to(index, cx)
        }
    }

    fn mouse_move(&mut self, event: &MouseMoveEvent, _: &mut Window, cx: &mut Context<Self>) {
        if self.selecting {
            self.select_to(self.index_at(event.position), cx);
        }
    }

    fn mouse_up(&mut self, _: &MouseUpEvent, _: &mut Window, _: &mut Context<Self>) {
        self.selecting = false;
    }

    fn byte_offset_from_utf16(&self, offset: usize) -> usize {
        let mut bytes = 0;
        let mut units = 0;
        for ch in self.content.chars() {
            if units >= offset {
                break;
            }
            units += ch.len_utf16();
            bytes += ch.len_utf8();
        }
        bytes
    }

    fn to_utf16(&self, offset: usize) -> usize {
        self.content[..offset].encode_utf16().count()
    }

    fn emit_change(&self, cx: &mut Context<Self>) {
        let callback = self.on_change.clone();
        let value = self.content.to_string();
        cx.defer(move |cx| callback(value, cx));
    }
}

impl EntityInputHandler for TextInput {
    fn text_for_range(
        &mut self,
        range: Range<usize>,
        actual: &mut Option<Range<usize>>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<String> {
        let bytes =
            self.byte_offset_from_utf16(range.start)..self.byte_offset_from_utf16(range.end);
        actual.replace(self.to_utf16(bytes.start)..self.to_utf16(bytes.end));
        Some(self.content[bytes].to_string())
    }

    fn selected_text_range(
        &mut self,
        ignore_disabled: bool,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<UTF16Selection> {
        if !self.enabled && !ignore_disabled {
            return None;
        }
        Some(UTF16Selection {
            range: self.to_utf16(self.selection.start)..self.to_utf16(self.selection.end),
            reversed: self.reversed,
        })
    }

    fn marked_text_range(&self, _: &mut Window, _: &mut Context<Self>) -> Option<Range<usize>> {
        self.marked
            .as_ref()
            .map(|r| self.to_utf16(r.start)..self.to_utf16(r.end))
    }

    fn unmark_text(&mut self, _: &mut Window, cx: &mut Context<Self>) {
        if self.enabled && self.marked.take().is_some() {
            self.emit_change(cx);
            cx.notify();
        }
    }

    fn replace_text_in_range(
        &mut self,
        range: Option<Range<usize>>,
        text: &str,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.enabled {
            return;
        }
        let range = range
            .map(|r| self.byte_offset_from_utf16(r.start)..self.byte_offset_from_utf16(r.end))
            .or(self.marked.clone())
            .unwrap_or(self.selection.clone());
        if text.contains(['\r', '\n'])
            || text.len() > MAX_TEXT_BYTES - (self.content.len() - range.len())
        {
            return;
        }
        self.content =
            (self.content[..range.start].to_owned() + text + &self.content[range.end..]).into();
        let end = range.start + text.len();
        self.selection = end..end;
        self.reversed = false;
        self.marked = None;
        self.emit_change(cx);
        cx.notify();
    }

    fn replace_and_mark_text_in_range(
        &mut self,
        range: Option<Range<usize>>,
        text: &str,
        selected: Option<Range<usize>>,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.enabled {
            return;
        }
        let range = range
            .map(|r| self.byte_offset_from_utf16(r.start)..self.byte_offset_from_utf16(r.end))
            .or(self.marked.clone())
            .unwrap_or(self.selection.clone());
        if text.contains(['\r', '\n'])
            || text.len() > MAX_TEXT_BYTES - (self.content.len() - range.len())
        {
            return;
        }
        self.content =
            (self.content[..range.start].to_owned() + text + &self.content[range.end..]).into();
        self.marked = (!text.is_empty()).then_some(range.start..range.start + text.len());
        self.selection = selected
            .map(|r| {
                range.start + utf16_offset(text, r.start)..range.start + utf16_offset(text, r.end)
            })
            .unwrap_or(range.start + text.len()..range.start + text.len());
        self.reversed = false;
        cx.notify();
    }

    fn bounds_for_range(
        &mut self,
        range: Range<usize>,
        bounds: Bounds<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<Bounds<Pixels>> {
        let line = self.layout.as_ref()?;
        let range =
            self.byte_offset_from_utf16(range.start)..self.byte_offset_from_utf16(range.end);
        Some(Bounds::from_corners(
            point(bounds.left() + line.x_for_index(range.start), bounds.top()),
            point(bounds.left() + line.x_for_index(range.end), bounds.bottom()),
        ))
    }

    fn character_index_for_point(
        &mut self,
        point: Point<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<usize> {
        Some(self.to_utf16(self.index_at(point)))
    }
}

fn utf16_offset(text: &str, offset: usize) -> usize {
    let mut bytes = 0;
    let mut units = 0;
    for ch in text.chars() {
        if units >= offset {
            break;
        }
        units += ch.len_utf16();
        bytes += ch.len_utf8();
    }
    bytes
}

impl Focusable for TextInput {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for TextInput {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("text-input-editor")
            .w_full()
            .h_full()
            .min_w_0()
            .key_context("TextInput")
            .track_focus(&self.focus)
            .cursor(CursorStyle::IBeam)
            .on_action(cx.listener(Self::backspace))
            .on_action(cx.listener(Self::delete))
            .on_action(cx.listener(Self::left))
            .on_action(cx.listener(Self::right))
            .on_action(cx.listener(Self::select_left))
            .on_action(cx.listener(Self::select_right))
            .on_action(cx.listener(Self::select_all))
            .on_action(cx.listener(Self::home))
            .on_action(cx.listener(Self::end))
            .on_action(cx.listener(Self::submit))
            .on_mouse_down(MouseButton::Left, cx.listener(Self::mouse_down))
            .on_mouse_move(cx.listener(Self::mouse_move))
            .on_mouse_up(MouseButton::Left, cx.listener(Self::mouse_up))
            .child(TextElement { input: cx.entity() })
    }
}

pub fn bind_keys(cx: &mut App) {
    cx.bind_keys(bindings());
}

/// The chords a focused text input takes for editing, in its own key context.
pub fn bindings() -> Vec<KeyBinding> {
    vec![
        KeyBinding::new("backspace", Backspace, Some("TextInput")),
        KeyBinding::new("delete", Delete, Some("TextInput")),
        KeyBinding::new("left", Left, Some("TextInput")),
        KeyBinding::new("right", Right, Some("TextInput")),
        KeyBinding::new("shift-left", SelectLeft, Some("TextInput")),
        KeyBinding::new("shift-right", SelectRight, Some("TextInput")),
        KeyBinding::new("ctrl-a", SelectAll, Some("TextInput")),
        KeyBinding::new("home", Home, Some("TextInput")),
        KeyBinding::new("end", End, Some("TextInput")),
        KeyBinding::new("enter", Submit, Some("TextInput")),
    ]
}

#[cfg(test)]
mod acknowledgement_tests {
    use super::*;
    use gpui::TestAppContext;

    #[gpui::test]
    fn controlled_acknowledgement_restores_rejected_edit(cx: &mut TestAppContext) {
        let (editor, cx) = cx.add_window_view(|_, cx| {
            TextInput::new(
                "saved".into(),
                String::new(),
                true,
                Rc::new(|_, _| {}),
                Rc::new(|_, _| {}),
                cx,
            )
        });
        cx.update(|window, cx| {
            editor.update(cx, |editor, cx| {
                editor.replace_text_in_range(Some(0..5), "rejected", window, cx);
                editor.acknowledge("rejected", cx);
                assert_eq!(editor.content.as_ref(), "saved");
                assert_eq!(editor.selection, 5..5);
            })
        });
    }

    #[gpui::test]
    fn acknowledgement_preserves_accepted_caret_and_newer_preedit(cx: &mut TestAppContext) {
        let (editor, cx) = cx.add_window_view(|_, cx| {
            TextInput::new(
                "ab".into(),
                String::new(),
                true,
                Rc::new(|_, _| {}),
                Rc::new(|_, _| {}),
                cx,
            )
        });
        cx.update(|window, cx| {
            editor.update(cx, |editor, cx| {
                editor.replace_text_in_range(Some(1..1), "x", window, cx);
                editor.configure("axb", "", true, Rc::new(|_, _| {}), Rc::new(|_, _| {}), cx);
                editor.acknowledge("axb", cx);
                assert_eq!(editor.selection, 2..2);
                editor.replace_and_mark_text_in_range(Some(2..2), "z", None, window, cx);
                editor.acknowledge("axb", cx);
                assert_eq!(editor.content.as_ref(), "axzb");
                assert_eq!(editor.marked, Some(2..3));
            })
        });
    }

    #[gpui::test]
    fn earlier_turn_does_not_overwrite_a_newer_queued_edit(cx: &mut TestAppContext) {
        let (editor, cx) = cx.add_window_view(|_, cx| {
            TextInput::new(
                String::new(),
                String::new(),
                true,
                Rc::new(|_, _| {}),
                Rc::new(|_, _| {}),
                cx,
            )
        });
        cx.update(|window, cx| {
            editor.update(cx, |editor, cx| {
                editor.replace_text_in_range(None, "a", window, cx);
                editor.replace_text_in_range(None, "b", window, cx);
                editor.begin_acknowledgement("a");
                editor.configure("a", "", true, Rc::new(|_, _| {}), Rc::new(|_, _| {}), cx);
                editor.acknowledge("a", cx);
                assert_eq!(editor.content.as_ref(), "ab");
                editor.begin_acknowledgement("ab");
                editor.configure("ab", "", true, Rc::new(|_, _| {}), Rc::new(|_, _| {}), cx);
                editor.acknowledge("ab", cx);
                assert_eq!(editor.content.as_ref(), "ab");
                assert_eq!(editor.selection, 2..2);
            })
        });
    }
}

struct TextElement {
    input: Entity<TextInput>,
}
struct Prepaint {
    cursor: Option<PaintQuad>,
    selection: Option<PaintQuad>,
}

impl IntoElement for TextElement {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl Element for TextElement {
    type RequestLayoutState = Rc<RefCell<Option<ShapedLine>>>;
    type PrepaintState = Prepaint;
    fn id(&self) -> Option<ElementId> {
        None
    }
    fn source_location(&self) -> Option<&'static core::panic::Location<'static>> {
        None
    }

    fn request_layout(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        window: &mut Window,
        _: &mut App,
    ) -> (LayoutId, Self::RequestLayoutState) {
        let state = Rc::new(RefCell::new(None));
        let out = state.clone();
        let input = self.input.clone();
        let text_style = window.text_style();
        let font_size = text_style.font_size.to_pixels(window.rem_size());
        let line_height = window.line_height();
        let mut style = Style::default();
        style.min_size.width = relative(1.).into();
        let id = window.request_measured_layout(style, move |known, _, window, cx| {
            let input = input.read(cx);
            let placeholder = input.content.is_empty();
            let text: SharedString = if placeholder {
                input.placeholder.clone()
            } else {
                input.content.clone()
            };
            let run = TextRun {
                len: text.len(),
                font: text_style.font(),
                color: if placeholder {
                    text_style.color.opacity(0.55)
                } else {
                    text_style.color
                },
                background_color: None,
                underline: input.marked.as_ref().map(|_| UnderlineStyle {
                    color: Some(text_style.color),
                    thickness: px(1.),
                    wavy: false,
                }),
                strikethrough: None,
            };
            let line = window
                .text_system()
                .shape_line(text, font_size, &[run], None);
            let width = known.width.unwrap_or(line.width + px(2.));
            out.borrow_mut().replace(line);
            size(width, line_height)
        });
        (id, state)
    }

    fn prepaint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        bounds: Bounds<Pixels>,
        state: &mut Self::RequestLayoutState,
        _: &mut Window,
        cx: &mut App,
    ) -> Prepaint {
        let input = self.input.read(cx);
        let borrowed = state.borrow();
        let line = borrowed.as_ref().unwrap();
        let height = bounds.size.height;
        let cursor = input.selection.is_empty().then(|| {
            fill(
                Bounds::new(
                    point(
                        bounds.left() + line.x_for_index(input.cursor()),
                        bounds.top(),
                    ),
                    size(px(2.), height),
                ),
                rgba(0x70c5e8ff),
            )
        });
        let selection = (!input.selection.is_empty()).then(|| {
            fill(
                Bounds::new(
                    point(
                        bounds.left() + line.x_for_index(input.selection.start),
                        bounds.top(),
                    ),
                    size(
                        line.x_for_index(input.selection.end)
                            - line.x_for_index(input.selection.start),
                        height,
                    ),
                ),
                rgba(0x70c5e845),
            )
        });
        Prepaint { cursor, selection }
    }

    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        bounds: Bounds<Pixels>,
        state: &mut Self::RequestLayoutState,
        prepaint: &mut Prepaint,
        window: &mut Window,
        cx: &mut App,
    ) {
        let focus = self.input.read(cx).focus.clone();
        window.handle_input(
            &focus,
            ElementInputHandler::new(bounds, self.input.clone()),
            cx,
        );
        if let Some(selection) = prepaint.selection.take() {
            window.paint_quad(selection);
        }
        let line = state.borrow_mut().take().unwrap();
        line.paint(
            bounds.origin,
            bounds.size.height,
            gpui::TextAlign::Left,
            None,
            window,
            cx,
        )
        .unwrap();
        if focus.is_focused(window)
            && let Some(cursor) = prepaint.cursor.take()
        {
            window.paint_quad(cursor);
        }
        self.input.update(cx, |input, _| {
            input.layout = Some(line);
            input.bounds = Some(bounds);
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf16_selection_offsets_land_on_utf8_boundaries() {
        let text = "a🦀é";
        assert_eq!(utf16_offset(text, 0), 0);
        assert_eq!(utf16_offset(text, 1), 1);
        assert_eq!(utf16_offset(text, 2), 5);
        assert_eq!(utf16_offset(text, 3), 5);
        assert_eq!(utf16_offset(text, 4), 7);
    }

    #[test]
    fn text_limit_is_explicit_and_bounded() {
        assert_eq!(MAX_TEXT_BYTES, 1024 * 1024);
    }
}
