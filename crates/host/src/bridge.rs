use crate::roc_platform_abi::{
    MountOrNoChangeOrReplace, MountOrNoChangeOrReplaceTag, RocErasedCallable,
};
use std::collections::{HashMap, HashSet};
use std::hash::{BuildHasherDefault, Hasher};
use std::time::Instant;

// A realistic row can lower to several host nodes. Keep a finite corruption /
// runaway guard, but do not make the common 10k + 1k collection workload fail
// merely because labelled controls multiply its node count.
const MAX_STAGED_NODES: usize = 1_048_576;

/// Node IDs are monotonically allocated by `BridgeState`, so hashing them with
/// SipHash adds work without providing collision resistance. Keep the generic
/// validator on the standard hasher for arbitrary test input; mounted IDs use
/// a cheap integer mixer instead of a keyed general-purpose hasher.
#[derive(Default)]
struct NodeIdHasher(u64);

impl Hasher for NodeIdHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        // `u64::hash` calls `write_u64`; this fallback keeps the implementation
        // total if the key representation changes in future.
        self.0 = bytes.iter().fold(0xcbf29ce484222325, |hash, byte| {
            (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
        });
    }

    fn write_u64(&mut self, value: u64) {
        // Multiplication spreads sequential IDs across both the bucket bits and
        // hashbrown's high-bit fingerprints; identity hashing would give every
        // small ID the same fingerprint.
        self.0 = value.wrapping_mul(0x9e3779b97f4a7c15);
    }
}

