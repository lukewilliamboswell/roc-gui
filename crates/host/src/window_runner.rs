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
use std::time::Duration;

use gpui::{App, AppContext, AsyncApp, Keystroke, WindowHandle, px, size};

use crate::probe::{self, Rect};
use crate::screenshot::{self, ShotError};
use crate::spec::{BoundsExpectation, Command, Locator, Region, Screenshot, Spec, Step};
use crate::{Runtime, runner, task_counts};

/// Where a window run writes its evidence.
pub struct Options {
    pub report_path: PathBuf,
    pub shot_dir: PathBuf,
    pub timeout: Duration,
    pub require_shots: bool,
}

/// Why a step did not pass.
#[derive(Debug)]
pub enum StepError {
    /// A locator resolved to something other than exactly one node.
    LocatorMatched { locator: String, count: usize },
    /// The node exists in the graph but did not participate in a frame.
    NotPainted(String),
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
    /// A modal dialog is capturing interaction.
    BehindDialog(String),
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
            Self::OffScreen { locator, bounds } => format!(
                "{locator} is laid out at ({:.1},{:.1})-({:.1},{:.1}) but is not on screen",
                bounds.left, bounds.top, bounds.right, bounds.bottom
            ),
            Self::Geometry(detail) => detail.clone(),
            Self::Timeout { waited, outstanding } => format!(
                "settle timed out after {}ms with {outstanding} task(s) outstanding",
                waited.as_millis()
            ),
            Self::WindowClosed => "the window closed before the step ran".to_owned(),
            Self::Screenshot(error) => {
                format!("screenshot unavailable ({}): {}", error.reason(), error.hint())
            }
            Self::Keystroke { chord, detail } => {
                format!("GPUI rejected the key chord {chord:?}: {detail}")
            }
            Self::Untypable(character) => {
                format!("cannot type {character:?} as a keystroke")
            }
            Self::NotClickable(locator) => format!(
                "{locator} does not accept pointer activation; it may be disabled"
            ),
            Self::BehindDialog(locator) => {
                format!("{locator} is behind an active dialog and cannot be clicked")
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

/// Bounds for a node that actually took part in the last frame.
fn painted_bounds(runtime: &Runtime, locator: &Locator) -> Result<Rect, StepError> {
    let id = resolve(runtime, locator)?;
    probe::bounds(id).ok_or_else(|| StepError::NotPainted(describe(locator)))
}

/// Whether a node is visible, not merely laid out.
///
/// Scroll-clipped content still records bounds, so the element rect is
/// intersected against the viewport and every scrolling ancestor. Testing only
/// that bounds exist would call a clipped element visible.
fn visible_rect(runtime: &Runtime, locator: &Locator, viewport: Rect) -> Result<Rect, StepError> {
    let id = resolve(runtime, locator)?;
    let bounds = probe::bounds(id).ok_or_else(|| StepError::NotPainted(describe(locator)))?;
    let mut clip = viewport;
    for ancestor in runtime.graph.scroll_ancestors(id) {
        if let Some(rect) = probe::bounds(ancestor) {
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
    if let Some(min) = expectation.min_width {
        if width < min as f32 {
            violations.push(format!("width {width:.1} is below :min-width {min}"));
        }
    }
    if let Some(max) = expectation.max_width {
        if width > max as f32 {
            violations.push(format!("width {width:.1} is above :max-width {max}"));
        }
    }
    if let Some(min) = expectation.min_height {
        if height < min as f32 {
            violations.push(format!("height {height:.1} is below :min-height {min}"));
        }
    }
    if let Some(max) = expectation.max_height {
        if height > max as f32 {
            violations.push(format!("height {height:.1} is above :max-height {max}"));
        }
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
pub(crate) fn quiet_enough(history: &[(u64, u64)], frames: u32) -> bool {
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
    let mut history = vec![task_counts()];
    while started.elapsed() < timeout {
        next_frame(window, cx).await?;
        history.push(task_counts());
        if quiet_enough(&history, frames) {
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

/// Await one presented frame.
async fn next_frame(window: WindowHandle<Runtime>, cx: &mut AsyncApp) -> Result<(), StepError> {
    let (sender, receiver) = async_channel::bounded::<()>(1);
    window
        .update(cx, |_, window, _| {
            window.on_next_frame(move |_, _| {
                let _ = sender.try_send(());
            });
            // Not `request_animation_frame`: despite its documentation it calls
            // `current_view`, which panics outside a render pass. `refresh`
            // marks the window dirty from anywhere.
            window.refresh();
        })
        .map_err(|_| StepError::WindowClosed)?;
    receiver.recv().await.map_err(|_| StepError::WindowClosed).map(|_| ())
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
    json.push_str("{\n  \"schema_version\": 1,\n");
    json.push_str(&format!(
        "  \"spec\": {{ \"name\": \"{}\" }},\n",
        escape(&outcome.spec_name)
    ));
    json.push_str(&format!(
        "  \"run_mode\": \"window-scenario\",\n  \"outcome\": \"{}\",\n",
        if outcome.passed() { "pass" } else { "fail" }
    ));
    match outcome.window {
        Some((width, height)) => json.push_str(&format!(
            "  \"window\": {{ \"width_points\": {width:.0}, \"height_points\": {height:.0}, \"scale_factor\": {:.1} }},\n",
            outcome.scale_factor
        )),
        None => json.push_str("  \"window\": null,\n"),
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

/// Run one step against the live window.
async fn run_step(
    step: &Step,
    ordinal: usize,
    window: WindowHandle<Runtime>,
    options: &Options,
    cx: &mut AsyncApp,
) -> Result<Option<ShotRecord>, StepError> {
    match &step.command {
        Command::Screenshot(request) => {
            return take_screenshot(request, ordinal, window, options, cx);
        }
        Command::Settle { frames, timeout_ms } => {
            settle(
                window,
                *frames,
                Duration::from_millis(u64::from(*timeout_ms)),
                cx,
            )
            .await
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
                            Some(handle) => handle.focus(window),
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
            settle(window, 1, options.timeout, cx).await
        }
        Command::Focus(locator) => {
            let id = window
                .update(cx, |runtime, _, _| resolve(runtime, locator))
                .map_err(|_| StepError::WindowClosed)??;
            let focused = window
                .update(cx, |runtime, window, _| {
                    runtime.focus_handles.get(&id).map(|handle| {
                        handle.focus(window);
                    })
                })
                .map_err(|_| StepError::WindowClosed)?;
            if focused.is_none() {
                return Err(StepError::Geometry(format!(
                    "{} is not focusable",
                    describe(locator)
                )));
            }
            settle(window, 1, options.timeout, cx).await
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
            settle(window, 1, options.timeout, cx).await
        }
        Command::Type(text) => {
            for character in text.chars() {
                let keystroke = typed_keystroke(character)?;
                cx.update_window(window.into(), |_, window, cx| {
                    window.dispatch_keystroke(keystroke, cx);
                })
                .map_err(|_| StepError::WindowClosed)?;
                settle(window, 1, options.timeout, cx).await?;
            }
            Ok(())
        }
        Command::Key(chord) => {
            dispatch_chord(window, chord, cx)?;
            settle(window, 1, options.timeout, cx).await
        }
        Command::Resize { width, height } => {
            cx.update_window(window.into(), |_, window, _| {
                window.resize(size(px(*width as f32), px(*height as f32)));
            })
            .map_err(|_| StepError::WindowClosed)?;
            settle(window, 2, options.timeout, cx).await
        }
        // Deliberately the same claim the semantic runner makes: present in
        // the mounted graph. The stronger pixel claim is `expect-on-screen`, so
        // one word does not mean two different things on two runners.
        Command::ExpectVisible(locator) => window
            .update(cx, |runtime, _, _| resolve(runtime, locator).map(|_| ()))
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectOnScreen(locator) => {
            let viewport = viewport_rect(window, cx)?;
            window
                .update(cx, |runtime, _, _| {
                    visible_rect(runtime, locator, viewport).map(|_| ())
                })
                .map_err(|_| StepError::WindowClosed)?
        }
        Command::ExpectRenderedCount(locator, expected) => window
            .update(cx, |runtime, _, _| {
                let ids = runner::matches(&runtime.graph, locator);
                let painted = probe::laid_out_count(&ids);
                if painted == *expected {
                    Ok(())
                } else {
                    Err(StepError::Geometry(format!(
                        "{} laid out {painted} instances; expected {expected}",
                        describe(locator)
                    )))
                }
            })
            .map_err(|_| StepError::WindowClosed)?,
        Command::ExpectBounds(locator, expectation) => window
            .update(cx, |runtime, _, _| {
                let bounds = painted_bounds(runtime, locator)?;
                check_bounds(&describe(locator), bounds, expectation)
            })
            .map_err(|_| StepError::WindowClosed)?,
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
        Command::AwaitTask => settle(window, 2, options.timeout, cx).await,
        // An application that polls — a clipboard watcher rearms its read on
        // every tick — never reaches the quiescence `settle` waits for, because
        // one task is outstanding at every instant by construction. `await-ticks`
        // therefore counts completions rather than waiting for there to be none,
        // which is also what the step means: apply N successive wait completions.
        Command::AwaitTicks(count) => advance_timer_fires(window, *count, options.timeout, cx).await,
        // The fixture clipboard is one process-wide store, so changing the
        // granted source here is the same act the semantic runner performs. One
        // presented frame is all this step waits for; observing the change is
        // the application's own timer's job, and `await-ticks` waits for that.
        Command::ClipboardText(text) => match crate::clipboard::inject_fixture(text.clone()) {
            Err(detail) => Err(StepError::Geometry(detail)),
            Ok(()) => next_frame(window, cx).await,
        },
        // Unreachable: `spec::check_runner` refuses a specification whose
        // steps this runner does not implement, so the refusal happens before
        // the window opens rather than part-way through a run.
        other => Err(StepError::Unsupported(other.kind())),
    }
    .map(|()| None)
}

/// Resolve a locator to a control a real click could actually have activated.
///
/// GPUI 0.2.2 exposes no usable pointer entry point, so the click itself is
/// simulated at the production handler. What is *not* simulated is whether the
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
        Region::Locator(locator) => {
            let bounds = painted_bounds(runtime, locator)?;
            Ok((bounds.left, bounds.top, bounds.right, bounds.bottom))
        }
    }
}

/// Photograph the window, or one region of it.
///
/// A capture that cannot happen is reported as `unavailable` with a reason
/// rather than failing the run, unless the run required screenshots. Either way
/// it never reports a pass it did not earn.
fn take_screenshot(
    request: &Screenshot,
    ordinal: usize,
    window: WindowHandle<Runtime>,
    options: &Options,
    cx: &mut AsyncApp,
) -> Result<Option<ShotRecord>, StepError> {
    let geometry = window
        .update(cx, |runtime, window, _| {
            let size = window.viewport_size();
            let viewport = Rect {
                left: 0.0,
                top: 0.0,
                right: f32::from(size.width),
                bottom: f32::from(size.height),
            };
            let region = region_rect(runtime, &request.region, viewport)?;
            let frame = window.bounds();
            Ok::<_, StepError>(screenshot::screen_rect(
                (
                    f32::from(frame.origin.x),
                    f32::from(frame.origin.y),
                    f32::from(frame.size.width),
                    f32::from(frame.size.height),
                ),
                (viewport.right, viewport.bottom),
                region,
                request.pad as f32,
            ))
        })
        .map_err(|_| StepError::WindowClosed)??;

    let file_name = format!("{ordinal:02}-{}.png", request.name);
    let destination = options.shot_dir.join(&file_name);
    let result = match geometry {
        Some(geometry) => screenshot::capture(geometry, &destination),
        None => Err(screenshot::ShotError::DegenerateRegion),
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
        let mut outcome = Outcome {
            spec_name: spec.name.clone(),
            steps: Vec::new(),
            window: None,
            scale_factor: 1.0,
            failed: false,
        };

        // Let the first real frame land before anything is asserted about it.
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
                match run_step(step, ordinal, window, &options, cx).await {
                    Ok(shot) => outcome.steps.push(StepRecord {
                        ordinal,
                        line: step.line,
                        kind: step.command.kind(),
                        status: if shot.as_ref().is_some_and(|shot| shot.file.is_none()) {
                            "unavailable"
                        } else {
                            "pass"
                        },
                        message: None,
                        shot,
                    }),
                    Err(error) => {
                        outcome.failed = true;
                        outcome.steps.push(StepRecord {
                            ordinal,
                            line: step.line,
                            kind: step.command.kind(),
                            status: "fail",
                            message: Some(error.message(step.line)),
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

