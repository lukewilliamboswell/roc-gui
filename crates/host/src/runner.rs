use crate::{
    SUBMIT_EVENT_BIT, await_task_completion,
    bridge::{ApplyFacts, ControlKey, MountedGraph, NodeKind},
    clear_bridge, complete, dispatch,
    observatory::{self, Cycle, StepResult},
    roc_platform_abi::roc_gui_init,
    spec::{Command, Locator, Spec},
    take_patch, task_counts,
};
use std::time::Instant;

fn matches(graph: &MountedGraph, locator: &Locator) -> Vec<u64> {
    if let Locator::CanvasItemPrefix(prefix) = locator {
        return graph
            .nodes_preorder()
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
        .nodes_preorder()
        .into_iter()
        .filter_map(|node| match (locator, &node.kind) {
            (Locator::Text(expected), NodeKind::Text(actual)) if expected == actual => {
                Some(node.id)
            }
            (Locator::TextPrefix(expected), NodeKind::Text(actual))
                if actual.starts_with(expected) =>
            {
                Some(node.id)
            }
            (Locator::ButtonName(expected), NodeKind::Button { label, .. })
                if expected == label =>
            {
                Some(node.id)
            }
            (Locator::ButtonPrefix(expected), NodeKind::Button { label, .. })
                if label.starts_with(expected) =>
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
                if !label.is_empty() && expected == label =>
            {
                Some(node.id)
            }
            (Locator::DialogName(expected), NodeKind::Dialog { label, .. })
                if expected == label =>
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

fn expect_file_counter(
    line: usize,
    name: &str,
    expected: u64,
    observed: u64,
    evidence: &mut Option<(u64, u64)>,
) -> Result<(), String> {
    *evidence = Some((expected, observed));
    if expected == observed {
        Ok(())
    } else {
        Err(format!(
            "line {line}: expected {expected} file {name}, observed {observed}"
        ))
    }
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
    let roc_started = Instant::now();
    unsafe { roc_gui_init() };
    let roc_ns = elapsed_ns(roc_started);
    let (roc_work, roc_work_valid) = observatory::take_roc_work();
    let patch = take_patch();
    let facts = graph.apply_measured(patch)?.facts;
    observatory::cycle(make_cycle(
        run_id,
        0,
        None,
        "initialization",
        "init",
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
    let mut timer_fired_seen = crate::timers::fired_count();
    let mut dialog_return_focus: Option<(u8, String)> = None;
    for (ordinal, step) in spec.steps.iter().enumerate() {
        let role = match &step.command {
            Command::MarkMetrics => "boundary",
            command if command.is_operation() && marked => "operation",
            command if command.is_operation() => "setup",
            _ => "assertion",
        };
        let mut pending_cycle = None;
        let mut count_evidence = None;
        let mut audio_counter_evidence = None;
        let mut clipboard_counter_evidence = None;
        let mut sqlite_counter_evidence = None;
        let mut http_counter_evidence = None;
        let mut tcp_counter_evidence = None;
        let mut patch_evidence = None;
        let result = match &step.command {
            Command::MarkMetrics => {
                marked = true;
                Ok(())
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
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let patch = dispatch(matches[0]);
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = graph.apply_measured(patch)?.facts;
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
                    pending_cycle = Some(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        "click",
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
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let mut id = found[0];
                    let mut patch = crate::dispatch_canvas(
                        id,
                        crate::CanvasEventPayload {
                            phase: 0,
                            x: *from_x,
                            y: *from_y,
                            target,
                        },
                    );
                    let _ = graph.apply_measured(patch)?.facts;
                    id = matches(&graph, locator).into_iter().next().ok_or_else(|| {
                        format!("line {}: canvas disappeared during drag", step.line)
                    })?;
                    patch = crate::dispatch_canvas(
                        id,
                        crate::CanvasEventPayload {
                            phase: 1,
                            x: *to_x,
                            y: *to_y,
                            target,
                        },
                    );
                    let _ = graph.apply_measured(patch)?.facts;
                    id = matches(&graph, locator).into_iter().next().ok_or_else(|| {
                        format!("line {}: canvas disappeared during drag", step.line)
                    })?;
                    patch = crate::dispatch_canvas(
                        id,
                        crate::CanvasEventPayload {
                            phase: 2,
                            x: *to_x,
                            y: *to_y,
                            target,
                        },
                    );
                    let facts = graph.apply_measured(patch)?.facts;
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    last_patch = Some(facts);
                    pending_cycle = Some(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        "drag",
                        cycle_started,
                        roc_ns,
                        roc_work,
                        &facts,
                        roc_work_valid,
                    ));
                    cycle_ordinal += 1;
                    Ok(())
                } else {
                    Err(format!("line {}: locator is not a canvas", step.line))
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
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let patch = crate::dispatch_input(node_id, value.clone());
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = graph.apply_measured(patch)?.facts;
                    last_patch = Some(facts);
                    pending_cycle = Some(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        trigger,
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
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let patch = crate::dispatch_input(event_id, value.clone());
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = graph.apply_measured(patch)?.facts;
                    let next_dialog = graph.active_dialog();
                    if previous_dialog.is_some() && next_dialog.is_none() {
                        focused = dialog_return_focus
                            .take()
                            .and_then(|identity| graph.find_focus_identity(&identity));
                    }
                    last_patch = Some(facts);
                    pending_cycle = Some(make_cycle(
                        run_id,
                        cycle_ordinal,
                        Some(ordinal),
                        if marked { "measured" } else { "setup" },
                        "text_submit",
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
                } else if !matches!(
                    graph.node(matches[0]).map(|node| &node.kind),
                    Some(
                        NodeKind::Button { enabled: true, .. }
                            | NodeKind::Checkbox { enabled: true, .. }
                            | NodeKind::Textarea {
                                enabled: true,
                                read_only: false,
                                ..
                            }
                            | NodeKind::TextInput { enabled: true, .. }
                    )
                ) {
                    Err(format!("line {}: locator is not focusable", step.line))
                } else {
                    focused = Some(matches[0]);
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
                            let cycle_started = Instant::now();
                            observatory::reset_roc_work();
                            let roc_started = Instant::now();
                            let patch = dispatch(id);
                            let roc_ns = elapsed_ns(roc_started);
                            let (roc_work, roc_work_valid) = observatory::take_roc_work();
                            let facts = graph.apply_measured(patch)?.facts;
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
                            pending_cycle = Some(make_cycle(
                                run_id,
                                cycle_ordinal,
                                Some(ordinal),
                                if marked { "measured" } else { "setup" },
                                "keyboard",
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
                let before = task_counts();
                let cycle_started = Instant::now();
                observatory::reset_roc_work();
                let roc_started = Instant::now();
                let completion = await_task_completion()?;
                let patch = complete(completion);
                let roc_ns = elapsed_ns(roc_started);
                let after = task_counts();
                if after.1 != before.1 + 1 || after.1 > after.0 {
                    return Err("task completion counters violated ownership invariants".into());
                }
                let (roc_work, roc_work_valid) = observatory::take_roc_work();
                let facts = graph.apply_measured(patch)?.facts;
                last_patch = Some(facts);
                pending_cycle = Some(make_cycle(
                    run_id,
                    cycle_ordinal,
                    Some(ordinal),
                    if marked { "measured" } else { "setup" },
                    "task",
                    cycle_started,
                    roc_ns,
                    roc_work,
                    &facts,
                    roc_work_valid,
                ));
                cycle_ordinal += 1;
                Ok(())
            }
            Command::ClipboardText(text) => crate::clipboard::inject_fixture(text.clone())
                .map_err(|message| format!("line {}: {message}", step.line)),
            Command::AwaitTicks(count) => {
                if *count == 0 {
                    return Err(format!(
                        "line {}: await-ticks count must be positive",
                        step.line
                    ));
                }
                for _ in 0..*count {
                    let patch = complete(await_task_completion()?);
                    let fired = crate::timers::fired_count();
                    if fired <= timer_fired_seen {
                        return Err(format!(
                            "line {}: completed task was not a fired timer wait",
                            step.line
                        ));
                    }
                    timer_fired_seen += 1;
                    last_patch = Some(graph.apply_measured(patch)?.facts);
                }
                Ok(())
            }
            Command::ExpectSubscriptions(expected) => {
                let active = crate::timers::active_count();
                if active == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected {expected} active subscriptions, observed {active}",
                        step.line
                    ))
                }
            }
            Command::ExpectTcpStreams(expected) => {
                let active = crate::tcp::active_count();
                count_evidence = Some((*expected as u64, active as u64));
                if active == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected {expected} active TCP streams, observed {active}",
                        step.line
                    ))
                }
            }
            Command::ExpectProcesses(expected) => {
                let active = crate::process::active_count();
                let (spawned, _, _, canceled) = crate::process::counters();
                if canceled > spawned {
                    return Err("process lifecycle counters violated ownership invariants".into());
                }
                if active == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected {expected} active PTY processes, observed {active}",
                        step.line
                    ))
                }
            }
            Command::ExpectClipboardCounters(expected) => {
                let (operations, handles) = crate::clipboard::counters();
                let observed = [handles as u64, operations[0], operations[1], operations[2]];
                count_evidence = Some((expected.iter().sum(), observed.iter().sum()));
                clipboard_counter_evidence = Some((*expected, observed));
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected clipboard counters {:?}, observed {:?}",
                        step.line, expected, observed
                    ))
                }
            }
            Command::ExpectSqliteCounters(expected) => {
                let (operations, connections) = crate::sqlite::counters();
                let observed = [connections as u64, operations[0], operations[1]];
                count_evidence = Some((expected.iter().sum(), observed.iter().sum()));
                sqlite_counter_evidence = Some((*expected, observed));
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected SQLite counters {:?}, observed {:?}",
                        step.line, expected, observed
                    ))
                }
            }
            Command::ExpectHttpCounters(expected) => {
                let (operations, clients) = crate::http::counters();
                let observed = [clients as u64, operations[0], operations[1], operations[2]];
                count_evidence = Some((expected.iter().sum(), observed.iter().sum()));
                http_counter_evidence = Some((*expected, observed));
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected HTTP counters {:?}, observed {:?}",
                        step.line, expected, observed
                    ))
                }
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
                count_evidence = Some((expected.iter().sum(), observed.iter().sum()));
                tcp_counter_evidence = Some((*expected, observed));
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected TCP counters {:?}, observed {:?}",
                        step.line, expected, observed
                    ))
                }
            }
            Command::ExpectDeviceConnections(expected) => {
                let active = crate::device::active_count();
                let (_, connected, _, closed) = crate::device::counters();
                if closed > connected {
                    return Err("device lifecycle counters violated ownership invariants".into());
                }
                count_evidence = Some((*expected as u64, active as u64));
                if active == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected {expected} active device connections, observed {active}",
                        step.line
                    ))
                }
            }
            Command::ExpectDeviceTransactions(expected) => {
                let (_, _, transactions, _) = crate::device::counters();
                count_evidence = Some((*expected as u64, transactions));
                if transactions == *expected as u64 {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected {expected} device transactions, observed {transactions}",
                        step.line
                    ))
                }
            }
            Command::ExpectSystemSamplers(expected) => {
                let active = crate::system_monitor::active_count();
                let (acquired, _, closed) = crate::system_monitor::counters();
                if closed > acquired {
                    return Err(
                        "system sampler lifecycle counters violated ownership invariants".into(),
                    );
                }
                count_evidence = Some((*expected as u64, active as u64));
                if active == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected {expected} active system samplers, observed {active}",
                        step.line
                    ))
                }
            }
            Command::ExpectSystemSamples(expected) => {
                let (_, sampled, _) = crate::system_monitor::counters();
                count_evidence = Some((*expected as u64, sampled));
                if sampled == *expected as u64 {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected {expected} system samples, observed {sampled}",
                        step.line
                    ))
                }
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
                count_evidence = Some((expected.iter().sum(), observed.iter().sum()));
                audio_counter_evidence = Some((*expected, observed));
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected audio counters {:?}, observed {:?}",
                        step.line, expected, observed
                    ))
                }
            }
            Command::ExpectFilePicks(expected) => expect_file_counter(
                step.line,
                "picks",
                *expected,
                crate::files::operation_counts()[0] - file_counter_baseline[0],
                &mut count_evidence,
            ),
            Command::ExpectFileLists(expected) => expect_file_counter(
                step.line,
                "lists",
                *expected,
                crate::files::operation_counts()[1] - file_counter_baseline[1],
                &mut count_evidence,
            ),
            Command::ExpectFileOpens(expected) => expect_file_counter(
                step.line,
                "opens",
                *expected,
                crate::files::operation_counts()[2] - file_counter_baseline[2],
                &mut count_evidence,
            ),
            Command::ExpectFileReads(expected) => expect_file_counter(
                step.line,
                "reads",
                *expected,
                crate::files::operation_counts()[3] - file_counter_baseline[3],
                &mut count_evidence,
            ),
            Command::ExpectFileSelectionCounters(expected) => {
                let observed = crate::files::selection_counts();
                count_evidence = Some((expected.iter().sum(), observed.iter().sum()));
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected file selection counters {:?}, observed {:?}",
                        step.line, expected, observed
                    ))
                }
            }
            Command::ExpectImageOwnerCounters(expected) => {
                let observed = crate::image_data::counters();
                count_evidence = Some((expected.iter().sum(), observed.iter().sum()));
                if observed == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected image owner counters {:?}, observed {:?}",
                        step.line, expected, observed
                    ))
                }
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
            Command::ExpectCanvasPrimitives(locator, expected) => {
                let found = matches(&graph, locator);
                let actual = if found.len() == 1 {
                    match graph.node(found[0]).map(|node| &node.kind) {
                        Some(NodeKind::Canvas { primitives, .. }) => primitives.len(),
                        _ => 0,
                    }
                } else {
                    0
                };
                count_evidence = Some((*expected as u64, actual as u64));
                if actual == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected canvas owner to report {expected} primitives, but it reported {actual}",
                        step.line
                    ))
                }
            }
            Command::ExpectValue(locator, expected) => {
                let found = matches(&graph, locator);
                if found.len() != 1 {
                    Err(format!(
                        "line {}: expect-value locator matched {} nodes; expected exactly one",
                        step.line,
                        found.len()
                    ))
                } else if matches!(graph.node(found[0]).map(|node| &node.kind), Some(NodeKind::Textarea { value, .. }) if value == expected)
                {
                    Ok(())
                } else {
                    Err(format!("line {}: textarea value differed", step.line))
                }
            }
            Command::ExpectValueBytes(locator, expected) => {
                let found = matches(&graph, locator);
                let actual = if found.len() == 1 {
                    match graph.node(found[0]).map(|node| &node.kind) {
                        Some(NodeKind::Textarea { value, .. }) => value.len(),
                        _ => 0,
                    }
                } else {
                    0
                };
                count_evidence = Some((*expected as u64, actual as u64));
                if found.len() == 1 && actual == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected textarea value to contain {expected} bytes; observed {actual}",
                        step.line
                    ))
                }
            }
            Command::ExpectImageBytes(locator, expected) => {
                let found = matches(&graph, locator);
                let actual = if found.len() == 1 {
                    match graph.node(found[0]).map(|node| &node.kind) {
                        Some(NodeKind::Image { bytes, .. }) => bytes.len(),
                        _ => 0,
                    }
                } else {
                    0
                };
                count_evidence = Some((*expected as u64, actual as u64));
                if found.len() == 1 && actual == *expected {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected image source to contain {expected} bytes; observed {actual}",
                        step.line
                    ))
                }
            }
            Command::ExpectBefore(first, second) => {
                let first_matches = matches(&graph, first);
                let second_matches = matches(&graph, second);
                let ordered = graph.nodes_preorder();
                let position = |id| ordered.iter().position(|node| node.id == id);
                if first_matches.len() != 1 || second_matches.len() != 1 {
                    Err(format!(
                        "line {}: expect-before locators matched {} and {} nodes; expected one each",
                        step.line,
                        first_matches.len(),
                        second_matches.len()
                    ))
                } else if position(first_matches[0]) < position(second_matches[0]) {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected first locator before second",
                        step.line
                    ))
                }
            }
            Command::ExpectPatch(expected) => match last_patch {
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
        // Operation timing begins only after locator resolution, at the same
        // boundary as its attributed cycle. Assertions are correctness-only.
        let operation_duration = pending_cycle.as_ref().map(|cycle| cycle.duration_ns);
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
        if let Some(cycle) = pending_cycle {
            observatory::cycle(cycle);
        }
        result?;
    }
    Ok(())
}

fn make_cycle(
    run_id: i64,
    ordinal: u64,
    step_ordinal: Option<usize>,
    measurement_phase: &'static str,
    trigger: &'static str,
    cycle_started: Instant,
    roc_callback_ns: u64,
    roc_work: [observatory::RocWork; 4],
    facts: &ApplyFacts,
    roc_work_valid: bool,
) -> Cycle {
    Cycle {
        run_id,
        ordinal,
        step_ordinal,
        measurement_phase,
        trigger,
        patch_kind: facts.kind,
        duration_ns: elapsed_ns(cycle_started),
        roc_callback_ns,
        validate_ns: facts.validate_ns,
        apply_ns: facts.apply_ns,
        graph_apply_ns: facts.apply_ns,
        gpui_apply_ns: None,
        staged_nodes: facts.staged,
        removed_nodes: facts.removed,
        live_nodes: facts.live,
        parent_nodes_scanned: facts.scanned,
        roc_work,
        roc_work_valid,
    }
}

fn elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}
