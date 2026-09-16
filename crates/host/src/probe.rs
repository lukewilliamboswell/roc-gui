//! Laid-out bounds for mounted nodes, recorded from the production render path.
//!
//! GPUI 0.2.2 exposes element bounds outside `test-support` only through
//! `canvas`'s prepaint closure — the idiom `NodeView::render` already uses for
//! canvas hit testing. This module reuses it to record where each node was laid
//! out, so the window runner can dispatch input at real coordinates and crop
//! screenshots to a located element.
//!
//! Recording is off unless a window specification asked for it. The gate is a
//! runtime atomic rather than a `#[cfg]`, because a compile-time switch would
//! mean the shipped binary is not the tested binary.
//!
//! # Why bounds persist across frames
//!
//! GPUI caches views: a `NodeView` whose state did not change is not
//! re-rendered, so its prepaint closure does not run again and it records
//! nothing that frame. Treating "absent this frame" as "not laid out" would
//! therefore report a perfectly visible, unchanged control as missing. Bounds
//! are kept until the node leaves the mounted graph, and [`retain_mounted`]
//! prunes them when it does.
//!
//! # What this cannot see
//!
//! * Nodes that never render have no bounds. That is the intended signal, not a
//!   gap: an unmaterialized virtual-list row is genuinely absent from the frame.
//! * Only a canvas node's own rect is recorded, never its primitives.
//! * Bounds *are* recorded for nodes scrolled out of view — they are laid out,
//!   merely clipped. Visibility is therefore a question for the caller, which
//!   must intersect against scroll ancestors; `bounds().is_some()` alone would
//!   be a lie.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};

use gpui::{Bounds, IntoElement, Pixels, canvas, prelude::*};

/// A laid-out rectangle in window coordinates, logical pixels.
///
/// Deliberately not a gpui type: the screenshot geometry that consumes it is a
/// pure function, and keeping this plain makes both testable without a window.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

impl Rect {
    pub fn width(self) -> f32 {
        self.right - self.left
    }

    pub fn height(self) -> f32 {
        self.bottom - self.top
    }

    pub fn is_empty(self) -> bool {
        self.width() <= 0.0 || self.height() <= 0.0
    }

    /// The overlap of two rectangles, or `None` when they do not overlap.
    pub fn intersect(self, other: Self) -> Option<Self> {
        let clipped = Self {
            left: self.left.max(other.left),
            top: self.top.max(other.top),
            right: self.right.min(other.right),
            bottom: self.bottom.min(other.bottom),
        };
        (!clipped.is_empty()).then_some(clipped)
    }

    /// The same rectangle, from a gpui one.
    pub fn from_gpui(bounds: Bounds<Pixels>) -> Self {
        Self::from_bounds(bounds)
    }

    fn from_bounds(bounds: Bounds<Pixels>) -> Self {
        Self {
            left: f32::from(bounds.origin.x),
            top: f32::from(bounds.origin.y),
            right: f32::from(bounds.origin.x + bounds.size.width),
            bottom: f32::from(bounds.origin.y + bounds.size.height),
        }
    }
}

static ENABLED: AtomicBool = AtomicBool::new(false);

thread_local! {
    /// Last known bounds per mounted node, in window coordinates.
    static RECORDED: RefCell<HashMap<u64, Rect>> = RefCell::new(HashMap::new());
}

/// Begin recording bounds. Called once, before the window opens.
pub fn enable() {
    ENABLED.store(true, Ordering::Relaxed);
}

#[inline]
pub fn enabled() -> bool {
    ENABLED.load(Ordering::Relaxed)
}

/// Record where a node was laid out. Called from the render path.
pub fn record(id: u64, bounds: Bounds<Pixels>) {
    RECORDED.with(|recorded| {
        recorded.borrow_mut().insert(id, Rect::from_bounds(bounds));
    });
}

/// Forget nodes that have left the mounted graph.
///
/// Only unmounted ids are dropped. Wiping everything would discard the bounds
/// of mounted nodes that GPUI chose not to re-render, which is most of them on
/// any given frame.
pub fn retain_mounted(live: &HashSet<u64>) {
    RECORDED.with(|recorded| {
        recorded.borrow_mut().retain(|id, _| live.contains(id));
    });
}

