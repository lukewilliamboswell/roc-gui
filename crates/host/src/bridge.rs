pub use crate::observatory::CycleTarget;
use crate::roc_platform_abi::{
    MountOrNoChangeOrReplace, MountOrNoChangeOrReplaceTag, RocErasedCallable,
};
use std::collections::{HashMap, HashSet, hash_map::Entry};
use std::hash::{BuildHasherDefault, Hasher};
use std::iter::FusedIterator;
use std::sync::Arc;
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

type KeyedChildKey = [u8; 32];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct KeyedChild {
    root: u64,
    instance: u64,
    previous: Option<KeyedChildKey>,
    next: Option<KeyedChildKey>,
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct KeyedOrderEdit {
    revision: u64,
    touches: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KeyedOrderError {
    Duplicate(KeyedChildKey),
    Missing(KeyedChildKey),
    StaleRevision { actual: u64, expected: u64 },
    StaleNewRevision { current: u64, proposed: u64 },
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KeyedOrderOperation {
    Insert {
        key: KeyedChildKey,
        root: u64,
        instance: u64,
        before: Option<KeyedChildKey>,
    },
    Remove {
        key: KeyedChildKey,
    },
    Move {
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
    },
    Replace {
        key: KeyedChildKey,
        root: u64,
    },
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct KeyedOrderAtomicEdit {
    revision: u64,
    original_reads: u64,
    first_touches: u64,
}

struct KeyedChildIter<'a> {
    order: &'a KeyedChildOrder,
    front: Option<KeyedChildKey>,
    back: Option<KeyedChildKey>,
    remaining: usize,
}

impl<'a> Iterator for KeyedChildIter<'a> {
    type Item = (KeyedChildKey, &'a KeyedChild);
    fn next(&mut self) -> Option<Self::Item> {
        if self.remaining == 0 {
            return None;
        }
        let key = self.front.expect("non-empty keyed order has a head");
        let child = self.order.children.get(&key).expect("linked child");
        self.front = child.next;
        self.remaining -= 1;
        Some((key, child))
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.remaining, Some(self.remaining))
    }
}

impl DoubleEndedIterator for KeyedChildIter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.remaining == 0 {
            return None;
        }
        let key = self.back.expect("non-empty keyed order has a tail");
        let child = self.order.children.get(&key).expect("linked child");
        self.back = child.previous;
        self.remaining -= 1;
        Some((key, child))
    }
}

impl ExactSizeIterator for KeyedChildIter<'_> {}
impl FusedIterator for KeyedChildIter<'_> {}

struct KeyedOrderJournal<'a> {
    order: &'a mut KeyedChildOrder,
    original_head: Option<KeyedChildKey>,
    original_tail: Option<KeyedChildKey>,
    original_revision: u64,
    originals: HashMap<KeyedChildKey, Option<KeyedChild>>,
    original_reads: u64,
    first_touches: u64,
}

impl<'a> KeyedOrderJournal<'a> {
    fn new(order: &'a mut KeyedChildOrder) -> Self {
        Self {
            original_head: order.head,
            original_tail: order.tail,
            original_revision: order.revision,
            order,
            originals: HashMap::new(),
            original_reads: 0,
            first_touches: 0,
        }
    }
    fn touch(&mut self, key: KeyedChildKey) {
        if let Entry::Vacant(entry) = self.originals.entry(key) {
            entry.insert(self.order.children.get(&key).copied());
            self.original_reads += 1;
            self.first_touches += 1;
        }
    }
    fn child(&self, key: KeyedChildKey) -> Result<KeyedChild, KeyedOrderError> {
        self.order
            .children
            .get(&key)
            .copied()
            .ok_or(KeyedOrderError::Missing(key))
    }
    fn insert(
        &mut self,
        key: KeyedChildKey,
        root: u64,
        instance: u64,
        before: Option<KeyedChildKey>,
    ) -> Result<(), KeyedOrderError> {
        if self.order.children.contains_key(&key) {
            return Err(KeyedOrderError::Duplicate(key));
        }
        let next = before.map(|anchor| self.child(anchor)).transpose()?;
        let previous = next.map_or(self.order.tail, |child| child.previous);
        self.touch(key);
        self.order.children.insert(
            key,
            KeyedChild {
                root,
                instance,
                previous,
                next: before,
            },
        );
        if let Some(previous) = previous {
            self.touch(previous);
            self.order
                .children
                .get_mut(&previous)
                .expect("predecessor")
                .next = Some(key);
        } else {
            self.order.head = Some(key);
        }
        if let Some(anchor) = before {
            self.touch(anchor);
            self.order
                .children
                .get_mut(&anchor)
                .expect("anchor")
                .previous = Some(key);
        } else {
            self.order.tail = Some(key);
        }
        Ok(())
    }
    fn remove(&mut self, key: KeyedChildKey) -> Result<(), KeyedOrderError> {
        let child = self.child(key)?;
        if let Some(previous) = child.previous {
            self.touch(previous);
            self.order
                .children
                .get_mut(&previous)
                .expect("predecessor")
                .next = child.next;
        } else {
            self.order.head = child.next;
        }
        if let Some(next) = child.next {
            self.touch(next);
            self.order
                .children
                .get_mut(&next)
                .expect("successor")
                .previous = child.previous;
        } else {
            self.order.tail = child.previous;
        }
        self.touch(key);
        self.order.children.remove(&key);
        Ok(())
    }
    fn move_before(
        &mut self,
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
    ) -> Result<(), KeyedOrderError> {
        let child = self.child(key)?;
        if before == Some(key) || child.next == before {
            return Ok(());
        }
        if let Some(anchor) = before {
            self.child(anchor)?;
        }
        if let Some(previous) = child.previous {
            self.touch(previous);
            self.order
                .children
                .get_mut(&previous)
                .expect("predecessor")
                .next = child.next;
        } else {
            self.order.head = child.next;
        }
        if let Some(next) = child.next {
            self.touch(next);
            self.order
                .children
                .get_mut(&next)
                .expect("successor")
                .previous = child.previous;
        } else {
            self.order.tail = child.previous;
        }
        let previous = before
            .and_then(|anchor| {
                self.order
                    .children
                    .get(&anchor)
                    .and_then(|entry| entry.previous)
            })
            .or_else(|| before.is_none().then_some(self.order.tail).flatten());
        if let Some(previous) = previous {
            self.touch(previous);
            self.order
                .children
                .get_mut(&previous)
                .expect("move predecessor")
                .next = Some(key);
        } else {
            self.order.head = Some(key);
        }
        if let Some(anchor) = before {
            self.touch(anchor);
            self.order
                .children
                .get_mut(&anchor)
                .expect("anchor")
                .previous = Some(key);
        } else {
            self.order.tail = Some(key);
        }
        self.touch(key);
        let moved = self.order.children.get_mut(&key).expect("move key");
        moved.previous = previous;
        moved.next = before;
        Ok(())
    }
    fn replace(&mut self, key: KeyedChildKey, root: u64) -> Result<(), KeyedOrderError> {
        self.child(key)?;
        self.touch(key);
        self.order.children.get_mut(&key).expect("replace key").root = root;
        Ok(())
    }
    fn rollback(self) {
        self.order.head = self.original_head;
        self.order.tail = self.original_tail;
        self.order.revision = self.original_revision;
        for (key, original) in self.originals {
            if let Some(child) = original {
                self.order.children.insert(key, child);
            } else {
                self.order.children.remove(&key);
            }
        }
    }
}

/// Stable linked order for one future keyed container. Hash lookup plus a
/// bounded number of neighbour rewrites keeps structural work proportional to
/// semantic edits rather than sibling count.
#[derive(Default)]
struct KeyedChildOrder {
    revision: u64,
    head: Option<KeyedChildKey>,
    tail: Option<KeyedChildKey>,
    children: HashMap<KeyedChildKey, KeyedChild>,
}

impl KeyedChildOrder {
    fn from_seed(
        revision: u64,
        entries: &[(KeyedChildKey, u64, u64)],
    ) -> Result<Self, KeyedOrderError> {
        let mut order = Self {
            revision,
            ..Self::default()
        };
        for (index, (key, root, instance)) in entries.iter().copied().enumerate() {
            if order.children.contains_key(&key) {
                return Err(KeyedOrderError::Duplicate(key));
            }
            let previous = index.checked_sub(1).map(|prior| entries[prior].0);
            let next = entries.get(index + 1).map(|entry| entry.0);
            order.children.insert(
                key,
                KeyedChild {
                    root,
                    instance,
                    previous,
                    next,
                },
            );
        }
        order.head = entries.first().map(|entry| entry.0);
        order.tail = entries.last().map(|entry| entry.0);
        Ok(order)
    }

    fn iter(&self) -> KeyedChildIter<'_> {
        KeyedChildIter {
            order: self,
            front: self.head,
            back: self.tail,
            remaining: self.children.len(),
        }
    }

    #[cfg(test)]
    fn apply_atomic(
        &mut self,
        base_revision: u64,
        new_revision: u64,
        operations: &[KeyedOrderOperation],
    ) -> Result<KeyedOrderAtomicEdit, KeyedOrderError> {
        self.check_revision(base_revision)?;
        if new_revision <= base_revision {
            return Err(KeyedOrderError::StaleNewRevision {
                current: base_revision,
                proposed: new_revision,
            });
        }
        let mut journal = KeyedOrderJournal::new(self);
        for operation in operations {
            let result = match *operation {
                KeyedOrderOperation::Insert {
                    key,
                    root,
                    instance,
                    before,
                } => journal.insert(key, root, instance, before),
                KeyedOrderOperation::Remove { key } => journal.remove(key),
                KeyedOrderOperation::Move { key, before } => journal.move_before(key, before),
                KeyedOrderOperation::Replace { key, root } => journal.replace(key, root),
            };
            if let Err(error) = result {
                journal.rollback();
                return Err(error);
            }
        }
        journal.order.revision = new_revision;
        Ok(KeyedOrderAtomicEdit {
            revision: new_revision,
            original_reads: journal.original_reads,
            first_touches: journal.first_touches,
        })
    }

    fn check_revision(&self, expected: u64) -> Result<(), KeyedOrderError> {
        if expected == self.revision {
            Ok(())
        } else {
            Err(KeyedOrderError::StaleRevision {
                actual: self.revision,
                expected,
            })
        }
    }

    #[cfg(test)]
    fn get(&self, key: KeyedChildKey) -> Option<(u64, u64)> {
        self.children
            .get(&key)
            .map(|child| (child.root, child.instance))
    }

    #[cfg(test)]
    fn insert_before(
        &mut self,
        expected_revision: u64,
        key: KeyedChildKey,
        root: u64,
        instance: u64,
        before: Option<KeyedChildKey>,
    ) -> Result<KeyedOrderEdit, KeyedOrderError> {
        self.check_revision(expected_revision)?;
        if self.children.contains_key(&key) {
            return Err(KeyedOrderError::Duplicate(key));
        }
        let next = match before {
            Some(anchor) => Some(
                *self
                    .children
                    .get(&anchor)
                    .ok_or(KeyedOrderError::Missing(anchor))?,
            ),
            None => None,
        };
        let previous = next.map_or(self.tail, |child| child.previous);
        let mut touches = 1;
        self.children.insert(
            key,
            KeyedChild {
                root,
                instance,
                previous,
                next: before,
            },
        );
        if let Some(previous) = previous {
            self.children
                .get_mut(&previous)
                .expect("linked predecessor")
                .next = Some(key);
            touches += 1;
        } else {
            self.head = Some(key);
        }
        if let Some(anchor) = before {
            self.children
                .get_mut(&anchor)
                .expect("validated anchor")
                .previous = Some(key);
            touches += 1;
        } else {
            self.tail = Some(key);
        }
        self.revision += 1;
        Ok(KeyedOrderEdit {
            revision: self.revision,
            touches,
        })
    }

    #[cfg(test)]
    fn remove(
        &mut self,
        expected_revision: u64,
        key: KeyedChildKey,
    ) -> Result<(KeyedChild, KeyedOrderEdit), KeyedOrderError> {
        self.check_revision(expected_revision)?;
        let child = *self
            .children
            .get(&key)
            .ok_or(KeyedOrderError::Missing(key))?;
        let mut touches = 1;
        if let Some(previous) = child.previous {
            self.children
                .get_mut(&previous)
                .expect("linked predecessor")
                .next = child.next;
            touches += 1;
        } else {
            self.head = child.next;
        }
        if let Some(next) = child.next {
            self.children
                .get_mut(&next)
                .expect("linked successor")
                .previous = child.previous;
            touches += 1;
        } else {
            self.tail = child.previous;
        }
        self.children.remove(&key);
        self.revision += 1;
        Ok((
            child,
            KeyedOrderEdit {
                revision: self.revision,
                touches,
            },
        ))
    }

    #[cfg(test)]
    fn move_before(
        &mut self,
        expected_revision: u64,
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
    ) -> Result<KeyedOrderEdit, KeyedOrderError> {
        self.check_revision(expected_revision)?;
        let child = *self
            .children
            .get(&key)
            .ok_or(KeyedOrderError::Missing(key))?;
        if before == Some(key) || child.next == before {
            self.revision += 1;
            return Ok(KeyedOrderEdit {
                revision: self.revision,
                touches: 0,
            });
        }
        if let Some(anchor) = before
            && !self.children.contains_key(&anchor)
        {
            return Err(KeyedOrderError::Missing(anchor));
        }

        let mut touches = 1;
        if let Some(previous) = child.previous {
            self.children
                .get_mut(&previous)
                .expect("linked predecessor")
                .next = child.next;
            touches += 1;
        } else {
            self.head = child.next;
        }
        if let Some(next) = child.next {
            self.children
                .get_mut(&next)
                .expect("linked successor")
                .previous = child.previous;
            touches += 1;
        } else {
            self.tail = child.previous;
        }

        let previous = before
            .and_then(|anchor| self.children.get(&anchor).and_then(|entry| entry.previous))
            .or_else(|| before.is_none().then_some(self.tail).flatten());
        if let Some(previous) = previous {
            self.children
                .get_mut(&previous)
                .expect("move predecessor")
                .next = Some(key);
            touches += 1;
        } else {
            self.head = Some(key);
        }
        if let Some(anchor) = before {
            self.children
                .get_mut(&anchor)
                .expect("validated anchor")
                .previous = Some(key);
            touches += 1;
        } else {
            self.tail = Some(key);
        }
        let moved = self.children.get_mut(&key).expect("validated move key");
        moved.previous = previous;
        moved.next = before;
        self.revision += 1;
        Ok(KeyedOrderEdit {
            revision: self.revision,
            touches,
        })
    }

    #[cfg(test)]
    fn replace(
        &mut self,
        expected_revision: u64,
        key: KeyedChildKey,
        root: u64,
    ) -> Result<KeyedOrderEdit, KeyedOrderError> {
        self.check_revision(expected_revision)?;
        self.children
            .get_mut(&key)
            .ok_or(KeyedOrderError::Missing(key))?
            .root = root;
        self.revision += 1;
        Ok(KeyedOrderEdit {
            revision: self.revision,
            touches: 1,
        })
    }

    #[cfg(test)]
    fn keys(&self) -> Vec<KeyedChildKey> {
        self.iter().map(|(key, _)| key).collect()
    }
}

/// The logical extent of a list whose rows are produced on demand.
///
/// The mounted item children are the rows `first..first + children.len()` of
/// `count`. The owning render boundary, `instance`, is what carries the list's
/// viewport across renders, because the list node itself is replaced whenever
/// its window moves.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProvidedRows {
    pub instance: u64,
    pub count: u64,
    pub first: u64,
    /// The application asked to hear when the visible rows change.
    pub notify: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NodeKind {
    /// A mounted component's lifetime. This node adds no layout surface.
    Boundary {
        instance: u64,
    },
    Canvas {
        label: String,
        primitives: Vec<CanvasPrimitive>,
        /// Whether the owner handles pointer movement with no button pressed,
        /// and wheel scrolling. The host listens only for what is handled.
        hover: bool,
        wheel: bool,
        /// Whether the owner handles the size the canvas is laid out at. The
        /// host reports sizes only to a canvas that asks.
        size: bool,
        style: Box<Style>,
    },
    Button {
        caption: String,
        label: String,
        /// A plain button, or one tab of a tab strip.
        role: ButtonRole,
        enabled: bool,
        hover_enter: bool,
        hover_exit: bool,
        style: Box<Style>,
    },
    Checkbox {
        label: String,
        checked: bool,
        enabled: bool,
        /// The indicator's own colours, each None for the host's default.
        indicator: CheckboxIndicator,
        style: Box<Style>,
    },
    Textarea {
        label: String,
        value: String,
        placeholder: String,
        enabled: bool,
        read_only: bool,
        style: Box<Style>,
    },
    Image {
        label: String,
        bytes: Vec<u8>,
        format: ImageFormat,
        fit: ImageFit,
        grayscale: bool,
        style: Box<Style>,
    },
    Column {
        label: String,
        style: Box<Style>,
    },
    KeyedColumn {
        label: String,
        style: Box<Style>,
        revision: u64,
        keys: Vec<KeyedChildKey>,
    },
    Dialog {
        label: String,
        style: Box<Style>,
    },
    /// An anchor, its first child, annotated by a non-modal surface that
    /// presents the remaining children. With no remaining children it is a
    /// hover region and presents nothing.
    Popover {
        label: String,
        placement: Placement,
        delay_ms: u32,
        hover_enter: bool,
        hover_exit: bool,
        /// The key chords the region answers, in the order declared.
        shortcuts: Vec<Shortcut>,
        /// A request for focus to move into the anchor, honoured once for each
        /// distinct serial; 0 asks for nothing.
        focus_serial: u64,
        /// The surface's style; the anchor keeps its own.
        style: Box<Style>,
    },
    Panel {
        label: String,
        style: Box<Style>,
    },
    Row {
        label: String,
        style: Box<Style>,
    },
    Scroll {
        name: String,
        axis: ScrollAxis,
        style: Box<Style>,
    },
    VirtualItem {
        key: u64,
    },
    VirtualList {
        name: String,
        row_height: u32,
        /// Space held clear at the bottom of each row inside `row_height`.
        row_gap: u32,
        style: Box<Style>,
        /// Present when the application produces rows on demand; the item
        /// children are then a window of the list, not the whole of it.
        rows: Option<ProvidedRows>,
    },
    TextInput {
        label: String,
        value: String,
        placeholder: String,
        enabled: bool,
        style: Box<Style>,
    },
    /// Two panes, its children, and the divider between them. It carries the
    /// sized pane's extent and bounds so a drag becomes a size without asking
    /// Roc, and the keys the divider answers while it holds keyboard focus. A
    /// collapsed pane stays mounted but is neither drawn nor presented.
    Split {
        label: String,
        axis: SplitAxis,
        side: SplitSide,
        size: u32,
        min: u32,
        max: u32,
        collapsible: bool,
        collapsed: bool,
        thickness: u32,
        /// The divider's keys, in the order declared.
        shortcuts: Vec<Shortcut>,
        /// The divider's colours; its size fields size the split.
        style: Box<Style>,
    },
    /// A column that accepts files dropped on it. It carries the file types it
    /// accepts, already validated, so a drop is admitted without asking Roc,
    /// and the colours it shows while acceptable files are dragged over it.
    DropTarget {
        label: String,
        types: Vec<crate::document::FileType>,
        drop_bg: Option<crate::Paint>,
        drop_border: Option<crate::Paint>,
        style: Box<Style>,
    },
    /// Text that carries its own type: colour, size, weight, and face, with no
    /// container element to hold them. `runs` is empty for text of one style;
    /// otherwise the runs cover `value` exactly, in order, and each restyles
    /// its own bytes of it.
    StyledText {
        value: String,
        fg: Option<crate::Paint>,
        font_size: u32,
        font_weight: u32,
        font_face: FontFace,
        runs: Vec<TextRun>,
    },
    Text(String),
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
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
    pub fill: Option<crate::Paint>,
    pub stroke: Option<crate::Paint>,
    pub stroke_width: u32,
    pub radius: u32,
    /// A text primitive's line, its size in logical pixels, and its placement
    /// within the box from `x` to `x + width`. Empty for every other kind.
    pub text: String,
    pub text_size: u32,
    pub align: CanvasTextAlign,
}

impl CanvasPrimitive {
    /// A text primitive's line height: its size and a quarter again, rounded
    /// down, so a locator's rectangle is the same on every host.
    pub fn line_height(&self) -> u32 {
        self.text_size + self.text_size / 4
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum CanvasPrimitiveKind {
    Ellipse,
    Line,
    #[default]
    Rectangle,
    Text,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum CanvasTextAlign {
    #[default]
    Start,
    Center,
    End,
}

/// One key chord a region answers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Shortcut {
    /// The chord in GPUI's canonical spelling, which is also what the
    /// application's handler is told was pressed.
    pub keys: String,
    pub scope: ShortcutScope,
}

/// When a shortcut is live.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShortcutScope {
    /// While its region is mounted and presented.
    Window,
    /// Only while keyboard focus is inside its region.
    Focus,
}

/// The shortcut a keystroke reached: the event naming its region's route,
/// which of the region's shortcuts it is, and the chord as the region spells it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShortcutMatch {
    pub region: u64,
    pub event: u64,
    pub index: u64,
    pub keys: String,
}

/// What a pressable control is to a person and to a locator.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ButtonRole {
    #[default]
    Button,
    Tab {
        selected: bool,
    },
}

/// The direction a split lays out its panes: side by side, or stacked.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SplitAxis {
    Horizontal,
    Vertical,
}

/// Which of a split's panes its size belongs to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SplitSide {
    Start,
    End,
}

/// A split's requested extent: what `Event.Resize` carries.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Resize {
    pub size: u32,
    pub collapsed: bool,
}

/// A divider as it was when a pointer pressed it. A drag is measured from
/// the press, so every move asks for a size against these bounds rather than
/// against a size an earlier move of the same drag already changed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SplitterGrip {
    axis: SplitAxis,
    side: SplitSide,
    /// The sized pane's extent under the pointer: zero while collapsed.
    start: u32,
    /// The size a collapse keeps to return to.
    size: u32,
    min: u32,
    max: u32,
    collapsible: bool,
}

impl SplitterGrip {
    /// The size a pointer `(dx, dy)` logical pixels from where it pressed asks
    /// for. Movement across the divider's axis is ignored; movement towards
    /// the sized pane shrinks it. A collapsible pane dragged below half its
    /// minimum asks to collapse, keeping the size it had.
    pub fn resize(&self, dx: f32, dy: f32) -> Resize {
        let along = match self.axis {
            SplitAxis::Horizontal => dx,
            SplitAxis::Vertical => dy,
        };
        let signed = match self.side {
            SplitSide::Start => along,
            SplitSide::End => -along,
        };
        let raw = self.start as f32 + signed;
        if self.collapsible && self.min > 0 && raw < self.min as f32 / 2.0 {
            return Resize {
                size: self.size,
                collapsed: true,
            };
        }
        let clamped = raw.round().clamp(self.min as f32, self.max as f32) as u32;
        Resize {
            size: clamped,
            collapsed: false,
        }
    }
}

