use crate::{
    await_task_completion,
    bridge::{ApplyFacts, MountedGraph, NodeKind},
    clear_bridge, complete, dispatch,
    observatory::{self, Cycle, StepResult},
    roc_platform_abi::roc_gui_init,
    spec::{Command, Locator, Spec},
    take_patch, task_counts,
};
use std::time::Instant;

fn matches(graph: &MountedGraph, locator: &Locator) -> Vec<u64> {
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
            (Locator::ButtonName(expected), NodeKind::Button { name }) if expected == name => {
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
            (Locator::RowName(expected), NodeKind::Row { label, .. })
                if !label.is_empty() && expected == label =>
            {
                Some(node.id)
            }
            (Locator::ScrollName(expected), NodeKind::Scroll { name, .. }) if expected == name => {
                Some(node.id)
            }
            _ => None,
        })
        .collect()
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
    for (ordinal, step) in spec.steps.iter().enumerate() {
        let role = match &step.command {
            Command::MarkMetrics => "boundary",
            command if command.is_operation() && marked => "operation",
            command if command.is_operation() => "setup",
            _ => "assertion",
        };
        let mut pending_cycle = None;
        let mut count_evidence = None;
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
                } else {
                    let cycle_started = Instant::now();
                    observatory::reset_roc_work();
                    let roc_started = Instant::now();
                    let patch = dispatch(matches[0]);
                    let roc_ns = elapsed_ns(roc_started);
                    let (roc_work, roc_work_valid) = observatory::take_roc_work();
                    let facts = graph.apply_measured(patch)?.facts;
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
            Command::Focus(locator) => {
                let matches = matches(&graph, locator);
                if matches.len() != 1 {
                    Err(format!(
                        "line {}: focus locator matched {} nodes; expected exactly one",
                        step.line,
                        matches.len()
                    ))
                } else if !matches!(
                    graph.node(matches[0]).map(|node| &node.kind),
                    Some(NodeKind::Button { .. } | NodeKind::Checkbox { enabled: true, .. })
                ) {
                    Err(format!("line {}: locator is not focusable", step.line))
                } else {
                    focused = Some(matches[0]);
                    Ok(())
                }
            }
            Command::PressKey(key) => {
                let focused_id = focused.ok_or_else(|| {
                    format!("line {}: press-key requires a focused control", step.line)
                });
                match focused_id {
                    Err(message) => Err(message),
                    Ok(id) if graph.node(id).is_none() => Err(format!(
                        "line {}: the focused control is no longer live",
                        step.line
                    )),
                    Ok(id) => {
                        let activates = graph.node(id).unwrap().kind.accepts_key(*key);
                        if !activates {
                            Err(format!(
                                "line {}: key does not activate the focused control",
                                step.line
                            ))
                        } else {
                            let cycle_started = Instant::now();
                            observatory::reset_roc_work();
                            let roc_started = Instant::now();
                            let patch = dispatch(id);
                            let roc_ns = elapsed_ns(roc_started);
                            let (roc_work, roc_work_valid) = observatory::take_roc_work();
                            let facts = graph.apply_measured(patch)?.facts;
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
