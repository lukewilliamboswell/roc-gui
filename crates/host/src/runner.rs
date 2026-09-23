use crate::{
    SUBMIT_EVENT_BIT, await_task_completion,
    bridge::{
        ApplyFacts, ButtonRole, CanvasPrimitive, CanvasPrimitiveKind, ControlKey, MountedGraph,
        NodeKind, Patch,
    },
    clear_bridge, complete, dispatch,
    observatory::{self, Cycle, StepResult},
    roc_platform_abi::roc_gui_init,
    spec::{Command, Locator, Spec},
    take_patch, task_counts,
};
use std::time::Instant;

fn counter_pattern<const N: usize>(
    expected: &[Option<u64>; N],
    observed: [u64; N],
) -> (bool, (u64, u64)) {
    expected
        .iter()
        .zip(observed)
        .fold((true, (0, 0)), |(matches, totals), (expected, observed)| {
            let Some(expected) = expected else {
                return (matches, totals);
            };
            (
                matches && *expected == observed,
                (totals.0 + expected, totals.1 + observed),
            )
        })
}

/// Apply the production graph transaction before publishing its Roc session.
fn apply_transaction(graph: &mut MountedGraph, patch: Patch) -> Result<ApplyFacts, String> {
    match graph.apply_measured(patch) {
        Ok(applied) => {
            crate::accept_transaction(graph, &applied);
            Ok(applied.facts)
        }
        Err(error) => {
            crate::reject_transaction();
            Err(error)
        }
    }
}

/// Both runners read the same completed owner observation, never reconstruct it.
pub(crate) fn component_work_claim(
    expected: &[Option<u64>; observatory::COMPONENT_WORK_NAMES.len()],
) -> (Result<(), String>, Option<observatory::ComponentWork>) {
    let observed = observatory::last_component_work();
    let Some(work) = observed else {
        return (
            Err("component work is unavailable: no production turn has committed".into()),
            None,
        );
    };
    // Every differing count at once, so one run tells the whole story.
    let differences = expected
        .iter()
        .enumerate()
        .filter_map(|(index, expected)| {
            expected
                .filter(|expected| *expected != work.0[index])
                .map(|expected| {
                    format!(
                        "expected component {} count {expected}, observed {}",
                        observatory::COMPONENT_WORK_NAMES[index],
                        work.0[index]
                    )
                })
        })
        .collect::<Vec<_>>();
    if differences.is_empty() {
        (Ok(()), observed)
    } else {
        (Err(differences.join("; ")), observed)
    }
}

/// The one primitive a canvas-item locator names, and the canvas that owns it.
///
/// `matches` answers with the canvas node for these locators, because that is
/// the node a click is dispatched to. A photograph wants the shape itself,
/// which only the owning canvas's primitive list holds. `None` unless exactly
/// one primitive matches, so a prefix naming a family fails the same way an
/// ambiguous locator fails everywhere else.
pub(crate) fn canvas_item<'a>(
    graph: &'a MountedGraph,
    locator: &Locator,
) -> Option<(u64, &'a CanvasPrimitive)> {
    let candidates: std::collections::HashSet<_> = matches(graph, locator).into_iter().collect();
    let matching = |item: &CanvasPrimitive| match locator.target() {
        Locator::CanvasItemName(name) => item.label == *name,
        Locator::CanvasItemPrefix(prefix) => item.label.starts_with(prefix),
        _ => false,
    };
    let mut found = graph
        .nodes_preorder()
        .into_iter()
        .filter(|node| candidates.contains(&node.id))
        .flat_map(|node| {
            let primitives = match &node.kind {
                NodeKind::Canvas { primitives, .. } => primitives.as_slice(),
                _ => &[][..],
            };
            primitives
                .iter()
                .filter(|item| matching(item))
                .map(move |item| (node.id, item))
        });
    let first = found.next()?;
    found.next().is_none().then_some(first)
}

/// A claim answered entirely from the mounted graph, and its count evidence.
///
/// These claims are true or false of the same graph on either runner, so they
/// belong to neither. Keeping one implementation is what lets one window
/// specification assert a semantic truth and photograph it in the same run,
/// without the two runners drifting into two slightly different meanings of the
/// same word. The message carries no line number: the caller is what knows
/// where the step was written.
pub(crate) fn graph_claim(
    graph: &MountedGraph,
    command: &Command,
) -> Option<(Result<(), String>, Option<(u64, u64)>)> {
    /// The single node a locator names, or how many it named instead.
    fn only(graph: &MountedGraph, locator: &Locator) -> Result<u64, usize> {
        let found = matches(graph, locator);
        if found.len() == 1 {
            Ok(found[0])
        } else {
            Err(found.len())
        }
    }

    Some(match command {
        Command::ExpectBackground(locator, expected) => {
            let actual = only(graph, locator)
                .map_err(|count| {
                    format!("expect-background locator matched {count} nodes; expected exactly one")
                })
                .and_then(|id| match graph.node(id).map(|node| &node.kind) {
                    Some(
                        NodeKind::Button { style, .. }
                        | NodeKind::Checkbox { style, .. }
                        | NodeKind::Textarea { style, .. }
                        | NodeKind::TextInput { style, .. }
                        | NodeKind::Canvas { style, .. }
                        | NodeKind::Image { style, .. }
                        | NodeKind::Column { style, .. }
                        | NodeKind::KeyedColumn { style, .. }
                        | NodeKind::Dialog { style, .. }
                        | NodeKind::Popover { style, .. }
                        | NodeKind::Panel { style, .. }
                        | NodeKind::Row { style, .. }
                        | NodeKind::Scroll { style, .. }
                        | NodeKind::VirtualList { style, .. },
                    ) => style
                        .bg
                        .map(crate::Paint::resolve)
                        .ok_or_else(|| "explicit background is unavailable".to_owned()),
                    _ => Err("locator has no application background".to_owned()),
                });
            (
                actual.and_then(|actual| {
                    if actual == *expected {
                        Ok(())
                    } else {
                        Err(format!(
                            "expected background 0x{expected:06x}; observed 0x{actual:06x}"
                        ))
                    }
                }),
                None,
            )
        }

        Command::ExpectKeyboardCounters(expected) => {
            let observed = graph.keyboard_counters().as_array();
            (
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "expected keyboard counters offered/matched/compared/focused {expected:?}; observed {observed:?}"
                    ))
                },
                None,
            )
        }

        Command::ExpectPopoverCounters(expected) => {
            let observed = graph.popover_counters().as_array();
            (
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "expected popover counters opened/closed/dismissed {expected:?}; observed {observed:?}"
                    ))
                },
                None,
            )
        }

        Command::ExpectCanvasPrimitives(locator, expected) => {
            let actual = match only(graph, locator).ok().and_then(|id| graph.node(id)) {
                Some(node) => match &node.kind {
                    NodeKind::Canvas { primitives, .. } => primitives.len(),
                    _ => 0,
                },
                None => 0,
            };
            (
                if actual == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "expected canvas owner to report {expected} primitives, but it reported {actual}"
                    ))
                },
                Some((*expected as u64, actual as u64)),
            )
        }
        // A canvas text primitive's value is the line it sets.
        Command::ExpectValue(locator, expected)
            if matches!(
                locator.target(),
                Locator::CanvasItemName(_) | Locator::CanvasItemPrefix(_)
            ) =>
        {
            (
                match canvas_item(graph, locator) {
                    None => Err(
                        "expect-value canvas-item locator must match exactly one primitive"
                            .to_owned(),
                    ),
                    Some((_, item)) if item.kind != CanvasPrimitiveKind::Text => {
                        Err("expect-value on a canvas item requires a text primitive".to_owned())
                    }
                    Some((_, item)) if item.text == *expected => Ok(()),
                    // Application text never enters a diagnostic.
                    Some(_) => Err("canvas text differed".to_owned()),
                },
                None,
            )
        }
        // A divider's value is the size it carries, or `collapsed`.
        Command::ExpectValue(locator, expected)
            if matches!(locator.target(), Locator::SeparatorName(_)) =>
        {
            (
                match only(graph, locator)
                    .map(|id| graph.node(id).and_then(|node| node.kind.splitter_value()))
                {
                    Err(count) => Err(format!(
                        "expect-value locator matched {count} nodes; expected exactly one"
                    )),
                    Ok(None) => Err("expect-value on a separator requires a divider".to_owned()),
                    Ok(Some(value)) => {
                        let shown = if value.collapsed {
                            "collapsed".to_owned()
                        } else {
                            value.size.to_string()
                        };
                        if shown == *expected {
                            Ok(())
                        } else {
                            Err(format!(
                                "expected divider value {expected}; observed {shown}"
                            ))
                        }
                    }
                },
                None,
            )
        }
        Command::ExpectSelected(locator, wanted) => (
            match only(graph, locator).map(|id| graph.node(id).map(|node| &node.kind)) {
                Err(count) => Err(format!(
                    "{} locator matched {count} nodes; expected exactly one",
                    command.kind()
                )),
                Ok(Some(NodeKind::Button {
                    role: ButtonRole::Tab { selected },
                    ..
                })) => {
                    if selected == wanted {
                        Ok(())
                    } else if *wanted {
                        Err("the tab is not selected".to_owned())
                    } else {
                        Err("the tab is selected".to_owned())
                    }
                }
                Ok(_) => Err(format!("{} requires a tab", command.kind())),
            },
            None,
        ),
        Command::ExpectValue(locator, expected) => (
            match only(graph, locator) {
                Err(count) => Err(format!(
                    "expect-value locator matched {count} nodes; expected exactly one"
                )),
                Ok(id) => {
                    if matches!(graph.node(id).map(|node| &node.kind), Some(NodeKind::Textarea { value, .. } | NodeKind::TextInput { value, .. }) if value == expected)
                    {
                        Ok(())
                    } else {
                        Err("controlled input value differed".to_owned())
                    }
                }
            },
            None,
        ),
        Command::ExpectValueBytes(locator, expected) => {
            let actual = match only(graph, locator) {
                Err(count) => Err(format!(
                    "expect-value-bytes locator matched {count} nodes; expected exactly one"
                )),
                Ok(id) => match graph.node(id).map(|node| &node.kind) {
                    Some(NodeKind::Textarea { value, .. } | NodeKind::TextInput { value, .. }) => {
                        Ok(value.len())
                    }
                    _ => Err("expect-value-bytes requires a controlled input".to_owned()),
                },
            };
            match actual {
                Ok(actual) => (
                    if actual == *expected {
                        Ok(())
                    } else {
                        Err(format!(
                            "expected controlled input value to contain {expected} bytes; observed {actual}"
                        ))
                    },
                    Some((*expected as u64, actual as u64)),
                ),
                Err(message) => (Err(message), None),
            }
        }
        Command::ExpectImageBytes(locator, expected) => {
            let found = only(graph, locator);
            let actual = match found.ok().and_then(|id| graph.node(id)) {
                Some(node) => match &node.kind {
                    NodeKind::Image { bytes, .. } => bytes.len(),
                    _ => 0,
                },
                None => 0,
            };
            (
                if found.is_ok() && actual == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "expected image source to contain {expected} bytes; observed {actual}"
                    ))
                },
                Some((*expected as u64, actual as u64)),
            )
        }
        Command::ExpectRows(locator, expected) => {
            let observed = only(graph, locator)
                .map_err(|count| {
                    format!("expect-rows locator matched {count} nodes; expected exactly one")
                })
                .and_then(|id| {
                    let node = graph.node(id).expect("matched node is mounted");
                    match &node.kind {
                        NodeKind::VirtualList { rows, .. } => {
                            let mounted = node.children.len() as u64;
                            Ok(match rows {
                                Some(rows) => (rows.count, rows.first, mounted),
                                None => (mounted, 0, mounted),
                            })
                        }
                        _ => Err("expect-rows requires a virtual list".to_owned()),
                    }
                });
            match observed {
                Err(message) => (Err(message), None),
                Ok((count, first, mounted)) => {
                    let mut differences = Vec::new();
                    for (name, wanted, actual) in [
                        ("rows", expected.count, count),
                        ("first mounted row", expected.first, first),
                        ("mounted rows", expected.mounted, mounted),
                    ] {
                        if let Some(wanted) = wanted
                            && wanted != actual
                        {
                            differences
                                .push(format!("expected {wanted} {name}; observed {actual}"));
                        }
                    }
                    (
                        if differences.is_empty() {
                            Ok(())
                        } else {
                            Err(differences.join("; "))
                        },
                        expected.count.map(|wanted| (wanted, count)),
                    )
                }
            }
        }
        Command::ExpectBefore(first, second) => {
            let ordered = graph.nodes_preorder();
            let position = |id| ordered.iter().position(|node| node.id == id);
            (
                match (only(graph, first), only(graph, second)) {
                    (Ok(first), Ok(second)) if position(first) < position(second) => Ok(()),
                    (Ok(_), Ok(_)) => Err("expected first locator before second".to_owned()),
                    (first, second) => Err(format!(
                        "expect-before locators matched {} and {} nodes; expected one each",
                        first.map_or_else(|count| count, |_| 1),
                        second.map_or_else(|count| count, |_| 1),
                    )),
                },
                None,
            )
        }
        _ => return None,
    })
}

