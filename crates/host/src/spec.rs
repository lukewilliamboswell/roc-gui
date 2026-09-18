use std::fmt;

use crate::bridge::ControlKey;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Spec {
    pub name: String,
    pub benchmark: Option<Benchmark>,
    pub grants: Vec<Grant>,
    pub steps: Vec<Step>,
}

/// One capability a specification asks for.
///
/// A specification states everything it needs beside its steps, so the case can
/// be read on its own. A specification that declares no grant receives no
/// capability, and exercises denial through the application's ordinary
/// acquisition path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Grant {
    /// Read access to one directory, relative to the application directory.
    Directory(String),
    /// A directory chooser the person dismisses without choosing.
    ///
    /// `(directory canceled)` provisions the chooser itself rather than a
    /// grant: the acquisition path runs, no authority is produced, and
    /// `pick_directory!` answers `Ok(Canceled)`. Cancelling is not a failure,
    /// and an application that cannot be shown cancelling cannot be shown
    /// treating it as one.
    DirectoryCanceled,
    /// Private application-data storage seeded from this directory.
    AppData(String),
    /// The content directory an `Assets.content_directory` store resolves to.
    /// The application names no path of its own, so the case names the one the
    /// host provisions.
    Assets(String),
    /// Clipboard authority: the real system clipboard, or a fixture source the
    /// `clipboard-text` step drives.
    Clipboard { system: bool },
    /// A paced null audio sink in place of the system output device.
    AudioNull,
    /// HTTP access to exactly one origin.
    HttpOrigin(String),
    /// TCP access to exactly one `IP:PORT` endpoint.
    Tcp(String),
    /// A loopback service the harness starts before the case, and the port it
    /// reports readiness on.
    Server { script: String, port: u32 },
    /// A PTY child profile: `local-shell` or `test-program`.
    Process(String),
    /// One HID device: `virtual`, `virtual:COUNT`, or a hexadecimal `VID:PID`.
    Device(String),
    /// A system sampler: `standard`, `unavailable`, or `processes:N`.
    SystemMonitor(String),
}

impl Grant {
    /// The grant's vocabulary name, which is also its uniqueness key.
    pub fn name(&self) -> &'static str {
        match self {
            Self::Directory(_) | Self::DirectoryCanceled => "directory",
            Self::AppData(_) => "app-data",
            Self::Assets(_) => "assets",
            Self::Clipboard { .. } => "clipboard",
            Self::AudioNull => "audio",
            Self::HttpOrigin(_) => "http-origin",
            Self::Tcp(_) => "tcp",
            Self::Server { .. } => "server",
            Self::Process(_) => "process",
            Self::Device(_) => "device",
            Self::SystemMonitor(_) => "system-monitor",
        }
    }

    /// The application-relative path this grant names, if it names one.
    ///
    /// Every path a specification supplies reaches a capability only after the
    /// harness resolves it against the application directory and proves it
    /// stays inside.
    pub fn path(&self) -> Option<&str> {
        match self {
            Self::Directory(path)
            | Self::AppData(path)
            | Self::Assets(path)
            | Self::Server { script: path, .. } => Some(path),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Benchmark {
    pub warmups: u32,
    pub samples: u32,
    pub iterations: u32,
    pub scale: u64,
    pub initial_size: u64,
    pub change_size: u64,
}

/// Which runner a step can execute on.
///
/// The semantic runner drives the mounted graph with no window; the window
/// runner drives the real GPUI window. Some claims are only honest on one of
/// them, so every command declares where it belongs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Capability {
    /// Only meaningful without a window (benchmark lifecycles, patch shape).
    Semantic,
    /// Only meaningful against a real window (pixels, layout, real input).
    Window,
    /// Equally honest on either runner.
    Both,
}

/// The runner a specification is about to execute on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Runner {
    Semantic,
    Window,
}

impl Capability {
    pub fn permits(self, runner: Runner) -> bool {
        matches!(
            (self, runner),
            (Self::Both, _) | (Self::Semantic, Runner::Semantic) | (Self::Window, Runner::Window)
        )
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Semantic => "semantic-only",
            Self::Window => "window-only",
            Self::Both => "both",
        }
    }

    /// How to run a specification this capability rejected.
    fn remedy(self) -> &'static str {
        match self {
            Self::Semantic => "run this specification with --host-run-spec",
            Self::Window => "run this specification with --host-run-window-spec",
            Self::Both => "",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Step {
    pub line: usize,
    pub command: Command,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Command {
    Click(Locator),
    /// Deliver a hover transition through the production graph event route.
    HoverEnter(Locator),
    HoverExit(Locator),
    /// Compare explicit application background, not a native hover refinement.
    ExpectBackground(Locator, u32),
    MarkNativeWork,
    ExpectNativeWork {
        button_renders_max: Option<u64>,
        boundary_renders_max: Option<u64>,
        boundary_elements_max: Option<u64>,
        cached_prepaint_subtrees_min: Option<u64>,
        cached_paint_subtrees_min: Option<u64>,
        replayed_scene_operations_min: Option<u64>,
        fresh_hitboxes_max: Option<u64>,
        fresh_mouse_listeners_max: Option<u64>,
        element_states_moved_min: Option<u64>,
    },
    Drag(Locator, i32, i32, i32, i32),
    ReplaceText(Locator, String),
    Focus(Locator),
    PressKey(ControlKey),
    AwaitTask,
    /// Resolve task completions until the locator matches this many nodes.
    ///
    /// Output arrives in as many tasks as the platform decides: a console
    /// flushes what it has when it has it. A specification that counts task
    /// completions is asserting a fact about that chunking rather than about
    /// the application, so this waits for the graph to say what it means.
    AwaitCount(Locator, usize),
    ClipboardText(String),
    AwaitTicks(u32),
    ExpectSubscriptions(usize),
    ExpectTcpStreams(usize),
    ExpectProcesses(usize),
    ExpectClipboardCounters([Option<u64>; 4]),
    ExpectSqliteCounters([u64; 3]),
    ExpectHttpCounters([u64; 4]),
    ExpectTcpCounters([u64; 5]),
    ExpectDeviceConnections(usize),
    ExpectDeviceTransactions(usize),
    ExpectSystemSamplers(usize),
    ExpectSystemSamples(usize),
    ExpectAudioCounters([u64; 9]),
    ExpectFilePicks(u64),
    ExpectFileLists(u64),
    ExpectFileOpens(u64),
    ExpectFileReads(u64),
    ExpectFileSelectionCounters([u64; 7]),
    ExpectFileLifecycleCounters([u64; 6]),
    ExpectFileAccess([u64; 3]),
    RevokeFileGrants,
    ExpectImageOwnerCounters([u64; 4]),
    /// Asset-store owner counters: opens, refused opens, manifest checks, reads,
    /// refused reads, and bytes read. All six are numeric; no path, file name,
    /// or asset content ever becomes evidence.
    ExpectAssetCounters([u64; 6]),
    /// Counts from the most recently committed production action turn.
    ExpectComponentWork([Option<u64>; crate::observatory::COMPONENT_WORK_NAMES.len()]),
    Submit(Locator),
    ExpectVisible(Locator),
    ExpectFocused(Locator),
    ExpectNotVisible(Locator),
    ExpectCount(Locator, usize),
    ExpectCanvasPrimitives(Locator, usize),
    ExpectValue(Locator, String),
    ExpectValueBytes(Locator, usize),
    ExpectImageBytes(Locator, usize),
    ExpectBefore(Locator, Locator),
    ExpectPatch(PatchExpectation),
    MarkMetrics,
    /// Wait for `frames` consecutive quiet presented frames, or fail.
    Settle {
        frames: u32,
        timeout_ms: u32,
    },
    /// Painted this frame and not clipped away by a scroll ancestor.
    ExpectOnScreen(Locator),
    /// How many instances actually took part in the last frame.
    ExpectRenderedCount(Locator, usize),
    /// Laid-out size within bounds. Deliberately min/max, never exact: exact
    /// pixel geometry is font- and DPI-brittle.
    ExpectBounds(Locator, BoundsExpectation),
    /// Photograph the window, or one region of it.
    Screenshot(Screenshot),
    /// Type text one real keystroke at a time into the focused element.
    Type(String),
    /// Send one real key chord, such as "cmd-a", through the keymap.
    Key(String),
    /// Resize the production window, so a layout can be proved at a size other
    /// than the one `main.roc` asks for.
    Resize {
        width: u32,
        height: u32,
    },
    /// Move a scroll region or virtual list, so that content below the fold can
    /// be asserted, clicked, and photographed.
    Scroll {
        region: Locator,
        motion: ScrollMotion,
    },
}

/// How far a `scroll` step moves its region.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ScrollMotion {
    /// By a signed number of logical pixels. Positive moves towards the end of
    /// the content, the direction a wheel-down gesture moves it.
    By(i32),
    /// Until the located element is inside the region's viewport. The target
    /// must be inside the region; for a virtual list it need not be
    /// materialized, because the list is positioned by the target's index among
    /// the region's children.
    To(Locator),
}

/// Modifier tokens a chord may carry, matching GPUI's keystroke spelling.
const CHORD_MODIFIERS: [&str; 6] = ["ctrl", "alt", "shift", "cmd", "super", "fn"];

/// Check a chord's shape without reimplementing GPUI's parser.
///
/// `Keystroke::parse` stays the authority at dispatch; this only rejects
/// obvious nonsense at parse time so a specification fails before it runs.
fn valid_chord(chord: &str) -> bool {
    let mut parts = chord.split('-').peekable();
    let mut seen_modifier = false;
    while let Some(part) = parts.next() {
        if part.is_empty() {
            return false;
        }
        if parts.peek().is_none() {
            // The final token is the key itself, and may be a literal "-".
            return !part.is_empty();
        }
        if !CHORD_MODIFIERS.contains(&part) {
            return false;
        }
        seen_modifier = true;
    }
    seen_modifier
}

/// What part of the window a screenshot covers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Region {
    /// The whole content area.
    Window,
    /// Cropped to a located element's laid-out bounds.
    Locator(Locator),
    /// An explicit content-relative rectangle.
    Rect {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    },
}

/// A named screenshot request.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Screenshot {
    /// The file stem, and the key an agent correlates report to image by.
    pub name: String,
    pub region: Region,
    pub pad: u32,
}

/// Names become file stems and report keys, so keep them boring and stable.
fn valid_screenshot_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 48
        && name
            .chars()
            .all(|value| value.is_ascii_lowercase() || value.is_ascii_digit() || value == '-')
}

/// Bounds on a laid-out element's size, in logical pixels.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BoundsExpectation {
    pub min_width: Option<u32>,
    pub max_width: Option<u32>,
    pub min_height: Option<u32>,
    pub max_height: Option<u32>,
}

impl BoundsExpectation {
    pub fn is_empty(self) -> bool {
        self.min_width.is_none()
            && self.max_width.is_none()
            && self.min_height.is_none()
            && self.max_height.is_none()
    }
}

