//! Runs a specification against the real GPUI window.
//!
//! A sibling of [`crate::runner`], not an extension of it. The semantic runner
//! owns a [`MountedGraph`] and mutates it directly; this runner owns nothing and
//! drives the live `Runtime` through the same window, event route, and render
//! path an interactive session uses. It is spawned from inside
//! `Application::run`, in the position the GPUI smoke check already occupies.
//!
//! It runs exactly one lifecycle: no per-step remount, no bridge teardown
//! between steps. Benchmark measurement therefore belongs to the semantic
//! runner, and `spec::check_runner` refuses those steps here.

use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::time::Duration;

use gpui::{App, AppContext, AsyncApp, Keystroke, MouseMoveEvent, WindowHandle, point, px, size};

use crate::probe::{self, Rect};
use crate::screenshot::{self, ShotError};
use crate::spec::{
    BoundsExpectation, Command, Locator, Region, Screenshot, ScrollMotion, Spec, Step,
};
use crate::{Runtime, ScrollTracker, runner, task_counts};

/// Where a window run writes its evidence.
pub struct Options {
    pub report_path: PathBuf,
    pub shot_dir: PathBuf,
    pub timeout: Duration,
    pub require_shots: bool,
    /// The content size the application asked its window to open at, in
    /// points. Kept beside the size the window actually got so a run says
    /// which one it measured.
    pub requested_window: (f32, f32),
}