/// Resolve a locator against the mounted graph.
///
/// Shared with the window runner so both resolve locators identically rather
/// than keeping two implementations in step by hand.
pub(crate) fn matches(graph: &MountedGraph, locator: &Locator) -> Vec<u64> {
    if let Locator::Within(ancestor, target) = locator {
        // Canvas primitives are semantic leaves. Their event address is their
        // canvas, but that does not make a primitive a scope for its siblings.
        if matches!(
            ancestor.target(),
            Locator::CanvasItemName(_) | Locator::CanvasItemPrefix(_)
        ) {
            return vec![];
        }
        let ancestors: std::collections::HashSet<_> =
            matches(graph, ancestor).into_iter().collect();
        let primitive_target = matches!(
            target.target(),
            Locator::CanvasItemName(_) | Locator::CanvasItemPrefix(_)
        );
        return matches(graph, target)
            .into_iter()
            .filter(|id| {
                // A node is not its own descendant. A primitive's shared
                // event address names its semantic parent, the canvas.
                let mut next = if primitive_target {
                    Some(*id)
                } else {
                    graph.parent(*id).map(|(parent, _)| parent)
                };
                while let Some(parent) = next {
                    if ancestors.contains(&parent) {
                        return true;
                    }
                    next = graph.parent(parent).map(|(parent, _)| parent);
                }
                false
            })
            .collect();
    }
    if let Locator::CanvasItemPrefix(prefix) = locator {
        return graph
            .presented_preorder()
            .into_iter()
            .flat_map(|node| match &node.kind {
                NodeKind::Canvas { primitives, .. } => primitives
                    .iter()
                    .filter(|item| item.label.starts_with(prefix))
                    .map(|_| node.id)
                    .collect::<Vec<_>>(),
                _ => vec![],
            })
            .collect();
    }
    graph
        .presented_preorder()
        .into_iter()
        .filter_map(|node| match (locator, &node.kind) {
            (
                Locator::Text(expected),
                NodeKind::Text(actual) | NodeKind::StyledText { value: actual, .. },
            ) if expected == actual => Some(node.id),
            (
                Locator::TextPrefix(expected),
                NodeKind::Text(actual) | NodeKind::StyledText { value: actual, .. },
            ) if actual.starts_with(expected) => Some(node.id),
            (
                Locator::ButtonName(expected),
                NodeKind::Button {
                    label,
                    role: ButtonRole::Button,
                    ..
                },
            ) if expected == label => Some(node.id),
            (
                Locator::ButtonPrefix(expected),
                NodeKind::Button {
                    label,
                    role: ButtonRole::Button,
                    ..
                },
            ) if label.starts_with(expected) => Some(node.id),
            (
                Locator::TabName(expected),
                NodeKind::Button {
                    label,
                    role: ButtonRole::Tab { .. },
                    ..
                },
            ) if expected == label => Some(node.id),
            (Locator::SeparatorName(expected), NodeKind::Split { label, .. })
                if expected == label =>
            {
                Some(node.id)
            }
            (Locator::CheckboxName(expected), NodeKind::Checkbox { label, .. })
                if expected == label =>
            {
                Some(node.id)
            }
            (Locator::CheckboxPrefix(expected), NodeKind::Checkbox { label, .. })
                if label.starts_with(expected) =>
            {
                Some(node.id)
            }
            (Locator::ColumnName(expected), NodeKind::Column { label, .. })
            | (Locator::ColumnName(expected), NodeKind::KeyedColumn { label, .. })
                if !label.is_empty() && expected == label =>
            {
                Some(node.id)
            }
            (Locator::DialogName(expected), NodeKind::Dialog { label, .. })
                if expected == label =>
            {
                Some(node.id)
            }
            (Locator::Shortcut(expected), NodeKind::Popover { shortcuts, .. })
                if shortcuts.iter().any(|shortcut| &shortcut.keys == expected) =>
            {
                Some(node.id)
            }
            // A tooltip is its presenting surface; a closed one is not there.
            (Locator::TooltipName(expected), NodeKind::Popover { label, .. })
                if expected == label && graph.popover_open(node.id) =>
            {
                Some(node.id)
            }
            (Locator::PanelName(expected), NodeKind::Panel { label, .. })
                if !label.is_empty() && expected == label =>
            {
                Some(node.id)
            }
            (Locator::RowName(expected), NodeKind::Row { label, .. })
                if !label.is_empty() && expected == label =>
            {
                Some(node.id)
            }
            (Locator::ScrollName(expected), NodeKind::Scroll { name, .. }) if expected == name => {
                Some(node.id)
            }
            (Locator::TextInputName(expected), NodeKind::TextInput { label, .. })
                if expected == label =>
            {
                Some(node.id)
            }
            (Locator::VirtualListName(expected), NodeKind::VirtualList { name, .. })
                if expected == name =>
            {
                Some(node.id)
            }
            (Locator::TextareaName(expected), NodeKind::Textarea { label, .. })
                if expected == label =>
            {
                Some(node.id)
            }
            (Locator::ImageName(expected), NodeKind::Image { label, .. }) if expected == label => {
                Some(node.id)
            }
            (Locator::CanvasName(expected), NodeKind::Canvas { label, .. })
                if expected == label =>
            {
                Some(node.id)
            }
            (Locator::CanvasItemName(expected), NodeKind::Canvas { primitives, .. })
                if primitives.iter().any(|item| item.label == *expected) =>
            {
                Some(node.id)
            }
            (Locator::CanvasItemPrefix(_), _) => None,
            _ => None,
        })
        .collect()
}

/// Evidence a resource claim contributes to its observatory step record.
///
/// The window runner discards this: it writes a report of step outcomes, not a
/// capture. It is returned rather than recorded here so that the reading of the
/// owner and the recording of it stay in one place each.
#[derive(Default)]
pub(crate) struct CounterEvidence {
    pub audio: Option<([u64; 9], [u64; 9])>,
    pub clipboard: Option<([Option<u64>; 4], [u64; 4])>,
    pub sqlite: Option<([u64; 3], [u64; 3])>,
    pub http: Option<([u64; 4], [u64; 4])>,
    pub tcp: Option<([u64; 5], [u64; 5])>,
}

