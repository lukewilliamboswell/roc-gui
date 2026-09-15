use crate::roc_platform_abi::{
    MountOrNoChangeOrReplace, MountOrNoChangeOrReplaceTag, RocErasedCallable,
};
use std::collections::{HashMap, HashSet};
use std::time::Instant;

// A realistic row can lower to several host nodes. Keep a finite corruption /
// runaway guard, but do not make the common 10k + 1k collection workload fail
// merely because labelled controls multiply its node count.
const MAX_STAGED_NODES: usize = 1_048_576;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NodeKind {
    Button { name: String },
    Column,
    Row,
    Text(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Node {
    pub id: u64,
    pub kind: NodeKind,
    pub children: Vec<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Patch {
    Mount {
        root: u64,
        nodes: Vec<Node>,
    },
    NoChange,
    Replace {
        old_root: u64,
        root: u64,
        nodes: Vec<Node>,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApplyFacts {
    pub kind: &'static str,
    pub staged: u64,
    pub removed: u64,
    pub live: u64,
    pub scanned: u64,
    pub validate_ns: u64,
    pub apply_ns: u64,
}

#[derive(Debug)]
pub struct GraphApply {
    pub facts: ApplyFacts,
    pub root: Option<u64>,
    pub staged_ids: Vec<u64>,
    pub removed_ids: Vec<u64>,
    pub parent: Option<(u64, usize)>,
}

/// The canonical mounted UI graph. Both semantic specs and the GPUI runtime
/// apply patches here; GPUI entities are only a materialized view of this state.
#[derive(Default)]
pub struct MountedGraph {
    nodes: HashMap<u64, Node>,
    parents: HashMap<u64, (u64, usize)>,
    root: Option<u64>,
}

impl MountedGraph {
    pub fn node(&self, id: u64) -> Option<&Node> {
        self.nodes.get(&id)
    }

    /// Nodes in production child order, suitable for semantic ordering checks.
    pub fn nodes_preorder(&self) -> Vec<&Node> {
        let mut ordered = Vec::with_capacity(self.nodes.len());
        let mut pending = self.root.into_iter().collect::<Vec<_>>();
        while let Some(id) = pending.pop() {
            let node = self.nodes.get(&id).expect("mounted child is missing");
            ordered.push(node);
            pending.extend(node.children.iter().rev().copied());
        }
        ordered
    }

    #[cfg(test)]
    fn root(&self) -> Option<u64> {
        self.root
    }

    pub fn apply(&mut self, patch: Patch) -> Result<GraphApply, String> {
        self.apply_inner::<false>(patch)
    }

    pub fn apply_measured(&mut self, patch: Patch) -> Result<GraphApply, String> {
        self.apply_inner::<true>(patch)
    }

    fn apply_inner<const MEASURE: bool>(&mut self, patch: Patch) -> Result<GraphApply, String> {
        let validate_started = MEASURE.then(Instant::now);
        match &patch {
            Patch::Mount { root, nodes } | Patch::Replace { root, nodes, .. } => {
                validate_tree(*root, nodes)?;
            }
            Patch::NoChange => {}
        }
        let validate_ns = validate_started.map(elapsed_ns).unwrap_or(0);
        let apply_started = MEASURE.then(Instant::now);

        let (kind, root, staged_ids, removed_ids, parent, scanned) = match patch {
            Patch::NoChange => ("no_change", None, vec![], vec![], None, 0),
            Patch::Mount { root, nodes } => {
                if !self.nodes.is_empty() {
                    return Err("application attempted to mount twice".into());
                }
                let staged_ids = nodes.iter().map(|node| node.id).collect();
                self.parents.extend(parent_entries(&nodes));
                self.nodes
                    .extend(nodes.into_iter().map(|node| (node.id, node)));
                self.root = Some(root);
                ("mount", Some(root), staged_ids, vec![], None, 0)
            }
            Patch::Replace {
                old_root,
                root,
                nodes,
            } => {
                let removed_ids = self.subtree_ids(old_root)?.into_iter().collect::<Vec<_>>();
                if nodes.iter().any(|node| self.nodes.contains_key(&node.id)) {
                    return Err("replacement reused a live node id".into());
                }
                let parent = self.parents.get(&old_root).copied();
                let scanned = u64::from(parent.is_some());
                let replacing_root = self.root == Some(old_root);
                if parent.is_none() && !replacing_root {
                    return Err("replacement target is detached".into());
                }
                let staged_ids = nodes.iter().map(|node| node.id).collect();
                self.parents.extend(parent_entries(&nodes));
                self.nodes
                    .extend(nodes.into_iter().map(|node| (node.id, node)));
                if let Some((parent_id, position)) = parent {
                    self.nodes
                        .get_mut(&parent_id)
                        .expect("located parent disappeared")
                        .children[position] = root;
                    self.parents.insert(root, (parent_id, position));
                } else {
                    self.root = Some(root);
                }
                for id in &removed_ids {
                    self.nodes.remove(id);
                    self.parents.remove(id);
                }
                (
                    "replace",
                    Some(root),
                    staged_ids,
                    removed_ids,
                    parent,
                    scanned,
                )
            }
        };
        let facts = ApplyFacts {
            kind,
            staged: staged_ids.len() as u64,
            removed: removed_ids.len() as u64,
            live: self.nodes.len() as u64,
            scanned,
            validate_ns,
            apply_ns: apply_started.map(elapsed_ns).unwrap_or(0),
        };
        Ok(GraphApply {
            facts,
            root,
            staged_ids,
            removed_ids,
            parent,
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
}

fn parent_entries(nodes: &[Node]) -> impl Iterator<Item = (u64, (u64, usize))> + '_ {
    nodes.iter().flat_map(|node| {
        node.children
            .iter()
            .enumerate()
            .map(move |(position, child)| (*child, (node.id, position)))
    })
}

fn elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Commit {
    Mount { root: u64 },
    NoChange,
    Replace { old_root: u64, root: u64 },
}

pub struct BridgeState {
    pub dispatcher: Option<RocErasedCallable>,
    pub pending: Option<Patch>,
    next_node_id: u64,
    staged: Vec<Node>,
}

impl BridgeState {
    pub const fn new() -> Self {
        Self {
            dispatcher: None,
            pending: None,
            next_node_id: 1,
            staged: Vec::new(),
        }
    }

    pub fn stage_node(&mut self, kind: NodeKind, children: Vec<u64>) -> Result<u64, String> {
        if self.pending.is_some() {
            return Err("Roc built a node before the previous patch was consumed".into());
        }
        if self.staged.len() >= MAX_STAGED_NODES {
            return Err(format!("native subtree exceeds {MAX_STAGED_NODES} nodes"));
        }

        let staged_start = self.staged.first().map(|node| node.id);
        if let Some(child) = children.iter().find(|child| {
            !staged_start.is_some_and(|start| start <= **child && **child < self.next_node_id)
        }) {
            return Err(format!("new node references unstaged child {child}"));
        }

        let id = self.next_node_id;
        self.next_node_id = id
            .checked_add(1)
            .ok_or_else(|| "native node id space exhausted".to_string())?;
        self.staged.push(Node { id, kind, children });
        Ok(id)
    }

    pub fn commit(&mut self, commit: Commit) -> Result<(), String> {
        if self.pending.is_some() {
            return Err("Roc emitted two patches in one dispatch".into());
        }

        let patch = match commit {
            Commit::NoChange => {
                if !self.staged.is_empty() {
                    return Err("NoChange followed staged node creation".into());
                }
                Patch::NoChange
            }
            Commit::Mount { root } => Patch::Mount {
                root,
                nodes: std::mem::take(&mut self.staged),
            },
            Commit::Replace { old_root, root } => Patch::Replace {
                old_root,
                root,
                nodes: std::mem::take(&mut self.staged),
            },
        };
        self.pending = Some(patch);
        Ok(())
    }
}

pub fn decode_commit(patch: &MountOrNoChangeOrReplace) -> Commit {
    unsafe {
        match patch.tag {
            MountOrNoChangeOrReplaceTag::Mount => Commit::Mount {
                root: patch.borrow_payload_mount_unchecked().root,
            },
            MountOrNoChangeOrReplaceTag::NoChange => Commit::NoChange,
            MountOrNoChangeOrReplaceTag::Replace => {
                let value = patch.borrow_payload_replace_unchecked();
                Commit::Replace {
                    old_root: value.old_root,
                    root: value.root,
                }
            }
        }
    }
}

pub fn validate_tree(root: u64, nodes: &[Node]) -> Result<(), String> {
    if root == 0 {
        return Err("node id 0 is reserved".into());
    }
    if nodes.len() > MAX_STAGED_NODES {
        return Err(format!("native subtree exceeds {MAX_STAGED_NODES} nodes"));
    }

    let mut ids = HashSet::with_capacity(nodes.len());
    for node in nodes {
        if node.id == 0 {
            return Err("node id 0 is reserved".into());
        }
        if !ids.insert(node.id) {
            return Err(format!("duplicate node id {}", node.id));
        }
    }
    if !ids.contains(&root) {
        return Err(format!("subtree root {root} is missing"));
    }

    let by_id: HashMap<_, _> = nodes.iter().map(|node| (node.id, node)).collect();
    let mut parents = HashSet::new();
    for node in nodes {
        match node.kind {
            NodeKind::Text(_) if !node.children.is_empty() => {
                return Err(format!("text node {} has children", node.id));
            }
            NodeKind::Button { .. } if node.children.len() != 1 => {
                return Err(format!("button node {} must have one label child", node.id));
            }
            _ => {}
        }
        for child in &node.children {
            if !by_id.contains_key(child) {
                return Err(format!("node {} references missing child {child}", node.id));
            }
            if !parents.insert(*child) {
                return Err(format!("node {child} has more than one parent"));
            }
        }
    }
    if parents.contains(&root) {
        return Err(format!("subtree root {root} has a parent"));
    }
    if parents.len() + 1 != nodes.len() {
        return Err("native subtree is disconnected".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(id: u64, value: &str) -> Node {
        Node {
            id,
            kind: NodeKind::Text(value.into()),
            children: vec![],
        }
    }

    #[test]
    fn validates_a_small_tree() {
        let nodes = vec![
            text(2, "hello"),
            Node {
                id: 1,
                kind: NodeKind::Column,
                children: vec![2],
            },
        ];
        assert_eq!(validate_tree(1, &nodes), Ok(()));
    }

    #[test]
    fn rejects_duplicate_and_disconnected_nodes() {
        assert!(
            validate_tree(1, &[text(1, "a"), text(1, "b")])
                .unwrap_err()
                .contains("duplicate")
        );
        assert!(
            validate_tree(1, &[text(1, "a"), text(2, "b")])
                .unwrap_err()
                .contains("disconnected")
        );
    }

    #[test]
    fn rejects_bad_button_shape() {
        let nodes = [Node {
            id: 1,
            kind: NodeKind::Button { name: "bad".into() },
            children: vec![],
        }];
        assert!(validate_tree(1, &nodes).unwrap_err().contains("one label"));
    }

    #[test]
    fn stages_bottom_up_and_commits_a_tree() {
        let mut bridge = BridgeState::new();
        let label = bridge
            .stage_node(NodeKind::Text("click".into()), vec![])
            .unwrap();
        let button = bridge
            .stage_node(
                NodeKind::Button {
                    name: "Click".into(),
                },
                vec![label],
            )
            .unwrap();
        let root = bridge.stage_node(NodeKind::Column, vec![button]).unwrap();

        bridge.commit(Commit::Mount { root }).unwrap();
        assert_eq!(
            bridge.pending.take(),
            Some(Patch::Mount {
                root,
                nodes: vec![
                    text(label, "click"),
                    Node {
                        id: button,
                        kind: NodeKind::Button {
                            name: "Click".into()
                        },
                        children: vec![label],
                    },
                    Node {
                        id: root,
                        kind: NodeKind::Column,
                        children: vec![button],
                    },
                ],
            })
        );
    }

    #[test]
    fn node_ids_are_fresh_across_transactions() {
        let mut bridge = BridgeState::new();
        let first = bridge
            .stage_node(NodeKind::Text("first".into()), vec![])
            .unwrap();
        bridge.commit(Commit::Mount { root: first }).unwrap();
        bridge.pending.take();

        let second = bridge
            .stage_node(NodeKind::Text("second".into()), vec![])
            .unwrap();
        assert!(second > first);
        bridge
            .commit(Commit::Replace {
                old_root: first,
                root: second,
            })
            .unwrap();
    }

    #[test]
    fn rejects_unstaged_children_and_dirty_no_change() {
        let mut bridge = BridgeState::new();
        assert!(
            bridge
                .stage_node(NodeKind::Button { name: "Bad".into() }, vec![999])
                .unwrap_err()
                .contains("unstaged child")
        );

        bridge
            .stage_node(NodeKind::Text("unused".into()), vec![])
            .unwrap();
        assert!(
            bridge
                .commit(Commit::NoChange)
                .unwrap_err()
                .contains("staged node")
        );
    }

    #[test]
    fn canonical_graph_reports_and_applies_nested_replacement() {
        let mut graph = MountedGraph::default();
        let mounted = graph
            .apply(Patch::Mount {
                root: 3,
                nodes: vec![
                    text(1, "old"),
                    Node {
                        id: 2,
                        kind: NodeKind::Row,
                        children: vec![1],
                    },
                    Node {
                        id: 3,
                        kind: NodeKind::Column,
                        children: vec![2],
                    },
                ],
            })
            .unwrap();
        assert_eq!(mounted.facts.kind, "mount");
        assert_eq!(mounted.facts.live, 3);
        assert_eq!(graph.root(), Some(3));

        let replaced = graph
            .apply(Patch::Replace {
                old_root: 2,
                root: 5,
                nodes: vec![
                    text(4, "new"),
                    Node {
                        id: 5,
                        kind: NodeKind::Row,
                        children: vec![4],
                    },
                ],
            })
            .unwrap();
        assert_eq!(replaced.facts.kind, "replace");
        assert_eq!(replaced.facts.staged, 2);
        assert_eq!(replaced.facts.removed, 2);
        assert_eq!(replaced.facts.live, 3);
        assert_eq!(replaced.facts.scanned, 1);
        assert_eq!(replaced.parent, Some((3, 0)));
        assert_eq!(graph.node(3).unwrap().children, vec![5]);
        assert!(graph.node(1).is_none());
        assert!(graph.node(2).is_none());

        let replaced_again = graph
            .apply(Patch::Replace {
                old_root: 4,
                root: 6,
                nodes: vec![text(6, "newer")],
            })
            .unwrap();
        assert_eq!(replaced_again.parent, Some((5, 0)));
        assert_eq!(replaced_again.facts.scanned, 1);
        assert_eq!(graph.node(5).unwrap().children, vec![6]);
    }
}
