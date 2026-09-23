//! The viewport of a virtual list whose rows the application produces on
//! demand.
//!
//! Such a list mounts only a window of its rows. Which window is a fact about
//! the viewport, and the viewport belongs to the host: GPUI reports the rows
//! it shows, and an application's scroll request moves them. This module holds
//! that fact for each list, keyed by the list's own render boundary, because
//! the list node itself is replaced every time its window moves.
//!
//! The semantic runner has no viewport. It uses the same model with the one
//! extent it does know, the window the application asked for, so a
//! specification sees the rows a window of that size would build, and a scroll
//! request moves them exactly as it would on screen.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ops::Range;
use std::sync::atomic::{AtomicU64, Ordering};

/// Where a requested row is placed in the viewport.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Align {
    Start,
    Center,
    End,
}

/// A viewport event for the list's Roc route.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct RowsEvent {
    /// The mounted window no longer covers the rows near the viewport.
    pub refresh: bool,
    /// The visible rows changed and the application asked to hear of it.
    pub report: bool,
    pub start: u64,
    pub end: u64,
}

/// One list's viewport, in rows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Viewport {
    /// How many rows the viewport shows at once.
    rows: u64,
    /// The rows the viewport intersects.
    visible: Range<u64>,
    /// The serial of the last scroll request applied, so a request held in
    /// state across renders moves the list once.
    applied: Option<u64>,
    /// The visible rows last reported to the application.
    reported: Option<Range<u64>>,
    /// A requested position the native list has not yet taken up.
    pending_scroll: Option<(u64, Align)>,
}

impl Viewport {
    fn new(rows: u64) -> Self {
        let rows = rows.max(1);
        Self {
            rows,
            visible: 0..rows,
            applied: None,
            reported: None,
            pending_scroll: None,
        }
    }

    /// Keep the visible rows inside a list that may have shrunk.
    fn clamp(&mut self, count: u64) {
        let start = self.visible.start.min(count.saturating_sub(self.rows));
        self.visible = start..start.saturating_add(self.rows).min(count);
    }

    /// Apply a scroll request, once per serial.
    fn request(&mut self, count: u64, row: u64, align: u8, serial: u64) {
        if align == 0 || self.applied == Some(serial) {
            return;
        }
        self.applied = Some(serial);
        if count == 0 {
            return;
        }
        let row = row.min(count - 1);
        let rows = self.rows;
        let placed = match align {
            1 => Some(Align::Start),
            2 => Some(Align::Center),
            3 => Some(Align::End),
            _ if row < self.visible.start => Some(Align::Start),
            _ if row >= self.visible.end => Some(Align::End),
            _ => None,
        };
        let Some(placed) = placed else {
            return;
        };
        let start = match placed {
            Align::Start => row,
            Align::Center => row.saturating_sub(rows / 2),
            Align::End => (row + 1).saturating_sub(rows),
        }
        .min(count.saturating_sub(rows));
        self.visible = start..start.saturating_add(rows).min(count);
        self.pending_scroll = Some((row, placed));
    }

    /// The rows worth building: the visible rows and one viewport either side,
    /// so ordinary scrolling reaches built rows before it reaches the edge.
    fn window(&self, count: u64) -> Range<u64> {
        let start = self.visible.start.saturating_sub(self.rows);
        let end = self.visible.end.saturating_add(self.rows).min(count);
        start.min(end)..end
    }

    /// Record the rows GPUI drew, and say what the list's route must hear.
    fn observe(
        &mut self,
        visible: Range<u64>,
        count: u64,
        mounted: Range<u64>,
        notify: bool,
    ) -> Option<RowsEvent> {
        // A requested position not yet taken up describes where the list is
        // going; the frame describes where it was.
        if self.pending_scroll.is_some() {
            return None;
        }
        self.rows = (visible.end - visible.start).max(1);
        self.visible = visible.clone();
        let guard = (self.rows / 2).max(1);
        let refresh = (mounted.start > 0 && visible.start < mounted.start.saturating_add(guard))
            || (mounted.end < count && visible.end.saturating_add(guard) > mounted.end);
        let report = notify && self.reported.as_ref() != Some(&visible);
        if report {
            self.reported = Some(visible.clone());
        }
        (refresh || report).then_some(RowsEvent {
            refresh,
            report,
            start: visible.start,
            end: visible.end,
        })
    }
}