/// A claim answered from a process-global resource owner, and its evidence.
///
/// Like [`graph_claim`], these are true or false of the same host on either
/// runner: there is one files registry, one clipboard, one audio device table,
/// and a window run reaches them through this function rather than through a
/// second reading of the same statics. File operation counts are differences
/// from the baseline the caller's lifecycle began at; every other reading is
/// absolute. The message carries no line number: the caller is what knows where
/// the step was written.
pub(crate) fn resource_claim(
    command: &Command,
    file_baseline: [u64; 4],
) -> Option<(Result<(), String>, Option<(u64, u64)>, CounterEvidence)> {
    /// An exact owner reading, reported as the whole array on either side.
    fn exact<const N: usize>(
        name: &str,
        expected: &[u64; N],
        observed: [u64; N],
    ) -> (Result<(), String>, Option<(u64, u64)>) {
        let counts = Some((expected.iter().sum(), observed.iter().sum()));
        if observed == *expected {
            (Ok(()), counts)
        } else {
            (
                Err(format!(
                    "expected {name} {expected:?}, observed {observed:?}"
                )),
                counts,
            )
        }
    }

    /// A single owner reading named in the singular by the step itself.
    fn single(
        noun: &str,
        expected: u64,
        observed: u64,
    ) -> (Result<(), String>, Option<(u64, u64)>) {
        let counts = Some((expected, observed));
        if expected == observed {
            (Ok(()), counts)
        } else {
            (
                Err(format!("expected {expected} {noun}, observed {observed}")),
                counts,
            )
        }
    }

    let mut evidence = CounterEvidence::default();
    let (result, counts) = match command {
        Command::ExpectSubscriptions(expected) => {
            // Historically the only counter assertion with no count evidence;
            // left that way so a capture does not gain a column here.
            let active = crate::timers::active_count();
            (
                if active == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "expected {expected} active subscriptions, observed {active}"
                    ))
                },
                None,
            )
        }
        Command::ExpectTcpStreams(expected) => single(
            "active TCP streams",
            *expected as u64,
            crate::tcp::active_count() as u64,
        ),
        Command::ExpectProcesses(expected) => {
            let active = crate::process::active_count();
            let (spawned, _, _, canceled) = crate::process::counters();
            if canceled > spawned {
                (
                    Err("process lifecycle counters violated ownership invariants".to_owned()),
                    None,
                )
            } else {
                single("active PTY processes", *expected as u64, active as u64)
            }
        }
        Command::ExpectClipboardCounters(expected) => {
            let (operations, handles) = crate::clipboard::counters();
            let observed = [handles as u64, operations[0], operations[1], operations[2]];
            let (matches, totals) = counter_pattern(expected, observed);
            evidence.clipboard = Some((*expected, observed));
            (
                if matches {
                    Ok(())
                } else {
                    Err(format!(
                        "expected clipboard counter pattern {expected:?}, observed {observed:?}"
                    ))
                },
                Some(totals),
            )
        }
        Command::ExpectSqliteCounters(expected) => {
            let (operations, connections) = crate::sqlite::counters();
            let observed = [connections as u64, operations[0], operations[1]];
            evidence.sqlite = Some((*expected, observed));
            exact("SQLite counters", expected, observed)
        }
        Command::ExpectHttpCounters(expected) => {
            let (operations, clients) = crate::http::counters();
            let observed = [clients as u64, operations[0], operations[1], operations[2]];
            evidence.http = Some((*expected, observed));
            exact("HTTP counters", expected, observed)
        }
        Command::ExpectTcpCounters(expected) => {
            let (operations, streams) = crate::tcp::counters();
            let observed = [
                streams as u64,
                operations[0],
                operations[1],
                operations[2],
                operations[3],
            ];
            evidence.tcp = Some((*expected, observed));
            exact("TCP counters", expected, observed)
        }
        Command::ExpectDeviceConnections(expected) => {
            let active = crate::device::active_count();
            let (_, connected, _, closed) = crate::device::counters();
            if closed > connected {
                (
                    Err("device lifecycle counters violated ownership invariants".to_owned()),
                    None,
                )
            } else {
                single("active device connections", *expected as u64, active as u64)
            }
        }
        Command::ExpectDeviceTransactions(expected) => {
            let (_, _, transactions, _) = crate::device::counters();
            single("device transactions", *expected as u64, transactions)
        }
        Command::ExpectSystemSamplers(expected) => {
            let active = crate::system_monitor::active_count();
            let (acquired, _, closed) = crate::system_monitor::counters();
            if closed > acquired {
                (
                    Err(
                        "system sampler lifecycle counters violated ownership invariants"
                            .to_owned(),
                    ),
                    None,
                )
            } else {
                single("active system samplers", *expected as u64, active as u64)
            }
        }
        Command::ExpectSystemSamples(expected) => {
            let (_, sampled, _) = crate::system_monitor::counters();
            single("system samples", *expected as u64, sampled)
        }
        Command::ExpectAudioCounters(expected) => {
            let (operations, outputs, tracks) = crate::audio::counters();
            let observed = [
                outputs as u64,
                tracks as u64,
                operations[0],
                operations[1],
                operations[2],
                operations[3],
                operations[4],
                operations[5],
                operations[6],
            ];
            evidence.audio = Some((*expected, observed));
            exact("audio counters", expected, observed)
        }
        Command::ExpectFilePicks(expected) => single(
            "file picks",
            *expected,
            crate::files::operation_counts()[0] - file_baseline[0],
        ),
        Command::ExpectFileLists(expected) => single(
            "file lists",
            *expected,
            crate::files::operation_counts()[1] - file_baseline[1],
        ),
        Command::ExpectFileOpens(expected) => single(
            "file opens",
            *expected,
            crate::files::operation_counts()[2] - file_baseline[2],
        ),
        Command::ExpectFileReads(expected) => single(
            "file reads",
            *expected,
            crate::files::operation_counts()[3] - file_baseline[3],
        ),
        Command::ExpectFileSelectionCounters(expected) => exact(
            "file selection counters",
            expected,
            crate::files::selection_counts(),
        ),
        Command::ExpectFileLifecycleCounters(expected) => exact(
            "file lifecycle counters",
            expected,
            crate::files::lifecycle_counts(),
        ),
        Command::ExpectFileAccess(expected) => {
            let access = crate::files::access_snapshot();
            exact(
                "file access",
                expected,
                [
                    access.portal_session_read,
                    access.provisioned_session_read,
                    access.revoked,
                ],
            )
        }
        Command::ExpectTaskCounters(expected) => {
            let observed = crate::tasks::counters();
            let constrained = expected
                .iter()
                .zip(observed)
                .all(|(expected, observed)| expected.is_none_or(|value| value == observed));
            let counts = Some((
                expected.iter().flatten().sum(),
                expected
                    .iter()
                    .zip(observed)
                    .filter(|(expected, _)| expected.is_some())
                    .map(|(_, observed)| observed)
                    .sum(),
            ));
            let shown =
                |value: &Option<u64>| value.map_or("_".to_string(), |value| value.to_string());
            (
                if constrained {
                    Ok(())
                } else {
                    Err(format!(
                        "expected task counters [{}], observed {observed:?}",
                        expected.iter().map(shown).collect::<Vec<_>>().join(", ")
                    ))
                },
                counts,
            )
        }
        Command::ExpectWatchCounters(expected) => {
            let observed = crate::watch::counters();
            let constrained = expected
                .iter()
                .zip(observed)
                .all(|(expected, observed)| expected.is_none_or(|value| value == observed));
            let counts = Some((
                expected.iter().flatten().sum(),
                expected
                    .iter()
                    .zip(observed)
                    .filter(|(expected, _)| expected.is_some())
                    .map(|(_, observed)| observed)
                    .sum(),
            ));
            let shown =
                |value: &Option<u64>| value.map_or("_".to_string(), |value| value.to_string());
            (
                if constrained {
                    Ok(())
                } else {
                    Err(format!(
                        "expected watch counters [{}], observed {observed:?}",
                        expected.iter().map(shown).collect::<Vec<_>>().join(", ")
                    ))
                },
                counts,
            )
        }
        Command::ExpectDocumentCounters(expected) => {
            let [picks, chosen, canceled, refused, reads] = crate::document::counters();
            exact(
                "document counters",
                expected,
                [
                    picks,
                    chosen,
                    canceled,
                    refused,
                    reads,
                    crate::document::live() as u64,
                ],
            )
        }
        Command::ExpectImageOwnerCounters(expected) => exact(
            "image owner counters",
            expected,
            crate::image_data::counters(),
        ),
        Command::ExpectAssetCounters(expected) => {
            exact("asset counters", expected, crate::assets::counters())
        }
        Command::ExpectHashCounters(expected) => {
            exact("hash counters", expected, crate::files::hash_counters())
        }
        // The whole list, in order, compared as a list. A claim that counted
        // grants instead would pass for an application holding entirely
        // different authority than the one the specification names.
        Command::ExpectGrants(expected) => {
            let observed: Vec<String> = crate::grant::enumerate()
                .iter()
                .map(crate::grant::Grant::describe)
                .collect();
            let counts = Some((expected.len() as u64, observed.len() as u64));
            if observed == *expected {
                (Ok(()), counts)
            } else {
                (
                    Err(format!(
                        "expected grants {expected:?}, observed {observed:?}"
                    )),
                    counts,
                )
            }
        }
        Command::ExpectGrantCounters(expected) => {
            exact("grant counters", expected, crate::grant::counters())
        }
        _ => return None,
    };
    Some((result, counts, evidence))
}

