//! The lifetime of each accepted task, from issue to delivery or cancellation.
//!
//! A task is issued when the transaction that asked for it commits. It then
//! ends in exactly one of three ways: its completion is delivered to the
//! application, a newer task with the same key from the same component
//! supersedes it, or it is cancelled — explicitly, by its component being
//! removed, or by the session ending. A task that ends without delivery never
//! reaches the application: if it has not started it never runs, and if its
//! completion is already queued that completion is dropped where it is taken,
//! so no cycle is recorded for it.
//!
//! A capability that blocks a worker — a timer's tick, a watch's change, a
//! SQLite statement — arms an [`Interrupt`] for the wait. Ending the task
//! while a wait is armed counts one interrupted wait and wakes it, and it then
//! answers `Canceled` (or `Interrupted`). Counting where the task ends, on
//! the thread that ends it, makes the count follow from the order of turns
//! rather than from when a worker gets to run.

use std::{
    cell::RefCell,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU8, AtomicU64, Ordering},
    },
};

const QUEUED: u8 = 0;
const RUNNING: u8 = 1;
const PUBLISHED: u8 = 2;
const DELIVERED: u8 = 3;
const SUPERSEDED: u8 = 4;
const CANCELLED: u8 = 5;

type Hook = Box<dyn Fn() + Send>;

/// A published completion: an owned value the host releases with `release`
/// unless it is delivered.
pub(crate) struct Owned {
    raw: usize,
    release: fn(usize),
}

impl Owned {
    pub(crate) fn new(raw: usize, release: fn(usize)) -> Self {
        Self { raw, release }
    }

    pub(crate) fn into_raw(mut self) -> usize {
        std::mem::take(&mut self.raw)
    }
}

impl Drop for Owned {
    fn drop(&mut self) {
        if self.raw != 0 {
            (self.release)(self.raw);
        }
    }
}

/// One issued task, shared by the registry, the worker running it, and the
/// envelope carrying its completion.
pub(crate) struct TaskSlot {
    owner: u64,
    key: String,
    state: AtomicU8,
    interrupt: Mutex<Option<Hook>>,
    /// The completion its worker published, held here rather than in the
    /// queue so that ending the task releases it at once, whenever the UI
    /// thread next takes from the queue.
    completion: Mutex<Option<Owned>>,
}

impl TaskSlot {
    fn stopped(&self) -> bool {
        self.state.load(Ordering::Acquire) >= SUPERSEDED
    }
}

impl std::fmt::Debug for TaskSlot {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TaskSlot")
            .field("owner", &self.owner)
            .field("key", &self.key)
            .field("state", &self.state.load(Ordering::Relaxed))
            .finish()
    }
}

/// Indices into the counters, which are reported in this order.
const ISSUED: usize = 0;
const COMPLETED: usize = 1;
const DELIVERED_COUNT: usize = 2;
const SUPERSEDED_COUNT: usize = 3;
const CANCELLED_COUNT: usize = 4;
const INTERRUPTED: usize = 5;

static COUNTERS: [AtomicU64; 6] = [const { AtomicU64::new(0) }; 6];
/// Tasks a worker is running now, from `begin` until `finish` has released
/// or published what they produced.
static RUNNING_NOW: Mutex<Vec<Arc<TaskSlot>>> = Mutex::new(Vec::new());
/// Tasks issued and not yet delivered, superseded, or cancelled.
static LIVE: Mutex<Vec<Arc<TaskSlot>>> = Mutex::new(Vec::new());

thread_local! {
    /// The task a worker thread is running, for the capabilities it calls.
    static CURRENT: RefCell<Option<Arc<TaskSlot>>> = const { RefCell::new(None) };
}

fn bump(index: usize) {
    COUNTERS[index].fetch_add(1, Ordering::Relaxed);
}

