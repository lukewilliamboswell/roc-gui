use rusqlite::{Connection, OpenFlags, params};
use sha2::{Digest, Sha256};
use std::{
    fs::{File, OpenOptions},
    io::Read,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering},
        mpsc::{Receiver, RecvTimeoutError, SyncSender, sync_channel},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub const SCHEMA_VERSION: u32 = 11;
static CLOCK_ORIGIN: OnceLock<Instant> = OnceLock::new();
// This process-wide flag is the hot-path gate. The recorder mutex and its
// queue are only consulted after this overwhelmingly predictable branch.
static ENABLED: AtomicBool = AtomicBool::new(false);
static DETAIL: AtomicU8 = AtomicU8::new(0);
static ROC_ALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ROC_ALLOC_REQUESTED_BYTES: AtomicU64 = AtomicU64::new(0);
static ROC_DEALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ROC_REALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ROC_REALLOC_REQUESTED_BYTES: AtomicU64 = AtomicU64::new(0);
static GPUI_FRAME_ORDINAL: AtomicU64 = AtomicU64::new(0);
pub const ROC_WORK_KINDS: usize = 5;

/// Numeric work reported by the Roc component runtime at the owning operation.
/// The order is the `component_work!` ABI; changing it requires a schema change.
pub const COMPONENT_WORK_NAMES: [&str; 7] = [
    "rendered",
    "compared",
    "skipped",
    "mounted",
    "retired",
    "registry_visits",
    "ancestor_invalidations",
];

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ComponentWork(pub [u64; COMPONENT_WORK_NAMES.len()]);

#[derive(Default)]
struct ComponentWorkOwner {
    totals: ComponentWork,
    pending: Option<ComponentWork>,
    committed: Option<ComponentWork>,
    commits: u64,
    cycle_start: ComponentWork,
    cycle_start_commits: u64,
}

thread_local! {
    static COMPONENT_WORK: std::cell::RefCell<ComponentWorkOwner> = Default::default();
}

/// Start one production action turn, independently of whether capture is enabled.
pub fn begin_component_work() {
    COMPONENT_WORK.with(|owner| {
        let mut owner = owner.borrow_mut();
        assert!(owner.pending.is_none(), "nested component work turn");
        owner.pending = Some(ComponentWork::default());
    });
}

pub fn note_component_work(kind: u8, amount: u64) {
    let kind = usize::from(kind);
    assert!(
        kind < COMPONENT_WORK_NAMES.len(),
        "unknown component work kind"
    );
    COMPONENT_WORK.with(|owner| {
        let mut owner = owner.borrow_mut();
        let pending = owner
            .pending
            .as_mut()
            .expect("component work outside a turn");
        pending.0[kind] = pending.0[kind]
            .checked_add(amount)
            .expect("component work overflow");
        owner.totals.0[kind] = owner.totals.0[kind]
            .checked_add(amount)
            .expect("component work overflow");
    });
}

/// Publish only after the mounted graph accepts the same action transaction.
pub fn commit_component_work() {
    COMPONENT_WORK.with(|owner| {
        let mut owner = owner.borrow_mut();
        owner.committed = owner.pending.take();
        if owner.committed.is_some() {
            owner.commits = owner
                .commits
                .checked_add(1)
                .expect("component turn overflow");
        }
    });
}

pub fn reject_component_work() {
    COMPONENT_WORK.with(|owner| owner.borrow_mut().pending = None);
}

pub fn clear_component_work() {
    COMPONENT_WORK.with(|owner| *owner.borrow_mut() = ComponentWorkOwner::default());
}

/// None means no production turn has supplied a committed observation.
pub fn last_component_work() -> Option<ComponentWork> {
    COMPONENT_WORK.with(|owner| owner.borrow().committed)
}

#[cfg(test)]
fn total_component_work() -> ComponentWork {
    COMPONENT_WORK.with(|owner| owner.borrow().totals)
}

fn reset_component_cycle() {
    COMPONENT_WORK.with(|owner| {
        let mut owner = owner.borrow_mut();
        owner.cycle_start = owner.totals;
        owner.cycle_start_commits = owner.commits;
    });
}

/// A measured cycle may contain several turns, such as a complete drag gesture.
/// Subtract owner totals instead of attributing only its final turn to the cycle.
pub fn component_cycle_work() -> Option<ComponentWork> {
    COMPONENT_WORK.with(|owner| {
        let owner = owner.borrow();
        (owner.commits != owner.cycle_start_commits).then(|| {
            ComponentWork(std::array::from_fn(|kind| {
                owner.totals.0[kind] - owner.cycle_start.0[kind]
            }))
        })
    })
}

#[derive(Clone, Copy, Debug, Default)]
pub struct RocWork {
    pub occurred: bool,
    pub duration_ns: u64,
    pub alloc_calls: u64,
    pub allocated_bytes: u64,
    pub dealloc_calls: u64,
    pub realloc_calls: u64,
    pub reallocated_bytes: u64,
}

#[derive(Default)]
struct ActiveRocWork {
    kind: Option<usize>,
    started: Option<Instant>,
    totals: [RocWork; ROC_WORK_KINDS],
    valid: bool,
}

thread_local! {
    static ROC_WORK: std::cell::RefCell<ActiveRocWork> = Default::default();
}

pub const ROC_WORK_NAMES: [&str; ROC_WORK_KINDS] = [
    "routing",
    "application_update",
    "application_render",
    "platform_lowering",
    "component_comparison",
];
const TRANSACTION_EVENTS: usize = 1024;
const TRANSACTION_COALESCE: Duration = Duration::from_millis(2);
const TERMINAL_RESERVE_MAX_BYTES: u64 = 1024 * 1024;
const MAX_DIAGNOSTIC_BYTES: usize = 2048;

pub fn now_ns() -> u64 {
    CLOCK_ORIGIN
        .get_or_init(Instant::now)
        .elapsed()
        .as_nanos()
        .try_into()
        .unwrap_or(u64::MAX)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Detail {
    Summary,
    Full,
}

impl Detail {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "summary" => Some(Self::Summary),
            "full" => Some(Self::Full),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Summary => "summary",
            Self::Full => "full",
        }
    }

    fn code(self) -> u8 {
        match self {
            Self::Summary => 0,
            Self::Full => 1,
        }
    }

    fn records_cycle(self, measurement_phase: &str) -> bool {
        self == Self::Full || measurement_phase != "setup"
    }
}

#[derive(Clone, Debug)]
pub struct Config {
    pub path: PathBuf,
    pub detail: Detail,
    pub buffer_mib: usize,
    pub max_mib: u64,
    pub backend: &'static str,
    pub app_name: String,
    pub spec_name: Option<String>,
    pub spec_hash: Option<String>,
    pub benchmark: Option<(u32, u32, u32, u64, u64, u64)>,
    pub job_count: usize,
    pub patch_expected: bool,
}

#[derive(Clone, Debug)]
pub struct Cycle {
    pub run_id: i64,
    pub ordinal: u64,
    pub step_ordinal: Option<usize>,
    pub measurement_phase: &'static str,
    pub trigger: &'static str,
    pub patch_kind: &'static str,
    pub duration_ns: u64,
    pub roc_callback_ns: u64,
    pub validate_ns: u64,
    pub apply_ns: u64,
    pub graph_apply_ns: u64,
    pub gpui_apply_ns: Option<u64>,
    pub staged_nodes: u64,
    pub removed_nodes: u64,
    pub live_nodes: u64,
    pub parent_nodes_scanned: u64,
    pub retained_nodes: u64,
    pub validation_visits: u64,
    pub roc_work: [RocWork; ROC_WORK_KINDS],
    pub roc_work_valid: bool,
    pub component_work: Option<ComponentWork>,
}

pub fn reset_roc_work() {
    reset_component_cycle();
    if !active() {
        return;
    }
    ROC_WORK.with(|work| {
        *work.borrow_mut() = ActiveRocWork {
            valid: true,
            ..Default::default()
        }
    });
}

pub fn start_roc_work(kind: u8) {
    if !active() {
        return;
    }
    let kind = kind as usize;
    ROC_WORK.with(|work| {
        let mut work = work.borrow_mut();
        if kind >= ROC_WORK_KINDS || work.kind.is_some() {
            work.valid = false;
            work.kind = None;
            work.started = None;
            return;
        }
        work.totals[kind].occurred = true;
        work.kind = Some(kind);
        work.started = Some(Instant::now());
    });
}

pub fn end_roc_work(kind: u8) {
    if !active() {
        return;
    }
    ROC_WORK.with(|work| {
        let mut work = work.borrow_mut();
        if kind as usize >= ROC_WORK_KINDS || work.kind != Some(kind as usize) {
            work.valid = false;
            work.kind = None;
            work.started = None;
            return;
        }
        let elapsed = work.started.take().map(now_elapsed_ns).unwrap_or(0);
        work.totals[kind as usize].duration_ns = work.totals[kind as usize]
            .duration_ns
            .saturating_add(elapsed);
        work.kind = None;
    });
}

pub fn take_roc_work() -> ([RocWork; ROC_WORK_KINDS], bool) {
    if !active() {
        return ([RocWork::default(); ROC_WORK_KINDS], false);
    }
    ROC_WORK.with(|work| {
        let mut work = work.borrow_mut();
        if work.kind.is_some() {
            work.valid = false;
        }
        (std::mem::take(&mut work.totals), work.valid)
    })
}

fn now_elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}

fn attribute_alloc(update: impl FnOnce(&mut RocWork)) {
    ROC_WORK.with(|work| {
        let mut work = work.borrow_mut();
        if let Some(kind) = work.kind {
            update(&mut work.totals[kind]);
        }
    });
}

#[derive(Clone, Debug)]
pub struct StepResult {
    pub run_id: i64,
    pub ordinal: usize,
    pub source_line: usize,
    pub kind: &'static str,
    pub role: &'static str,
    pub status: &'static str,
    pub duration_ns: Option<u64>,
    pub expected_count: Option<u64>,
    pub observed_count: Option<u64>,
    pub audio_counters: Option<([u64; 9], [u64; 9])>,
    pub clipboard_counters: Option<([u64; 4], [u64; 4])>,
    pub sqlite_counters: Option<([u64; 3], [u64; 3])>,
    pub http_counters: Option<([u64; 4], [u64; 4])>,
    pub tcp_counters: Option<([u64; 5], [u64; 5])>,
    pub component_work: Option<(
        [Option<u64>; COMPONENT_WORK_NAMES.len()],
        Option<ComponentWork>,
    )>,
    pub expected_patch_kind: Option<String>,
    pub observed_patch_kind: Option<&'static str>,
    pub expected_staged_nodes: Option<u64>,
    pub observed_staged_nodes: Option<u64>,
    pub expected_removed_nodes: Option<u64>,
    pub observed_removed_nodes: Option<u64>,
    pub diagnostic: Option<String>,
}