type NodeMap<V> = HashMap<u64, V, BuildHasherDefault<NodeIdHasher>>;
type NodeSet = HashSet<u64, BuildHasherDefault<NodeIdHasher>>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NodeKind {
    Canvas {
        label: String,
        primitives: Vec<CanvasPrimitive>,
        style: Style,
    },
    Button {
        caption: String,
        label: String,
        enabled: bool,
        style: Style,
    },
    Checkbox {
        label: String,
        checked: bool,
        enabled: bool,
        /// The indicator's own colours, each None for the host's default.
        indicator: CheckboxIndicator,
        style: Style,
    },
    Textarea {
        label: String,
        value: String,
        placeholder: String,
        enabled: bool,
        read_only: bool,
        style: Style,
    },
    Image {
        label: String,
        bytes: Vec<u8>,
        format: ImageFormat,
        fit: ImageFit,
        grayscale: bool,
        style: Style,
    },
    Column {
        label: String,
        style: Style,
    },
    Dialog {
        label: String,
        style: Style,
    },
    Panel {
        label: String,
        style: Style,
    },
    Row {
        label: String,
        style: Style,
    },
    Scroll {
        name: String,
        axis: ScrollAxis,
    },
    VirtualItem {
        key: u64,
    },
    VirtualList {
        name: String,
        row_height: u32,
    },
    TextInput {
        label: String,
        value: String,
        placeholder: String,
        enabled: bool,
        style: Style,
    },
    Text(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CanvasPrimitive {
    pub kind: CanvasPrimitiveKind,
    pub key: u64,
    pub label: String,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub x2: i32,
    pub y2: i32,
    pub fill: Option<u32>,
    pub stroke: Option<u32>,
    pub stroke_width: u32,
    pub radius: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CanvasPrimitiveKind {
    Ellipse,
    Line,
    Rectangle,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ControlKey {
    Enter,
    Escape,
    Space,
}

impl NodeKind {
    pub fn accepts_key(&self, key: ControlKey) -> bool {
        matches!(
            (self, key),
            (
                Self::Button { enabled: true, .. },
                ControlKey::Enter | ControlKey::Space
            ) | (Self::Checkbox { enabled: true, .. }, ControlKey::Space)
                | (Self::Dialog { .. }, ControlKey::Escape)
        )
    }

    /// Whether a pointer press on this control takes keyboard focus rather
    /// than activating it. Text entry behaves this way.
    pub fn focuses_on_pointer(&self) -> bool {
        matches!(
            self,
            Self::TextInput { enabled: true, .. } | Self::Textarea { enabled: true, .. }
        )
    }

    /// Whether this control accepts pointer activation.
    ///
    /// The production render path attaches a click handler only to enabled
    /// controls, so a simulated click must honour the same condition.
    pub fn accepts_pointer(&self) -> bool {
        matches!(
            self,
            Self::Button { enabled: true, .. }
                | Self::Checkbox { enabled: true, .. }
                | Self::TextInput { enabled: true, .. }
                | Self::Textarea { enabled: true, .. }
                | Self::Canvas { .. }
        )
    }

    pub fn focus_identity(&self) -> Option<(u8, String)> {
        match self {
            Self::Button {
                label,
                enabled: true,
                ..
            } => Some((0, label.clone())),
            Self::Checkbox {
                label,
                enabled: true,
                ..
            } => Some((1, label.clone())),
            Self::Textarea {
                label,
                enabled: true,
                read_only: false,
                ..
            } => Some((2, label.clone())),
            Self::TextInput {
                label,
                enabled: true,
                ..
            } => Some((3, label.clone())),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Length {
    Auto,
    Fill,
    Px(u32),
}

impl Default for Length {
    fn default() -> Self {
        Self::Auto
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Overflow {
    Visible,
    Clip,
    Scroll,
}

impl Default for Overflow {
    fn default() -> Self {
        Self::Visible
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScrollAxis {
    Vertical,
    Horizontal,
    Both,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImageFormat {
    Bmp,
    Gif,
    Jpeg,
    Png,
    Svg,
    Tiff,
    Webp,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImageFit {
    Contain,
    Cover,
    Fill,
    None,
    ScaleDown,
}

/// Where a container places its children across its layout axis.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Align {
    /// The element's own native alignment.
    #[default]
    Native,
    Start,
    Center,
    End,
    Baseline,
    Stretch,
}

/// How a container distributes its children along its layout axis.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Justify {
    /// The element's own native distribution.
    #[default]
    Native,
    Start,
    Center,
    End,
    Between,
    Around,
}

/// The checkbox indicator's colours. `fg` reaches the caption; these reach the
/// box and its mark, which otherwise keep host values chosen for a dark ground.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CheckboxIndicator {
    pub box_bg: Option<u32>,
    pub box_checked_bg: Option<u32>,
    pub box_border: Option<u32>,
    pub mark_color: Option<u32>,
}

/// How a string behaves when it is wider than the space it was given.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum TextOverflow {
    #[default]
    Wrap,
    NoWrap,
    Ellipsis,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Style {
    pub gap: u32,
    /// Top, right, bottom, left, already resolved from the shorthand.
    pub padding: [u32; 4],
    pub width: Length,
    pub height: Length,
    /// Floors and ceilings for the two sides. A fixed length is otherwise a
    /// shrinkable basis, so a sibling's overflow can squeeze it.
    pub min_width: Length,
    pub min_height: Length,
    pub max_width: Length,
    pub max_height: Length,
    pub grow: bool,
    pub bg: Option<u32>,
    pub hover_bg: Option<u32>,
    pub active_bg: Option<u32>,
    pub disabled_bg: Option<u32>,
    pub disabled_fg: Option<u32>,
    pub focus_color: Option<u32>,
    pub fg: Option<u32>,
    pub border_color: Option<u32>,
    /// Top, right, bottom, left, already resolved from the shorthand.
    pub border_width: [u32; 4],
    pub radius: u32,
    pub font_size: u32,
    pub font_weight: u32,
    pub text_overflow: TextOverflow,
    pub overflow_x: Overflow,
    pub overflow_y: Overflow,
    pub align: Align,
    pub justify: Justify,
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
    pub retired_root: bool,
    pub parent: Option<(u64, usize)>,
}

/// The canonical mounted UI graph. Both semantic specs and the GPUI runtime
/// apply patches here; GPUI entities are only a materialized view of this state.
#[derive(Default)]
pub struct MountedGraph {
    nodes: NodeMap<MountedNode>,
    root: Option<u64>,
    max_seen_node_id: u64,
}

struct MountedNode {
    node: Node,
    parent: Option<(u64, usize)>,
}

impl MountedGraph {
    pub fn node(&self, id: u64) -> Option<&Node> {
        self.nodes.get(&id).map(|entry| &entry.node)
    }

    /// Nodes in production child order, suitable for semantic ordering checks.
    pub fn nodes_preorder(&self) -> Vec<&Node> {
        let mut ordered = Vec::with_capacity(self.nodes.len());
        let mut pending = self.root.into_iter().collect::<Vec<_>>();
        while let Some(id) = pending.pop() {
            let node = &self.nodes.get(&id).expect("mounted child is missing").node;
            ordered.push(node);
            pending.extend(node.children.iter().rev().copied());
        }
        ordered
    }

    pub fn active_dialog(&self) -> Option<u64> {
        self.nodes_preorder()
            .into_iter()
            .find_map(|node| matches!(node.kind, NodeKind::Dialog { .. }).then_some(node.id))
    }

    pub fn is_descendant_of(&self, mut id: u64, ancestor: u64) -> bool {
        loop {
            if id == ancestor {
                return true;
            }
            match self
                .nodes
                .get(&id)
                .and_then(|entry| entry.parent.map(|value| value.0))
            {
                Some(parent) => id = parent,
                None => return false,
            }
        }
    }

    /// Every scrolling or virtual-list ancestor of `id`, nearest first.
    ///
    /// A node inside a scroll region is laid out whether or not it is scrolled
    /// into view, so deciding visibility means clipping against these.
    pub fn scroll_ancestors(&self, id: u64) -> Vec<u64> {
        let mut found = Vec::new();
        let mut current = self.nodes.get(&id).and_then(|entry| entry.parent);
        while let Some(parent) = current {
            let Some(entry) = self.nodes.get(&parent.0) else {
                break;
            };
            if matches!(
                entry.node.kind,
                NodeKind::Scroll { .. } | NodeKind::VirtualList { .. }
            ) {
                found.push(parent.0);
            }
            current = entry.parent;
        }
        found
    }

    pub fn first_focusable_in(&self, ancestor: u64) -> Option<u64> {
        self.nodes_preorder().into_iter().find_map(|node| {
            (self.is_descendant_of(node.id, ancestor) && node.kind.focus_identity().is_some())
                .then_some(node.id)
        })
    }

    pub fn find_focus_identity(&self, identity: &(u8, String)) -> Option<u64> {
        self.nodes_preorder().into_iter().find_map(|node| {
            (node.kind.focus_identity().as_ref() == Some(identity)).then_some(node.id)
        })
    }

    /// IDs below virtual-list nodes. They remain in the canonical graph for
    /// semantic lookup and routing but do not receive eager GPUI entities.
    pub fn virtual_descendant_ids(&self) -> HashSet<u64> {
        let mut result = HashSet::new();
        for entry in self.nodes.values() {
            if matches!(entry.node.kind, NodeKind::VirtualList { .. }) {
                let mut pending = entry.node.children.clone();
                while let Some(id) = pending.pop() {
                    if result.insert(id) {
                        if let Some(child) = self.nodes.get(&id) {
                            pending.extend(child.node.children.iter().copied());
                        }
                    }
                }
            }
        }
        result
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
        if let Patch::Replace {
            old_root, nodes, ..
        } = &patch
        {
            let retained_dialogs = self
                .nodes
                .values()
                .filter(|entry| matches!(entry.node.kind, NodeKind::Dialog { .. }))
                .filter(|entry| !self.is_descendant_of(entry.node.id, *old_root))
                .count();
            let new_dialogs = nodes
                .iter()
                .filter(|node| matches!(node.kind, NodeKind::Dialog { .. }))
                .count();
            if retained_dialogs + new_dialogs > 1 {
                return Err("mounted graph would contain more than one modal dialog".into());
            }
            let mut input_labels = self
                .nodes
                .values()
                .filter(|entry| !self.is_descendant_of(entry.node.id, *old_root))
                .filter_map(|entry| match &entry.node.kind {
                    NodeKind::TextInput { label, .. } => Some(label.clone()),
                    _ => None,
                })
                .collect::<HashSet<_>>();
            for label in nodes.iter().filter_map(|node| match &node.kind {
                NodeKind::TextInput { label, .. } => Some(label),
                _ => None,
            }) {
                if !input_labels.insert(label.clone()) {
                    return Err(format!(
                        "mounted graph contains duplicate text input label {label:?}"
                    ));
                }
            }
        }
        let validate_ns = validate_started.map(elapsed_ns).unwrap_or(0);
        let apply_started = MEASURE.then(Instant::now);

        let (kind, root, staged_ids, removed_ids, removed, retired_root, parent, scanned) =
            match patch {
                Patch::NoChange => ("no_change", None, vec![], vec![], 0, false, None, 0),
                Patch::Mount { root, nodes } => {
                    if !self.nodes.is_empty() {
                        return Err("application attempted to mount twice".into());
                    }
                    let staged_ids = nodes.iter().map(|node| node.id).collect();
                    self.insert_nodes(nodes);
                    self.root = Some(root);
                    ("mount", Some(root), staged_ids, vec![], 0, false, None, 0)
                }
                Patch::Replace {
                    old_root,
                    root,
                    nodes,
                } => {
                    let replacing_root = self.root == Some(old_root);
                    let (removed_ids, removed) = if replacing_root {
                        (vec![], self.nodes.len() as u64)
                    } else {
                        let ids = self.subtree_ids(old_root)?.into_iter().collect::<Vec<_>>();
                        let count = ids.len() as u64;
                        (ids, count)
                    };
                    let production_fresh = contiguous_id_start(&nodes)
                        .is_some_and(|first| first > self.max_seen_node_id);
                    if !production_fresh
                        && nodes.iter().any(|node| self.nodes.contains_key(&node.id))
                    {
                        return Err("replacement reused a live node id".into());
                    }
                    let parent = self.nodes.get(&old_root).and_then(|entry| entry.parent);
                    let scanned = u64::from(parent.is_some());
                    if parent.is_none() && !replacing_root {
                        return Err("replacement target is detached".into());
                    }
                    let staged_ids = nodes.iter().map(|node| node.id).collect();
                    // Retire the old subtree before admitting its replacement. Node ids have
                    // already been checked for overlap, and removing first lets both maps reuse
                    // their existing allocation instead of briefly growing to hold two complete
                    // roots at once.
                    if replacing_root {
                        self.nodes.clear();
                    } else {
                        for id in &removed_ids {
                            self.nodes.remove(id);
                        }
                    }
                    self.insert_nodes(nodes);
                    if let Some((parent_id, position)) = parent {
                        self.nodes
                            .get_mut(&parent_id)
                            .expect("located parent disappeared")
                            .node
                            .children[position] = root;
                        self.nodes
                            .get_mut(&root)
                            .expect("replacement root disappeared")
                            .parent = Some((parent_id, position));
                    } else {
                        self.root = Some(root);
                    }
                    (
                        "replace",
                        Some(root),
                        staged_ids,
                        removed_ids,
                        removed,
                        replacing_root,
                        parent,
                        scanned,
                    )
                }
            };
        let facts = ApplyFacts {
            kind,
            staged: staged_ids.len() as u64,
            removed,
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
            retired_root,
            parent,
        })
    }

    fn subtree_ids(&self, root: u64) -> Result<NodeSet, String> {
        let mut found = NodeSet::default();
        let mut pending = vec![root];
        while let Some(id) = pending.pop() {
            if !found.insert(id) {
                return Err(format!("cycle in mounted tree at node {id}"));
            }
            let node = &self
                .nodes
                .get(&id)
                .ok_or_else(|| format!("replacement target {id} is missing"))?
                .node;
            pending.extend(node.children.iter().copied());
        }
        Ok(found)
    }

    fn insert_nodes(&mut self, nodes: Vec<Node>) {
        let mut entries = nodes
            .into_iter()
            .map(|node| MountedNode { node, parent: None })
            .collect::<Vec<_>>();

        // BridgeState allocates production node IDs contiguously and lowering
        // emits them in allocation order. Populate parent metadata directly in
        // that dense vector. Keep arbitrary hand-built patches supported by a
        // temporary index without paying for a second persistent graph map.
        let dense_base = entries.first().map(|entry| entry.node.id);
        let dense = dense_base.is_some_and(|base| {
            entries
                .iter()
                .enumerate()
                .all(|(index, entry)| base.checked_add(index as u64) == Some(entry.node.id))
        });
        if dense {
            let base = dense_base.expect("dense entries have a base");
            for parent_index in 0..entries.len() {
                let parent_id = entries[parent_index].node.id;
                for position in 0..entries[parent_index].node.children.len() {
                    let child = entries[parent_index].node.children[position];
                    let child_index = usize::try_from(child - base)
                        .expect("validated dense child index fits usize");
                    entries[child_index].parent = Some((parent_id, position));
                }
            }
        } else {
            let indices = entries
                .iter()
                .enumerate()
                .map(|(index, entry)| (entry.node.id, index))
                .collect::<NodeMap<_>>();
            for parent_index in 0..entries.len() {
                let parent_id = entries[parent_index].node.id;
                for position in 0..entries[parent_index].node.children.len() {
                    let child = entries[parent_index].node.children[position];
                    let child_index = indices[&child];
                    entries[child_index].parent = Some((parent_id, position));
                }
            }
        }

        let inserted_max = entries.iter().map(|entry| entry.node.id).max().unwrap_or(0);
        self.nodes
            .extend(entries.into_iter().map(|entry| (entry.node.id, entry)));
        self.max_seen_node_id = self.max_seen_node_id.max(inserted_max);
    }
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
    pub task_dispatcher: Option<RocErasedCallable>,
    pub pending: Option<Patch>,
    next_node_id: u64,
    staged: Vec<Node>,
    child_builders: Vec<(u64, Vec<u64>)>,
    next_child_builder_id: u64,
}

impl BridgeState {
    pub const fn new() -> Self {
        Self {
            dispatcher: None,
            task_dispatcher: None,
            pending: None,
            next_node_id: 1,
            staged: Vec::new(),
            child_builders: Vec::new(),
            next_child_builder_id: 1,
        }
    }

    pub fn begin_children(&mut self) -> Result<u64, String> {
        if self.pending.is_some() {
            return Err("Roc began children before the previous patch was consumed".into());
        }
        if self.child_builders.len() >= MAX_STAGED_NODES {
            return Err(format!(
                "native child-builder nesting exceeds {MAX_STAGED_NODES}"
            ));
        }
        let id = self.next_child_builder_id;
        self.next_child_builder_id = id
            .checked_add(1)
            .ok_or_else(|| "child builder id space exhausted".to_string())?;
        self.child_builders.push((id, Vec::new()));
        Ok(id)
    }

    pub fn push_child(&mut self, builder: u64, child: u64) -> Result<(), String> {
        let (active, children) = self
            .child_builders
            .last_mut()
            .ok_or_else(|| format!("missing child builder {builder}"))?;
        if *active != builder {
            return Err(format!("child builder {builder} is not active"));
        }
        children.push(child);
        Ok(())
    }

    pub fn finish_children(&mut self, builder: u64) -> Result<Vec<u64>, String> {
        let (active, children) = self
            .child_builders
            .pop()
            .ok_or_else(|| format!("missing child builder {builder}"))?;
        if active != builder {
            self.child_builders.push((active, children));
            return Err(format!("child builder {builder} is not active"));
        }
        Ok(children)
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
        if !self.child_builders.is_empty() {
            return Err("Roc committed a patch with unfinished child builders".into());
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

fn validate_virtual_keys<'a>(
    list: &Node,
    mut lookup: impl FnMut(u64) -> Option<&'a Node>,
) -> Result<(), String> {
    let mut keys = HashSet::with_capacity(list.children.len());
    for child in &list.children {
        let Some(Node {
            kind: NodeKind::VirtualItem { key },
            ..
        }) = lookup(*child)
        else {
            return Err(format!(
                "virtual list node {} has a non-item child",
                list.id
            ));
        };
        if !keys.insert(*key) {
            return Err(format!(
                "virtual list node {} has duplicate item key {}",
                list.id, key
            ));
        }
    }
    Ok(())
}

pub fn validate_tree(root: u64, nodes: &[Node]) -> Result<(), String> {
    if root == 0 {
        return Err("node id 0 is reserved".into());
    }
    if nodes.len() > MAX_STAGED_NODES {
        return Err(format!("native subtree exceeds {MAX_STAGED_NODES} nodes"));
    }
    if nodes
        .iter()
        .filter(|node| matches!(node.kind, NodeKind::Dialog { .. }))
        .count()
        > 1
    {
        return Err("native subtree contains more than one modal dialog".into());
    }
    let mut input_labels = HashSet::new();
    for label in nodes.iter().filter_map(|node| match &node.kind {
        NodeKind::TextInput { label, .. } => Some(label),
        _ => None,
    }) {
        if label.is_empty() {
            return Err("text input label must not be empty".into());
        }
        if !input_labels.insert(label) {
            return Err(format!(
                "native subtree contains duplicate text input label {label:?}"
            ));
        }
    }

    // BridgeState assigns one monotonically increasing id to every staged node
    // and keeps those nodes in assignment order. Validate that production shape
    // without hashing every id. Hand-built/non-canonical patches still take the
    // general validator below, so validate_tree retains its complete contract.
    if let Some(first_id) = contiguous_id_start(nodes) {
        return validate_contiguous_tree(root, first_id, nodes);
    }

    // Keep membership and ownership in one table. Validation still runs in two
    // passes so duplicate/root errors retain precedence over shape and edge
    // errors, but edges no longer require separate id, lookup, and parent sets.
    let mut ownership = HashMap::with_capacity(nodes.len());
    for node in nodes {
        if node.id == 0 {
            return Err("node id 0 is reserved".into());
        }
        if ownership.insert(node.id, false).is_some() {
            return Err(format!("duplicate node id {}", node.id));
        }
    }
    if !ownership.contains_key(&root) {
        return Err(format!("subtree root {root} is missing"));
    }

    let mut parent_count = 0;
    for node in nodes {
        match node.kind {
            NodeKind::Text(_)
            | NodeKind::Checkbox { .. }
            | NodeKind::Button { .. }
            | NodeKind::Textarea { .. }
            | NodeKind::Image { .. }
            | NodeKind::Canvas { .. }
            | NodeKind::TextInput { .. }
                if !node.children.is_empty() =>
            {
                return Err(format!("leaf node {} has children", node.id));
            }
            NodeKind::Scroll { .. } if node.children.len() != 1 => {
                return Err(format!(
                    "scroll node {} must have one content child",
                    node.id
                ));
            }
            NodeKind::VirtualItem { .. } if node.children.len() != 1 => {
                return Err(format!(
                    "virtual item node {} must have one content child",
                    node.id
                ));
            }
            NodeKind::VirtualList { row_height, .. } if !(1..=16_384).contains(&row_height) => {
                return Err(format!(
                    "virtual list node {} has invalid row height",
                    node.id
                ));
            }
            NodeKind::VirtualList { .. } => {
                validate_virtual_keys(node, |id| nodes.iter().find(|candidate| candidate.id == id))?
            }
            _ => {}
        }
        for child in &node.children {
            match ownership.get_mut(child) {
                None => {
                    return Err(format!("node {} references missing child {child}", node.id));
                }
                Some(has_parent @ false) => {
                    *has_parent = true;
                    parent_count += 1;
                }
                Some(true) => {
                    return Err(format!("node {child} has more than one parent"));
                }
            }
        }
    }
    if ownership[&root] {
        return Err(format!("subtree root {root} has a parent"));
    }
    if parent_count + 1 != nodes.len() {
        return Err("native subtree is disconnected".into());
    }
    Ok(())
}

fn contiguous_id_start(nodes: &[Node]) -> Option<u64> {
    let first_id = nodes.first()?.id;
    if first_id == 0 {
        return None;
    }
    nodes
        .iter()
        .enumerate()
        .all(|(offset, node)| {
            u64::try_from(offset)
                .ok()
                .and_then(|offset| first_id.checked_add(offset))
                == Some(node.id)
        })
        .then_some(first_id)
}

fn validate_contiguous_tree(root: u64, first_id: u64, nodes: &[Node]) -> Result<(), String> {
    let root_index = root
        .checked_sub(first_id)
        .and_then(|offset| usize::try_from(offset).ok())
        .filter(|index| *index < nodes.len())
        .ok_or_else(|| format!("subtree root {root} is missing"))?;

    // Production staging needs one dense ownership byte per node instead of a
    // hash-table entry for every id. Bytes avoid the read/modify/write and proxy
    // cost of bit packing while remaining small beside the staged node graph.
    let mut has_parent = vec![0_u8; nodes.len()];
    let mut parent_count = 0;
    for node in nodes {
        match node.kind {
            NodeKind::Text(_)
            | NodeKind::Checkbox { .. }
            | NodeKind::Button { .. }
            | NodeKind::Textarea { .. }
            | NodeKind::Image { .. }
            | NodeKind::Canvas { .. }
            | NodeKind::TextInput { .. }
                if !node.children.is_empty() =>
            {
                return Err(format!("leaf node {} has children", node.id));
            }
            NodeKind::Scroll { .. } if node.children.len() != 1 => {
                return Err(format!(
                    "scroll node {} must have one content child",
                    node.id
                ));
            }
            NodeKind::VirtualItem { .. } if node.children.len() != 1 => {
                return Err(format!(
                    "virtual item node {} must have one content child",
                    node.id
                ));
            }
            NodeKind::VirtualList { row_height, .. } if !(1..=16_384).contains(&row_height) => {
                return Err(format!(
                    "virtual list node {} has invalid row height",
                    node.id
                ));
            }
            NodeKind::VirtualList { .. } => validate_virtual_keys(node, |id| {
                id.checked_sub(first_id)
                    .and_then(|offset| usize::try_from(offset).ok())
                    .and_then(|index| nodes.get(index))
            })?,
            _ => {}
        }
        for child in &node.children {
            let child_index = child
                .checked_sub(first_id)
                .and_then(|offset| usize::try_from(offset).ok())
                .filter(|index| *index < nodes.len())
                .ok_or_else(|| format!("node {} references missing child {child}", node.id))?;
            if std::mem::replace(&mut has_parent[child_index], 1) != 0 {
                return Err(format!("node {child} has more than one parent"));
            }
            parent_count += 1;
        }
    }
    if has_parent[root_index] != 0 {
        return Err(format!("subtree root {root} has a parent"));
    }
    if parent_count + 1 != nodes.len() {
        return Err("native subtree is disconnected".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn button(label: &str, enabled: bool) -> NodeKind {
        NodeKind::Button {
            caption: label.into(),
            label: label.into(),
            enabled,
            style: Style::default(),
        }
    }

    #[test]
    fn controls_accept_only_their_native_activation_keys() {
        let enabled_button = button("Open", true);
        assert!(enabled_button.accepts_key(ControlKey::Enter));
        assert!(enabled_button.accepts_key(ControlKey::Space));
        assert!(!button("Open", false).accepts_key(ControlKey::Enter));
        assert!(!button("Open", false).accepts_key(ControlKey::Space));

        let enabled = NodeKind::Checkbox {
            label: "Show files".into(),
            checked: false,
            enabled: true,
            indicator: CheckboxIndicator::default(),
            style: Style::default(),
        };
        let disabled = match &enabled {
            NodeKind::Checkbox {
                label,
                checked,
                style,
                ..
            } => NodeKind::Checkbox {
                label: label.clone(),
                checked: *checked,
                enabled: false,
                indicator: CheckboxIndicator::default(),
                style: *style,
            },
            _ => unreachable!(),
        };
        assert!(!enabled.accepts_key(ControlKey::Enter));
        assert!(enabled.accepts_key(ControlKey::Space));
        assert!(!disabled.accepts_key(ControlKey::Space));

        let dialog = NodeKind::Dialog {
            label: "Confirm".into(),
            style: Style::default(),
        };
        assert!(dialog.accepts_key(ControlKey::Escape));
        assert!(!dialog.accepts_key(ControlKey::Enter));
    }

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
                kind: NodeKind::Column {
                    label: String::new(),
                    style: Style::default(),
                },
                children: vec![2],
            },
        ];
        assert_eq!(validate_tree(1, &nodes), Ok(()));
    }

    #[test]
    fn rejects_more_than_one_dialog_in_a_subtree() {
        let dialog = |id| Node {
            id,
            kind: NodeKind::Dialog {
                label: format!("dialog-{id}"),
                style: Style::default(),
            },
            children: vec![],
        };
        let nodes = vec![
            dialog(2),
            dialog(3),
            Node {
                id: 1,
                kind: NodeKind::Column {
                    label: String::new(),
                    style: Style::default(),
                },
                children: vec![2, 3],
            },
        ];
        assert!(
            validate_tree(1, &nodes)
                .unwrap_err()
                .contains("more than one modal dialog")
        );
    }

    #[test]
    fn rejects_duplicate_text_input_labels_used_for_editor_identity() {
        let input = |id| Node {
            id,
            kind: NodeKind::TextInput {
                label: "Profile name".into(),
                value: String::new(),
                placeholder: String::new(),
                enabled: true,
                style: Style::default(),
            },
            children: vec![],
        };
        let nodes = vec![
            input(1),
            input(2),
            Node {
                id: 3,
                kind: NodeKind::Column {
                    label: String::new(),
                    style: Style::default(),
                },
                children: vec![1, 2],
            },
        ];
        assert!(
            validate_tree(3, &nodes)
                .unwrap_err()
                .contains("duplicate text input label")
        );
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
    fn rejects_button_children() {
        let nodes = [
            Node {
                id: 1,
                kind: button("bad", true),
                children: vec![2],
            },
            text(2, "bad"),
        ];
        assert!(validate_tree(1, &nodes).unwrap_err().contains("children"));
    }

    #[test]
    fn rejects_bad_scroll_shape() {
        let nodes = [Node {
            id: 1,
            kind: NodeKind::Scroll {
                name: "contents".into(),
                axis: ScrollAxis::Vertical,
            },
            children: vec![],
        }];
        assert!(
            validate_tree(1, &nodes)
                .unwrap_err()
                .contains("one content child")
        );
    }

    #[test]
    fn virtual_list_requires_unique_stable_item_keys() {
        let nodes = [
            text(1, "first"),
            Node {
                id: 2,
                kind: NodeKind::VirtualItem { key: 7 },
                children: vec![1],
            },
            text(3, "second"),
            Node {
                id: 4,
                kind: NodeKind::VirtualItem { key: 7 },
                children: vec![3],
            },
            Node {
                id: 5,
                kind: NodeKind::VirtualList {
                    name: "rows".into(),
                    row_height: 24,
                },
                children: vec![2, 4],
            },
        ];
        assert!(
            validate_tree(5, &nodes)
                .unwrap_err()
                .contains("duplicate item key 7")
        );
    }

    #[test]
    fn virtual_descendants_remain_logical_without_eager_views() {
        let mut graph = MountedGraph::default();
        let nodes = vec![
            text(1, "row"),
            Node {
                id: 2,
                kind: NodeKind::VirtualItem { key: 11 },
                children: vec![1],
            },
            Node {
                id: 3,
                kind: NodeKind::VirtualList {
                    name: "rows".into(),
                    row_height: 24,
                },
                children: vec![2],
            },
        ];
        graph.apply(Patch::Mount { root: 3, nodes }).unwrap();
        assert_eq!(graph.nodes_preorder().len(), 3);
        assert_eq!(graph.virtual_descendant_ids(), HashSet::from([1, 2]));
    }

    #[test]
    fn validation_preserves_edge_and_ownership_errors() {
        assert_eq!(
            validate_tree(
                1,
                &[
                    Node {
                        id: 1,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![2],
                    },
                    text(2, "child"),
                    Node {
                        id: 3,
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![2],
                    },
                ],
            ),
            Err("node 2 has more than one parent".into())
        );
        assert_eq!(
            validate_tree(
                1,
                &[Node {
                    id: 1,
                    kind: NodeKind::Column {
                        label: String::new(),
                        style: Style::default()
                    },
                    children: vec![99],
                }],
            ),
            Err("node 1 references missing child 99".into())
        );
        assert_eq!(
            validate_tree(
                1,
                &[
                    Node {
                        id: 1,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![2],
                    },
                    Node {
                        id: 2,
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![1],
                    },
                ],
            ),
            Err("subtree root 1 has a parent".into())
        );
    }

    #[test]
    fn validation_preserves_id_and_shape_error_precedence() {
        assert_eq!(validate_tree(0, &[]), Err("node id 0 is reserved".into()));
        assert_eq!(
            validate_tree(7, &[text(1, "only")]),
            Err("subtree root 7 is missing".into())
        );
        assert_eq!(
            validate_tree(
                1,
                &[
                    text(1, "first"),
                    Node {
                        id: 1,
                        kind: NodeKind::Text("duplicate with child".into()),
                        children: vec![99],
                    },
                ],
            ),
            Err("duplicate node id 1".into())
        );
        assert_eq!(
            validate_tree(
                1,
                &[Node {
                    id: 1,
                    kind: NodeKind::Text("bad".into()),
                    children: vec![99],
                }],
            ),
            Err("leaf node 1 has children".into())
        );
    }

    #[test]
    fn validates_contiguous_production_ids_from_any_transaction() {
        let nodes = vec![
            text(41, "first"),
            text(42, "second"),
            Node {
                id: 43,
                kind: NodeKind::Row {
                    label: String::new(),
                    style: Style::default(),
                },
                children: vec![41, 42],
            },
        ];
        assert_eq!(validate_tree(43, &nodes), Ok(()));
    }

    #[test]
    fn contiguous_validation_preserves_shape_and_edge_errors() {
        assert_eq!(
            validate_tree(
                3,
                &[
                    text(1, "child"),
                    Node {
                        id: 2,
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![1],
                    },
                    Node {
                        id: 3,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![1],
                    },
                ],
            ),
            Err("node 1 has more than one parent".into())
        );
        assert_eq!(
            validate_tree(
                2,
                &[
                    text(1, "child"),
                    Node {
                        id: 2,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![99],
                    },
                ],
            ),
            Err("node 2 references missing child 99".into())
        );
    }

    #[test]
    fn validation_rejects_subtrees_above_the_staging_guard() {
        let nodes = vec![
            Node {
                id: 1,
                kind: NodeKind::Column {
                    label: String::new(),
                    style: Style::default()
                },
                children: vec![],
            };
            MAX_STAGED_NODES + 1
        ];
        assert_eq!(
            validate_tree(1, &nodes),
            Err(format!("native subtree exceeds {MAX_STAGED_NODES} nodes"))
        );
    }

    #[test]
    fn stages_bottom_up_and_commits_a_tree() {
        let mut bridge = BridgeState::new();
        let button = bridge.stage_node(button("Click", true), vec![]).unwrap();
        let root = bridge
            .stage_node(
                NodeKind::Column {
                    label: String::new(),
                    style: Style::default(),
                },
                vec![button],
            )
            .unwrap();

        bridge.commit(Commit::Mount { root }).unwrap();
        assert_eq!(
            bridge.pending.take(),
            Some(Patch::Mount {
                root,
                nodes: vec![
                    Node {
                        id: button,
                        kind: self::button("Click", true),
                        children: vec![],
                    },
                    Node {
                        id: root,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Style::default()
                        },
                        children: vec![button],
                    },
                ],
            })
        );
    }

    #[test]
    fn streams_nested_children_into_their_own_host_builders() {
        let mut bridge = BridgeState::new();
        let outer = bridge.begin_children().unwrap();
        let inner = bridge.begin_children().unwrap();
        let text = bridge
            .stage_node(NodeKind::Text("nested".into()), vec![])
            .unwrap();
        bridge.push_child(inner, text).unwrap();
        let inner_children = bridge.finish_children(inner).unwrap();
        let row = bridge
            .stage_node(
                NodeKind::Row {
                    label: String::new(),
                    style: Style::default(),
                },
                inner_children,
            )
            .unwrap();
        bridge.push_child(outer, row).unwrap();
        assert_eq!(bridge.finish_children(outer), Ok(vec![row]));
    }

    #[test]
    fn rejects_out_of_order_and_unfinished_child_builders() {
        let mut bridge = BridgeState::new();
        let outer = bridge.begin_children().unwrap();
        let inner = bridge.begin_children().unwrap();
        assert_eq!(
            bridge.push_child(outer, 1),
            Err(format!("child builder {outer} is not active"))
        );
        assert_eq!(
            bridge.finish_children(outer),
            Err(format!("child builder {outer} is not active"))
        );
        assert_eq!(
            bridge.commit(Commit::NoChange),
            Err("Roc committed a patch with unfinished child builders".into())
        );
        assert_eq!(bridge.finish_children(inner), Ok(vec![]));
        assert_eq!(bridge.finish_children(outer), Ok(vec![]));
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
        assert_eq!(second, first + 1);
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
                .stage_node(button("Bad", true), vec![999])
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
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Style::default(),
                        },
                        children: vec![1],
                    },
                    Node {
                        id: 3,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Style::default(),
                        },
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
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Style::default(),
                        },
                        children: vec![4],
                    },
                ],
            })
            .unwrap();
        assert_eq!(replaced.facts.kind, "replace");
        assert_eq!(replaced.facts.staged, 2);
        assert_eq!(replaced.facts.removed, 2);
        assert_eq!(replaced.facts.live, 3);
        assert!(!replaced.retired_root);
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

    #[test]
    fn root_replacement_retires_the_complete_old_graph() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 2,
                nodes: vec![
                    text(1, "old"),
                    Node {
                        id: 2,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Style::default(),
                        },
                        children: vec![1],
                    },
                ],
            })
            .unwrap();

        let replaced = graph
            .apply(Patch::Replace {
                old_root: 2,
                root: 4,
                nodes: vec![
                    text(3, "new"),
                    Node {
                        id: 4,
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Style::default(),
                        },
                        children: vec![3],
                    },
                ],
            })
            .unwrap();

        assert_eq!(replaced.facts.removed, 2);
        assert_eq!(replaced.facts.live, 2);
        assert!(replaced.retired_root);
        assert!(replaced.removed_ids.is_empty());
        assert_eq!(replaced.parent, None);
        assert_eq!(graph.root(), Some(4));
        assert!(graph.node(1).is_none());
        assert!(graph.node(2).is_none());
        assert_eq!(graph.node(4).unwrap().children, vec![3]);
    }
}