fn live() -> std::sync::MutexGuard<'static, Vec<Arc<TaskSlot>>> {
    LIVE.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Issued, completed (a worker published the completion of a task still
/// live), delivered, superseded, cancelled, and capability waits interrupted,
/// in that order.
pub(crate) fn counters() -> [u64; 6] {
    std::array::from_fn(|index| COUNTERS[index].load(Ordering::Relaxed))
}

/// Tasks issued, and tasks that have ended: delivered, superseded, or
/// cancelled. Their difference is the work still outstanding.
pub(crate) fn issued_and_settled() -> (u64, u64) {
    let [issued, _, delivered, superseded, cancelled, _] = counters();
    (issued, delivered + superseded + cancelled)
}

/// Running tasks whose worker only their end or a capability can move on at
/// this instant: those blocked, or about to block, in an interruptible wait,
/// and those that have ended and are still unwinding. A task counted here as
/// ended is no longer counted once its worker has released what it produced.
pub(crate) fn waiting() -> u64 {
    RUNNING_NOW
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .iter()
        .filter(|slot| {
            slot.stopped()
                || slot
                    .interrupt
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .is_some()
        })
        .count() as u64
}

/// Completions delivered to the application.
pub(crate) fn delivered() -> u64 {
    COUNTERS[DELIVERED_COUNT].load(Ordering::Relaxed)
}

/// End a task without delivery. Returns whether this call ended it.
fn stop(slot: &TaskSlot, why: u8) -> bool {
    let mut current = slot.state.load(Ordering::Acquire);
    loop {
        if current >= DELIVERED {
            return false;
        }
        match slot
            .state
            .compare_exchange(current, why, Ordering::AcqRel, Ordering::Acquire)
        {
            Ok(_) => break,
            Err(actual) => current = actual,
        }
    }
    bump(if why == SUPERSEDED {
        SUPERSEDED_COUNT
    } else {
        CANCELLED_COUNT
    });
    drop(take_completion(slot));
    let hook = slot
        .interrupt
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(wake) = hook.as_ref() {
        bump(INTERRUPTED);
        wake();
    }
    true
}

fn take_completion(slot: &TaskSlot) -> Option<Owned> {
    slot.completion
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .take()
}

fn stop_where(why: u8, matches: impl Fn(&TaskSlot) -> bool) {
    let ended: Vec<Arc<TaskSlot>> = {
        let mut live = live();
        let (ended, kept) = std::mem::take(&mut *live)
            .into_iter()
            .partition(|slot| matches(slot));
        *live = kept;
        ended
    };
    for slot in ended {
        stop(&slot, why);
    }
}

/// Issue a task committed by `owner`. A non-empty `key` supersedes the
/// owner's live task with that key.
pub(crate) fn issue(owner: u64, key: String) -> Arc<TaskSlot> {
    if !key.is_empty() {
        stop_where(SUPERSEDED, |slot| slot.owner == owner && slot.key == key);
    }
    let slot = Arc::new(TaskSlot {
        owner,
        key,
        state: AtomicU8::new(QUEUED),
        interrupt: Mutex::new(None),
        completion: Mutex::new(None),
    });
    bump(ISSUED);
    live().push(slot.clone());
    slot
}

/// Cancel `owner`'s live task with `key`, if there is one.
pub(crate) fn cancel(owner: u64, key: &str) {
    if key.is_empty() {
        return;
    }
    stop_where(CANCELLED, |slot| slot.owner == owner && slot.key == key);
}

/// Cancel every live task owned by a component that was removed.
pub(crate) fn unmount(removed: &[u64]) {
    if removed.is_empty() {
        return;
    }
    stop_where(CANCELLED, |slot| {
        slot.owner != 0 && removed.contains(&slot.owner)
    });
}

/// The session ended: wake every blocked wait, and forget the counts.
pub(crate) fn reset() {
    let ended = std::mem::take(&mut *live());
    for slot in ended {
        stop(&slot, CANCELLED);
    }
    for counter in &COUNTERS {
        counter.store(0, Ordering::Relaxed);
    }
}

/// A worker is about to run `slot`. False when it ended while queued, in which
/// case it must not run.
pub(crate) fn begin(slot: &Arc<TaskSlot>) -> bool {
    if slot
        .state
        .compare_exchange(QUEUED, RUNNING, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return false;
    }
    CURRENT.with(|current| *current.borrow_mut() = Some(slot.clone()));
    RUNNING_NOW
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .push(slot.clone());
    true
}

/// A worker finished running `slot` with `completion`. True when it is
/// published; false when the task ended while it ran, and it is released.
pub(crate) fn finish(slot: &TaskSlot, completion: Owned) -> bool {
    CURRENT.with(|current| current.borrow_mut().take());
    *slot
        .completion
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(completion);
    let published = slot
        .state
        .compare_exchange(RUNNING, PUBLISHED, Ordering::AcqRel, Ordering::Acquire)
        .is_ok();
    if published {
        bump(COMPLETED);
    } else {
        // Ended while it ran: whichever of this and `stop` takes the
        // completion second finds nothing.
        drop(take_completion(slot));
    }
    RUNNING_NOW
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .retain(|held| !std::ptr::eq(Arc::as_ptr(held), slot));
    published
}

/// The UI thread took `slot` from the queue: its completion, to deliver, or
/// nothing when the task ended after it was published and was released then.
pub(crate) fn deliver(slot: &Arc<TaskSlot>) -> Option<Owned> {
    slot.state
        .compare_exchange(PUBLISHED, DELIVERED, Ordering::AcqRel, Ordering::Acquire)
        .ok()?;
    bump(DELIVERED_COUNT);
    live().retain(|held| !Arc::ptr_eq(held, slot));
    take_completion(slot)
}

/// A capability wait armed against the running task's end.
///
/// Arm it before blocking, with a hook that wakes the wait; check
/// [`requested`](Interrupt::requested) under the same lock the hook takes, so
/// a wake cannot fall between the check and the wait. Outside a task it is
/// inert.
pub(crate) struct Interrupt {
    slot: Option<Arc<TaskSlot>>,
}

impl Interrupt {
    pub(crate) fn arm(wake: impl Fn() + Send + 'static) -> Self {
        let slot = CURRENT.with(|current| current.borrow().clone());
        if let Some(slot) = &slot {
            *slot
                .interrupt
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(Box::new(wake));
        }
        Self { slot }
    }

    /// Whether the task this wait serves has ended.
    pub(crate) fn requested(&self) -> bool {
        self.slot.as_ref().is_some_and(|slot| slot.stopped())
    }
}

impl Drop for Interrupt {
    fn drop(&mut self) {
        if let Some(slot) = &self.slot {
            slot.interrupt
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .take();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;

    // Other tests issue tasks through the production transaction path, so
    // these use owners nothing else mounts and assert each task's own fate.
    const OWNER: u64 = 0x7a5c_0000_0000;

    fn none() -> Owned {
        Owned::new(0, |_| {})
    }

    fn deliver_some(slot: &Arc<TaskSlot>) -> bool {
        deliver(slot).is_some()
    }

    static RELEASED: AtomicU64 = AtomicU64::new(0);

    fn counted() -> Owned {
        Owned::new(1, |_| {
            RELEASED.fetch_add(1, Ordering::Relaxed);
        })
    }

    #[test]
    fn a_published_completion_is_released_when_its_task_ends_not_when_it_is_taken() {
        let before = RELEASED.load(Ordering::Relaxed);
        let slot = issue(OWNER + 7, "page".into());
        assert!(begin(&slot));
        assert!(finish(&slot, counted()));
        issue(OWNER + 7, "page".into());
        assert_eq!(RELEASED.load(Ordering::Relaxed), before + 1);
        assert!(deliver(&slot).is_none());
        let delivered = issue(OWNER + 8, String::new());
        assert!(begin(&delivered));
        assert!(finish(&delivered, counted()));
        let owned = deliver(&delivered).expect("a live completion is delivered");
        assert_eq!(owned.into_raw(), 1);
        assert_eq!(RELEASED.load(Ordering::Relaxed), before + 1);
    }

    #[test]
    fn a_keyed_task_supersedes_the_last_and_its_completion_is_never_published() {
        let first = issue(OWNER + 1, "query".into());
        assert!(begin(&first));
        let second = issue(OWNER + 1, "query".into());
        assert!(first.stopped());
        assert!(
            !finish(&first, none()),
            "a superseded task must not publish"
        );
        assert!(begin(&second));
        assert!(finish(&second, none()));
        assert!(deliver_some(&second));
        assert!(!live().iter().any(|slot| slot.owner == OWNER + 1));
    }

    #[test]
    fn keys_are_scoped_to_their_component_and_unkeyed_tasks_never_supersede() {
        let mine = issue(OWNER + 2, "page".into());
        let theirs = issue(OWNER + 3, "page".into());
        let plain = issue(OWNER + 2, String::new());
        let also_plain = issue(OWNER + 2, String::new());
        for slot in [&mine, &theirs, &plain, &also_plain] {
            assert!(begin(slot));
            assert!(finish(slot, none()));
            assert!(deliver_some(slot));
        }
    }

    #[test]
    fn a_queued_task_that_ends_never_runs_and_a_published_one_is_dropped() {
        let queued = issue(OWNER + 4, "a".into());
        cancel(OWNER + 4, "a");
        assert!(!begin(&queued));
        let published = issue(OWNER + 4, "b".into());
        assert!(begin(&published));
        assert!(finish(&published, none()));
        unmount(&[OWNER + 4]);
        assert!(!deliver_some(&published));
        assert!(!live().iter().any(|slot| slot.owner == OWNER + 4));
    }

    #[test]
    fn a_delivered_task_cannot_be_cancelled_afterwards() {
        let slot = issue(OWNER + 5, "done".into());
        assert!(begin(&slot));
        assert!(finish(&slot, none()));
        assert!(deliver_some(&slot));
        assert!(!stop(&slot, CANCELLED));
    }

    #[test]
    fn ending_a_task_wakes_its_armed_wait() {
        let slot = issue(OWNER + 6, "wait".into());
        assert!(begin(&slot));
        let woke = Arc::new(AtomicBool::new(false));
        let interrupt = {
            let woke = woke.clone();
            Interrupt::arm(move || woke.store(true, Ordering::Release))
        };
        assert!(!interrupt.requested());
        cancel(OWNER + 6, "wait");
        assert!(woke.load(Ordering::Acquire));
        assert!(interrupt.requested());
        drop(interrupt);
        assert!(slot.interrupt.lock().unwrap().is_none());
        assert!(!finish(&slot, none()));
    }

    #[test]
    fn an_interrupt_outside_a_task_is_inert() {
        let interrupt = Interrupt::arm(|| panic!("no task to end"));
        assert!(!interrupt.requested());
    }
}
