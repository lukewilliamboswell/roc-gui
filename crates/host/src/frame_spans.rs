//! The host element that owns, and therefore measures, its GPUI frame work.
//!
//! The application's whole element tree hangs below one instance of
//! [`FrameSpans`], returned by `Runtime::render`. GPUI drives an element in
//! three calls — `request_layout`, `prepaint`, `paint` — and each of those, on
//! this element, performs that stage for the entire application subtree. The
//! durations recorded here are therefore the element's own work, not a stage
//! timed from outside and attributed inward.
//!
//! What GPUI does not let the host own, this element does not claim:
//!
//! - **Layout solve.** `Window::compute_layout` runs taffy once for the window,
//!   from `AnyElement::prepaint_as_root` on GPUI's root element, between this
//!   element's `request_layout` and its `prepaint`. No host-owned element is on
//!   the stack for it, so it is reported unavailable rather than folded into
//!   either neighbour. `layout_request_ns` is the stage this element does own:
//!   building the subtree's styles and layout nodes.
//! - **Presentation.** `Window::present` and `Window::complete_frame` are
//!   private to `gpui`, and `PlatformWindow::completed_frame` is not reachable
//!   from a dependent crate. A Wayland frame callback would be the honest seam
//!   and is not available on macOS. Presentation stays unavailable.
//!
//! Native work counters run independently of capture. Runtime::render supplies
//! the baseline before constructing the root view element, and completing paint
//! publishes that frame's observed delta. Abandoned frames are not published.

use std::panic::Location;
use std::time::Instant;

use gpui::{
    AnyElement, App, Bounds, Element, ElementId, GlobalElementId, InspectorElementId, IntoElement,
    LayoutId, Pixels, Window,
};

use crate::observatory;

/// Wraps the application's root element and records its own stage durations.
pub struct FrameSpans {
    child: AnyElement,
    layout_request_ns: u64,
    prepaint_ns: u64,
    native_start: observatory::NativeWork,
}

impl FrameSpans {
    pub fn new(child: impl IntoElement, native_start: observatory::NativeWork) -> Self {
        Self {
            child: child.into_any_element(),
            layout_request_ns: 0,
            prepaint_ns: 0,
            native_start,
        }
    }
}

fn elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}

impl IntoElement for FrameSpans {
    type Element = Self;

    fn into_element(self) -> Self::Element {
        self
    }
}

impl Element for FrameSpans {
    type RequestLayoutState = ();
    type PrepaintState = ();

    fn id(&self) -> Option<ElementId> {
        None
    }

    fn source_location(&self) -> Option<&'static Location<'static>> {
        None
    }

    fn request_layout(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, Self::RequestLayoutState) {
        if !observatory::active() {
            return (self.child.request_layout(window, cx), ());
        }
        let started = Instant::now();
        let layout_id = self.child.request_layout(window, cx);
        self.layout_request_ns = elapsed_ns(started);
        (layout_id, ())
    }

    fn prepaint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut Self::RequestLayoutState,
        window: &mut Window,
        cx: &mut App,
    ) {
        if !observatory::active() {
            self.child.prepaint(window, cx);
            return;
        }
        let started = Instant::now();
        self.child.prepaint(window, cx);
        self.prepaint_ns = elapsed_ns(started);
    }

    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        _: &mut Self::RequestLayoutState,
        _: &mut Self::PrepaintState,
        window: &mut Window,
        cx: &mut App,
    ) {
        if !observatory::active() {
            self.child.paint(window, cx);
            observatory::complete_native_frame(self.native_start);
            return;
        }
        let started = Instant::now();
        self.child.paint(window, cx);
        let paint_ns = elapsed_ns(started);
        let native_work = observatory::complete_native_frame(self.native_start);
        // The frame row is submitted from the stage that completes it, so a
        // frame abandoned before paint records nothing rather than a partial
        // row whose missing stage would have to be invented.
        observatory::gpui_frame(
            self.layout_request_ns,
            self.prepaint_ns,
            paint_ns,
            native_work,
        );
    }
}