enum Event {
    RunStart {
        id: i64,
        phase: &'static str,
        sample: Option<u32>,
        iteration: u32,
        started_ns: u64,
        resources: ResourceSnapshot,
    },
    RunEnd {
        id: i64,
        outcome: &'static str,
        ended_ns: u64,
        diagnostic: Option<String>,
        resources: ResourceSnapshot,
    },
    Step(Box<StepResult>),
    Cycle(Box<Cycle>),
    GpuiFrame {
        ordinal: u64,
        layout_request_ns: u64,
        prepaint_ns: u64,
        paint_ns: u64,
    },
    VirtualListFrame {
        list_id: u64,
        visible_items: u64,
        materialized_entities: u64,
        recycled_entities: u64,
        live_entities: u64,
    },
    Finish {
        application_outcome: &'static str,
        drain_started: Instant,
    },
}

struct Recorder {
    sender: SyncSender<Event>,
    omitted: Arc<AtomicU64>,
    pending: Arc<AtomicU64>,
    high_water: Arc<AtomicU64>,
    join: thread::JoinHandle<Result<(), String>>,
}

static RECORDER: Mutex<Option<Recorder>> = Mutex::new(None);

#[derive(Clone, Copy, Debug, Default)]
struct ResourceSnapshot {
    cpu_user_ns: u64,
    cpu_system_ns: u64,
    max_rss_bytes: u64,
    current_rss_bytes: Option<u64>,
    roc_alloc_calls: u64,
    roc_alloc_requested_bytes: u64,
    roc_dealloc_calls: u64,
    roc_realloc_calls: u64,
    roc_realloc_requested_bytes: u64,
}

/// Record Roc allocation activity with one predictable disabled-path branch.
/// These counters intentionally measure requested bytes, not retained/live bytes.
pub fn note_roc_alloc(requested_bytes: usize) {
    if ENABLED.load(Ordering::Relaxed) {
        ROC_ALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        ROC_ALLOC_REQUESTED_BYTES.fetch_add(requested_bytes as u64, Ordering::Relaxed);
        attribute_alloc(|work| {
            work.alloc_calls += 1;
            work.allocated_bytes = work.allocated_bytes.saturating_add(requested_bytes as u64);
        });
    }
}

pub fn note_roc_dealloc() {
    if ENABLED.load(Ordering::Relaxed) {
        ROC_DEALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        attribute_alloc(|work| work.dealloc_calls += 1);
    }
}

pub fn note_roc_realloc(requested_bytes: usize) {
    if ENABLED.load(Ordering::Relaxed) {
        ROC_REALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        ROC_REALLOC_REQUESTED_BYTES.fetch_add(requested_bytes as u64, Ordering::Relaxed);
        attribute_alloc(|work| {
            work.realloc_calls += 1;
            work.reallocated_bytes = work
                .reallocated_bytes
                .saturating_add(requested_bytes as u64);
        });
    }
}

fn resource_snapshot() -> ResourceSnapshot {
    let (cpu_user_ns, cpu_system_ns, max_rss_bytes) = process_resources();
    ResourceSnapshot {
        cpu_user_ns,
        cpu_system_ns,
        max_rss_bytes,
        current_rss_bytes: current_rss_bytes(),
        roc_alloc_calls: ROC_ALLOC_CALLS.load(Ordering::Relaxed),
        roc_alloc_requested_bytes: ROC_ALLOC_REQUESTED_BYTES.load(Ordering::Relaxed),
        roc_dealloc_calls: ROC_DEALLOC_CALLS.load(Ordering::Relaxed),
        roc_realloc_calls: ROC_REALLOC_CALLS.load(Ordering::Relaxed),
        roc_realloc_requested_bytes: ROC_REALLOC_REQUESTED_BYTES.load(Ordering::Relaxed),
    }
}

#[cfg(unix)]
fn page_size_bytes() -> i64 {
    unsafe { libc::sysconf(libc::_SC_PAGESIZE) as i64 }
}

#[cfg(windows)]
fn page_size_bytes() -> i64 {
    use windows_sys::Win32::System::SystemInformation::{GetSystemInfo, SYSTEM_INFO};
    let mut info = unsafe { std::mem::zeroed::<SYSTEM_INFO>() };
    unsafe { GetSystemInfo(&mut info) };
    info.dwPageSize as i64
}

#[cfg(unix)]
fn current_rss_bytes() -> Option<u64> {
    let statm = std::fs::read_to_string("/proc/self/statm").ok()?;
    let resident_pages = statm.split_whitespace().nth(1)?.parse::<u64>().ok()?;
    let page_size = page_size_bytes();
    (page_size > 0).then(|| resident_pages.saturating_mul(page_size as u64))
}

#[cfg(windows)]
fn memory_counters() -> Option<windows_sys::Win32::System::ProcessStatus::PROCESS_MEMORY_COUNTERS> {
    use windows_sys::Win32::System::{
        ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS},
        Threading::GetCurrentProcess,
    };
    let mut counters = unsafe { std::mem::zeroed::<PROCESS_MEMORY_COUNTERS>() };
    counters.cb = size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
    (unsafe { K32GetProcessMemoryInfo(GetCurrentProcess(), &mut counters, counters.cb) } != 0)
        .then_some(counters)
}

#[cfg(windows)]
fn current_rss_bytes() -> Option<u64> {
    memory_counters().map(|counters| counters.WorkingSetSize as u64)
}

#[cfg(windows)]
fn process_resources() -> (u64, u64, u64) {
    use windows_sys::Win32::{
        Foundation::FILETIME,
        System::Threading::{GetCurrentProcess, GetProcessTimes},
    };
    let mut times = unsafe { std::mem::zeroed::<[FILETIME; 4]>() };
    let [creation, exit, kernel, user] = &mut times;
    if unsafe { GetProcessTimes(GetCurrentProcess(), creation, exit, kernel, user) } == 0 {
        return (0, 0, 0);
    }
    // FILETIME durations count 100-nanosecond intervals.
    let filetime_ns = |value: &FILETIME| {
        ((value.dwHighDateTime as u64) << 32 | value.dwLowDateTime as u64).saturating_mul(100)
    };
    (
        filetime_ns(user),
        filetime_ns(kernel),
        memory_counters().map_or(0, |counters| counters.PeakWorkingSetSize as u64),
    )
}

#[cfg(unix)]
fn process_resources() -> (u64, u64, u64) {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::zeroed();
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) } != 0 {
        return (0, 0, 0);
    }
    let usage = unsafe { usage.assume_init() };
    let timeval_ns = |value: libc::timeval| {
        (value.tv_sec.max(0) as u64)
            .saturating_mul(1_000_000_000)
            .saturating_add((value.tv_usec.max(0) as u64).saturating_mul(1_000))
    };
    #[cfg(target_os = "linux")]
    let max_rss_bytes = (usage.ru_maxrss.max(0) as u64).saturating_mul(1024);
    // Darwin reports ru_maxrss in bytes.
    #[cfg(target_os = "macos")]
    let max_rss_bytes = usage.ru_maxrss.max(0) as u64;
    (
        timeval_ns(usage.ru_utime),
        timeval_ns(usage.ru_stime),
        max_rss_bytes,
    )
}

pub fn default_path(app_name: &str) -> PathBuf {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_secs();
    let safe_name: String = app_name
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_') {
                character
            } else {
                '-'
            }
        })
        .collect();
    PathBuf::from(format!("{seconds}-{safe_name}.rgstats"))
}

pub fn stable_hash(bytes: &[u8]) -> String {
    format!("sha256:{:x}", Sha256::digest(bytes))
}

fn executable_hash() -> String {
    let Ok(path) = std::env::current_exe() else {
        return "unavailable".into();
    };
    let Ok(mut file) = File::open(path) else {
        return "unavailable".into();
    };
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let Ok(count) = file.read(&mut buffer) else {
            return "unavailable".into();
        };
        if count == 0 {
            return format!("sha256:{:x}", hash.finalize());
        }
        hash.update(&buffer[..count]);
    }
}

fn cpu_model() -> String {
    let Ok(contents) = std::fs::read_to_string("/proc/cpuinfo") else {
        return "unavailable".into();
    };
    contents
        .lines()
        .find_map(|line| line.strip_prefix("model name\t:").map(str::trim))
        .filter(|value| !value.is_empty())
        .map(|value| value.chars().take(256).collect())
        .unwrap_or_else(|| "unavailable".into())
}

fn kernel_release() -> String {
    std::fs::read_to_string("/proc/sys/kernel/osrelease")
        .ok()
        .map(|value| value.trim().chars().take(128).collect::<String>())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "unavailable".into())
}

pub fn start(config: Config) -> Result<(), String> {
    if config.buffer_mib == 0 || config.buffer_mib > 4096 {
        return Err("stats buffer must be between 1 and 4096 MiB".into());
    }
    if config.max_mib == 0 {
        return Err("stats maximum database size must be positive".into());
    }
    DETAIL.store(config.detail.code(), Ordering::Relaxed);
    GPUI_FRAME_ORDINAL.store(0, Ordering::Relaxed);
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&config.path)
        .map_err(|error| {
            format!(
                "cannot create {} without overwriting: {error}",
                config.path.display()
            )
        })?;

    let capacity = config
        .buffer_mib
        .saturating_mul(1024 * 1024)
        // Events own at most one bounded diagnostic string. Charging every
        // slot for that worst case makes buffer_mib a conservative bound on
        // queued event payload instead of merely counting enum headers.
        .checked_div((std::mem::size_of::<Event>() + MAX_DIAGNOSTIC_BYTES).max(1))
        .unwrap_or(0)
        .max(16);
    let (sender, receiver) = sync_channel(capacity);
    let (ready_sender, ready_receiver) = sync_channel(1);
    let omitted = Arc::new(AtomicU64::new(0));
    let writer_omitted = omitted.clone();
    let pending = Arc::new(AtomicU64::new(0));
    let writer_pending = pending.clone();
    let high_water = Arc::new(AtomicU64::new(0));
    let writer_high_water = high_water.clone();
    let join = thread::Builder::new()
        .name("roc-gui-stats".into())
        .spawn(move || {
            writer(
                config,
                receiver,
                writer_omitted,
                writer_pending,
                writer_high_water,
                ready_sender,
            )
        })
        .map_err(|error| format!("cannot start stats writer: {error}"))?;
    match ready_receiver.recv() {
        Ok(Ok(())) => {
            {
                let mut slot = RECORDER.lock().unwrap_or_else(|error| error.into_inner());
                assert!(slot.is_none(), "stats recorder started twice");
                *slot = Some(Recorder {
                    sender,
                    omitted,
                    pending,
                    high_water,
                    join,
                });
            }
            ENABLED.store(true, Ordering::Release);
            Ok(())
        }
        Ok(Err(message)) => {
            let _ = join.join();
            Err(message)
        }
        Err(_) => {
            let _ = join.join();
            Err("stats writer stopped during startup".into())
        }
    }
}