/// Where a node is laid out, if it has been laid out while mounted.
pub fn bounds(id: u64) -> Option<Rect> {
    RECORDED.with(|recorded| recorded.borrow().get(&id).copied())
}

/// How many of `ids` have been laid out, rather than merely mounted.
///
/// For a virtual list this is materialization evidence: a row that was never
/// rendered has no bounds, and a row that scrolled out of the mounted graph has
/// been pruned.
pub fn laid_out_count(ids: &[u64]) -> usize {
    RECORDED.with(|recorded| {
        let recorded = recorded.borrow();
        ids.iter().filter(|id| recorded.contains_key(id)).count()
    })
}

/// An invisible element that reports its parent's laid-out bounds.
pub fn marker(id: u64) -> impl IntoElement {
    canvas(move |bounds, _, _| record(id, bounds), |_, _, _, _| {})
        .absolute()
        .size_full()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(left: f32, top: f32, right: f32, bottom: f32) -> Rect {
        Rect {
            left,
            top,
            right,
            bottom,
        }
    }

    fn reset() {
        RECORDED.with(|recorded| recorded.borrow_mut().clear());
    }

    fn stage(id: u64, value: Rect) {
        RECORDED.with(|recorded| {
            recorded.borrow_mut().insert(id, value);
        });
    }

    #[test]
    fn intersection_clips_and_rejects_disjoint_rects() {
        let viewport = rect(0.0, 0.0, 100.0, 100.0);
        assert_eq!(
            rect(50.0, 50.0, 150.0, 150.0).intersect(viewport),
            Some(rect(50.0, 50.0, 100.0, 100.0))
        );
        assert_eq!(rect(200.0, 0.0, 300.0, 50.0).intersect(viewport), None);
        // Touching edges share no area, so they do not intersect.
        assert_eq!(rect(100.0, 0.0, 200.0, 50.0).intersect(viewport), None);
    }

    #[test]
    fn geometry_helpers_agree() {
        let value = rect(10.0, 20.0, 40.0, 60.0);
        assert_eq!(value.width(), 30.0);
        assert_eq!(value.height(), 40.0);
        assert!(!value.is_empty());
        assert!(rect(10.0, 10.0, 10.0, 20.0).is_empty());
    }

    #[test]
    fn recorded_bounds_are_queryable() {
        reset();
        assert_eq!(bounds(7), None);
        stage(7, rect(0.0, 0.0, 10.0, 10.0));
        assert_eq!(bounds(7), Some(rect(0.0, 0.0, 10.0, 10.0)));
        assert_eq!(laid_out_count(&[7, 8]), 1);
    }

    /// The regression this module was restructured for: GPUI does not
    /// re-render an unchanged view, so a node that records nothing this frame
    /// is still laid out and must keep its bounds.
    #[test]
    fn bounds_survive_frames_that_did_not_re_render_the_node() {
        reset();
        stage(1, rect(0.0, 0.0, 5.0, 5.0));
        stage(2, rect(5.0, 0.0, 10.0, 5.0));
        // A frame in which only node 2 re-rendered.
        stage(2, rect(5.0, 0.0, 12.0, 5.0));
        retain_mounted(&HashSet::from([1, 2]));
        assert_eq!(bounds(1), Some(rect(0.0, 0.0, 5.0, 5.0)));
        assert_eq!(bounds(2), Some(rect(5.0, 0.0, 12.0, 5.0)));
    }

    #[test]
    fn unmounted_nodes_are_pruned() {
        reset();
        stage(1, rect(0.0, 0.0, 5.0, 5.0));
        stage(2, rect(5.0, 0.0, 10.0, 5.0));
        retain_mounted(&HashSet::from([2]));
        assert_eq!(bounds(1), None);
        assert!(bounds(2).is_some());
        assert_eq!(laid_out_count(&[1, 2]), 1);
    }

    #[test]
    fn a_mounted_node_that_never_rendered_has_no_bounds() {
        reset();
        stage(1, rect(0.0, 0.0, 5.0, 5.0));
        // Node 9 is mounted but was never laid out.
        retain_mounted(&HashSet::from([1, 9]));
        assert_eq!(bounds(9), None);
        assert_eq!(laid_out_count(&[1, 9]), 1);
    }
}