pub fn run(spec: &Spec) -> Result<(), String> {
    let mut next_run = 1i64;
    if let Some(benchmark) = spec.benchmark {
        for warmup in 0..benchmark.warmups {
            run_lifecycle(spec, next_run, "warmup", None, warmup)?;
            next_run += 1;
        }
        for sample in 0..benchmark.samples {
            for iteration in 0..benchmark.iterations {
                run_lifecycle(spec, next_run, "sample", Some(sample), iteration)?;
                next_run += 1;
            }
        }
    } else {
        run_lifecycle(spec, next_run, "test", None, 0)?;
    }
    Ok(())
}

fn run_lifecycle(
    spec: &Spec,
    run_id: i64,
    phase: &'static str,
    sample: Option<u32>,
    iteration: u32,
) -> Result<(), String> {
    let started_ns = observatory::now_ns();
    observatory::run_start(run_id, phase, sample, iteration, started_ns);
    let result = run_lifecycle_inner(spec, run_id);
    clear_bridge();
    let (outcome, diagnostic) = match &result {
        Ok(()) => ("pass", None),
        Err(message) => ("fail", Some(message.clone())),
    };
    observatory::run_end(run_id, outcome, observatory::now_ns(), diagnostic);
    result
}

fn run_lifecycle_inner(spec: &Spec, run_id: i64) -> Result<(), String> {
    let file_counter_baseline = crate::files::operation_counts();
    let mut graph = MountedGraph::default();
    let cycle_started = Instant::now();
    observatory::reset_roc_work();
    observatory::begin_component_work();
    let roc_started = Instant::now();
    unsafe { roc_gui_init() };
    let roc_ns = elapsed_ns(roc_started);
    let (roc_work, roc_work_valid) = observatory::take_roc_work();
    let patch = take_patch();
    let facts = apply_transaction(&mut graph, patch)?;
    observatory::cycle(make_cycle(
        run_id,
        0,
        None,
        "initialization",
        "init",
        None,
        cycle_started,
        roc_ns,
        roc_work,
        &facts,
        roc_work_valid,
    ));

    let mut marked = spec.benchmark.is_none();
    let mut cycle_ordinal = 1u64;
    let mut last_patch: Option<ApplyFacts> = None;
    let mut focused: Option<u64> = None;
    // The canvas an unpressed pointer is over and the last point delivered.
    // Named by its label, which survives the patch a hover itself causes; a
    // node id does not.
    let mut hovering: Option<(String, (i32, i32))> = None;
    let mut timer_fired_seen = crate::timers::fired_count();
    let mut dialog_return_focus: Option<(u8, String)> = None;
    for (ordinal, step) in spec.steps.iter().enumerate() {
        // The control focused before the step, by the identity that survives
        // a rebuild renumbering it.
        let focus_before = focused
            .and_then(|id| graph.node(id))
            .and_then(|node| node.kind.focus_identity());
        let role = match &step.command {
            Command::MarkMetrics => "boundary",
            command if command.is_operation() && marked => "operation",
            command if command.is_operation() => "setup",
            _ => "assertion",
        };
        let mut pending_cycles = Vec::new();
        let mut count_evidence = None;
        let mut audio_counter_evidence = None;
        let mut clipboard_counter_evidence = None;
        let mut sqlite_counter_evidence = None;
        let mut http_counter_evidence = None;
        let mut tcp_counter_evidence = None;
        let mut component_work_evidence = None;
        let mut patch_evidence = None;
        let result = match &step.command {
            // Unreachable in practice: `spec::check_runner` rejects window-only
            // steps before a case reaches this runner. Kept as a real arm so the
            // refusal is stated here too rather than silently skipped.
            // The trusted surface needs a window to be drawn on, so this
            // runner refuses the claim rather than answering it from state no
            // frame ever rendered.
            Command::ExpectAppAccess(_)
            | Command::Settle { .. }
            | Command::MarkNativeWork
            | Command::ExpectNativeWork { .. }
            | Command::ExpectOnScreen(_)
            | Command::ExpectRenderedCount(_, _)
            | Command::ExpectBounds(_, _)
            | Command::Screenshot(_)
            | Command::Type(_)
            | Command::Resize { .. }
            | Command::Scroll { .. } => Err(format!(
                "line {}: step `{}` is window-only; run this specification with --host-run-window-spec",
                step.line,
                step.command.kind(),
            )),
            Command::ExpectComponentWork(expected) => {
                let (result, observed) = component_work_claim(expected);
                component_work_evidence = Some((*expected, observed));
                result.map_err(|message| format!("line {}: {message}", step.line))
            }
            Command::MarkMetrics => {
                marked = true;
                Ok(())
            }
            Command::HoverEnter(locator) | Command::HoverExit(locator) => {
                let found = matches(&graph, locator);
                let targets = found
                    .first()
                    .map(|id| graph.hover_targets(*id))
                    .unwrap_or_default();
                if found.len() != 1 {
                    Err(format!(
                        "line {}: hover locator matched {} nodes; expected exactly one",
                        step.line,
                        found.len()
                    ))
                } else if targets.is_empty() {
                    Err(format!(
                        "line {}: hover locator is neither a hover target nor inside a popover's anchor",
                        step.line
                    ))
                } else {
                    // The canonical graph owns transition suppression, popover
                    // presentation, and route liveness, shared with the GPUI
                    // on_hover callback. No alternate handler table. A pointer
                    // resting on the node rests on every region anchoring it;
                    // a target an earlier handler's rebuild retired is skipped,
                    // its state having moved to its replacement.
                    let entered = matches!(step.command, Command::HoverEnter(_));
                    last_patch = None;
                    for target in targets {
                        if graph.node(target).is_none() {
                            continue;
                        }
                        let route = graph.hover_transition(target, entered);
                        if let Some(route) = route {
                            let hover_target = graph.cycle_target(route);
                            let cycle_started = Instant::now();
                            observatory::reset_roc_work();
                            let roc_started = Instant::now();
                            let patch = dispatch(route);
                            let roc_ns = elapsed_ns(roc_started);
                            let (roc_work, roc_work_valid) = observatory::take_roc_work();
                            let facts = apply_transaction(&mut graph, patch)?;
                            last_patch = Some(facts);
                            pending_cycles.push(make_cycle(
                                run_id,
                                cycle_ordinal,
                                Some(ordinal),
                                if marked { "measured" } else { "setup" },
                                if entered { "hover-enter" } else { "hover-exit" },
                                hover_target,
                                cycle_started,
                                roc_ns,
                                roc_work,
                                &facts,
                                roc_work_valid,
                            ));
                            cycle_ordinal += 1;
                        }
                    }
                    Ok(())
                }
            }
            Command::Click(locator) => {
                let matches = matches(&graph, locator);
                if matches.len() != 1 {
                    Err(format!(
                        "line {}: click locator matched {} nodes; expected exactly one",
                        step.line,
                        matches.len()
                    ))
                } else if graph
                    .active_dialog()
                    .is_some_and(|dialog| !graph.is_descendant_of(matches[0], dialog))
                {
                    Ok(())
                } else if matches!(
                    graph.node(matches[0]).map(|node| &node.kind),
                    Some(
                        NodeKind::Button { enabled: false, .. }
                            | NodeKind::Checkbox { enabled: false, .. }
                    )
                ) {
                    // Native disabled controls consume no event, so the semantic
                    // runner likewise performs no Roc dispatch or measurement.
                    Ok(())
                } else {
                    let previous_dialog = graph.active_dialog();
                    let opener = graph
                        .node(matches[0])
                        .and_then(|node| node.kind.focus_identity());
                    let click_target = graph.cycle_target(matches[0]);
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let patch = dispatch(matches[0]);
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = apply_transaction(&mut graph, patch)?;
                    let next_dialog = graph.active_dialog();
                    match (previous_dialog, next_dialog) {
                        (None, Some(dialog)) => {
                            dialog_return_focus = opener;
                            focused = graph.first_focusable_in(dialog);
                        }
                        (Some(_), None) => {
                            focused = dialog_return_focus
                                .take()
                                .and_then(|identity| graph.find_focus_identity(&identity));
                        }
                        _ => {}
                    }
                    last_patch = Some(facts);
                    pending_cycles.push(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        "click",
                        click_target,
                        cycle_started,
                        roc_ns,
                        roc_work,
                        &facts,
                        roc_work_valid,
                    ));
                    cycle_ordinal += 1;
                    Ok(())
                }
            }
            Command::Drag(locator, from_x, from_y, to_x, to_y) => {
                let found = matches(&graph, locator);
                if found.len() != 1 {
                    Err(format!(
                        "line {}: drag locator matched {} nodes; expected exactly one",
                        step.line,
                        found.len()
                    ))
                } else if let Some(NodeKind::Canvas { primitives, .. }) =
                    graph.node(found[0]).map(|node| &node.kind)
                {
                    let target = crate::canvas_target(primitives, *from_x, *from_y).unwrap_or(0);
                    for (phase, x, y) in
                        [(0, *from_x, *from_y), (1, *to_x, *to_y), (2, *to_x, *to_y)]
                    {
                        let id = matches(&graph, locator).into_iter().next().ok_or_else(|| {
                            format!("line {}: canvas disappeared during drag", step.line)
                        })?;
                        let drag_target = graph.cycle_target(id);
                        let cycle_started = Instant::now();
                        observatory::reset_roc_work();
                        let roc_started = Instant::now();
                        let patch = crate::dispatch_canvas(
                            id,
                            crate::CanvasEventPayload {
                                phase,
                                x,
                                y,
                                dx: 0,
                                dy: 0,
                                target,
                            },
                        );
                        let roc_ns = elapsed_ns(roc_started);
                        let (roc_work, roc_work_valid) = observatory::take_roc_work();
                        let facts = apply_transaction(&mut graph, patch)?;
                        last_patch = Some(facts);
                        pending_cycles.push(make_cycle(
                            run_id,
                            cycle_ordinal,
                            Some(ordinal),
                            if marked { "measured" } else { "setup" },
                            "drag",
                            drag_target,
                            cycle_started,
                            roc_ns,
                            roc_work,
                            &facts,
                            roc_work_valid,
                        ));
                        cycle_ordinal += 1;
                    }
                    hovering = None;
                    Ok(())
                } else if let Some(grip) = graph
                    .node(found[0])
                    .and_then(|node| node.kind.splitter_grip())
                {
                    // One move from the press to the release, measured by the
                    // rule the window's pointer handler uses; a size the
                    // divider already shows asks Roc for nothing.
                    let resize = grip.resize((*to_x - *from_x) as f32, (*to_y - *from_y) as f32);
                    let shown = graph
                        .node(found[0])
                        .and_then(|node| node.kind.splitter_value());
                    if shown != Some(resize) {
                        let resize_target = graph.cycle_target(found[0]);
                        let cycle_started = Instant::now();
                        observatory::reset_roc_work();
                        let roc_started = Instant::now();
                        let patch = crate::dispatch_resize(found[0], resize);
                        let roc_ns = elapsed_ns(roc_started);
                        let (roc_work, roc_work_valid) = observatory::take_roc_work();
                        let facts = apply_transaction(&mut graph, patch)?;
                        last_patch = Some(facts);
                        pending_cycles.push(make_cycle(
                            run_id,
                            cycle_ordinal,
                            Some(ordinal),
                            if marked { "measured" } else { "setup" },
                            "drag",
                            resize_target,
                            cycle_started,
                            roc_ns,
                            roc_work,
                            &facts,
                            roc_work_valid,
                        ));
                        cycle_ordinal += 1;
                    }
                    hovering = None;
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: drag takes a canvas or a separator",
                        step.line
                    ))
                }
            }
            Command::PointerMove(locator, _, _)
            | Command::PointerLeave(locator)
            | Command::Wheel(locator, _, _, _, _) => {
                let found = matches(&graph, locator);
                let listening = match (found.as_slice(), &step.command) {
                    ([id], _) => match graph.node(*id).map(|node| &node.kind) {
                        Some(NodeKind::Canvas {
                            primitives,
                            hover,
                            wheel,
                            ..
                        }) => {
                            if matches!(step.command, Command::Wheel(..)) {
                                Ok((*id, *wheel, primitives))
                            } else {
                                Ok((*id, *hover, primitives))
                            }
                        }
                        _ => Err(format!("line {}: locator is not a canvas", step.line)),
                    },
                    (found, _) => Err(format!(
                        "line {}: {} locator matched {} nodes; expected exactly one",
                        step.line,
                        step.command.kind(),
                        found.len()
                    )),
                };
                match listening {
                    Err(message) => Err(message),
                    Ok((_, false, _)) => Err(format!(
                        "line {}: the canvas has no {} handler, so the host delivers nothing",
                        step.line,
                        if matches!(step.command, Command::Wheel(..)) {
                            "on_wheel"
                        } else {
                            "on_hover"
                        }
                    )),
                    Ok((id, true, primitives)) => {
                        // The window delivers what its pointer produces: one
                        // move per new point, a leave only after a move, and
                        // the topmost keyed shape under the point.
                        let canvas = match graph.node(id).map(|node| &node.kind) {
                            Some(NodeKind::Canvas { label, .. }) => label.clone(),
                            _ => String::new(),
                        };
                        let event = match &step.command {
                            Command::PointerMove(_, x, y) => {
                                (hovering != Some((canvas.clone(), (*x, *y)))).then(|| {
                                    hovering = Some((canvas.clone(), (*x, *y)));
                                    (
                                        "hover",
                                        crate::CanvasEventPayload {
                                            phase: crate::CANVAS_HOVER_MOVE,
                                            x: *x,
                                            y: *y,
                                            dx: 0,
                                            dy: 0,
                                            target: crate::canvas_target(primitives, *x, *y)
                                                .unwrap_or(0),
                                        },
                                    )
                                })
                            }
                            Command::PointerLeave(_) => match hovering.take() {
                                Some((hovered, (x, y))) if hovered == canvas => Some((
                                    "hover",
                                    crate::CanvasEventPayload {
                                        phase: crate::CANVAS_HOVER_LEAVE,
                                        x,
                                        y,
                                        dx: 0,
                                        dy: 0,
                                        target: 0,
                                    },
                                )),
                                other => {
                                    hovering = other;
                                    None
                                }
                            },
                            Command::Wheel(_, x, y, dx, dy) => Some((
                                "wheel",
                                crate::CanvasEventPayload {
                                    phase: crate::CANVAS_WHEEL,
                                    x: *x,
                                    y: *y,
                                    dx: *dx,
                                    dy: *dy,
                                    target: crate::canvas_target(primitives, *x, *y).unwrap_or(0),
                                },
                            )),
                            _ => unreachable!("matched a canvas pointer step above"),
                        };
                        match event {
                            None => Ok(()),
                            Some((trigger, event)) => {
                                let canvas_target = graph.cycle_target(id);
                                let cycle_started = Instant::now();
                                observatory::reset_roc_work();
                                let roc_started = Instant::now();
                                let patch = crate::dispatch_canvas(id, event);
                                let roc_ns = elapsed_ns(roc_started);
                                let (roc_work, roc_work_valid) = observatory::take_roc_work();
                                let facts = apply_transaction(&mut graph, patch)?;
                                last_patch = Some(facts);
                                pending_cycles.push(make_cycle(
                                    run_id,
                                    cycle_ordinal,
                                    Some(ordinal),
                                    if marked { "measured" } else { "setup" },
                                    trigger,
                                    canvas_target,
                                    cycle_started,
                                    roc_ns,
                                    roc_work,
                                    &facts,
                                    roc_work_valid,
                                ));
                                cycle_ordinal += 1;
                                Ok(())
                            }
                        }
                    }
                }
            }
            Command::ReplaceText(locator, value) => {
                let found = matches(&graph, locator);
                if found.len() != 1 {
                    Err(format!(
                        "line {}: text locator matched {} nodes; expected exactly one",
                        step.line,
                        found.len()
                    ))
                } else if graph
                    .active_dialog()
                    .is_some_and(|dialog| !graph.is_descendant_of(found[0], dialog))
                {
                    Err(format!(
                        "line {}: locator is blocked by the active dialog",
                        step.line
                    ))
                } else if matches!(
                    graph.node(found[0]).map(|node| &node.kind),
                    Some(NodeKind::TextInput { enabled: true, .. })
                        | Some(NodeKind::Textarea {
                            enabled: true,
                            read_only: false,
                            ..
                        })
                ) {
                    let node_id = found[0];
                    let trigger = if matches!(
                        graph.node(node_id).map(|node| &node.kind),
                        Some(NodeKind::TextInput { .. })
                    ) {
                        "text_change"
                    } else {
                        "input"
                    };
                    let input_target = graph.cycle_target(node_id);
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let patch = crate::dispatch_input(node_id, value.clone());
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = apply_transaction(&mut graph, patch)?;
                    last_patch = Some(facts);
                    pending_cycles.push(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        trigger,
                        input_target,
                        cycle_started,
                        roc_ns,
                        roc_work,
                        &facts,
                        roc_work_valid,
                    ));
                    cycle_ordinal += 1;
                    Ok(())
                } else if matches!(
                    graph.node(found[0]).map(|node| &node.kind),
                    Some(NodeKind::TextInput { enabled: false, .. })
                ) {
                    // Disabled native text inputs neither edit nor dispatch.
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: locator is not an editable text control",
                        step.line
                    ))
                }
            }
            Command::Submit(locator) => {
                let found = matches(&graph, locator);
                if found.len() != 1 {
                    Err(format!(
                        "line {}: submit locator matched {} nodes; expected exactly one",
                        step.line,
                        found.len()
                    ))
                } else if graph
                    .active_dialog()
                    .is_some_and(|dialog| !graph.is_descendant_of(found[0], dialog))
                {
                    Err(format!(
                        "line {}: locator is blocked by the active dialog",
                        step.line
                    ))
                } else if let Some(NodeKind::TextInput {
                    enabled: true,
                    value,
                    ..
                }) = graph.node(found[0]).map(|node| &node.kind)
                {
                    let node_id = found[0];
                    let event_id = node_id | SUBMIT_EVENT_BIT;
                    let previous_dialog = graph.active_dialog();
                    let submit_target = graph.cycle_target(event_id);
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let patch = crate::dispatch_input(event_id, value.clone());
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = apply_transaction(&mut graph, patch)?;
                    let next_dialog = graph.active_dialog();
                    if previous_dialog.is_some() && next_dialog.is_none() {
                        focused = dialog_return_focus
                            .take()
                            .and_then(|identity| graph.find_focus_identity(&identity));
                    }
                    last_patch = Some(facts);
                    pending_cycles.push(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        "text_submit",
                        submit_target,
                        cycle_started,
                        roc_ns,
                        roc_work,
                        &facts,
                        roc_work_valid,
                    ));
                    cycle_ordinal += 1;
                    Ok(())
                } else if matches!(
                    graph.node(found[0]).map(|node| &node.kind),
                    Some(NodeKind::TextInput { enabled: false, .. })
                ) {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: locator is not an enabled text input",
                        step.line
                    ))
                }
            }
            Command::Focus(locator) => {
                let matches = matches(&graph, locator);
                if matches.len() != 1 {
                    Err(format!(
                        "line {}: focus locator matched {} nodes; expected exactly one",
                        step.line,
                        matches.len()
                    ))
                } else if graph
                    .active_dialog()
                    .is_some_and(|dialog| !graph.is_descendant_of(matches[0], dialog))
                {
                    Err(format!(
                        "line {}: locator is blocked by the active dialog",
                        step.line
                    ))
                } else if graph
                    .node(matches[0])
                    .and_then(|node| node.kind.focus_identity())
                    .is_none()
                {
                    // The one definition of what takes focus, which is also
                    // what the window gives a focus handle.
                    Err(format!("line {}: locator is not focusable", step.line))
                } else {
                    focused = Some(matches[0]);
                    // Focus entering or leaving a popover's region, as the
                    // native focus listeners report it.
                    graph.popover_focus_moved(focused);
                    Ok(())
                }
            }
            Command::PressKey(ControlKey::Escape) if graph.active_dialog().is_none() => {
                // Escape that no dialog takes reaches the window root, which
                // closes every presenting popover.
                if graph.dismiss_popovers().is_empty() {
                    Err(format!(
                        "line {}: Escape requires an active dialog or a presenting popover",
                        step.line
                    ))
                } else {
                    Ok(())
                }
            }
            Command::PressKey(key) => {
                let focused_id = if *key == ControlKey::Escape {
                    graph.active_dialog().ok_or_else(|| {
                        format!("line {}: Escape requires an active dialog", step.line)
                    })
                } else {
                    focused.ok_or_else(|| {
                        format!("line {}: press-key requires a focused control", step.line)
                    })
                };
                match focused_id {
                    Err(message) => Err(message),
                    Ok(id) if graph.node(id).is_none() => Err(format!(
                        "line {}: the focused control is no longer live",
                        step.line
                    )),
                    Ok(id) => {
                        let previous_dialog = graph.active_dialog();
                        let activates = graph.node(id).unwrap().kind.accepts_key(*key);
                        if !activates {
                            Err(format!(
                                "line {}: key does not activate the focused control",
                                step.line
                            ))
                        } else {
                            let opener = graph.node(id).and_then(|node| node.kind.focus_identity());
                            let key_target = graph.cycle_target(id);
                            let cycle_started = Instant::now();
                            observatory::reset_roc_work();
                            let roc_started = Instant::now();
                            let patch = dispatch(id);
                            let roc_ns = elapsed_ns(roc_started);
                            let (roc_work, roc_work_valid) = observatory::take_roc_work();
                            let facts = apply_transaction(&mut graph, patch)?;
                            let next_dialog = graph.active_dialog();
                            match (previous_dialog, next_dialog) {
                                (None, Some(dialog)) => {
                                    dialog_return_focus = opener;
                                    focused = graph.first_focusable_in(dialog);
                                }
                                (Some(_), None) => {
                                    focused = dialog_return_focus
                                        .take()
                                        .and_then(|identity| graph.find_focus_identity(&identity));
                                }
                                _ => {}
                            }
                            last_patch = Some(facts);
                            pending_cycles.push(make_cycle(
                                run_id,
                                cycle_ordinal,
                                Some(ordinal),
                                if marked { "measured" } else { "setup" },
                                "keyboard",
                                key_target,
                                cycle_started,
                                roc_ns,
                                roc_work,
                                &facts,
                                roc_work_valid,
                            ));
                            cycle_ordinal += 1;
                            Ok(())
                        }
                    }
                }
            }
            Command::Key(chord) => {
                let keystroke = crate::keyboard::delivered(chord)
                    .map_err(|detail| format!("line {}: {detail}", step.line))?;
                let focused_kind = focused.and_then(|id| graph.node(id)).map(|node| &node.kind);
                if crate::keyboard::host_takes(focused_kind, &keystroke) {
                    // The window's keymap gives this chord to the host or to the
                    // focused control before any shortcut; this runner does not
                    // imitate what they then do.
                    Err(format!(
                        "line {}: the window gives \"{chord}\" to the host or the focused control before any shortcut; use focus, press-key, or a window run",
                        step.line
                    ))
                } else {
                    match graph.resolve_shortcut(
                        focused,
                        crate::keyboard::types_character(&keystroke),
                        |declared| crate::keyboard::matches(&keystroke, declared),
                    ) {
                        // Nothing answers the chord, and in a window nothing
                        // would happen either.
                        None => Ok(()),
                        Some(found) => {
                            // The focused control opened any dialog the shortcut
                            // shows, and gets focus back when it closes.
                            let previous_dialog = graph.active_dialog();
                            let opener = focused
                                .and_then(|id| graph.node(id))
                                .and_then(|node| node.kind.focus_identity());
                            let shortcut_target = graph.cycle_target(found.event);
                            let cycle_started = Instant::now();
                            observatory::reset_roc_work();
                            let roc_started = Instant::now();
                            let patch = crate::dispatch_shortcut(&found);
                            let roc_ns = elapsed_ns(roc_started);
                            let (roc_work, roc_work_valid) = observatory::take_roc_work();
                            let facts = apply_transaction(&mut graph, patch)?;
                            match (previous_dialog, graph.active_dialog()) {
                                (None, Some(dialog)) => {
                                    dialog_return_focus = opener;
                                    focused = graph.first_focusable_in(dialog);
                                }
                                (Some(_), None) => {
                                    focused = dialog_return_focus
                                        .take()
                                        .and_then(|identity| graph.find_focus_identity(&identity));
                                }
                                _ => {}
                            }
                            last_patch = Some(facts);
                            pending_cycles.push(make_cycle(
                                run_id,
                                cycle_ordinal,
                                Some(ordinal),
                                if marked { "measured" } else { "setup" },
                                "key",
                                shortcut_target,
                                cycle_started,
                                roc_ns,
                                roc_work,
                                &facts,
                                roc_work_valid,
                            ));
                            cycle_ordinal += 1;
                            Ok(())
                        }
                    }
                }
            }
            Command::AwaitTask => {
                let before = crate::tasks::delivered();
                let cycle_started = Instant::now();
                observatory::reset_roc_work();
                let completion = await_task_completion()?;
                let roc_started = Instant::now();
                let patch = complete(completion);
                let roc_ns = elapsed_ns(roc_started);
                let after = task_counts();
                if crate::tasks::delivered() != before + 1 || after.1 > after.0 {
                    return Err("task completion counters violated ownership invariants".into());
                }
                let (roc_work, roc_work_valid) = observatory::take_roc_work();
                let facts = apply_transaction(&mut graph, patch)?;
                last_patch = Some(facts);
                pending_cycles.push(make_cycle(
                    run_id,
                    cycle_ordinal,
                    Some(ordinal),
                    if marked { "measured" } else { "setup" },
                    "task",
                    None,
                    cycle_started,
                    roc_ns,
                    roc_work,
                    &facts,
                    roc_work_valid,
                ));
                cycle_ordinal += 1;
                Ok(())
            }
            Command::AwaitCount(locator, expected) => {
                // A wait can deliver several production turns. Record each callback
                // and its own graph decision, never combine work with another patch.
                let before = crate::tasks::delivered();
                let deadline = Instant::now() + crate::TASK_BUDGET;
                let mut completions = 0u64;
                let outcome = loop {
                    let found = matches(&graph, locator).len();
                    if found == *expected {
                        break Ok(());
                    }
                    // Without a clock, the one thing a wait can let happen
                    // without a task is a hovered popover's delay elapsing.
                    let pending = graph.pending_popovers();
                    if !pending.is_empty() {
                        for id in pending {
                            graph.popover_elapse(id);
                        }
                        continue;
                    }
                    if Instant::now() >= deadline {
                        break Err(format!(
                            "line {}: expected locator to match {expected} nodes within {} seconds, but it matched {found}",
                            step.line,
                            crate::TASK_BUDGET.as_secs(),
                        ));
                    }
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let completion = await_task_completion()?;
                    let roc_started = Instant::now();
                    let patch = complete(completion);
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = apply_transaction(&mut graph, patch)?;
                    last_patch = Some(facts);
                    pending_cycles.push(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        "task",
                        None,
                        cycle_started,
                        roc_ns,
                        roc_work,
                        &facts,
                        roc_work_valid,
                    ));
                    cycle_ordinal += 1;
                    completions += 1;
                };
                let after = task_counts();
                if crate::tasks::delivered() != before + completions || after.1 > after.0 {
                    return Err("task completion counters violated ownership invariants".into());
                }
                count_evidence = Some((*expected as u64, matches(&graph, locator).len() as u64));
                outcome
            }
            Command::ClipboardText(text) => crate::clipboard::inject_fixture(text.clone())
                .map_err(|message| format!("line {}: {message}", step.line)),
            Command::SystemTheme(settings) => {
                crate::appearance::set_system(*settings);
                Ok(())
            }
            Command::ExpectTheme(dark) => {
                theme_is(*dark).map_err(|message| format!("line {}: {message}", step.line))
            }
            // A worker blocking is not a turn: nothing is delivered and no
            // cycle is recorded. The step only lets a later cancellation find
            // the wait it is meant to interrupt, rather than a queued task.
            Command::AwaitTaskWaits(expected) => {
                let deadline = Instant::now() + crate::TASK_BUDGET;
                loop {
                    let waiting = crate::tasks::waiting();
                    if waiting == *expected {
                        count_evidence = Some((*expected, waiting));
                        break Ok(());
                    }
                    if Instant::now() >= deadline {
                        break Err(format!(
                            "line {}: expected {expected} blocked task waits within {} seconds, observed {waiting}",
                            step.line,
                            crate::TASK_BUDGET.as_secs(),
                        ));
                    }
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
            }
            Command::AwaitTicks(count) => {
                if *count == 0 {
                    return Err(format!(
                        "line {}: await-ticks count must be positive",
                        step.line
                    ));
                }
                for _ in 0..*count {
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let completion = await_task_completion()?;
                    let roc_started = Instant::now();
                    let patch = complete(completion);
                    let roc_ns = elapsed_ns(roc_started);
                    let fired = crate::timers::fired_count();
                    if fired <= timer_fired_seen {
                        return Err(format!(
                            "line {}: completed task was not a fired timer wait",
                            step.line
                        ));
                    }
                    timer_fired_seen += 1;
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = apply_transaction(&mut graph, patch)?;
                    last_patch = Some(facts);
                    pending_cycles.push(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        "task",
                        None,
                        cycle_started,
                        roc_ns,
                        roc_work,
                        &facts,
                        roc_work_valid,
                    ));
                    cycle_ordinal += 1;
                }
                Ok(())
            }
            // Claims about a process-global resource owner, and the one step
            // that changes one. Both runners answer them from the same reading
            // of the same host, so `expect-file-reads` cannot come to mean two
            // things; only the recording of the evidence is this runner's.
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
            | Command::ExpectTaskCounters(_)
            | Command::ExpectAssetCounters(_)
            | Command::ExpectHashCounters(_)
            | Command::ExpectGrants(_)
            | Command::ExpectGrantCounters(_)
            | Command::ExpectImageOwnerCounters(_) => {
                let (result, counts, evidence) =
                    resource_claim(&step.command, file_counter_baseline)
                        .expect("resource claim is missing an arm");
                count_evidence = counts;
                audio_counter_evidence = evidence.audio;
                clipboard_counter_evidence = evidence.clipboard;
                sqlite_counter_evidence = evidence.sqlite;
                http_counter_evidence = evidence.http;
                tcp_counter_evidence = evidence.tcp;
                result.map_err(|message| format!("line {}: {message}", step.line))
            }
            Command::RevokeFileGrants => {
                crate::files::revoke_all_roots();
                Ok(())
            }
            Command::ReplaceFile { name, source } => {
                crate::files::replace_in_private_copy(name, source)
                    .map_err(|message| format!("line {}: {message}", step.line))
            }
            Command::ExpectVisible(locator) => {
                let count = matches(&graph, locator).len();
                if count == 0 {
                    Err(format!(
                        "line {}: expected locator to be visible",
                        step.line
                    ))
                } else {
                    Ok(())
                }
            }
            Command::ExpectFocused(locator) => {
                let found = matches(&graph, locator);
                if found.len() == 1 && focused == Some(found[0]) {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected locator to have semantic focus",
                        step.line
                    ))
                }
            }
            Command::ExpectNotVisible(locator) => {
                let count = matches(&graph, locator).len();
                if count == 0 {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected locator not to be visible, but it matched {count} nodes",
                        step.line
                    ))
                }
            }
            Command::ExpectCount(locator, expected) => {
                let actual = matches(&graph, locator).len();
                count_evidence = Some((*expected as u64, actual as u64));
                if actual == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected locator to match {expected} nodes, but it matched {actual}",
                        step.line
                    ))
                }
            }
            // Answered from the mounted graph alone, so the window runner
            // makes the same claims from the same code.
            command @ (Command::ExpectCanvasPrimitives(_, _)
            | Command::ExpectValue(_, _)
            | Command::ExpectSelected(_, _)
            | Command::ExpectValueBytes(_, _)
            | Command::ExpectImageBytes(_, _)
            | Command::ExpectRows(_, _)
            | Command::ExpectBefore(_, _)
            | Command::ExpectBackground(_, _)
            | Command::ExpectPopoverCounters(_)
            | Command::ExpectKeyboardCounters(_)) => {
                let (result, counts) =
                    graph_claim(&graph, command).expect("graph claim is missing an arm");
                count_evidence = counts;
                result.map_err(|detail| format!("line {}: {detail}", step.line))
            }
            // Taken, not borrowed: a second `expect-patch` with no interaction
            // between them would otherwise inspect the same patch twice and
            // report a fact about a step that produced none.
            Command::ExpectPatch(expected) => match last_patch.take() {
                None => Err(format!(
                    "line {}: no preceding interaction patch to inspect",
                    step.line
                )),
                Some(actual) => {
                    patch_evidence = Some((
                        expected.kind.clone(),
                        actual.kind,
                        expected.staged,
                        actual.staged,
                        expected.removed,
                        actual.removed,
                    ));
                    if expected.kind == actual.kind
                        && expected.staged == actual.staged
                        && expected.removed == actual.removed
                    {
                        Ok(())
                    } else {
                        Err(format!(
                            "line {}: expected {} patch with {} staged and {} removed nodes; observed {} with {} staged and {} removed",
                            step.line,
                            expected.kind,
                            expected.staged,
                            expected.removed,
                            actual.kind,
                            actual.staged,
                            actual.removed
                        ))
                    }
                }
            },
        };
        // The same control under a new id keeps focus, as it does in the
        // window, where focus follows a rebuilt control by its identity.
        if focused.is_some_and(|id| graph.node(id).is_none()) {
            focused = focus_before.and_then(|identity| graph.find_focus_identity(&identity));
        }
        // A region that asked for focus with a new serial takes it once the
        // step's patches are applied, as the window's does after a patch.
        if let Some(target) = graph.take_focus_request() {
            focused = Some(target);
            graph.popover_focus_moved(focused);
        }
        // Operation timing begins only after locator resolution, at the same
        // boundary as its attributed cycle. Assertions are correctness-only.
        let operation_duration = (!pending_cycles.is_empty())
            .then(|| pending_cycles.iter().map(|cycle| cycle.duration_ns).sum());
        let diagnostic = result.as_ref().err().cloned();
        observatory::step(StepResult {
            run_id,
            ordinal,
            source_line: step.line,
            kind: step.command.kind(),
            role,
            status: if result.is_ok() { "pass" } else { "fail" },
            duration_ns: operation_duration,
            expected_count: count_evidence.map(|value| value.0),
            observed_count: count_evidence.map(|value| value.1),
            audio_counters: audio_counter_evidence,
            clipboard_counters: clipboard_counter_evidence,
            sqlite_counters: sqlite_counter_evidence,
            http_counters: http_counter_evidence,
            tcp_counters: tcp_counter_evidence,
            component_work: component_work_evidence,
            expected_patch_kind: patch_evidence.as_ref().map(|value| value.0.clone()),
            observed_patch_kind: patch_evidence.as_ref().map(|value| value.1),
            expected_staged_nodes: patch_evidence.as_ref().map(|value| value.2),
            observed_staged_nodes: patch_evidence.as_ref().map(|value| value.3),
            expected_removed_nodes: patch_evidence.as_ref().map(|value| value.4),
            observed_removed_nodes: patch_evidence.as_ref().map(|value| value.5),
            diagnostic,
        });
        // The step is deliberately admitted before its cycle so the composite
        // foreign key remains valid even when batches split here.
        for cycle in pending_cycles {
            observatory::cycle(cycle);
        }
        result?;
    }
    Ok(())
}