fn submit(event: Event, lossless: bool) {
    let slot = RECORDER.lock().unwrap_or_else(|error| error.into_inner());
    if let Some(recorder) = slot.as_ref() {
        let pending = recorder.pending.fetch_add(1, Ordering::Relaxed) + 1;
        recorder.high_water.fetch_max(pending, Ordering::Relaxed);
        let (admitted, disconnected) = if lossless {
            match recorder.sender.send(event) {
                Ok(()) => (true, false),
                Err(_) => (false, true),
            }
        } else {
            match recorder.sender.try_send(event) {
                Ok(()) => (true, false),
                Err(std::sync::mpsc::TrySendError::Full(_)) => (false, false),
                Err(std::sync::mpsc::TrySendError::Disconnected(_)) => (false, true),
            }
        };
        if !admitted {
            recorder.pending.fetch_sub(1, Ordering::Relaxed);
            recorder.omitted.fetch_add(1, Ordering::Relaxed);
        }
        if disconnected {
            // The application remains usable if observability fails. Future
            // hot paths immediately return at the global branch; finish still
            // joins the writer and reports the failure.
            ENABLED.store(false, Ordering::Release);
        }
    }
}

pub fn active() -> bool {
    ENABLED.load(Ordering::Relaxed)
}

pub fn run_start(
    id: i64,
    phase: &'static str,
    sample: Option<u32>,
    iteration: u32,
    started_ns: u64,
) {
    submit(
        Event::RunStart {
            id,
            phase,
            sample,
            iteration,
            started_ns,
            resources: resource_snapshot(),
        },
        true,
    );
}

pub fn run_end(id: i64, outcome: &'static str, ended_ns: u64, diagnostic: Option<String>) {
    submit(
        Event::RunEnd {
            id,
            outcome,
            ended_ns,
            diagnostic: diagnostic.map(bounded_diagnostic),
            resources: resource_snapshot(),
        },
        true,
    );
}

pub fn step(result: StepResult) {
    let mut result = result;
    result.diagnostic = result.diagnostic.map(bounded_diagnostic);
    submit(Event::Step(Box::new(result)), true);
}

fn bounded_diagnostic(mut value: String) -> String {
    if value.len() > MAX_DIAGNOSTIC_BYTES {
        let mut end = MAX_DIAGNOSTIC_BYTES;
        while !value.is_char_boundary(end) {
            end -= 1;
        }
        value.truncate(end);
    }
    value.shrink_to_fit();
    value
}

pub fn cycle(cycle: Cycle) {
    // Setup cycles are useful for diagnosing full execution but are outside
    // the operation selected for measurement. Summary keeps the measured and
    // interactive paths plus all semantic result rows.
    let detail = if DETAIL.load(Ordering::Relaxed) == Detail::Full.code() {
        Detail::Full
    } else {
        Detail::Summary
    };
    if !detail.records_cycle(cycle.measurement_phase) {
        return;
    }
    submit(Event::Cycle(Box::new(cycle)), false);
}

/// Record one GPUI frame's host-owned element spans.
///
/// Called by [`crate::frame_spans::FrameSpans`], the element that performs this
/// work: each duration is the time that element's own `request_layout`,
/// `prepaint`, or `paint` call spent on the application subtree. Taffy's layout
/// solve and window presentation are performed by GPUI outside any host-owned
/// element and are reported as unavailable rather than derived from these.
pub fn gpui_frame(layout_request_ns: u64, prepaint_ns: u64, paint_ns: u64) {
    if !active() {
        return;
    }
    let ordinal = GPUI_FRAME_ORDINAL.fetch_add(1, Ordering::Relaxed);
    submit(
        Event::GpuiFrame {
            ordinal,
            layout_request_ns,
            prepaint_ns,
            paint_ns,
        },
        false,
    );
}

pub fn virtual_list_frame(
    list_id: u64,
    visible_items: u64,
    materialized_entities: u64,
    recycled_entities: u64,
    live_entities: u64,
) {
    submit(
        Event::VirtualListFrame {
            list_id,
            visible_items,
            materialized_entities,
            recycled_entities,
            live_entities,
        },
        false,
    );
}

pub fn finish(application_outcome: &'static str) -> Result<(), String> {
    let recorder = {
        let mut slot = RECORDER.lock().unwrap_or_else(|error| error.into_inner());
        let Some(recorder) = slot.take() else {
            return Ok(());
        };
        ENABLED.store(false, Ordering::Release);
        recorder
    };
    let pending = recorder.pending.fetch_add(1, Ordering::Relaxed) + 1;
    recorder.high_water.fetch_max(pending, Ordering::Relaxed);
    if recorder
        .sender
        .send(Event::Finish {
            application_outcome,
            drain_started: Instant::now(),
        })
        .is_err()
    {
        recorder.pending.fetch_sub(1, Ordering::Relaxed);
        return Err("stats writer stopped before finalization".to_string());
    }
    drop(recorder.sender);
    recorder
        .join
        .join()
        .map_err(|_| "stats writer panicked".to_string())?
}

fn writer(
    config: Config,
    receiver: Receiver<Event>,
    omitted: Arc<AtomicU64>,
    pending: Arc<AtomicU64>,
    high_water: Arc<AtomicU64>,
    ready: SyncSender<Result<(), String>>,
) -> Result<(), String> {
    let result = open_and_initialize(&config);
    let mut connection = match result {
        Ok(connection) => {
            let _ = ready.send(Ok(()));
            connection
        }
        Err(message) => {
            let _ = ready.send(Err(message.clone()));
            return Err(message);
        }
    };
    let mut rows_written = 0u64;
    let mut transactions = 0u64;
    let mut output_limited = false;
    let max_bytes = config.max_mib.saturating_mul(1024 * 1024);
    let terminal_reserve = (max_bytes / 2).min(TERMINAL_RESERVE_MAX_BYTES);
    let admission_limit = max_bytes.saturating_sub(terminal_reserve);

    while let Ok(first) = receiver.recv() {
        // Coalesce a short burst before opening SQLite's transaction. Without
        // this window the writer commonly commits one transaction per event,
        // simply because it wins the race back to recv().
        let mut events = Vec::with_capacity(TRANSACTION_EVENTS.min(256));
        events.push(first);
        let deadline = Instant::now() + TRANSACTION_COALESCE;
        while events.len() < TRANSACTION_EVENTS {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                break;
            }
            match receiver.recv_timeout(remaining) {
                Ok(event) => {
                    let finishing = matches!(event, Event::Finish { .. });
                    events.push(event);
                    if finishing {
                        break;
                    }
                }
                Err(RecvTimeoutError::Timeout) | Err(RecvTimeoutError::Disconnected) => break,
            }
        }
        pending.fetch_sub(events.len() as u64, Ordering::Relaxed);
        let transaction = connection
            .transaction()
            .map_err(|error| format!("stats transaction failed: {error}"))?;
        let mut finish = None;
        for event in events {
            if let Event::Finish { .. } = event {
                finish = Some(event);
                break;
            }
            // Runs, steps, and finalization are correctness/control evidence.
            // The terminal reserve is specifically held for them; only the
            // high-volume cycle stream is sacrificed at the admission limit.
            if output_limited
                && matches!(
                    event,
                    Event::Cycle(_) | Event::VirtualListFrame { .. } | Event::GpuiFrame { .. }
                )
            {
                omitted.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            write_event(&transaction, event)?;
            rows_written += 1;
        }
        transaction
            .commit()
            .map_err(|error| format!("stats commit failed: {error}"))?;
        transactions += 1;
        let output_bytes = database_bytes(&connection, &config.path).unwrap_or(0);
        if output_bytes >= admission_limit {
            output_limited = true;
        }
        if let Some(Event::Finish {
            application_outcome,
            drain_started,
        }) = finish
        {
            finalize(
                &connection,
                &config.path,
                application_outcome,
                drain_started.elapsed(),
                omitted.load(Ordering::Relaxed),
                high_water.load(Ordering::Relaxed),
                rows_written,
                transactions,
                output_limited,
            )?;
            return Ok(());
        }
    }
    Err("stats recorder ended without a finalization event".into())
}

