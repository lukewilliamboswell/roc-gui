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
    ExpectDeviceConnections(usize),
    ExpectDeviceTransactions(usize),
    ExpectAudioCounters([u64; 9]),
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
            Self::ExpectDeviceConnections(_) => "expect-device-connections",
            Self::ExpectDeviceTransactions(_) => "expect-device-transactions",
            Self::ExpectAudioCounters(_) => "expect-audio-counters",
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
        | "expect-device-connections"
        | "expect-device-transactions"
        | "expect-audio-counters"
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
        | "mark-metrics" => {
            return Err(error(node, format!("invalid arguments for {head}")));
        }
        _ => return Err(error(node, format!("unsupported step {head}"))),
    };
    Ok(Step {
        line: node.line(),
        command,
    })
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

#[cfg(test)]
mod tests {
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
}