/// Why a step did not pass.
#[derive(Debug)]
pub enum StepError {
    /// A locator resolved to something other than exactly one node.
    LocatorMatched { locator: String, count: usize },
    /// The node exists in the graph but did not participate in a frame.
    NotPainted(String),
    /// The window has not drawn the graph this step is asking about.
    Stale { painted: u64, graph: u64 },
    /// Laid out, but clipped away by a scroll ancestor or the viewport.
    OffScreen { locator: String, bounds: Rect },
    /// A geometry expectation was not met.
    Geometry(String),
    /// The window did not go quiet before the deadline.
    Timeout { waited: Duration, outstanding: u64 },
    /// The window closed underneath the runner.
    WindowClosed,
    /// A screenshot could not be taken, and the run required one.
    Screenshot(ShotError),
    /// A key chord GPUI itself refused to parse.
    Keystroke { chord: String, detail: String },
    /// A character that cannot be sent as a keystroke.
    Untypable(char),
    /// The control does not accept pointer activation.
    NotClickable(String),
    /// Resting the pointer on this node reaches no hover handler and no popover.
    NotHoverable(String),
    /// A pointer press on this control reaches no click handler at all. A
    /// canvas takes coordinates through its pointer route, so a `click` step
    /// would otherwise report success having dispatched nothing.
    NoClickRoute(String),
    /// A modal dialog is capturing interaction.
    BehindDialog(String),
    /// A `scroll` step named something that does not scroll.
    NotScrollable(String),
    /// A `scroll :to` named a target that is not inside the region.
    NotInRegion { region: String, target: String },
    /// A step this runner does not implement reached it anyway.
    Unsupported(&'static str),
}

impl StepError {
    fn message(&self, line: usize) -> String {
        let detail = match self {
            Self::LocatorMatched { locator, count } => {
                format!("{locator} matched {count} nodes; expected exactly one")
            }
            Self::NotPainted(locator) => {
                format!("{locator} is mounted but was not painted in the last frame")
            }
            Self::Stale { painted, graph } => format!(
                "the window drew graph generation {painted} and the step asks about {graph}"
            ),
            Self::OffScreen { locator, bounds } => format!(
                "{locator} is laid out at ({:.1},{:.1})-({:.1},{:.1}) but is not on screen",
                bounds.left, bounds.top, bounds.right, bounds.bottom
            ),
            Self::Geometry(detail) => detail.clone(),
            Self::Timeout {
                waited,
                outstanding,
            } => format!(
                "settle timed out after {}ms with {outstanding} task(s) outstanding",
                waited.as_millis()
            ),
            Self::WindowClosed => "the window closed before the step ran".to_owned(),
            Self::Screenshot(error) => {
                format!(
                    "screenshot unavailable ({}): {}",
                    error.reason(),
                    error.hint()
                )
            }
            Self::Keystroke { chord, detail } => {
                format!("GPUI rejected the key chord {chord:?}: {detail}")
            }
            Self::Untypable(character) => {
                format!("cannot type {character:?} as a keystroke")
            }
            Self::NotClickable(locator) => {
                format!("{locator} does not accept pointer activation; it may be disabled")
            }
            Self::NotHoverable(locator) => {
                format!("{locator} has no hover handler and no popover anchors it")
            }
            Self::NoClickRoute(locator) => format!(
                "{locator} takes pointer coordinates, not a click; press it with a `drag` step under --host-run-spec"
            ),
            Self::BehindDialog(locator) => {
                format!("{locator} is behind an active dialog and cannot be clicked")
            }
            Self::NotScrollable(locator) => format!(
                "{locator} is not a scroll region or virtual list, so it cannot be scrolled"
            ),
            Self::NotInRegion { region, target } => {
                format!("{target} is not inside {region}, so scrolling {region} cannot reach it")
            }
            Self::Unsupported(kind) => format!(
                "step `{kind}` is semantic-only; run this specification with --host-run-spec"
            ),
        };
        format!("line {line}: {detail}")
    }
}

/// What one step did, for the report.
struct StepRecord {
    ordinal: usize,
    line: usize,
    kind: &'static str,
    status: &'static str,
    message: Option<String>,
    /// Present on screenshot steps: the name, file, and size or reason.
    shot: Option<ShotRecord>,
}

struct ShotRecord {
    name: String,
    file: Option<String>,
    bytes: u64,
    reason: Option<&'static str>,
    hint: Option<String>,
}

/// The whole run, for the report.
pub struct Outcome {
    spec_name: String,
    steps: Vec<StepRecord>,
    window: Option<(f32, f32)>,
    scale_factor: f32,
    failed: bool,
    /// Screenshot steps the run tolerated rather than captured.
    ///
    /// A run that photographed nothing proved nothing visual, so it is not a
    /// pass: it says so, and the suite decides whether it was allowed.
    unavailable_shots: usize,
}

impl Outcome {
    pub fn passed(&self) -> bool {
        !self.failed
    }
}

fn describe(locator: &Locator) -> String {
    locator.to_string()
}

/// Resolve a locator to exactly one live node id.
fn resolve(runtime: &Runtime, locator: &Locator) -> Result<u64, StepError> {
    let found = runner::matches(&runtime.graph, locator);
    if found.len() == 1 {
        Ok(found[0])
    } else {
        Err(StepError::LocatorMatched {
            locator: describe(locator),
            count: found.len(),
        })
    }
}

/// Where one node was laid out, in window coordinates.
///
/// A scrolling node is asked for its own rectangle rather than the probe's: the
/// probe marker is a child of the scrolling element and therefore travels with
/// the content, so once the region has moved it describes where the top of the
/// content now is rather than the viewport it is clipped to. GPUI records the
/// container on the tracked handle at every prepaint, and that does not move.
/// Where a node is, as of a frame the window has actually drawn.
///
/// A scroll region's probe marker travels with its content, so once the region
/// has moved the marker no longer describes the viewport the content is clipped
/// to. The region's own tracker does, and it is written at every prepaint, so
/// it is preferred where one exists and the recorded bounds answer otherwise.
fn node_rect(runtime: &Runtime, frame: &probe::Frame<'_>, id: u64) -> Option<Rect> {
    runtime
        .scroll_trackers
        .get(&id)
        .map(|tracker| Rect::from_gpui(tracker.viewport()))
        .filter(|rect| !rect.is_empty())
        .or_else(|| frame.bounds(id))
}

/// Bounds for a node that actually took part in the last frame.
fn painted_bounds(runtime: &Runtime, locator: &Locator) -> Result<Rect, StepError> {
    let id = resolve(runtime, locator)?;
    let frame = runtime.painted().map_err(stale)?;
    node_rect(runtime, &frame, id).ok_or_else(|| StepError::NotPainted(describe(locator)))
}

/// A graph the window has not drawn yet is a wait, not an answer.
fn stale(value: probe::Stale) -> StepError {
    StepError::Stale {
        painted: value.painted,
        graph: value.graph,
    }
}

/// How the window that answered differs from the window that was asked for.
///
/// A platform may refuse the size an application requests: a display smaller
/// than the request, or a window manager with its own view of where a window
/// may end. Every geometry answer afterwards is then about a window nobody
/// asked for, and an element laid out past the fold reads as "not on screen"
/// with nothing to say why. Returns the sentence that names the difference,
/// and nothing at all when the window opened at the size it was given.
fn window_shortfall(requested: (f32, f32), actual: Option<(f32, f32)>) -> Option<String> {
    let (want_width, want_height) = requested;
    let (got_width, got_height) = actual?;
    // Half a point of slack: a scale factor can round a size it did honour.
    let short = got_width + 0.5 < want_width || got_height + 0.5 < want_height;
    short.then(|| {
        format!(
            "the window opened at {got_width:.0}x{got_height:.0} points but the application asked for {want_width:.0}x{want_height:.0}, so content past the edge is clipped"
        )
    })
}

/// Whether a node is visible, not merely laid out.
///
/// Scroll-clipped content still records bounds, so the element rect is
/// intersected against the viewport and every scrolling ancestor. Testing only
/// that bounds exist would call a clipped element visible.
fn visible_rect(runtime: &Runtime, locator: &Locator, viewport: Rect) -> Result<Rect, StepError> {
    let id = resolve(runtime, locator)?;
    let frame = runtime.painted().map_err(stale)?;
    let bounds =
        node_rect(runtime, &frame, id).ok_or_else(|| StepError::NotPainted(describe(locator)))?;
    let mut clip = viewport;
    for ancestor in runtime.graph.scroll_ancestors(id) {
        if let Some(rect) = node_rect(runtime, &frame, ancestor) {
            clip = match clip.intersect(rect) {
                Some(value) => value,
                None => {
                    return Err(StepError::OffScreen {
                        locator: describe(locator),
                        bounds,
                    });
                }
            };
        }
    }
    bounds.intersect(clip).ok_or(StepError::OffScreen {
        locator: describe(locator),
        bounds,
    })
}

/// Compare a laid-out rectangle against a size expectation.
///
/// Reports every violated bound at once, so one run tells the whole story.
pub(crate) fn check_bounds(
    locator: &str,
    bounds: Rect,
    expectation: &BoundsExpectation,
) -> Result<(), StepError> {
    let width = bounds.width();
    let height = bounds.height();
    let mut violations = Vec::new();
    if let Some(min) = expectation.min_width
        && width < min as f32
    {
        violations.push(format!("width {width:.1} is below :min-width {min}"));
    }
    if let Some(max) = expectation.max_width
        && width > max as f32
    {
        violations.push(format!("width {width:.1} is above :max-width {max}"));
    }
    if let Some(min) = expectation.min_height
        && height < min as f32
    {
        violations.push(format!("height {height:.1} is below :min-height {min}"));
    }
    if let Some(max) = expectation.max_height
        && height > max as f32
    {
        violations.push(format!("height {height:.1} is above :max-height {max}"));
    }
    if violations.is_empty() {
        Ok(())
    } else {
        Err(StepError::Geometry(format!(
            "{locator}: {}",
            violations.join("; ")
        )))
    }
}

/// True once the host has been quiet for `frames` consecutive presented frames.
///
/// Split out from the await loop so the quiescence rule is testable without a
/// window.
pub(crate) fn quiet_enough<T: PartialEq>(history: &[T], frames: u32) -> bool {
    let frames = frames as usize;
    if history.len() <= frames {
        return false;
    }
    let tail = &history[history.len() - (frames + 1)..];
    tail.windows(2).all(|pair| pair[0] == pair[1])
}

/// Wait for the window to present `frames` consecutive quiet frames.
async fn settle(
    window: WindowHandle<Runtime>,
    frames: u32,
    timeout: Duration,
    cx: &mut AsyncApp,
) -> Result<(), StepError> {
    let started = std::time::Instant::now();
    // A viewport turn is host work as much as a task is: it replaces a list the
    // frame just drew, so a frame after one is not yet the settled picture.
    let activity = || (task_counts(), crate::rows::turns());
    let mut history = vec![activity()];
    while started.elapsed() < timeout {
        next_frame(window, cx).await?;
        history.push(activity());
        if quiet_enough(&history, frames) {
            account_through_now();
            prune_bounds(window, cx)?;
            return Ok(());
        }
    }
    let (accepted, completed) = task_counts();
    Err(StepError::Timeout {
        waited: started.elapsed(),
        outstanding: accepted.saturating_sub(completed),
    })
}

/// The worker completions the specification has waited for, or let land in a
/// step that waits for the window rather than for one completion.
static ACCOUNTED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// Every completion so far has been waited for.
fn account_through_now() {
    ACCOUNTED.store(task_counts().1, Ordering::Relaxed);
}

/// Await exactly one worker completion no earlier step waited for, rather
/// than quiescence.
///
/// An application whose timer restarts the moment a sample lands is never
/// task-quiet, so settling for it can only ever time out. What the step
/// actually claims is that one more accepted task has completed and its
/// patch has been applied, which is a fact the counters carry directly.
/// Frames apply completions, so the one this step waits for has often landed
/// during the step that started it; it is counted then, rather than waited for
/// again. An application that keeps a subscription open — a watch, a timer —
/// always has a task in flight, so waiting for the next completion instead
/// would wait on the subscription.
async fn await_completion(
    window: WindowHandle<Runtime>,
    timeout: Duration,
    cx: &mut AsyncApp,
) -> Result<(), StepError> {
    let started = std::time::Instant::now();
    let (accepted, completed) = task_counts();
    let accounted = ACCOUNTED.load(Ordering::Relaxed);
    if completed > accounted {
        ACCOUNTED.store(accounted + 1, Ordering::Relaxed);
        prune_bounds(window, cx)?;
        return Ok(());
    }
    // Nothing is in flight and nothing unaccounted has landed, so there is no
    // task for this step to wait for. Waiting for another would wait forever.
    if accepted == completed {
        prune_bounds(window, cx)?;
        return Ok(());
    }
    while started.elapsed() < timeout {
        next_frame(window, cx).await?;
        let (_, now) = task_counts();
        if now > accounted {
            ACCOUNTED.store(accounted + 1, Ordering::Relaxed);
            prune_bounds(window, cx)?;
            return Ok(());
        }
    }
    let (accepted, completed) = task_counts();
    Err(StepError::Timeout {
        waited: started.elapsed(),
        outstanding: accepted.saturating_sub(completed),
    })
}

/// Await `count` further timer fires, and the completion each one carries.
///
/// `settle` cannot serve a polling application: a clipboard watcher rearms its
/// read inside the completion that delivers the last one, so one task is
/// outstanding at every instant and the counts never hold still.
///
/// Counting *fires* rather than completions is what makes the step meaningful
/// after a `clipboard-text`. The semantic runner drives the timer itself, so its
/// ticks are exact; here the timer is real wall-clock and a completion may have
/// been in flight before the step began. A fire, by contrast, can only be one
/// that started after this step did, so the read it carries is guaranteed to see
/// what the preceding step put on the clipboard.
async fn advance_timer_fires(
    window: WindowHandle<Runtime>,
    count: u32,
    timeout: Duration,
    cx: &mut AsyncApp,
) -> Result<(), StepError> {
    let started = std::time::Instant::now();
    let target_fires = crate::timers::fired_count().saturating_add(u64::from(count));
    while started.elapsed() < timeout {
        next_frame(window, cx).await?;
        if crate::timers::fired_count() >= target_fires {
            // The fire has happened; its completion is what applies the state.
            // Waiting for one completion after that point costs at most one more
            // interval and cannot land before the fire we waited for.
            let completed = task_counts().1;
            while started.elapsed() < timeout {
                next_frame(window, cx).await?;
                if task_counts().1 > completed {
                    // One more frame, so that state has been laid out and
                    // painted before the next step asserts against it.
                    next_frame(window, cx).await?;
                    account_through_now();
                    prune_bounds(window, cx)?;
                    return Ok(());
                }
            }
            break;
        }
    }
    let (accepted, completed) = task_counts();
    Err(StepError::Timeout {
        waited: started.elapsed(),
        outstanding: accepted.saturating_sub(completed),
    })
}

/// Wait until the window has drawn the graph as it now stands.
///
/// A painted question is unanswerable until then, so waiting happens here once,
/// rather than in each assertion guessing at a number of frames.
async fn await_painted(
    window: WindowHandle<Runtime>,
    timeout: Duration,
    cx: &mut AsyncApp,
) -> Result<(), StepError> {
    let started = std::time::Instant::now();
    loop {
        let behind = window
            .update(cx, |runtime, _, _| runtime.painted().err())
            .map_err(|_| StepError::WindowClosed)?;
        let Some(behind) = behind else {
            return Ok(());
        };
        if started.elapsed() >= timeout {
            return Err(stale(behind));
        }
        next_frame(window, cx).await?;
    }
}

/// Drop recorded bounds for nodes that have left the mounted graph.
fn prune_bounds(window: WindowHandle<Runtime>, cx: &mut AsyncApp) -> Result<(), StepError> {
    window
        .update(cx, |runtime, _, _| {
            let live: std::collections::HashSet<u64> = runtime
                .graph
                .nodes_preorder()
                .into_iter()
                .map(|node| node.id)
                .collect();
            probe::retain_mounted(&live);
        })
        .map_err(|_| StepError::WindowClosed)
}

/// Await the next frame callback with a normal view invalidation.
async fn next_frame(window: WindowHandle<Runtime>, cx: &mut AsyncApp) -> Result<(), StepError> {
    let (sender, receiver) = async_channel::bounded::<()>(1);
    window
        .update(cx, |_, window, cx| {
            window.on_next_frame(move |_, _| {
                let _ = sender.try_send(());
            });
            // A forced Window::refresh bypasses all view caches. Request the
            // same ordinary invalidation as an application update instead.
            cx.notify();
        })
        .map_err(|_| StepError::WindowClosed)?;
    receiver
        .recv()
        .await
        .map_err(|_| StepError::WindowClosed)
        .map(|_| ())
}

/// Write the agent-facing report.
///
/// Hand-serialized, like the observatory's own formats: the host carries no
/// JSON dependency and this shape is small and stable.
fn write_report(path: &Path, outcome: &Outcome, options: &Options) -> std::io::Result<()> {
    fn escape(value: &str) -> String {
        let mut out = String::with_capacity(value.len());
        for character in value.chars() {
            match character {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                value if (value as u32) < 0x20 => {
                    out.push_str(&format!("\\u{:04x}", value as u32));
                }
                value => out.push(value),
            }
        }
        out
    }

    let mut json = String::new();
    json.push_str("{\n  \"schema_version\": 2,\n");
    json.push_str(&format!(
        "  \"spec\": {{ \"name\": \"{}\" }},\n",
        escape(&outcome.spec_name)
    ));
    // A run that photographed nothing proved nothing visual, so it does not
    // call itself a pass. Whether that is tolerable is the suite's judgement,
    // made once and out loud, rather than a silence here.
    json.push_str(&format!(
        "  \"run_mode\": \"window-scenario\",\n  \"outcome\": \"{}\",\n  \"unavailable_shots\": {},\n",
        if !outcome.passed() {
            "fail"
        } else if outcome.unavailable_shots > 0 {
            "degraded"
        } else {
            "pass"
        },
        outcome.unavailable_shots
    ));
    // The requested size is recorded whether or not the window was measured:
    // it is what the application asked for, and it is known even when the
    // window closed before anything could be measured about it.
    let (requested_width, requested_height) = options.requested_window;
    match outcome.window {
        Some((width, height)) => json.push_str(&format!(
            "  \"window\": {{ \"width_points\": {width:.0}, \"height_points\": {height:.0}, \"requested_width_points\": {requested_width:.0}, \"requested_height_points\": {requested_height:.0}, \"scale_factor\": {:.1} }},\n",
            outcome.scale_factor
        )),
        None => json.push_str(&format!(
            "  \"window\": {{ \"width_points\": null, \"height_points\": null, \"requested_width_points\": {requested_width:.0}, \"requested_height_points\": {requested_height:.0}, \"scale_factor\": null }},\n"
        )),
    }
    json.push_str(&format!(
        "  \"require_shots\": {},\n",
        options.require_shots
    ));
    json.push_str("  \"steps\": [\n");
    for (index, step) in outcome.steps.iter().enumerate() {
        json.push_str(&format!(
            "    {{ \"ordinal\": {}, \"line\": {}, \"kind\": \"{}\", \"status\": \"{}\"",
            step.ordinal, step.line, step.kind, step.status
        ));
        if let Some(message) = &step.message {
            json.push_str(&format!(", \"message\": \"{}\"", escape(message)));
        }
        if let Some(shot) = &step.shot {
            json.push_str(&format!(", \"name\": \"{}\"", escape(&shot.name)));
            match &shot.file {
                Some(file) => json.push_str(&format!(
                    ", \"file\": \"{}\", \"bytes\": {}",
                    escape(file),
                    shot.bytes
                )),
                None => {
                    if let Some(reason) = shot.reason {
                        json.push_str(&format!(", \"reason\": \"{reason}\""));
                    }
                    if let Some(hint) = &shot.hint {
                        json.push_str(&format!(", \"hint\": \"{}\"", escape(hint)));
                    }
                }
            }
        }
        json.push_str(" }");
        if index + 1 < outcome.steps.len() {
            json.push(',');
        }
        json.push('\n');
    }
    json.push_str("  ],\n  \"screenshots\": [\n");
    let shots: Vec<&ShotRecord> = outcome
        .steps
        .iter()
        .filter_map(|step| step.shot.as_ref())
        .collect();
    for (index, shot) in shots.iter().enumerate() {
        match &shot.file {
            Some(file) => json.push_str(&format!(
                "    {{ \"name\": \"{}\", \"file\": \"{}\", \"bytes\": {} }}",
                escape(&shot.name),
                escape(file),
                shot.bytes
            )),
            None => json.push_str(&format!(
                "    {{ \"name\": \"{}\", \"status\": \"unavailable\", \"reason\": \"{}\" }}",
                escape(&shot.name),
                shot.reason.unwrap_or("unknown")
            )),
        }
        if index + 1 < shots.len() {
            json.push(',');
        }
        json.push('\n');
    }
    json.push_str("  ]\n}\n");

    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, json)
}

