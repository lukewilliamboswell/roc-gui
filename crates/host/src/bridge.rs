use crate::roc_platform_abi::{
    MountOrNoChangeOrReplace, MountOrNoChangeOrReplaceTag, RocErasedCallable,
};
use std::collections::{HashMap, HashSet};

const MAX_STAGED_NODES: usize = 65_536;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NodeKind {
    Button,
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
            Commit::Mount { root } => {
                validate_tree(root, &self.staged)?;
                Patch::Mount {
                    root,
                    nodes: std::mem::take(&mut self.staged),
                }
            }
            Commit::Replace { old_root, root } => {
                validate_tree(root, &self.staged)?;
                Patch::Replace {
                    old_root,
                    root,
                    nodes: std::mem::take(&mut self.staged),
                }
            }
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
            NodeKind::Button if node.children.len() != 1 => {
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
            kind: NodeKind::Button,
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
        let button = bridge.stage_node(NodeKind::Button, vec![label]).unwrap();
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
                        kind: NodeKind::Button,
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
                .stage_node(NodeKind::Button, vec![999])
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
}