impl Command {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Click(_) => "click",
            Self::HoverEnter(_) => "hover-enter",
            Self::HoverExit(_) => "hover-exit",
            Self::ExpectBackground(_, _) => "expect-background",
            Self::MarkNativeWork => "mark-native-work",
            Self::ExpectNativeWork { .. } => "expect-native-work",
            Self::Drag(..) => "drag",
            Self::ReplaceText(_, _) => "replace-text",
            Self::Focus(_) => "focus",
            Self::PressKey(_) => "press-key",
            Self::AwaitTask => "await-task",
            Self::AwaitCount(_, _) => "await-count",
            Self::ClipboardText(_) => "clipboard-text",
            Self::AwaitTicks(_) => "await-ticks",
            Self::ExpectSubscriptions(_) => "expect-subscriptions",
            Self::ExpectTcpStreams(_) => "expect-tcp-streams",
            Self::ExpectProcesses(_) => "expect-processes",
            Self::ExpectClipboardCounters(_) => "expect-clipboard-counters",
            Self::ExpectSqliteCounters(_) => "expect-sqlite-counters",
            Self::ExpectHttpCounters(_) => "expect-http-counters",
            Self::ExpectTcpCounters(_) => "expect-tcp-counters",
            Self::ExpectDeviceConnections(_) => "expect-device-connections",
            Self::ExpectDeviceTransactions(_) => "expect-device-transactions",
            Self::ExpectSystemSamplers(_) => "expect-system-samplers",
            Self::ExpectSystemSamples(_) => "expect-system-samples",
            Self::ExpectAudioCounters(_) => "expect-audio-counters",
            Self::ExpectFilePicks(_) => "expect-file-picks",
            Self::ExpectFileLists(_) => "expect-file-lists",
            Self::ExpectFileOpens(_) => "expect-file-opens",
            Self::ExpectFileReads(_) => "expect-file-reads",
            Self::ExpectFileSelectionCounters(_) => "expect-file-selection-counters",
            Self::ExpectFileLifecycleCounters(_) => "expect-file-lifecycle-counters",
            Self::ExpectFileAccess(_) => "expect-file-access",
            Self::RevokeFileGrants => "revoke-file-grants",
            Self::ExpectImageOwnerCounters(_) => "expect-image-owner-counters",
            Self::ExpectAssetCounters(_) => "expect-asset-counters",
            Self::ExpectComponentWork(_) => "expect-component-work",
            Self::Submit(_) => "submit",
            Self::ExpectVisible(_) => "expect-visible",
            Self::ExpectFocused(_) => "expect-focused",
            Self::ExpectNotVisible(_) => "expect-not-visible",
            Self::ExpectCount(_, _) => "expect-count",
            Self::ExpectCanvasPrimitives(_, _) => "expect-canvas-primitives",
            Self::ExpectValue(_, _) => "expect-value",
            Self::ExpectValueBytes(_, _) => "expect-value-bytes",
            Self::ExpectImageBytes(_, _) => "expect-image-bytes",
            Self::ExpectBefore(_, _) => "expect-before",
            Self::ExpectPatch(_) => "expect-patch",
            Self::MarkMetrics => "mark-metrics",
            Self::Settle { .. } => "settle",
            Self::ExpectOnScreen(_) => "expect-on-screen",
            Self::ExpectRenderedCount(_, _) => "expect-rendered-count",
            Self::ExpectBounds(_, _) => "expect-bounds",
            Self::Screenshot(_) => "screenshot",
            Self::Type(_) => "type",
            Self::Key(_) => "key",
            Self::Resize { .. } => "resize",
            Self::Scroll { .. } => "scroll",
        }
    }

    /// Where this command may run.
    ///
    /// The match is deliberately exhaustive with no wildcard arm: a new
    /// `Command` will not compile until someone decides where it is honest.
    pub fn capability(&self) -> Capability {
        match self {
            // Benchmark-lifecycle and patch-shape claims depend on the
            // semantic runner's per-iteration mount, which the window runner
            // does not perform.
            Self::ExpectPatch(_) | Self::MarkMetrics => Capability::Semantic,
            // Settling on presented frames has no meaning without a window.
            Self::Settle { .. }
            | Self::MarkNativeWork
            | Self::ExpectNativeWork { .. }
            | Self::ExpectOnScreen(_)
            | Self::ExpectRenderedCount(_, _)
            | Self::ExpectBounds(_, _)
            | Self::Screenshot(_)
            | Self::Type(_)
            | Self::Key(_)
            | Self::Resize { .. }
            // Scrolling is a fact about a viewport and a content size, neither
            // of which the semantic runner has: without layout there is no
            // fold for content to be below.
            | Self::Scroll { .. } => Capability::Window,
            // Shared with the semantic runner, and implemented by both.
            Self::Click(_)
            | Self::HoverEnter(_)
            | Self::HoverExit(_)
            | Self::Focus(_)
            | Self::PressKey(_)
            | Self::AwaitTask
            // The fixture clipboard is one process-wide store, so changing the
            // granted source and waiting for the application's own timer to
            // observe it mean the same thing under either runner. Without these
            // two a windowed case could not put a single item into a
            // clipboard-driven application, and so could not photograph one.
            | Self::ClipboardText(_)
            | Self::AwaitTicks(_)
            | Self::AwaitCount(_, _)
            | Self::ExpectVisible(_)
            | Self::ExpectFocused(_)
            | Self::ExpectNotVisible(_)
            | Self::ExpectCount(_, _)
            // Answered from the mounted graph alone, which both runners hold,
            // and by one shared implementation rather than two. A window case
            // can therefore assert a semantic truth and photograph it.
            | Self::ExpectCanvasPrimitives(_, _)
            | Self::ExpectValue(_, _)
            | Self::ExpectValueBytes(_, _)
            | Self::ExpectImageBytes(_, _)
            | Self::ExpectComponentWork(_)
            | Self::ExpectBefore(_, _)
            | Self::ExpectBackground(_, _)
            // Answered from a process-global resource owner, of which the host
            // has exactly one. A window run reads the same files registry, the
            // same clipboard and the same audio device table the semantic run
            // reads, through the same shared implementation, so a windowed case
            // can photograph a granted-authority readout and assert the counter
            // that produced it in the same run. Revoking grants likewise acts on
            // the one registry; what the application then sees is its next read.
            | Self::RevokeFileGrants
            | Self::ExpectSubscriptions(_)
            | Self::ExpectTcpStreams(_)
            | Self::ExpectProcesses(_)
            | Self::ExpectClipboardCounters(_)
            | Self::ExpectSqliteCounters(_)
            | Self::ExpectHttpCounters(_)
            | Self::ExpectTcpCounters(_)
            | Self::ExpectDeviceConnections(_)
            | Self::ExpectDeviceTransactions(_)
            | Self::ExpectSystemSamplers(_)
            | Self::ExpectSystemSamples(_)
            | Self::ExpectAudioCounters(_)
            | Self::ExpectFilePicks(_)
            | Self::ExpectFileLists(_)
            | Self::ExpectFileOpens(_)
            | Self::ExpectFileReads(_)
            | Self::ExpectFileSelectionCounters(_)
            | Self::ExpectFileLifecycleCounters(_)
            | Self::ExpectFileAccess(_)
            | Self::ExpectImageOwnerCounters(_)
            | Self::ExpectAssetCounters(_) => Capability::Both,
            // Semantic-only because the window runner does not implement them.
            // They are honest claims, made by one runner rather than two; the
            // alternative of accepting a specification and then refusing a step
            // mid-run would report a failure that is about the harness rather
            // than about the application.
            Self::Drag(..)
            | Self::ReplaceText(_, _)
            | Self::Submit(_) => Capability::Semantic,
        }
    }

    pub fn is_operation(&self) -> bool {
        matches!(
            self,
            Self::Click(_)
                | Self::HoverEnter(_)
                | Self::HoverExit(_)
                | Self::Drag(..)
                | Self::ReplaceText(_, _)
                | Self::Focus(_)
                | Self::PressKey(_)
                | Self::AwaitTask
                | Self::AwaitCount(_, _)
                | Self::ClipboardText(_)
                | Self::AwaitTicks(_)
                | Self::Submit(_)
                | Self::RevokeFileGrants
                | Self::Scroll { .. }
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PatchExpectation {
    pub kind: String,
    pub staged: u64,
    pub removed: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Locator {
    Within(Box<Locator>, Box<Locator>),
    Text(String),
    TextPrefix(String),
    ButtonName(String),
    ButtonPrefix(String),
    CheckboxName(String),
    CheckboxPrefix(String),
    ColumnName(String),
    DialogName(String),
    PanelName(String),
    RowName(String),
    ScrollName(String),
    VirtualListName(String),
    TextareaName(String),
    ImageName(String),
    CanvasName(String),
    CanvasItemName(String),
    CanvasItemPrefix(String),
    TextInputName(String),
}

impl Locator {
    /// The final target role, without changing the scope used for resolution.
    pub(crate) fn target(&self) -> &Self {
        match self {
            Self::Within(_, target) => target.target(),
            _ => self,
        }
    }
}

impl fmt::Display for Locator {
    /// Render a locator the way it is written in a specification, so a failure
    /// message quotes the author's own words back to them.
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (form, value) = match self {
            Self::Within(ancestor, target) => {
                return write!(formatter, "(within {ancestor} {target})");
            }
            Self::Text(value) => ("(text", value),
            Self::TextPrefix(value) => ("(text-prefix", value),
            Self::ButtonName(value) => ("(role button :name", value),
            Self::ButtonPrefix(value) => ("(button-prefix", value),
            Self::CheckboxName(value) => ("(role checkbox :name", value),
            Self::CheckboxPrefix(value) => ("(checkbox-prefix", value),
            Self::ColumnName(value) => ("(role column :name", value),
            Self::DialogName(value) => ("(role dialog :name", value),
            Self::PanelName(value) => ("(role panel :name", value),
            Self::RowName(value) => ("(role row :name", value),
            Self::ScrollName(value) => ("(role scroll :name", value),
            Self::VirtualListName(value) => ("(role virtual-list :name", value),
            Self::TextareaName(value) => ("(role textarea :name", value),
            Self::ImageName(value) => ("(role image :name", value),
            Self::CanvasName(value) => ("(role canvas :name", value),
            Self::CanvasItemName(value) => ("(role canvas-item :name", value),
            Self::CanvasItemPrefix(value) => ("(canvas-item-prefix", value),
            Self::TextInputName(value) => ("(role textbox :name", value),
        };
        write!(formatter, "{form} {value:?})")
    }
}

const MAX_SOURCE_BYTES: usize = 1024 * 1024;
const MAX_NESTING_DEPTH: usize = 128;
const MAX_EXPRESSIONS: usize = 100_000;
const MAX_STEPS: usize = 100_000;
const MAX_BENCHMARK_LIFECYCLES: u64 = 100_000;

#[derive(Clone, Debug, PartialEq, Eq)]
enum SExpr {
    Atom(String, usize),
    String(String, usize),
    List(Vec<SExpr>, usize),
}

impl SExpr {
    fn line(&self) -> usize {
        match self {
            Self::Atom(_, line) | Self::String(_, line) | Self::List(_, line) => *line,
        }
    }

    fn atom(&self) -> Option<&str> {
        match self {
            Self::Atom(value, _) => Some(value),
            _ => None,
        }
    }

    fn string(&self) -> Option<&str> {
        match self {
            Self::String(value, _) => Some(value),
            _ => None,
        }
    }

    fn list(&self) -> Option<&[SExpr]> {
        match self {
            Self::List(values, _) => Some(values),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParseError {
    pub line: usize,
    pub message: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

pub fn parse(source: &str) -> Result<Spec, ParseError> {
    if source.len() > MAX_SOURCE_BYTES {
        return Err(ParseError {
            line: 1,
            message: format!("spec exceeds the {MAX_SOURCE_BYTES}-byte source limit"),
        });
    }
    let mut parser = Parser::new(source);
    let root = parser.expr()?;
    parser.skip_space_and_comments();
    if parser.peek().is_some() {
        return Err(parser.error("expected exactly one top-level form"));
    }
    parse_spec(&root)
}

fn parse_spec(root: &SExpr) -> Result<Spec, ParseError> {
    let values = require_list(root, "test form")?;
    if values.first().and_then(SExpr::atom) != Some("test") {
        return Err(error(root, "supported specs must start with (test ...)"));
    }
    let name = values
        .get(1)
        .and_then(SExpr::string)
        .ok_or_else(|| error(root, "test requires a string name"))?
        .to_owned();
    let mut benchmark = None;
    let mut grants = None;
    let mut steps = None;
    for section in &values[2..] {
        let list = require_list(section, "test section")?;
        match list.first().and_then(SExpr::atom) {
            Some("grants") => {
                if grants.is_some() {
                    return Err(error(section, "duplicate grants clause"));
                }
                grants = Some(parse_grants(&list[1..])?);
            }
            Some("benchmark") => {
                if benchmark.is_some() {
                    return Err(error(section, "duplicate benchmark clause"));
                }
                benchmark = Some(parse_benchmark(section, list)?);
            }
            Some("steps") => {
                if steps.is_some() {
                    return Err(error(section, "duplicate steps clause"));
                }
                steps = Some(
                    list[1..]
                        .iter()
                        .map(parse_step)
                        .collect::<Result<Vec<_>, _>>()?,
                );
            }
            Some(other) => return Err(error(section, format!("unsupported test section {other}"))),
            None => return Err(error(section, "test section needs a name")),
        }
    }
    let steps = steps.ok_or_else(|| error(root, "test requires a steps clause"))?;
    if steps.len() > MAX_STEPS {
        return Err(error(
            root,
            format!("spec exceeds the {MAX_STEPS}-step limit"),
        ));
    }
    if let Some(policy) = benchmark {
        let marks = steps
            .iter()
            .filter(|step| matches!(step.command, Command::MarkMetrics))
            .count();
        if marks != 1 {
            return Err(error(
                root,
                format!("benchmark requires exactly one mark-metrics step; found {marks}"),
            ));
        }
        let verifies_scale = steps.iter().any(|step| {
            matches!(step.command, Command::ExpectCount(_, expected) | Command::ExpectCanvasPrimitives(_, expected) | Command::ExpectValueBytes(_, expected) | Command::ExpectImageBytes(_, expected) if expected as u64 == policy.scale)
        });
        if !verifies_scale {
            return Err(error(
                root,
                format!(
                    "benchmark :scale {} requires an expect-count assertion with the same count",
                    policy.scale
                ),
            ));
        }
    }
    Ok(Spec {
        name,
        benchmark,
        grants: grants.unwrap_or_default(),
        steps,
    })
}

/// Parse the `(grants ...)` clause.
///
/// An absent clause and an empty clause both mean the same thing: this case
/// receives no capability. The empty clause is how a denial case says so out
/// loud.
fn parse_grants(entries: &[SExpr]) -> Result<Vec<Grant>, ParseError> {
    let mut grants: Vec<Grant> = Vec::new();
    for entry in entries {
        let list = require_list(entry, "grant")?;
        let grant = parse_grant(entry, list)?;
        if grants
            .iter()
            .any(|existing| existing.name() == grant.name())
        {
            return Err(error(entry, format!("duplicate {} grant", grant.name())));
        }
        grants.push(grant);
    }
    Ok(grants)
}

fn parse_grant(node: &SExpr, list: &[SExpr]) -> Result<Grant, ParseError> {
    let name = list
        .first()
        .and_then(SExpr::atom)
        .ok_or_else(|| error(node, "grant requires a name"))?;
    match (name, list.len()) {
        // `canceled` is an atom and a path is a string, so the two directory
        // forms cannot be confused for one another.
        ("directory", 2) if list[1].atom() == Some("canceled") => Ok(Grant::DirectoryCanceled),
        ("directory", 2) => Ok(Grant::Directory(grant_path(&list[1], "directory")?)),
        ("app-data", 2) => Ok(Grant::AppData(grant_path(&list[1], "app-data")?)),
        ("assets", 2) => Ok(Grant::Assets(grant_path(&list[1], "assets")?)),
        ("clipboard", 2) => match list[1].atom() {
            Some("system") => Ok(Grant::Clipboard { system: true }),
            Some("fixture") => Ok(Grant::Clipboard { system: false }),
            _ => Err(error(node, "clipboard grant must be system or fixture")),
        },
        ("audio", 2) if list[1].atom() == Some("null") => Ok(Grant::AudioNull),
        ("http-origin", 2) => Ok(Grant::HttpOrigin(grant_string(&list[1], "http-origin")?)),
        ("tcp", 2) => Ok(Grant::Tcp(grant_string(&list[1], "tcp")?)),
        ("server", 3) => {
            let script = grant_path(&list[1], "server")?;
            let port = list[2]
                .atom()
                .and_then(|value| value.parse::<u32>().ok())
                .filter(|port| (1..=65535).contains(port))
                .ok_or_else(|| error(node, "server grant requires a readiness port 1..65535"))?;
            Ok(Grant::Server { script, port })
        }
        ("process", 2) => match list[1].atom() {
            Some(profile @ ("local-shell" | "test-program")) => {
                Ok(Grant::Process(profile.to_owned()))
            }
            _ => Err(error(
                node,
                "process grant must be local-shell or test-program",
            )),
        },
        ("device", 2 | 3) => {
            if list[1].atom() != Some("virtual") {
                let identifier = grant_string(&list[1], "device")?;
                if list.len() != 2 {
                    return Err(error(node, "a VID:PID device grant takes no control count"));
                }
                return Ok(Grant::Device(identifier));
            }
            match list.get(2) {
                None => Ok(Grant::Device("virtual".to_owned())),
                Some(count) => {
                    let controls = count
                        .atom()
                        .and_then(|value| value.parse::<u32>().ok())
                        .ok_or_else(|| {
                            error(node, "virtual device control count must be an integer")
                        })?;
                    Ok(Grant::Device(format!("virtual:{controls}")))
                }
            }
        }
        ("system-monitor", 2 | 3) => match (list[1].atom(), list.get(2)) {
            (Some(kind @ ("standard" | "unavailable")), None) => {
                Ok(Grant::SystemMonitor(kind.to_owned()))
            }
            (Some("processes"), Some(count)) => {
                let processes = count
                    .atom()
                    .and_then(|value| value.parse::<u32>().ok())
                    .ok_or_else(|| {
                        error(node, "system-monitor process count must be an integer")
                    })?;
                Ok(Grant::SystemMonitor(format!("processes:{processes}")))
            }
            _ => Err(error(
                node,
                "system-monitor grant must be standard, unavailable, or (processes N)",
            )),
        },
        (
            "directory" | "app-data" | "assets" | "clipboard" | "audio" | "http-origin" | "tcp"
            | "server" | "process" | "device" | "system-monitor",
            _,
        ) => Err(error(node, format!("malformed {name} grant"))),
        _ => Err(error(
            node,
            format!(
                "unsupported grant {name}; supported grants are app-data, audio, clipboard, \
                 device, directory, http-origin, process, server, system-monitor, and tcp"
            ),
        )),
    }
}

fn grant_string(node: &SExpr, name: &str) -> Result<String, ParseError> {
    node.string()
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| error(node, format!("{name} grant requires a non-empty string")))
}

/// Validate a path a specification supplies.
///
/// A grant path is relative to the application directory and may not leave it.
/// The check is lexical and happens at parse time, so a path that escapes is a
/// parse error naming its line rather than a capability the harness hands out.
fn grant_path(node: &SExpr, name: &str) -> Result<String, ParseError> {
    let value = grant_string(node, name)?;
    if value.starts_with('/') || value.starts_with('\\') || value.contains('\0') {
        return Err(error(
            node,
            format!("{name} grant path must be relative to the application directory"),
        ));
    }
    if value
        .split('/')
        .any(|segment| segment.is_empty() || segment == "." || segment == "..")
    {
        return Err(error(
            node,
            format!("{name} grant path must stay inside the application directory"),
        ));
    }
    Ok(value)
}

fn parse_benchmark(node: &SExpr, values: &[SExpr]) -> Result<Benchmark, ParseError> {
    let mut result = Benchmark {
        warmups: 0,
        samples: 1,
        iterations: 1,
        scale: 0,
        initial_size: 0,
        change_size: 0,
    };
    let mut seen = std::collections::HashSet::new();
    let mut index = 1;
    while index < values.len() {
        let key = values[index]
            .atom()
            .ok_or_else(|| error(&values[index], "benchmark key must be an atom"))?;
        let value = values
            .get(index + 1)
            .and_then(SExpr::atom)
            .ok_or_else(|| error(&values[index], format!("{key} requires an integer")))?;
        if !seen.insert(key) {
            return Err(error(
                &values[index],
                format!("duplicate benchmark key {key}"),
            ));
        }
        match key {
            ":warmups" => result.warmups = parse_u32(&values[index + 1], value, true)?,
            ":samples" => result.samples = parse_u32(&values[index + 1], value, false)?,
            ":iterations" => result.iterations = parse_u32(&values[index + 1], value, false)?,
            ":scale" => {
                result.scale = value
                    .parse()
                    .map_err(|_| error(&values[index + 1], "scale must be a positive integer"))?;
                if result.scale == 0 {
                    return Err(error(
                        &values[index + 1],
                        "scale must be a positive integer",
                    ));
                }
            }
            ":initial-size" => {
                result.initial_size = value.parse().map_err(|_| {
                    error(
                        &values[index + 1],
                        "initial size must be a non-negative integer",
                    )
                })?;
            }
            ":change-size" => {
                result.change_size = value.parse().map_err(|_| {
                    error(
                        &values[index + 1],
                        "change size must be a non-negative integer",
                    )
                })?;
            }
            _ => {
                return Err(error(
                    &values[index],
                    format!("unsupported benchmark key {key}"),
                ));
            }
        }
        index += 2;
    }
    if result.scale == 0 {
        return Err(error(node, "benchmark requires :scale"));
    }
    let lifecycles = u64::from(result.warmups)
        .checked_add(u64::from(result.samples) * u64::from(result.iterations))
        .ok_or_else(|| error(node, "benchmark lifecycle count overflows"))?;
    if lifecycles > MAX_BENCHMARK_LIFECYCLES {
        return Err(error(
            node,
            format!("benchmark exceeds the {MAX_BENCHMARK_LIFECYCLES}-lifecycle limit"),
        ));
    }
    Ok(result)
}

fn parse_u32(node: &SExpr, value: &str, zero_allowed: bool) -> Result<u32, ParseError> {
    let parsed: u32 = value
        .parse()
        .map_err(|_| error(node, "benchmark count must be an integer"))?;
    if !zero_allowed && parsed == 0 {
        return Err(error(node, "benchmark count must be positive"));
    }
    Ok(parsed)
}

fn parse_i32(node: &SExpr, description: &str) -> Result<i32, ParseError> {
    node.atom()
        .ok_or_else(|| error(node, format!("{description} must be an integer")))?
        .parse()
        .map_err(|_| error(node, format!("{description} must be an integer")))
}

/// Keyword arguments (`:key value`) trailing a step's positional arguments.
///
/// Mirrors the pair walking `parse_benchmark` already performs, so step and
/// benchmark keywords report the same way.
struct Keywords<'a> {
    head: &'a str,
    pairs: Vec<(&'a str, &'a SExpr)>,
}

fn parse_keywords<'a>(
    head: &'a str,
    rest: &'a [SExpr],
    allowed: &[&str],
) -> Result<Keywords<'a>, ParseError> {
    let mut pairs: Vec<(&'a str, &'a SExpr)> = Vec::new();
    let mut index = 0;
    while index < rest.len() {
        let key = rest[index]
            .atom()
            .filter(|value| value.starts_with(':'))
            .ok_or_else(|| error(&rest[index], format!("{head} expects :key value pairs")))?;
        if !allowed.contains(&key) {
            return Err(error(
                &rest[index],
                format!(
                    "unsupported key {key} for {head}; expected {}",
                    allowed.join(", ")
                ),
            ));
        }
        if pairs.iter().any(|(seen, _)| *seen == key) {
            return Err(error(
                &rest[index],
                format!("duplicate key {key} for {head}"),
            ));
        }
        let value = rest
            .get(index + 1)
            .ok_or_else(|| error(&rest[index], format!("{key} requires a value")))?;
        pairs.push((key, value));
        index += 2;
    }
    Ok(Keywords { head, pairs })
}

impl<'a> Keywords<'a> {
    fn expr(&self, key: &str) -> Option<&'a SExpr> {
        self.pairs
            .iter()
            .find(|(seen, _)| *seen == key)
            .map(|(_, value)| *value)
    }

    fn u32_in(
        &self,
        key: &str,
        range: std::ops::RangeInclusive<u32>,
    ) -> Result<Option<u32>, ParseError> {
        let Some(value) = self.expr(key) else {
            return Ok(None);
        };
        let parsed: u32 = value
            .atom()
            .and_then(|text| text.parse().ok())
            .ok_or_else(|| error(value, format!("{key} requires an integer")))?;
        if !range.contains(&parsed) {
            return Err(error(
                value,
                format!(
                    "{key} for {} must be between {} and {}",
                    self.head,
                    range.start(),
                    range.end()
                ),
            ));
        }
        Ok(Some(parsed))
    }
}

fn parse_step(node: &SExpr) -> Result<Step, ParseError> {
    let values = require_list(node, "step")?;
    let head = values
        .first()
        .and_then(SExpr::atom)
        .ok_or_else(|| error(node, "step requires a command name"))?;
    let command = match head {
        "click" if values.len() == 2 => Command::Click(parse_locator(&values[1])?),
        "hover-enter" if values.len() == 2 => Command::HoverEnter(parse_locator(&values[1])?),
        "hover-exit" if values.len() == 2 => Command::HoverExit(parse_locator(&values[1])?),
        "expect-background" if values.len() == 3 => {
            let color = values[2]
                .atom()
                .and_then(|value| value.strip_prefix("0x"))
                .and_then(|value| u32::from_str_radix(value, 16).ok())
                .filter(|value| *value <= 0xffffff)
                .ok_or_else(|| {
                    error(
                        &values[2],
                        "expect-background requires an RGB color as 0xRRGGBB",
                    )
                })?;
            Command::ExpectBackground(parse_locator(&values[1])?, color)
        }
        "drag" if values.len() == 6 => Command::Drag(
            parse_locator(&values[1])?,
            parse_i32(&values[2], "drag coordinate")?,
            parse_i32(&values[3], "drag coordinate")?,
            parse_i32(&values[4], "drag coordinate")?,
            parse_i32(&values[5], "drag coordinate")?,
        ),
        "replace-text" if values.len() == 3 => Command::ReplaceText(
            parse_locator(&values[1])?,
            values[2]
                .string()
                .ok_or_else(|| error(&values[2], "replace-text requires a string"))?
                .to_owned(),
        ),
        "focus" if values.len() == 2 => Command::Focus(parse_locator(&values[1])?),
        "press-key" if values.len() == 2 => {
            let key = values[1]
                .atom()
                .ok_or_else(|| error(&values[1], "press-key requires Enter, Escape, or Space"))?;
            Command::PressKey(match key {
                "Enter" => ControlKey::Enter,
                "Escape" => ControlKey::Escape,
                "Space" => ControlKey::Space,
                _ => {
                    return Err(error(
                        &values[1],
                        "press-key requires Enter, Escape, or Space",
                    ));
                }
            })
        }
        "await-task" if values.len() == 1 => Command::AwaitTask,
        "await-count" if values.len() == 3 => {
            let expected = values[2]
                .atom()
                .ok_or_else(|| error(&values[2], "await-count requires a non-negative integer"))?
                .parse::<usize>()
                .map_err(|_| error(&values[2], "await-count requires a non-negative integer"))?;
            Command::AwaitCount(parse_locator(&values[1])?, expected)
        }
        "type" if values.len() == 2 => {
            let text = values[1]
                .string()
                .ok_or_else(|| error(&values[1], "type requires a string"))?;
            if text.is_empty() {
                return Err(error(&values[1], "type requires a non-empty string"));
            }
            Command::Type(text.to_owned())
        }
        "key" if values.len() == 2 => {
            let chord = values[1]
                .string()
                .ok_or_else(|| error(&values[1], "key requires a chord string"))?;
            if !valid_chord(chord) {
                return Err(error(
                    &values[1],
                    "key requires a chord such as \"cmd-a\" or \"ctrl-shift-k\"",
                ));
            }
            Command::Key(chord.to_owned())
        }
        "screenshot" if values.len() >= 2 => {
            let name = values[1]
                .string()
                .ok_or_else(|| error(&values[1], "screenshot requires a name string"))?;
            if !valid_screenshot_name(name) {
                return Err(error(
                    &values[1],
                    "screenshot names use lowercase letters, digits, and hyphens, up to 48 characters",
                ));
            }
            let keywords = parse_keywords(head, &values[2..], &[":region", ":pad"])?;
            let region = match keywords.expr(":region") {
                None => Region::Window,
                Some(node) => parse_region(node)?,
            };
            Command::Screenshot(Screenshot {
                name: name.to_owned(),
                region,
                pad: keywords.u32_in(":pad", 0..=256)?.unwrap_or(0),
            })
        }
        "expect-on-screen" if values.len() == 2 => {
            Command::ExpectOnScreen(parse_locator(&values[1])?)
        }
        "expect-rendered-count" if values.len() == 3 => Command::ExpectRenderedCount(
            parse_locator(&values[1])?,
            values[2]
                .atom()
                .and_then(|text| text.parse().ok())
                .ok_or_else(|| {
                    error(
                        &values[2],
                        "expect-rendered-count requires a non-negative integer",
                    )
                })?,
        ),
        "expect-bounds" if values.len() >= 2 => {
            let locator = parse_locator(&values[1])?;
            let keywords = parse_keywords(
                head,
                &values[2..],
                &[":min-width", ":max-width", ":min-height", ":max-height"],
            )?;
            let expectation = BoundsExpectation {
                min_width: keywords.u32_in(":min-width", 0..=100_000)?,
                max_width: keywords.u32_in(":max-width", 0..=100_000)?,
                min_height: keywords.u32_in(":min-height", 0..=100_000)?,
                max_height: keywords.u32_in(":max-height", 0..=100_000)?,
            };
            if expectation.is_empty() {
                return Err(error(
                    node,
                    "expect-bounds requires at least one of :min-width, :max-width, :min-height, :max-height",
                ));
            }
            Command::ExpectBounds(locator, expectation)
        }
        "resize" if values.len() == 3 => {
            let dimension = |index: usize, name: &str| -> Result<u32, ParseError> {
                values[index]
                    .atom()
                    .and_then(|value| value.parse::<u32>().ok())
                    .filter(|value| (64..=8192).contains(value))
                    .ok_or_else(|| {
                        error(
                            &values[index],
                            &format!("resize {name} is 64 to 8192 logical pixels"),
                        )
                    })
            };
            Command::Resize {
                width: dimension(1, "width")?,
                height: dimension(2, "height")?,
            }
        }
        "scroll" if values.len() >= 2 => {
            let region = parse_locator(&values[1])?;
            let keywords = parse_keywords(head, &values[2..], &[":by", ":to"])?;
            let motion = match (keywords.expr(":by"), keywords.expr(":to")) {
                (Some(by), None) => {
                    let amount = by
                        .atom()
                        .and_then(|text| text.parse::<i32>().ok())
                        .filter(|value| {
                            value.unsigned_abs() >= 1 && value.unsigned_abs() <= 100_000
                        })
                        .ok_or_else(|| {
                            error(
                                by,
                                "scroll :by is a non-zero number of logical pixels, up to 100000",
                            )
                        })?;
                    ScrollMotion::By(amount)
                }
                (None, Some(to)) => ScrollMotion::To(parse_locator(to)?),
                _ => {
                    return Err(error(node, "scroll requires exactly one of :by and :to"));
                }
            };
            Command::Scroll { region, motion }
        }
        "settle" => {
            let keywords = parse_keywords(head, &values[1..], &[":frames", ":timeout-ms"])?;
            Command::Settle {
                frames: keywords.u32_in(":frames", 1..=60)?.unwrap_or(2),
                timeout_ms: keywords.u32_in(":timeout-ms", 1..=60_000)?.unwrap_or(2_000),
            }
        }
        "clipboard-text" if values.len() == 2 => Command::ClipboardText(
            values[1]
                .string()
                .ok_or_else(|| error(&values[1], "clipboard-text requires a string"))?
                .to_owned(),
        ),
        "await-ticks" if values.len() == 2 => Command::AwaitTicks(
            values[1]
                .atom()
                .ok_or_else(|| error(&values[1], "await-ticks requires a positive integer"))?
                .parse()
                .map_err(|_| error(&values[1], "await-ticks requires a positive integer"))?,
        ),
        "expect-subscriptions" if values.len() == 2 => Command::ExpectSubscriptions(
            values[1]
                .atom()
                .ok_or_else(|| {
                    error(
                        &values[1],
                        "expect-subscriptions requires a non-negative integer",
                    )
                })?
                .parse()
                .map_err(|_| {
                    error(
                        &values[1],
                        "expect-subscriptions requires a non-negative integer",
                    )
                })?,
        ),
        "expect-tcp-streams" if values.len() == 2 => Command::ExpectTcpStreams(
            values[1]
                .atom()
                .ok_or_else(|| {
                    error(
                        &values[1],
                        "expect-tcp-streams requires a non-negative integer",
                    )
                })?
                .parse()
                .map_err(|_| {
                    error(
                        &values[1],
                        "expect-tcp-streams requires a non-negative integer",
                    )
                })?,
        ),
        "expect-processes" if values.len() == 2 => Command::ExpectProcesses(
            values[1]
                .atom()
                .ok_or_else(|| {
                    error(
                        &values[1],
                        "expect-processes requires a non-negative integer",
                    )
                })?
                .parse()
                .map_err(|_| {
                    error(
                        &values[1],
                        "expect-processes requires a non-negative integer",
                    )
                })?,
        ),
        "expect-clipboard-counters" if values.len() == 5 => {
            let mut expected = [None; 4];
            for (index, value) in values[1..].iter().enumerate() {
                let atom = value
                    .atom()
                    .ok_or_else(|| error(value, "clipboard counters must be integers or _"))?;
                expected[index] = if atom == "_" {
                    None
                } else {
                    Some(atom.parse().map_err(|_| {
                        error(
                            value,
                            "clipboard counters must be non-negative integers or _",
                        )
                    })?)
                };
            }
            Command::ExpectClipboardCounters(expected)
        }
        "expect-sqlite-counters" if values.len() == 4 => {
            let mut expected = [0u64; 3];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = value
                    .atom()
                    .ok_or_else(|| error(value, "SQLite counters must be integers"))?
                    .parse()
                    .map_err(|_| error(value, "SQLite counters must be non-negative integers"))?;
            }
            Command::ExpectSqliteCounters(expected)
        }
        "expect-http-counters" if values.len() == 5 => {
            let mut expected = [0u64; 4];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = value
                    .atom()
                    .ok_or_else(|| error(value, "HTTP counters must be integers"))?
                    .parse()
                    .map_err(|_| error(value, "HTTP counters must be non-negative integers"))?;
            }
            Command::ExpectHttpCounters(expected)
        }
        "expect-tcp-counters" if values.len() == 6 => {
            let mut expected = [0u64; 5];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = value
                    .atom()
                    .ok_or_else(|| error(value, "TCP counters must be integers"))?
                    .parse()
                    .map_err(|_| error(value, "TCP counters must be non-negative integers"))?;
            }
            Command::ExpectTcpCounters(expected)
        }
        "expect-device-connections" if values.len() == 2 => Command::ExpectDeviceConnections(
            values[1]
                .atom()
                .ok_or_else(|| {
                    error(
                        &values[1],
                        "expect-device-connections requires a non-negative integer",
                    )
                })?
                .parse()
                .map_err(|_| {
                    error(
                        &values[1],
                        "expect-device-connections requires a non-negative integer",
                    )
                })?,
        ),
        "expect-device-transactions" if values.len() == 2 => Command::ExpectDeviceTransactions(
            values[1]
                .atom()
                .ok_or_else(|| {
                    error(
                        &values[1],
                        "expect-device-transactions requires a non-negative integer",
                    )
                })?
                .parse()
                .map_err(|_| {
                    error(
                        &values[1],
                        "expect-device-transactions requires a non-negative integer",
                    )
                })?,
        ),
        "expect-system-samplers" if values.len() == 2 => {
            Command::ExpectSystemSamplers(parse_non_negative(&values[1], "expect-system-samplers")?)
        }
        "expect-system-samples" if values.len() == 2 => {
            Command::ExpectSystemSamples(parse_non_negative(&values[1], "expect-system-samples")?)
        }
        "expect-audio-counters" if values.len() == 10 => {
            let mut expected = [0u64; 9];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = value
                    .atom()
                    .ok_or_else(|| error(value, "audio counters must be integers"))?
                    .parse()
                    .map_err(|_| error(value, "audio counters must be non-negative integers"))?;
            }
            Command::ExpectAudioCounters(expected)
        }
        "expect-file-picks" | "expect-file-lists" | "expect-file-opens" | "expect-file-reads"
            if values.len() == 2 =>
        {
            let expected = values[1]
                .atom()
                .ok_or_else(|| error(&values[1], "file counter must be an integer"))?
                .parse()
                .map_err(|_| error(&values[1], "file counter must be a non-negative integer"))?;
            match head {
                "expect-file-picks" => Command::ExpectFilePicks(expected),
                "expect-file-lists" => Command::ExpectFileLists(expected),
                "expect-file-opens" => Command::ExpectFileOpens(expected),
                _ => Command::ExpectFileReads(expected),
            }
        }
        "expect-image-owner-counters" if values.len() == 5 => {
            let mut expected = [0u64; 4];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = value
                    .atom()
                    .ok_or_else(|| error(value, "image owner counters must be integers"))?
                    .parse()
                    .map_err(|_| {
                        error(value, "image owner counters must be non-negative integers")
                    })?;
            }
            Command::ExpectImageOwnerCounters(expected)
        }
        "expect-asset-counters" if values.len() == 7 => {
            let mut expected = [0u64; 6];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = parse_non_negative(value, "expect-asset-counters")? as u64;
            }
            Command::ExpectAssetCounters(expected)
        }
        "expect-file-selection-counters" if values.len() == 8 => {
            let mut expected = [0u64; 7];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = value
                    .atom()
                    .ok_or_else(|| error(value, "file selection counters must be integers"))?
                    .parse()
                    .map_err(|_| {
                        error(
                            value,
                            "file selection counters must be non-negative integers",
                        )
                    })?;
            }
            Command::ExpectFileSelectionCounters(expected)
        }
        "expect-file-lifecycle-counters" if values.len() == 7 => {
            let mut expected = [0u64; 6];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] =
                    parse_non_negative(value, "expect-file-lifecycle-counters")? as u64;
            }
            Command::ExpectFileLifecycleCounters(expected)
        }
        "expect-file-access" if values.len() == 4 => {
            let mut expected = [0u64; 3];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = parse_non_negative(value, "expect-file-access")? as u64;
            }
            Command::ExpectFileAccess(expected)
        }
        "revoke-file-grants" if values.len() == 1 => Command::RevokeFileGrants,
        "submit" if values.len() == 2 => Command::Submit(parse_locator(&values[1])?),
        "expect-visible" if values.len() == 2 => Command::ExpectVisible(parse_locator(&values[1])?),
        "expect-focused" if values.len() == 2 => Command::ExpectFocused(parse_locator(&values[1])?),
        "expect-not-visible" if values.len() == 2 => {
            Command::ExpectNotVisible(parse_locator(&values[1])?)
        }
        "expect-count" if values.len() == 3 => {
            let expected = values[2]
                .atom()
                .ok_or_else(|| error(&values[2], "expect-count requires a non-negative integer"))?
                .parse::<usize>()
                .map_err(|_| error(&values[2], "expect-count requires a non-negative integer"))?;
            Command::ExpectCount(parse_locator(&values[1])?, expected)
        }
        "expect-canvas-primitives" if values.len() == 3 => {
            let expected = values[2]
                .atom()
                .ok_or_else(|| {
                    error(
                        &values[2],
                        "expect-canvas-primitives requires a non-negative integer",
                    )
                })?
                .parse::<usize>()
                .map_err(|_| {
                    error(
                        &values[2],
                        "expect-canvas-primitives requires a non-negative integer",
                    )
                })?;
            Command::ExpectCanvasPrimitives(parse_locator(&values[1])?, expected)
        }
        "expect-value" if values.len() == 3 => Command::ExpectValue(
            parse_locator(&values[1])?,
            values[2]
                .string()
                .ok_or_else(|| error(&values[2], "expect-value requires a string"))?
                .to_owned(),
        ),
        "expect-value-bytes" if values.len() == 3 => Command::ExpectValueBytes(
            parse_locator(&values[1])?,
            values[2]
                .atom()
                .ok_or_else(|| error(&values[2], "expect-value-bytes requires an integer"))?
                .parse()
                .map_err(|_| error(&values[2], "expect-value-bytes requires an integer"))?,
        ),
        "expect-image-bytes" if values.len() == 3 => Command::ExpectImageBytes(
            parse_locator(&values[1])?,
            values[2]
                .atom()
                .ok_or_else(|| error(&values[2], "expect-image-bytes requires an integer"))?
                .parse()
                .map_err(|_| error(&values[2], "expect-image-bytes requires an integer"))?,
        ),
        "expect-before" if values.len() == 3 => {
            Command::ExpectBefore(parse_locator(&values[1])?, parse_locator(&values[2])?)
        }
        "expect-component-work" if values.len() >= 3 && values.len() % 2 == 1 => {
            let mut expected = [None; crate::observatory::COMPONENT_WORK_NAMES.len()];
            for pair in values[1..].chunks_exact(2) {
                let name = pair[0]
                    .atom()
                    .and_then(|name| name.strip_prefix(':'))
                    .ok_or_else(|| {
                        error(
                            &pair[0],
                            "component work requires named :counter COUNT pairs",
                        )
                    })?;
                let index = crate::observatory::COMPONENT_WORK_NAMES
                    .iter()
                    .position(|candidate| candidate.replace('_', "-") == name)
                    .ok_or_else(|| error(&pair[0], "unknown component work counter"))?;
                if expected[index].is_some() {
                    return Err(error(&pair[0], "duplicate component work counter"));
                }
                expected[index] = Some(
                    pair[1]
                        .atom()
                        .ok_or_else(|| {
                            error(
                                &pair[1],
                                "component work count must be a non-negative integer",
                            )
                        })?
                        .parse::<u64>()
                        .map_err(|_| {
                            error(
                                &pair[1],
                                "component work count must be a non-negative integer",
                            )
                        })?,
                );
            }
            Command::ExpectComponentWork(expected)
        }
        "expect-patch" if values.len() == 7 => {
            if values[1].atom() != Some(":kind")
                || values[3].atom() != Some(":staged")
                || values[5].atom() != Some(":removed")
            {
                return Err(error(
                    node,
                    "expect-patch syntax is :kind KIND :staged COUNT :removed COUNT",
                ));
            }
            let kind = values[2].atom().ok_or_else(|| {
                error(
                    &values[2],
                    "patch kind must be mount, replace, keyed, or no_change",
                )
            })?;
            if !matches!(kind, "mount" | "replace" | "keyed" | "no_change") {
                return Err(error(
                    &values[2],
                    "patch kind must be mount, replace, keyed, or no_change",
                ));
            }
            let count = |value: &SExpr| {
                value
                    .atom()
                    .ok_or_else(|| error(value, "patch count must be a non-negative integer"))?
                    .parse::<u64>()
                    .map_err(|_| error(value, "patch count must be a non-negative integer"))
            };
            Command::ExpectPatch(PatchExpectation {
                kind: kind.to_owned(),
                staged: count(&values[4])?,
                removed: count(&values[6])?,
            })
        }
        "mark-native-work" if values.len() == 1 => Command::MarkNativeWork,
        "expect-native-work" => {
            let keys = parse_keywords(
                head,
                &values[1..],
                &[
                    ":button-renders-max",
                    ":boundary-renders-max",
                    ":boundary-elements-max",
                    ":cached-prepaint-subtrees-min",
                    ":cached-paint-subtrees-min",
                    ":replayed-scene-operations-min",
                    ":fresh-hitboxes-max",
                    ":fresh-mouse-listeners-max",
                    ":element-states-moved-min",
                ],
            )?;
            let count = |key| -> Result<Option<u64>, ParseError> {
                keys.expr(key)
                    .map(|value| {
                        value
                            .atom()
                            .and_then(|value| value.parse::<u64>().ok())
                            .ok_or_else(|| {
                                error(value, format!("{key} requires a non-negative integer"))
                            })
                    })
                    .transpose()
            };
            let button_renders_max = count(":button-renders-max")?;
            let boundary_renders_max = count(":boundary-renders-max")?;
            let boundary_elements_max = count(":boundary-elements-max")?;
            let cached_prepaint_subtrees_min = count(":cached-prepaint-subtrees-min")?;
            let cached_paint_subtrees_min = count(":cached-paint-subtrees-min")?;
            let replayed_scene_operations_min = count(":replayed-scene-operations-min")?;
            let fresh_hitboxes_max = count(":fresh-hitboxes-max")?;
            let fresh_mouse_listeners_max = count(":fresh-mouse-listeners-max")?;
            let element_states_moved_min = count(":element-states-moved-min")?;
            if button_renders_max.is_none()
                && boundary_renders_max.is_none()
                && boundary_elements_max.is_none()
                && cached_prepaint_subtrees_min.is_none()
                && cached_paint_subtrees_min.is_none()
                && replayed_scene_operations_min.is_none()
                && fresh_hitboxes_max.is_none()
                && fresh_mouse_listeners_max.is_none()
                && element_states_moved_min.is_none()
            {
                return Err(error(
                    node,
                    "expect-native-work requires at least one native work maximum",
                ));
            }
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
            }
        }
        "mark-metrics" if values.len() == 1 => Command::MarkMetrics,
        "click"
        | "drag"
        | "replace-text"
        | "focus"
        | "press-key"
        | "await-task"
        | "await-count"
        | "clipboard-text"
        | "await-ticks"
        | "expect-subscriptions"
        | "expect-tcp-streams"
        | "expect-processes"
        | "expect-clipboard-counters"
        | "expect-sqlite-counters"
        | "expect-http-counters"
        | "expect-tcp-counters"
        | "expect-device-connections"
        | "expect-device-transactions"
        | "expect-system-samplers"
        | "expect-system-samples"
        | "expect-audio-counters"
        | "expect-file-picks"
        | "expect-file-lists"
        | "expect-file-opens"
        | "expect-file-reads"
        | "expect-file-selection-counters"
        | "expect-file-lifecycle-counters"
        | "expect-file-access"
        | "revoke-file-grants"
        | "expect-image-owner-counters"
        | "expect-asset-counters"
        | "expect-component-work"
        | "expect-visible"
        | "expect-not-visible"
        | "expect-count"
        | "expect-canvas-primitives"
        | "expect-before"
        | "expect-patch"
        | "expect-value"
        | "expect-value-bytes"
        | "expect-image-bytes"
        | "submit"
        | "mark-metrics"
        | "mark-native-work"
        | "expect-on-screen"
        | "expect-rendered-count"
        | "expect-bounds"
        | "screenshot"
        | "type"
        | "key"
        | "scroll" => {
            return Err(error(node, format!("invalid arguments for {head}")));
        }
        _ => return Err(error(node, format!("unsupported step {head}"))),
    };
    Ok(Step {
        line: node.line(),
        command,
    })
}

