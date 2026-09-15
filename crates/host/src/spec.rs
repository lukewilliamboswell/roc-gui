use std::fmt;

use crate::bridge::ControlKey;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Spec {
    pub name: String,
    pub benchmark: Option<Benchmark>,
    pub steps: Vec<Step>,
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
        match (self, runner) {
            (Self::Both, _) => true,
            (Self::Semantic, Runner::Semantic) => true,
            (Self::Window, Runner::Window) => true,
            _ => false,
        }
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
            Self::Semantic => "the window runner runs one lifecycle and does not measure it",
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
    Drag(Locator, i32, i32, i32, i32),
    ReplaceText(Locator, String),
    Focus(Locator),
    PressKey(ControlKey),
    AwaitTask,
    ClipboardText(String),
    AwaitTicks(u32),
    ExpectSubscriptions(usize),
    ExpectTcpStreams(usize),
    ExpectProcesses(usize),
    ExpectClipboardCounters([u64; 4]),
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
    Settle { frames: u32, timeout_ms: u32 },
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
    Rect { x: u32, y: u32, width: u32, height: u32 },
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
            Self::Drag(..) => "drag",
            Self::ReplaceText(_, _) => "replace-text",
            Self::Focus(_) => "focus",
            Self::PressKey(_) => "press-key",
            Self::AwaitTask => "await-task",
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
            | Self::ExpectOnScreen(_)
            | Self::ExpectRenderedCount(_, _)
            | Self::ExpectBounds(_, _)
            | Self::Screenshot(_)
            | Self::Type(_)
            | Self::Key(_) => Capability::Window,
            // Shared with the semantic runner, and implemented by both.
            Self::Click(_)
            | Self::Focus(_)
            | Self::PressKey(_)
            | Self::AwaitTask
            | Self::ExpectVisible(_)
            | Self::ExpectFocused(_)
            | Self::ExpectNotVisible(_)
            | Self::ExpectCount(_, _) => Capability::Both,
            // Semantic-only because the window runner does not implement them.
            // They are honest claims, made by one runner rather than two; the
            // alternative of accepting a specification and then refusing a step
            // mid-run would report a failure that is about the harness rather
            // than about the application.
            Self::Drag(..)
            | Self::ReplaceText(_, _)
            | Self::ClipboardText(_)
            | Self::AwaitTicks(_)
            | Self::Submit(_)
            | Self::RevokeFileGrants
            | Self::ExpectCanvasPrimitives(_, _)
            | Self::ExpectValue(_, _)
            | Self::ExpectValueBytes(_, _)
            | Self::ExpectImageBytes(_, _)
            | Self::ExpectBefore(_, _)
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
            | Self::ExpectImageOwnerCounters(_) => Capability::Semantic,
        }
    }

    pub fn is_operation(&self) -> bool {
        matches!(
            self,
            Self::Click(_)
                | Self::Drag(..)
                | Self::ReplaceText(_, _)
                | Self::Focus(_)
                | Self::PressKey(_)
                | Self::AwaitTask
                | Self::ClipboardText(_)
                | Self::AwaitTicks(_)
                | Self::Submit(_)
                | Self::RevokeFileGrants
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

impl fmt::Display for Locator {
    /// Render a locator the way it is written in a specification, so a failure
    /// message quotes the author's own words back to them.
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (form, value) = match self {
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
    let mut steps = None;
    for section in &values[2..] {
        let list = require_list(section, "test section")?;
        match list.first().and_then(SExpr::atom) {
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
        steps,
    })
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
                format!("unsupported key {key} for {head}; expected {}", allowed.join(", ")),
            ));
        }
        if pairs.iter().any(|(seen, _)| *seen == key) {
            return Err(error(&rest[index], format!("duplicate key {key} for {head}")));
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

    fn u32_in(&self, key: &str, range: std::ops::RangeInclusive<u32>) -> Result<Option<u32>, ParseError> {
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
            let mut expected = [0u64; 4];
            for (index, value) in values[1..].iter().enumerate() {
                expected[index] = value
                    .atom()
                    .ok_or_else(|| error(value, "clipboard counters must be integers"))?
                    .parse()
                    .map_err(|_| {
                        error(value, "clipboard counters must be non-negative integers")
                    })?;
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
                    "patch kind must be mount, replace, or no_change",
                )
            })?;
            if !matches!(kind, "mount" | "replace" | "no_change") {
                return Err(error(
                    &values[2],
                    "patch kind must be mount, replace, or no_change",
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
        "mark-metrics" if values.len() == 1 => Command::MarkMetrics,
        "click"
        | "drag"
        | "replace-text"
        | "focus"
        | "press-key"
        | "await-task"
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
        | "expect-on-screen"
        | "expect-rendered-count"
        | "expect-bounds"
        | "screenshot"
        | "type"
        | "key" => {
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
            return Err(error(node, "rect region requires a non-zero width and height"));
        }
        return Ok(Region::Rect {
            x: numbers[0],
            y: numbers[1],
            width: numbers[2],
            height: numbers[3],
        });
    }
    let locator = parse_locator(node)?;
    // Only a canvas node's own rectangle is recorded, never its primitives, so
    // a canvas-item region would silently photograph the whole canvas.
    if matches!(
        locator,
        Locator::CanvasItemName(_) | Locator::CanvasItemPrefix(_)
    ) {
        return Err(error(
            node,
            "canvas items have no recorded bounds; screenshot the canvas instead",
        ));
    }
    Ok(Region::Locator(locator))
}

fn parse_locator(node: &SExpr) -> Result<Locator, ParseError> {
    let values = require_list(node, "locator")?;
    match values.first().and_then(SExpr::atom) {
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
            Command::ExpectClipboardCounters([1, 2, 3, 4])
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
            (r#"(test "s" (steps (settle :frames 0)))"#, "must be between 1 and 60"),
            (r#"(test "s" (steps (settle :frames 99)))"#, "must be between 1 and 60"),
            (r#"(test "s" (steps (settle :frames x)))"#, "requires an integer"),
            (r#"(test "s" (steps (settle :nope 1)))"#, "unsupported key :nope"),
            (
                r#"(test "s" (steps (settle :frames 1 :frames 2)))"#,
                "duplicate key :frames",
            ),
            (r#"(test "s" (steps (settle 2)))"#, "expects :key value pairs"),
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
        let spec = parse(r#"(test "s" (steps (type "hello") (key "cmd-a") (key "escape")))"#).unwrap();
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
            (r#"(test "s" (steps (key "nope-a")))"#, "key requires a chord"),
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
        assert!(message.contains("line 1: step `settle` is window-only"), "{message}");
        assert!(message.contains("--host-run-window-spec"), "{message}");
        assert!(check_runner(&windowed, Runner::Window).is_ok());

        let measured = parse(r#"(test "s" (steps (mark-metrics)))"#).unwrap();
        let message = check_runner(&measured, Runner::Window).unwrap_err();
        assert!(message.contains("`mark-metrics` is semantic-only"), "{message}");
        assert!(check_runner(&measured, Runner::Semantic).is_ok());
    }

    #[test]
    fn benchmark_clauses_are_semantic_only() {
        let spec = parse(
            r#"(test "s" (benchmark :warmups 1 :samples 1 :iterations 1 :scale 1 :initial-size 1 :change-size 1) (steps (mark-metrics) (expect-count (text "row") 1)))"#,
        )
        .unwrap();
        let message = check_runner(&spec, Runner::Window).unwrap_err();
        assert!(message.contains("benchmark clauses are semantic-only"), "{message}");
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

    /// Only a canvas node's own rectangle is recorded, so a canvas-item region
    /// would silently photograph the whole canvas.
    #[test]
    fn screenshot_refuses_canvas_item_regions() {
        let error = parse(
            r#"(test "s" (steps (screenshot "a" :region (role canvas-item :name "dot"))))"#,
        )
        .unwrap_err();
        assert!(
            error.message.contains("canvas items have no recorded bounds"),
            "{}",
            error.message
        );
    }

    /// The guard for the committed suite: every specification parses, and
    /// belongs to exactly one runner. Both kinds share a directory, so the file
    /// contents are the only thing that decides which runner takes it.
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