#[cfg(test)]
mod counter_pattern_tests {
    use super::counter_pattern;

    #[test]
    fn unconstrained_owner_counts_do_not_decide_the_claim_or_aggregate() {
        assert_eq!(
            counter_pattern(&[Some(1), Some(1), None, Some(1)], [1, 1, 3, 1]),
            (true, (3, 3))
        );
        assert_eq!(
            counter_pattern(&[Some(1), Some(1), None, Some(1)], [1, 2, 3, 1]),
            (false, (3, 4))
        );
    }
}

// Flat constructor for the observatory cycle record.
#[allow(clippy::too_many_arguments)]
fn make_cycle(
    run_id: i64,
    ordinal: u64,
    step_ordinal: Option<usize>,
    measurement_phase: &'static str,
    trigger: &'static str,
    target: Option<observatory::CycleTarget>,
    cycle_started: Instant,
    roc_callback_ns: u64,
    roc_work: [observatory::RocWork; observatory::ROC_WORK_KINDS],
    facts: &ApplyFacts,
    roc_work_valid: bool,
) -> Cycle {
    let (start_ns, end_ns) = observatory::interval_since(cycle_started);
    Cycle {
        run_id,
        ordinal,
        step_ordinal,
        measurement_phase,
        trigger,
        target,
        patch_kind: facts.kind,
        start_ns,
        end_ns,
        duration_ns: end_ns - start_ns,
        roc_callback_ns,
        validate_ns: facts.validate_ns,
        apply_ns: facts.apply_ns,
        graph_apply_ns: facts.apply_ns,
        gpui_apply_ns: None,
        staged_nodes: facts.staged,
        removed_nodes: facts.removed,
        live_nodes: facts.live,
        parent_nodes_scanned: facts.scanned,
        retained_nodes: facts.retained_nodes,
        validation_visits: facts.validation_visits,
        keyed_graph_visits: facts.keyed_graph_visits,
        keyed_original_reads: facts.keyed_original_reads,
        keyed_first_touches: facts.keyed_first_touches,
        keyed_native_edits: 0,
        keyed_item_entities_created: 0,
        keyed_item_entities_retired: 0,
        keyed_item_entities_moved: 0,
        roc_work,
        roc_work_valid,
        component_work: observatory::component_cycle_work(),
    }
}

