use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    sync::{
        Arc, Condvar, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

const MAX_ACTIVE: usize = 256;
struct Timer {
    state: Mutex<TimerState>,
    wake: Condvar,
}
struct TimerState {
    canceled: bool,
    waiting: bool,
    next: Instant,
    interval: Duration,
}
struct Store {
    next: u64,
    timers: HashMap<u64, Arc<Timer>>,
    allocations: HashMap<usize, u64>,
}
static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static FIRED: AtomicU64 = AtomicU64::new(0);

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            timers: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}
fn lookup(handle: *mut u64) -> Option<Arc<Timer>> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.timers.get(&id).cloned()
}
pub fn start(interval_ms: u64) -> *mut u64 {
    assert!((1..=60_000).contains(&interval_ms));
    let mut guard = store().lock().expect("timer store poisoned");
    assert!(
        guard.timers.len() < MAX_ACTIVE,
        "active timer limit exceeded"
    );
    let id = guard.next;
    guard.next = guard.next.checked_add(1).expect("timer ids exhausted");
    let interval = Duration::from_millis(interval_ms);
    guard.timers.insert(
        id,
        Arc::new(Timer {
            state: Mutex::new(TimerState {
                canceled: false,
                waiting: false,
                next: Instant::now() + interval,
                interval,
            }),
            wake: Condvar::new(),
        }),
    );
    let handle = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            core::mem::align_of::<u64>(),
            false,
            roc_host(),
        ) as *mut u64
    };
    unsafe { handle.write(id) };
    let allocation = unsafe { (handle as *mut u8).sub(core::mem::size_of::<isize>()) } as usize;
    crate::register_resource_allocation(
        crate::resource_domain::TIMERS,
        &mut guard.allocations,
        allocation,
        id,
    );
    handle
}
pub fn next(handle: *mut u64) -> bool {
    let timer = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some(timer) = timer else { return false };
    // Declared before the state guard so it is released after it: the wake
    // takes the state lock while holding the task's.
    let interrupt = {
        let timer = timer.clone();
        crate::tasks::Interrupt::arm(move || {
            let _held = timer.state.lock();
            timer.wake.notify_all();
        })
    };
    let mut state = timer.state.lock().expect("timer state poisoned");
    if state.canceled || state.waiting {
        return false;
    }
    state.waiting = true;
    while !state.canceled && !interrupt.requested() {
        let now = Instant::now();
        if now >= state.next {
            break;
        }
        let duration = state.next.saturating_duration_since(now);
        let (next, _) = timer
            .wake
            .wait_timeout(state, duration)
            .expect("timer state poisoned");
        state = next;
    }
    state.waiting = false;
    if state.canceled {
        false
    } else if interrupt.requested() {
        // The task waiting ended; the timer itself runs on for the next one.
        false
    } else {
        state.next = Instant::now() + state.interval;
        FIRED.fetch_add(1, Ordering::Relaxed);
        true
    }
}
pub fn cancel(handle: *mut u64) -> bool {
    let timer = lookup(handle);
    let Some(timer) = timer else {
        unsafe { decref_box(handle as RocBox, roc_host()) };
        return false;
    };
    let mut state = timer.state.lock().expect("timer state poisoned");
    let changed = !state.canceled;
    state.canceled = true;
    timer.wake.notify_all();
    drop(state);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    changed
}
pub fn route_dealloc(allocation_base: *mut std::ffi::c_void) {
    let timer = {
        let mut guard = store().lock().expect("timer store poisoned");
        let id =
            crate::remove_resource_allocation(&mut guard.allocations, allocation_base as usize);
        id.and_then(|id| guard.timers.remove(&id))
    };
    if let Some(timer) = timer {
        let mut state = timer.state.lock().expect("timer state poisoned");
        state.canceled = true;
        timer.wake.notify_all();
    }
}
pub fn active_count() -> usize {
    store()
        .lock()
        .expect("timer store poisoned")
        .timers
        .values()
        .filter(|timer| !timer.state.lock().expect("timer state poisoned").canceled)
        .count()
}

pub fn fired_count() -> u64 {
    FIRED.load(Ordering::Relaxed)
}
