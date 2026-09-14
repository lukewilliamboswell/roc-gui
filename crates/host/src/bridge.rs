use crate::roc_platform_abi::{
    AnonStruct257fafdaa0a9c26e, ButtonOrColumnOrRowOrTextTag, MountOrNoChangeOrReplace,
    MountOrNoChangeOrReplaceTag, RocErasedCallable,
};
use std::collections::{HashMap, HashSet};

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

pub struct BridgeState {
    pub dispatcher: Option<RocErasedCallable>,
    pub pending: Option<Patch>,
}

impl BridgeState {
    pub const fn new() -> Self {
        Self {
            dispatcher: None,
            pending: None,
        }
    }
}

fn decode_nodes(nodes: &[AnonStruct257fafdaa0a9c26e]) -> Vec<Node> {
    nodes
        .iter()
        .map(|node| {
            let kind = match node.kind.tag {
                ButtonOrColumnOrRowOrTextTag::Button => NodeKind::Button,
                ButtonOrColumnOrRowOrTextTag::Column => NodeKind::Column,
                ButtonOrColumnOrRowOrTextTag::Row => NodeKind::Row,
                ButtonOrColumnOrRowOrTextTag::Text => {
                    let text = unsafe { node.kind.borrow_payload_text_unchecked() };
                    NodeKind::Text(text.as_str().to_owned())
                }
            };
            Node {
                id: node.id,
                kind,
                children: node.children.as_slice().to_vec(),
            }
        })
        .collect()
}

pub fn decode_patch(patch: &MountOrNoChangeOrReplace) -> Patch {
    unsafe {
        match patch.tag {
            MountOrNoChangeOrReplaceTag::Mount => {
                let value = patch.borrow_payload_mount_unchecked();
                Patch::Mount {
                    root: value.root,
                    nodes: decode_nodes(value.nodes.as_slice()),
                }
            }
            MountOrNoChangeOrReplaceTag::NoChange => Patch::NoChange,
            MountOrNoChangeOrReplaceTag::Replace => {
                let value = patch.borrow_payload_replace_unchecked();
                Patch::Replace {
                    old_root: value.old_root,
                    root: value.root,
                    nodes: decode_nodes(value.nodes.as_slice()),
                }
            }
        }
    }
}

pub fn validate_tree(root: u64, nodes: &[Node]) -> Result<(), String> {
    if root == 0 {
        return Err("node id 0 is reserved".into());
    }
    if nodes.len() > 65_536 {
        return Err("native subtree exceeds 65536 nodes".into());
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
}