/// Whether adaptive colours resolve to the scheme a step names. Both runners
/// answer from the one process-wide appearance.
pub(crate) fn theme_is(dark: bool) -> Result<(), String> {
    let actual = crate::appearance::effective_dark();
    if actual == dark {
        Ok(())
    } else {
        let name = |dark| if dark { "dark" } else { "light" };
        Err(format!(
            "expected the {} scheme; adaptive colours resolve to {}",
            name(dark),
            name(actual)
        ))
    }
}

fn elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}

#[cfg(test)]
mod controlled_value_tests {
    use super::*;
    use crate::bridge::{Node, Style};

    fn controlled_graph(textarea: bool, value: &str) -> (MountedGraph, Locator) {
        let label = "Editor".to_owned();
        let value = value.to_owned();
        let placeholder = String::new();
        let style: Box<Style> = Box::default();
        let (kind, locator) = if textarea {
            (
                NodeKind::Textarea {
                    label: label.clone(),
                    value,
                    placeholder,
                    enabled: true,
                    read_only: false,
                    style,
                },
                Locator::TextareaName(label),
            )
        } else {
            (
                NodeKind::TextInput {
                    label: label.clone(),
                    value,
                    placeholder,
                    enabled: true,
                    style,
                },
                Locator::TextInputName(label),
            )
        };
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![Node {
                    id: 1,
                    kind,
                    children: vec![],
                }],
            })
            .unwrap();
        (graph, locator)
    }

    #[test]
    fn background_claim_uses_explicit_graph_color_without_fabricating_counts() {
        for color in [
            None,
            Some(crate::Paint::Rgb(0)),
            Some(crate::Paint::Rgb(0x66E0FF)),
        ] {
            let mut graph = MountedGraph::default();
            graph
                .apply(Patch::Mount {
                    root: 1,
                    nodes: vec![Node {
                        id: 1,
                        kind: NodeKind::Button {
                            role: crate::bridge::ButtonRole::Button,
                            caption: String::new(),
                            label: "Cell".into(),
                            enabled: true,
                            hover_enter: true,
                            hover_exit: true,
                            style: Box::new(Style {
                                bg: color,
                                ..Style::default()
                            }),
                        },
                        children: vec![],
                    }],
                })
                .unwrap();
            let (result, counts) = graph_claim(
                &graph,
                &Command::ExpectBackground(Locator::ButtonName("Cell".into()), 0x66E0FF),
            )
            .unwrap();
            assert_eq!(result.is_ok(), color == Some(crate::Paint::Rgb(0x66E0FF)));
            assert_eq!(counts, None);
            if color.is_none() {
                assert!(result.unwrap_err().contains("unavailable"));
            }
        }
    }

    #[test]
    fn controlled_values_compare_exact_text_without_exposing_it() {
        for textarea in [false, true] {
            let (graph, locator) = controlled_graph(textarea, "private-é");
            let (claim, observed) = graph_claim(
                &graph,
                &Command::ExpectValue(locator.clone(), "private-é".into()),
            )
            .unwrap();
            assert!(claim.is_ok());
            assert_eq!(observed, None);
            let (claim, observed) =
                graph_claim(&graph, &Command::ExpectValue(locator, "secret-é".into())).unwrap();
            assert_eq!(claim.unwrap_err(), "controlled input value differed");
            assert_eq!(observed, None);
        }
    }

    #[test]
    fn controlled_value_lengths_count_utf8_bytes_including_empty_values() {
        for textarea in [false, true] {
            for value in ["", "é"] {
                let (graph, locator) = controlled_graph(textarea, value);
                let length = value.len();
                let (claim, observed) =
                    graph_claim(&graph, &Command::ExpectValueBytes(locator.clone(), length))
                        .unwrap();
                assert!(claim.is_ok());
                assert_eq!(observed, Some((length as u64, length as u64)));
                let (claim, observed) =
                    graph_claim(&graph, &Command::ExpectValueBytes(locator, length + 1)).unwrap();
                assert!(claim.is_err());
                assert_eq!(observed, Some((length as u64 + 1, length as u64)));
            }
        }
    }

    #[test]
    fn an_unavailable_controlled_value_is_not_reported_as_zero_bytes() {
        let (graph, _) = controlled_graph(false, "");
        let (claim, observed) = graph_claim(
            &graph,
            &Command::ExpectValueBytes(Locator::TextInputName("Absent".into()), 0),
        )
        .unwrap();
        assert!(claim.is_err());
        assert_eq!(observed, None);
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![Node {
                    id: 1,
                    kind: NodeKind::Text("caption".into()),
                    children: vec![],
                }],
            })
            .unwrap();
        let (claim, observed) = graph_claim(
            &graph,
            &Command::ExpectValueBytes(Locator::Text("caption".into()), 0),
        )
        .unwrap();
        assert!(claim.is_err());
        assert_eq!(observed, None);
    }
}