fn check_native_work_full(
    work: Option<crate::observatory::NativeFrameWork>,
    gpui_work: Option<crate::observatory::GpuiFrameWorkObservation>,
    button_max: Option<u64>,
    boundary_max: Option<u64>,
    boundary_elements_max: Option<u64>,
    cached_prepaint_min: Option<u64>,
    cached_paint_min: Option<u64>,
    replayed_scene_min: Option<u64>,
    fresh_hitboxes_max: Option<u64>,
    fresh_mouse_listeners_max: Option<u64>,
    element_states_moved_min: Option<u64>,
) -> Result<(), StepError> {
    let work = work.ok_or_else(|| StepError::Geometry(
        "native work unavailable: mark-native-work and at least one completed frame are required".into()
    ))?;
    for (name, actual, maximum) in [
        ("button renders", work.max_rendered[1], button_max),
        ("boundary renders", work.max_rendered[15], boundary_max),
        (
            "boundary elements created",
            work.max_view_elements_created[15],
            boundary_elements_max,
        ),
    ] {
        if let Some(maximum) = maximum
            && actual > maximum
        {
            return Err(StepError::Geometry(format!(
                "expected {name} per completed frame <= {maximum}; observed maximum {actual} across {} frame(s)",
                work.frames
            )));
        }
    }
    if [
        cached_prepaint_min,
        cached_paint_min,
        replayed_scene_min,
        fresh_hitboxes_max,
        fresh_mouse_listeners_max,
        element_states_moved_min,
    ]
    .iter()
    .any(Option::is_some)
    {
        let gpui_work = gpui_work.ok_or_else(|| StepError::Geometry(
            "GPUI frame work unavailable: mark-native-work and a completed observed frame are required".into()
        ))?;
        for (name, actual, minimum) in [
            (
                "cached prepaint subtrees",
                gpui_work.max_counts[0],
                cached_prepaint_min,
            ),
            (
                "cached paint subtrees",
                gpui_work.max_counts[5],
                cached_paint_min,
            ),
            (
                "replayed scene operations",
                gpui_work.max_counts[6],
                replayed_scene_min,
            ),
            (
                "element states moved",
                gpui_work.max_counts[16],
                element_states_moved_min,
            ),
        ] {
            if let Some(minimum) = minimum
                && actual < minimum
            {
                return Err(StepError::Geometry(format!(
                    "expected {name} per completed frame >= {minimum}; observed maximum {actual} across {} frame(s)",
                    gpui_work.frames
                )));
            }
        }
        for (name, actual, maximum) in [
            (
                "fresh hitboxes",
                gpui_work.max_counts[12],
                fresh_hitboxes_max,
            ),
            (
                "fresh mouse listeners",
                gpui_work.max_counts[13],
                fresh_mouse_listeners_max,
            ),
        ] {
            if let Some(maximum) = maximum
                && actual > maximum
            {
                return Err(StepError::Geometry(format!(
                    "expected {name} per completed frame <= {maximum}; observed maximum {actual} across {} frame(s)",
                    gpui_work.frames
                )));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
fn check_native_work(
    work: Option<crate::observatory::NativeFrameWork>,
    button_max: Option<u64>,
    boundary_max: Option<u64>,
    boundary_elements_max: Option<u64>,
) -> Result<(), StepError> {
    check_native_work_full(
        work,
        None,
        button_max,
        boundary_max,
        boundary_elements_max,
        None,
        None,
        None,
        None,
        None,
        None,
    )
}

/// Run one step against the live window.
async fn run_step(
    step: &Step,
    ordinal: usize,
    window: WindowHandle<Runtime>,
    options: &Options,
    // File operation counts are differences from the start of the lifecycle, of
    // which this runner has exactly one, so the baseline is read once before the
    // first step rather than re-read here.
    file_baseline: [u64; 4],
    cx: &mut AsyncApp,
) -> Result<Option<ShotRecord>, StepError> {
    match &step.command {
        Command::Screenshot(request) => {
            // A photograph is the most painted question there is.
            await_painted(window, options.timeout, cx).await?;
            return take_screenshot(request, ordinal, window, options, cx).await;
        }
        Command::MarkNativeWork => window
            .update(cx, |_, _, _| {
                crate::observatory::mark_native_work();
                Ok(())
            })
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectNativeWork {
            button_renders_max,
            boundary_renders_max,
            boundary_elements_max,
            cached_prepaint_subtrees_min,
            cached_paint_subtrees_min,
            replayed_scene_operations_min,
            fresh_hitboxes_max,
            fresh_mouse_listeners_max,
            element_states_moved_min,
        } => window
            .update(cx, |_, _, _| {
                check_native_work_full(
                    crate::observatory::native_work_since_mark(),
                    crate::observatory::gpui_frame_work_since_mark(),
                    *button_renders_max,
                    *boundary_renders_max,
                    *boundary_elements_max,
                    *cached_prepaint_subtrees_min,
                    *cached_paint_subtrees_min,
                    *replayed_scene_operations_min,
                    *fresh_hitboxes_max,
                    *fresh_mouse_listeners_max,
                    *element_states_moved_min,
                )
            })
            .map_err(|_| StepError::WindowClosed)?,
        Command::Settle { frames, timeout_ms } => {
            settle(
                window,
                *frames,
                Duration::from_millis(u64::from(*timeout_ms)),
                cx,
            )
            .await
        }
        Command::HoverEnter(locator) | Command::HoverExit(locator) => {
            let entered = matches!(step.command, Command::HoverEnter(_));
            let viewport = viewport_rect(window, cx)?;
            let position = window
                .update(cx, |runtime, _, _| {
                    let id = resolve(runtime, locator)?;
                    if runtime.graph.hover_targets(id).is_empty() {
                        return Err(StepError::NotHoverable(describe(locator)));
                    }
                    let position = if entered {
                        let bounds = visible_rect(runtime, locator, viewport)?;
                        point(
                            px((bounds.left + bounds.right) / 2.0),
                            px((bounds.top + bounds.bottom) / 2.0),
                        )
                    } else {
                        point(px(-1.0), px(-1.0))
                    };
                    Ok::<_, StepError>(position)
                })
                .map_err(|_| StepError::WindowClosed)??;
            // Release the Runtime borrow before GPUI delivers callbacks into it.
            cx.update_window(window.into(), |_, window, cx| {
                window.dispatch_event(
                    gpui::PlatformInput::MouseMove(MouseMoveEvent {
                        position,
                        pressed_button: None,
                        modifiers: Default::default(),
                    }),
                    cx,
                );
            })
            .map_err(|_| StepError::WindowClosed)?;
            await_painted(window, options.timeout, cx).await
        }
        Command::PointerMove(locator, _, _)
        | Command::PointerLeave(locator)
        | Command::Wheel(locator, _, _, _, _) => {
            // The window's own pointer, at a point of the canvas's painted
            // surface: GPUI hit-tests it and the canvas's production
            // listeners turn it into the event, exactly as a person's would.
            let (x, y) = match &step.command {
                Command::PointerMove(_, x, y) | Command::Wheel(_, x, y, _, _) => (*x, *y),
                _ => (0, 0),
            };
            let origin = window
                .update(cx, |runtime, _, _| {
                    let id = resolve(runtime, locator)?;
                    let surface = runtime
                        .canvas_surfaces
                        .get(&id)
                        .and_then(|slot| *slot.lock().expect("canvas bounds poisoned"))
                        .ok_or_else(|| StepError::NotPainted(describe(locator)))?;
                    Ok::<_, StepError>(surface.origin)
                })
                .map_err(|_| StepError::WindowClosed)??;
            let position = point(origin.x + px(x as f32), origin.y + px(y as f32));
            let input = match &step.command {
                Command::PointerMove(..) => gpui::PlatformInput::MouseMove(MouseMoveEvent {
                    position,
                    pressed_button: None,
                    modifiers: Default::default(),
                }),
                Command::PointerLeave(_) => gpui::PlatformInput::MouseMove(MouseMoveEvent {
                    position: point(px(-1.0), px(-1.0)),
                    pressed_button: None,
                    modifiers: Default::default(),
                }),
                Command::Wheel(_, _, _, dx, dy) => {
                    gpui::PlatformInput::ScrollWheel(gpui::ScrollWheelEvent {
                        position,
                        // A scroll towards the content's end is negative in GPUI.
                        delta: gpui::ScrollDelta::Pixels(point(
                            px(-(*dx as f32)),
                            px(-(*dy as f32)),
                        )),
                        modifiers: Default::default(),
                        touch_phase: gpui::TouchPhase::Moved,
                    })
                }
                _ => unreachable!("matched a canvas pointer step above"),
            };
            // Release the Runtime borrow before GPUI delivers callbacks into it.
            cx.update_window(window.into(), |_, window, cx| {
                window.dispatch_event(input, cx);
            })
            .map_err(|_| StepError::WindowClosed)?;
            await_painted(window, options.timeout, cx).await
        }
        Command::Click(locator) => {
            let viewport = viewport_rect(window, cx)?;
            window
                .update(cx, |runtime, window, cx| {
                    let id = clickable_target(runtime, locator, viewport)?;
                    let takes_focus = runtime
                        .graph
                        .node(id)
                        .is_some_and(|node| node.kind.focuses_on_pointer());
                    if takes_focus {
                        // Clicking a text field focuses it. Without this the
                        // step would pass having done nothing, and a later
                        // `type` would go to whatever held focus before.
                        let handle = runtime.focus_handles.get(&id).cloned();
                        match handle {
                            Some(handle) => handle.focus(window, cx),
                            None => {
                                return Err(StepError::Geometry(format!(
                                    "{} accepts pointer focus but has no focus handle",
                                    describe(locator)
                                )));
                            }
                        }
                    } else {
                        // The same call the production `on_click` closure makes.
                        runtime.event_if_live(id, cx);
                    }
                    Ok::<(), StepError>(())
                })
                .map_err(|_| StepError::WindowClosed)??;
            // The click changed the graph on this thread, enqueuing nothing, so
            // the wait that means something is for the window to have drawn it.
            // A task the click started is the specification's to await.
            await_painted(window, options.timeout, cx).await
        }
        Command::Focus(locator) => {
            let id = window
                .update(cx, |runtime, _, _| resolve(runtime, locator))
                .map_err(|_| StepError::WindowClosed)??;
            let focused = window
                .update(cx, |runtime, window, cx| {
                    runtime.focus_handles.get(&id).map(|handle| {
                        // A person moving keyboard focus is at this window, and
                        // GPUI reports focus entering and leaving a region only
                        // in the active window. Concurrent cases each open one.
                        window.activate_window();
                        handle.focus(window, cx);
                    })
                })
                .map_err(|_| StepError::WindowClosed)?;
            if focused.is_none() {
                return Err(StepError::Geometry(format!(
                    "{} is not focusable",
                    describe(locator)
                )));
            }
            await_painted(window, options.timeout, cx).await
        }
        Command::PressKey(key) => {
            // The chord the production keymap binds for this activation key, so
            // the step exercises the real binding rather than a parallel table.
            let chord = match key {
                crate::bridge::ControlKey::Enter => "enter",
                crate::bridge::ControlKey::Escape => "escape",
                crate::bridge::ControlKey::Space => "space",
            };
            dispatch_chord(window, chord, cx)?;
            await_painted(window, options.timeout, cx).await
        }
        Command::Type(text) => {
            for character in text.chars() {
                let keystroke = typed_keystroke(character)?;
                cx.update_window(window.into(), |_, window, cx| {
                    window.dispatch_keystroke(keystroke, cx);
                })
                .map_err(|_| StepError::WindowClosed)?;
                // A keystroke changes the graph synchronously and enqueues no
                // task, so waiting on task counters would be waiting for
                // nothing. Wait for the window to have drawn the character.
                await_painted(window, options.timeout, cx).await?;
            }
            Ok(())
        }
        Command::Key(chord) => {
            dispatch_chord(window, chord, cx)?;
            await_painted(window, options.timeout, cx).await
        }
        Command::Resize { width, height } => {
            cx.update_window(window.into(), |_, window, _| {
                window.resize(size(px(*width as f32), px(*height as f32)));
            })
            .map_err(|_| StepError::WindowClosed)?;
            settle(window, 2, options.timeout, cx).await
        }
        Command::Scroll { region, motion } => {
            window
                .update(cx, |runtime, _, _| scroll_region(runtime, region, motion))
                .map_err(|_| StepError::WindowClosed)??;
            // Two frames: GPUI applies a virtual list's deferred scroll during
            // the next prepaint, and the rows it materializes are laid out in
            // the one after that.
            settle(window, 2, options.timeout, cx).await
        }
        // Deliberately the same claim the semantic runner makes: present in
        // the mounted graph. The stronger pixel claim is `expect-on-screen`, so
        // one word does not mean two different things on two runners.
        Command::ExpectVisible(locator) => window
            .update(cx, |runtime, _, _| resolve(runtime, locator).map(|_| ()))
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectOnScreen(locator) => {
            await_painted(window, options.timeout, cx).await?;
            let viewport = viewport_rect(window, cx)?;
            window
                .update(cx, |runtime, _, _| {
                    visible_rect(runtime, locator, viewport).map(|_| ())
                })
                .map_err(|_| StepError::WindowClosed)?
        }
        Command::ExpectRenderedCount(locator, expected) => {
            await_painted(window, options.timeout, cx).await?;
            window
                .update(cx, |runtime, _, _| {
                    let ids = runner::matches(&runtime.graph, locator);
                    let painted = runtime.painted().map_err(stale)?.laid_out_count(&ids);
                    if painted == *expected {
                        Ok(())
                    } else {
                        Err(StepError::Geometry(format!(
                            "{} laid out {painted} instances; expected {expected}",
                            describe(locator)
                        )))
                    }
                })
                .map_err(|_| StepError::WindowClosed)?
        }
        Command::ExpectBounds(locator, expectation) => {
            await_painted(window, options.timeout, cx).await?;
            window
                .update(cx, |runtime, _, _| {
                    let bounds = painted_bounds(runtime, locator)?;
                    check_bounds(&describe(locator), bounds, expectation)
                })
                .map_err(|_| StepError::WindowClosed)?
        }
        // Focus in a real window is answered by the focus handle the host
        // actually uses, rather than by a model of it.
        Command::ExpectFocused(locator) => window
            .update(cx, |runtime, window, _| {
                let id = resolve(runtime, locator)?;
                let focused = runtime
                    .focus_handles
                    .get(&id)
                    .is_some_and(|handle| handle.is_focused(window));
                if focused {
                    Ok(())
                } else {
                    Err(StepError::Geometry(format!(
                        "{} does not hold keyboard focus",
                        describe(locator)
                    )))
                }
            })
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectNotVisible(locator) => window
            .update(cx, |runtime, _, _| {
                let found = runner::matches(&runtime.graph, locator);
                if found.is_empty() {
                    Ok(())
                } else {
                    Err(StepError::Geometry(format!(
                        "{} matched {} nodes; expected none",
                        describe(locator),
                        found.len()
                    )))
                }
            })
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectCount(locator, expected) => window
            .update(cx, |runtime, _, _| {
                let found = runner::matches(&runtime.graph, locator).len();
                if found == *expected {
                    Ok(())
                } else {
                    Err(StepError::Geometry(format!(
                        "{} matched {found} nodes; expected {expected}",
                        describe(locator)
                    )))
                }
            })
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectAppAccess(expected) => window
            .update(cx, |_, _, _| {
                let open = crate::access_panel::is_open();
                if open == *expected {
                    Ok(())
                } else {
                    Err(StepError::Geometry(format!(
                        "expected the App access surface {}, observed {}",
                        if *expected { "open" } else { "closed" },
                        if open { "open" } else { "closed" }
                    )))
                }
            })
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectComponentWork(expected) => window
            .update(cx, |_, _, _| {
                runner::component_work_claim(expected)
                    .0
                    .map_err(StepError::Geometry)
            })
            .map_err(|_| StepError::WindowClosed)?,
        // The claims answered from the mounted graph alone, made by the
        // same code the semantic runner calls, so the word means one thing.
        Command::ExpectCanvasPrimitives(_, _)
        | Command::ExpectValue(_, _)
        | Command::ExpectValueBytes(_, _)
        | Command::ExpectImageBytes(_, _)
        | Command::ExpectRows(_, _)
        | Command::ExpectBefore(_, _)
        | Command::ExpectBackground(_, _)
        | Command::ExpectPopoverCounters(_)
        | Command::ExpectKeyboardCounters(_) => window
            .update(cx, |runtime, _, _| {
                runner::graph_claim(&runtime.graph, &step.command)
                    .expect("graph claim is missing an arm")
                    .0
                    .map_err(StepError::Geometry)
            })
            .map_err(|_| StepError::WindowClosed)?,
        // Claims about a process-global resource owner, answered by the same
        // shared reading the semantic runner uses, so a windowed case can
        // photograph a granted-authority readout and assert the counter that
        // produced it in one run. The observatory evidence the claim also
        // returns belongs to a capture, which this runner does not write.
        Command::ExpectSubscriptions(_)
        | Command::ExpectTcpStreams(_)
        | Command::ExpectProcesses(_)
        | Command::ExpectClipboardCounters(_)
        | Command::ExpectSqliteCounters(_)
        | Command::ExpectHttpCounters(_)
        | Command::ExpectTcpCounters(_)
        | Command::ExpectDeviceConnections(_)
        | Command::ExpectDeviceTransactions(_)
        | Command::ExpectSystemSamplers(_)
        | Command::ExpectSystemSamples(_)
        | Command::ExpectAudioCounters(_)
        | Command::ExpectFilePicks(_)
        | Command::ExpectFileLists(_)
        | Command::ExpectFileOpens(_)
        | Command::ExpectFileReads(_)
        | Command::ExpectFileSelectionCounters(_)
        | Command::ExpectFileLifecycleCounters(_)
        | Command::ExpectFileAccess(_)
        | Command::ExpectDocumentCounters(_)
        | Command::ExpectWatchCounters(_)
        | Command::ExpectAssetCounters(_)
        | Command::ExpectHashCounters(_)
        | Command::ExpectGrants(_)
        | Command::ExpectGrantCounters(_)
        | Command::ExpectImageOwnerCounters(_) => window
            .update(cx, |_, _, _| {
                runner::resource_claim(&step.command, file_baseline)
                    .expect("resource claim is missing an arm")
                    .0
                    .map_err(StepError::Geometry)
            })
            .map_err(|_| StepError::WindowClosed)?,
        // Revocation acts on the one files registry the host owns. It changes
        // no graph, so it presents no frame: what the application sees of it is
        // its next read, which is the next step's business.
        Command::RevokeFileGrants => window
            .update(cx, |_, _, _| {
                crate::files::revoke_all_roots();
                Ok(())
            })
            .map_err(|_| StepError::WindowClosed)?,
        // A file moved into place outside the application, which it sees
        // only through a watch, on its own schedule; the next step waits for it.
        Command::ReplaceFile { name, source } => {
            crate::files::replace_in_private_copy(name, source).map_err(StepError::Geometry)
        }
        Command::AwaitTask => await_completion(window, options.timeout, cx).await,
        // An application that polls — a clipboard watcher rearms its read on
        // every tick — never reaches the quiescence `settle` waits for, because
        // one task is outstanding at every instant by construction. `await-ticks`
        // therefore counts completions rather than waiting for there to be none,
        // which is also what the step means: apply N successive wait completions.
        Command::AwaitTicks(count) => {
            advance_timer_fires(window, *count, options.timeout, cx).await
        }
        // The fixture clipboard is one process-wide store, so changing the
        // granted source here is the same act the semantic runner performs. One
        // presented frame is all this step waits for; observing the change is
        // the application's own timer's job, and `await-ticks` waits for that.
        Command::ClipboardText(text) => match crate::clipboard::inject_fixture(text.clone()) {
            Err(detail) => Err(StepError::Geometry(detail)),
            Ok(()) => next_frame(window, cx).await,
        },
        Command::AwaitCount(locator, expected) => {
            // A terminal answers on its own schedule, not the window's, so this
            // presents frames until the graph holds what the step names rather
            // than until the window merely looks quiet.
            let deadline = std::time::Instant::now() + options.timeout;
            loop {
                let found = window
                    .update(cx, |runtime, _, _| {
                        runner::matches(&runtime.graph, locator).len()
                    })
                    .map_err(|_| StepError::WindowClosed)?;
                if found == *expected {
                    // The graph holding it is not the same as the window having
                    // drawn it, and the next step may ask where it is.
                    await_painted(window, options.timeout, cx).await?;
                    let drawn = window
                        .update(cx, |runtime, _, _| {
                            runner::matches(&runtime.graph, locator).len()
                        })
                        .map_err(|_| StepError::WindowClosed)?;
                    if drawn == *expected {
                        account_through_now();
                        break Ok(());
                    }
                }
                if std::time::Instant::now() >= deadline {
                    break Err(StepError::Geometry(format!(
                        "{} matched {found} nodes, expected {expected} within {}ms",
                        describe(locator),
                        options.timeout.as_millis()
                    )));
                }
                next_frame(window, cx).await?;
            }
        }
        // Unreachable: `spec::check_runner` refuses a specification whose
        // steps this runner does not implement, so the refusal happens before
        // the window opens rather than part-way through a run.
        other => Err(StepError::Unsupported(other.kind())),
    }
    .map(|()| None)
}

/// Resolve a locator to a control a real click could actually have activated.
///
/// Click and hover steps activate the production handler route directly.
/// What is *not* simulated here is whether the
/// click could have landed: the control must have been painted this frame, must
/// survive clipping by the viewport and its scrolling ancestors, must accept
/// pointer activation, and must satisfy the same modality rule the semantic
/// runner applies. Those are the checks a real pointer would have performed,
/// and they are answered from real laid-out geometry.
fn clickable_target(
    runtime: &Runtime,
    locator: &Locator,
    viewport: Rect,
) -> Result<u64, StepError> {
    let id = resolve(runtime, locator)?;
    // A pointer cannot reach what was never drawn, nor what is scrolled away.
    visible_rect(runtime, locator, viewport)?;
    let node = runtime
        .graph
        .node(id)
        .ok_or_else(|| StepError::NotPainted(describe(locator)))?;
    if matches!(node.kind, crate::bridge::NodeKind::Canvas { .. }) {
        return Err(StepError::NoClickRoute(describe(locator)));
    }
    if !node.kind.accepts_pointer() {
        return Err(StepError::NotClickable(describe(locator)));
    }
    if runtime
        .graph
        .active_dialog()
        .is_some_and(|dialog| !runtime.graph.is_descendant_of(id, dialog))
    {
        return Err(StepError::BehindDialog(describe(locator)));
    }
    Ok(id)
}

/// Move one scroll region, through the handle the production element tracks.
///
/// This writes the same offset cell GPUI's own wheel handler writes: the
/// element is given this handle with `track_scroll`, which replaces the offset
/// GPUI would otherwise keep in per-element state. What is not exercised is the
/// wheel event itself — hit testing, momentum, and rubber-banding belong to the
/// pointer seam this host does not have. The offset is clamped by GPUI against
/// the real content size at the next prepaint, so an overlarge request settles
/// at the end of the content rather than past it.
fn scroll_region(
    runtime: &Runtime,
    region: &Locator,
    motion: &ScrollMotion,
) -> Result<(), StepError> {
    let region_id = resolve(runtime, region)?;
    let tracker = runtime
        .scroll_trackers
        .get(&region_id)
        .ok_or_else(|| StepError::NotScrollable(describe(region)))?;
    match motion {
        ScrollMotion::By(amount) => {
            let horizontal = matches!(
                runtime.graph.node(region_id).map(|node| &node.kind),
                Some(crate::bridge::NodeKind::Scroll {
                    axis: crate::bridge::ScrollAxis::Horizontal,
                    ..
                })
            );
            let delta = if horizontal {
                point(px(*amount as f32), px(0.0))
            } else {
                point(px(0.0), px(*amount as f32))
            };
            tracker.scroll_by(delta);
            Ok(())
        }
        ScrollMotion::To(target) => {
            let target_id = resolve(runtime, target)?;
            if target_id == region_id || !runtime.graph.is_descendant_of(target_id, region_id) {
                return Err(StepError::NotInRegion {
                    region: describe(region),
                    target: describe(target),
                });
            }
            if let ScrollTracker::List(_) = tracker {
                // A row below the fold of a virtual list has no element and no
                // bounds, so the only thing that can name it is its position.
                let index = runtime
                    .graph
                    .child_index_containing(region_id, target_id)
                    .ok_or_else(|| StepError::NotInRegion {
                        region: describe(region),
                        target: describe(target),
                    })?;
                // A provided list mounts a window of its rows, so a mounted
                // row's position is counted from the window's first row.
                let first = match runtime.graph.node(region_id).map(|node| &node.kind) {
                    Some(crate::bridge::NodeKind::VirtualList {
                        rows: Some(rows), ..
                    }) => usize::try_from(rows.first).unwrap_or(usize::MAX),
                    _ => 0,
                };
                tracker.scroll_to_row(first.saturating_add(index));
                return Ok(());
            }
            // A scroll region lays every child out, below the fold included, so
            // the distance to travel is real geometry rather than an estimate.
            // It is read from the frame the preceding step settled, because a
            // graph the window has not drawn cannot say where anything is.
            let frame = runtime.painted().map_err(stale)?;
            let bounds = frame
                .bounds(target_id)
                .ok_or_else(|| StepError::NotPainted(describe(target)))?;
            let viewport = Rect::from_gpui(tracker.viewport());
            tracker.scroll_by(point(
                px(axis_delta(
                    bounds.left,
                    bounds.right,
                    viewport.left,
                    viewport.right,
                )),
                px(axis_delta(
                    bounds.top,
                    bounds.bottom,
                    viewport.top,
                    viewport.bottom,
                )),
            ));
            Ok(())
        }
    }
}

/// How far the content must move along one axis to bring `[near, far]` inside
/// `[low, high]`. Positive moves the content towards its end.
///
/// A target taller than the viewport is aligned to its leading edge: there is
/// no offset that shows all of it, and showing its start is what a person
/// scrolling to it would expect.
pub(crate) fn axis_delta(near: f32, far: f32, low: f32, high: f32) -> f32 {
    if near < low || far - near > high - low {
        near - low
    } else if far > high {
        far - high
    } else {
        0.0
    }
}

/// Where one canvas primitive sits, in window coordinates.
///
/// A line is expanded by half its stroke on every side, because a line's
/// coordinates describe its centre rather than its extent, and a zero-area
/// rectangle photographs nothing. The floor of one point keeps a hairline
/// visible in the result.
pub(crate) fn primitive_rect(canvas: Rect, item: &crate::bridge::CanvasPrimitive) -> Rect {
    use crate::bridge::CanvasPrimitiveKind;
    let (left, top, right, bottom) = match item.kind {
        CanvasPrimitiveKind::Rectangle | CanvasPrimitiveKind::Ellipse => (
            item.x as f32,
            item.y as f32,
            item.x as f32 + item.width as f32,
            item.y as f32 + item.height as f32,
        ),
        CanvasPrimitiveKind::Text => (
            item.x as f32,
            item.y as f32,
            item.x as f32 + item.width as f32,
            item.y as f32 + item.line_height() as f32,
        ),
        CanvasPrimitiveKind::Line => {
            let margin = (item.stroke_width as f32 / 2.0).max(1.0);
            (
                item.x.min(item.x2) as f32 - margin,
                item.y.min(item.y2) as f32 - margin,
                item.x.max(item.x2) as f32 + margin,
                item.y.max(item.y2) as f32 + margin,
            )
        }
    };
    Rect {
        left: canvas.left + left,
        top: canvas.top + top,
        right: canvas.left + right,
        bottom: canvas.top + bottom,
    }
}

/// Send one chord through the window's real keymap.
fn dispatch_chord(
    window: WindowHandle<Runtime>,
    chord: &str,
    cx: &mut AsyncApp,
) -> Result<bool, StepError> {
    let keystroke = Keystroke::parse(chord).map_err(|error| StepError::Keystroke {
        chord: chord.to_owned(),
        detail: error.to_string(),
    })?;
    // Deliberately `update_window` rather than `window.update`: the latter
    // leases the `Runtime` entity, and the action handlers this keystroke
    // reaches call `runtime.update` themselves, which GPUI refuses as a
    // reentrant update.
    cx.update_window(window.into(), |_, window, cx| {
        window.dispatch_keystroke(keystroke, cx)
    })
    .map_err(|_| StepError::WindowClosed)
}

/// The keystroke spelling for one typed character.
///
/// GPUI names a few keys rather than taking their literal character, so those
/// are mapped rather than passed through.
fn typed_keystroke(character: char) -> Result<Keystroke, StepError> {
    let name = match character {
        ' ' => "space".to_owned(),
        '\t' => "tab".to_owned(),
        '\n' => "enter".to_owned(),
        '-' => "-".to_owned(),
        value if value.is_control() => return Err(StepError::Untypable(value)),
        value => value.to_string(),
    };
    let mut keystroke = Keystroke::parse(&name).map_err(|error| StepError::Keystroke {
        chord: name.clone(),
        detail: error.to_string(),
    })?;
    // A literal character carries itself as the typed text, which is what an
    // input element consumes.
    if keystroke.key_char.is_none() && !character.is_control() {
        keystroke.key_char = Some(character.to_string());
    }
    Ok(keystroke)
}

/// Resolve a screenshot's region to window-relative content coordinates.
fn region_rect(
    runtime: &Runtime,
    region: &Region,
    viewport: Rect,
) -> Result<(f32, f32, f32, f32), StepError> {
    match region {
        Region::Window => Ok((0.0, 0.0, viewport.right, viewport.bottom)),
        Region::Rect {
            x,
            y,
            width,
            height,
        } => Ok((
            *x as f32,
            *y as f32,
            (*x + *width) as f32,
            (*y + *height) as f32,
        )),
        // A canvas primitive has no element and no recorded bounds of its own.
        // Its rectangle is the canvas's, offset by the coordinates the owner
        // drew it at — the same one-point-to-one-point mapping `canvas_target`
        // inverts to decide what a press landed on.
        Region::Locator(locator)
            if matches!(
                locator.target(),
                Locator::CanvasItemName(_) | Locator::CanvasItemPrefix(_)
            ) =>
        {
            let (canvas, item) = runner::canvas_item(&runtime.graph, locator).ok_or_else(|| {
                StepError::LocatorMatched {
                    locator: describe(locator),
                    count: 0,
                }
            })?;
            // The painted surface, not the node's div: a canvas's style may
            // inset it, and the owner's coordinates are relative to where the
            // picture is drawn. This is the same rectangle the hit test maps a
            // press through.
            let canvas_rect = runtime
                .canvas_surfaces
                .get(&canvas)
                .and_then(|slot| *slot.lock().expect("canvas bounds poisoned"))
                .map(Rect::from_gpui)
                .ok_or_else(|| StepError::NotPainted(describe(locator)))?;
            let frame = runtime.painted().map_err(stale)?;
            let mut clip = viewport;
            for ancestor in runtime.graph.scroll_ancestors(canvas) {
                if let Some(rect) = node_rect(runtime, &frame, ancestor) {
                    clip = clip.intersect(rect).ok_or(StepError::OffScreen {
                        locator: describe(locator),
                        bounds: canvas_rect,
                    })?;
                }
            }
            // Clipped to its canvas as well as to the window: a shape drawn
            // past the edge of the surface it belongs to is not painted there.
            let bounds = primitive_rect(canvas_rect, item)
                .intersect(canvas_rect)
                .and_then(|rect| rect.intersect(clip))
                .ok_or(StepError::OffScreen {
                    locator: describe(locator),
                    bounds: canvas_rect,
                })?;
            Ok((bounds.left, bounds.top, bounds.right, bounds.bottom))
        }
        // The visible part, not the laid-out part: an element half below the
        // fold of its scroll region has no pixels down there to photograph, and
        // a rectangle reaching past the window would capture whatever the
        // desktop has behind it.
        // A canvas is photographed where its picture is painted, the same
        // surface its primitives and pointer steps are placed on.
        Region::Locator(locator)
            if resolve(runtime, locator).is_ok_and(|id| {
                matches!(
                    runtime.graph.node(id).map(|node| &node.kind),
                    Some(crate::bridge::NodeKind::Canvas { .. })
                )
            }) =>
        {
            let canvas = resolve(runtime, locator)?;
            let surface = runtime
                .canvas_surfaces
                .get(&canvas)
                .and_then(|slot| *slot.lock().expect("canvas bounds poisoned"))
                .map(Rect::from_gpui)
                .ok_or_else(|| StepError::NotPainted(describe(locator)))?;
            let frame = runtime.painted().map_err(stale)?;
            let mut clip = viewport;
            for ancestor in runtime.graph.scroll_ancestors(canvas) {
                if let Some(rect) = node_rect(runtime, &frame, ancestor) {
                    clip = clip.intersect(rect).ok_or(StepError::OffScreen {
                        locator: describe(locator),
                        bounds: surface,
                    })?;
                }
            }
            let bounds = surface.intersect(clip).ok_or(StepError::OffScreen {
                locator: describe(locator),
                bounds: surface,
            })?;
            Ok((bounds.left, bounds.top, bounds.right, bounds.bottom))
        }
        Region::Locator(locator) => {
            let bounds = visible_rect(runtime, locator, viewport)?;
            Ok((bounds.left, bounds.top, bounds.right, bounds.bottom))
        }
    }
}

/// Photograph the window, or one region of it.
///
/// A capture that cannot happen is reported as `unavailable` with a reason
/// rather than failing the run, unless the run required screenshots. Either way
/// it never reports a pass it did not earn.
async fn take_screenshot(
    request: &Screenshot,
    ordinal: usize,
    window: WindowHandle<Runtime>,
    options: &Options,
    cx: &mut AsyncApp,
) -> Result<Option<ShotRecord>, StepError> {
    let (client, screen, scale, native, readback) = window
        .update(cx, |runtime, window, _| {
            let size = window.viewport_size();
            let viewport = Rect {
                left: 0.0,
                top: 0.0,
                right: f32::from(size.width),
                bottom: f32::from(size.height),
            };
            let region = region_rect(runtime, &request.region, viewport)?;
            let content = (viewport.right, viewport.bottom);
            let pad = request.pad as f32;
            // A frame the host renders itself is cropped relative to its
            // content area; a capture tool takes screen space.
            let client = screenshot::screen_rect(
                (0.0, 0.0, viewport.right, viewport.bottom),
                content,
                region,
                pad,
            );
            let frame = window.bounds();
            let screen = screenshot::screen_rect(
                (
                    f32::from(frame.origin.x),
                    f32::from(frame.origin.y),
                    f32::from(frame.size.width),
                    f32::from(frame.size.height),
                ),
                content,
                region,
                pad,
            );
            let readback = client.is_some() && window.request_frame_capture();
            Ok::<_, StepError>((
                client,
                screen,
                window.scale_factor(),
                native_window(window),
                readback,
            ))
        })
        .map_err(|_| StepError::WindowClosed)??;

    let file_name = format!("{ordinal:02}-{}.png", request.name);
    let destination = options.shot_dir.join(&file_name);
    let result = if readback {
        // The renderer copies out the next frame it presents. Ask for frames
        // the way settling does until one has been presented and read.
        let mut captured = None;
        for _ in 0..READBACK_FRAMES {
            next_frame(window, cx).await?;
            captured = window
                .update(cx, |_, window, _| window.take_captured_frame())
                .map_err(|_| StepError::WindowClosed)?;
            if captured.is_some() {
                break;
            }
        }
        match (captured, client) {
            (Some(frame), Some(client)) => screenshot::save_client_region(
                screenshot::READBACK,
                frame.width,
                frame.height,
                &frame.rgba,
                scale,
                client,
                &destination,
            ),
            _ => Err(ShotError::ToolFailed {
                tool: screenshot::READBACK,
                status: None,
                detail: format!("no frame was presented within {READBACK_FRAMES} frames"),
            }),
        }
    } else {
        // Windows captures by asking the window to render, which is a message
        // the window's own thread answers. This step runs on that thread;
        // driving it from the background executor would wait for a pump that
        // may never come.
        #[cfg(windows)]
        let _ = screen;
        match native {
            #[cfg(windows)]
            Some((hwnd, scale)) => match client {
                Some(client) => screenshot::capture_window(hwnd, scale, client, &destination),
                None => Err(ShotError::DegenerateRegion),
            },
            #[cfg(windows)]
            None => Err(ShotError::UnsupportedPlatform),
            #[cfg(not(windows))]
            () => match screen {
                Some(screen) => screenshot::capture(screen, &destination),
                None => Err(ShotError::DegenerateRegion),
            },
        }
    };
    match result {
        Ok(bytes) => Ok(Some(ShotRecord {
            name: request.name.clone(),
            file: Some(file_name),
            bytes,
            reason: None,
            hint: None,
        })),
        Err(error) if options.require_shots => Err(StepError::Screenshot(error)),
        Err(error) => Ok(Some(ShotRecord {
            name: request.name.clone(),
            file: None,
            bytes: 0,
            reason: Some(error.reason()),
            hint: Some(error.hint()),
        })),
    }
}

/// Frames to wait for a requested readback before calling it failed. The
/// frame after the request is the one read; the rest absorb a compositor that
/// withholds a frame callback.
const READBACK_FRAMES: usize = 8;

/// The native window and its scale factor, which a Windows capture needs.
#[cfg(windows)]
fn native_window(window: &gpui::Window) -> Option<(isize, f32)> {
    use raw_window_handle::{HasWindowHandle, RawWindowHandle};
    // `Window` has an inherent `window_handle` for GPUI's own handle.
    match HasWindowHandle::window_handle(window).ok()?.as_raw() {
        RawWindowHandle::Win32(handle) => Some((handle.hwnd.get(), window.scale_factor())),
        _ => None,
    }
}

#[cfg(not(windows))]
fn native_window(_window: &gpui::Window) {}

fn viewport_rect(window: WindowHandle<Runtime>, cx: &mut AsyncApp) -> Result<Rect, StepError> {
    window
        .update(cx, |_, window, _| {
            let size = window.viewport_size();
            Rect {
                left: 0.0,
                top: 0.0,
                right: f32::from(size.width),
                bottom: f32::from(size.height),
            }
        })
        .map_err(|_| StepError::WindowClosed)
}

/// Drive `spec` against `window`, write the report, then quit.
pub fn spawn(spec: Spec, window: WindowHandle<Runtime>, options: Options, cx: &mut App) {
    cx.spawn(async move |cx| {
        crate::watchdog::milestone(crate::watchdog::Milestone::DriverStarted);
        let file_baseline = crate::files::operation_counts();
        let mut outcome = Outcome {
            spec_name: spec.name.clone(),
            steps: Vec::new(),
            window: None,
            scale_factor: 1.0,
            failed: false,
            unavailable_shots: 0,
        };

        // Let the first real frame land before anything is asserted about it.
        account_through_now();
        if let Err(error) = settle(window, 2, options.timeout, cx).await {
            outcome.failed = true;
            outcome.steps.push(StepRecord {
                ordinal: 0,
                line: 0,
                kind: "startup",
                status: "fail",
                message: Some(error.message(0)),
                shot: None,
            });
        }

        if let Ok((size, scale)) = window.update(cx, |_, window, _| {
            (window.viewport_size(), window.scale_factor())
        }) {
            outcome.window = Some((f32::from(size.width), f32::from(size.height)));
            outcome.scale_factor = scale;
        }

        if !outcome.failed {
            for (ordinal, step) in spec.steps.iter().enumerate() {
                match run_step(step, ordinal, window, &options, file_baseline, cx).await {
                    Ok(shot) => {
                        let missing = shot.as_ref().is_some_and(|shot| shot.file.is_none());
                        if missing {
                            outcome.unavailable_shots += 1;
                        }
                        outcome.steps.push(StepRecord {
                            ordinal,
                            line: step.line,
                            kind: step.command.kind(),
                            status: if missing { "unavailable" } else { "pass" },
                            message: None,
                            shot,
                        })
                    }
                    Err(error) => {
                        outcome.failed = true;
                        // A clipped element is the one failure a smaller
                        // window explains, so that is where the difference is
                        // reported rather than in every unrelated message.
                        let mut message = error.message(step.line);
                        if matches!(error, StepError::OffScreen { .. })
                            && let Some(note) =
                                window_shortfall(options.requested_window, outcome.window)
                        {
                            message.push_str(&format!("; {note}"));
                        }
                        outcome.steps.push(StepRecord {
                            ordinal,
                            line: step.line,
                            kind: step.command.kind(),
                            status: "fail",
                            message: Some(message),
                            shot: None,
                        });
                        break;
                    }
                }
            }
        }

        if let Err(error) = write_report(&options.report_path, &outcome, &options) {
            eprintln!(
                "roc-gui window report error: {}: {error}",
                options.report_path.display()
            );
        }
        if outcome.passed() {
            eprintln!("PASS: {}", outcome.spec_name);
        } else {
            for step in outcome.steps.iter().filter(|step| step.status == "fail") {
                if let Some(message) = &step.message {
                    eprintln!("FAIL: {}: {message}", outcome.spec_name);
                }
            }
        }
        crate::watchdog::disarm();
        // Exits rather than quitting: `cx.quit()` terminates the process without
        // returning to `main`, so a status set there would never be read.
        crate::finish_and_exit(i32::from(!outcome.passed()));
    })
    .detach();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_work_assertion_uses_owner_completed_frame_maxima() {
        use crate::observatory as owner;
        assert!(check_native_work(None, Some(0), None, None).is_err());
        owner::mark_native_work();
        assert!(check_native_work(owner::native_work_since_mark(), Some(0), None, None).is_err());
        let before = owner::native_work_totals();
        owner::note_native_render(1);
        owner::note_native_render(15);
        owner::note_native_view_element(15);
        owner::note_native_view_element(15);
        owner::complete_native_frame(before);
        let before = owner::native_work_totals();
        owner::note_native_render(1);
        owner::note_native_render(1);
        owner::complete_native_frame(before);
        let work = owner::native_work_since_mark();
        assert!(check_native_work(work, Some(2), Some(1), Some(2)).is_ok());
        assert!(check_native_work(work, None, None, Some(1)).is_err());
        assert!(check_native_work(work, None, Some(1), None).is_ok());
        let error = check_native_work(work, Some(1), None, None).unwrap_err();
        assert!(format!("{error:?}").contains("observed maximum 2"));
        assert!(check_native_work(work, None, Some(0), None).is_err());
        owner::mark_native_work();
        assert!(check_native_work(owner::native_work_since_mark(), Some(0), None, None).is_err());
        owner::complete_native_frame(owner::native_work_totals());
        assert!(check_native_work(owner::native_work_since_mark(), Some(0), Some(0), None).is_ok());
    }

    #[test]
    fn quiescence_needs_consecutive_unchanged_frames() {
        // One frame of history can never prove two quiet frames.
        assert!(!quiet_enough(&[(1, 1)], 2));
        // Counts still moving.
        assert!(!quiet_enough(&[(1, 0), (2, 1), (3, 2)], 2));
        // Two unchanged transitions in a row.
        assert!(quiet_enough(&[(3, 3), (3, 3), (3, 3)], 2));
        // Quiet, then work arrives again.
        assert!(!quiet_enough(&[(3, 3), (3, 3), (4, 3)], 2));
        // A single quiet frame is enough when only one was asked for.
        assert!(quiet_enough(&[(3, 3), (3, 3)], 1));
    }

    #[test]
    fn scrolling_moves_only_as_far_as_it_must() {
        // Already inside the viewport: nothing moves.
        assert_eq!(axis_delta(20.0, 60.0, 0.0, 100.0), 0.0);
        // Below the fold: bring its far edge to the near edge of the fold.
        assert_eq!(axis_delta(120.0, 160.0, 0.0, 100.0), 60.0);
        // Above the start: travel back by the gap at the leading edge.
        assert_eq!(axis_delta(-30.0, 10.0, 0.0, 100.0), -30.0);
        // Taller than the viewport: show its start, since nothing shows all.
        assert_eq!(axis_delta(150.0, 400.0, 0.0, 100.0), 150.0);
    }

    #[test]
    fn a_canvas_primitive_sits_where_its_owner_drew_it() {
        use crate::bridge::{CanvasPrimitive, CanvasPrimitiveKind};
        let canvas = Rect {
            left: 100.0,
            top: 50.0,
            right: 500.0,
            bottom: 450.0,
        };
        let mut item = CanvasPrimitive {
            kind: CanvasPrimitiveKind::Rectangle,
            key: 1,
            label: "Card".into(),
            x: 10,
            y: 20,
            width: 40,
            height: 30,
            x2: 0,
            y2: 0,
            fill: None,
            stroke: None,
            stroke_width: 0,
            radius: 0,
            ..Default::default()
        };
        assert_eq!(
            primitive_rect(canvas, &item),
            Rect {
                left: 110.0,
                top: 70.0,
                right: 150.0,
                bottom: 100.0
            }
        );
        // An ellipse fills the same box it was given.
        item.kind = CanvasPrimitiveKind::Ellipse;
        assert_eq!(primitive_rect(canvas, &item).right, 150.0);
        // A line has no area of its own, so its stroke is what it covers, and
        // its coordinates run in whichever direction the owner drew them.
        item.kind = CanvasPrimitiveKind::Line;
        item.x2 = 4;
        item.y2 = 60;
        item.stroke_width = 8;
        assert_eq!(
            primitive_rect(canvas, &item),
            Rect {
                left: 100.0,
                top: 66.0,
                right: 114.0,
                bottom: 114.0
            }
        );
    }

    #[test]
    fn a_scroll_step_names_what_it_could_not_reach() {
        let message = StepError::NotScrollable("(role panel :name \"Body\")".to_owned()).message(4);
        assert!(message.contains("cannot be scrolled"), "{message}");
        let message = StepError::NotInRegion {
            region: "(role scroll :name \"Contents\")".to_owned(),
            target: "(text \"Elsewhere\")".to_owned(),
        }
        .message(9);
        assert!(message.starts_with("line 9: "), "{message}");
        assert!(message.contains("is not inside"), "{message}");
    }

    #[test]
    fn step_errors_name_the_line_and_the_remedy() {
        let error = StepError::Timeout {
            waited: Duration::from_millis(2_000),
            outstanding: 3,
        };
        let message = error.message(12);
        assert!(message.starts_with("line 12: "), "{message}");
        assert!(message.contains("3 task(s) outstanding"), "{message}");
    }

    #[test]
    fn a_window_smaller_than_requested_says_so_and_a_faithful_one_stays_silent() {
        // The size that was honoured explains nothing and is not mentioned.
        assert!(window_shortfall((660.0, 720.0), Some((660.0, 720.0))).is_none());
        // Rounding within half a point is the size it was given.
        assert!(window_shortfall((660.0, 720.0), Some((660.0, 719.7))).is_none());
        // A window larger than the request is not a shortfall either.
        assert!(window_shortfall((660.0, 720.0), Some((800.0, 900.0))).is_none());
        // Nothing was measured, so nothing is claimed.
        assert!(window_shortfall((660.0, 720.0), None).is_none());
        let note = window_shortfall((660.0, 720.0), Some((660.0, 652.0)))
            .expect("a clamped window is a difference worth reporting");
        assert!(note.contains("opened at 660x652"), "{note}");
        assert!(note.contains("asked for 660x720"), "{note}");
    }

    #[test]
    fn off_screen_reports_where_the_element_actually_is() {
        let error = StepError::OffScreen {
            locator: "Text(\"row\")".to_owned(),
            bounds: Rect {
                left: 12.0,
                top: 812.0,
                right: 108.0,
                bottom: 844.0,
            },
        };
        let message = error.message(6);
        assert!(message.contains("(12.0,812.0)-(108.0,844.0)"), "{message}");
        assert!(message.contains("not on screen"), "{message}");
    }
}