/// Which side of its anchor a popover surface is placed on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Placement {
    Below,
    Above,
    Start,
    End,
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

    /// Whether a pointer press on this control is dispatched to Roc as a click.
    ///
    /// This is the single definition of what `Runtime::event_if_live` will
    /// route; the window runner consults it so a simulated press cannot claim
    /// to have activated a control the production handler would have ignored.
    pub fn dispatches_click(&self) -> bool {
        matches!(
            self,
            Self::Button { enabled: true, .. }
                | Self::Checkbox { enabled: true, .. }
                | Self::Dialog { .. }
        )
    }

    /// Whether this control accepts pointer activation.
    ///
    /// The production render path attaches a click handler only to enabled
    /// controls, so a simulated click must honour the same condition. A canvas
    /// is deliberately absent: it takes raw press, move, and release events
    /// with coordinates through `Runtime::canvas_pointer`, not a click, so a
    /// simulated click would reach no handler at all.
    pub fn accepts_pointer(&self) -> bool {
        matches!(
            self,
            Self::Button { enabled: true, .. }
                | Self::Checkbox { enabled: true, .. }
                | Self::TextInput { enabled: true, .. }
                | Self::Textarea { enabled: true, .. }
        )
    }

    /// Which kind this is, as a capture names the target of a cycle. A
    /// popover with no surface of its own is a region: it anchors hover or
    /// shortcut handlers and presents nothing.
    pub fn target_kind(&self) -> &'static str {
        match self {
            Self::Canvas { .. } => "canvas",
            Self::Button { .. } => "button",
            Self::Checkbox { .. } => "checkbox",
            Self::Textarea { .. } => "textarea",
            Self::Image { .. } => "image",
            Self::Column { .. } | Self::KeyedColumn { .. } => "column",
            Self::Dialog { .. } => "dialog",
            Self::Panel { .. } => "panel",
            Self::Row { .. } => "row",
            Self::Scroll { .. } => "scroll",
            Self::VirtualItem { .. } => "virtual_item",
            Self::VirtualList { .. } => "virtual_list",
            Self::TextInput { .. } => "text_input",
            Self::Text(_) | Self::StyledText { .. } => "text",
            Self::Boundary { .. } => "boundary",
            Self::Popover { label, .. } if label.is_empty() => "region",
            Self::Popover { .. } => "popover",
            Self::Split { .. } => "split",
            Self::DropTarget { .. } => "drop_target",
        }
    }

    /// Which kind this is, as a number, for identity comparisons.
    ///
    /// Two nodes are the same element across a patch only if they agree here:
    /// a button that became a checkbox at the same place is a different
    /// control, whatever it is called.
    pub fn tag(&self) -> u8 {
        match self {
            Self::Canvas { .. } => 0,
            Self::Button { .. } => 1,
            Self::Checkbox { .. } => 2,
            Self::Textarea { .. } => 3,
            Self::Image { .. } => 4,
            Self::Column { .. } | Self::KeyedColumn { .. } => 5,
            Self::Dialog { .. } => 6,
            Self::Panel { .. } => 7,
            Self::Row { .. } => 8,
            Self::Scroll { .. } => 9,
            Self::VirtualItem { .. } => 10,
            Self::VirtualList { .. } => 11,
            Self::TextInput { .. } => 12,
            Self::Text(_) => 13,
            Self::StyledText { .. } => 14,
            Self::Boundary { .. } => 15,
            Self::Popover { .. } => 17,
            Self::Split { .. } => 18,
            Self::DropTarget { .. } => 19,
        }
    }

    /// The name this node carries among its siblings, when it has one a patch
    /// preserves.
    ///
    /// This is the same name a specification locates the node by, which is
    /// what makes it the application's own statement of what the thing is.
    /// `Text` has no name — a paragraph is identified by where it sits — and a
    /// virtual item is named by the key its application chose for the row.
    pub fn sibling_name(&self) -> Option<std::borrow::Cow<'_, str>> {
        let name: std::borrow::Cow<'_, str> = match self {
            Self::Canvas { label, .. }
            | Self::Button { label, .. }
            | Self::Checkbox { label, .. }
            | Self::Textarea { label, .. }
            | Self::Image { label, .. }
            | Self::Column { label, .. }
            | Self::KeyedColumn { label, .. }
            | Self::Dialog { label, .. }
            | Self::Popover { label, .. }
            | Self::Panel { label, .. }
            | Self::Row { label, .. }
            | Self::Split { label, .. }
            | Self::DropTarget { label, .. }
            | Self::TextInput { label, .. } => label.as_str().into(),
            Self::Scroll { name, .. } | Self::VirtualList { name, .. } => name.as_str().into(),
            Self::VirtualItem { key } => key.to_string().into(),
            Self::Text(_) | Self::StyledText { .. } | Self::Boundary { .. } => "".into(),
        };
        (!name.is_empty()).then_some(name)
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
            Self::Split { label, .. } => Some((4, label.clone())),
            _ => None,
        }
    }

    /// A divider's grip for a drag starting now, or `None` for anything else.
    pub fn splitter_grip(&self) -> Option<SplitterGrip> {
        match self {
            Self::Split {
                axis,
                side,
                size,
                min,
                max,
                collapsible,
                collapsed,
                ..
            } => Some(SplitterGrip {
                axis: *axis,
                side: *side,
                start: if *collapsed { 0 } else { *size },
                size: *size,
                min: *min,
                max: *max,
                collapsible: *collapsible,
            }),
            _ => None,
        }
    }

    /// Which child of a split its collapse hides, if it is collapsed.
    pub fn hidden_pane(&self) -> Option<usize> {
        match self {
            Self::Split {
                side,
                collapsible: true,
                collapsed: true,
                ..
            } => Some(match side {
                SplitSide::Start => 0,
                SplitSide::End => 1,
            }),
            _ => None,
        }
    }

    /// What a divider shows now, which a drag need not ask for again.
    pub fn splitter_value(&self) -> Option<Resize> {
        match self {
            Self::Split {
                size, collapsed, ..
            } => Some(Resize {
                size: *size,
                collapsed: *collapsed,
            }),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Length {
    #[default]
    Auto,
    Fill,
    Px(u32),
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Overflow {
    #[default]
    Visible,
    Clip,
    Scroll,
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
    pub box_bg: Option<crate::Paint>,
    pub box_checked_bg: Option<crate::Paint>,
    pub box_border: Option<crate::Paint>,
    pub mark_color: Option<crate::Paint>,
}

/// One styled run of rich text: `len` UTF-8 bytes of the element's value,
/// and what the run sets over the element's own type. An absent colour and a
/// zero weight keep the element's.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TextRun {
    pub len: usize,
    pub fg: Option<crate::Paint>,
    pub bg: Option<crate::Paint>,
    pub font_weight: u32,
    pub underline: bool,
    pub monospace: bool,
}

/// The typeface family a string is set in.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FontFace {
    #[default]
    Default,
    Monospace,
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
    pub bg: Option<crate::Paint>,
    pub hover_bg: Option<crate::Paint>,
    pub active_bg: Option<crate::Paint>,
    pub disabled_bg: Option<crate::Paint>,
    pub disabled_fg: Option<crate::Paint>,
    pub focus_color: Option<crate::Paint>,
    pub fg: Option<crate::Paint>,
    pub border_color: Option<crate::Paint>,
    /// Top, right, bottom, left, already resolved from the shorthand.
    pub border_width: [u32; 4],
    pub radius: u32,
    pub font_size: u32,
    pub font_weight: u32,
    /// A soft drop shadow: blur radius, downward offset, colour, and the
    /// percentage of that colour it is painted at. A zero blur paints none.
    pub shadow: u32,
    pub shadow_y: u32,
    pub shadow_color: Option<crate::Paint>,
    pub shadow_alpha: u32,
    pub font_face: FontFace,
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

/// Stable ownership of a mounted node. Ordinary children retain their vector
/// position; keyed children will retain collection identity independently of
/// display position when keyed graph transactions are connected.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParentLocation {
    OrdinaryIndex {
        parent: u64,
        index: usize,
    },
    Keyed {
        container: u64,
        key: [u8; 32],
        instance: u64,
    },
}

impl ParentLocation {
    pub(crate) fn parent(self) -> u64 {
        match self {
            Self::OrdinaryIndex { parent, .. } => parent,
            Self::Keyed { container, .. } => container,
        }
    }
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
    /// Fresh nodes joined to complete, still-mounted component subtrees.
    ReplaceRetaining {
        old_root: u64,
        root: u64,
        nodes: Vec<Node>,
        retained_roots: Vec<u64>,
    },
    Keyed {
        container: u64,
        base_revision: u64,
        new_revision: u64,
        operations: Vec<KeyedGraphOperation>,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApplyFacts {
    pub kind: &'static str,
    pub staged: u64,
    pub removed: u64,
    pub live: u64,
    pub scanned: u64,
    pub retained_nodes: u64,
    pub validation_visits: u64,
    pub validate_ns: u64,
    pub apply_ns: u64,
    pub keyed_graph_visits: u64,
    pub keyed_original_reads: u64,
    pub keyed_first_touches: u64,
}

#[derive(Debug)]
pub struct GraphApply {
    pub facts: ApplyFacts,
    pub root: Option<u64>,
    pub staged_ids: Vec<u64>,
    pub removed_ids: Vec<u64>,
    pub retired_root: bool,
    pub parent: Option<(u64, usize)>,
    pub retained_roots: Vec<u64>,
    pub removed_instances: Vec<u64>,
    pub staged_instances: Vec<u64>,
    pub(crate) keyed_edits: Vec<KeyedNativeEdit>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum KeyedNativeEdit {
    Insert {
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
        root: u64,
    },
    Remove {
        key: KeyedChildKey,
        root: u64,
    },
    Move {
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
    },
    Set {
        key: KeyedChildKey,
        old_root: u64,
        root: u64,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum KeyedGraphOperation {
    Insert {
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
        root: u64,
        nodes: Vec<Node>,
    },
    Remove {
        key: KeyedChildKey,
    },
    Move {
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
    },
    Set {
        key: KeyedChildKey,
        root: u64,
        nodes: Vec<Node>,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct KeyedGraphApply {
    revision: u64,
    staged: u64,
    removed: u64,
    graph_visits: u64,
    original_reads: u64,
    first_touches: u64,
    staged_ids: Vec<u64>,
    removed_ids: Vec<u64>,
    staged_instances: Vec<u64>,
    removed_instances: Vec<u64>,
    validate_ns: u64,
    apply_ns: u64,
    native_edits: Vec<KeyedNativeEdit>,
}

/// One step of an [`ElementIdentity`]: a node's key among its siblings.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum IdentitySegment {
    /// An explicit component lifetime cannot inherit a removed component's state.
    Boundary { instance: u64 },
    /// The node names itself. `occurrence` separates siblings that share a
    /// name, and is 0 for the overwhelmingly common unique case. The name is
    /// shared, so cloning an identity path bumps refcounts instead of copying
    /// one string per ancestor segment.
    Named {
        tag: u8,
        name: Arc<str>,
        occurrence: u32,
    },
    /// The node has no name of its own, so its place among its siblings is
    /// what identifies it.
    Positional { tag: u8, index: usize },
}

impl IdentitySegment {
    pub(crate) fn of(node: &Node, index: usize, occurrence: u32) -> Self {
        if let NodeKind::Boundary { instance } = node.kind {
            return Self::Boundary { instance };
        }
        match node.kind.sibling_name() {
            Some(name) => Self::Named {
                tag: node.kind.tag(),
                name: Arc::from(&*name),
                occurrence,
            },
            None => Self::Positional {
                tag: node.kind.tag(),
                index,
            },
        }
    }
}

/// A native key path, anchored at the nearest component boundary when present.
pub type ElementIdentity = Vec<IdentitySegment>;

pub const HOVER_ENTER_EVENT_BIT: u64 = 1 << 62;
pub const HOVER_EXIT_EVENT_BIT: u64 = 1 << 61;
/// The route of every shortcut a region declares.
pub const SHORTCUT_EVENT_BIT: u64 = 1 << 60;

/// The canonical mounted UI graph. Both semantic specs and the GPUI runtime
/// apply patches here; GPUI entities are only a materialized view of this state.
#[derive(Default)]
pub struct MountedGraph {
    nodes: NodeMap<MountedNode>,
    root: Option<u64>,
    max_seen_node_id: u64,
    max_seen_instance: Option<u64>,
    boundary_instances: NodeMap<u64>,
    input_labels: HashMap<(Option<u64>, String), u64>,
    input_owners: NodeMap<Option<u64>>,
    dialog: Option<u64>,
    hovered: NodeSet,
    popovers: PopoverState,
    keyboard: KeyboardState,
    /// The size last reported to each canvas whose owner handles its size.
    /// Carried by identity across a rebuild, so a canvas hears each size once
    /// while it stays mounted, whichever runner lays it out.
    canvas_sizes: NodeMap<(u32, u32)>,
}

/// The regions whose shortcuts a keystroke may reach and the focus requests
/// the last transaction made. Owned by the graph so the native window and the
/// semantic runner resolve a keystroke, and honour a request, by one policy.
#[derive(Default)]
struct KeyboardState {
    /// Every mounted region that declares a shortcut.
    regions: NodeSet,
    /// The subset declaring one that is live wherever focus is.
    window_regions: NodeSet,
    /// The serial each mounted region last asked for focus with.
    serials: NodeMap<u64>,
    /// Regions staged by the transaction being applied that carry a serial.
    staged_requests: Vec<u64>,
    /// Regions whose serial is new since the last request was taken.
    requests: Vec<u64>,
    counters: KeyboardCounters,
}

/// Deterministic keyboard work, counted by the graph that does it.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct KeyboardCounters {
    /// Keystrokes offered to the application's shortcuts.
    pub offered: u64,
    /// Keystrokes a shortcut answered.
    pub matched: u64,
    /// Declared shortcuts compared against a keystroke.
    pub compared: u64,
    /// Focus requests that moved focus.
    pub focused: u64,
}

impl KeyboardCounters {
    pub fn as_array(self) -> [u64; 4] {
        [self.offered, self.matched, self.compared, self.focused]
    }
}

/// Which popovers are presenting, and why. Owned by the graph so the native
/// window and the semantic runner apply one policy: a surface opens after its
/// delay while the pointer rests on the anchor, at once while keyboard focus
/// is inside it, and closes when both have left or on Escape.
#[derive(Default)]
struct PopoverState {
    open: NodeSet,
    /// Hovered, waiting for the delay to elapse.
    pending: NodeSet,
    focus_within: NodeSet,
    counters: PopoverCounters,
}

/// Deterministic popover transitions, counted by the graph that decides them.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PopoverCounters {
    /// Surfaces that began presenting.
    pub opened: u64,
    /// Surfaces closed because pointer and focus both left.
    pub closed: u64,
    /// Surfaces closed by Escape.
    pub dismissed: u64,
}

impl PopoverCounters {
    pub fn as_array(self) -> [u64; 3] {
        [self.opened, self.closed, self.dismissed]
    }
}

/// Interaction state of retired nodes, carried by identity to the nodes that
/// replace them, so a rebuild under the pointer neither replays nor drops it.
#[derive(Default)]
struct InteractionCarry {
    hovered: HashSet<ElementIdentity>,
    open: HashSet<ElementIdentity>,
    pending: HashSet<ElementIdentity>,
    focus_within: HashSet<ElementIdentity>,
    /// The serial a retired region had asked for focus with.
    focus_serials: HashMap<ElementIdentity, u64>,
    /// The size a retired canvas had last reported.
    canvas_sizes: HashMap<ElementIdentity, (u32, u32)>,
}

impl InteractionCarry {
    fn is_empty(&self) -> bool {
        self.hovered.is_empty()
            && self.open.is_empty()
            && self.pending.is_empty()
            && self.focus_within.is_empty()
            && self.canvas_sizes.is_empty()
    }
}

/// Whether the graph tracks pointer edges for this node: an enabled button
/// with a hover handler, or any popover.
fn tracks_hover(kind: &NodeKind) -> bool {
    match kind {
        NodeKind::Button {
            enabled: true,
            hover_enter,
            hover_exit,
            ..
        } => *hover_enter || *hover_exit,
        NodeKind::Popover { .. } => true,
        _ => false,
    }
}

struct MountedNode {
    node: Node,
    parent: Option<ParentLocation>,
    subtree_size: u64,
    segment: IdentitySegment,
    keyed_children: Option<KeyedChildOrder>,
}

/// Allocation-free semantic child order for mounted graph traversal.
pub(crate) struct MountedChildren<'a> {
    kind: MountedChildrenKind<'a>,
}

enum MountedChildrenKind<'a> {
    Ordinary(std::iter::Copied<std::slice::Iter<'a, u64>>),
    Keyed(KeyedChildIter<'a>),
}

impl Iterator for MountedChildren<'_> {
    type Item = u64;

    fn next(&mut self) -> Option<Self::Item> {
        match &mut self.kind {
            MountedChildrenKind::Ordinary(iter) => iter.next(),
            MountedChildrenKind::Keyed(iter) => iter.next().map(|(_, child)| child.root),
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        match &self.kind {
            MountedChildrenKind::Ordinary(iter) => iter.size_hint(),
            MountedChildrenKind::Keyed(iter) => iter.size_hint(),
        }
    }
}

impl DoubleEndedIterator for MountedChildren<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        match &mut self.kind {
            MountedChildrenKind::Ordinary(iter) => iter.next_back(),
            MountedChildrenKind::Keyed(iter) => iter.next_back().map(|(_, child)| child.root),
        }
    }
}

impl ExactSizeIterator for MountedChildren<'_> {}

impl MountedGraph {
    pub(crate) fn children_of(&self, id: u64) -> MountedChildren<'_> {
        let Some(entry) = self.nodes.get(&id) else {
            return MountedChildren {
                kind: MountedChildrenKind::Ordinary([].iter().copied()),
            };
        };
        if let Some(order) = &entry.keyed_children {
            MountedChildren {
                kind: MountedChildrenKind::Keyed(order.iter()),
            }
        } else {
            MountedChildren {
                kind: MountedChildrenKind::Ordinary(entry.node.children.iter().copied()),
            }
        }
    }

    pub(crate) fn keyed_children(&self, id: u64) -> Option<Vec<([u8; 32], u64)>> {
        self.nodes
            .get(&id)?
            .keyed_children
            .as_ref()
            .map(|order| order.iter().map(|(key, child)| (key, child.root)).collect())
    }

    pub fn node(&self, id: u64) -> Option<&Node> {
        self.nodes.get(&id).map(|entry| &entry.node)
    }

    pub fn parent(&self, id: u64) -> Option<(u64, usize)> {
        match self.nodes.get(&id)?.parent? {
            ParentLocation::OrdinaryIndex { parent, index } => Some((parent, index)),
            ParentLocation::Keyed { .. } => None,
        }
    }

    pub fn parent_location(&self, id: u64) -> Option<ParentLocation> {
        self.nodes.get(&id).and_then(|entry| entry.parent)
    }

    /// The node an event route reaches, named for a capture without any
    /// application text: its kind, and a hash of its structural path.
    ///
    /// The path is the kind and the display position of every node from the
    /// root down to the target. It holds no label, name, value, key, or
    /// component instance, so it can be recorded under the capture privacy
    /// rules, and it depends only on the shape of the mounted graph, so the
    /// same control in the same place hashes the same across runs, rebuilds,
    /// and machines. A keyed or virtual row is named by where it is shown,
    /// never by its key, which an application derives from its data.
    pub fn cycle_target(&self, route: u64) -> Option<CycleTarget> {
        const ROUTE_BITS: u64 =
            (1 << 63) | HOVER_ENTER_EVENT_BIT | HOVER_EXIT_EVENT_BIT | SHORTCUT_EVENT_BIT;
        let target = route & !ROUTE_BITS;
        let kind = self.node(target)?.kind.target_kind();
        // FNV-1a over (tag, position) pairs from the target up to the root. The
        // walk order is fixed, so the hash names the same path every time.
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        let mut mix = |value: u64| {
            for byte in value.to_le_bytes() {
                hash ^= u64::from(byte);
                hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
            }
        };
        let mut id = target;
        loop {
            let entry = self.nodes.get(&id)?;
            mix(u64::from(entry.node.kind.tag()));
            match entry.parent {
                Some(ParentLocation::OrdinaryIndex { parent, index }) => {
                    mix(index as u64);
                    id = parent;
                }
                Some(ParentLocation::Keyed { container, .. }) => {
                    let position = self.children_of(container).position(|child| child == id)?;
                    mix(position as u64);
                    id = container;
                }
                None => break,
            }
        }
        Some(CycleTarget {
            kind,
            identity: format!("{hash:016x}"),
        })
    }

    pub fn subtree_size(&self, id: u64) -> Option<u64> {
        self.nodes.get(&id).map(|entry| entry.subtree_size)
    }

    /// This node's committed sibling key, without enumerating its siblings.
    pub fn cached_segment(&self, id: u64) -> Option<&IdentitySegment> {
        self.nodes.get(&id).map(|entry| &entry.segment)
    }

    pub fn boundary_root(&self, instance: u64) -> Option<u64> {
        self.boundary_instances.get(&instance).copied()
    }

    fn component_owner(&self, mut id: u64) -> Option<u64> {
        loop {
            let entry = self.nodes.get(&id)?;
            if let NodeKind::Boundary { instance } = entry.node.kind {
                return Some(instance);
            }
            id = entry.parent?.parent();
        }
    }

    pub fn is_virtual_descendant(&self, id: u64) -> bool {
        let mut parent = self.nodes.get(&id).and_then(|entry| entry.parent);
        while let Some(location) = parent {
            let id = location.parent();
            if matches!(
                self.node(id).map(|node| &node.kind),
                Some(NodeKind::VirtualList { .. })
            ) {
                return true;
            }
            parent = self.nodes.get(&id).and_then(|entry| entry.parent);
        }
        false
    }

    pub(crate) fn identity(&self, id: u64) -> ElementIdentity {
        let mut identity = Vec::new();
        let mut current = Some(id);
        while let Some(id) = current {
            let entry = &self.nodes[&id];
            identity.push(entry.segment.clone());
            current = entry.parent.map(ParentLocation::parent);
        }
        identity.reverse();
        identity
    }

    /// Nodes in production child order, suitable for semantic ordering checks.
    pub fn nodes_preorder(&self) -> Vec<&Node> {
        let mut ordered = Vec::with_capacity(self.nodes.len());
        let mut pending = self.root.into_iter().collect::<Vec<_>>();
        while let Some(id) = pending.pop() {
            let node = &self.nodes.get(&id).expect("mounted child is missing").node;
            ordered.push(node);
            pending.extend(self.children_of(id).rev());
        }
        ordered
    }

    /// Nodes a person can currently perceive, in production child order: the
    /// content of a closed popover is mounted but not presented, so it is
    /// skipped along with everything below it.
    pub fn presented_preorder(&self) -> Vec<&Node> {
        let mut ordered = Vec::with_capacity(self.nodes.len());
        let mut pending = self.root.into_iter().collect::<Vec<_>>();
        while let Some(id) = pending.pop() {
            let node = &self.nodes.get(&id).expect("mounted child is missing").node;
            ordered.push(node);
            if matches!(node.kind, NodeKind::Popover { .. }) && !self.popovers.open.contains(&id) {
                pending.extend(node.children.first().copied());
            } else if let Some(hidden) = node.kind.hidden_pane() {
                pending.extend(
                    node.children
                        .iter()
                        .enumerate()
                        .rev()
                        .filter(|(index, _)| *index != hidden)
                        .map(|(_, child)| *child),
                );
            } else {
                pending.extend(self.children_of(id).rev());
            }
        }
        ordered
    }

    /// Where every mounted node sits, named rather than numbered.
    ///
    /// A mounted node id is deliberately never reused, so it cannot say that
    /// the control in this frame is the control a person is already pressing
    /// in the last one. This is the identity that can: the path of sibling
    /// keys from the nearest component boundary (or mounted root), each key
    /// the node's own name when it has one and its position when it has not.
    /// Boundaries reset the prefix to their never-reused instance token. The
    /// identity is stable across a rebuild within the same component lifetime,
    /// and changes when the application identifies a different control.
    ///
    /// Repeated names among siblings are disambiguated by occurrence, so the
    /// identity of a node is unique within the graph even when an application
    /// gives two sibling buttons the same name.
    #[cfg(test)]
    pub fn element_identities(&self) -> HashMap<u64, ElementIdentity> {
        let mut identities = HashMap::new();
        if let Some(root) = self.root {
            let key = self
                .node(root)
                .map(|node| IdentitySegment::of(node, 0, 0))
                .unwrap_or(IdentitySegment::Positional { tag: 0, index: 0 });
            self.identities_below(root, key, &[], &mut identities);
        }
        identities
    }

    /// The sibling keys of one node's children, in child order.
    ///
    /// Repeated names are separated here, where the siblings are all in view.
    pub fn child_segments(&self, parent: u64) -> Vec<(u64, IdentitySegment)> {
        let Some(_node) = self.node(parent) else {
            return Vec::new();
        };
        let mut seen: HashMap<(u8, String), u32> = HashMap::new();
        let mut segments = Vec::with_capacity(self.children_of(parent).len());
        for (index, child) in self.children_of(parent).enumerate() {
            let Some(child_node) = self.node(child) else {
                continue;
            };
            let occurrence = match child_node.kind.sibling_name() {
                Some(name) => {
                    let slot = seen
                        .entry((child_node.kind.tag(), name.into_owned()))
                        .or_default();
                    let occurrence = *slot;
                    *slot += 1;
                    occurrence
                }
                None => 0,
            };
            segments.push((child, IdentitySegment::of(child_node, index, occurrence)));
        }
        segments
    }

    /// Record identities for `root` and everything beneath it, given the
    /// identity of its parent and its own key among that parent's children.
    #[cfg(test)]
    pub fn identities_below(
        &self,
        root: u64,
        own: IdentitySegment,
        parent_identity: &[IdentitySegment],
        into: &mut HashMap<u64, ElementIdentity>,
    ) {
        let mut identity = parent_identity.to_vec();
        identity.push(own);
        let mut pending = vec![(root, identity)];
        while let Some((id, mut identity)) = pending.pop() {
            if let Some(Node {
                kind: NodeKind::Boundary { instance },
                ..
            }) = self.node(id)
            {
                identity = vec![IdentitySegment::Boundary {
                    instance: *instance,
                }];
            }
            for (child, segment) in self.child_segments(id) {
                let mut child_identity = identity.clone();
                child_identity.push(segment);
                pending.push((child, child_identity));
            }
            into.insert(id, identity);
        }
    }

    pub fn active_dialog(&self) -> Option<u64> {
        self.dialog
    }

    /// Resolve only installed hover handlers on live enabled controls.
    pub fn hover_route(&self, id: u64, entered: bool) -> Option<u64> {
        match &self.node(id)?.kind {
            NodeKind::Button {
                enabled: true,
                hover_enter,
                hover_exit,
                ..
            } if if entered { *hover_enter } else { *hover_exit } => Some(
                id | if entered {
                    HOVER_ENTER_EVENT_BIT
                } else {
                    HOVER_EXIT_EVENT_BIT
                },
            ),
            NodeKind::Popover {
                hover_enter,
                hover_exit,
                ..
            } if if entered { *hover_enter } else { *hover_exit } => Some(
                id | if entered {
                    HOVER_ENTER_EVENT_BIT
                } else {
                    HOVER_EXIT_EVENT_BIT
                },
            ),
            _ => None,
        }
    }

    /// The production hover transition shared by native input and semantic
    /// specifications. Track both edges even when only one has a callback.
    pub fn hover_transition(&mut self, id: u64, entered: bool) -> Option<u64> {
        if self
            .dialog
            .is_some_and(|dialog| !self.is_descendant_of(id, dialog))
        {
            return None;
        }
        if !self.node(id).is_some_and(|node| tracks_hover(&node.kind)) {
            return None;
        }
        let changed = if entered {
            self.hovered.insert(id)
        } else {
            self.hovered.remove(&id)
        };
        if changed {
            self.popover_hover_edge(id, entered);
        }
        changed.then(|| self.hover_route(id, entered)).flatten()
    }

    /// The nodes a pointer resting on `id` hovers, outermost first: every
    /// popover whose anchor contains `id`, then `id` itself when it tracks
    /// hover. A popover's surface floats outside its anchor, so a node in a
    /// surface hovers nothing above that popover.
    pub fn hover_targets(&self, id: u64) -> Vec<u64> {
        let mut targets = Vec::new();
        if self.node(id).is_some_and(|node| tracks_hover(&node.kind)) {
            targets.push(id);
        }
        let mut current = id;
        while let Some(location) = self.parent_location(current) {
            let parent = location.parent();
            if matches!(
                self.node(parent).map(|node| &node.kind),
                Some(NodeKind::Popover { .. })
            ) {
                if !matches!(location, ParentLocation::OrdinaryIndex { index: 0, .. }) {
                    break;
                }
                targets.push(parent);
            }
            current = parent;
        }
        targets.reverse();
        targets
    }

    /// A popover with content to present, as opposed to a hover region.
    fn presents(&self, id: u64) -> bool {
        self.node(id).is_some_and(|node| {
            matches!(node.kind, NodeKind::Popover { .. }) && node.children.len() > 1
        })
    }

    fn open_popover(&mut self, id: u64) -> bool {
        self.popovers.pending.remove(&id);
        let opened = self.popovers.open.insert(id);
        if opened {
            self.popovers.counters.opened += 1;
        }
        opened
    }

    fn close_popover(&mut self, id: u64) -> bool {
        self.popovers.pending.remove(&id);
        let closed = self.popovers.open.remove(&id);
        if closed {
            self.popovers.counters.closed += 1;
        }
        closed
    }

    fn popover_hover_edge(&mut self, id: u64, entered: bool) {
        if !self.presents(id) {
            return;
        }
        if entered {
            let delay = match self.node(id).map(|node| &node.kind) {
                Some(NodeKind::Popover { delay_ms, .. }) => *delay_ms,
                _ => 0,
            };
            if delay == 0 {
                self.open_popover(id);
            } else if !self.popovers.open.contains(&id) {
                self.popovers.pending.insert(id);
            }
        } else {
            self.popovers.pending.remove(&id);
            if !self.popovers.focus_within.contains(&id) {
                self.close_popover(id);
            }
        }
    }

    /// The delay a hovered popover is waiting out, when it is waiting.
    pub fn popover_delay(&self, id: u64) -> Option<u32> {
        if !self.popovers.pending.contains(&id) {
            return None;
        }
        match self.node(id).map(|node| &node.kind) {
            Some(NodeKind::Popover { delay_ms, .. }) => Some(*delay_ms),
            _ => None,
        }
    }

    /// The delay has elapsed. Opens the popover only if the pointer is still
    /// resting on its anchor; reports whether it opened.
    pub fn popover_elapse(&mut self, id: u64) -> bool {
        self.popovers.pending.remove(&id) && self.hovered.contains(&id) && self.open_popover(id)
    }

    /// Every popover waiting out a delay. A runner without a clock elapses
    /// these when a specification waits.
    pub fn pending_popovers(&self) -> Vec<u64> {
        let mut pending = self.popovers.pending.iter().copied().collect::<Vec<_>>();
        pending.sort_unstable();
        pending
    }

    /// Keyboard focus entered or left a popover. Reports whether the popover
    /// opened or closed.
    pub fn popover_focus(&mut self, id: u64, within: bool) -> bool {
        if !self.presents(id) {
            return false;
        }
        if within {
            self.popovers.focus_within.insert(id);
            self.open_popover(id)
        } else {
            self.popovers.focus_within.remove(&id);
            !self.hovered.contains(&id) && self.close_popover(id)
        }
    }

    /// Focus moved to `focused`, or left every control. Updates each popover
    /// the move entered or left, and returns those whose presentation changed.
    pub fn popover_focus_moved(&mut self, focused: Option<u64>) -> Vec<u64> {
        let mut containing = Vec::new();
        let mut current = focused;
        while let Some(id) = current {
            if self.presents(id) {
                containing.push(id);
            }
            current = self.parent(id).map(|(parent, _)| parent);
        }
        let mut left = self
            .popovers
            .focus_within
            .iter()
            .copied()
            .filter(|id| !containing.contains(id))
            .collect::<Vec<_>>();
        left.sort_unstable();
        let mut changed = Vec::new();
        for id in left {
            if self.popover_focus(id, false) {
                changed.push(id);
            }
        }
        for id in containing {
            if !self.popovers.focus_within.contains(&id) && self.popover_focus(id, true) {
                changed.push(id);
            }
        }
        changed
    }

    /// Escape closes every presenting popover and cancels every pending one.
    /// Returns the popovers it closed; each stays closed until the pointer or
    /// focus enters it again.
    pub fn dismiss_popovers(&mut self) -> Vec<u64> {
        let mut closed = self.popovers.open.drain().collect::<Vec<_>>();
        closed.sort_unstable();
        self.popovers.pending.clear();
        self.popovers.focus_within.clear();
        self.popovers.counters.dismissed += closed.len() as u64;
        closed
    }

    pub fn popover_open(&self, id: u64) -> bool {
        self.popovers.open.contains(&id)
    }

    pub fn popover_counters(&self) -> PopoverCounters {
        self.popovers.counters
    }

    pub fn keyboard_counters(&self) -> KeyboardCounters {
        self.keyboard.counters
    }

    /// Whether a person can perceive `id`: nothing above it is the content of
    /// a closed popover or the pane of a collapsed split.
    fn is_presented(&self, id: u64) -> bool {
        let mut current = id;
        while let Some(location) = self.parent_location(current) {
            let parent = location.parent();
            if let ParentLocation::OrdinaryIndex { index, .. } = location
                && self
                    .node(parent)
                    .and_then(|node| node.kind.hidden_pane())
                    .is_some_and(|hidden| hidden == index)
            {
                return false;
            }
            if !matches!(location, ParentLocation::OrdinaryIndex { index: 0, .. })
                && matches!(
                    self.node(parent).map(|node| &node.kind),
                    Some(NodeKind::Popover { .. })
                )
                && !self.popovers.open.contains(&parent)
            {
                return false;
            }
            current = parent;
        }
        true
    }

    /// `id` and its ancestors, from the mounted root down to `id`.
    fn path_from_root(&self, id: u64) -> Vec<u64> {
        let mut path = vec![id];
        let mut current = id;
        while let Some(location) = self.parent_location(current) {
            current = location.parent();
            path.push(current);
        }
        path.reverse();
        path
    }

    /// Whether `a` comes before `b` in document order, the order Tab visits.
    /// An ancestor comes before its descendants.
    fn precedes(&self, a: u64, b: u64) -> bool {
        let (left, right) = (self.path_from_root(a), self.path_from_root(b));
        let shared = left
            .iter()
            .zip(&right)
            .take_while(|(left, right)| left == right)
            .count();
        match (left.get(shared), right.get(shared)) {
            (None, _) => true,
            (Some(_), None) => false,
            (Some(first), Some(second)) => {
                self.children_of(left[shared - 1])
                    .find(|child| child == first || child == second)
                    == Some(*first)
            }
        }
    }

    /// Whether a keystroke may reach the shortcuts of `region` while a modal
    /// dialog is active: only those declared inside it may.
    fn region_live(&self, region: u64) -> bool {
        self.dialog
            .is_none_or(|dialog| self.is_descendant_of(region, dialog))
            && self.is_presented(region)
    }

    /// The shortcut a keystroke reaches, with keyboard focus on `focused`.
    ///
    /// The regions enclosing focus are asked first, innermost first, with both
    /// their window and focus shortcuts; then every other live region's window
    /// shortcuts, where the last in document order wins a chord two declare. A
    /// modal dialog leaves only the regions inside it live. A keystroke that
    /// would type a character into a focused text field is text, and reaches
    /// no shortcut. `matches` compares one declared chord, in canonical
    /// spelling, with the keystroke; every comparison is counted.
    pub fn resolve_shortcut(
        &mut self,
        focused: Option<u64>,
        types_character: bool,
        matches: impl Fn(&str) -> bool,
    ) -> Option<ShortcutMatch> {
        self.keyboard.counters.offered += 1;
        let focused = focused.filter(|id| self.nodes.contains_key(id));
        let editing = focused.is_some_and(|id| {
            matches!(
                self.node(id).map(|node| &node.kind),
                Some(
                    NodeKind::TextInput { enabled: true, .. }
                        | NodeKind::Textarea {
                            enabled: true,
                            read_only: false,
                            ..
                        }
                )
            )
        });
        if editing && types_character {
            return None;
        }
        let mut compared = 0;
        let mut found = None;
        let mut enclosing = Vec::new();
        let mut current = focused;
        while let Some(id) = current {
            if self.keyboard.regions.contains(&id) {
                enclosing.push(id);
            }
            if Some(id) == self.dialog {
                break;
            }
            current = self.parent_location(id).map(ParentLocation::parent);
        }
        'enclosing: for region in &enclosing {
            if !self.region_live(*region) {
                continue;
            }
            let declared = match self.node(*region).map(|node| &node.kind) {
                Some(NodeKind::Popover { shortcuts, .. }) => shortcuts.as_slice(),
                // A split's region is its divider, not the panes beside it.
                Some(NodeKind::Split { shortcuts, .. }) if focused == Some(*region) => {
                    shortcuts.as_slice()
                }
                _ => &[],
            };
            for (index, shortcut) in declared.iter().enumerate() {
                compared += 1;
                if matches(&shortcut.keys) {
                    found = Some((*region, index, shortcut.keys.clone()));
                    break 'enclosing;
                }
            }
        }
        if found.is_none() {
            let mut candidates = Vec::new();
            for region in &self.keyboard.window_regions {
                if enclosing.contains(region) || !self.region_live(*region) {
                    continue;
                }
                if let Some(NodeKind::Popover { shortcuts, .. }) =
                    self.node(*region).map(|node| &node.kind)
                {
                    for (index, shortcut) in shortcuts.iter().enumerate() {
                        if shortcut.scope != ShortcutScope::Window {
                            continue;
                        }
                        compared += 1;
                        if matches(&shortcut.keys) {
                            candidates.push((*region, index, shortcut.keys.clone()));
                            break;
                        }
                    }
                }
            }
            found = candidates.into_iter().reduce(|kept, next| {
                if self.precedes(kept.0, next.0) {
                    next
                } else {
                    kept
                }
            });
        }
        self.keyboard.counters.compared += compared;
        let (region, index, keys) = found?;
        self.keyboard.counters.matched += 1;
        Some(ShortcutMatch {
            region,
            event: region | SHORTCUT_EVENT_BIT,
            index: index as u64,
            keys,
        })
    }

    /// The control focus moves to for the regions that asked since this was
    /// last called: the first enabled control inside the one latest in
    /// document order, if it is live and has one. A request made behind a
    /// modal dialog, or inside a closed popover, moves nothing.
    pub fn take_focus_request(&mut self) -> Option<u64> {
        let requests = std::mem::take(&mut self.keyboard.requests);
        let region = requests
            .into_iter()
            .filter(|region| self.nodes.contains_key(region) && self.region_live(*region))
            .reduce(|kept, next| {
                if self.precedes(kept, next) {
                    next
                } else {
                    kept
                }
            })?;
        let mut pending = vec![region];
        while let Some(id) = pending.pop() {
            let node = self.node(id)?;
            if node.kind.focus_identity().is_some() {
                self.keyboard.counters.focused += 1;
                return Some(id);
            }
            if matches!(node.kind, NodeKind::Popover { .. }) && !self.popovers.open.contains(&id) {
                pending.extend(node.children.first().copied());
            } else if let Some(hidden) = node.kind.hidden_pane() {
                let shown = node
                    .children
                    .iter()
                    .enumerate()
                    .rev()
                    .filter(|(index, _)| *index != hidden)
                    .map(|(_, child)| *child)
                    .collect::<Vec<_>>();
                pending.extend(shown);
            } else {
                pending.extend(self.children_of(id).rev());
            }
        }
        None
    }

    /// Collect the interaction state of nodes about to be retired, by
    /// identity, while their ancestry is still mounted.
    fn carry_interaction(&mut self, removed: &[u64]) -> InteractionCarry {
        let mut carry = InteractionCarry::default();
        for id in removed {
            self.keyboard.regions.remove(id);
            self.keyboard.window_regions.remove(id);
            if let Some(serial) = self.keyboard.serials.remove(id) {
                carry.focus_serials.insert(self.identity(*id), serial);
            }
            if let Some(size) = self.canvas_sizes.remove(id) {
                carry.canvas_sizes.insert(self.identity(*id), size);
            }
            let hovered = self.hovered.remove(id);
            let open = self.popovers.open.remove(id);
            let pending = self.popovers.pending.remove(id);
            let focus = self.popovers.focus_within.remove(id);
            if hovered || open || pending || focus {
                let identity = self.identity(*id);
                if hovered {
                    carry.hovered.insert(identity.clone());
                }
                if open {
                    carry.open.insert(identity.clone());
                }
                if pending {
                    carry.pending.insert(identity.clone());
                }
                if focus {
                    carry.focus_within.insert(identity);
                }
            }
        }
        carry
    }

    /// Give carried interaction state to the staged nodes that took the
    /// retired nodes' identities.
    fn restore_interaction(&mut self, staged: &[u64], carry: InteractionCarry) {
        // A region asks for focus when its serial is one its identity has not
        // asked with before: new, or changed since the region it replaces.
        for region in std::mem::take(&mut self.keyboard.staged_requests) {
            let Some(NodeKind::Popover { focus_serial, .. }) =
                self.node(region).map(|node| &node.kind)
            else {
                continue;
            };
            let serial = *focus_serial;
            let before = carry.focus_serials.get(&self.identity(region)).copied();
            self.keyboard.serials.insert(region, serial);
            if before != Some(serial) {
                self.keyboard.requests.push(region);
            }
        }
        if carry.is_empty() {
            return;
        }
        for id in staged {
            let Some(node) = self.node(*id) else {
                continue;
            };
            if matches!(node.kind, NodeKind::Canvas { size: true, .. }) {
                if let Some(size) = carry.canvas_sizes.get(&self.identity(*id)) {
                    self.canvas_sizes.insert(*id, *size);
                }
                continue;
            }
            if !tracks_hover(&node.kind) {
                continue;
            }
            let presents = self.presents(*id);
            let identity = self.identity(*id);
            if carry.hovered.contains(&identity) {
                self.hovered.insert(*id);
            }
            if presents {
                if carry.open.contains(&identity) {
                    self.popovers.open.insert(*id);
                }
                if carry.pending.contains(&identity) {
                    self.popovers.pending.insert(*id);
                }
                if carry.focus_within.contains(&identity) {
                    self.popovers.focus_within.insert(*id);
                }
            }
        }
    }

    /// Record `size` as the size reported to a canvas whose owner handles
    /// its size. False when the canvas is gone, does not ask, or has already
    /// heard this size, so nothing is to be delivered.
    pub(crate) fn report_canvas_size(&mut self, id: u64, size: (u32, u32)) -> bool {
        if !matches!(
            self.node(id).map(|node| &node.kind),
            Some(NodeKind::Canvas { size: true, .. })
        ) {
            return false;
        }
        self.canvas_sizes.insert(id, size) != Some(size)
    }

    /// The size last reported to a canvas, if one has been.
    pub(crate) fn reported_canvas_size(&self, id: u64) -> Option<(u32, u32)> {
        self.canvas_sizes.get(&id).copied()
    }

    /// Modal input policy: a newly active dialog retires background pointer
    /// and popover state without dispatching callbacks.
    fn retire_behind_dialog(&mut self, dialog: u64) {
        let blocked = self
            .hovered
            .iter()
            .chain(self.popovers.open.iter())
            .chain(self.popovers.pending.iter())
            .chain(self.popovers.focus_within.iter())
            .copied()
            .filter(|id| !self.is_descendant_of(*id, dialog))
            .collect::<Vec<_>>();
        for id in blocked {
            self.hovered.remove(&id);
            self.popovers.focus_within.remove(&id);
            self.close_popover(id);
        }
    }

    pub fn is_descendant_of(&self, mut id: u64, ancestor: u64) -> bool {
        loop {
            if id == ancestor {
                return true;
            }
            match self
                .nodes
                .get(&id)
                .and_then(|entry| entry.parent.map(ParentLocation::parent))
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
        // A presenting popover's surface, and its content, float above the
        // window rather than inside any scrolling ancestor.
        if self.presents(id) {
            return found;
        }
        let mut current = self.nodes.get(&id).and_then(|entry| entry.parent);
        while let Some(parent) = current {
            let parent_id = parent.parent();
            let Some(entry) = self.nodes.get(&parent_id) else {
                break;
            };
            if matches!(parent, ParentLocation::OrdinaryIndex { index, .. } if index > 0)
                && matches!(entry.node.kind, NodeKind::Popover { .. })
            {
                break;
            }
            if matches!(
                entry.node.kind,
                NodeKind::Scroll { .. } | NodeKind::VirtualList { .. }
            ) {
                found.push(parent_id);
            }
            current = entry.parent;
        }
        found
    }

    /// Which child of `ancestor` contains `id`, by position.
    ///
    /// A virtual list's rows below the fold are in the mounted graph but have
    /// no element and no laid-out bounds, so bringing one into view is an
    /// index, not a rectangle. `None` when `id` is not under `ancestor`.
    pub fn child_index_containing(&self, ancestor: u64, id: u64) -> Option<usize> {
        let mut current = id;
        loop {
            let parent = self
                .nodes
                .get(&current)
                .and_then(|entry| entry.parent)?
                .parent();
            if parent == ancestor {
                return self
                    .children_of(ancestor)
                    .position(|child| child == current);
            }
            current = parent;
        }
    }

    pub fn first_focusable_in(&self, ancestor: u64) -> Option<u64> {
        self.nodes_preorder().into_iter().find_map(|node| {
            (self.is_descendant_of(node.id, ancestor) && node.kind.focus_identity().is_some())
                .then_some(node.id)
        })
    }

    /// Every focusable control, in the order Tab visits them.
    pub fn focus_order(&self) -> Vec<u64> {
        self.nodes_preorder()
            .into_iter()
            .filter_map(|node| node.kind.focus_identity().is_some().then_some(node.id))
            .collect()
    }

    /// Where focus should go when the control that had it is gone from this
    /// graph entirely.
    ///
    /// The control held position `was_at` in the previous graph's focus order.
    /// Focus moves to whatever now occupies that position — which, when a row
    /// is deleted from a list, is the row that followed it — and to the last
    /// focusable control when the removed one was at the end. A graph with
    /// nothing focusable yields nothing, because there is nowhere to go.
    pub fn focus_destination(&self, was_at: usize) -> Option<u64> {
        let order = self.focus_order();
        if order.is_empty() {
            return None;
        }
        Some(order[was_at.min(order.len() - 1)])
    }

    pub fn find_focus_identity(&self, identity: &(u8, String)) -> Option<u64> {
        self.nodes_preorder().into_iter().find_map(|node| {
            (node.kind.focus_identity().as_ref() == Some(identity)).then_some(node.id)
        })
    }

    /// IDs below virtual-list nodes. They remain in the canonical graph for
    /// semantic lookup and routing but do not receive eager GPUI entities.
    #[cfg(test)]
    pub fn virtual_descendant_ids(&self) -> HashSet<u64> {
        let mut result = HashSet::new();
        for entry in self.nodes.values() {
            if matches!(entry.node.kind, NodeKind::VirtualList { .. }) {
                let mut pending = self.children_of(entry.node.id).collect::<Vec<_>>();
                while let Some(id) = pending.pop() {
                    if result.insert(id) && self.nodes.contains_key(&id) {
                        pending.extend(self.children_of(id));
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

    /// Apply one keyed-container transaction. This is deliberately internal
    /// until the Roc ABI can supply the same complete atomic unit.
    fn apply_keyed(
        &mut self,
        container: u64,
        base_revision: u64,
        new_revision: u64,
        operations: Vec<KeyedGraphOperation>,
    ) -> Result<KeyedGraphApply, String> {
        self.apply_keyed_inner::<false>(container, base_revision, new_revision, operations)
    }

    fn apply_keyed_inner<const MEASURE: bool>(
        &mut self,
        container: u64,
        base_revision: u64,
        new_revision: u64,
        operations: Vec<KeyedGraphOperation>,
    ) -> Result<KeyedGraphApply, String> {
        let validate_started = MEASURE.then(Instant::now);
        let previous_dialog = self.dialog;
        let entry = self
            .nodes
            .get(&container)
            .ok_or_else(|| format!("keyed container {container} is missing"))?;
        if entry.keyed_children.is_none() && !entry.node.children.is_empty() {
            return Err("an ordinary container cannot become keyed after mounting children".into());
        }
        let was_keyed = entry.keyed_children.is_some();
        let mut order = self
            .nodes
            .get_mut(&container)
            .expect("validated container")
            .keyed_children
            .take()
            .unwrap_or_default();
        if let Err(error) = order.check_revision(base_revision) {
            self.nodes
                .get_mut(&container)
                .expect("validated container")
                .keyed_children = was_keyed.then_some(order);
            return Err(format!("keyed order rejected transaction: {error:?}"));
        }
        if new_revision <= base_revision {
            self.nodes
                .get_mut(&container)
                .expect("validated container")
                .keyed_children = was_keyed.then_some(order);
            return Err(format!(
                "keyed order rejected transaction: {:?}",
                KeyedOrderError::StaleNewRevision {
                    current: base_revision,
                    proposed: new_revision
                }
            ));
        }

        struct FragmentPlan {
            key: KeyedChildKey,
            root: u64,
            nodes: Vec<Node>,
            validated: ValidatedFragment,
        }

        type PreparedFragments = (Vec<FragmentPlan>, Vec<u64>, u64, Vec<KeyedNativeEdit>);
        let owner = self.component_owner(container);
        let mut journal = KeyedOrderJournal::new(&mut order);
        let prepared = (|| -> Result<PreparedFragments, String> {
            let mut fragments = Vec::new();
            let mut native_edits = Vec::new();
            let mut staged_ids = NodeSet::default();
            let mut staged_instances = NodeSet::default();
            let mut graph_visits = 0;

            for operation in operations {
                match operation {
                    KeyedGraphOperation::Insert {
                        key,
                        before,
                        root,
                        nodes,
                    } => {
                        let validated =
                            validate_fragment(root, &nodes, &NodeSet::default(), owner, |id| {
                                self.node(id)
                            })?;
                        graph_visits += validated.visits;
                        let instance = match validated
                            .lookup(root, &nodes, |id| self.node(id))
                            .map(|node| &node.kind)
                        {
                            Some(NodeKind::Boundary { instance }) => *instance,
                            _ => {
                                return Err("a keyed item root must be a component boundary".into());
                            }
                        };
                        Self::validate_keyed_staged_fragment(
                            self,
                            &nodes,
                            &mut staged_ids,
                            &mut staged_instances,
                            None,
                        )?;
                        journal
                            .insert(key, root, instance, before)
                            .map_err(|error| {
                                format!("keyed order rejected transaction: {error:?}")
                            })?;
                        native_edits.push(KeyedNativeEdit::Insert { key, before, root });
                        fragments.push(FragmentPlan {
                            key,
                            root,
                            nodes,
                            validated,
                        });
                    }
                    KeyedGraphOperation::Remove { key } => {
                        let root = journal
                            .child(key)
                            .map_err(|error| {
                                format!("keyed order rejected transaction: {error:?}")
                            })?
                            .root;
                        journal.remove(key).map_err(|error| {
                            format!("keyed order rejected transaction: {error:?}")
                        })?;
                        native_edits.push(KeyedNativeEdit::Remove { key, root });
                    }
                    KeyedGraphOperation::Move { key, before } => {
                        journal.move_before(key, before).map_err(|error| {
                            format!("keyed order rejected transaction: {error:?}")
                        })?;
                        native_edits.push(KeyedNativeEdit::Move { key, before });
                    }
                    KeyedGraphOperation::Set { key, root, nodes } => {
                        let child = journal.child(key).map_err(|error| {
                            format!("keyed order rejected transaction: {error:?}")
                        })?;
                        let validated =
                            validate_fragment(root, &nodes, &NodeSet::default(), owner, |id| {
                                self.node(id)
                            })?;
                        graph_visits += validated.visits;
                        match validated
                            .lookup(root, &nodes, |id| self.node(id))
                            .map(|node| &node.kind)
                        {
                            Some(NodeKind::Boundary { instance })
                                if *instance == child.instance => {}
                            Some(NodeKind::Boundary { .. }) => {
                                return Err(
                                    "a keyed Set must preserve its component instance".into()
                                );
                            }
                            _ => {
                                return Err("a keyed item root must be a component boundary".into());
                            }
                        }
                        Self::validate_keyed_staged_fragment(
                            self,
                            &nodes,
                            &mut staged_ids,
                            &mut staged_instances,
                            Some(child.instance),
                        )?;
                        journal.replace(key, root).map_err(|error| {
                            format!("keyed order rejected transaction: {error:?}")
                        })?;
                        native_edits.push(KeyedNativeEdit::Set {
                            key,
                            old_root: child.root,
                            root,
                        });
                        fragments.push(FragmentPlan {
                            key,
                            root,
                            nodes,
                            validated,
                        });
                    }
                }
            }

            let mut removed_roots = Vec::new();
            for (key, original) in &journal.originals {
                let final_child = journal.order.children.get(key);
                if let Some(original) = original
                    && final_child.is_none_or(|child| child.root != original.root)
                {
                    removed_roots.push(original.root);
                }
            }
            let mut removed_ids = Vec::new();
            for root in removed_roots {
                let mut pending = vec![root];
                while let Some(id) = pending.pop() {
                    graph_visits += 1;
                    removed_ids.push(id);
                    pending.extend(self.children_of(id));
                }
            }
            let removed = removed_ids.iter().copied().collect::<NodeSet>();

            fragments.retain(|fragment| {
                journal
                    .order
                    .children
                    .get(&fragment.key)
                    .is_some_and(|child| child.root == fragment.root)
            });
            let mut labels = HashSet::new();
            let mut staged_dialog = false;
            for fragment in &fragments {
                for node in &fragment.nodes {
                    match &node.kind {
                        NodeKind::Dialog { .. } => {
                            if staged_dialog || self.dialog.is_some_and(|id| !removed.contains(&id))
                            {
                                return Err(
                                    "mounted graph would contain more than one modal dialog".into(),
                                );
                            }
                            staged_dialog = true;
                        }
                        NodeKind::TextInput { label, .. } => {
                            let owner = fragment.validated.input_owners[&node.id];
                            if !labels.insert((owner, label.clone()))
                                || self
                                    .input_labels
                                    .get(&(owner, label.clone()))
                                    .is_some_and(|id| !removed.contains(id))
                            {
                                return Err(format!(
                                    "mounted graph contains duplicate text input label {label:?}"
                                ));
                            }
                        }
                        NodeKind::Boundary { instance }
                            if self
                                .boundary_instances
                                .get(instance)
                                .is_some_and(|id| !removed.contains(id)) =>
                        {
                            return Err(format!(
                                "component instance {instance} is already mounted"
                            ));
                        }
                        _ => {}
                    }
                }
            }
            Ok((fragments, removed_ids, graph_visits, native_edits))
        })();

        let (fragments, removed_ids, graph_visits, native_edits) = match prepared {
            Ok(prepared) => prepared,
            Err(error) => {
                journal.rollback();
                self.nodes
                    .get_mut(&container)
                    .expect("validated container")
                    .keyed_children = was_keyed.then_some(order);
                return Err(error);
            }
        };
        journal.order.revision = new_revision;
        let original_reads = journal.original_reads;
        let first_touches = journal.first_touches;
        drop(journal);
        let validate_ns = validate_started.map(elapsed_ns).unwrap_or(0);
        let apply_started = MEASURE.then(Instant::now);

        let old_size = self.nodes[&container].subtree_size;
        let mut removed_instances = Vec::new();
        let carried = self.carry_interaction(&removed_ids);
        for id in &removed_ids {
            let entry = self.nodes.remove(id).expect("prevalidated retirement");
            match entry.node.kind {
                NodeKind::Boundary { instance } => {
                    self.boundary_instances.remove(&instance);
                    removed_instances.push(instance);
                }
                NodeKind::TextInput { label, .. } => {
                    let owner = self.input_owners.remove(id).flatten();
                    self.input_labels.remove(&(owner, label));
                }
                NodeKind::Dialog { .. } => self.dialog = None,
                _ => {}
            }
        }
        let mut staged = 0;
        let mut staged_ids = Vec::new();
        let mut staged_instances = Vec::new();
        for fragment in fragments {
            staged += fragment.nodes.len() as u64;
            staged_ids.extend(fragment.nodes.iter().map(|node| node.id));
            staged_instances.extend(fragment.nodes.iter().filter_map(|node| match node.kind {
                NodeKind::Boundary { instance } => Some(instance),
                _ => None,
            }));
            self.insert_nodes(fragment.nodes, &fragment.validated);
            let child = order.children.get(&fragment.key).expect("final keyed root");
            let root = self.nodes.get_mut(&fragment.root).expect("inserted root");
            root.parent = Some(ParentLocation::Keyed {
                container,
                key: fragment.key,
                instance: child.instance,
            });
            root.segment = IdentitySegment::Boundary {
                instance: child.instance,
            };
        }
        let keyed_size = old_size - removed_ids.len() as u64 + staged;
        if keyed_size != old_size {
            self.nodes
                .get_mut(&container)
                .expect("validated container")
                .subtree_size = keyed_size;
            let mut ancestor = self.nodes[&container].parent.map(ParentLocation::parent);
            while let Some(id) = ancestor {
                let entry = self.nodes.get_mut(&id).expect("mounted ancestor");
                entry.subtree_size = entry.subtree_size - old_size + keyed_size;
                ancestor = entry.parent.map(ParentLocation::parent);
            }
        }
        self.nodes
            .get_mut(&container)
            .expect("validated container")
            .keyed_children = Some(order);
        self.restore_interaction(&staged_ids, carried);
        if self.dialog != previous_dialog
            && let Some(dialog) = self.dialog
        {
            self.retire_behind_dialog(dialog);
        }
        Ok(KeyedGraphApply {
            revision: new_revision,
            staged,
            removed: removed_ids.len() as u64,
            graph_visits,
            original_reads,
            first_touches,
            staged_ids,
            removed_ids,
            staged_instances,
            removed_instances,
            validate_ns,
            apply_ns: apply_started.map(elapsed_ns).unwrap_or(0),
            native_edits,
        })
    }

    fn validate_keyed_staged_fragment(
        &self,
        nodes: &[Node],
        staged_ids: &mut NodeSet,
        staged_instances: &mut NodeSet,
        replacing_instance: Option<u64>,
    ) -> Result<(), String> {
        for node in nodes {
            if node.id <= self.max_seen_node_id || !staged_ids.insert(node.id) {
                return Err("keyed transaction reused a previously issued node id".into());
            }
            if let NodeKind::Boundary { instance } = node.kind {
                if !staged_instances.insert(instance) {
                    return Err(format!(
                        "component instance {instance} appears twice in keyed transaction"
                    ));
                }
                if Some(instance) != replacing_instance
                    && self.max_seen_instance.is_some_and(|max| instance <= max)
                {
                    return Err(format!("component instance {instance} was retired"));
                }
            }
        }
        Ok(())
    }

    fn apply_inner<const MEASURE: bool>(&mut self, patch: Patch) -> Result<GraphApply, String> {
        let patch = match patch {
            Patch::Keyed {
                container,
                base_revision,
                new_revision,
                operations,
            } => {
                let keyed = if MEASURE {
                    self.apply_keyed_inner::<true>(
                        container,
                        base_revision,
                        new_revision,
                        operations,
                    )?
                } else {
                    self.apply_keyed(container, base_revision, new_revision, operations)?
                };
                return Ok(GraphApply {
                    facts: ApplyFacts {
                        kind: "keyed",
                        staged: keyed.staged,
                        removed: keyed.removed,
                        live: self.nodes.len() as u64,
                        scanned: 0,
                        retained_nodes: 0,
                        validation_visits: keyed.graph_visits,
                        validate_ns: keyed.validate_ns,
                        apply_ns: keyed.apply_ns,
                        keyed_graph_visits: keyed.graph_visits,
                        keyed_original_reads: keyed.original_reads,
                        keyed_first_touches: keyed.first_touches,
                    },
                    root: Some(container),
                    staged_ids: keyed.staged_ids,
                    removed_ids: keyed.removed_ids,
                    retired_root: false,
                    parent: None,
                    retained_roots: vec![],
                    removed_instances: keyed.removed_instances,
                    staged_instances: keyed.staged_instances,
                    keyed_edits: keyed.native_edits,
                });
            }
            patch => patch,
        };
        let previous_dialog = self.dialog;
        let validate_started = MEASURE.then(Instant::now);
        let (old_root, root, nodes, retained_roots) = match patch {
            Patch::NoChange => {
                let validate_ns = validate_started.map(elapsed_ns).unwrap_or(0);
                let apply_started = MEASURE.then(Instant::now);
                return Ok(GraphApply {
                    facts: ApplyFacts {
                        kind: "no_change",
                        staged: 0,
                        removed: 0,
                        live: self.nodes.len() as u64,
                        scanned: 0,
                        retained_nodes: 0,
                        validation_visits: 0,
                        validate_ns,
                        apply_ns: apply_started.map(elapsed_ns).unwrap_or(0),
                        keyed_graph_visits: 0,
                        keyed_original_reads: 0,
                        keyed_first_touches: 0,
                    },
                    root: None,
                    staged_ids: vec![],
                    removed_ids: vec![],
                    retired_root: false,
                    parent: None,
                    retained_roots: vec![],
                    removed_instances: vec![],
                    staged_instances: vec![],
                    keyed_edits: vec![],
                });
            }
            Patch::Mount { root, nodes } => (None, root, nodes, vec![]),
            Patch::Replace {
                old_root,
                root,
                nodes,
            } => (Some(old_root), root, nodes, vec![]),
            Patch::ReplaceRetaining {
                old_root,
                root,
                nodes,
                retained_roots,
            } => (Some(old_root), root, nodes, retained_roots),
            Patch::Keyed { .. } => unreachable!("keyed patch returned above"),
        };
        if old_root.is_none() && self.root.is_some() {
            return Err("application attempted to mount twice".into());
        }
        if let Some(id) = old_root
            && !self.nodes.contains_key(&id)
        {
            return Err(format!("replacement target {id} is missing"));
        }
        let parent_location = old_root.and_then(|id| self.parent_location(id));
        let parent = match parent_location {
            Some(ParentLocation::OrdinaryIndex { parent, index }) => Some((parent, index)),
            // A keyed child's identity segment is its boundary instance, not
            // its ordinal position. Avoid enumerating siblings merely to
            // validate and replace one keyed root.
            Some(ParentLocation::Keyed { container, .. }) => Some((container, 0)),
            None => None,
        };
        if old_root.is_some() && parent.is_none() && old_root != self.root {
            return Err("replacement target is detached".into());
        }
        let mut frontier = NodeSet::default();
        let mut retained_nodes = 0;
        let mut validation_visits = 0;
        for id in &retained_roots {
            if !frontier.insert(*id) {
                return Err(format!("duplicate retained root {id}"));
            }
            validation_visits += 1;
            let entry = self
                .nodes
                .get(id)
                .ok_or_else(|| format!("retained root {id} is not mounted"))?;
            if !matches!(entry.node.kind, NodeKind::Boundary { .. }) {
                return Err(format!("retained root {id} is not a component boundary"));
            }
            if Some(*id) == old_root {
                return Err("retain of replacement target must use NoChange".into());
            }
            retained_nodes += entry.subtree_size;
        }
        // Walk only the retired portion. Stopping at the frontier both proves
        // disjoint ancestry and avoids examining unchanged subtree interiors.
        let mut removed_ids = Vec::new();
        let mut found_frontier = NodeSet::default();
        let mut pending = old_root.into_iter().collect::<Vec<_>>();
        while let Some(id) = pending.pop() {
            if frontier.contains(&id) {
                found_frontier.insert(id);
                continue;
            }
            validation_visits += 1;
            removed_ids.push(id);
            pending.extend(self.children_of(id).rev());
        }
        if found_frontier != frontier {
            return Err("retained roots overlap or are outside the replacement target".into());
        }
        let removed = removed_ids.iter().copied().collect::<NodeSet>();
        let owner = parent.and_then(|(id, _)| self.component_owner(id));
        let validated = validate_fragment(root, &nodes, &frontier, owner, |id| self.node(id))?;
        validation_visits += validated.visits;
        for node in &nodes {
            if node.id <= self.max_seen_node_id {
                return Err("replacement reused a previously issued node id".into());
            }
            match &node.kind {
                NodeKind::Dialog { .. } if self.dialog.is_some_and(|id| !removed.contains(&id)) => {
                    return Err("mounted graph would contain more than one modal dialog".into());
                }
                NodeKind::TextInput { label, .. }
                    if self
                        .input_labels
                        .get(&(validated.input_owners[&node.id], label.clone()))
                        .is_some_and(|id| !removed.contains(id)) =>
                {
                    return Err(format!(
                        "mounted graph contains duplicate text input label {label:?}"
                    ));
                }
                NodeKind::Boundary { instance } => match self.boundary_instances.get(instance) {
                    Some(id) if !removed.contains(id) => {
                        return Err(format!("component instance {instance} is already mounted"));
                    }
                    None if self.max_seen_instance.is_some_and(|max| *instance <= max) => {
                        return Err(format!("component instance {instance} was retired"));
                    }
                    _ => {}
                },
                _ => {}
            }
        }
        let outer_identity = parent.map(|(id, _)| self.identity(id)).unwrap_or_default();
        let root_segment = if let Some((parent_id, position)) = parent {
            let node = validated
                .lookup(root, &nodes, |id| self.node(id))
                .expect("validated root");
            let occurrence = node
                .kind
                .sibling_name()
                .map(|name| {
                    self.children_of(parent_id)
                        .take(position)
                        .filter(|id| {
                            let other = &self.nodes[id].node;
                            other.kind.tag() == node.kind.tag()
                                && other.kind.sibling_name().as_ref() == Some(&name)
                        })
                        .count() as u32
                })
                .unwrap_or(0);
            IdentitySegment::of(node, position, occurrence)
        } else {
            IdentitySegment::of(
                validated
                    .lookup(root, &nodes, |id| self.node(id))
                    .expect("validated root"),
                0,
                0,
            )
        };
        let parent_segments_unchanged = old_root
            .and_then(|id| self.cached_segment(id))
            .is_some_and(|old_segment| old_segment == &root_segment);
        // A live component may be rebuilt or retained only in its original
        // structural scope. Native GPUI element identity includes that path.
        let mut identity = outer_identity;
        let mut pending = vec![(root, root_segment.clone(), false)];
        // Child scratch reused across nodes: clearing a Vec costs its live
        // length. The occurrence map is NOT reused — HashMap::clear walks the
        // retained capacity, so a map grown by one 10,000-child parent would
        // be re-walked for every later node.
        let mut children = Vec::new();
        while let Some((id, segment, exiting)) = pending.pop() {
            if exiting {
                identity.pop();
                continue;
            }
            identity.push(segment);
            if frontier.contains(&id) {
                if self.identity(id) != identity {
                    return Err(format!("retained component {id} changed structural scope"));
                }
                identity.pop();
                continue;
            }
            let node = &nodes[validated.indices[&id]];
            if let NodeKind::Boundary { instance } = node.kind
                && let Some(old) = self.boundary_instances.get(&instance)
                && self.identity(*old) != identity
            {
                return Err(format!(
                    "component instance {instance} changed structural scope"
                ));
            }
            pending.push((id, root_segment.clone(), true));
            let mut occurrences = HashMap::new();
            children.clear();
            for (position, child) in node.children.iter().enumerate() {
                let child_node = validated
                    .lookup(*child, &nodes, |id| self.node(id))
                    .expect("validated child");
                let occurrence = match child_node.kind.sibling_name() {
                    Some(name) => {
                        let count = occurrences
                            .entry((child_node.kind.tag(), name.into_owned()))
                            .or_insert(0);
                        let previous = *count;
                        *count += 1;
                        previous
                    }
                    None => 0,
                };
                children.push((
                    *child,
                    IdentitySegment::of(child_node, position, occurrence),
                    false,
                ));
            }
            pending.extend(children.drain(..).rev());
        }
        let validate_ns = validate_started.map(elapsed_ns).unwrap_or(0);
        let apply_started = MEASURE.then(Instant::now);
        let old_size = old_root.and_then(|id| self.subtree_size(id)).unwrap_or(0);
        let staged_ids = nodes.iter().map(|node| node.id).collect::<Vec<_>>();
        let staged_instances = nodes
            .iter()
            .filter_map(|node| match node.kind {
                NodeKind::Boundary { instance } => Some(instance),
                _ => None,
            })
            .collect();
        let mut removed_instances = Vec::new();
        let retired_root = old_root == self.root && old_root.is_some() && frontier.is_empty();
        let carried = self.carry_interaction(&removed_ids);
        for id in &removed_ids {
            let entry = self.nodes.remove(id).expect("validated retirement");
            match entry.node.kind {
                NodeKind::Boundary { instance } => {
                    self.boundary_instances.remove(&instance);
                    removed_instances.push(instance);
                }
                NodeKind::TextInput { label, .. } => {
                    let owner = self.input_owners.remove(id).flatten();
                    self.input_labels.remove(&(owner, label));
                }
                NodeKind::Dialog { .. } => {
                    self.dialog = None;
                }
                _ => {}
            }
        }
        self.insert_nodes(nodes, &validated);
        self.nodes.get_mut(&root).expect("validated root").parent = parent_location;
        self.nodes.get_mut(&root).expect("validated root").segment = root_segment;
        let new_size = self.nodes[&root].subtree_size;
        if let Some((parent_id, position)) = parent {
            if let Some(ParentLocation::Keyed { key, .. }) = parent_location {
                self.nodes
                    .get_mut(&parent_id)
                    .expect("validated keyed parent")
                    .keyed_children
                    .as_mut()
                    .expect("keyed parent has order")
                    .children
                    .get_mut(&key)
                    .expect("keyed parent contains child")
                    .root = root;
            } else {
                self.nodes
                    .get_mut(&parent_id)
                    .expect("validated parent")
                    .node
                    .children[position] = root;
            }
            // Replacing a component's content preserves its boundary key.
            // None of the other siblings' occurrence keys can change, even
            // when this parent has thousands of directly mounted components.
            if !parent_segments_unchanged {
                self.refresh_child_segments(parent_id);
            }
            let mut ancestor = Some(parent_id);
            while let Some(id) = ancestor {
                let entry = self.nodes.get_mut(&id).expect("mounted ancestor");
                entry.subtree_size = entry.subtree_size - old_size + new_size;
                ancestor = entry.parent.map(ParentLocation::parent);
            }
        } else {
            self.root = Some(root);
        }
        self.restore_interaction(&staged_ids, carried);
        if self.dialog != previous_dialog
            && let Some(dialog) = self.dialog
        {
            // Modal input policy suppresses background exit callbacks. Retire
            // blocked hover and popover state without dispatching callbacks or
            // walking unrelated mounted nodes.
            self.retire_behind_dialog(dialog);
        }
        let facts = ApplyFacts {
            kind: if old_root.is_some() {
                "replace"
            } else {
                "mount"
            },
            staged: staged_ids.len() as u64,
            removed: removed_ids.len() as u64,
            live: self.nodes.len() as u64,
            scanned: u64::from(parent.is_some()),
            retained_nodes,
            validation_visits,
            validate_ns,
            apply_ns: apply_started.map(elapsed_ns).unwrap_or(0),
            keyed_graph_visits: 0,
            keyed_original_reads: 0,
            keyed_first_touches: 0,
        };
        Ok(GraphApply {
            facts,
            root: Some(root),
            staged_ids,
            removed_ids,
            retired_root,
            parent,
            retained_roots,
            removed_instances,
            staged_instances,
            keyed_edits: vec![],
        })
    }

    fn insert_nodes(&mut self, nodes: Vec<Node>, validated: &ValidatedFragment) {
        let inserted_ids = nodes.iter().map(|node| node.id).collect::<NodeSet>();
        for node in nodes {
            self.max_seen_node_id = self.max_seen_node_id.max(node.id);
            match &node.kind {
                NodeKind::Boundary { instance } => {
                    self.boundary_instances.insert(*instance, node.id);
                    self.max_seen_instance = Some(
                        self.max_seen_instance
                            .map_or(*instance, |max| max.max(*instance)),
                    );
                }
                NodeKind::TextInput { label, .. } => {
                    let owner = validated.input_owners[&node.id];
                    self.input_owners.insert(node.id, owner);
                    self.input_labels.insert((owner, label.clone()), node.id);
                }
                NodeKind::Dialog { .. } => {
                    self.dialog = Some(node.id);
                }
                NodeKind::Popover {
                    shortcuts,
                    focus_serial,
                    ..
                } => {
                    if !shortcuts.is_empty() {
                        self.keyboard.regions.insert(node.id);
                    }
                    if shortcuts
                        .iter()
                        .any(|shortcut| shortcut.scope == ShortcutScope::Window)
                    {
                        self.keyboard.window_regions.insert(node.id);
                    }
                    if *focus_serial != 0 {
                        self.keyboard.staged_requests.push(node.id);
                    }
                }
                // A divider's keys are live only while it holds focus itself.
                NodeKind::Split { shortcuts, .. } if !shortcuts.is_empty() => {
                    self.keyboard.regions.insert(node.id);
                }
                _ => {}
            }
            let segment = IdentitySegment::of(&node, 0, 0);
            self.nodes.insert(
                node.id,
                MountedNode {
                    node,
                    parent: None,
                    subtree_size: 1,
                    segment,
                    keyed_children: None,
                },
            );
        }
        let seeded = self
            .nodes
            .iter()
            .filter_map(|(id, entry)| match &entry.node.kind {
                NodeKind::KeyedColumn { revision, keys, .. }
                    if inserted_ids.contains(id) && entry.keyed_children.is_none() =>
                {
                    Some((*id, *revision, keys.clone(), entry.node.children.clone()))
                }
                _ => None,
            })
            .collect::<Vec<_>>();
        for (container, revision, keys, roots) in seeded {
            let entries = keys
                .into_iter()
                .zip(roots)
                .map(|(key, root)| {
                    let instance = match self.nodes[&root].node.kind {
                        NodeKind::Boundary { instance } => instance,
                        _ => unreachable!("validated keyed seed child is a boundary"),
                    };
                    (key, root, instance)
                })
                .collect::<Vec<_>>();
            self.nodes
                .get_mut(&container)
                .expect("seeded keyed container was inserted")
                .keyed_children = Some(
                KeyedChildOrder::from_seed(revision, &entries)
                    .expect("validated keyed seed has unique keys"),
            );
        }
        for id in &validated.postorder {
            let children = self.nodes[id].node.children.clone();
            let size = 1 + children
                .iter()
                .map(|id| self.nodes[id].subtree_size)
                .sum::<u64>();
            self.nodes.get_mut(id).expect("inserted node").subtree_size = size;
            for (position, child) in children.into_iter().enumerate() {
                let parent = match self.nodes[id].keyed_children.as_ref() {
                    Some(order) => {
                        let (key, keyed_child) = order.iter().nth(position).expect("keyed child");
                        ParentLocation::Keyed {
                            container: *id,
                            key,
                            instance: keyed_child.instance,
                        }
                    }
                    None => ParentLocation::OrdinaryIndex {
                        parent: *id,
                        index: position,
                    },
                };
                self.nodes.get_mut(&child).expect("validated child").parent = Some(parent);
            }
            self.refresh_child_segments(*id);
        }
    }

    fn refresh_child_segments(&mut self, parent: u64) {
        for (id, segment) in self.child_segments(parent) {
            self.nodes.get_mut(&id).expect("mounted child").segment = segment;
        }
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

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum ComponentKey {
    Unkeyed(u64),
    Digest([u8; 32]),
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct ComponentLocation {
    scope: ElementIdentity,
    key: ComponentKey,
}

#[derive(Clone, Copy)]
struct ComponentMount {
    instance: u64,
    root: u64,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ScopeKind {
    Render,
    Native,
    Component,
}

struct ComponentScope {
    identity: ElementIdentity,
    occurrences: HashMap<(u8, Arc<str>), u32>,
    kind: ScopeKind,
}

/// Identity reconciliation for the production Roc lowering walk. Pending
/// choices never replace committed mount metadata until the graph accepts its
/// transaction. Application digests stay private and are never capture identity.
pub struct ComponentRegistry {
    next_instance: u64,
    live: HashMap<ComponentLocation, ComponentMount>,
    instances: NodeMap<ComponentLocation>,
    pending: HashMap<ComponentLocation, ComponentMount>,
    pending_instances: NodeSet,
    seen: HashSet<ComponentLocation>,
    scopes: Vec<ComponentScope>,
    rendering: bool,
}

impl Default for ComponentRegistry {
    fn default() -> Self {
        Self {
            // Instance zero is the permanent application root.
            next_instance: 1,
            live: HashMap::new(),
            instances: NodeMap::default(),
            pending: HashMap::new(),
            pending_instances: NodeSet::default(),
            seen: HashSet::new(),
            scopes: Vec::new(),
            rendering: false,
        }
    }
}

impl ComponentRegistry {
    pub fn begin_render(&mut self, owner: u64) -> Result<(), String> {
        if self.rendering || !self.pending.is_empty() {
            return Err("component render began before its preceding transaction committed".into());
        }
        if owner != 0 && !self.instances.contains_key(&owner) {
            return Err(format!("component render owner {owner} is not mounted"));
        }
        self.rendering = true;
        self.scopes.push(ComponentScope {
            identity: vec![IdentitySegment::Boundary { instance: owner }],
            occurrences: HashMap::new(),
            kind: ScopeKind::Render,
        });
        Ok(())
    }

    pub fn scope_enter(&mut self, tag: u8, label: &str, position: u64) -> Result<(), String> {
        let position =
            usize::try_from(position).map_err(|_| "native scope position is too large")?;
        if tag >= 15 {
            return Err("native scope has invalid kind".into());
        }
        if self.scopes.len() >= MAX_STAGED_NODES {
            return Err("component scope nesting exceeds native tree limit".into());
        }
        let parent = self
            .scopes
            .last_mut()
            .ok_or("native scope entered outside a render")?;
        let segment = if label.is_empty() {
            IdentitySegment::Positional {
                tag,
                index: position,
            }
        } else {
            let name: Arc<str> = Arc::from(label);
            let occurrence = parent.occurrences.entry((tag, name.clone())).or_default();
            let segment = IdentitySegment::Named {
                tag,
                name,
                occurrence: *occurrence,
            };
            *occurrence = occurrence
                .checked_add(1)
                .ok_or("native scope occurrence overflow")?;
            segment
        };
        let mut identity = parent.identity.clone();
        identity.push(segment);
        self.scopes.push(ComponentScope {
            identity,
            occurrences: HashMap::new(),
            kind: ScopeKind::Native,
        });
        Ok(())
    }

    pub fn scope_exit(&mut self) -> Result<(), String> {
        self.exit_scope(ScopeKind::Native)
    }

    pub fn resolve(&mut self, key_kind: u8, key_digest: &[u8]) -> Result<(u64, u64), String> {
        let key = match key_kind {
            0 if key_digest.is_empty() => ComponentKey::Unkeyed(self.next_instance),
            0 => return Err("unkeyed boundary must have an empty digest".into()),
            1 => ComponentKey::Digest(
                key_digest
                    .try_into()
                    .map_err(|_| "component key digest must contain exactly 32 bytes")?,
            ),
            _ => return Err("invalid component key kind".into()),
        };
        let scope = self
            .scopes
            .last()
            .ok_or("component resolved outside a render")?
            .identity
            .clone();
        let location = ComponentLocation { scope, key };
        if !self.seen.insert(location.clone()) {
            return Err("duplicate component key in one structural parent scope".into());
        }
        let mount = match self.live.get(&location).copied() {
            Some(mount) => mount,
            None => {
                let instance = self.next_instance;
                self.next_instance = instance
                    .checked_add(1)
                    .ok_or("component instance space exhausted")?;
                ComponentMount { instance, root: 0 }
            }
        };
        self.pending_instances.insert(mount.instance);
        self.pending.insert(location, mount);
        Ok((mount.instance, mount.root))
    }

    pub fn component_enter(&mut self, instance: u64) -> Result<(), String> {
        if self.scopes.is_empty() || !self.pending_instances.contains(&instance) {
            return Err(format!(
                "component {instance} was not resolved in this render"
            ));
        }
        if self.scopes.len() >= MAX_STAGED_NODES {
            return Err("component scope nesting exceeds native tree limit".into());
        }
        self.scopes.push(ComponentScope {
            identity: vec![IdentitySegment::Boundary { instance }],
            occurrences: HashMap::new(),
            kind: ScopeKind::Component,
        });
        Ok(())
    }

    pub fn component_exit(&mut self) -> Result<(), String> {
        self.exit_scope(ScopeKind::Component)
    }

    fn exit_scope(&mut self, kind: ScopeKind) -> Result<(), String> {
        if !self.scopes.last().is_some_and(|scope| scope.kind == kind) {
            return Err("mismatched component/native scope exit".into());
        }
        self.scopes.pop();
        Ok(())
    }

    /// Called by the bridge commit before making a patch available to the host.
    pub fn finish_render(&mut self) -> Result<(), String> {
        if !self.rendering {
            return Ok(());
        }
        if self.scopes.len() != 1 || self.scopes[0].kind != ScopeKind::Render {
            return Err("component render committed with unfinished scopes".into());
        }
        self.scopes.clear();
        Ok(())
    }

    /// Accept only the metadata associated with nodes in the accepted graph.
    /// Retirement and root updates follow the graph delta, never a full scan.
    pub fn commit(&mut self, graph: &MountedGraph, applied: &GraphApply) {
        for instance in &applied.removed_instances {
            if graph.boundary_root(*instance).is_none()
                && let Some(location) = self.instances.remove(instance)
            {
                self.live.remove(&location);
            }
        }
        for (location, mut mount) in std::mem::take(&mut self.pending) {
            if let Some(root) = graph.boundary_root(mount.instance) {
                mount.root = root;
                self.instances.insert(mount.instance, location.clone());
                self.live.insert(location, mount);
            }
        }
        for instance in &applied.staged_instances {
            if let Some(location) = self.instances.get(instance)
                && let Some(mount) = self.live.get_mut(location)
            {
                mount.root = graph
                    .boundary_root(*instance)
                    .expect("staged component is mounted");
            }
        }
        self.abort();
    }

    /// Discard unaccepted reconciliation without reusing allocated identities.
    pub fn abort(&mut self) {
        // Hash-table iteration and clearing can depend on capacity. Scratch
        // from a large ancestor render must not tax the next small local one.
        self.pending = HashMap::new();
        self.pending_instances = NodeSet::default();
        self.seen = HashSet::new();
        self.scopes.clear();
        self.rendering = false;
    }
}

pub struct BridgeState {
    pub dispatcher: Option<RocErasedCallable>,
    pub pending: Option<Patch>,
    pub components: Option<ComponentRegistry>,
    next_node_id: u64,
    staged: Vec<Node>,
    retained_roots: Vec<u64>,
    retained_lookup: Option<NodeSet>,
    child_builders: Vec<(u64, Vec<u64>)>,
    next_child_builder_id: u64,
    keyed_edit: Option<KeyedEditBuilder>,
}

struct KeyedEditBuilder {
    container: u64,
    base_revision: u64,
    new_revision: u64,
    operations: Vec<KeyedGraphOperation>,
}

impl BridgeState {
    pub const fn new() -> Self {
        Self {
            dispatcher: None,
            pending: None,
            components: None,
            next_node_id: 1,
            staged: Vec::new(),
            retained_roots: Vec::new(),
            retained_lookup: None,
            child_builders: Vec::new(),
            next_child_builder_id: 1,
            keyed_edit: None,
        }
    }

    pub fn begin_keyed_edit(
        &mut self,
        container: u64,
        base_revision: u64,
        new_revision: u64,
    ) -> Result<(), String> {
        if self.pending.is_some() || self.keyed_edit.is_some() {
            return Err("Roc began overlapping native graph transactions".into());
        }
        if !self.staged.is_empty()
            || !self.retained_roots.is_empty()
            || !self.child_builders.is_empty()
        {
            return Err("keyed edit began with unfinished ordinary staging".into());
        }
        self.keyed_edit = Some(KeyedEditBuilder {
            container,
            base_revision,
            new_revision,
            operations: Vec::new(),
        });
        Ok(())
    }

    fn keyed_fragment(&mut self, root: u64) -> Result<Vec<Node>, String> {
        if self.keyed_edit.is_none() {
            return Err("keyed item outside an edit".into());
        }
        if !self.child_builders.is_empty() {
            return Err("keyed item committed with unfinished child builders".into());
        }
        if self.staged.is_empty() || !self.staged.iter().any(|node| node.id == root) {
            return Err(format!(
                "keyed item root {root} was not staged in this edit"
            ));
        }
        Ok(std::mem::take(&mut self.staged))
    }

    pub fn keyed_insert_before(
        &mut self,
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
        root: u64,
    ) -> Result<(), String> {
        let nodes = self.keyed_fragment(root)?;
        self.keyed_edit
            .as_mut()
            .ok_or_else(|| "keyed InsertBefore outside an edit".to_string())?
            .operations
            .push(KeyedGraphOperation::Insert {
                key,
                before,
                root,
                nodes,
            });
        Ok(())
    }

    pub fn keyed_remove(&mut self, key: KeyedChildKey) -> Result<(), String> {
        self.keyed_order_only(KeyedGraphOperation::Remove { key })
    }

    pub fn keyed_move_before(
        &mut self,
        key: KeyedChildKey,
        before: Option<KeyedChildKey>,
    ) -> Result<(), String> {
        self.keyed_order_only(KeyedGraphOperation::Move { key, before })
    }

    fn keyed_order_only(&mut self, operation: KeyedGraphOperation) -> Result<(), String> {
        if !self.staged.is_empty() || !self.child_builders.is_empty() {
            return Err("keyed order edit followed unfinished item staging".into());
        }
        self.keyed_edit
            .as_mut()
            .ok_or_else(|| "keyed operation outside an edit".to_string())?
            .operations
            .push(operation);
        Ok(())
    }

    pub fn keyed_set(&mut self, key: KeyedChildKey, root: u64) -> Result<(), String> {
        let nodes = self.keyed_fragment(root)?;
        self.keyed_edit
            .as_mut()
            .ok_or_else(|| "keyed Set outside an edit".to_string())?
            .operations
            .push(KeyedGraphOperation::Set { key, root, nodes });
        Ok(())
    }

    pub fn commit_keyed_edit(&mut self) -> Result<(), String> {
        if self.pending.is_some() {
            return Err("Roc emitted two patches in one dispatch".into());
        }
        if !self.staged.is_empty() || !self.child_builders.is_empty() {
            return Err("keyed edit committed with unfinished item staging".into());
        }
        if let Some(components) = &mut self.components {
            components.finish_render()?;
        }
        let edit = self
            .keyed_edit
            .take()
            .ok_or_else(|| "keyed commit outside an edit".to_string())?;
        self.pending = Some(Patch::Keyed {
            container: edit.container,
            base_revision: edit.base_revision,
            new_revision: edit.new_revision,
            operations: edit.operations,
        });
        Ok(())
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
        if self.staged.len() + self.retained_roots.len() >= MAX_STAGED_NODES {
            return Err(format!("native subtree exceeds {MAX_STAGED_NODES} nodes"));
        }

        let staged_start = self.staged.first().map(|node| node.id);
        if let Some(child) = children.iter().find(|child| {
            !staged_start.is_some_and(|start| start <= **child && **child < self.next_node_id)
                && !self
                    .retained_lookup
                    .as_ref()
                    .is_some_and(|roots| roots.contains(child))
        }) {
            return Err(format!("new node references unstaged child {child}"));
        }

        let id = self.next_node_id;
        self.next_node_id = id
            .checked_add(1)
            .filter(|next| *next < HOVER_EXIT_EVENT_BIT)
            .ok_or_else(|| "native node id space exhausted".to_string())?;
        self.staged.push(Node { id, kind, children });
        Ok(id)
    }

    pub fn seed_keyed_column(
        &mut self,
        container: u64,
        revision: u64,
        keys: Vec<KeyedChildKey>,
    ) -> Result<(), String> {
        // One indexing pass keeps a large seeded column linear; probing the
        // staged vector per key made the initial mount quadratic in its size.
        let staged_index: HashMap<u64, usize> = self
            .staged
            .iter()
            .enumerate()
            .map(|(index, node)| (node.id, index))
            .collect();
        let position = *staged_index
            .get(&container)
            .ok_or_else(|| format!("keyed seed container {container} was not staged"))?;
        let node = &self.staged[position];
        if keys.len() != node.children.len() {
            return Err("keyed seed key count differs from child count".into());
        }
        let (label, style) = match &node.kind {
            NodeKind::Column { label, style } => (label.clone(), style.clone()),
            _ => return Err("keyed seed target is not a column".into()),
        };
        let mut seen = HashSet::with_capacity(keys.len());
        for (key, child) in keys.iter().zip(&node.children) {
            if !seen.insert(*key) {
                return Err("keyed seed contains a duplicate key".into());
            }
            let child_node = staged_index
                .get(child)
                .map(|index| &self.staged[*index])
                .ok_or_else(|| format!("keyed seed child {child} was not staged"))?;
            if !matches!(child_node.kind, NodeKind::Boundary { .. }) {
                return Err("keyed seed child is not a component boundary".into());
            }
        }
        self.staged[position].kind = NodeKind::KeyedColumn {
            label,
            style,
            revision,
            keys,
        };
        Ok(())
    }

    /// Declare a mounted component root as an opaque leaf of this transaction.
    /// Liveness, component kind, scope, and ancestry are checked by the graph.
    pub fn retain_subtree(&mut self, root: u64) -> Result<u64, String> {
        if self.pending.is_some() {
            return Err("Roc retained a subtree before the previous patch was consumed".into());
        }
        if self.keyed_edit.is_some() {
            return Err("keyed item fragments cannot retain mounted subtrees".into());
        }
        if root == 0
            || root
                >= self
                    .staged
                    .first()
                    .map_or(self.next_node_id, |node| node.id)
        {
            return Err(format!("retained root {root} was not previously issued"));
        }
        if self.retained_roots.len() + self.staged.len() >= MAX_STAGED_NODES {
            return Err(format!("native subtree exceeds {MAX_STAGED_NODES} nodes"));
        }
        if !self
            .retained_lookup
            .get_or_insert_with(NodeSet::default)
            .insert(root)
        {
            return Err(format!("duplicate retained root {root}"));
        }
        self.retained_roots.push(root);
        Ok(root)
    }

    pub fn commit(&mut self, commit: Commit) -> Result<(), String> {
        if self.pending.is_some() {
            return Err("Roc emitted two patches in one dispatch".into());
        }
        if !self.child_builders.is_empty() {
            return Err("Roc committed a patch with unfinished child builders".into());
        }
        if self.keyed_edit.is_some() {
            return Err("ordinary patch committed during a keyed edit".into());
        }
        if let Some(components) = &mut self.components {
            components.finish_render()?;
        }

        let patch = match commit {
            Commit::NoChange => {
                if !self.staged.is_empty() {
                    return Err("NoChange followed staged node creation".into());
                }
                if !self.retained_roots.is_empty() {
                    return Err("NoChange followed subtree retention".into());
                }
                Patch::NoChange
            }
            Commit::Mount { root } => {
                if !self.retained_roots.is_empty() {
                    return Err("Mount followed subtree retention".into());
                }
                Patch::Mount {
                    root,
                    nodes: std::mem::take(&mut self.staged),
                }
            }
            Commit::Replace { old_root, root } => {
                let nodes = std::mem::take(&mut self.staged);
                if self.retained_roots.is_empty() {
                    Patch::Replace {
                        old_root,
                        root,
                        nodes,
                    }
                } else {
                    self.retained_lookup = None;
                    Patch::ReplaceRetaining {
                        old_root,
                        root,
                        nodes,
                        retained_roots: std::mem::take(&mut self.retained_roots),
                    }
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
    validate_fragment(root, nodes, &NodeSet::default(), None, |_| None).map(|_| ())
}

struct ValidatedFragment {
    indices: NodeMap<usize>,
    input_owners: NodeMap<Option<u64>>,
    /// Fresh nodes only, with children before their parents.
    postorder: Vec<u64>,
    visits: u64,
}

impl ValidatedFragment {
    fn lookup<'a>(
        &self,
        id: u64,
        nodes: &'a [Node],
        mounted: impl FnOnce(u64) -> Option<&'a Node>,
    ) -> Option<&'a Node> {
        self.indices
            .get(&id)
            .map(|index| &nodes[*index])
            .or_else(|| mounted(id))
    }
}

/// Validate the replacement with retained roots treated as opaque leaves.
/// Mounted descendants have already been validated and are never walked here.
fn validate_fragment<'a>(
    root: u64,
    nodes: &'a [Node],
    retained: &NodeSet,
    owner: Option<u64>,
    mounted: impl Fn(u64) -> Option<&'a Node>,
) -> Result<ValidatedFragment, String> {
    if root == 0 {
        return Err("node id 0 is reserved".into());
    }
    if nodes.len().saturating_add(retained.len()) > MAX_STAGED_NODES {
        return Err(format!("native subtree exceeds {MAX_STAGED_NODES} nodes"));
    }
    let mut indices = NodeMap::default();
    let mut ownership = NodeSet::default();
    for (index, node) in nodes.iter().enumerate() {
        if node.id == 0 {
            return Err("node id 0 is reserved".into());
        }
        if retained.contains(&node.id) || indices.insert(node.id, index).is_some() {
            return Err(format!("duplicate node id {}", node.id));
        }
    }
    if !indices.contains_key(&root) && !retained.contains(&root) {
        return Err(format!("subtree root {root} is missing"));
    }
    let mut result = ValidatedFragment {
        indices,
        input_owners: NodeMap::default(),
        postorder: Vec::with_capacity(nodes.len()),
        visits: 0,
    };
    let mut dialogs = 0;
    let mut input_labels = HashSet::new();
    let mut instances = NodeSet::default();
    for node in nodes {
        result.visits += 1;
        match &node.kind {
            NodeKind::Dialog { .. } => {
                dialogs += 1;
                if dialogs > 1 {
                    return Err("native subtree contains more than one modal dialog".into());
                }
            }
            NodeKind::TextInput { label, .. } if label.is_empty() => {
                return Err("text input label must not be empty".into());
            }
            NodeKind::Boundary { instance } if !instances.insert(*instance) => {
                return Err(format!("duplicate component instance {instance}"));
            }
            _ => {}
        }
        match node.kind {
            NodeKind::Text(_)
            | NodeKind::StyledText { .. }
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
            NodeKind::Boundary { .. } if node.children.len() != 1 => {
                return Err(format!(
                    "boundary node {} must have one content child",
                    node.id
                ));
            }
            NodeKind::Popover { .. } if node.children.is_empty() => {
                return Err(format!(
                    "popover node {} must have an anchor child",
                    node.id
                ));
            }
            NodeKind::Popover { delay_ms, .. } if delay_ms > 60_000 => {
                return Err(format!(
                    "popover node {} delay exceeds 60000 milliseconds",
                    node.id
                ));
            }
            NodeKind::Scroll { .. } if node.children.len() != 1 => {
                return Err(format!(
                    "scroll node {} must have one content child",
                    node.id
                ));
            }
            NodeKind::Split { .. } if node.children.len() != 2 => {
                return Err(format!("split node {} must have two panes", node.id));
            }
            NodeKind::Split { size, min, max, .. } if !(min <= size && size <= max) => {
                return Err(format!(
                    "split node {} holds a size outside its bounds",
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
            NodeKind::VirtualList {
                rows: Some(rows), ..
            } if rows.instance == 0
                || rows
                    .first
                    .checked_add(node.children.len() as u64)
                    .is_none_or(|end| end > rows.count) =>
            {
                return Err(format!(
                    "virtual list node {} mounts rows outside its provided extent",
                    node.id
                ));
            }
            NodeKind::VirtualList { .. } => {
                validate_virtual_keys(node, |id| result.lookup(id, nodes, &mounted))?
            }
            _ => {}
        }
        for child in &node.children {
            if !result.indices.contains_key(child) && !retained.contains(child) {
                return Err(format!("node {} references missing child {child}", node.id));
            }
            if !ownership.insert(*child) {
                return Err(format!("node {child} has more than one parent"));
            }
        }
    }
    if ownership.contains(&root) {
        return Err(format!("subtree root {root} has a parent"));
    }
    // Parent counts alone cannot distinguish a valid tree from an isolated
    // root plus a disconnected cycle. Prove reachability from the actual root.
    let mut reached = NodeSet::default();
    let mut pending = vec![(root, false, owner)];
    while let Some((id, exiting, owner)) = pending.pop() {
        if exiting {
            result.postorder.push(id);
            continue;
        }
        result.visits += 1;
        if !reached.insert(id) {
            return Err(format!("cycle in native subtree at node {id}"));
        }
        if retained.contains(&id) {
            continue;
        }
        let node = &nodes[result.indices[&id]];
        let owner = match &node.kind {
            NodeKind::Boundary { instance } => Some(*instance),
            NodeKind::TextInput { label, .. } => {
                if !input_labels.insert((owner, label)) {
                    return Err(format!(
                        "native subtree contains duplicate text input label {label:?}"
                    ));
                }
                result.input_owners.insert(id, owner);
                owner
            }
            _ => owner,
        };
        pending.push((id, true, owner));
        pending.extend(
            node.children
                .iter()
                .rev()
                .map(|child| (*child, false, owner)),
        );
    }
    if reached.len() != nodes.len() + retained.len() {
        return Err("native subtree is disconnected".into());
    }
    Ok(result)
}
#[cfg(test)]
mod tests {

    #[test]
    fn focus_moves_to_whatever_took_the_place_of_a_removed_control() {
        let mut graph = MountedGraph::default();
        let button = |id: u64, name: &str| Node {
            id,
            kind: NodeKind::Button {
                role: crate::bridge::ButtonRole::Button,
                caption: name.into(),
                label: name.into(),
                enabled: true,
                hover_enter: false,
                hover_exit: false,
                style: Box::default(),
            },
            children: vec![],
        };
        let row = |id: u64, children: Vec<u64>| Node {
            id,
            kind: NodeKind::Row {
                label: String::new(),
                style: Box::default(),
            },
            children,
        };
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![
                    row(1, vec![2, 3, 4]),
                    button(2, "a"),
                    button(3, "b"),
                    button(4, "c"),
                ],
            })
            .expect("mount");
        assert_eq!(graph.focus_order(), vec![2, 3, 4]);

        // "b" had focus, at position 1, and is gone from the next graph.
        graph
            .apply(Patch::Replace {
                old_root: 1,
                root: 5,
                nodes: vec![row(5, vec![6, 7]), button(6, "a"), button(7, "c")],
            })
            .expect("replace");
        assert_eq!(
            graph.focus_destination(1),
            Some(7),
            "focus should land on the control that took the removed one's place"
        );
        // The last control removed: focus lands on the new last one.
        assert_eq!(graph.focus_destination(9), Some(7));
    }

    #[test]
    fn a_cycle_target_names_a_place_and_no_text() {
        let button = |id: u64, name: &str| Node {
            id,
            kind: NodeKind::Button {
                role: ButtonRole::Button,
                caption: name.into(),
                label: name.into(),
                enabled: true,
                hover_enter: false,
                hover_exit: false,
                style: Box::default(),
            },
            children: vec![],
        };
        let row = |id: u64, children: Vec<u64>| Node {
            id,
            kind: NodeKind::Row {
                label: String::new(),
                style: Box::default(),
            },
            children,
        };
        let mounted = |nodes: Vec<Node>| {
            let mut graph = MountedGraph::default();
            graph
                .apply(Patch::Mount {
                    root: nodes[0].id,
                    nodes,
                })
                .expect("mount");
            graph
        };
        let first = mounted(vec![
            row(1, vec![2, 3]),
            button(2, "Save"),
            button(3, "Open"),
        ]);
        let save = first.cycle_target(2).expect("target");
        assert_eq!(save.kind, "button");
        assert_eq!(save.identity.len(), 16);
        assert!(!save.identity.contains("Save"));
        // A different run numbers its nodes differently and names its buttons
        // differently; the same place has the same identity.
        let renamed = mounted(vec![
            row(7, vec![8, 9]),
            button(8, "Speichern"),
            button(9, "x"),
        ]);
        assert_eq!(renamed.cycle_target(8), Some(save.clone()));
        // Route bits select a handler, not a different node.
        assert_eq!(
            first.cycle_target(2 | HOVER_ENTER_EVENT_BIT),
            Some(save.clone())
        );
        // Another place is another identity.
        assert_ne!(first.cycle_target(3).unwrap().identity, save.identity);
        assert_eq!(first.cycle_target(99), None);
    }

    #[test]
    fn a_graph_with_nothing_focusable_offers_nowhere_for_focus_to_go() {
        let graph = MountedGraph::default();
        assert_eq!(graph.focus_destination(0), None);
    }
    use super::*;

    fn keyed_test_key(value: u8) -> KeyedChildKey {
        let mut key = [0; 32];
        key[0] = value;
        key
    }

    #[test]
    fn keyed_child_order_edits_links_and_preserves_identity() {
        let a = keyed_test_key(1);
        let b = keyed_test_key(2);
        let c = keyed_test_key(3);
        let mut order = KeyedChildOrder::default();

        assert_eq!(
            order.insert_before(0, a, 10, 100, None),
            Ok(KeyedOrderEdit {
                revision: 1,
                touches: 1
            })
        );
        assert_eq!(
            order.insert_before(1, b, 20, 200, None),
            Ok(KeyedOrderEdit {
                revision: 2,
                touches: 2
            })
        );
        assert_eq!(
            order.insert_before(2, c, 30, 300, Some(b)),
            Ok(KeyedOrderEdit {
                revision: 3,
                touches: 3
            })
        );
        assert_eq!(order.keys(), vec![a, c, b]);
        assert_eq!(order.get(c), Some((30, 300)));

        assert_eq!(
            order.move_before(3, b, Some(a)),
            Ok(KeyedOrderEdit {
                revision: 4,
                touches: 3
            })
        );
        assert_eq!(order.keys(), vec![b, a, c]);
        assert_eq!(
            order.get(b),
            Some((20, 200)),
            "a move preserves root and instance identity"
        );

        assert_eq!(
            order.replace(4, c, 31),
            Ok(KeyedOrderEdit {
                revision: 5,
                touches: 1
            })
        );
        assert_eq!(
            order.get(c),
            Some((31, 300)),
            "replacement preserves the keyed instance"
        );
        let (removed, edit) = order.remove(5, a).expect("remove existing key");
        assert_eq!((removed.root, removed.instance), (10, 100));
        assert_eq!(
            edit,
            KeyedOrderEdit {
                revision: 6,
                touches: 3
            }
        );
        assert_eq!(order.keys(), vec![b, c]);

        assert_eq!(
            order.move_before(6, b, Some(c)),
            Ok(KeyedOrderEdit {
                revision: 7,
                touches: 0
            })
        );
        assert_eq!(order.keys(), vec![b, c]);
    }

    #[test]
    fn keyed_child_order_rejections_are_atomic() {
        let a = keyed_test_key(1);
        let missing = keyed_test_key(9);
        let mut order = KeyedChildOrder::default();
        order.insert_before(0, a, 10, 100, None).unwrap();
        let snapshot = order.keys();

        assert_eq!(
            order.insert_before(1, a, 11, 101, None),
            Err(KeyedOrderError::Duplicate(a))
        );
        assert_eq!(
            order.insert_before(1, keyed_test_key(2), 20, 200, Some(missing)),
            Err(KeyedOrderError::Missing(missing))
        );
        assert_eq!(
            order.remove(1, missing),
            Err(KeyedOrderError::Missing(missing))
        );
        assert_eq!(
            order.move_before(1, a, Some(missing)),
            Err(KeyedOrderError::Missing(missing))
        );
        assert_eq!(
            order.replace(1, missing, 99),
            Err(KeyedOrderError::Missing(missing))
        );
        assert_eq!(
            order.remove(0, a),
            Err(KeyedOrderError::StaleRevision {
                actual: 1,
                expected: 0
            })
        );
        assert_eq!(order.revision, 1);
        assert_eq!(order.keys(), snapshot);
        assert_eq!(order.get(a), Some((10, 100)));
    }

    #[test]
    fn keyed_child_order_touch_count_is_independent_of_sibling_count() {
        let mut order = KeyedChildOrder::default();
        for value in 0..10_000_u64 {
            let mut key = [0; 32];
            key[..8].copy_from_slice(&value.to_le_bytes());
            let edit = order
                .insert_before(value, key, value + 1, value + 10_001, None)
                .unwrap();
            assert!(edit.touches <= 2);
        }
        let mut first = [0; 32];
        first[..8].copy_from_slice(&0_u64.to_le_bytes());
        let moved = order.move_before(10_000, first, None).unwrap();
        assert!(moved.touches <= 5);
        assert_eq!(order.keys().last(), Some(&first));
    }

    fn keyed_snapshot(order: &KeyedChildOrder) -> (u64, Vec<(KeyedChildKey, KeyedChild)>) {
        (
            order.revision,
            order.iter().map(|(key, child)| (key, *child)).collect(),
        )
    }

    #[test]
    fn keyed_child_iterator_is_exact_and_double_ended() {
        let mut order = KeyedChildOrder::default();
        let keys: Vec<_> = (1..=4).map(keyed_test_key).collect();
        for (index, key) in keys.iter().copied().enumerate() {
            order
                .insert_before(index as u64, key, index as u64, index as u64, None)
                .unwrap();
        }
        let mut iter = order.iter();
        assert_eq!(iter.len(), 4);
        assert_eq!(iter.next().map(|(key, _)| key), Some(keys[0]));
        assert_eq!(iter.next_back().map(|(key, _)| key), Some(keys[3]));
        assert_eq!(iter.len(), 2);
        assert_eq!(iter.next_back().map(|(key, _)| key), Some(keys[2]));
        assert_eq!(iter.next().map(|(key, _)| key), Some(keys[1]));
        assert_eq!(iter.next(), None);
        assert_eq!(iter.next_back(), None);
    }

    #[test]
    fn keyed_atomic_mixed_edits_commit_one_supplied_revision() {
        let (a, b, c, d) = (
            keyed_test_key(1),
            keyed_test_key(2),
            keyed_test_key(3),
            keyed_test_key(4),
        );
        let mut order = KeyedChildOrder::default();
        order.insert_before(0, a, 10, 100, None).unwrap();
        order.insert_before(1, b, 20, 200, None).unwrap();
        order.insert_before(2, c, 30, 300, None).unwrap();
        let edit = order
            .apply_atomic(
                3,
                40,
                &[
                    KeyedOrderOperation::Insert {
                        key: d,
                        root: 40,
                        instance: 400,
                        before: Some(b),
                    },
                    KeyedOrderOperation::Move {
                        key: c,
                        before: Some(a),
                    },
                    KeyedOrderOperation::Replace { key: d, root: 41 },
                    KeyedOrderOperation::Remove { key: b },
                ],
            )
            .unwrap();
        assert_eq!(order.keys(), vec![c, a, d]);
        assert_eq!(order.get(d), Some((41, 400)));
        assert_eq!(order.revision, 40);
        assert_eq!(edit.revision, 40);
        assert_eq!(edit.original_reads, edit.first_touches);
        assert_eq!(edit.first_touches, 4, "each affected key is saved once");
    }

    #[test]
    fn keyed_atomic_every_operation_failure_restores_exact_state() {
        let (a, b, fresh, missing) = (
            keyed_test_key(1),
            keyed_test_key(2),
            keyed_test_key(3),
            keyed_test_key(9),
        );
        let failures = [
            KeyedOrderOperation::Insert {
                key: a,
                root: 99,
                instance: 99,
                before: None,
            },
            KeyedOrderOperation::Insert {
                key: keyed_test_key(4),
                root: 99,
                instance: 99,
                before: Some(missing),
            },
            KeyedOrderOperation::Remove { key: missing },
            KeyedOrderOperation::Move {
                key: missing,
                before: None,
            },
            KeyedOrderOperation::Move {
                key: a,
                before: Some(missing),
            },
            KeyedOrderOperation::Replace {
                key: missing,
                root: 99,
            },
        ];
        for failure in failures {
            let mut order = KeyedChildOrder::default();
            order.insert_before(0, a, 10, 100, None).unwrap();
            order.insert_before(1, b, 20, 200, None).unwrap();
            let before = keyed_snapshot(&order);
            let result = order.apply_atomic(
                2,
                3,
                &[
                    KeyedOrderOperation::Insert {
                        key: fresh,
                        root: 30,
                        instance: 300,
                        before: Some(b),
                    },
                    KeyedOrderOperation::Replace { key: a, root: 11 },
                    failure,
                ],
            );
            assert!(result.is_err());
            assert_eq!(keyed_snapshot(&order), before);
            assert!(!order.children.contains_key(&fresh));
        }
    }

    #[test]
    fn keyed_atomic_rejects_stale_base_and_new_revisions_without_touching_state() {
        let a = keyed_test_key(1);
        let mut order = KeyedChildOrder::default();
        order.insert_before(0, a, 10, 100, None).unwrap();
        let before = keyed_snapshot(&order);
        let operation = [KeyedOrderOperation::Replace { key: a, root: 11 }];
        assert_eq!(
            order.apply_atomic(0, 2, &operation),
            Err(KeyedOrderError::StaleRevision {
                actual: 1,
                expected: 0
            })
        );
        assert_eq!(
            order.apply_atomic(1, 1, &operation),
            Err(KeyedOrderError::StaleNewRevision {
                current: 1,
                proposed: 1
            })
        );
        assert_eq!(keyed_snapshot(&order), before);
    }

    #[test]
    fn keyed_atomic_journal_work_is_independent_of_ten_thousand_siblings() {
        let mut order = KeyedChildOrder::default();
        for value in 0..10_000_u64 {
            let mut key = [0; 32];
            key[..8].copy_from_slice(&value.to_le_bytes());
            order
                .insert_before(value, key, value, value + 10_000, None)
                .unwrap();
        }
        let mut first = [0; 32];
        first[..8].copy_from_slice(&0_u64.to_le_bytes());
        let edit = order
            .apply_atomic(
                10_000,
                20_000,
                &[KeyedOrderOperation::Move {
                    key: first,
                    before: None,
                }],
            )
            .unwrap();
        assert!(edit.original_reads <= 3);
        assert_eq!(edit.original_reads, edit.first_touches);
        assert_eq!(order.iter().next_back().map(|(key, _)| key), Some(first));
    }

    fn keyed_graph() -> MountedGraph {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![Node {
                    id: 1,
                    kind: NodeKind::Column {
                        label: "keyed".into(),
                        style: Box::default(),
                    },
                    children: vec![],
                }],
            })
            .unwrap();
        graph
    }

    fn keyed_button_fragment(root: u64, instance: u64, label: &str) -> Vec<Node> {
        vec![
            Node {
                id: root,
                kind: NodeKind::Boundary { instance },
                children: vec![root + 1],
            },
            Node {
                id: root + 1,
                kind: NodeKind::Button {
                    role: crate::bridge::ButtonRole::Button,
                    caption: label.into(),
                    label: label.into(),
                    enabled: true,
                    hover_enter: true,
                    hover_exit: true,
                    style: Box::default(),
                },
                children: vec![],
            },
        ]
    }

    #[test]
    fn keyed_graph_move_changes_semantic_order_without_changing_identity() {
        let (a, b, c) = (keyed_test_key(1), keyed_test_key(2), keyed_test_key(3));
        let mut graph = keyed_graph();
        graph
            .apply_keyed(
                1,
                0,
                1,
                vec![
                    KeyedGraphOperation::Insert {
                        key: a,
                        before: None,
                        root: 2,
                        nodes: keyed_button_fragment(2, 10, "a"),
                    },
                    KeyedGraphOperation::Insert {
                        key: b,
                        before: None,
                        root: 4,
                        nodes: keyed_button_fragment(4, 11, "b"),
                    },
                    KeyedGraphOperation::Insert {
                        key: c,
                        before: None,
                        root: 6,
                        nodes: keyed_button_fragment(6, 12, "c"),
                    },
                ],
            )
            .unwrap();
        let identity = graph.identity(5);
        assert_eq!(graph.children_of(1).collect::<Vec<_>>(), vec![2, 4, 6]);
        assert_eq!(graph.focus_order(), vec![3, 5, 7]);
        assert_eq!(graph.subtree_size(1), Some(7));
        assert_eq!(
            graph.parent_location(4),
            Some(ParentLocation::Keyed {
                container: 1,
                key: b,
                instance: 11
            })
        );

        let edit = graph
            .apply_keyed(
                1,
                1,
                2,
                vec![KeyedGraphOperation::Move {
                    key: c,
                    before: Some(a),
                }],
            )
            .unwrap();
        assert_eq!(edit.graph_visits, 0);
        assert_eq!(graph.children_of(1).collect::<Vec<_>>(), vec![6, 2, 4]);
        assert_eq!(graph.focus_order(), vec![7, 3, 5]);
        assert_eq!(graph.identity(5), identity);
    }

    #[test]
    fn keyed_graph_remove_retires_metadata_and_missing_key_is_atomic() {
        let key = keyed_test_key(1);
        let missing = keyed_test_key(9);
        let mut graph = keyed_graph();
        graph
            .apply_keyed(
                1,
                0,
                1,
                vec![KeyedGraphOperation::Insert {
                    key,
                    before: None,
                    root: 2,
                    nodes: keyed_button_fragment(2, 10, "hover"),
                }],
            )
            .unwrap();
        assert_eq!(
            graph.hover_transition(3, true),
            Some(3 | HOVER_ENTER_EVENT_BIT)
        );
        let before = graph
            .nodes_preorder()
            .iter()
            .map(|node| node.id)
            .collect::<Vec<_>>();
        assert!(
            graph
                .apply_keyed(
                    1,
                    1,
                    2,
                    vec![
                        KeyedGraphOperation::Move { key, before: None },
                        KeyedGraphOperation::Remove { key: missing },
                    ],
                )
                .is_err()
        );
        assert_eq!(
            graph
                .nodes_preorder()
                .iter()
                .map(|node| node.id)
                .collect::<Vec<_>>(),
            before
        );
        assert_eq!(graph.boundary_root(10), Some(2));

        graph
            .apply_keyed(1, 1, 3, vec![KeyedGraphOperation::Remove { key }])
            .unwrap();
        assert_eq!(graph.boundary_root(10), None);
        assert_eq!(graph.node(2), None);
        assert!(!graph.hovered.contains(&3));
        assert_eq!(graph.subtree_size(1), Some(1));
    }

    #[test]
    fn keyed_graph_remove_retires_input_and_dialog_indices() {
        let key = keyed_test_key(1);
        let mut graph = keyed_graph();
        graph
            .apply_keyed(
                1,
                0,
                1,
                vec![KeyedGraphOperation::Insert {
                    key,
                    before: None,
                    root: 2,
                    nodes: vec![
                        Node {
                            id: 2,
                            kind: NodeKind::Boundary { instance: 10 },
                            children: vec![3],
                        },
                        Node {
                            id: 3,
                            kind: NodeKind::Column {
                                label: "item".into(),
                                style: Box::default(),
                            },
                            children: vec![4, 5],
                        },
                        Node {
                            id: 4,
                            kind: NodeKind::TextInput {
                                label: "name".into(),
                                value: String::new(),
                                placeholder: String::new(),
                                enabled: true,
                                style: Box::default(),
                            },
                            children: vec![],
                        },
                        Node {
                            id: 5,
                            kind: NodeKind::Dialog {
                                label: "modal".into(),
                                style: Box::default(),
                            },
                            children: vec![],
                        },
                    ],
                }],
            )
            .unwrap();
        assert_eq!(graph.active_dialog(), Some(5));
        assert_eq!(graph.input_labels.get(&(Some(10), "name".into())), Some(&4));
        graph
            .apply_keyed(1, 1, 2, vec![KeyedGraphOperation::Remove { key }])
            .unwrap();
        assert_eq!(graph.active_dialog(), None);
        assert!(!graph.input_owners.contains_key(&4));
        assert!(!graph.input_labels.contains_key(&(Some(10), "name".into())));
    }

    #[test]
    fn keyed_graph_set_replaces_subtree_and_preserves_keyed_instance() {
        let key = keyed_test_key(1);
        let mut graph = keyed_graph();
        graph
            .apply_keyed(
                1,
                0,
                1,
                vec![KeyedGraphOperation::Insert {
                    key,
                    before: None,
                    root: 2,
                    nodes: keyed_button_fragment(2, 10, "old"),
                }],
            )
            .unwrap();
        let edit = graph
            .apply_keyed(
                1,
                1,
                7,
                vec![KeyedGraphOperation::Set {
                    key,
                    root: 4,
                    nodes: keyed_button_fragment(4, 10, "new"),
                }],
            )
            .unwrap();
        assert_eq!((edit.staged, edit.removed), (2, 2));
        assert_eq!(graph.children_of(1).collect::<Vec<_>>(), vec![4]);
        assert_eq!(graph.boundary_root(10), Some(4));
        assert_eq!(graph.focus_order(), vec![5]);
        assert_eq!(
            graph.parent_location(4),
            Some(ParentLocation::Keyed {
                container: 1,
                key,
                instance: 10
            })
        );
    }

    #[test]
    fn keyed_graph_edits_update_every_ancestor_subtree_size() {
        let key = keyed_test_key(1);
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![
                    Node {
                        id: 1,
                        kind: NodeKind::Row {
                            label: "outer".into(),
                            style: Box::default(),
                        },
                        children: vec![2],
                    },
                    Node {
                        id: 2,
                        kind: NodeKind::Column {
                            label: "keyed".into(),
                            style: Box::default(),
                        },
                        children: vec![],
                    },
                ],
            })
            .unwrap();
        graph
            .apply_keyed(
                2,
                0,
                1,
                vec![KeyedGraphOperation::Insert {
                    key,
                    before: None,
                    root: 3,
                    nodes: keyed_button_fragment(3, 10, "item"),
                }],
            )
            .unwrap();
        assert_eq!(graph.subtree_size(2), Some(3));
        assert_eq!(graph.subtree_size(1), Some(4));
        graph
            .apply_keyed(2, 1, 2, vec![KeyedGraphOperation::Remove { key }])
            .unwrap();
        assert_eq!(graph.subtree_size(2), Some(1));
        assert_eq!(graph.subtree_size(1), Some(2));
    }

    #[test]
    fn keyed_graph_stale_duplicate_and_fragment_failures_leave_graph_unchanged() {
        let key = keyed_test_key(1);
        let mut graph = keyed_graph();
        let before = graph
            .nodes_preorder()
            .iter()
            .map(|node| node.id)
            .collect::<Vec<_>>();
        assert!(
            graph
                .apply_keyed(
                    1,
                    9,
                    10,
                    vec![KeyedGraphOperation::Insert {
                        key,
                        before: None,
                        root: 2,
                        nodes: keyed_button_fragment(2, 10, "a"),
                    }],
                )
                .is_err()
        );
        assert!(
            graph
                .apply_keyed(
                    1,
                    0,
                    1,
                    vec![
                        KeyedGraphOperation::Insert {
                            key,
                            before: None,
                            root: 2,
                            nodes: keyed_button_fragment(2, 10, "a"),
                        },
                        KeyedGraphOperation::Insert {
                            key,
                            before: None,
                            root: 4,
                            nodes: keyed_button_fragment(4, 11, "b"),
                        },
                    ],
                )
                .is_err()
        );
        assert!(
            graph
                .apply_keyed(
                    1,
                    0,
                    1,
                    vec![KeyedGraphOperation::Insert {
                        key,
                        before: None,
                        root: 2,
                        nodes: vec![Node {
                            id: 2,
                            kind: NodeKind::Boundary { instance: 10 },
                            children: vec![],
                        }],
                    }],
                )
                .is_err()
        );
        assert_eq!(
            graph
                .nodes_preorder()
                .iter()
                .map(|node| node.id)
                .collect::<Vec<_>>(),
            before
        );
        assert_eq!(graph.subtree_size(1), Some(1));
    }

    #[test]
    fn keyed_graph_move_work_is_bounded_at_ten_thousand_items() {
        let mut graph = keyed_graph();
        let mut operations = Vec::with_capacity(10_000);
        for value in 0..10_000_u64 {
            let mut key = [0; 32];
            key[..8].copy_from_slice(&value.to_le_bytes());
            let root = value * 2 + 2;
            operations.push(KeyedGraphOperation::Insert {
                key,
                before: None,
                root,
                nodes: keyed_button_fragment(root, value + 10, "row"),
            });
        }
        graph.apply_keyed(1, 0, 1, operations).unwrap();
        let mut first = [0; 32];
        first[..8].copy_from_slice(&0_u64.to_le_bytes());
        let edit = graph
            .apply_keyed(
                1,
                1,
                2,
                vec![KeyedGraphOperation::Move {
                    key: first,
                    before: None,
                }],
            )
            .unwrap();
        assert_eq!(edit.graph_visits, 0);
        assert!(edit.first_touches <= 3);
        assert_eq!(edit.original_reads, edit.first_touches);
        assert_eq!(graph.children_of(1).next_back(), Some(2));
    }

    #[test]
    fn bridge_keyed_builder_emits_one_production_patch_with_owned_counters() {
        let (a, b) = (keyed_test_key(1), keyed_test_key(2));
        let mut bridge = BridgeState::new();
        let container = bridge
            .stage_node(
                NodeKind::Column {
                    label: "keyed".into(),
                    style: Box::default(),
                },
                vec![],
            )
            .unwrap();
        bridge.commit(Commit::Mount { root: container }).unwrap();
        let mut graph = MountedGraph::default();
        graph.apply(bridge.pending.take().unwrap()).unwrap();

        bridge.begin_keyed_edit(container, 0, 5).unwrap();
        let child_a = bridge.stage_node(button("a", true), vec![]).unwrap();
        let root_a = bridge
            .stage_node(NodeKind::Boundary { instance: 10 }, vec![child_a])
            .unwrap();
        bridge.keyed_insert_before(a, None, root_a).unwrap();
        let child_b = bridge.stage_node(button("b", true), vec![]).unwrap();
        let root_b = bridge
            .stage_node(NodeKind::Boundary { instance: 11 }, vec![child_b])
            .unwrap();
        bridge.keyed_insert_before(b, Some(a), root_b).unwrap();
        bridge.commit_keyed_edit().unwrap();
        assert!(matches!(bridge.pending, Some(Patch::Keyed { .. })));
        let inserted = graph.apply(bridge.pending.take().unwrap()).unwrap();
        assert_eq!(inserted.facts.kind, "keyed");
        assert_eq!(inserted.facts.keyed_graph_visits, 8);
        assert_eq!(
            inserted.facts.keyed_original_reads,
            inserted.facts.keyed_first_touches
        );
        assert_eq!(
            graph.children_of(container).collect::<Vec<_>>(),
            vec![root_b, root_a]
        );

        bridge.begin_keyed_edit(container, 5, 6).unwrap();
        bridge.keyed_move_before(a, Some(b)).unwrap();
        bridge.commit_keyed_edit().unwrap();
        let moved = graph.apply(bridge.pending.take().unwrap()).unwrap();
        assert_eq!(moved.facts.keyed_graph_visits, 0);
        assert!(moved.facts.keyed_first_touches <= 3);
        assert_eq!(
            graph.children_of(container).collect::<Vec<_>>(),
            vec![root_a, root_b]
        );
    }

    #[test]
    fn bridge_keyed_builder_keeps_fragment_and_ordinary_transactions_separate() {
        let mut bridge = BridgeState::new();
        bridge.begin_keyed_edit(1, 0, 1).unwrap();
        assert!(bridge.commit(Commit::NoChange).is_err());
        let unstaged = keyed_test_key(1);
        assert!(bridge.keyed_insert_before(unstaged, None, 99).is_err());
        let child = bridge.stage_node(button("item", true), vec![]).unwrap();
        assert!(bridge.keyed_remove(unstaged).is_err());
        let root = bridge
            .stage_node(NodeKind::Boundary { instance: 10 }, vec![child])
            .unwrap();
        bridge.keyed_set(unstaged, root).unwrap();
        bridge.commit_keyed_edit().unwrap();
        assert!(matches!(bridge.pending, Some(Patch::Keyed { .. })));
    }

    #[test]
    fn seeded_keyed_column_mounts_with_revision_and_accepts_later_edits() {
        let key = keyed_test_key(7);
        let mut bridge = BridgeState::new();
        let leaf = bridge.stage_node(button("seeded", true), vec![]).unwrap();
        let boundary = bridge
            .stage_node(NodeKind::Boundary { instance: 70 }, vec![leaf])
            .unwrap();
        let container = bridge
            .stage_node(
                NodeKind::Column {
                    label: "seeded".into(),
                    style: Box::default(),
                },
                vec![boundary],
            )
            .unwrap();
        bridge.seed_keyed_column(container, 4, vec![key]).unwrap();
        bridge.commit(Commit::Mount { root: container }).unwrap();

        let mut graph = MountedGraph::default();
        graph.apply(bridge.pending.take().unwrap()).unwrap();
        assert_eq!(
            graph.children_of(container).collect::<Vec<_>>(),
            vec![boundary]
        );
        assert!(
            matches!(graph.parent_location(boundary), Some(ParentLocation::Keyed { container: seeded, key: found, instance: 70 }) if seeded == container && found == key)
        );

        bridge.begin_keyed_edit(container, 4, 5).unwrap();
        bridge.keyed_remove(key).unwrap();
        bridge.commit_keyed_edit().unwrap();
        graph.apply(bridge.pending.take().unwrap()).unwrap();
        assert!(graph.children_of(container).next().is_none());
    }

    #[test]
    fn keyed_seed_rejects_bad_counts_duplicates_and_non_boundaries() {
        let key = keyed_test_key(1);
        let mut bridge = BridgeState::new();
        let leaf = bridge.stage_node(button("plain", true), vec![]).unwrap();
        let column = bridge
            .stage_node(
                NodeKind::Column {
                    label: String::new(),
                    style: Box::default(),
                },
                vec![leaf],
            )
            .unwrap();
        assert!(bridge.seed_keyed_column(column, 1, vec![]).is_err());
        assert!(bridge.seed_keyed_column(column, 1, vec![key]).is_err());

        let first = bridge
            .stage_node(NodeKind::Boundary { instance: 1 }, vec![leaf])
            .unwrap();
        let second_leaf = bridge.stage_node(button("second", true), vec![]).unwrap();
        let second = bridge
            .stage_node(NodeKind::Boundary { instance: 2 }, vec![second_leaf])
            .unwrap();
        let duplicate = bridge
            .stage_node(
                NodeKind::Column {
                    label: String::new(),
                    style: Box::default(),
                },
                vec![first, second],
            )
            .unwrap();
        assert!(
            bridge
                .seed_keyed_column(duplicate, 1, vec![key, key])
                .is_err()
        );
    }

    fn button(label: &str, enabled: bool) -> NodeKind {
        NodeKind::Button {
            role: crate::bridge::ButtonRole::Button,
            caption: label.into(),
            label: label.into(),
            enabled,
            hover_enter: false,
            hover_exit: false,
            style: Box::default(),
        }
    }

    /// Every control a simulated pointer is allowed to press must have somewhere
    /// for that press to go: it either dispatches a click through the Roc event
    /// route, or it takes keyboard focus instead. A kind that satisfies neither
    /// would let the window runner report a successful `click` while the
    /// application never saw the press.
    #[test]
    fn every_pointer_target_either_dispatches_or_takes_focus() {
        let kinds = [
            button("Open", true),
            NodeKind::Checkbox {
                label: "Show files".into(),
                checked: false,
                enabled: true,
                indicator: CheckboxIndicator::default(),
                style: Box::default(),
            },
            NodeKind::TextInput {
                label: "Name".into(),
                value: String::new(),
                placeholder: String::new(),
                enabled: true,
                style: Box::default(),
            },
            NodeKind::Textarea {
                label: "Notes".into(),
                value: String::new(),
                placeholder: String::new(),
                enabled: true,
                read_only: false,
                style: Box::default(),
            },
            NodeKind::Canvas {
                label: "Timeline track".into(),
                primitives: vec![],
                hover: false,
                wheel: false,
                size: false,
                style: Box::default(),
            },
            NodeKind::Dialog {
                label: "Confirm".into(),
                style: Box::default(),
            },
            NodeKind::Text("Frame 0".into()),
        ];
        for kind in &kinds {
            assert!(
                !kind.accepts_pointer() || kind.dispatches_click() || kind.focuses_on_pointer(),
                "{kind:?} accepts a pointer press that reaches no handler"
            );
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
            style: Box::default(),
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
                style: style.clone(),
            },
            _ => unreachable!(),
        };
        assert!(!enabled.accepts_key(ControlKey::Enter));
        assert!(enabled.accepts_key(ControlKey::Space));
        assert!(!disabled.accepts_key(ControlKey::Space));

        let dialog = NodeKind::Dialog {
            label: "Confirm".into(),
            style: Box::default(),
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

    /// Identity is what survives a patch that renumbers every node. Two trees
    /// that describe the same controls must produce the same identities even
    /// though they share no node id.
    #[test]
    fn identity_survives_a_rebuild_that_renumbers_every_node() {
        let tree = |base: u64| {
            vec![
                Node {
                    id: base,
                    kind: NodeKind::Column {
                        label: "Transport".into(),
                        style: Box::default(),
                    },
                    children: vec![base + 1, base + 2, base + 3],
                },
                text(base + 1, "Frame 12"),
                Node {
                    id: base + 2,
                    kind: button("Pause", true),
                    children: vec![],
                },
                Node {
                    id: base + 3,
                    kind: button("Stop", true),
                    children: vec![],
                },
            ]
        };
        let mut first = MountedGraph::default();
        first
            .apply(Patch::Mount {
                root: 1,
                nodes: tree(1),
            })
            .expect("first mount");
        let mut second = MountedGraph::default();
        second
            .apply(Patch::Mount {
                root: 100,
                nodes: tree(100),
            })
            .expect("second mount");
        let before = first.element_identities();
        let after = second.element_identities();
        assert_eq!(before[&3], after[&102], "Pause changed identity");
        assert_eq!(before[&1], after[&100], "the column changed identity");
        assert_ne!(before[&3], before[&4], "two buttons share an identity");
    }

    /// Identity has to be unique inside one graph, or two controls would claim
    /// the same GPUI element. Sibling names an application repeats, and
    /// unnamed nodes, both have to stay apart.
    #[test]
    fn identity_is_unique_even_when_siblings_share_a_name() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![
                    Node {
                        id: 1,
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Box::default(),
                        },
                        children: vec![2, 3, 4, 5],
                    },
                    Node {
                        id: 2,
                        kind: button("Delete", true),
                        children: vec![],
                    },
                    Node {
                        id: 3,
                        kind: button("Delete", true),
                        children: vec![],
                    },
                    text(4, "one"),
                    text(5, "two"),
                ],
            })
            .expect("mount");
        let identities = graph.element_identities();
        let distinct = identities.values().collect::<HashSet<_>>();
        assert_eq!(distinct.len(), identities.len());
    }

    /// A control whose name changes is a different control. That is what makes
    /// a press on a control that left the tree get dropped rather than handed
    /// to whatever replaced it.
    #[test]
    fn renaming_a_control_changes_its_identity() {
        let mount = |name: &str| {
            let mut graph = MountedGraph::default();
            graph
                .apply(Patch::Mount {
                    root: 1,
                    nodes: vec![
                        Node {
                            id: 1,
                            kind: NodeKind::Row {
                                label: "Transport".into(),
                                style: Box::default(),
                            },
                            children: vec![2],
                        },
                        Node {
                            id: 2,
                            kind: button(name, true),
                            children: vec![],
                        },
                    ],
                })
                .expect("mount");
            graph.element_identities()[&2].clone()
        };
        assert_ne!(mount("Pause"), mount("Play"));
    }

    #[test]
    fn validates_a_small_tree() {
        let nodes = vec![
            text(2, "hello"),
            Node {
                id: 1,
                kind: NodeKind::Column {
                    label: String::new(),
                    style: Box::default(),
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
                style: Box::default(),
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
                    style: Box::default(),
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
                style: Box::default(),
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
                    style: Box::default(),
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
                style: Box::default(),
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
                    row_gap: 0,
                    style: Box::default(),
                    rows: None,
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
    fn a_provided_list_mounts_rows_only_inside_its_extent() {
        let list = |first, count, instance| Node {
            id: 5,
            kind: NodeKind::VirtualList {
                name: "rows".into(),
                row_height: 24,
                row_gap: 0,
                style: Box::default(),
                rows: Some(ProvidedRows {
                    instance,
                    count,
                    first,
                    notify: false,
                }),
            },
            children: vec![2, 4],
        };
        let rows = |list| {
            [
                text(1, "first"),
                Node {
                    id: 2,
                    kind: NodeKind::VirtualItem { key: 998 },
                    children: vec![1],
                },
                text(3, "second"),
                Node {
                    id: 4,
                    kind: NodeKind::VirtualItem { key: 999 },
                    children: vec![3],
                },
                list,
            ]
        };
        assert!(validate_tree(5, &rows(list(998, 1000, 9))).is_ok());
        for refused in [
            list(999, 1000, 9),
            list(u64::MAX, 1000, 9),
            list(0, 1000, 0),
        ] {
            assert!(
                validate_tree(5, &rows(refused))
                    .unwrap_err()
                    .contains("outside its provided extent")
            );
        }
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
                    row_gap: 0,
                    style: Box::default(),
                    rows: None,
                },
                children: vec![2],
            },
        ];
        graph.apply(Patch::Mount { root: 3, nodes }).unwrap();
        assert_eq!(graph.nodes_preorder().len(), 3);
        assert_eq!(graph.virtual_descendant_ids(), HashSet::from([1, 2]));
    }

    /// Bringing a virtual-list row into view is an index, not a rectangle: the
    /// row below the fold is in the graph but has no element.
    #[test]
    fn a_rows_position_in_its_list_is_recoverable_from_a_descendant() {
        let mut graph = MountedGraph::default();
        let mut nodes = vec![Node {
            id: 30,
            kind: NodeKind::VirtualList {
                name: "rows".into(),
                row_height: 24,
                row_gap: 0,
                style: Box::default(),
                rows: None,
            },
            children: vec![2, 4, 6],
        }];
        for (index, (item, leaf)) in [(2, 1), (4, 3), (6, 5)].into_iter().enumerate() {
            nodes.push(text(leaf, &format!("row {index}")));
            nodes.push(Node {
                id: item,
                kind: NodeKind::VirtualItem { key: item },
                children: vec![leaf],
            });
        }
        graph.apply(Patch::Mount { root: 30, nodes }).unwrap();
        // The deepest node, two levels below the list, still names row two.
        assert_eq!(graph.child_index_containing(30, 5), Some(2));
        assert_eq!(graph.child_index_containing(30, 2), Some(0));
        // The list is not inside itself, and an unrelated id is nowhere.
        assert_eq!(graph.child_index_containing(30, 30), None);
        assert_eq!(graph.child_index_containing(30, 99), None);
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
                            style: Box::default()
                        },
                        children: vec![2],
                    },
                    text(2, "child"),
                    Node {
                        id: 3,
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Box::default()
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
                        style: Box::default()
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
                            style: Box::default()
                        },
                        children: vec![2],
                    },
                    Node {
                        id: 2,
                        kind: NodeKind::Row {
                            label: String::new(),
                            style: Box::default()
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
                    style: Box::default(),
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
                            style: Box::default()
                        },
                        children: vec![1],
                    },
                    Node {
                        id: 3,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Box::default()
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
                            style: Box::default()
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
                    style: Box::default()
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
                    style: Box::default(),
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
                            style: Box::default()
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
                    style: Box::default(),
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
                            style: Box::default(),
                        },
                        children: vec![1],
                    },
                    Node {
                        id: 3,
                        kind: NodeKind::Column {
                            label: String::new(),
                            style: Box::default(),
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
                            style: Box::default(),
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
                            style: Box::default(),
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
                            style: Box::default(),
                        },
                        children: vec![3],
                    },
                ],
            })
            .unwrap();

        assert_eq!(replaced.facts.removed, 2);
        assert_eq!(replaced.facts.live, 2);
        assert!(replaced.retired_root);
        assert_eq!(replaced.removed_ids, vec![2, 1]);
        assert_eq!(replaced.parent, None);
        assert_eq!(graph.root(), Some(4));
        assert!(graph.node(1).is_none());
        assert!(graph.node(2).is_none());
        assert_eq!(graph.node(4).unwrap().children, vec![3]);
    }

    fn component(id: u64, instance: u64, child: u64) -> Node {
        Node {
            id,
            kind: NodeKind::Boundary { instance },
            children: vec![child],
        }
    }

    fn column(id: u64, children: Vec<u64>) -> Node {
        Node {
            id,
            kind: NodeKind::Column {
                label: "root".into(),
                style: Box::default(),
            },
            children,
        }
    }

    fn two_components() -> MountedGraph {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 5,
                nodes: vec![
                    text(1, "first"),
                    component(2, 1, 1),
                    text(3, "second"),
                    component(4, 2, 3),
                    column(5, vec![2, 4]),
                ],
            })
            .unwrap();
        graph
    }

    #[test]
    fn mounted_child_abstraction_preserves_ordinary_semantics() {
        let graph = two_components();
        assert_eq!(graph.children_of(5).collect::<Vec<_>>(), vec![2, 4]);
        assert_eq!(
            graph
                .nodes_preorder()
                .into_iter()
                .map(|node| node.id)
                .collect::<Vec<_>>(),
            vec![5, 2, 1, 4, 3]
        );
        assert_eq!(graph.child_index_containing(5, 1), Some(0));
        assert!(graph.is_descendant_of(3, 5));
        assert!(!graph.is_descendant_of(1, 4));
        let identities = graph.element_identities();
        assert_eq!(
            identities[&2],
            vec![IdentitySegment::Boundary { instance: 1 }]
        );
        assert_eq!(
            identities[&4],
            vec![IdentitySegment::Boundary { instance: 2 }]
        );
        assert!(graph.focus_order().is_empty());
    }

    #[test]
    fn retaining_reordered_components_preserves_ids_and_reattaches_roots() {
        let mut graph = two_components();
        let identities = graph.element_identities();
        let applied = graph
            .apply(Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![4, 2])],
                retained_roots: vec![2, 4],
            })
            .unwrap();
        assert_eq!(applied.staged_ids, vec![6]);
        assert_eq!(applied.removed_ids, vec![5]);
        assert_eq!(applied.facts.retained_nodes, 4);
        assert_eq!(applied.facts.live, 5);
        assert!(!applied.retired_root);
        assert_eq!(graph.parent(4), Some((6, 0)));
        assert_eq!(graph.parent(2), Some((6, 1)));
        assert_eq!(graph.parent(1), Some((2, 0)));
        assert_eq!(graph.subtree_size(6), Some(5));
        assert_eq!(graph.element_identities()[&1], identities[&1]);
        assert_eq!(graph.element_identities()[&3], identities[&3]);
        assert_eq!(graph.boundary_root(1), Some(2));
    }

    #[test]
    fn retained_parent_links_support_the_next_local_replacement() {
        let mut graph = two_components();
        graph
            .apply(Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![4, 2])],
                retained_roots: vec![2, 4],
            })
            .unwrap();
        let applied = graph
            .apply(Patch::Replace {
                old_root: 2,
                root: 9,
                nodes: vec![
                    text(7, "changed"),
                    text(8, "additional"),
                    column(10, vec![7, 8]),
                    component(9, 1, 10),
                ],
            })
            .unwrap();
        assert_eq!(applied.parent, Some((6, 1)));
        assert_eq!(graph.node(6).unwrap().children, vec![4, 9]);
        assert_eq!(graph.subtree_size(6), Some(7));
        assert_eq!(graph.subtree_size(9), Some(4));
        assert_eq!(graph.boundary_root(1), Some(9));
    }

    #[test]
    fn invalid_retention_is_atomic() {
        let cases = vec![
            Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![2, 4])],
                retained_roots: vec![2, 2, 4],
            },
            Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![1])],
                retained_roots: vec![1],
            },
            Patch::ReplaceRetaining {
                old_root: 2,
                root: 6,
                nodes: vec![column(6, vec![4])],
                retained_roots: vec![4],
            },
            Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![2, 2])],
                retained_roots: vec![2],
            },
            Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![2]), text(7, "unreachable")],
                retained_roots: vec![2],
            },
            Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![2])],
                retained_roots: vec![2, 4],
            },
            Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![99])],
                retained_roots: vec![99],
            },
        ];
        for patch in cases {
            let mut graph = two_components();
            let before = graph
                .nodes_preorder()
                .into_iter()
                .cloned()
                .collect::<Vec<_>>();
            assert!(graph.apply(patch).is_err());
            assert_eq!(
                graph
                    .nodes_preorder()
                    .into_iter()
                    .cloned()
                    .collect::<Vec<_>>(),
                before
            );
            assert_eq!(graph.boundary_root(1), Some(2));
            assert_eq!(graph.subtree_size(5), Some(5));
            graph
                .apply(Patch::Replace {
                    old_root: 1,
                    root: 6,
                    nodes: vec![text(6, "valid afterwards")],
                })
                .unwrap();
        }
    }

    #[test]
    fn retained_roots_must_be_disjoint() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 4,
                nodes: vec![
                    text(1, "leaf"),
                    component(2, 1, 1),
                    component(3, 2, 2),
                    column(4, vec![3]),
                ],
            })
            .unwrap();
        let error = graph
            .apply(Patch::ReplaceRetaining {
                old_root: 4,
                root: 5,
                nodes: vec![column(5, vec![3, 2])],
                retained_roots: vec![2, 3],
            })
            .unwrap_err();
        assert!(error.contains("overlap"));
        assert_eq!(graph.root(), Some(4));
    }

    #[test]
    fn changed_native_scope_requires_new_component_lifetime() {
        let mut graph = two_components();
        let error = graph
            .apply(Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![Node {
                    id: 6,
                    kind: NodeKind::Row {
                        label: "root".into(),
                        style: Box::default(),
                    },
                    children: vec![2, 4],
                }],
                retained_roots: vec![2, 4],
            })
            .unwrap_err();
        assert!(error.contains("structural scope"));
        let error = graph
            .apply(Patch::Replace {
                old_root: 5,
                root: 8,
                nodes: vec![
                    text(6, "new"),
                    component(7, 1, 6),
                    Node {
                        id: 8,
                        kind: NodeKind::Row {
                            label: "root".into(),
                            style: Box::default(),
                        },
                        children: vec![7],
                    },
                ],
            })
            .unwrap_err();
        assert!(error.contains("structural scope"));
    }

    #[test]
    fn retired_node_ids_and_component_instances_cannot_be_resurrected() {
        let mut graph = two_components();
        graph
            .apply(Patch::ReplaceRetaining {
                old_root: 5,
                root: 6,
                nodes: vec![column(6, vec![2])],
                retained_roots: vec![2],
            })
            .unwrap();
        assert_eq!(graph.boundary_root(2), None);
        assert!(
            graph
                .apply(Patch::Replace {
                    old_root: 1,
                    root: 3,
                    nodes: vec![text(3, "reused")]
                })
                .unwrap_err()
                .contains("previously issued")
        );
        assert!(
            graph
                .apply(Patch::Replace {
                    old_root: 2,
                    root: 8,
                    nodes: vec![text(7, "recreated"), component(8, 2, 7)],
                })
                .unwrap_err()
                .contains("retired")
        );
        graph
            .apply(Patch::Replace {
                old_root: 2,
                root: 8,
                nodes: vec![text(7, "new lifetime"), component(8, 3, 7)],
            })
            .unwrap();
        assert_eq!(graph.boundary_root(3), Some(8));
    }

    #[test]
    fn disconnected_cycles_are_rejected_for_dense_and_sparse_ids() {
        for (root, a, b) in [(1, 2, 3), (10, 20, 30)] {
            assert!(
                validate_tree(
                    root,
                    &[column(root, vec![]), column(a, vec![b]), column(b, vec![a])]
                )
                .unwrap_err()
                .contains("disconnected")
            );
        }
    }

    #[test]
    fn local_replacement_among_direct_component_siblings_keeps_bounded_graph_work() {
        for count in [100_u64, 1_000, 10_000] {
            let mut graph = MountedGraph::default();
            let parent = count * 2 + 1;
            let mut nodes = Vec::new();
            let mut children = Vec::new();
            for instance in 1..=count {
                let content = instance * 2 - 1;
                let boundary = instance * 2;
                nodes.push(text(content, "row"));
                nodes.push(component(boundary, instance, content));
                children.push(boundary);
            }
            nodes.push(column(parent, children));
            graph
                .apply(Patch::Mount {
                    root: parent,
                    nodes,
                })
                .unwrap();

            let instance = count / 2;
            let old_root = instance * 2;
            let root = parent + 2;
            let applied = graph
                .apply(Patch::Replace {
                    old_root,
                    root,
                    nodes: vec![
                        text(parent + 1, "edited"),
                        component(root, instance, parent + 1),
                    ],
                })
                .unwrap();

            assert_eq!(applied.facts.staged, 2);
            assert_eq!(applied.facts.removed, 2);
            assert_eq!(applied.facts.validation_visits, 6);
            assert_eq!(applied.facts.scanned, 1);
            assert_eq!(graph.subtree_size(parent), Some(count * 2 + 1));
            assert_eq!(graph.parent(root), Some((parent, instance as usize - 1)));
            assert_eq!(
                graph.cached_segment(root),
                Some(&IdentitySegment::Boundary { instance })
            );
            for sibling in [1, instance - 1, instance + 1, count] {
                assert_eq!(graph.boundary_root(sibling), Some(sibling * 2));
                assert_eq!(
                    graph.cached_segment(sibling * 2),
                    Some(&IdentitySegment::Boundary { instance: sibling })
                );
            }
        }
    }

    #[test]
    fn boundaries_have_one_child_and_unique_live_instances() {
        assert!(
            validate_tree(
                1,
                &[Node {
                    id: 1,
                    kind: NodeKind::Boundary { instance: 0 },
                    children: vec![]
                }]
            )
            .unwrap_err()
            .contains("one content child")
        );
        assert!(
            validate_tree(
                5,
                &[
                    text(1, "a"),
                    component(2, 1, 1),
                    text(3, "b"),
                    component(4, 1, 3),
                    column(5, vec![2, 4])
                ]
            )
            .unwrap_err()
            .contains("duplicate component instance")
        );
        let mut graph = two_components();
        assert!(
            graph
                .apply(Patch::ReplaceRetaining {
                    old_root: 5,
                    root: 8,
                    nodes: vec![
                        text(6, "duplicate"),
                        component(7, 1, 6),
                        column(8, vec![2, 7])
                    ],
                    retained_roots: vec![2],
                })
                .unwrap_err()
                .contains("already mounted")
        );
    }

    #[test]
    fn retained_constraints_distinguish_global_dialogs_from_component_input_labels() {
        let kinds = [
            NodeKind::Dialog {
                label: "modal".into(),
                style: Box::default(),
            },
            NodeKind::TextInput {
                label: "field".into(),
                value: String::new(),
                placeholder: String::new(),
                enabled: true,
                style: Box::default(),
            },
        ];
        for kind in kinds {
            let is_dialog = matches!(kind, NodeKind::Dialog { .. });
            let mut graph = MountedGraph::default();
            graph
                .apply(Patch::Mount {
                    root: 3,
                    nodes: vec![
                        Node {
                            id: 1,
                            kind: kind.clone(),
                            children: vec![],
                        },
                        component(2, 1, 1),
                        column(3, vec![2]),
                    ],
                })
                .unwrap();
            let result = graph.apply(Patch::ReplaceRetaining {
                old_root: 3,
                root: 5,
                nodes: vec![
                    Node {
                        id: 4,
                        kind,
                        children: vec![],
                    },
                    column(5, vec![2, 4]),
                ],
                retained_roots: vec![2],
            });
            if is_dialog {
                assert!(result.is_err());
                assert_eq!(graph.root(), Some(3));
            } else {
                assert!(
                    result.is_ok(),
                    "same input label in different component scopes is valid"
                );
                assert_eq!(graph.root(), Some(5));
            }
        }
    }

    #[test]
    fn input_label_indices_follow_component_scope_during_local_replacement() {
        let field = |id| Node {
            id,
            kind: NodeKind::TextInput {
                label: "Name".into(),
                value: String::new(),
                placeholder: String::new(),
                enabled: true,
                style: Box::default(),
            },
            children: vec![],
        };
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 8,
                nodes: vec![
                    field(1),
                    text(2, "slot"),
                    column(3, vec![1, 2]),
                    component(4, 1, 3),
                    field(5),
                    component(6, 2, 5),
                    column(7, vec![4, 6]),
                    component(8, 0, 7),
                ],
            })
            .unwrap();
        graph
            .apply(Patch::Replace {
                old_root: 5,
                root: 9,
                nodes: vec![field(9)],
            })
            .unwrap();
        assert!(
            graph
                .apply(Patch::Replace {
                    old_root: 2,
                    root: 10,
                    nodes: vec![field(10)]
                })
                .unwrap_err()
                .contains("duplicate text input label")
        );
        graph
            .apply(Patch::Replace {
                old_root: 1,
                root: 10,
                nodes: vec![field(10)],
            })
            .unwrap();
        assert_eq!(graph.input_labels.get(&(Some(1), "Name".into())), Some(&10));
        assert_eq!(graph.input_labels.get(&(Some(2), "Name".into())), Some(&9));
    }

    #[test]
    fn staging_accepts_only_explicit_retention_and_rejects_dirty_no_change() {
        let mut bridge = BridgeState::new();
        let leaf = bridge
            .stage_node(NodeKind::Text("leaf".into()), vec![])
            .unwrap();
        let boundary = bridge
            .stage_node(NodeKind::Boundary { instance: 0 }, vec![leaf])
            .unwrap();
        bridge.commit(Commit::Mount { root: boundary }).unwrap();
        bridge.pending.take();
        assert_eq!(bridge.retain_subtree(boundary), Ok(boundary));
        assert!(
            bridge
                .retain_subtree(boundary)
                .unwrap_err()
                .contains("duplicate")
        );
        assert!(
            bridge
                .commit(Commit::NoChange)
                .unwrap_err()
                .contains("retention")
        );
        assert!(
            bridge
                .commit(Commit::Mount { root: boundary })
                .unwrap_err()
                .contains("retention")
        );
        let root = bridge
            .stage_node(
                NodeKind::Column {
                    label: "root".into(),
                    style: Box::default(),
                },
                vec![boundary],
            )
            .unwrap();
        bridge
            .commit(Commit::Replace {
                old_root: boundary,
                root,
            })
            .unwrap();
        assert!(
            matches!(bridge.pending.take(), Some(Patch::ReplaceRetaining { retained_roots, .. }) if retained_roots == vec![boundary])
        );
        assert!(
            bridge
                .stage_node(
                    NodeKind::Column {
                        label: "other".into(),
                        style: Box::default()
                    },
                    vec![boundary]
                )
                .unwrap_err()
                .contains("unstaged")
        );
    }

    #[test]
    fn no_change_has_no_graph_validation_or_retirement_work() {
        let mut graph = two_components();
        let result = graph.apply(Patch::NoChange).unwrap();
        assert_eq!(result.facts.validation_visits, 0);
        assert_eq!(result.facts.staged, 0);
        assert_eq!(result.facts.removed, 0);
        assert_eq!(result.facts.live, 5);
    }

    #[test]
    fn retention_validation_does_not_visit_unchanged_interiors() {
        let mut visits = Vec::new();
        for count in [1_u64, 1000, 10_000] {
            let mut nodes = (1..=count).map(|id| text(id, "row")).collect::<Vec<_>>();
            nodes.push(column(count + 1, (1..=count).collect()));
            nodes.push(component(count + 2, 1, count + 1));
            nodes.push(column(count + 3, vec![count + 2]));
            let mut graph = MountedGraph::default();
            graph
                .apply(Patch::Mount {
                    root: count + 3,
                    nodes,
                })
                .unwrap();
            let applied = graph
                .apply(Patch::ReplaceRetaining {
                    old_root: count + 3,
                    root: count + 4,
                    nodes: vec![column(count + 4, vec![count + 2])],
                    retained_roots: vec![count + 2],
                })
                .unwrap();
            assert_eq!(applied.facts.retained_nodes, count + 2);
            assert_eq!(applied.facts.staged, 1);
            assert_eq!(applied.facts.removed, 1);
            visits.push(applied.facts.validation_visits);
        }
        assert_eq!(visits, vec![5, 5, 5]);
    }

    fn test_digest(value: u64) -> [u8; 32] {
        let mut digest = [0; 32];
        digest[..8].copy_from_slice(&value.to_le_bytes());
        digest
    }

    fn registered_component() -> (ComponentRegistry, MountedGraph) {
        let mut registry = ComponentRegistry::default();
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert_eq!(registry.resolve(1, &[1; 32]), Ok((1, 0)));
        registry.component_enter(1).unwrap();
        registry.component_exit().unwrap();
        registry.scope_exit().unwrap();
        registry.finish_render().unwrap();
        let mut graph = MountedGraph::default();
        let applied = graph
            .apply(Patch::Mount {
                root: 4,
                nodes: vec![
                    text(1, "leaf"),
                    component(2, 1, 1),
                    column(3, vec![2]),
                    component(4, 0, 3),
                ],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        (registry, graph)
    }

    #[test]
    fn component_registry_scratch_capacity_belongs_to_only_one_transaction() {
        let mut registry = ComponentRegistry::default();
        let mut graph = MountedGraph::default();
        let count = 10_000;
        let mut nodes = Vec::new();
        let mut children = Vec::new();
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        for key in 1..=count {
            let (instance, old_root) = registry.resolve(1, &test_digest(key)).unwrap();
            assert_eq!(old_root, 0);
            nodes.push(text(key * 2 - 1, "row"));
            nodes.push(component(key * 2, instance, key * 2 - 1));
            children.push(key * 2);
        }
        registry.scope_exit().unwrap();
        registry.finish_render().unwrap();
        assert!(registry.pending.capacity() >= count as usize);
        nodes.push(column(count * 2 + 1, children));
        let applied = graph
            .apply(Patch::Mount {
                root: count * 2 + 1,
                nodes,
            })
            .unwrap();
        registry.commit(&graph, &applied);
        assert_eq!(registry.live.len(), count as usize);
        assert_eq!(registry.pending.capacity(), 0);
        assert_eq!(registry.pending_instances.capacity(), 0);
        assert_eq!(registry.seen.capacity(), 0);

        registry.begin_render(count / 2).unwrap();
        registry.resolve(1, &test_digest(1)).unwrap();
        assert!(registry.pending.capacity() < 16);
        assert!(registry.pending_instances.capacity() < 16);
        assert!(registry.seen.capacity() < 16);
        registry.abort();
        assert_eq!(registry.pending.capacity(), 0);
        assert_eq!(registry.pending_instances.capacity(), 0);
        assert_eq!(registry.seen.capacity(), 0);
        assert_eq!(registry.live.len(), count as usize);
    }

    #[test]
    fn component_registry_matches_scoped_keys_after_retention() {
        let (mut registry, mut graph) = registered_component();
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert_eq!(registry.resolve(1, &[1; 32]), Ok((1, 2)));
        registry.scope_exit().unwrap();
        registry.finish_render().unwrap();
        let applied = graph
            .apply(Patch::ReplaceRetaining {
                old_root: 4,
                root: 6,
                nodes: vec![column(5, vec![2]), component(6, 0, 5)],
                retained_roots: vec![2],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        registry.begin_render(1).unwrap();
        registry.finish_render().unwrap();
        let applied = graph
            .apply(Patch::Replace {
                old_root: 2,
                root: 8,
                nodes: vec![text(7, "changed"), component(8, 1, 7)],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert_eq!(registry.resolve(1, &[1; 32]), Ok((1, 8)));
    }

    #[test]
    fn component_registry_key_changes_and_retirement_allocate_new_lifetimes() {
        let (mut registry, mut graph) = registered_component();
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert_eq!(registry.resolve(1, &[2; 32]), Ok((2, 0)));
        registry.scope_exit().unwrap();
        registry.finish_render().unwrap();
        let applied = graph
            .apply(Patch::Replace {
                old_root: 4,
                root: 8,
                nodes: vec![
                    text(5, "new key"),
                    component(6, 2, 5),
                    column(7, vec![6]),
                    component(8, 0, 7),
                ],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        assert!(
            registry
                .begin_render(1)
                .unwrap_err()
                .contains("not mounted")
        );
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert_eq!(registry.resolve(1, &[1; 32]), Ok((3, 0)));
        registry.abort();
        let applied = graph
            .apply(Patch::Replace {
                old_root: 8,
                root: 10,
                nodes: vec![column(9, vec![]), component(10, 0, 9)],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert_eq!(registry.resolve(1, &[2; 32]), Ok((4, 0)));
    }

    #[test]
    fn component_registry_rejects_duplicate_keys() {
        let mut registry = ComponentRegistry::default();
        registry.begin_render(0).unwrap();
        assert_eq!(registry.resolve(1, &test_digest(7)), Ok((1, 0)));
        assert!(
            registry
                .resolve(1, &test_digest(7))
                .unwrap_err()
                .contains("duplicate component key")
        );
        assert_eq!(registry.resolve(1, &[7; 32]), Ok((2, 0)));
        registry.abort();
        registry.begin_render(0).unwrap();
        assert_eq!(
            registry.resolve(1, &test_digest(7)),
            Ok((3, 0)),
            "aborted allocation cannot be reused"
        );
    }

    #[test]
    fn component_registry_native_scope_changes_remount() {
        let (mut registry, _) = registered_component();
        registry.begin_render(0).unwrap();
        registry.scope_enter(8, "root", 0).unwrap();
        assert_eq!(
            registry.resolve(1, &[1; 32]),
            Ok((2, 0)),
            "Column became Row"
        );
        registry.abort();
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "wrapper", 0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert_eq!(
            registry.resolve(1, &[1; 32]),
            Ok((3, 0)),
            "new native wrapper changes scope"
        );
    }

    fn hover_button(id: u64, enabled: bool, enter: bool, exit: bool) -> Node {
        Node {
            id,
            kind: NodeKind::Button {
                role: crate::bridge::ButtonRole::Button,
                caption: "Cell".into(),
                label: "Cell".into(),
                enabled,
                hover_enter: enter,
                hover_exit: exit,
                style: Box::default(),
            },
            children: vec![],
        }
    }

    #[test]
    fn hover_edges_use_live_routes_and_track_optional_handlers() {
        for (enter, exit) in [(true, true), (true, false), (false, true), (false, false)] {
            let mut graph = MountedGraph::default();
            graph
                .apply(Patch::Mount {
                    root: 1,
                    nodes: vec![hover_button(1, true, enter, exit)],
                })
                .unwrap();
            assert_eq!(graph.hover_transition(1, false), None);
            assert_eq!(
                graph.hover_transition(1, true),
                enter.then_some(1 | HOVER_ENTER_EVENT_BIT)
            );
            assert_eq!(graph.hover_transition(1, true), None);
            assert_eq!(
                graph.hover_transition(1, false),
                exit.then_some(1 | HOVER_EXIT_EVENT_BIT)
            );
            assert_eq!(graph.hover_transition(1, false), None);
            graph
                .apply(Patch::Replace {
                    old_root: 1,
                    root: 2,
                    nodes: vec![hover_button(2, false, enter, exit)],
                })
                .unwrap();
            assert_eq!(graph.hover_transition(1, true), None);
            assert_eq!(graph.hover_transition(2, true), None);
        }
    }

    #[test]
    fn modal_input_policy_retires_background_hover_without_callbacks() {
        for deliver_blocked_exit in [false, true] {
            let mut graph = MountedGraph::default();
            graph
                .apply(Patch::Mount {
                    root: 10,
                    nodes: vec![
                        hover_button(1, true, true, true),
                        text(2, "slot"),
                        column(10, vec![1, 2]),
                    ],
                })
                .unwrap();
            assert_eq!(
                graph.hover_transition(1, true),
                Some(1 | HOVER_ENTER_EVENT_BIT)
            );
            graph
                .apply(Patch::Replace {
                    old_root: 2,
                    root: 20,
                    nodes: vec![
                        Node {
                            id: 20,
                            kind: NodeKind::Dialog {
                                label: "Modal".into(),
                                style: Box::default(),
                            },
                            children: vec![21],
                        },
                        hover_button(21, true, true, true),
                    ],
                })
                .unwrap();
            assert!(!graph.hovered.contains(&1));
            assert_eq!(graph.hover_transition(1, true), None);
            if deliver_blocked_exit {
                assert_eq!(graph.hover_transition(1, false), None);
            }
            assert_eq!(
                graph.hover_transition(21, true),
                Some(21 | HOVER_ENTER_EVENT_BIT)
            );
            // Rebuilding only modal content must preserve an active modal hover.
            graph
                .apply(Patch::Replace {
                    old_root: 21,
                    root: 22,
                    nodes: vec![hover_button(22, true, true, true)],
                })
                .unwrap();
            assert_eq!(graph.hover_transition(22, true), None);
            assert_eq!(
                graph.hover_transition(22, false),
                Some(22 | HOVER_EXIT_EVENT_BIT)
            );
            graph
                .apply(Patch::Replace {
                    old_root: 20,
                    root: 23,
                    nodes: vec![text(23, "slot")],
                })
                .unwrap();
            assert_eq!(
                graph.hover_transition(1, true),
                Some(1 | HOVER_ENTER_EVENT_BIT)
            );
            assert_eq!(graph.hover_transition(1, true), None);
            assert_eq!(
                graph.hover_transition(1, false),
                Some(1 | HOVER_EXIT_EVENT_BIT)
            );
            assert_eq!(graph.hover_transition(21, true), None);
        }
    }

    #[test]
    fn hover_survives_local_replacement_without_visiting_unrelated_siblings() {
        for count in [100_u64, 1_000, 10_000] {
            let mut graph = MountedGraph::default();
            let mut nodes = Vec::new();
            let mut children = Vec::new();
            for instance in 1..=count {
                nodes.push(hover_button(instance * 2 - 1, true, true, true));
                nodes.push(component(instance * 2, instance, instance * 2 - 1));
                children.push(instance * 2);
            }
            let root = count * 2 + 1;
            nodes.push(column(root, children));
            graph.apply(Patch::Mount { root, nodes }).unwrap();
            assert_eq!(
                graph.hover_transition(1, true),
                Some(1 | HOVER_ENTER_EVENT_BIT)
            );
            let next = root + 1;
            let applied = graph
                .apply(Patch::Replace {
                    old_root: 2,
                    root: next + 1,
                    nodes: vec![
                        hover_button(next, true, true, true),
                        component(next + 1, 1, next),
                    ],
                })
                .unwrap();
            assert_eq!(applied.facts.staged, 2);
            assert_eq!(applied.facts.removed, 2);
            assert_eq!(
                graph.hover_transition(1, false),
                None,
                "retired route cannot leave replacement"
            );
            assert_eq!(
                graph.hover_transition(next, true),
                None,
                "replacement preserves hovered state"
            );
            assert_eq!(
                graph.hover_transition(next, false),
                Some(next | HOVER_EXIT_EVENT_BIT)
            );
            assert_eq!(
                graph.hover_transition(next, true),
                Some(next | HOVER_ENTER_EVENT_BIT)
            );
            graph
                .apply(Patch::Replace {
                    old_root: next + 1,
                    root: next + 3,
                    nodes: vec![
                        hover_button(next + 2, true, true, true),
                        component(next + 3, count + 1, next + 2),
                    ],
                })
                .unwrap();
            assert_eq!(
                graph.hover_transition(next + 2, true),
                Some((next + 2) | HOVER_ENTER_EVENT_BIT),
                "owner remount resets hover lifetime"
            );
        }
    }

    #[test]
    fn component_registry_validates_digest_without_allocating() {
        let mut registry = ComponentRegistry::default();
        registry.begin_render(0).unwrap();
        for length in [0, 1, 31, 33, 64] {
            assert!(
                registry
                    .resolve(1, &vec![0; length])
                    .unwrap_err()
                    .contains("exactly 32 bytes")
            );
        }
        assert!(registry.resolve(0, &[0; 32]).is_err());
        assert!(registry.resolve(2, &[0; 32]).is_err());
        assert_eq!(registry.resolve(1, &[0; 32]), Ok((1, 0)));
        let mut last_bit = [0; 32];
        last_bit[31] = 128;
        assert_eq!(
            registry.resolve(1, &last_bit),
            Ok((2, 0)),
            "all 256 digest bits participate in identity"
        );
    }

    #[test]
    fn component_registry_unkeyed_reconstruction_has_a_new_lifetime() {
        let mut registry = ComponentRegistry::default();
        registry.begin_render(0).unwrap();
        assert_eq!(registry.resolve(0, &[]), Ok((1, 0)));
        assert_eq!(
            registry.resolve(0, &[]),
            Ok((2, 0)),
            "unkeyed siblings never collide"
        );
        registry.finish_render().unwrap();
        let mut graph = MountedGraph::default();
        let applied = graph
            .apply(Patch::Mount {
                root: 5,
                nodes: vec![
                    text(1, "first"),
                    component(2, 1, 1),
                    text(3, "second"),
                    component(4, 2, 3),
                    column(5, vec![2, 4]),
                ],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        registry.begin_render(1).unwrap();
        registry.finish_render().unwrap();
        let applied = graph
            .apply(Patch::Replace {
                old_root: 2,
                root: 7,
                nodes: vec![text(6, "local"), component(7, 1, 6)],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        assert_eq!(graph.boundary_root(1), Some(7));
        registry.begin_render(0).unwrap();
        assert_eq!(registry.resolve(0, &[]), Ok((3, 0)));
        assert_eq!(registry.resolve(0, &[]), Ok((4, 0)));
        registry.abort();
        registry.begin_render(0).unwrap();
        assert_eq!(
            registry.resolve(0, &[]),
            Ok((5, 0)),
            "aborted lifetimes cannot be reused"
        );
    }

    #[test]
    fn component_registry_keyed_reorder_keeps_identity_but_owner_remount_does_not() {
        let mut registry = ComponentRegistry::default();
        registry.begin_render(0).unwrap();
        assert_eq!(registry.resolve(1, &[1; 32]), Ok((1, 0)));
        registry.component_enter(1).unwrap();
        assert_eq!(registry.resolve(1, &[2; 32]), Ok((2, 0)));
        assert_eq!(registry.resolve(1, &[3; 32]), Ok((3, 0)));
        registry.component_exit().unwrap();
        registry.finish_render().unwrap();
        let mut graph = MountedGraph::default();
        let applied = graph
            .apply(Patch::Mount {
                root: 6,
                nodes: vec![
                    text(1, "a"),
                    component(2, 2, 1),
                    text(3, "b"),
                    component(4, 3, 3),
                    column(5, vec![2, 4]),
                    component(6, 1, 5),
                ],
            })
            .unwrap();
        registry.commit(&graph, &applied);
        registry.begin_render(1).unwrap();
        assert_eq!(registry.resolve(1, &[3; 32]), Ok((3, 4)));
        assert_eq!(registry.resolve(1, &[2; 32]), Ok((2, 2)));
        registry.abort();
        registry.begin_render(0).unwrap();
        assert_eq!(registry.resolve(1, &[4; 32]), Ok((4, 0)));
        registry.component_enter(4).unwrap();
        assert_eq!(
            registry.resolve(1, &[2; 32]),
            Ok((5, 0)),
            "same child key under a new owner starts a new lifetime"
        );
    }

    #[test]
    fn component_registry_scopes_must_balance_before_commit() {
        let mut registry = ComponentRegistry::default();
        assert!(registry.resolve(0, &[]).is_err());
        registry.begin_render(0).unwrap();
        registry.scope_enter(5, "root", 0).unwrap();
        assert!(
            registry
                .finish_render()
                .unwrap_err()
                .contains("unfinished scopes")
        );
        assert!(registry.component_exit().is_err());
        registry.resolve(1, &[1; 32]).unwrap();
        registry.component_enter(1).unwrap();
        assert!(registry.scope_exit().is_err());
        registry.component_exit().unwrap();
        registry.scope_exit().unwrap();
        registry.finish_render().unwrap();
        assert!(
            registry.begin_render(0).is_err(),
            "finished lowering still awaits graph acceptance"
        );
    }

    fn popover(id: u64, label: &str, delay_ms: u32, handlers: bool, children: Vec<u64>) -> Node {
        Node {
            id,
            kind: NodeKind::Popover {
                label: label.into(),
                placement: Placement::Below,
                delay_ms,
                hover_enter: handlers,
                hover_exit: handlers,
                shortcuts: vec![],
                focus_serial: 0,
                style: Box::default(),
            },
            children,
        }
    }

    /// A region of one child that answers `chords` and asks for focus with
    /// `serial`.
    fn keyed_region(id: u64, child: u64, chords: &[(&str, ShortcutScope)], serial: u64) -> Node {
        Node {
            id,
            kind: NodeKind::Popover {
                label: String::new(),
                placement: Placement::Below,
                delay_ms: 0,
                hover_enter: false,
                hover_exit: false,
                shortcuts: chords
                    .iter()
                    .map(|(keys, scope)| Shortcut {
                        keys: (*keys).into(),
                        scope: *scope,
                    })
                    .collect(),
                focus_serial: serial,
                style: Box::default(),
            },
            children: vec![child],
        }
    }

    fn resolve(graph: &mut MountedGraph, focused: Option<u64>, chord: &str) -> Option<(u64, u64)> {
        graph
            .resolve_shortcut(focused, false, |declared| declared == chord)
            .map(|found| (found.region, found.index))
    }

    /// A window region 20 around a column holding a focus region 21 around
    /// button 1, a window region 22 around button 2, and a plain button 3.
    fn shortcut_tree(base: u64) -> Vec<Node> {
        use ShortcutScope::{Focus, Window};
        vec![
            button_node(base + 1, "One"),
            button_node(base + 2, "Two"),
            button_node(base + 3, "Three"),
            keyed_region(
                base + 21,
                base + 1,
                &[("down", Focus), ("ctrl-k", Window)],
                0,
            ),
            keyed_region(
                base + 22,
                base + 2,
                &[("ctrl-k", Window), ("ctrl-j", Window)],
                0,
            ),
            column(base + 10, vec![base + 21, base + 22, base + 3]),
            keyed_region(
                base + 20,
                base + 10,
                &[("ctrl-k", Window), ("f1", Window)],
                0,
            ),
        ]
    }

    fn button_node(id: u64, label: &str) -> Node {
        Node {
            id,
            kind: button(label, true),
            children: vec![],
        }
    }

    #[test]
    fn a_shortcut_nearer_focus_wins_and_focus_shortcuts_need_focus_inside() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 20,
                nodes: shortcut_tree(0),
            })
            .unwrap();
        // With focus in the focus region, it answers first, innermost first.
        assert_eq!(resolve(&mut graph, Some(1), "down"), Some((21, 0)));
        assert_eq!(resolve(&mut graph, Some(1), "ctrl-k"), Some((21, 1)));
        assert_eq!(resolve(&mut graph, Some(2), "ctrl-k"), Some((22, 0)));
        // Elsewhere its focus shortcut is not live, and among regions not
        // enclosing focus the last in document order wins.
        assert_eq!(resolve(&mut graph, Some(3), "down"), None);
        assert_eq!(resolve(&mut graph, Some(3), "ctrl-k"), Some((20, 0)));
        assert_eq!(resolve(&mut graph, None, "ctrl-j"), Some((22, 1)));
        assert_eq!(resolve(&mut graph, None, "f1"), Some((20, 1)));
        assert_eq!(resolve(&mut graph, None, "f2"), None);
        let counters = graph.keyboard_counters();
        assert_eq!((counters.offered, counters.matched), (8, 6));
    }

    #[test]
    fn a_typed_character_in_a_text_field_reaches_no_shortcut() {
        let mut graph = MountedGraph::default();
        let field = Node {
            id: 1,
            kind: NodeKind::TextInput {
                label: "Filter".into(),
                value: String::new(),
                placeholder: String::new(),
                enabled: true,
                style: Box::default(),
            },
            children: vec![],
        };
        graph
            .apply(Patch::Mount {
                root: 2,
                nodes: vec![
                    field,
                    keyed_region(2, 1, &[("j", ShortcutScope::Window)], 0),
                ],
            })
            .unwrap();
        assert!(graph.resolve_shortcut(Some(1), true, |_| true).is_none());
        assert_eq!(graph.keyboard_counters().compared, 0);
        assert!(
            graph
                .resolve_shortcut(None, true, |keys| keys == "j")
                .is_some()
        );
    }

    #[test]
    fn a_modal_dialog_leaves_only_its_own_shortcuts_live() {
        let mut graph = MountedGraph::default();
        let mut nodes = shortcut_tree(0);
        nodes.retain(|node| node.id != 20);
        nodes.push(button_node(30, "Close"));
        nodes.push(keyed_region(
            31,
            30,
            &[("ctrl-j", ShortcutScope::Window)],
            0,
        ));
        nodes.push(Node {
            id: 32,
            kind: NodeKind::Dialog {
                label: "Palette".into(),
                style: Box::default(),
            },
            children: vec![31],
        });
        nodes.push(keyed_region(
            20,
            10,
            &[("ctrl-k", ShortcutScope::Window)],
            0,
        ));
        nodes.push(column(40, vec![20, 32]));
        graph.apply(Patch::Mount { root: 40, nodes }).unwrap();
        assert_eq!(resolve(&mut graph, Some(30), "ctrl-k"), None);
        assert_eq!(resolve(&mut graph, Some(30), "ctrl-j"), Some((31, 0)));
        assert_eq!(resolve(&mut graph, None, "ctrl-j"), Some((31, 0)));
    }

    #[test]
    fn a_region_takes_focus_once_for_each_new_serial() {
        let tree = |serial: u64, base: u64| {
            vec![
                text(base + 1, "Heading"),
                button_node(base + 2, "Choose"),
                column(base + 3, vec![base + 1, base + 2]),
                keyed_region(base + 4, base + 3, &[], serial),
                column(base + 10, vec![base + 4]),
            ]
        };
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 10,
                nodes: tree(7, 0),
            })
            .unwrap();
        assert_eq!(graph.take_focus_request(), Some(2));
        assert_eq!(graph.take_focus_request(), None);
        // The same serial on the region that replaces it asks for nothing.
        graph
            .apply(Patch::Replace {
                old_root: 10,
                root: 110,
                nodes: tree(7, 100),
            })
            .unwrap();
        assert_eq!(graph.take_focus_request(), None);
        // A new serial asks again; 0 never asks.
        graph
            .apply(Patch::Replace {
                old_root: 110,
                root: 210,
                nodes: tree(8, 200),
            })
            .unwrap();
        assert_eq!(graph.take_focus_request(), Some(202));
        graph
            .apply(Patch::Replace {
                old_root: 210,
                root: 310,
                nodes: tree(0, 300),
            })
            .unwrap();
        assert_eq!(graph.take_focus_request(), None);
        assert_eq!(graph.keyboard_counters().focused, 2);
    }

    /// A cell with a note: column 10 holds popover 3, anchoring text 1 and
    /// presenting text 2.
    fn noted_cell(base: u64, delay_ms: u32) -> Vec<Node> {
        vec![
            text(base + 1, "cell"),
            text(base + 2, "note"),
            popover(base + 3, "Note", delay_ms, false, vec![base + 1, base + 2]),
            column(base + 10, vec![base + 3]),
        ]
    }

    /// A split 5 of button 1 and button 2, sizing its end pane, collapsible,
    /// whose divider answers `left` and `enter`, inside column 10.
    fn split_tree(base: u64, collapsed: bool) -> Vec<Node> {
        vec![
            button_node(base + 1, "Main"),
            button_node(base + 2, "Aside"),
            Node {
                id: base + 5,
                kind: NodeKind::Split {
                    label: "Divider".into(),
                    axis: SplitAxis::Horizontal,
                    side: SplitSide::End,
                    size: 300,
                    min: 200,
                    max: 600,
                    collapsible: true,
                    collapsed,
                    thickness: 6,
                    shortcuts: ["left", "enter"]
                        .iter()
                        .map(|keys| Shortcut {
                            keys: (*keys).into(),
                            scope: ShortcutScope::Focus,
                        })
                        .collect(),
                    style: Box::default(),
                },
                children: vec![base + 1, base + 2],
            },
            column(base + 10, vec![base + 5]),
        ]
    }

    #[test]
    fn a_drag_asks_for_a_size_measured_from_the_press_within_the_bounds() {
        let kind = split_tree(0, false)
            .into_iter()
            .find(|node| node.id == 5)
            .unwrap()
            .kind;
        let grip = kind.splitter_grip().unwrap();
        let ask = |size, collapsed| Resize { size, collapsed };
        // The sized pane is after the divider, so moving towards the start
        // widens it and moving towards the end narrows it.
        assert_eq!(grip.resize(-40.0, 13.0), ask(340, false));
        assert_eq!(grip.resize(40.4, 0.0), ask(260, false));
        // Movement across the axis is not movement along it.
        assert_eq!(grip.resize(0.0, 500.0), ask(300, false));
        assert_eq!(grip.resize(-900.0, 0.0), ask(600, false));
        // Below the minimum it holds the minimum, until past half of it,
        // where a collapsible pane asks to fold and keeps its size.
        assert_eq!(grip.resize(150.0, 0.0), ask(200, false));
        assert_eq!(grip.resize(201.0, 0.0), ask(300, true));
        assert_eq!(kind.splitter_value(), Some(ask(300, false)));
        // A folded pane is dragged out from nothing.
        let folded = split_tree(0, true)
            .into_iter()
            .find(|node| node.id == 5)
            .unwrap()
            .kind;
        assert_eq!(folded.hidden_pane(), Some(1));
        assert_eq!(
            folded.splitter_grip().unwrap().resize(-250.0, 0.0),
            ask(250, false)
        );
        assert_eq!(kind.hidden_pane(), None);
    }

    #[test]
    fn a_collapsed_split_keeps_its_pane_mounted_but_not_presented() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 10,
                nodes: split_tree(0, true),
            })
            .unwrap();
        let presented = graph
            .presented_preorder()
            .iter()
            .map(|node| node.id)
            .collect::<Vec<_>>();
        assert_eq!(presented, vec![10, 5, 1]);
        assert!(graph.node(2).is_some(), "the folded pane stays mounted");
        assert!(!graph.is_presented(2));
        assert!(graph.is_presented(1));
        assert!(validate_tree(10, &split_tree(0, false)).is_ok());
        let mut crowded = split_tree(0, false);
        crowded[2].children.push(3);
        crowded.push(button_node(3, "Third"));
        assert!(
            validate_tree(10, &crowded)
                .unwrap_err()
                .contains("must have two panes")
        );
    }

    #[test]
    fn a_dividers_keys_answer_only_while_it_holds_focus() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 10,
                nodes: split_tree(0, false),
            })
            .unwrap();
        assert_eq!(resolve(&mut graph, Some(5), "left"), Some((5, 0)));
        assert_eq!(resolve(&mut graph, Some(5), "enter"), Some((5, 1)));
        // Focus in a pane is inside the split, but not on its divider.
        assert_eq!(resolve(&mut graph, Some(1), "left"), None);
        assert_eq!(resolve(&mut graph, None, "left"), None);
    }

    #[test]
    fn popover_opens_after_its_delay_and_closes_when_the_pointer_leaves() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 10,
                nodes: noted_cell(0, 400),
            })
            .unwrap();
        assert_eq!(graph.hover_targets(1), vec![3]);
        assert!(
            graph.hover_targets(2).is_empty(),
            "the surface is not the anchor"
        );
        let presented = |graph: &MountedGraph| {
            graph
                .presented_preorder()
                .iter()
                .map(|node| node.id)
                .collect::<Vec<_>>()
        };
        assert_eq!(presented(&graph), vec![10, 3, 1]);
        // No handler is installed, so the edge dispatches nothing to Roc.
        assert_eq!(graph.hover_transition(3, true), None);
        assert!(!graph.popover_open(3));
        assert_eq!(graph.popover_delay(3), Some(400));
        assert_eq!(graph.pending_popovers(), vec![3]);
        assert!(graph.popover_elapse(3));
        assert!(graph.popover_open(3));
        assert_eq!(presented(&graph), vec![10, 3, 1, 2]);
        assert_eq!(graph.hover_transition(3, false), None);
        assert!(!graph.popover_open(3));
        // A delay that elapses after the pointer left opens nothing.
        graph.hover_transition(3, true);
        graph.hover_transition(3, false);
        assert!(!graph.popover_elapse(3));
        assert_eq!(
            graph.popover_counters(),
            PopoverCounters {
                opened: 1,
                closed: 1,
                dismissed: 0
            }
        );
    }

    #[test]
    fn popover_focus_opens_at_once_and_holds_it_open_past_the_pointer() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 10,
                nodes: noted_cell(0, 400),
            })
            .unwrap();
        assert_eq!(graph.popover_focus_moved(Some(1)), vec![3]);
        assert!(graph.popover_open(3));
        graph.hover_transition(3, true);
        graph.hover_transition(3, false);
        assert!(graph.popover_open(3), "focus inside keeps it presenting");
        assert_eq!(graph.popover_focus_moved(None), vec![3]);
        assert!(!graph.popover_open(3));
        // Escape closes what presents, and it stays closed.
        graph.popover_focus_moved(Some(1));
        assert_eq!(graph.dismiss_popovers(), vec![3]);
        assert!(!graph.popover_open(3));
        assert_eq!(graph.popover_counters().as_array(), [2, 1, 1]);
    }

    #[test]
    fn popover_presentation_survives_a_rebuild_under_the_pointer() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 10,
                nodes: noted_cell(0, 0),
            })
            .unwrap();
        graph.hover_transition(3, true);
        assert!(graph.popover_open(3), "no delay opens at once");
        graph
            .apply(Patch::Replace {
                old_root: 10,
                root: 110,
                nodes: noted_cell(100, 0),
            })
            .unwrap();
        assert!(graph.popover_open(103));
        assert_eq!(graph.hover_transition(103, true), None, "still hovered");
        graph.hover_transition(103, false);
        assert!(!graph.popover_open(103));
        assert_eq!(graph.popover_counters().as_array(), [1, 1, 0]);
    }

    #[test]
    fn hover_region_reports_edges_on_any_element_and_presents_nothing() {
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 10,
                nodes: vec![
                    text(1, "cell"),
                    popover(3, "", 0, true, vec![1]),
                    column(10, vec![3]),
                ],
            })
            .unwrap();
        assert_eq!(graph.hover_targets(1), vec![3]);
        assert_eq!(
            graph.hover_transition(3, true),
            Some(3 | HOVER_ENTER_EVENT_BIT)
        );
        assert!(!graph.popover_open(3));
        assert_eq!(
            graph.hover_transition(3, false),
            Some(3 | HOVER_EXIT_EVENT_BIT)
        );
        assert_eq!(graph.popover_counters().as_array(), [0, 0, 0]);
    }

    #[test]
    fn popover_anchors_are_validated_and_modal_dialogs_close_background_popovers() {
        assert!(
            validate_tree(3, &[popover(3, "Empty", 0, false, vec![])])
                .unwrap_err()
                .contains("anchor")
        );
        let mut graph = MountedGraph::default();
        let mut nodes = noted_cell(0, 0);
        nodes.push(text(20, "slot"));
        nodes.push(column(30, vec![10, 20]));
        graph.apply(Patch::Mount { root: 30, nodes }).unwrap();
        graph.hover_transition(3, true);
        assert!(graph.popover_open(3));
        graph
            .apply(Patch::Replace {
                old_root: 20,
                root: 40,
                nodes: vec![Node {
                    id: 40,
                    kind: NodeKind::Dialog {
                        label: "Modal".into(),
                        style: Box::default(),
                    },
                    children: vec![],
                }],
            })
            .unwrap();
        assert!(
            !graph.popover_open(3),
            "a dialog retires background popovers"
        );
        assert_eq!(graph.hover_transition(3, true), None);
        assert!(!graph.popover_open(3), "and blocks them while it is up");
    }
}