#[cfg(test)]
mod component_work_tests {
    use super::*;

    #[test]
    fn shared_component_claim_distinguishes_unavailable_zero_and_a_failed_count() {
        observatory::clear_component_work();
        let mut expected = [None; observatory::COMPONENT_WORK_NAMES.len()];
        expected[0] = Some(0);
        let (result, observed) = component_work_claim(&expected);
        assert!(result.unwrap_err().contains("unavailable"));
        assert_eq!(observed, None);
        observatory::begin_component_work();
        observatory::commit_component_work();
        assert!(component_work_claim(&expected).0.is_ok());
        observatory::begin_component_work();
        observatory::note_component_work(0, 2);
        observatory::commit_component_work();
        assert!(
            component_work_claim(&expected)
                .0
                .unwrap_err()
                .contains("observed 2")
        );
        observatory::clear_component_work();
    }
}

#[cfg(test)]
mod locator_tests {
    use super::*;
    use crate::bridge::{Node, Style};

    fn within(ancestor: Locator, target: Locator) -> Locator {
        Locator::Within(Box::new(ancestor), Box::new(target))
    }

    fn graph() -> MountedGraph {
        let style: Box<Style> = Box::default();
        let node = |id, kind, children| Node { id, kind, children };
        let panel = |label: &str| NodeKind::Panel {
            label: label.into(),
            style: style.clone(),
        };
        let input = || NodeKind::TextInput {
            label: "Value".into(),
            value: String::new(),
            placeholder: String::new(),
            enabled: true,
            style: style.clone(),
        };
        let primitive = |key, label: &str| CanvasPrimitive {
            kind: CanvasPrimitiveKind::Rectangle,
            key,
            label: label.into(),
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            x2: 0,
            y2: 0,
            fill: None,
            stroke: None,
            stroke_width: 0,
            radius: 0,
            ..Default::default()
        };
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![
                    node(1, panel("Page"), vec![2, 5]),
                    node(2, panel("Left"), vec![3]),
                    node(3, NodeKind::Boundary { instance: 11 }, vec![4]),
                    node(
                        4,
                        NodeKind::Row {
                            label: "Contents".into(),
                            style: style.clone(),
                        },
                        vec![8, 10],
                    ),
                    node(5, panel("Right"), vec![6]),
                    node(6, NodeKind::Boundary { instance: 22 }, vec![7]),
                    node(
                        7,
                        NodeKind::Row {
                            label: "Contents".into(),
                            style: style.clone(),
                        },
                        vec![9, 12],
                    ),
                    node(8, input(), vec![]),
                    node(9, input(), vec![]),
                    node(
                        10,
                        NodeKind::Canvas {
                            label: "Canvas".into(),
                            primitives: vec![primitive(1, "Dot one"), primitive(2, "Dot two")],
                            hover: false,
                            wheel: false,
                            style: style.clone(),
                        },
                        vec![],
                    ),
                    node(
                        12,
                        NodeKind::Canvas {
                            label: "Canvas".into(),
                            primitives: vec![primitive(1, "Dot one")],
                            hover: false,
                            wheel: false,
                            style,
                        },
                        vec![],
                    ),
                ],
            })
            .unwrap();
        graph
    }

    #[test]
    fn within_filters_duplicate_component_labels_without_hiding_ambiguity() {
        let graph = graph();
        let target = Locator::TextInputName("Value".into());
        assert_eq!(matches(&graph, &target), vec![8, 9]);
        assert_eq!(
            matches(
                &graph,
                &within(Locator::PanelName("Left".into()), target.clone())
            ),
            vec![8]
        );
        assert_eq!(
            matches(
                &graph,
                &within(Locator::PanelName("Page".into()), target.clone())
            ),
            vec![8, 9]
        );
        assert_eq!(
            matches(
                &graph,
                &within(Locator::PanelName("Missing".into()), target)
            ),
            Vec::<u64>::new()
        );
    }

    #[test]
    fn within_is_strict_and_nested_targets_use_the_same_graph_path() {
        let graph = graph();
        let page = Locator::PanelName("Page".into());
        assert!(matches(&graph, &within(page.clone(), page)).is_empty());
        let target = within(
            Locator::RowName("Contents".into()),
            Locator::TextInputName("Value".into()),
        );
        assert_eq!(
            matches(&graph, &within(Locator::PanelName("Left".into()), target)),
            vec![8]
        );
    }

    #[test]
    fn scoped_canvas_counts_and_screenshot_targets_share_scope_resolution() {
        let graph = graph();
        let prefix = within(
            Locator::PanelName("Left".into()),
            Locator::CanvasItemPrefix("Dot".into()),
        );
        assert_eq!(matches(&graph, &prefix), vec![10, 10]);
        assert!(canvas_item(&graph, &prefix).is_none());
        let item = within(
            Locator::PanelName("Right".into()),
            Locator::CanvasItemName("Dot one".into()),
        );
        assert_eq!(matches(&graph, &item), vec![12]);
        let (owner, item) = canvas_item(&graph, &item).unwrap();
        assert_eq!(owner, 12);
        assert_eq!(item.label, "Dot one");
    }

    #[test]
    fn canvas_primitive_is_a_strict_semantic_child_not_an_ancestor() {
        let graph = graph();
        let canvas = within(
            Locator::PanelName("Left".into()),
            Locator::CanvasName("Canvas".into()),
        );
        let primitive = Locator::CanvasItemName("Dot one".into());
        let scoped = within(canvas.clone(), primitive.clone());
        assert_eq!(matches(&graph, &scoped), vec![10]);
        assert_eq!(canvas_item(&graph, &scoped).unwrap().0, 10);
        assert!(matches(&graph, &within(canvas.clone(), canvas)).is_empty());
        assert!(matches(&graph, &within(primitive.clone(), primitive)).is_empty());
    }
}