thread_local! {
    static VIEWPORTS: RefCell<HashMap<u64, Viewport>> = RefCell::new(HashMap::new());
    static EVENT: RefCell<Option<RowsEvent>> = const { RefCell::new(None) };
}

/// Roc turns the viewport started. A window specification settles only once
/// these stop, because each one replaces the list the frame just drew.
static TURNS: AtomicU64 = AtomicU64::new(0);

/// The rows a provided list should mount, applying any new scroll request.
///
/// `estimate` is the viewport height in rows before GPUI has drawn the list,
/// which is the window's own height: a list cannot show more than that.
pub(crate) fn window(
    instance: u64,
    count: u64,
    estimate: u64,
    request: (u64, u8, u64),
) -> Range<u64> {
    VIEWPORTS.with(|viewports| {
        let mut viewports = viewports.borrow_mut();
        let viewport = viewports
            .entry(instance)
            .or_insert_with(|| Viewport::new(estimate));
        viewport.clamp(count);
        let (row, align, serial) = request;
        viewport.request(count, row, align, serial);
        viewport.window(count)
    })
}

/// The requested position the native list must take up, once.
pub(crate) fn take_pending_scroll(instance: u64) -> Option<(u64, Align)> {
    VIEWPORTS.with(|viewports| {
        viewports
            .borrow_mut()
            .get_mut(&instance)
            .and_then(|viewport| viewport.pending_scroll.take())
    })
}

/// Record the rows a GPUI frame showed for a provided list.
pub(crate) fn observe(
    instance: u64,
    visible: Range<u64>,
    count: u64,
    mounted: Range<u64>,
    notify: bool,
) -> Option<RowsEvent> {
    VIEWPORTS.with(|viewports| {
        viewports
            .borrow_mut()
            .get_mut(&instance)
            .and_then(|viewport| viewport.observe(visible, count, mounted, notify))
    })
}

/// Forget the viewports of render boundaries that left the graph.
pub(crate) fn retire(instances: impl IntoIterator<Item = u64>) {
    VIEWPORTS.with(|viewports| {
        let mut viewports = viewports.borrow_mut();
        for instance in instances {
            viewports.remove(&instance);
        }
    });
}

pub(crate) fn clear() {
    VIEWPORTS.with(|viewports| viewports.borrow_mut().clear());
    EVENT.with(|event| event.borrow_mut().take());
}