fn parse_region(node: &SExpr) -> Result<Region, ParseError> {
    let values = require_list(node, "region")?;
    if values.first().and_then(SExpr::atom) == Some("rect") {
        if values.len() != 5 {
            return Err(error(node, "rect region requires x, y, width, and height"));
        }
        let mut numbers = [0u32; 4];
        for (slot, value) in numbers.iter_mut().zip(&values[1..]) {
            *slot = value
                .atom()
                .and_then(|text| text.parse().ok())
                .ok_or_else(|| error(value, "rect region requires non-negative integers"))?;
        }
        if numbers[2] == 0 || numbers[3] == 0 {
            return Err(error(
                node,
                "rect region requires a non-zero width and height",
            ));
        }
        return Ok(Region::Rect {
            x: numbers[0],
            y: numbers[1],
            width: numbers[2],
            height: numbers[3],
        });
    }
    Ok(Region::Locator(parse_locator(node)?))
}

fn parse_locator(node: &SExpr) -> Result<Locator, ParseError> {
    let values = require_list(node, "locator")?;
    match values.first().and_then(SExpr::atom) {
        Some("within") if values.len() == 3 => Ok(Locator::Within(
            Box::new(parse_locator(&values[1])?),
            Box::new(parse_locator(&values[2])?),
        )),
        Some("within") => Err(error(
            node,
            "within requires an ancestor and a target locator",
        )),
        Some("text") if values.len() == 2 => values[1]
            .string()
            .map(|value| Locator::Text(value.to_owned()))
            .ok_or_else(|| error(node, "text locator requires a string")),
        Some("text-prefix") if values.len() == 2 => values[1]
            .string()
            .map(|value| Locator::TextPrefix(value.to_owned()))
            .ok_or_else(|| error(node, "text-prefix locator requires a string")),
        Some("checkbox-prefix") if values.len() == 2 => values[1]
            .string()
            .map(|value| Locator::CheckboxPrefix(value.to_owned()))
            .ok_or_else(|| error(node, "checkbox-prefix locator requires a string")),
        Some("canvas-item-prefix") if values.len() == 2 => values[1]
            .string()
            .map(|value| Locator::CanvasItemPrefix(value.to_owned()))
            .ok_or_else(|| error(node, "canvas-item-prefix locator requires a string")),
        Some("button-prefix") if values.len() == 2 => values[1]
            .string()
            .map(|value| Locator::ButtonPrefix(value.to_owned()))
            .ok_or_else(|| error(node, "button-prefix locator requires a string")),
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("canvas-item")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::CanvasItemName(value.to_owned()))
                .ok_or_else(|| error(node, "canvas item name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("canvas")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::CanvasName(value.to_owned()))
                .ok_or_else(|| error(node, "canvas name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("dialog")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::DialogName(value.to_owned()))
                .ok_or_else(|| error(node, "dialog name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("textbox")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::TextInputName(value.to_owned()))
                .ok_or_else(|| error(node, "textbox name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("panel")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::PanelName(value.to_owned()))
                .ok_or_else(|| error(node, "panel name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("textarea")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::TextareaName(value.to_owned()))
                .ok_or_else(|| error(node, "textarea name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("image")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::ImageName(value.to_owned()))
                .ok_or_else(|| error(node, "image name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("column")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::ColumnName(value.to_owned()))
                .ok_or_else(|| error(node, "column name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("row")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::RowName(value.to_owned()))
                .ok_or_else(|| error(node, "row name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("button")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::ButtonName(value.to_owned()))
                .ok_or_else(|| error(node, "button name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("checkbox")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::CheckboxName(value.to_owned()))
                .ok_or_else(|| error(node, "checkbox name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("scroll")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::ScrollName(value.to_owned()))
                .ok_or_else(|| error(node, "scroll name must be a string"))
        }
        Some("role")
            if values.len() == 4
                && values[1].atom() == Some("virtual-list")
                && values[2].atom() == Some(":name") =>
        {
            values[3]
                .string()
                .map(|value| Locator::VirtualListName(value.to_owned()))
                .ok_or_else(|| error(node, "virtual-list name must be a string"))
        }
        Some("role") => Err(error(
            node,
            "supported roles are button, canvas, canvas-item, checkbox, column, dialog, image, panel, row, scroll, textarea, textbox, and virtual-list",
        )),
        Some(other) => Err(error(node, format!("unsupported locator {other}"))),
        None => Err(error(node, "locator requires a name")),
    }
}

fn require_list<'a>(node: &'a SExpr, context: &str) -> Result<&'a [SExpr], ParseError> {
    node.list()
        .ok_or_else(|| error(node, format!("{context} must be a list")))
}

fn error(node: &SExpr, message: impl Into<String>) -> ParseError {
    ParseError {
        line: node.line(),
        message: message.into(),
    }
}

fn parse_non_negative(node: &SExpr, command: &str) -> Result<usize, ParseError> {
    let message = || format!("{command} requires a non-negative integer");
    node.atom()
        .ok_or_else(|| error(node, message()))?
        .parse()
        .map_err(|_| error(node, message()))
}

struct Parser<'a> {
    bytes: &'a [u8],
    index: usize,
    line: usize,
    expressions: usize,
}

impl<'a> Parser<'a> {
    fn new(source: &'a str) -> Self {
        Self {
            bytes: source.as_bytes(),
            index: 0,
            line: 1,
            expressions: 0,
        }
    }

    fn expr(&mut self) -> Result<SExpr, ParseError> {
        self.expr_at_depth(0)
    }

    fn expr_at_depth(&mut self, depth: usize) -> Result<SExpr, ParseError> {
        if depth > MAX_NESTING_DEPTH {
            return Err(self.error(format!(
                "spec exceeds the {MAX_NESTING_DEPTH}-level nesting limit"
            )));
        }
        self.expressions += 1;
        if self.expressions > MAX_EXPRESSIONS {
            return Err(self.error(format!(
                "spec exceeds the {MAX_EXPRESSIONS}-expression limit"
            )));
        }
        self.skip_space_and_comments();
        let line = self.line;
        match self.peek() {
            Some(b'(') => {
                self.index += 1;
                let mut values = Vec::new();
                loop {
                    self.skip_space_and_comments();
                    match self.peek() {
                        Some(b')') => {
                            self.index += 1;
                            break;
                        }
                        None => return Err(self.error("unterminated list")),
                        _ => values.push(self.expr_at_depth(depth + 1)?),
                    }
                }
                Ok(SExpr::List(values, line))
            }
            Some(b'"') => self.string(line),
            Some(b')') => Err(self.error("unexpected ')'")),
            Some(_) => self.atom(line),
            None => Err(self.error("expected expression")),
        }
    }

    fn string(&mut self, line: usize) -> Result<SExpr, ParseError> {
        self.index += 1;
        let mut value = String::new();
        loop {
            let byte = self
                .peek()
                .ok_or_else(|| self.error("unterminated string"))?;
            self.index += 1;
            match byte {
                b'"' => break,
                b'\\' => {
                    let escaped = self
                        .peek()
                        .ok_or_else(|| self.error("unterminated escape"))?;
                    self.index += 1;
                    value.push(match escaped {
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'"' => '"',
                        b'\\' => '\\',
                        _ => return Err(self.error("unsupported string escape")),
                    });
                }
                b'\n' => {
                    self.line += 1;
                    value.push('\n');
                }
                _ if byte.is_ascii() => value.push(byte as char),
                _ => {
                    let start = self.index - 1;
                    let width = utf8_width(byte).ok_or_else(|| self.error("invalid UTF-8"))?;
                    let end = start + width;
                    if end > self.bytes.len() {
                        return Err(self.error("invalid UTF-8"));
                    }
                    value.push_str(
                        std::str::from_utf8(&self.bytes[start..end])
                            .map_err(|_| self.error("invalid UTF-8"))?,
                    );
                    self.index = end;
                }
            }
        }
        Ok(SExpr::String(value, line))
    }

    fn atom(&mut self, line: usize) -> Result<SExpr, ParseError> {
        let start = self.index;
        while let Some(byte) = self.peek() {
            if byte.is_ascii_whitespace() || matches!(byte, b'(' | b')' | b';') {
                break;
            }
            self.index += 1;
        }
        let value = std::str::from_utf8(&self.bytes[start..self.index])
            .map_err(|_| self.error("invalid UTF-8 atom"))?;
        Ok(SExpr::Atom(value.to_owned(), line))
    }

    fn skip_space_and_comments(&mut self) {
        loop {
            while let Some(byte) = self.peek() {
                if !byte.is_ascii_whitespace() {
                    break;
                }
                if byte == b'\n' {
                    self.line += 1;
                }
                self.index += 1;
            }
            if self.peek() != Some(b';') {
                break;
            }
            while let Some(byte) = self.peek() {
                self.index += 1;
                if byte == b'\n' {
                    self.line += 1;
                    break;
                }
            }
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.index).copied()
    }

    fn error(&self, message: impl Into<String>) -> ParseError {
        ParseError {
            line: self.line,
            message: message.into(),
        }
    }
}

fn utf8_width(first: u8) -> Option<usize> {
    match first {
        0xC2..=0xDF => Some(2),
        0xE0..=0xEF => Some(3),
        0xF0..=0xF4 => Some(4),
        _ => None,
    }
}

/// Reject a specification whose steps cannot run honestly on `runner`.
///
/// Reports the first offending step so the message names one concrete fix
/// rather than a list. Shared by both runners and their tests.
pub fn check_runner(spec: &Spec, runner: Runner) -> Result<(), String> {
    if runner == Runner::Window && spec.benchmark.is_some() {
        return Err(
            "benchmark clauses are semantic-only; the window runner runs one lifecycle".to_owned(),
        );
    }
    for step in &spec.steps {
        let capability = step.command.capability();
        if !capability.permits(runner) {
            return Err(format!(
                "line {}: step `{}` is {}; {}",
                step.line,
                step.command.kind(),
                capability.label(),
                capability.remedy(),
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;

    #[test]
    fn native_work_limits_are_window_only_and_strictly_parsed() {
        let parsed = parse(
            r#"(test "native" (steps (mark-native-work)
            (expect-native-work :button-renders-max 0 :boundary-renders-max 1)
            (expect-native-work :button-renders-max 18446744073709551615)
            (expect-native-work :boundary-renders-max 2)
            (expect-native-work :boundary-elements-max 100)
            (expect-native-work :cached-prepaint-subtrees-min 1 :cached-paint-subtrees-min 2
              :replayed-scene-operations-min 3 :fresh-hitboxes-max 4
              :fresh-mouse-listeners-max 5 :element-states-moved-min 6)))"#,
        )
        .unwrap();
        for step in &parsed.steps {
            assert_eq!(step.command.capability(), Capability::Window);
        }
        assert_eq!(
            parsed.steps[1].command,
            Command::ExpectNativeWork {
                button_renders_max: Some(0),
                boundary_renders_max: Some(1),
                boundary_elements_max: None,
                cached_prepaint_subtrees_min: None,
                cached_paint_subtrees_min: None,
                replayed_scene_operations_min: None,
                fresh_hitboxes_max: None,
                fresh_mouse_listeners_max: None,
                element_states_moved_min: None,
            }
        );
        assert_eq!(
            parsed.steps[5].command,
            Command::ExpectNativeWork {
                button_renders_max: None,
                boundary_renders_max: None,
                boundary_elements_max: None,
                cached_prepaint_subtrees_min: Some(1),
                cached_paint_subtrees_min: Some(2),
                replayed_scene_operations_min: Some(3),
                fresh_hitboxes_max: Some(4),
                fresh_mouse_listeners_max: Some(5),
                element_states_moved_min: Some(6),
            }
        );
        for command in [
            "mark-native-work 1",
            "expect-native-work",
            "expect-native-work :unknown 1",
            "expect-native-work :boundary-elements-max -1",
            "expect-native-work :button-renders-max",
            "expect-native-work :button-renders-max -1",
            "expect-native-work :button-renders-max 1.5",
            "expect-native-work :button-renders-max 18446744073709551616",
            "expect-native-work :button-renders-max 1 :button-renders-max 2",
        ] {
            assert!(
                parse(&format!("(test \"bad\" (steps ({command})))")).is_err(),
                "{command}"
            );
        }
    }

    #[test]
    fn hover_transitions_and_background_claims_are_shared_and_validate_colors() {
        let spec = parse(
            r#"(test "hover" (steps
            (hover-enter (role button :name "Cell 1"))
            (hover-exit (role button :name "Cell 1"))
            (expect-background (role button :name "Cell 1") 0x66E0FF)))"#,
        )
        .unwrap();
        assert!(check_runner(&spec, Runner::Semantic).is_ok());
        assert!(check_runner(&spec, Runner::Window).is_ok());
        assert!(spec.steps[0].command.is_operation());
        assert!(!spec.steps[2].command.is_operation());
        assert!(matches!(
            spec.steps[2].command,
            Command::ExpectBackground(_, 0x66E0FF)
        ));
        for color in ["0x1000000", "0xnope", "-1"] {
            assert!(
                parse(&format!(
                    r#"(test "bad" (steps (expect-background (role button :name "Cell") {color})))"#
                ))
                .is_err()
            );
        }
    }

    #[test]
    fn component_work_assertions_name_optional_last_turn_counts_on_both_runners() {
        let spec = parse(
            r#"(test "component work" (steps
            (expect-component-work :skipped 2 :rendered 1 :registry-visits 5 :projection-gets 7 :projection-sets 3)))"#,
        )
        .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::ExpectComponentWork([
                Some(1),
                None,
                Some(2),
                None,
                None,
                Some(5),
                None,
                Some(7),
                Some(3),
                None,
                None
            ])
        );
        assert!(check_runner(&spec, Runner::Semantic).is_ok());
        assert!(check_runner(&spec, Runner::Window).is_ok());
        assert!(!spec.steps[0].command.is_operation());
    }

    #[test]
    fn component_work_assertions_reject_ambiguous_or_invalid_counts() {
        for command in [
            "(expect-component-work)",
            "(expect-component-work :rendered)",
            "(expect-component-work :rendered -1)",
            "(expect-component-work :rendered 1 :rendered 2)",
            "(expect-component-work :registry_visits 1)",
            "(expect-component-work :unknown 0)",
            "(expect-component-work :rendered 18446744073709551616)",
        ] {
            assert!(
                parse(&format!("(test \"invalid\" (steps {command}))")).is_err(),
                "{command}"
            );
        }
    }

    #[test]
    fn parses_clipboard_fixture_changes_without_exposing_an_ambient_source() {
        let spec = parse(
            r#"(test "clipboard"
                (steps (clipboard-text "comparison value") (await-ticks 1)))"#,
        )
        .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::ClipboardText("comparison value".into())
        );
    }

    #[test]
    fn parses_native_owner_counter_assertions() {
        let clipboard =
            parse(r#"(test "clipboard counters" (steps (expect-clipboard-counters 1 2 3 4)))"#)
                .unwrap();
        assert!(matches!(
            clipboard.steps[0].command,
            Command::ExpectClipboardCounters([Some(1), Some(2), Some(3), Some(4)])
        ));
        let clipboard =
            parse(r#"(test "clipboard counters" (steps (expect-clipboard-counters 1 2 _ 4)))"#)
                .unwrap();
        assert!(matches!(
            clipboard.steps[0].command,
            Command::ExpectClipboardCounters([Some(1), Some(2), None, Some(4)])
        ));
        let sqlite =
            parse(r#"(test "SQLite counters" (steps (expect-sqlite-counters 1 2 3)))"#).unwrap();
        assert!(matches!(
            sqlite.steps[0].command,
            Command::ExpectSqliteCounters([1, 2, 3])
        ));
        let http =
            parse(r#"(test "HTTP counters" (steps (expect-http-counters 1 2 3 4)))"#).unwrap();
        assert!(matches!(
            http.steps[0].command,
            Command::ExpectHttpCounters([1, 2, 3, 4])
        ));
        let tcp =
            parse(r#"(test "TCP counters" (steps (expect-tcp-counters 1 2 3 4 5)))"#).unwrap();
        assert!(matches!(
            tcp.steps[0].command,
            Command::ExpectTcpCounters([1, 2, 3, 4, 5])
        ));
    }

    #[test]
    fn parses_semantic_test_and_comments() {
        let spec = parse(
            r#"(test "counter"
                ; human context
                (steps
                  (expect-visible (text "Counter"))
                  (click (role button :name "Left increment"))))"#,
        )
        .unwrap();
        assert_eq!(spec.name, "counter");
        assert_eq!(spec.steps.len(), 2);
        assert_eq!(spec.steps[1].line, 5);
    }

    #[test]
    fn parses_subscription_lifecycle_steps() {
        let spec =
            parse(r#"(test "timer" (steps (expect-subscriptions 1) (await-ticks 12)))"#).unwrap();
        assert_eq!(spec.steps[0].command, Command::ExpectSubscriptions(1));
        assert_eq!(spec.steps[1].command, Command::AwaitTicks(12));
    }

    #[test]
    fn parses_process_lifecycle_steps() {
        let spec = parse("(test \"process\" (steps (expect-processes 1)))").unwrap();
        assert_eq!(spec.steps[0].command, Command::ExpectProcesses(1));
    }

    #[test]
    fn parses_named_layout_roles() {
        let spec = parse(
            r#"(test "layout" (steps
				(expect-visible (role panel :name "Surface"))
				(expect-visible (role column :name "Content"))
                (expect-visible (role row :name "Toolbar"))))"#,
        )
        .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::ExpectVisible(Locator::PanelName("Surface".into()))
        );
        assert_eq!(
            spec.steps[1].command,
            Command::ExpectVisible(Locator::ColumnName("Content".into()))
        );
        assert_eq!(
            spec.steps[2].command,
            Command::ExpectVisible(Locator::RowName("Toolbar".into()))
        );
    }

    #[test]
    fn within_locators_nest_and_display_as_authored() {
        let locator = r#"(within (role panel :name "Left") (within (role row :name "Editor") (role textbox :name "Value")))"#;
        let spec = parse(&format!("(test \"scope\" (steps (focus {locator})))")).unwrap();
        let Command::Focus(parsed) = &spec.steps[0].command else {
            panic!("expected focus");
        };
        assert_eq!(parsed.to_string(), locator);
        assert_eq!(parsed.target(), &Locator::TextInputName("Value".into()));
        assert_eq!(spec.steps[0].command.capability(), Capability::Both);
    }

    #[test]
    fn within_rejects_missing_extra_or_invalid_locators() {
        for locator in [
            "(within)",
            "(within (text \"a\"))",
            "(within (text \"a\") (text \"b\") (text \"c\"))",
            "(within \"a\" (text \"b\"))",
            "(within (text \"a\") (unknown \"b\"))",
        ] {
            assert!(
                parse(&format!(
                    "(test \"scope\" (steps (expect-visible {locator})))"
                ))
                .is_err(),
                "accepted {locator}",
            );
        }
    }

    #[test]
    fn scroll_takes_a_distance_or_a_target_but_not_both() {
        let spec = parse(
            r#"(test "scroll"
                (steps
                  (scroll (role scroll :name "Directory contents") :by 240)
                  (scroll (role scroll :name "Directory contents")
                          :to (role row :name "Entry item-26.txt"))))"#,
        )
        .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::Scroll {
                region: Locator::ScrollName("Directory contents".into()),
                motion: ScrollMotion::By(240),
            }
        );
        assert_eq!(
            spec.steps[1].command,
            Command::Scroll {
                region: Locator::ScrollName("Directory contents".into()),
                motion: ScrollMotion::To(Locator::RowName("Entry item-26.txt".into())),
            }
        );
        // A negative distance scrolls back towards the start.
        assert!(matches!(
            parse(r#"(test "s" (steps (scroll (role scroll :name "c") :by -80)))"#)
                .unwrap()
                .steps[0]
                .command,
            Command::Scroll {
                motion: ScrollMotion::By(-80),
                ..
            }
        ));
        for bad in [
            r#"(test "s" (steps (scroll (role scroll :name "c"))))"#,
            r#"(test "s" (steps (scroll (role scroll :name "c") :by 0)))"#,
            r#"(test "s" (steps (scroll (role scroll :name "c") :by 10 :to (text "x"))))"#,
            r#"(test "s" (steps (scroll (role scroll :name "c") :toward 10)))"#,
        ] {
            assert!(parse(bad).is_err(), "accepted {bad}");
        }
    }

    #[test]
    fn scrolling_is_window_only() {
        let spec = parse(r#"(test "s" (steps (scroll (role scroll :name "c") :by 40)))"#).unwrap();
        assert!(check_runner(&spec, Runner::Window).is_ok());
        let refusal = check_runner(&spec, Runner::Semantic).unwrap_err();
        assert!(refusal.contains("window-only"), "{refusal}");
    }

    #[test]
    fn parses_named_scroll_region() {
        let spec = parse(
            r#"(test "scroll" (steps (expect-visible (role scroll :name "Directory contents"))))"#,
        )
        .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::ExpectVisible(Locator::ScrollName("Directory contents".into()))
        );
    }

    #[test]
    fn parses_named_virtual_list_region() {
        let spec =
            parse(r#"(test "virtual" (steps (expect-visible (role virtual-list :name "Rows"))))"#)
                .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::ExpectVisible(Locator::VirtualListName("Rows".into()))
        );
    }

    #[test]
    fn parses_asset_owner_counters_as_six_numbers() {
        let case = parse(r#"(test "assets" (steps (expect-asset-counters 1 0 1 2 0 4096)))"#)
            .expect("asset counters parse");
        assert_eq!(
            case.steps[0].command,
            Command::ExpectAssetCounters([1, 0, 1, 2, 0, 4096])
        );
        assert!(parse(r#"(test "assets" (steps (expect-asset-counters 1 2 3)))"#).is_err());
    }

    #[test]
    fn parses_image_identity_and_content_free_byte_evidence() {
        let spec = parse(
            r#"(test "image" (steps
                (expect-visible (role image :name "Preview"))
                (expect-image-bytes (role image :name "Preview") 100)))"#,
        )
        .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::ExpectVisible(Locator::ImageName("Preview".into()))
        );
        assert_eq!(
            spec.steps[1].command,
            Command::ExpectImageBytes(Locator::ImageName("Preview".into()), 100)
        );
    }

    #[test]
    fn parses_text_input_edits_and_submission() {
        let spec = parse(
            r#"(test "editing" (steps
                (replace-text (role textbox :name "Search") "privacy")
                (submit (role textbox :name "Search"))))"#,
        )
        .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::ReplaceText(Locator::TextInputName("Search".into()), "privacy".into())
        );
        assert_eq!(
            spec.steps[1].command,
            Command::Submit(Locator::TextInputName("Search".into()))
        );
    }

    #[test]
    fn parses_keyboard_activation() {
        let spec = parse(
            r#"(test "keyboard"
              (steps
                (focus (role button :name "Open"))
                (press-key Enter)
                (press-key Escape)
                (press-key Space)))"#,
        )
        .unwrap();
        assert!(matches!(spec.steps[0].command, Command::Focus(_)));
        assert_eq!(spec.steps[1].command, Command::PressKey(ControlKey::Enter));
        assert_eq!(spec.steps[2].command, Command::PressKey(ControlKey::Escape));
        assert_eq!(spec.steps[3].command, Command::PressKey(ControlKey::Space));
    }

    #[test]
    fn parses_a_complete_grant_set() {
        let case = parse(
            r#"(test "grants"
                 (grants
                   (directory "fixture")
                   (app-data "app-data-fixture/default")
                   (clipboard fixture)
                   (audio null)
                   (http-origin "http://127.0.0.1:38191")
                   (tcp "127.0.0.1:36379")
                   (server "fixture_server.py" 36379)
                   (process test-program)
                   (device virtual 100)
                   (system-monitor processes 500))
                 (steps (await-ticks 1)))"#,
        )
        .expect("grants parse");
        assert_eq!(
            case.grants,
            vec![
                Grant::Directory("fixture".into()),
                Grant::AppData("app-data-fixture/default".into()),
                Grant::Clipboard { system: false },
                Grant::AudioNull,
                Grant::HttpOrigin("http://127.0.0.1:38191".into()),
                Grant::Tcp("127.0.0.1:36379".into()),
                Grant::Server {
                    script: "fixture_server.py".into(),
                    port: 36379,
                },
                Grant::Process("test-program".into()),
                Grant::Device("virtual:100".into()),
                Grant::SystemMonitor("processes:500".into()),
            ]
        );
    }

    #[test]
    fn a_specification_without_grants_receives_nothing() {
        let declared = parse(r#"(test "none" (grants) (steps (await-ticks 1)))"#).unwrap();
        let absent = parse(r#"(test "none" (steps (await-ticks 1)))"#).unwrap();
        assert!(declared.grants.is_empty());
        assert_eq!(declared.grants, absent.grants);
    }

    /// A cancelled chooser is provisioned, not absent: it is the one directory
    /// outcome that produces no authority and is still not a failure.
    #[test]
    fn a_canceled_chooser_is_its_own_directory_provisioning() {
        let case = parse(r#"(test "c" (grants (directory canceled)) (steps (await-ticks 1)))"#)
            .expect("canceled chooser parses");
        assert_eq!(case.grants, vec![Grant::DirectoryCanceled]);
        assert_eq!(case.grants[0].name(), "directory");
        assert_eq!(case.grants[0].path(), None);
        // It occupies the directory slot, so a case cannot ask to be both
        // cancelled and granted.
        let duplicate = parse(
            r#"(test "c" (grants (directory canceled) (directory "fixture")) (steps (await-ticks 1)))"#,
        )
        .unwrap_err();
        assert!(duplicate.message.contains("duplicate directory grant"));
        // A path stays a path: only the bare atom means cancellation.
        assert_eq!(
            parse(r#"(test "c" (grants (directory "canceled")) (steps (await-ticks 1)))"#)
                .expect("quoted path parses")
                .grants,
            vec![Grant::Directory("canceled".into())]
        );
    }

    #[test]
    fn rejects_an_unknown_grant() {
        let error =
            parse(r#"(test "g" (grants (webcam full)) (steps (await-ticks 1)))"#).unwrap_err();
        assert_eq!(error.line, 1);
        assert!(error.message.contains("unsupported grant webcam"));
    }

    #[test]
    fn rejects_a_malformed_grant() {
        let error = parse("(test \"g\"\n  (grants\n    (directory))\n  (steps (await-ticks 1)))")
            .unwrap_err();
        assert_eq!(error.line, 3);
        assert!(error.message.contains("malformed directory grant"));
        let profile =
            parse(r#"(test "g" (grants (process sudo)) (steps (await-ticks 1)))"#).unwrap_err();
        assert!(profile.message.contains("local-shell or test-program"));
        let duplicate =
            parse(r#"(test "g" (grants (audio null) (audio null)) (steps (await-ticks 1)))"#)
                .unwrap_err();
        assert!(duplicate.message.contains("duplicate audio grant"));
    }

    #[test]
    fn rejects_a_grant_path_leaving_the_application_directory() {
        for path in ["../secrets", "/etc", "fixture/../../elsewhere", "./fixture"] {
            let source = format!(
                "(test \"g\"\n  (grants\n    (directory \"{path}\"))\n  (steps (await-ticks 1)))"
            );
            let error = parse(&source).unwrap_err();
            assert_eq!(error.line, 3, "{path}");
            assert!(
                error.message.contains("application directory"),
                "{path}: {}",
                error.message
            );
        }
    }

    #[test]
    fn rejects_unsupported_semantic_key() {
        let error = parse(r#"(test "keyboard" (steps (press-key Tab)))"#).unwrap_err();
        assert!(error.message.contains("Enter, Escape, or Space"));
    }

    #[test]
    fn parses_benchmark_policy() {
        let spec = parse(
            r#"(test "scale"
              (benchmark :warmups 2 :samples 7 :iterations 3 :scale 10000)
              (steps
                (mark-metrics)
                (click (role button :name "Build"))
                (expect-patch :kind replace :staged 60021 :removed 21)
                (expect-count (text-prefix "Row ") 10000)))"#,
        )
        .unwrap();
        assert_eq!(
            spec.benchmark,
            Some(Benchmark {
                warmups: 2,
                samples: 7,
                iterations: 3,
                scale: 10_000,
                initial_size: 0,
                change_size: 0,
            })
        );
    }

    #[test]
    fn parses_patch_evidence() {
        let spec = parse(
            r#"(test "patch"
              (benchmark :scale 1 :change-size 1)
              (steps (mark-metrics)
                (click (role button :name "Build"))
                (expect-patch :kind replace :staged 7 :removed 2)
                (expect-count (text "row") 1)))"#,
        )
        .unwrap();
        assert!(matches!(
            &spec.steps[2].command,
            Command::ExpectPatch(PatchExpectation { kind, staged: 7, removed: 2 }) if kind == "replace"
        ));
    }

    #[test]
    fn parses_canvas_drag_and_primitive_locator() {
        let spec = parse(
            r#"(test "canvas" (steps
            (drag (role canvas :name "Stage") -2 3 40 50)
            (expect-visible (role canvas-item :name "Card"))))"#,
        )
        .unwrap();
        assert!(
            matches!(&spec.steps[0].command, Command::Drag(Locator::CanvasName(name), -2, 3, 40, 50) if name == "Stage")
        );
        assert!(
            matches!(&spec.steps[1].command, Command::ExpectVisible(Locator::CanvasItemName(name)) if name == "Card")
        );
    }

    #[test]
    fn parses_file_owner_counters() {
        let spec = parse(r#"(test "files" (steps (expect-file-picks 1) (expect-file-lists 2) (expect-file-opens 3) (expect-file-reads 4)))"#).unwrap();
        assert!(matches!(spec.steps[0].command, Command::ExpectFilePicks(1)));
        assert!(matches!(spec.steps[3].command, Command::ExpectFileReads(4)));
    }

    #[test]
    fn benchmark_requires_one_mark() {
        let error =
            parse(r#"(test "bad" (benchmark :scale 1) (steps (expect-visible (text "x"))))"#)
                .unwrap_err();
        assert!(error.message.contains("exactly one"));
    }

    #[test]
    fn benchmark_requires_semantic_scale_verification() {
        let error = parse(
            r#"(test "bad"
              (benchmark :scale 1000)
              (steps (mark-metrics) (expect-count (text-prefix "Row ") 999)))"#,
        )
        .unwrap_err();
        assert!(error.message.contains("same count"));
    }

    #[test]
    fn bounds_benchmark_execution() {
        let error = parse(
            r#"(test "bad"
              (benchmark :warmups 1 :samples 100000 :iterations 2 :scale 1)
              (steps (mark-metrics) (expect-count (text "row") 1)))"#,
        )
        .unwrap_err();
        assert!(error.message.contains("lifecycle limit"));
    }

    #[test]
    fn bounds_source_size_and_nesting() {
        let oversized = " ".repeat(MAX_SOURCE_BYTES + 1);
        assert!(
            parse(&oversized)
                .unwrap_err()
                .message
                .contains("source limit")
        );

        let nested = format!(
            "{}x{}",
            "(".repeat(MAX_NESTING_DEPTH + 2),
            ")".repeat(MAX_NESTING_DEPTH + 2)
        );
        assert!(
            parse(&nested)
                .unwrap_err()
                .message
                .contains("nesting limit")
        );
    }

    #[test]
    fn rejects_window_scenarios_explicitly() {
        let error = parse(r#"(scenario "window" (steps))"#).unwrap_err();
        assert!(error.message.contains("must start with (test"));
    }

    #[test]
    fn await_count_waits_for_a_locator_on_either_runner() {
        let spec = parse(r#"(test "s" (steps (await-count (text "Ready") 3)))"#).unwrap();
        assert_eq!(spec.steps[0].command.kind(), "await-count");
        assert!(matches!(spec.steps[0].command, Command::AwaitCount(_, 3)));
        // Both runners wait; neither has to predict how many tasks that takes.
        assert!(check_runner(&spec, Runner::Semantic).is_ok());
        assert!(check_runner(&spec, Runner::Window).is_ok());
        assert!(parse(r#"(test "s" (steps (await-count (text "Ready"))))"#).is_err());
        assert!(parse(r#"(test "s" (steps (await-count (text "Ready") -1)))"#).is_err());
    }

    #[test]
    fn settle_defaults_and_accepts_keywords() {
        let spec = parse(r#"(test "s" (steps (settle)))"#).unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::Settle {
                frames: 2,
                timeout_ms: 2_000
            }
        );
        let spec = parse(r#"(test "s" (steps (settle :frames 4 :timeout-ms 500)))"#).unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::Settle {
                frames: 4,
                timeout_ms: 500
            }
        );
    }

    #[test]
    fn settle_rejects_malformed_keywords() {
        for (source, expected) in [
            (r#"(test "s" (steps (settle :frames)))"#, "requires a value"),
            (
                r#"(test "s" (steps (settle :frames 0)))"#,
                "must be between 1 and 60",
            ),
            (
                r#"(test "s" (steps (settle :frames 99)))"#,
                "must be between 1 and 60",
            ),
            (
                r#"(test "s" (steps (settle :frames x)))"#,
                "requires an integer",
            ),
            (
                r#"(test "s" (steps (settle :nope 1)))"#,
                "unsupported key :nope",
            ),
            (
                r#"(test "s" (steps (settle :frames 1 :frames 2)))"#,
                "duplicate key :frames",
            ),
            (
                r#"(test "s" (steps (settle 2)))"#,
                "expects :key value pairs",
            ),
        ] {
            let error = parse(source).unwrap_err();
            assert!(
                error.message.contains(expected),
                "{source}: expected {expected:?}, got {:?}",
                error.message
            );
        }
    }

    #[test]
    fn typing_and_chords_parse() {
        let spec =
            parse(r#"(test "s" (steps (type "hello") (key "cmd-a") (key "escape")))"#).unwrap();
        assert_eq!(spec.steps[0].command, Command::Type("hello".to_owned()));
        assert_eq!(spec.steps[1].command, Command::Key("cmd-a".to_owned()));
        assert_eq!(spec.steps[2].command, Command::Key("escape".to_owned()));
    }

    #[test]
    fn malformed_typing_and_chords_are_refused() {
        for (source, expected) in [
            (r#"(test "s" (steps (type "")))"#, "non-empty string"),
            (r#"(test "s" (steps (type x)))"#, "type requires a string"),
            (r#"(test "s" (steps (key "cmd-")))"#, "key requires a chord"),
            (
                r#"(test "s" (steps (key "nope-a")))"#,
                "key requires a chord",
            ),
            (r#"(test "s" (steps (key "")))"#, "key requires a chord"),
        ] {
            let error = parse(source).unwrap_err();
            assert!(
                error.message.contains(expected),
                "{source}: expected {expected:?}, got {:?}",
                error.message
            );
        }
    }

    /// A bare key with no modifier is a valid chord; GPUI parses it too.
    #[test]
    fn bare_keys_are_valid_chords() {
        for chord in ["escape", "enter", "tab", "a"] {
            let source = format!(r#"(test "s" (steps (key "{chord}")))"#);
            assert!(parse(&source).is_ok(), "{chord} should parse");
        }
    }

    #[test]
    fn capabilities_partition_the_vocabulary() {
        let semantic = parse(
            r#"(test "s" (steps (mark-metrics) (expect-patch :kind replace :staged 6 :removed 6)))"#,
        )
        .unwrap();
        for step in &semantic.steps {
            assert_eq!(step.command.capability(), Capability::Semantic);
        }
        let window = parse(r#"(test "s" (steps (settle)))"#).unwrap();
        assert_eq!(window.steps[0].command.capability(), Capability::Window);
        let both = parse(r#"(test "s" (steps (expect-visible (text "x"))))"#).unwrap();
        assert_eq!(both.steps[0].command.capability(), Capability::Both);
    }

    #[test]
    fn each_runner_refuses_the_other_runners_steps() {
        let windowed = parse(r#"(test "s" (steps (expect-visible (text "x")) (settle)))"#).unwrap();
        let message = check_runner(&windowed, Runner::Semantic).unwrap_err();
        assert!(
            message.contains("line 1: step `settle` is window-only"),
            "{message}"
        );
        assert!(message.contains("--host-run-window-spec"), "{message}");
        assert!(check_runner(&windowed, Runner::Window).is_ok());

        let measured = parse(r#"(test "s" (steps (mark-metrics)))"#).unwrap();
        let message = check_runner(&measured, Runner::Window).unwrap_err();
        assert!(
            message.contains("`mark-metrics` is semantic-only"),
            "{message}"
        );
        assert!(check_runner(&measured, Runner::Semantic).is_ok());
    }

    /// Driving the fixture clipboard is the only way to put an item into a
    /// clipboard-driven application, so a windowed case that cannot do it
    /// cannot photograph one. Both runners reach the same process-wide store.
    #[test]
    fn the_fixture_clipboard_can_be_driven_by_either_runner() {
        let spec = parse(
            r#"(test "s" (steps (clipboard-text "copied") (await-ticks 1) (expect-visible (text "copied"))))"#,
        )
        .unwrap();
        for step in &spec.steps {
            assert_eq!(step.command.capability(), Capability::Both);
        }
        assert!(check_runner(&spec, Runner::Window).is_ok());
        assert!(check_runner(&spec, Runner::Semantic).is_ok());
    }

    #[test]
    fn benchmark_clauses_are_semantic_only() {
        let spec = parse(
            r#"(test "s" (benchmark :warmups 1 :samples 1 :iterations 1 :scale 1 :initial-size 1 :change-size 1) (steps (mark-metrics) (expect-count (text "row") 1)))"#,
        )
        .unwrap();
        let message = check_runner(&spec, Runner::Window).unwrap_err();
        assert!(
            message.contains("benchmark clauses are semantic-only"),
            "{message}"
        );
    }

    #[test]
    fn screenshot_regions_take_three_shapes() {
        let spec = parse(
            r#"(test "s" (steps
                 (screenshot "whole")
                 (screenshot "one" :region (text "x"))
                 (screenshot "padded" :region (text "x") :pad 24)
                 (screenshot "boxed" :region (rect 0 0 640 96))))"#,
        )
        .unwrap();
        let expected = [
            Region::Window,
            Region::Locator(Locator::Text("x".to_owned())),
            Region::Locator(Locator::Text("x".to_owned())),
            Region::Rect {
                x: 0,
                y: 0,
                width: 640,
                height: 96,
            },
        ];
        for (step, region) in spec.steps.iter().zip(expected) {
            let Command::Screenshot(request) = &step.command else {
                panic!("expected a screenshot, got {:?}", step.command);
            };
            assert_eq!(request.region, region);
        }
        let Command::Screenshot(padded) = &spec.steps[2].command else {
            unreachable!()
        };
        assert_eq!(padded.pad, 24);
    }

    #[test]
    fn screenshot_names_are_constrained_to_file_stems() {
        for name in ["", "Has Capitals", "under_score", "a/b", &"x".repeat(49)] {
            let source = format!(r#"(test "s" (steps (screenshot "{name}")))"#);
            let error = parse(&source).unwrap_err();
            assert!(
                error.message.contains("screenshot names use lowercase"),
                "{name:?}: {}",
                error.message
            );
        }
        assert!(parse(r#"(test "s" (steps (screenshot "step-02-list")))"#).is_ok());
    }

    #[test]
    fn screenshot_rejects_malformed_regions_and_padding() {
        for (source, expected) in [
            (
                r#"(test "s" (steps (screenshot "a" :region (rect 0 0 10))))"#,
                "rect region requires x, y, width, and height",
            ),
            (
                r#"(test "s" (steps (screenshot "a" :region (rect 0 0 0 10))))"#,
                "non-zero width and height",
            ),
            (
                r#"(test "s" (steps (screenshot "a" :pad 999)))"#,
                "must be between 0 and 256",
            ),
            (
                r#"(test "s" (steps (screenshot "a" :nope 1)))"#,
                "unsupported key :nope",
            ),
            (r#"(test "s" (steps (screenshot)))"#, "invalid arguments"),
        ] {
            let error = parse(source).unwrap_err();
            assert!(
                error.message.contains(expected),
                "{source}: expected {expected:?}, got {:?}",
                error.message
            );
        }
    }

    /// A canvas primitive's rectangle is its canvas's, offset by the
    /// coordinates the owner drew it at, so it is a region like any other.
    #[test]
    fn screenshot_regions_reach_canvas_items() {
        let spec =
            parse(r#"(test "s" (steps (screenshot "a" :region (role canvas-item :name "dot"))))"#)
                .unwrap();
        assert_eq!(
            spec.steps[0].command,
            Command::Screenshot(Screenshot {
                name: "a".into(),
                region: Region::Locator(Locator::CanvasItemName("dot".into())),
                pad: 0,
            })
        );
    }

    /// The guard for the committed suite: every specification parses, and
    /// belongs to exactly one runner. Both kinds share a directory, so the file
    /// contents are the only thing that decides which runner takes it.
    #[test]
    fn resize_takes_a_bounded_logical_size() {
        let parsed = parse("(test \"t\" (steps (resize 900 600)))").expect("valid resize");
        assert!(matches!(
            parsed.steps[0].command,
            Command::Resize {
                width: 900,
                height: 600
            }
        ));
        assert!(matches!(
            parsed.steps[0].command.capability(),
            Capability::Window
        ));
        for bad in [
            "(test \"t\" (steps (resize 32 600)))",
            "(test \"t\" (steps (resize 900 9000)))",
            "(test \"t\" (steps (resize 900)))",
        ] {
            assert!(parse(bad).is_err(), "accepted {bad}");
        }
    }

    #[test]
    fn every_committed_spec_belongs_to_exactly_one_runner() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(Path::parent)
            .expect("workspace root");
        let mut semantic = 0;
        let mut window = 0;
        for group in ["examples", "benchmarks"] {
            let entries = match std::fs::read_dir(root.join(group)) {
                Ok(entries) => entries,
                Err(_) => continue,
            };
            for app in entries.filter_map(Result::ok) {
                let Ok(files) = std::fs::read_dir(app.path().join("specs")) else {
                    continue;
                };
                for file in files.filter_map(Result::ok) {
                    let path = file.path();
                    if path.extension().is_none_or(|ext| ext != "scm") {
                        continue;
                    }
                    let source = std::fs::read_to_string(&path).expect("read spec");
                    let spec = parse(&source)
                        .unwrap_or_else(|error| panic!("{}: {error}", path.display()));
                    match (
                        check_runner(&spec, Runner::Semantic),
                        check_runner(&spec, Runner::Window),
                    ) {
                        (Ok(()), Err(_)) => semantic += 1,
                        (Err(_), Ok(())) => window += 1,
                        (Ok(()), Ok(())) => semantic += 1,
                        (Err(first), Err(second)) => panic!(
                            "{}: no runner accepts this specification: {first} / {second}",
                            path.display()
                        ),
                    }
                }
            }
        }
        assert!(
            semantic > 100,
            "expected the committed semantic suite, found {semantic}"
        );
        assert!(window > 0, "expected committed window specifications");
    }
}
