use crate::{
    bridge::{Node, NodeKind, Patch, validate_tree},
    clear_bridge, dispatch,
    observatory::{self, Cycle, StepResult},
    roc_platform_abi::roc_gui_init,
    spec::{Command, Locator, Spec},
    take_patch,
};
use std::{
    collections::{HashMap, HashSet},
    time::Instant,
};

#[derive(Default)]
struct MountedGraph {
    nodes: HashMap<u64, Node>,
    root: Option<u64>,
}

struct ApplyFacts {
    kind: &'static str,
    staged: u64,
    removed: u64,
    live: u64,
    scanned: u64,
    validate_ns: u64,
    apply_ns: u64,
}

impl MountedGraph {
    fn apply(&mut self, patch: Patch) -> Result<ApplyFacts, String> {
        let validate_started = Instant::now();
        match &patch {
            Patch::Mount { root, nodes } | Patch::Replace { root, nodes, .. } => {
                validate_tree(*root, nodes)?;
            }
            Patch::NoChange => {}
        }
        let validate_ns = elapsed_ns(validate_started);
        let apply_started = Instant::now();
        let (kind, staged, removed, scanned) = match patch {
            Patch::NoChange => ("no_change", 0, 0, 0),
            Patch::Mount { root, nodes } => {
                if !self.nodes.is_empty() {
                    return Err("application attempted to mount twice".into());
                }
                let staged = nodes.len() as u64;
                self.nodes
                    .extend(nodes.into_iter().map(|node| (node.id, node)));
                self.root = Some(root);
                ("mount", staged, 0, 0)
            }
            Patch::Replace {
                old_root,
                root,
                nodes,
            } => {
                let removed_ids = self.subtree_ids(old_root)?;
                if nodes.iter().any(|node| self.nodes.contains_key(&node.id)) {
                    return Err("replacement reused a live node id".into());
                }
                let mut parent = None;
                let mut scanned = 0;
                for (id, node) in &self.nodes {
                    scanned += 1;
                    if let Some(position) =
                        node.children.iter().position(|child| *child == old_root)
                    {
                        parent = Some((*id, position));
                        break;
                    }
                }
                let replacing_root = self.root == Some(old_root);
                if parent.is_none() && !replacing_root {
                    return Err("replacement target is detached".into());
                }
                let staged = nodes.len() as u64;
                self.nodes
                    .extend(nodes.into_iter().map(|node| (node.id, node)));
                if let Some((parent_id, position)) = parent {
                    self.nodes
                        .get_mut(&parent_id)
                        .expect("located parent disappeared")
                        .children[position] = root;
                } else {
                    self.root = Some(root);
                }
                for id in &removed_ids {
                    self.nodes.remove(id);
                }
                ("replace", staged, removed_ids.len() as u64, scanned)
            }
        };
        Ok(ApplyFacts {
            kind,
            staged,
            removed,
            live: self.nodes.len() as u64,
            scanned,
            validate_ns,
            apply_ns: elapsed_ns(apply_started),
        })
    }

    fn subtree_ids(&self, root: u64) -> Result<HashSet<u64>, String> {
        let mut found = HashSet::new();
        let mut pending = vec![root];
        while let Some(id) = pending.pop() {
            if !found.insert(id) {
                return Err(format!("cycle in mounted tree at node {id}"));
            }
            let node = self
                .nodes
                .get(&id)
                .ok_or_else(|| format!("replacement target {id} is missing"))?;
            pending.extend(node.children.iter().copied());
        }
        Ok(found)
    }

    fn matches(&self, locator: &Locator) -> Vec<u64> {
        self.nodes
            .values()
            .filter_map(|node| match (locator, &node.kind) {
                (Locator::Text(expected), NodeKind::Text(actual)) if expected == actual => {
                    Some(node.id)
                }
                (Locator::ButtonName(expected), NodeKind::Button { name }) if expected == name => {
                    Some(node.id)
                }
                _ => None,
            })
            .collect()
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
    let mut graph = MountedGraph::default();
    let cycle_started = Instant::now();
    let roc_started = Instant::now();
    unsafe { roc_gui_init() };
    let roc_ns = elapsed_ns(roc_started);
    let patch = take_patch();
    let facts = graph.apply(patch)?;
    record_cycle(run_id, 0, "init", cycle_started, roc_ns, &facts);

    let mut marked = spec.benchmark.is_none();
    let mut cycle_ordinal = 1u64;
    for (ordinal, step) in spec.steps.iter().enumerate() {
        let role = match &step.command {
            Command::MarkMetrics => "boundary",
            command if command.is_operation() && marked => "operation",
            command if command.is_operation() => "setup",
            _ => "assertion",
        };
        let step_started = Instant::now();
        let result = match &step.command {
            Command::MarkMetrics => {
                marked = true;
                Ok(())
            }
            Command::Click(locator) => {
                let matches = graph.matches(locator);
                if matches.len() != 1 {
                    Err(format!(
                        "line {}: click locator matched {} nodes; expected exactly one",
                        step.line,
                        matches.len()
                    ))
                } else {
                    let cycle_started = Instant::now();
                    let roc_started = Instant::now();
                    let patch = dispatch(matches[0]);
                    let roc_ns = elapsed_ns(roc_started);
                    let facts = graph.apply(patch)?;
                    record_cycle(
                        run_id,
                        cycle_ordinal,
                        "click",
                        cycle_started,
                        roc_ns,
                        &facts,
                    );
                    cycle_ordinal += 1;
                    Ok(())
                }
            }
            Command::ExpectVisible(locator) => {
                let count = graph.matches(locator).len();
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
                let count = graph.matches(locator).len();
                if count == 0 {
                    Ok(())
                } else {
                    Err(format!(
                        "line {}: expected locator not to be visible, but it matched {count} nodes",
                        step.line
                    ))
                }
            }
        };
        let measured = matches!(role, "operation");
        let diagnostic = result.as_ref().err().cloned();
        observatory::step(StepResult {
            run_id,
            ordinal,
            source_line: step.line,
            kind: step.command.kind(),
            role,
            status: if result.is_ok() { "pass" } else { "fail" },
            duration_ns: measured.then(|| elapsed_ns(step_started)),
            diagnostic,
        });
        result?;
    }
    Ok(())
}

fn record_cycle(
    run_id: i64,
    ordinal: u64,
    trigger: &'static str,
    cycle_started: Instant,
    roc_callback_ns: u64,
    facts: &ApplyFacts,
) {
    observatory::cycle(Cycle {
        run_id,
        ordinal,
        trigger,
        patch_kind: facts.kind,
        duration_ns: elapsed_ns(cycle_started),
        roc_callback_ns,
        validate_ns: facts.validate_ns,
        apply_ns: facts.apply_ns,
        staged_nodes: facts.staged,
        removed_nodes: facts.removed,
        live_nodes: facts.live,
        parent_nodes_scanned: facts.scanned,
    });
}

fn elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}