/// Install the payload a viewport dispatch delivers.
pub(crate) fn begin_event(event: RowsEvent) {
    EVENT.with(|slot| {
        assert!(
            slot.borrow_mut().replace(event).is_none(),
            "nested viewport dispatch"
        );
    });
    TURNS.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn end_event() {
    EVENT.with(|slot| slot.borrow_mut().take());
}

/// The payload of the viewport dispatch in progress. Outside one, nothing is
/// asked of the list.
pub(crate) fn event() -> RowsEvent {
    EVENT.with(|slot| *slot.borrow()).unwrap_or(RowsEvent {
        refresh: false,
        report: false,
        start: 0,
        end: 0,
    })
}

pub(crate) fn turns() -> u64 {
    TURNS.load(Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_list_mounts_its_viewport_and_one_viewport_either_side() {
        let viewport = Viewport::new(10);
        assert_eq!(viewport.window(1_000_000), 0..20);
        let mut scrolled = viewport.clone();
        scrolled.visible = 500..510;
        assert_eq!(scrolled.window(1_000_000), 490..520);
        assert_eq!(scrolled.window(505), 490..505);
    }

    #[test]
    fn a_scroll_request_moves_the_list_once_per_serial() {
        let mut viewport = Viewport::new(10);
        viewport.request(1_000_000, 500_000, 1, 7);
        assert_eq!(viewport.visible, 500_000..500_010);
        assert_eq!(viewport.pending_scroll, Some((500_000, Align::Start)));
        viewport.pending_scroll = None;
        // The person scrolls away; the same request held in state does not
        // pull the list back.
        viewport.visible = 0..10;
        viewport.request(1_000_000, 500_000, 1, 7);
        assert_eq!(viewport.visible, 0..10);
        // A new serial moves it again, even to the same row.
        viewport.request(1_000_000, 500_000, 3, 8);
        assert_eq!(viewport.visible, 499_991..500_001);
        assert_eq!(viewport.pending_scroll, Some((500_000, Align::End)));
    }

    #[test]
    fn centred_and_edge_requests_stay_inside_the_list() {
        let mut viewport = Viewport::new(10);
        viewport.request(100, 50, 2, 1);
        assert_eq!(viewport.visible, 45..55);
        viewport.request(100, 99, 1, 2);
        assert_eq!(viewport.visible, 90..100);
        viewport.request(100, 1_000, 1, 3);
        assert_eq!(viewport.visible, 90..100);
        viewport.request(100, 0, 3, 4);
        assert_eq!(viewport.visible, 0..10);
        let mut empty = Viewport::new(10);
        empty.request(0, 5, 1, 1);
        assert_eq!(empty.window(0), 0..0);
    }

    #[test]
    fn nearest_moves_only_a_row_that_is_out_of_view() {
        let mut viewport = Viewport::new(10);
        viewport.visible = 20..30;
        viewport.request(100, 25, 4, 1);
        assert_eq!(viewport.visible, 20..30);
        assert_eq!(viewport.pending_scroll, None);
        viewport.request(100, 40, 4, 2);
        assert_eq!(viewport.visible, 31..41);
        assert_eq!(viewport.pending_scroll, Some((40, Align::End)));
        viewport.request(100, 3, 4, 3);
        assert_eq!(viewport.visible, 3..13);
        assert_eq!(viewport.pending_scroll, Some((3, Align::Start)));
    }

    #[test]
    fn a_shrunk_list_keeps_its_viewport_inside_it() {
        let mut viewport = Viewport::new(10);
        viewport.visible = 90..100;
        viewport.clamp(40);
        assert_eq!(viewport.visible, 30..40);
        viewport.clamp(4);
        assert_eq!(viewport.visible, 0..4);
    }

    #[test]
    fn the_route_hears_of_a_window_edge_and_of_new_visible_rows() {
        let mut viewport = Viewport::new(10);
        // Well inside the mounted rows: nothing to rebuild, and nobody asked.
        assert_eq!(viewport.observe(10..20, 1_000, 0..40, false), None);
        // Within half a viewport of the mounted edge: rebuild.
        let event = viewport.observe(26..36, 1_000, 0..40, false).unwrap();
        assert!(event.refresh && !event.report);
        // At the true end of the list there is nothing further to build.
        assert_eq!(viewport.observe(990..1_000, 1_000, 970..1_000, false), None);
        // A listener hears each distinct range once.
        let heard = viewport.observe(10..20, 1_000, 0..40, true).unwrap();
        assert!(heard.report && !heard.refresh);
        assert_eq!((heard.start, heard.end), (10, 20));
        assert_eq!(viewport.observe(10..20, 1_000, 0..40, true), None);
    }

    #[test]
    fn a_frame_before_the_requested_scroll_does_not_undo_it() {
        let mut viewport = Viewport::new(10);
        viewport.request(1_000, 500, 1, 1);
        assert_eq!(viewport.observe(0..10, 1_000, 490..520, true), None);
        assert_eq!(viewport.visible, 500..510);
        viewport.pending_scroll = None;
        let event = viewport.observe(500..510, 1_000, 490..520, true).unwrap();
        assert!(event.report && !event.refresh);
    }
}
