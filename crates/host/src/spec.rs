use std::fmt;

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
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Step {
    pub line: usize,
    pub command: Command,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Command {
    Click(Locator),
    ExpectVisible(Locator),
    ExpectNotVisible(Locator),
    MarkMetrics,
}

impl Command {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Click(_) => "click",
            Self::ExpectVisible(_) => "expect-visible",
            Self::ExpectNotVisible(_) => "expect-not-visible",
            Self::MarkMetrics => "mark-metrics",
        }
    }

    pub fn is_operation(&self) -> bool {
        matches!(self, Self::Click(_))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Locator {
    Text(String),
    ButtonName(String),
}

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
    if let Some(_) = benchmark {
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

fn parse_step(node: &SExpr) -> Result<Step, ParseError> {
    let values = require_list(node, "step")?;
    let head = values
        .first()
        .and_then(SExpr::atom)
        .ok_or_else(|| error(node, "step requires a command name"))?;
    let command = match head {
        "click" if values.len() == 2 => Command::Click(parse_locator(&values[1])?),
        "expect-visible" if values.len() == 2 => Command::ExpectVisible(parse_locator(&values[1])?),
        "expect-not-visible" if values.len() == 2 => {
            Command::ExpectNotVisible(parse_locator(&values[1])?)
        }
        "mark-metrics" if values.len() == 1 => Command::MarkMetrics,
        "click" | "expect-visible" | "expect-not-visible" | "mark-metrics" => {
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
        Some("role") => Err(error(node, "only (role button :name \"...\") is supported")),
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
}

impl<'a> Parser<'a> {
    fn new(source: &'a str) -> Self {
        Self {
            bytes: source.as_bytes(),
            index: 0,
            line: 1,
        }
    }

    fn expr(&mut self) -> Result<SExpr, ParseError> {
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
                        _ => values.push(self.expr()?),
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
    fn parses_benchmark_policy() {
        let spec = parse(
            r#"(test "scale"
              (benchmark :warmups 2 :samples 7 :iterations 3 :scale 10000)
              (steps (mark-metrics) (click (role button :name "Build"))))"#,
        )
        .unwrap();
        assert_eq!(
            spec.benchmark,
            Some(Benchmark {
                warmups: 2,
                samples: 7,
                iterations: 3,
                scale: 10_000,
            })
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
    fn rejects_window_scenarios_explicitly() {
        let error = parse(r#"(scenario "window" (steps))"#).unwrap_err();
        assert!(error.message.contains("must start with (test"));
    }
}