fn open_and_initialize(config: &Config) -> Result<Connection, String> {
    let connection = Connection::open_with_flags(
        &config.path,
        OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|error| format!("cannot open {}: {error}", config.path.display()))?;
    connection
        .busy_timeout(Duration::from_secs(1))
        .map_err(|error| format!("cannot configure SQLite timeout: {error}"))?;
    connection
        .execute_batch(SCHEMA)
        .map_err(|error| format!("cannot initialize stats schema: {error}"))?;
    let benchmark = config.benchmark.unwrap_or((0, 0, 0, 0, 0, 0));
    let logical_cpus = std::thread::available_parallelism()
        .map(|value| value.get().to_string())
        .unwrap_or_else(|_| "unavailable".into());
    let page_size = page_size_bytes();
    let metadata = [
        ("schema_version", SCHEMA_VERSION.to_string()),
        ("clean_shutdown", "0".into()),
        ("final_state", "recording".into()),
        ("requested_detail", config.detail.as_str().into()),
        ("effective_detail", config.detail.as_str().into()),
        ("backend", config.backend.into()),
        ("app_name", config.app_name.clone()),
        ("spec_name", config.spec_name.clone().unwrap_or_default()),
        ("spec_hash", config.spec_hash.clone().unwrap_or_default()),
        ("benchmark_warmups", benchmark.0.to_string()),
        ("benchmark_samples", benchmark.1.to_string()),
        ("benchmark_iterations", benchmark.2.to_string()),
        ("benchmark_scale", benchmark.3.to_string()),
        ("benchmark_initial_size", benchmark.4.to_string()),
        ("benchmark_change_size", benchmark.5.to_string()),
        ("host_os", std::env::consts::OS.into()),
        ("host_arch", std::env::consts::ARCH.into()),
        ("host_commit", option_env!("ROC_GUI_HOST_COMMIT").unwrap_or("unavailable").into()),
        ("host_dirty", option_env!("ROC_GUI_HOST_DIRTY").unwrap_or("unavailable").into()),
        ("roc_compiler_version", "unavailable".into()),
        ("application_revision", "unavailable".into()),
        ("executable_hash", executable_hash()),
        ("cpu_model", cpu_model()),
        ("logical_cpu_count", logical_cpus),
        ("kernel_release", kernel_release()),
        ("page_size_bytes", if page_size > 0 { page_size.to_string() } else { "unavailable".into() }),
        (
            "target_profile",
            if cfg!(debug_assertions) {
                "debug"
            } else {
                "release"
            }
            .into(),
        ),
        ("clock_source", "std::time::Instant".into()),
        ("buffer_mib", config.buffer_mib.to_string()),
        ("job_count", config.job_count.to_string()),
        (
            "timing_quality",
            if config.job_count == 1 { "isolated" } else { "partial-contended" }.into(),
        ),
        (
            "max_output_bytes",
            config.max_mib.saturating_mul(1024 * 1024).to_string(),
        ),
        ("transaction_events", TRANSACTION_EVENTS.to_string()),
        (
            "transaction_coalesce_ns",
            TRANSACTION_COALESCE.as_nanos().to_string(),
        ),
        (
            "terminal_reserve_max_bytes",
            TERMINAL_RESERVE_MAX_BYTES.to_string(),
        ),
        (
            "unavailable_sources",
            "gpu_timing,gpui_layout_solve,gpui_presentation,writer_thread_cpu_time,roc_live_allocation_bytes,roc_compiler_version,application_revision".into(),
        ),
    ];
    for (key, value) in metadata {
        connection
            .execute(
                "INSERT INTO metadata(key,value) VALUES(?1,?2)",
                params![key, value],
            )
            .map_err(|error| format!("cannot write stats metadata: {error}"))?;
    }
    for (name, required_detail, status, reason) in [
        (
            "test_outcome",
            "summary",
            if config.spec_name.is_some() {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.spec_name.is_some() {
                "capture has not finalized"
            } else {
                "interactive capture has no test outcome"
            },
        ),
        (
            "step_results",
            "summary",
            if config.spec_name.is_some() {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.spec_name.is_some() {
                "capture has not finalized"
            } else {
                "interactive capture has no spec steps"
            },
        ),
        (
            "host_cycles",
            "summary",
            "unfinalized",
            "capture has not finalized",
        ),
        (
            "roc_work_spans",
            "summary",
            "unfinalized",
            "capture has not finalized",
        ),
        (
            "component_work",
            "summary",
            "unfinalized",
            "capture has not finalized",
        ),
        (
            "patch_accounting",
            "summary",
            "unfinalized",
            "capture has not finalized",
        ),
        (
            "gpui_application",
            "summary",
            if config.backend.starts_with("gpui-") {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.backend.starts_with("gpui-") {
                "capture has not finalized"
            } else {
                "semantic headless execution does not instantiate GPUI views"
            },
        ),
        (
            "virtual_list_materialization",
            "summary",
            if config.backend.starts_with("gpui-") {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.backend.starts_with("gpui-") {
                "capture has not finalized"
            } else {
                "semantic headless execution has no viewport"
            },
        ),
        (
            "gpui_frame_spans",
            "summary",
            if config.backend.starts_with("gpui-") {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.backend.starts_with("gpui-") {
                "capture has not finalized"
            } else {
                "semantic headless execution draws no GPUI frame"
            },
        ),
        (
            "gpui_layout_solve",
            "summary",
            "unavailable",
            "taffy solves layout inside GPUI's root element, outside any host-owned element",
        ),
        (
            "gpui_presentation",
            "summary",
            "unavailable",
            "GPUI 0.2.2 keeps window present and frame completion private to the crate",
        ),
        (
            "gpu_timing",
            "summary",
            "unavailable",
            "GPUI exposes no honest non-stalling GPU timing here",
        ),
        (
            "process_resources",
            "summary",
            "unfinalized",
            "capture has not finalized",
        ),
        (
            "roc_allocations",
            "summary",
            "unfinalized",
            "capture has not finalized",
        ),
        (
            "scale_verification",
            "summary",
            if config.benchmark.is_some() {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.benchmark.is_some() {
                "capture has not finalized"
            } else {
                "case has no benchmark scale"
            },
        ),
        (
            "patch_verification",
            "summary",
            if config.patch_expected {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.patch_expected {
                "capture has not finalized"
            } else {
                "case declares no expect-patch contract"
            },
        ),
        (
            "timing_environment",
            "summary",
            if config.job_count == 1 {
                "complete"
            } else {
                "partial"
            },
            if config.job_count == 1 {
                "one benchmark case ran at a time"
            } else {
                "benchmark cases shared machine resources"
            },
        ),
    ] {
        connection.execute(
            "INSERT INTO measurement_status(name,required_detail,status,reason,rows_recorded,omitted_events) VALUES(?1,?2,?3,?4,0,0)",
            params![name, required_detail, status, reason],
        ).map_err(|error| format!("cannot initialize measurement status: {error}"))?;
    }
    Ok(connection)
}

fn write_event(connection: &Connection, event: Event) -> Result<(), String> {
    match event {
        Event::RunStart {
            id,
            phase,
            sample,
            iteration,
            started_ns,
            resources,
        } => connection.execute(
            "INSERT INTO runs(id,phase,sample_index,iteration_index,started_ns,outcome,start_cpu_user_ns,start_cpu_system_ns,start_max_rss_bytes,start_current_rss_bytes,start_roc_alloc_calls,start_roc_alloc_requested_bytes,start_roc_dealloc_calls,start_roc_realloc_calls,start_roc_realloc_requested_bytes) VALUES(?1,?2,?3,?4,?5,'running',?6,?7,?8,?9,?10,?11,?12,?13,?14)",
            params![id, phase, sample, iteration, as_i64(started_ns), as_i64(resources.cpu_user_ns), as_i64(resources.cpu_system_ns), as_i64(resources.max_rss_bytes), resources.current_rss_bytes.map(as_i64), as_i64(resources.roc_alloc_calls), as_i64(resources.roc_alloc_requested_bytes), as_i64(resources.roc_dealloc_calls), as_i64(resources.roc_realloc_calls), as_i64(resources.roc_realloc_requested_bytes)],
        ),
        Event::RunEnd {
            id,
            outcome,
            ended_ns,
            diagnostic,
            resources,
        } => connection.execute(
            "UPDATE runs SET ended_ns=?2,outcome=?3,diagnostic=?4,end_cpu_user_ns=?5,end_cpu_system_ns=?6,end_max_rss_bytes=?7,end_current_rss_bytes=?8,end_roc_alloc_calls=?9,end_roc_alloc_requested_bytes=?10,end_roc_dealloc_calls=?11,end_roc_realloc_calls=?12,end_roc_realloc_requested_bytes=?13 WHERE id=?1",
            params![id, as_i64(ended_ns), outcome, diagnostic, as_i64(resources.cpu_user_ns), as_i64(resources.cpu_system_ns), as_i64(resources.max_rss_bytes), resources.current_rss_bytes.map(as_i64), as_i64(resources.roc_alloc_calls), as_i64(resources.roc_alloc_requested_bytes), as_i64(resources.roc_dealloc_calls), as_i64(resources.roc_realloc_calls), as_i64(resources.roc_realloc_requested_bytes)],
        ),
        Event::Step(result) => {
            let audio_counters = result.audio_counters;
            let clipboard_counters = result.clipboard_counters;
            let sqlite_counters = result.sqlite_counters;
            let http_counters = result.http_counters;
            let tcp_counters = result.tcp_counters;
            let component_work = result.component_work;
            connection.execute(
            "INSERT INTO steps(run_id,ordinal,source_line,kind,role,status,duration_ns,expected_count,observed_count,expected_patch_kind,observed_patch_kind,expected_staged_nodes,observed_staged_nodes,expected_removed_nodes,observed_removed_nodes,diagnostic) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
            params![result.run_id, result.ordinal as i64, result.source_line as i64, result.kind, result.role, result.status, result.duration_ns.map(as_i64), result.expected_count.map(as_i64), result.observed_count.map(as_i64), result.expected_patch_kind, result.observed_patch_kind, result.expected_staged_nodes.map(as_i64), result.observed_staged_nodes.map(as_i64), result.expected_removed_nodes.map(as_i64), result.observed_removed_nodes.map(as_i64), result.diagnostic],
            ).map_err(|error| format!("cannot write step row: {error}"))?;
            if let Some((expected, observed)) = audio_counters {
                connection.execute(
                    "INSERT INTO audio_counter_assertions(step_id,expected_live_outputs,observed_live_outputs,expected_live_tracks,observed_live_tracks,expected_acquire,observed_acquire,expected_load,observed_load,expected_play,observed_play,expected_pause,observed_pause,expected_seek,observed_seek,expected_status,observed_status,expected_stop,observed_stop) VALUES((SELECT id FROM steps WHERE run_id=?1 AND ordinal=?2),?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20)",
                    params![result.run_id, result.ordinal as i64, as_i64(expected[0]), as_i64(observed[0]), as_i64(expected[1]), as_i64(observed[1]), as_i64(expected[2]), as_i64(observed[2]), as_i64(expected[3]), as_i64(observed[3]), as_i64(expected[4]), as_i64(observed[4]), as_i64(expected[5]), as_i64(observed[5]), as_i64(expected[6]), as_i64(observed[6]), as_i64(expected[7]), as_i64(observed[7]), as_i64(expected[8]), as_i64(observed[8])],
                ).map_err(|error| format!("cannot write audio counter assertion: {error}"))?;
            }
            if let Some((expected, observed)) = clipboard_counters {
                connection.execute(
                    "INSERT INTO clipboard_counter_assertions(step_id,expected_live_handles,observed_live_handles,expected_acquire,observed_acquire,expected_read,observed_read,expected_write,observed_write) VALUES((SELECT id FROM steps WHERE run_id=?1 AND ordinal=?2),?3,?4,?5,?6,?7,?8,?9,?10)",
                    params![result.run_id, result.ordinal as i64, as_i64(expected[0]), as_i64(observed[0]), as_i64(expected[1]), as_i64(observed[1]), as_i64(expected[2]), as_i64(observed[2]), as_i64(expected[3]), as_i64(observed[3])],
                ).map_err(|error| format!("cannot write clipboard counter assertion: {error}"))?;
            }
            if let Some((expected, observed)) = sqlite_counters {
                connection.execute(
                    "INSERT INTO database_counter_assertions(step_id,expected_live_connections,observed_live_connections,expected_open,observed_open,expected_query,observed_query) VALUES((SELECT id FROM steps WHERE run_id=?1 AND ordinal=?2),?3,?4,?5,?6,?7,?8)",
                    params![result.run_id, result.ordinal as i64, as_i64(expected[0]), as_i64(observed[0]), as_i64(expected[1]), as_i64(observed[1]), as_i64(expected[2]), as_i64(observed[2])],
                ).map_err(|error| format!("cannot write SQLite counter assertion: {error}"))?;
            }
            if let Some((expected, observed)) = http_counters {
                connection.execute(
                    "INSERT INTO http_counter_assertions(step_id,expected_live_clients,observed_live_clients,expected_acquire,observed_acquire,expected_send,observed_send,expected_denied,observed_denied) VALUES((SELECT id FROM steps WHERE run_id=?1 AND ordinal=?2),?3,?4,?5,?6,?7,?8,?9,?10)",
                    params![result.run_id, result.ordinal as i64, as_i64(expected[0]), as_i64(observed[0]), as_i64(expected[1]), as_i64(observed[1]), as_i64(expected[2]), as_i64(observed[2]), as_i64(expected[3]), as_i64(observed[3])],
                ).map_err(|error| format!("cannot write HTTP counter assertion: {error}"))?;
            }
            if let Some((expected, observed)) = tcp_counters {
                connection.execute(
                    "INSERT INTO tcp_counter_assertions(step_id,expected_live_streams,observed_live_streams,expected_connect,observed_connect,expected_read,observed_read,expected_write,observed_write,expected_close,observed_close) VALUES((SELECT id FROM steps WHERE run_id=?1 AND ordinal=?2),?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)",
                    params![result.run_id, result.ordinal as i64, as_i64(expected[0]), as_i64(observed[0]), as_i64(expected[1]), as_i64(observed[1]), as_i64(expected[2]), as_i64(observed[2]), as_i64(expected[3]), as_i64(observed[3]), as_i64(expected[4]), as_i64(observed[4])],
                ).map_err(|error| format!("cannot write TCP counter assertion: {error}"))?;
            }
            if let Some((expected, observed)) = component_work {
                for (kind, expected) in expected.into_iter().enumerate() {
                    if let Some(expected) = expected {
                        connection.execute(
                            "INSERT INTO component_work_assertions(step_id,kind,expected_count,observed_count) VALUES((SELECT id FROM steps WHERE run_id=?1 AND ordinal=?2),?3,?4,?5)",
                            params![result.run_id, result.ordinal as i64, kind as i64, as_i64(expected), observed.map(|work| as_i64(work.0[kind]))],
                        ).map_err(|error| format!("cannot write component work assertion: {error}"))?;
                    }
                }
            }
            Ok(1)
        },
        Event::Cycle(cycle) => {
            connection.execute(
                "INSERT INTO cycles(run_id,ordinal,step_ordinal,measurement_phase,trigger,patch_kind,duration_ns,roc_callback_ns,validate_ns,apply_ns,graph_apply_ns,gpui_apply_ns,staged_nodes,removed_nodes,live_nodes,parent_nodes_scanned,roc_work_valid,component_work_recorded,retained_nodes,validation_visits) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20)",
                params![cycle.run_id, as_i64(cycle.ordinal), cycle.step_ordinal.map(|value| value as i64), cycle.measurement_phase, cycle.trigger, cycle.patch_kind, as_i64(cycle.duration_ns), as_i64(cycle.roc_callback_ns), as_i64(cycle.validate_ns), as_i64(cycle.apply_ns), as_i64(cycle.graph_apply_ns), cycle.gpui_apply_ns.map(as_i64), as_i64(cycle.staged_nodes), as_i64(cycle.removed_nodes), as_i64(cycle.live_nodes), as_i64(cycle.parent_nodes_scanned), i64::from(cycle.roc_work_valid), i64::from(cycle.component_work.is_some()), as_i64(cycle.retained_nodes), as_i64(cycle.validation_visits)],
            )
            .map_err(|error| format!("cannot write cycle row: {error}"))?;
            let cycle_id = connection.last_insert_rowid();
            if let Some(work) = cycle.component_work {
                for (kind, count) in work.0.into_iter().enumerate().filter(|(_, count)| *count != 0) {
                    connection.execute(
                        "INSERT INTO component_work_counts(cycle_id,kind,count) VALUES(?1,?2,?3)",
                        params![cycle_id, kind as i64, as_i64(count)],
                    ).map_err(|error| format!("cannot write component work count: {error}"))?;
                }
            }
            for (kind, work) in ROC_WORK_NAMES.iter().zip(cycle.roc_work) {
                if !work.occurred {
                    continue;
                }
                connection.execute(
                    "INSERT INTO roc_work_spans(cycle_id,kind,duration_ns,alloc_calls,allocated_bytes,dealloc_calls,realloc_calls,reallocated_bytes) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)",
                    params![cycle_id, kind, as_i64(work.duration_ns), as_i64(work.alloc_calls), as_i64(work.allocated_bytes), as_i64(work.dealloc_calls), as_i64(work.realloc_calls), as_i64(work.reallocated_bytes)],
                ).map_err(|error| format!("cannot write Roc work span: {error}"))?;
            }
            Ok(1)
        },
        Event::GpuiFrame { ordinal, layout_request_ns, prepaint_ns, paint_ns } => connection.execute(
            "INSERT INTO gpui_frames(run_id,ordinal,layout_request_ns,prepaint_ns,paint_ns) VALUES(1,?1,?2,?3,?4)",
            params![as_i64(ordinal), as_i64(layout_request_ns), as_i64(prepaint_ns), as_i64(paint_ns)],
        ),
        Event::VirtualListFrame { list_id, visible_items, materialized_entities, recycled_entities, live_entities } => connection.execute(
            "INSERT INTO virtual_list_frames(run_id,list_id,visible_items,materialized_entities,recycled_entities,live_entities) VALUES(1,?1,?2,?3,?4,?5)",
            params![as_i64(list_id), as_i64(visible_items), as_i64(materialized_entities), as_i64(recycled_entities), as_i64(live_entities)],
        ),
        Event::Finish { .. } => return Err("internal recorder finalization ordering error".into()),
    }
    .map(|_| ())
    .map_err(|error| format!("cannot write stats row: {error}"))
}

// Terminal capture evidence is recorded as individual metadata values.
#[allow(clippy::too_many_arguments)]
fn finalize(
    connection: &Connection,
    path: &Path,
    application_outcome: &str,
    drain: Duration,
    omitted: u64,
    queue_high_water: u64,
    rows_written: u64,
    transactions: u64,
    output_limited: bool,
) -> Result<(), String> {
    // Establish a durable committed prefix before deriving terminal evidence.
    // A capture is never marked clean until a later checkpoint also succeeds.
    connection
        .execute_batch("PRAGMA wal_checkpoint(TRUNCATE)")
        .map_err(|error| {
            format!(
                "cannot checkpoint {} before finalization: {error}",
                path.display()
            )
        })?;
    if omitted > 0 {
        connection.execute(
            "INSERT INTO recording_gaps(family,lost_count,reason) VALUES('writer_queue',?1,'bounded recorder admission refused events')",
            params![as_i64(omitted)],
        ).map_err(|error| format!("cannot write recording gap: {error}"))?;
    }
    let output_bytes = database_bytes(connection, path).unwrap_or(0);
    connection.execute(
        "INSERT INTO recorder_health(id,transactions,queue_high_water,output_bytes,omitted_events,rows_written,writer_failed,output_limited,drain_duration_ns) VALUES(1,?1,?2,?3,?4,?5,0,?6,?7)",
        params![as_i64(transactions), as_i64(queue_high_water), as_i64(output_bytes), as_i64(omitted), as_i64(rows_written), i64::from(output_limited), as_i64(drain.as_nanos() as u64)],
    ).map_err(|error| format!("cannot write recorder health: {error}"))?;
    connection
        .execute(
            "INSERT OR REPLACE INTO metadata(key,value) VALUES(?1,?2)",
            params!["application_outcome", application_outcome],
        )
        .map_err(|error| format!("cannot finalize application outcome: {error}"))?;
    connection
        .execute(
            "INSERT OR REPLACE INTO metadata(key,value) VALUES('drain_duration_ns',?1)",
            params![drain.as_nanos().to_string()],
        )
        .map_err(|error| format!("cannot finalize drain metadata: {error}"))?;
    let partial = omitted > 0 || output_limited;
    connection.execute(
        "UPDATE measurement_status SET status=CASE WHEN status IN ('partial','not_recorded','unavailable') THEN status WHEN name='virtual_list_materialization' AND NOT EXISTS(SELECT 1 FROM virtual_list_frames) THEN 'unavailable' WHEN name='gpui_frame_spans' AND NOT EXISTS(SELECT 1 FROM gpui_frames) THEN 'unavailable' WHEN ?1 THEN 'partial' ELSE 'complete' END, reason=CASE WHEN status IN ('partial','not_recorded','unavailable') THEN reason WHEN name='virtual_list_materialization' AND NOT EXISTS(SELECT 1 FROM virtual_list_frames) THEN 'no virtual list entered a viewport' WHEN name='gpui_frame_spans' AND NOT EXISTS(SELECT 1 FROM gpui_frames) THEN 'no GPUI frame was drawn' WHEN ?1 THEN 'recorder omitted events' ELSE 'capture finalized without recorded loss' END, omitted_events=?2, rows_recorded=CASE name WHEN 'test_outcome' THEN (SELECT count(*) FROM runs) WHEN 'step_results' THEN (SELECT count(*) FROM steps) WHEN 'host_cycles' THEN (SELECT count(*) FROM cycles) WHEN 'roc_work_spans' THEN (SELECT count(*) FROM roc_work_spans) WHEN 'patch_accounting' THEN (SELECT count(*) FROM cycles) WHEN 'gpui_application' THEN (SELECT count(*) FROM cycles) WHEN 'virtual_list_materialization' THEN (SELECT count(*) FROM virtual_list_frames) WHEN 'gpui_frame_spans' THEN (SELECT count(*) FROM gpui_frames) WHEN 'process_resources' THEN (SELECT count(*) FROM runs WHERE ended_ns IS NOT NULL) WHEN 'roc_allocations' THEN (SELECT count(*) FROM runs WHERE ended_ns IS NOT NULL) WHEN 'scale_verification' THEN (SELECT count(*) FROM steps WHERE expected_count IS NOT NULL AND expected_count=observed_count) WHEN 'patch_verification' THEN (SELECT count(*) FROM steps WHERE expected_patch_kind=observed_patch_kind AND expected_staged_nodes=observed_staged_nodes AND expected_removed_nodes=observed_removed_nodes) ELSE 0 END",
        params![partial, as_i64(omitted)],
    ).map_err(|error| format!("cannot finalize measurement status: {error}"))?;
    connection.execute(
        "UPDATE measurement_status SET status=CASE WHEN ?1 THEN 'partial' WHEN NOT EXISTS(SELECT 1 FROM cycles) THEN 'unavailable' WHEN EXISTS(SELECT 1 FROM cycles WHERE roc_work_valid=0) THEN 'partial' WHEN NOT EXISTS(SELECT 1 FROM roc_work_spans) THEN 'unavailable' ELSE 'complete' END, reason=CASE WHEN ?1 THEN 'recorder omitted events' WHEN NOT EXISTS(SELECT 1 FROM cycles) THEN 'no host cycles were recorded' WHEN EXISTS(SELECT 1 FROM cycles WHERE roc_work_valid=0) THEN 'one or more callbacks had invalid or incomplete work spans' WHEN NOT EXISTS(SELECT 1 FROM roc_work_spans) THEN 'no attributed Roc work span occurred' ELSE 'every recorded callback has valid span evidence' END, rows_recorded=(SELECT count(*) FROM roc_work_spans), omitted_events=?2 WHERE name='roc_work_spans'",
        params![partial, as_i64(omitted)],
    ).map_err(|error| format!("cannot finalize Roc work status: {error}"))?;
    connection.execute(
        "UPDATE measurement_status SET status=CASE WHEN ?1 THEN 'partial' WHEN NOT EXISTS(SELECT 1 FROM cycles WHERE component_work_recorded=1) THEN 'unavailable' WHEN EXISTS(SELECT 1 FROM cycles WHERE component_work_recorded=0) THEN 'partial' ELSE 'complete' END, reason=CASE WHEN ?1 THEN 'recorder omitted events' WHEN NOT EXISTS(SELECT 1 FROM cycles WHERE component_work_recorded=1) THEN 'no committed component work observation was recorded' WHEN EXISTS(SELECT 1 FROM cycles WHERE component_work_recorded=0) THEN 'one or more cycles have no committed component work observation' ELSE 'every recorded cycle has component owner evidence' END, rows_recorded=(SELECT count(*) FROM cycles WHERE component_work_recorded=1), omitted_events=?2 WHERE name='component_work'",
        params![partial, as_i64(omitted)],
    ).map_err(|error| format!("cannot finalize component work status: {error}"))?;
    let orphan_count: i64 = connection
        .query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |row| {
            row.get(0)
        })
        .map_err(|error| format!("cannot validate stats foreign keys: {error}"))?;
    if orphan_count != 0 {
        return Err(format!(
            "stats database contains {orphan_count} orphan rows"
        ));
    }
    let integrity: String = connection
        .query_row("PRAGMA quick_check", [], |row| row.get(0))
        .map_err(|error| format!("cannot validate stats database: {error}"))?;
    if integrity != "ok" {
        return Err(format!(
            "stats database integrity check failed: {integrity}"
        ));
    }
    connection
        .execute(
            "UPDATE metadata SET value='complete' WHERE key='final_state'",
            [],
        )
        .map_err(|error| format!("cannot finalize state: {error}"))?;
    connection
        .execute_batch("PRAGMA wal_checkpoint(TRUNCATE)")
        .map_err(|error| format!("cannot checkpoint {}: {error}", path.display()))?;
    // This is deliberately the last logical write. If any checkpoint or
    // integrity operation above fails, clean_shutdown remains its startup 0.
    connection
        .execute(
            "UPDATE metadata SET value='1' WHERE key='clean_shutdown'",
            [],
        )
        .map_err(|error| format!("cannot mark clean shutdown: {error}"))?;
    Ok(())
}

fn database_bytes(connection: &Connection, path: &Path) -> rusqlite::Result<u64> {
    let pages: i64 = connection.query_row("PRAGMA page_count", [], |row| row.get(0))?;
    let page_size: i64 = connection.query_row("PRAGMA page_size", [], |row| row.get(0))?;
    let logical_main = (pages.max(0) as u64).saturating_mul(page_size.max(0) as u64);
    let main = std::fs::metadata(path)
        .map(|value| value.len())
        .unwrap_or(0);
    let wal_path = PathBuf::from(format!("{}-wal", path.display()));
    let wal = std::fs::metadata(wal_path)
        .map(|value| value.len())
        .unwrap_or(0);
    Ok(logical_main.max(main).saturating_add(wal))
}

fn as_i64(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

const SCHEMA: &str = r#"
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA user_version=11;
CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE measurement_status(
    name TEXT PRIMARY KEY,
    required_detail TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('unfinalized','complete','partial','not_recorded','unavailable')),
    reason TEXT NOT NULL,
    rows_recorded INTEGER NOT NULL,
    omitted_events INTEGER NOT NULL
);
CREATE TABLE runs(
    id INTEGER PRIMARY KEY,
    phase TEXT NOT NULL CHECK(phase IN ('test','warmup','sample','interactive')),
    sample_index INTEGER,
    iteration_index INTEGER NOT NULL,
    started_ns INTEGER NOT NULL,
    ended_ns INTEGER,
    outcome TEXT NOT NULL CHECK(outcome IN ('running','pass','fail')),
    diagnostic TEXT,
    start_cpu_user_ns INTEGER NOT NULL,
    end_cpu_user_ns INTEGER,
    start_cpu_system_ns INTEGER NOT NULL,
    end_cpu_system_ns INTEGER,
    start_max_rss_bytes INTEGER NOT NULL,
    end_max_rss_bytes INTEGER,
    start_current_rss_bytes INTEGER,
    end_current_rss_bytes INTEGER,
    start_roc_alloc_calls INTEGER NOT NULL,
    end_roc_alloc_calls INTEGER,
    start_roc_alloc_requested_bytes INTEGER NOT NULL,
    end_roc_alloc_requested_bytes INTEGER,
    start_roc_dealloc_calls INTEGER NOT NULL,
    end_roc_dealloc_calls INTEGER,
    start_roc_realloc_calls INTEGER NOT NULL,
    end_roc_realloc_calls INTEGER,
    start_roc_realloc_requested_bytes INTEGER NOT NULL,
    end_roc_realloc_requested_bytes INTEGER
);
CREATE TABLE steps(
    id INTEGER PRIMARY KEY,
    run_id INTEGER NOT NULL REFERENCES runs(id),
    ordinal INTEGER NOT NULL,
    source_line INTEGER NOT NULL,
    kind TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('setup','boundary','operation','assertion')),
    status TEXT NOT NULL CHECK(status IN ('pass','fail')),
    duration_ns INTEGER,
    expected_count INTEGER,
    observed_count INTEGER,
    expected_patch_kind TEXT,
    observed_patch_kind TEXT,
    expected_staged_nodes INTEGER,
    observed_staged_nodes INTEGER,
    expected_removed_nodes INTEGER,
    observed_removed_nodes INTEGER,
    diagnostic TEXT,
    UNIQUE(run_id,ordinal)
);
CREATE TABLE audio_counter_assertions(
    step_id INTEGER PRIMARY KEY REFERENCES steps(id),
    expected_live_outputs INTEGER NOT NULL, observed_live_outputs INTEGER NOT NULL,
    expected_live_tracks INTEGER NOT NULL, observed_live_tracks INTEGER NOT NULL,
    expected_acquire INTEGER NOT NULL, observed_acquire INTEGER NOT NULL,
    expected_load INTEGER NOT NULL, observed_load INTEGER NOT NULL,
    expected_play INTEGER NOT NULL, observed_play INTEGER NOT NULL,
    expected_pause INTEGER NOT NULL, observed_pause INTEGER NOT NULL,
    expected_seek INTEGER NOT NULL, observed_seek INTEGER NOT NULL,
    expected_status INTEGER NOT NULL, observed_status INTEGER NOT NULL,
    expected_stop INTEGER NOT NULL, observed_stop INTEGER NOT NULL
);
CREATE TABLE clipboard_counter_assertions(
    step_id INTEGER PRIMARY KEY REFERENCES steps(id),
    expected_live_handles INTEGER NOT NULL, observed_live_handles INTEGER NOT NULL,
    expected_acquire INTEGER NOT NULL, observed_acquire INTEGER NOT NULL,
    expected_read INTEGER NOT NULL, observed_read INTEGER NOT NULL,
    expected_write INTEGER NOT NULL, observed_write INTEGER NOT NULL
);
CREATE TABLE database_counter_assertions(
    step_id INTEGER PRIMARY KEY REFERENCES steps(id),
    expected_live_connections INTEGER NOT NULL, observed_live_connections INTEGER NOT NULL,
    expected_open INTEGER NOT NULL, observed_open INTEGER NOT NULL,
    expected_query INTEGER NOT NULL, observed_query INTEGER NOT NULL
);
CREATE TABLE http_counter_assertions(
    step_id INTEGER PRIMARY KEY REFERENCES steps(id),
    expected_live_clients INTEGER NOT NULL, observed_live_clients INTEGER NOT NULL,
    expected_acquire INTEGER NOT NULL, observed_acquire INTEGER NOT NULL,
    expected_send INTEGER NOT NULL, observed_send INTEGER NOT NULL
    ,expected_denied INTEGER NOT NULL, observed_denied INTEGER NOT NULL
);
CREATE TABLE tcp_counter_assertions(
    step_id INTEGER PRIMARY KEY REFERENCES steps(id),
    expected_live_streams INTEGER NOT NULL, observed_live_streams INTEGER NOT NULL,
    expected_connect INTEGER NOT NULL, observed_connect INTEGER NOT NULL,
    expected_read INTEGER NOT NULL, observed_read INTEGER NOT NULL,
    expected_write INTEGER NOT NULL, observed_write INTEGER NOT NULL,
    expected_close INTEGER NOT NULL, observed_close INTEGER NOT NULL
);
CREATE TABLE cycles(
    id INTEGER PRIMARY KEY,
    run_id INTEGER NOT NULL REFERENCES runs(id),
    ordinal INTEGER NOT NULL,
    step_ordinal INTEGER,
    measurement_phase TEXT NOT NULL CHECK(measurement_phase IN ('initialization','setup','measured','interactive')),
    trigger TEXT NOT NULL,
    patch_kind TEXT NOT NULL CHECK(patch_kind IN ('mount','no_change','replace')),
    duration_ns INTEGER NOT NULL,
    roc_callback_ns INTEGER NOT NULL,
    validate_ns INTEGER NOT NULL,
    apply_ns INTEGER NOT NULL,
    graph_apply_ns INTEGER NOT NULL,
    gpui_apply_ns INTEGER,
    staged_nodes INTEGER NOT NULL,
    removed_nodes INTEGER NOT NULL,
    live_nodes INTEGER NOT NULL,
    parent_nodes_scanned INTEGER NOT NULL,
    retained_nodes INTEGER NOT NULL,
    validation_visits INTEGER NOT NULL,
    roc_work_valid INTEGER NOT NULL CHECK(roc_work_valid IN (0,1)),
    component_work_recorded INTEGER NOT NULL CHECK(component_work_recorded IN (0,1)),
    UNIQUE(run_id,ordinal),
    FOREIGN KEY(run_id,step_ordinal) REFERENCES steps(run_id,ordinal)
);
CREATE TABLE component_work_counts(
    cycle_id INTEGER NOT NULL REFERENCES cycles(id),
    kind INTEGER NOT NULL CHECK(kind BETWEEN 0 AND 6),
    count INTEGER NOT NULL CHECK(count > 0),
    PRIMARY KEY(cycle_id,kind)
);
CREATE TABLE component_work_assertions(
    step_id INTEGER NOT NULL REFERENCES steps(id),
    kind INTEGER NOT NULL CHECK(kind BETWEEN 0 AND 6),
    expected_count INTEGER NOT NULL CHECK(expected_count >= 0),
    observed_count INTEGER CHECK(observed_count >= 0),
    PRIMARY KEY(step_id,kind)
);
CREATE TABLE gpui_frames(
    id INTEGER PRIMARY KEY,
    run_id INTEGER NOT NULL REFERENCES runs(id),
    ordinal INTEGER NOT NULL,
    layout_request_ns INTEGER NOT NULL,
    prepaint_ns INTEGER NOT NULL,
    paint_ns INTEGER NOT NULL,
    UNIQUE(run_id,ordinal)
);
CREATE TABLE virtual_list_frames(
    id INTEGER PRIMARY KEY,
    run_id INTEGER NOT NULL REFERENCES runs(id),
    list_id INTEGER NOT NULL,
    visible_items INTEGER NOT NULL,
    materialized_entities INTEGER NOT NULL,
    recycled_entities INTEGER NOT NULL,
    live_entities INTEGER NOT NULL
);
CREATE TABLE recording_gaps(
    id INTEGER PRIMARY KEY,
    family TEXT NOT NULL,
    lost_count INTEGER NOT NULL,
    reason TEXT NOT NULL
);
CREATE TABLE roc_work_spans(
    cycle_id INTEGER NOT NULL REFERENCES cycles(id),
    kind TEXT NOT NULL CHECK(kind IN ('routing','application_update','application_render','platform_lowering','component_comparison')),
    duration_ns INTEGER NOT NULL,
    alloc_calls INTEGER NOT NULL,
    allocated_bytes INTEGER NOT NULL,
    dealloc_calls INTEGER NOT NULL,
    realloc_calls INTEGER NOT NULL,
    reallocated_bytes INTEGER NOT NULL,
    PRIMARY KEY(cycle_id,kind)
);
CREATE TABLE recorder_health(
    id INTEGER PRIMARY KEY CHECK(id=1),
    transactions INTEGER NOT NULL,
    queue_high_water INTEGER NOT NULL,
    output_bytes INTEGER NOT NULL,
    omitted_events INTEGER NOT NULL,
    rows_written INTEGER NOT NULL,
    writer_failed INTEGER NOT NULL,
    output_limited INTEGER NOT NULL,
    drain_duration_ns INTEGER NOT NULL
);
CREATE INDEX runs_by_phase_sample ON runs(phase,sample_index,iteration_index);
CREATE INDEX steps_by_run_ordinal ON steps(run_id,ordinal);
CREATE INDEX cycles_by_run_ordinal ON cycles(run_id,ordinal);
CREATE INDEX roc_work_spans_by_kind ON roc_work_spans(kind,cycle_id);
CREATE INDEX virtual_list_frames_by_run ON virtual_list_frames(run_id,id);
CREATE INDEX gpui_frames_by_run_ordinal ON gpui_frames(run_id,ordinal);
"#;

#[cfg(test)]
mod tests {
    use super::*;

    static RECORDER_TEST: Mutex<()> = Mutex::new(());

    #[test]
    fn component_work_is_owned_by_committed_turns_without_a_recorder() {
        clear_component_work();
        assert_eq!(last_component_work(), None);
        begin_component_work();
        note_component_work(0, 2);
        note_component_work(1, 3);
        assert_eq!(last_component_work(), None);
        commit_component_work();
        let first = ComponentWork([2, 3, 0, 0, 0, 0, 0]);
        assert_eq!(last_component_work(), Some(first));
        begin_component_work();
        note_component_work(0, 1);
        reject_component_work();
        assert_eq!(last_component_work(), Some(first));
        assert_eq!(total_component_work(), ComponentWork([3, 3, 0, 0, 0, 0, 0]));
        begin_component_work();
        commit_component_work();
        assert_eq!(last_component_work(), Some(ComponentWork::default()));
        clear_component_work();
        assert_eq!(last_component_work(), None);
    }

    #[test]
    fn component_cycle_sums_actual_turns_and_does_not_reuse_a_previous_cycle() {
        clear_component_work();
        reset_component_cycle();
        assert_eq!(component_cycle_work(), None);
        for renders in [2, 3] {
            begin_component_work();
            note_component_work(0, renders);
            commit_component_work();
        }
        assert_eq!(
            last_component_work(),
            Some(ComponentWork([3, 0, 0, 0, 0, 0, 0]))
        );
        assert_eq!(
            component_cycle_work(),
            Some(ComponentWork([5, 0, 0, 0, 0, 0, 0]))
        );
        reset_component_cycle();
        assert_eq!(component_cycle_work(), None);
        begin_component_work();
        commit_component_work();
        assert_eq!(component_cycle_work(), Some(ComponentWork::default()));
        clear_component_work();
    }

    fn test_cycle(phase: &'static str, ordinal: u64, patch_kind: &'static str) -> Cycle {
        Cycle {
            run_id: 1,
            ordinal,
            step_ordinal: None,
            measurement_phase: phase,
            trigger: "click",
            patch_kind,
            duration_ns: 100,
            roc_callback_ns: 50,
            validate_ns: 10,
            apply_ns: 20,
            graph_apply_ns: 20,
            gpui_apply_ns: None,
            staged_nodes: 1,
            removed_nodes: 0,
            live_nodes: 1,
            parent_nodes_scanned: 1,
            retained_nodes: 0,
            validation_visits: 1,
            roc_work: [RocWork::default(); ROC_WORK_KINDS],
            roc_work_valid: true,
            component_work: None,
        }
    }

    fn detail_capture(detail: Detail) -> (PathBuf, Connection) {
        let path = std::env::temp_dir().join(format!(
            "roc-gui-detail-{}-{}-{}.rgstats",
            detail.as_str(),
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        start(Config {
            path: path.clone(),
            detail,
            buffer_mib: 1,
            max_mib: 16,
            backend: "semantic-headless",
            app_name: "test".into(),
            spec_name: Some("detail".into()),
            spec_hash: Some(stable_hash(b"detail")),
            benchmark: None,
            job_count: 1,
            patch_expected: false,
        })
        .unwrap();
        run_start(1, "sample", Some(0), 0, 1);
        cycle(test_cycle("setup", 0, "replace"));
        cycle(test_cycle("measured", 1, "no_change"));
        run_end(1, "pass", 2, None);
        finish("success").unwrap();
        let db = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        (path, db)
    }

    #[test]
    fn stable_hash_is_repeatable() {
        assert_eq!(stable_hash(b"abc"), stable_hash(b"abc"));
        assert_ne!(stable_hash(b"abc"), stable_hash(b"abd"));
    }

    #[test]
    fn detail_policy_is_explicit_and_setup_is_full_only() {
        assert_eq!(Detail::parse("summary"), Some(Detail::Summary));
        assert_eq!(Detail::parse("full"), Some(Detail::Full));
        assert_eq!(Detail::parse("standard"), None);
        assert!(Detail::Summary.records_cycle("measured"));
        assert!(Detail::Summary.records_cycle("interactive"));
        assert!(!Detail::Summary.records_cycle("setup"));
        assert!(Detail::Full.records_cycle("setup"));
    }

    #[test]
    fn detail_policy_controls_persisted_setup_cycles() {
        let _guard = RECORDER_TEST.lock().unwrap();
        for (detail, expected_cycles) in [(Detail::Summary, 1), (Detail::Full, 2)] {
            let (path, db) = detail_capture(detail);
            assert_eq!(
                db.query_row("SELECT count(*) FROM cycles", [], |row| row
                    .get::<_, i64>(0))
                    .unwrap(),
                expected_cycles
            );
            assert_eq!(
                db.query_row(
                    "SELECT value FROM metadata WHERE key='effective_detail'",
                    [],
                    |row| row.get::<_, String>(0)
                )
                .unwrap(),
                detail.as_str()
            );
            assert_eq!(
                db.query_row(
                    "SELECT status FROM measurement_status WHERE name='roc_work_spans'",
                    [],
                    |row| row.get::<_, String>(0)
                )
                .unwrap(),
                "unavailable"
            );
            let mut report = db
                .prepare(include_str!("../../../scripts/stats_queries/roc_work.sql"))
                .unwrap();
            let rows = report
                .query_map([], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(13)?))
                })
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            assert_eq!(rows, vec![("unavailable".into(), None)]);
            drop(report);
            let mut component_report = db
                .prepare(include_str!(
                    "../../../scripts/stats_queries/component_work.sql"
                ))
                .unwrap();
            let component_rows = component_report
                .query_map([], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, Option<i64>>(4)?))
                })
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            assert_eq!(
                component_rows,
                vec![("unavailable".into(), None); COMPONENT_WORK_NAMES.len()]
            );
            drop(component_report);
            drop(db);
            std::fs::remove_file(path).unwrap();
        }
    }

    #[test]
    fn persists_virtual_list_owner_counters() {
        let _guard = RECORDER_TEST.lock().unwrap();
        let path = std::env::temp_dir().join(format!(
            "roc-gui-virtual-list-{}-{}.rgstats",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        start(Config {
            path: path.clone(),
            detail: Detail::Summary,
            buffer_mib: 1,
            max_mib: 16,
            backend: "gpui-wayland",
            app_name: "test".into(),
            spec_name: None,
            spec_hash: None,
            benchmark: None,
            job_count: 1,
            patch_expected: false,
        })
        .unwrap();
        run_start(1, "interactive", None, 0, 1);
        virtual_list_frame(17, 8, 24, 6, 24);
        run_end(1, "pass", 2, None);
        finish("success").unwrap();
        let db = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let values = db.query_row("SELECT list_id,visible_items,materialized_entities,recycled_entities,live_entities FROM virtual_list_frames", [], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?, row.get::<_, i64>(2)?, row.get::<_, i64>(3)?, row.get::<_, i64>(4)?))).unwrap();
        assert_eq!(values, (17, 8, 24, 6, 24));
        assert_eq!(
            db.query_row(
                "SELECT status FROM measurement_status WHERE name='virtual_list_materialization'",
                [],
                |row| row.get::<_, String>(0)
            )
            .unwrap(),
            "complete"
        );
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn persists_gpui_frame_spans_and_keeps_unowned_stages_unavailable() {
        let _guard = RECORDER_TEST.lock().unwrap();
        let path = std::env::temp_dir().join(format!(
            "roc-gui-frame-spans-{}-{}.rgstats",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        start(Config {
            path: path.clone(),
            detail: Detail::Summary,
            buffer_mib: 1,
            max_mib: 16,
            backend: "gpui-wayland",
            app_name: "test".into(),
            spec_name: None,
            spec_hash: None,
            benchmark: None,
            job_count: 1,
            patch_expected: false,
        })
        .unwrap();
        run_start(1, "interactive", None, 0, 1);
        gpui_frame(400, 900, 1_600);
        gpui_frame(410, 910, 1_610);
        run_end(1, "pass", 2, None);
        finish("success").unwrap();
        let db = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let values = db
            .query_row(
                "SELECT ordinal,layout_request_ns,prepaint_ns,paint_ns FROM gpui_frames ORDER BY ordinal LIMIT 1",
                [],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .unwrap();
        assert_eq!(values, (0, 400, 900, 1_600));
        assert_eq!(
            db.query_row(
                "SELECT status,rows_recorded FROM measurement_status WHERE name='gpui_frame_spans'",
                [],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
            )
            .unwrap(),
            ("complete".to_string(), 2)
        );
        // The stages GPUI performs outside any host-owned element stay
        // unavailable; they are never derived from the spans above.
        for name in ["gpui_layout_solve", "gpui_presentation"] {
            assert_eq!(
                db.query_row(
                    "SELECT status FROM measurement_status WHERE name=?1",
                    params![name],
                    |row| row.get::<_, String>(0)
                )
                .unwrap(),
                "unavailable"
            );
        }
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn a_capture_with_no_frame_reports_frame_spans_unavailable() {
        let _guard = RECORDER_TEST.lock().unwrap();
        let path = std::env::temp_dir().join(format!(
            "roc-gui-frame-spans-absent-{}-{}.rgstats",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        start(Config {
            path: path.clone(),
            detail: Detail::Summary,
            buffer_mib: 1,
            max_mib: 16,
            backend: "semantic-headless",
            app_name: "test".into(),
            spec_name: None,
            spec_hash: None,
            benchmark: None,
            job_count: 1,
            patch_expected: false,
        })
        .unwrap();
        run_start(1, "interactive", None, 0, 1);
        run_end(1, "pass", 2, None);
        finish("success").unwrap();
        let db = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        assert_eq!(
            db.query_row("SELECT count(*) FROM gpui_frames", [], |row| row
                .get::<_, i64>(0))
                .unwrap(),
            0
        );
        assert_eq!(
            db.query_row(
                "SELECT status,reason FROM measurement_status WHERE name='gpui_frame_spans'",
                [],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            )
            .unwrap(),
            (
                "not_recorded".to_string(),
                "semantic headless execution draws no GPUI frame".to_string()
            )
        );
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn creates_and_finalizes_capture() {
        let _guard = RECORDER_TEST.lock().unwrap();
        let path = std::env::temp_dir().join(format!(
            "roc-gui-observatory-{}-{}.rgstats",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        start(Config {
            path: path.clone(),
            detail: Detail::Summary,
            buffer_mib: 1,
            max_mib: 16,
            backend: "semantic-headless",
            app_name: "test".into(),
            spec_name: Some("case".into()),
            spec_hash: Some(stable_hash(b"case")),
            benchmark: None,
            job_count: 1,
            patch_expected: false,
        })
        .unwrap();
        run_start(1, "sample", Some(0), 0, 1);
        reset_roc_work();
        start_roc_work(2);
        note_roc_alloc(32);
        note_roc_realloc(48);
        note_roc_dealloc();
        end_roc_work(2);
        start_roc_work(4);
        end_roc_work(4);
        let (attributed, valid) = take_roc_work();
        assert!(valid);
        assert!(attributed[2].duration_ns > 0);
        assert_eq!(attributed[2].alloc_calls, 1);
        assert_eq!(attributed[2].allocated_bytes, 32);
        assert_eq!(attributed[2].dealloc_calls, 1);
        assert_eq!(attributed[2].realloc_calls, 1);
        assert_eq!(attributed[2].reallocated_bytes, 48);
        assert_eq!(attributed[0].alloc_calls, 0);
        assert!(attributed[4].occurred);
        note_roc_alloc(64);
        note_roc_realloc(128);
        note_roc_dealloc();
        step(StepResult {
            run_id: 1,
            ordinal: 0,
            source_line: 1,
            kind: "expect-visible",
            role: "assertion",
            status: "pass",
            duration_ns: None,
            expected_count: None,
            observed_count: None,
            audio_counters: None,
            clipboard_counters: None,
            sqlite_counters: None,
            http_counters: None,
            tcp_counters: None,
            component_work: Some((
                [Some(2), Some(1), Some(0), None, None, None, None],
                Some(ComponentWork([2, 1, 0, 0, 0, 0, 0])),
            )),
            expected_patch_kind: Some("replace".into()),
            observed_patch_kind: Some("replace"),
            expected_staged_nodes: Some(7),
            observed_staged_nodes: Some(7),
            expected_removed_nodes: Some(2),
            observed_removed_nodes: Some(2),
            diagnostic: None,
        });
        let mut update = test_cycle("measured", 0, "replace");
        update.component_work = Some(ComponentWork([2, 1, 0, 0, 0, 0, 0]));
        update.retained_nodes = 7;
        update.validation_visits = 9;
        update.roc_work = attributed;
        update.roc_work[0] = RocWork {
            occurred: true,
            duration_ns: 7,
            ..RocWork::default()
        };
        cycle(update);
        let mut stale = test_cycle("measured", 1, "no_change");
        stale.component_work = Some(ComponentWork::default());
        stale.roc_work[0] = RocWork {
            occurred: true,
            duration_ns: 3,
            ..RocWork::default()
        };
        cycle(stale);
        run_end(1, "pass", 2, None);
        finish("success").unwrap();
        let db = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        assert_eq!(
            db.query_row(
                "SELECT value FROM metadata WHERE key='clean_shutdown'",
                [],
                |row| row.get::<_, String>(0)
            )
            .unwrap(),
            "1"
        );
        for key in ["requested_detail", "effective_detail"] {
            assert_eq!(
                db.query_row("SELECT value FROM metadata WHERE key=?1", [key], |row| {
                    row.get::<_, String>(0)
                })
                .unwrap(),
                "summary"
            );
        }
        assert_eq!(
            db.query_row("SELECT count(*) FROM steps", [], |row| row.get::<_, i64>(0))
                .unwrap(),
            1
        );
        assert_eq!(
            db.query_row("SELECT count(*) FROM component_work_counts", [], |row| row
                .get::<_, i64>(
                0
            ))
            .unwrap(),
            2
        );
        assert_eq!(
            db.query_row(
                "SELECT count(*) FROM cycles WHERE component_work_recorded=1",
                [],
                |row| row.get::<_, i64>(0)
            )
            .unwrap(),
            2
        );
        assert_eq!(db.query_row("SELECT count(*) FROM component_work_assertions WHERE expected_count=observed_count", [], |row| row.get::<_, i64>(0)).unwrap(), 3);
        let mut component_report = db
            .prepare(include_str!(
                "../../../scripts/stats_queries/component_work.sql"
            ))
            .unwrap();
        let counts = component_report
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, Option<i64>>(4)?,
                ))
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(counts.len(), COMPONENT_WORK_NAMES.len());
        assert_eq!(counts[0], ("complete".into(), "rendered".into(), Some(2)));
        assert_eq!(counts[2], ("complete".into(), "skipped".into(), Some(0)));
        drop(component_report);
        assert_eq!(
            db.query_row(
                include_str!("../../../scripts/stats_queries/host_gpui_work.sql"),
                [],
                |row| Ok((row.get::<_, i64>(12)?, row.get::<_, i64>(13)?))
            )
            .unwrap(),
            (7, 10)
        );
        assert_eq!(
            db.query_row("SELECT count(*) FROM roc_work_spans", [], |row| row
                .get::<_, i64>(0))
                .unwrap(),
            4,
            "absent render/lowering work must not be persisted as zero-valued occurrence"
        );
        assert_eq!(
            db.query_row(
                "SELECT count(*) FROM roc_work_spans WHERE kind='platform_lowering'",
                [],
                |row| row.get::<_, i64>(0)
            )
            .unwrap(),
            0
        );
        let roc_work_query = include_str!("../../../scripts/stats_queries/roc_work.sql");
        let mut report = db.prepare(roc_work_query).unwrap();
        let rows = report
            .query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(13)?))
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(
            rows,
            vec![
                ("complete".into(), Some("application_render".into())),
                ("complete".into(), Some("component_comparison".into())),
                ("complete".into(), Some("routing".into()))
            ]
        );
        assert_eq!(
            db.query_row(
                "SELECT expected_staged_nodes=observed_staged_nodes AND expected_removed_nodes=observed_removed_nodes FROM steps",
                [],
                |row| row.get::<_, i64>(0)
            )
            .unwrap(),
            1
        );
        assert_eq!(
            db.query_row("SELECT transactions FROM recorder_health", [], |row| {
                row.get::<_, i64>(0)
            })
            .unwrap(),
            1,
            "a short capture should be committed as one batch"
        );
        assert_eq!(
            db.query_row(
                "SELECT end_roc_alloc_calls-start_roc_alloc_calls, end_roc_alloc_requested_bytes-start_roc_alloc_requested_bytes, end_roc_dealloc_calls-start_roc_dealloc_calls, end_roc_realloc_calls-start_roc_realloc_calls, end_roc_realloc_requested_bytes-start_roc_realloc_requested_bytes FROM runs WHERE id=1",
                [],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?, row.get::<_, i64>(2)?, row.get::<_, i64>(3)?, row.get::<_, i64>(4)?)),
            )
            .unwrap(),
            (2, 96, 2, 2, 176)
        );
        assert_eq!(
            db.query_row(
                "SELECT status FROM measurement_status WHERE name='process_resources'",
                [],
                |row| row.get::<_, String>(0),
            )
            .unwrap(),
            "complete"
        );
        let process_resources_query =
            include_str!("../../../scripts/stats_queries/process_resources.sql");
        let mut process_resources = db.prepare(process_resources_query).unwrap();
        assert_eq!(
            process_resources.column_names(),
            [
                "evidence_status",
                "evidence_reason",
                "runs",
                "cpu_user_ns",
                "cpu_system_ns",
                "peak_rss_bytes",
                "startup_decomposition",
            ],
            "the resource report must not derive run-level deltas from raw current-RSS snapshots"
        );
        assert!(
            process_resources
                .query([])
                .unwrap()
                .next()
                .unwrap()
                .is_some()
        );
        for key in [
            "executable_hash",
            "cpu_model",
            "logical_cpu_count",
            "kernel_release",
            "page_size_bytes",
        ] {
            assert!(
                !db.query_row("SELECT value FROM metadata WHERE key=?1", [key], |row| {
                    row.get::<_, String>(0)
                },)
                    .unwrap()
                    .is_empty()
            );
        }
        assert!(!active());
        // Windows cannot delete a database that still has open handles.
        drop(process_resources);
        drop(report);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn benchmark_without_patch_contract_records_only_scale_verification() {
        let _guard = RECORDER_TEST.lock().unwrap();
        let path = std::env::temp_dir().join(format!(
            "roc-gui-observatory-status-{}-{}.rgstats",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        start(Config {
            path: path.clone(),
            detail: Detail::Summary,
            buffer_mib: 1,
            max_mib: 16,
            backend: "semantic-headless",
            app_name: "test".into(),
            spec_name: Some("benchmark-without-patch-contract".into()),
            spec_hash: Some(stable_hash(b"benchmark-without-patch-contract")),
            benchmark: Some((1, 1, 1, 0, 1, 1)),
            job_count: 1,
            patch_expected: false,
        })
        .unwrap();
        run_start(1, "sample", Some(0), 0, 1);
        step(StepResult {
            run_id: 1,
            ordinal: 0,
            source_line: 1,
            kind: "expect-count",
            role: "assertion",
            status: "pass",
            duration_ns: None,
            expected_count: Some(10),
            observed_count: Some(10),
            audio_counters: None,
            clipboard_counters: None,
            sqlite_counters: None,
            http_counters: None,
            tcp_counters: None,
            component_work: None,
            expected_patch_kind: None,
            observed_patch_kind: None,
            expected_staged_nodes: None,
            observed_staged_nodes: None,
            expected_removed_nodes: None,
            observed_removed_nodes: None,
            diagnostic: None,
        });
        run_end(1, "pass", 2, None);
        finish("success").unwrap();

        let db = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let status = |name| {
            db.query_row(
                "SELECT status, reason, rows_recorded FROM measurement_status WHERE name=?1",
                [name],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, i64>(2)?,
                    ))
                },
            )
            .unwrap()
        };
        assert_eq!(
            status("scale_verification"),
            (
                "complete".into(),
                "capture finalized without recorded loss".into(),
                1,
            )
        );
        assert_eq!(
            status("patch_verification"),
            (
                "not_recorded".into(),
                "case declares no expect-patch contract".into(),
                0,
            )
        );
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}
