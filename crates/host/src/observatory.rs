use rusqlite::{Connection, OpenFlags, params};
use sha2::{Digest, Sha256};
use std::{
    fs::{File, OpenOptions},
    io::Read,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc::{Receiver, RecvTimeoutError, SyncSender, sync_channel},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub const SCHEMA_VERSION: u32 = 2;
static CLOCK_ORIGIN: OnceLock<Instant> = OnceLock::new();
// This process-wide flag is the hot-path gate. The recorder mutex and its
// queue are only consulted after this overwhelmingly predictable branch.
static ENABLED: AtomicBool = AtomicBool::new(false);
static ROC_ALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ROC_ALLOC_REQUESTED_BYTES: AtomicU64 = AtomicU64::new(0);
static ROC_DEALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ROC_REALLOC_CALLS: AtomicU64 = AtomicU64::new(0);
static ROC_REALLOC_REQUESTED_BYTES: AtomicU64 = AtomicU64::new(0);
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
    Standard,
    Full,
}

impl Detail {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "summary" => Some(Self::Summary),
            "standard" => Some(Self::Standard),
            "full" => Some(Self::Full),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Summary => "summary",
            Self::Standard => "standard",
            Self::Full => "full",
        }
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
    Step(StepResult),
    Cycle(Cycle),
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
    }
}

pub fn note_roc_dealloc() {
    if ENABLED.load(Ordering::Relaxed) {
        ROC_DEALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
    }
}

pub fn note_roc_realloc(requested_bytes: usize) {
    if ENABLED.load(Ordering::Relaxed) {
        ROC_REALLOC_CALLS.fetch_add(1, Ordering::Relaxed);
        ROC_REALLOC_REQUESTED_BYTES.fetch_add(requested_bytes as u64, Ordering::Relaxed);
    }
}

fn resource_snapshot() -> ResourceSnapshot {
    let (cpu_user_ns, cpu_system_ns, max_rss_bytes) = process_resources();
    ResourceSnapshot {
        cpu_user_ns,
        cpu_system_ns,
        max_rss_bytes,
        roc_alloc_calls: ROC_ALLOC_CALLS.load(Ordering::Relaxed),
        roc_alloc_requested_bytes: ROC_ALLOC_REQUESTED_BYTES.load(Ordering::Relaxed),
        roc_dealloc_calls: ROC_DEALLOC_CALLS.load(Ordering::Relaxed),
        roc_realloc_calls: ROC_REALLOC_CALLS.load(Ordering::Relaxed),
        roc_realloc_requested_bytes: ROC_REALLOC_REQUESTED_BYTES.load(Ordering::Relaxed),
    }
}

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
    // Linux reports ru_maxrss in KiB.
    (
        timeval_ns(usage.ru_utime),
        timeval_ns(usage.ru_stime),
        (usage.ru_maxrss.max(0) as u64).saturating_mul(1024),
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
    submit(Event::Step(result), true);
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
    submit(Event::Cycle(cycle), false);
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
            if output_limited && matches!(event, Event::Cycle(_)) {
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
    let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    let metadata = [
        ("schema_version", SCHEMA_VERSION.to_string()),
        ("clean_shutdown", "0".into()),
        ("final_state", "recording".into()),
        ("requested_detail", config.detail.as_str().into()),
        // Schema v2 has one event family. Preserve the request for forward
        // compatibility, but do not claim that currently identical levels
        // changed what was captured.
        ("effective_detail", "summary".into()),
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
            "gpu_timing,writer_thread_cpu_time,roc_live_allocation_bytes,roc_compiler_version,application_revision".into(),
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
            "patch_accounting",
            "summary",
            "unfinalized",
            "capture has not finalized",
        ),
        (
            "gpui_application",
            "summary",
            if config.backend == "gpui-wayland" {
                "unfinalized"
            } else {
                "not_recorded"
            },
            if config.backend == "gpui-wayland" {
                "capture has not finalized"
            } else {
                "semantic headless execution does not instantiate GPUI views"
            },
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
            "INSERT INTO runs(id,phase,sample_index,iteration_index,started_ns,outcome,start_cpu_user_ns,start_cpu_system_ns,start_max_rss_bytes,start_roc_alloc_calls,start_roc_alloc_requested_bytes,start_roc_dealloc_calls,start_roc_realloc_calls,start_roc_realloc_requested_bytes) VALUES(?1,?2,?3,?4,?5,'running',?6,?7,?8,?9,?10,?11,?12,?13)",
            params![id, phase, sample, iteration, as_i64(started_ns), as_i64(resources.cpu_user_ns), as_i64(resources.cpu_system_ns), as_i64(resources.max_rss_bytes), as_i64(resources.roc_alloc_calls), as_i64(resources.roc_alloc_requested_bytes), as_i64(resources.roc_dealloc_calls), as_i64(resources.roc_realloc_calls), as_i64(resources.roc_realloc_requested_bytes)],
        ),
        Event::RunEnd {
            id,
            outcome,
            ended_ns,
            diagnostic,
            resources,
        } => connection.execute(
            "UPDATE runs SET ended_ns=?2,outcome=?3,diagnostic=?4,end_cpu_user_ns=?5,end_cpu_system_ns=?6,end_max_rss_bytes=?7,end_roc_alloc_calls=?8,end_roc_alloc_requested_bytes=?9,end_roc_dealloc_calls=?10,end_roc_realloc_calls=?11,end_roc_realloc_requested_bytes=?12 WHERE id=?1",
            params![id, as_i64(ended_ns), outcome, diagnostic, as_i64(resources.cpu_user_ns), as_i64(resources.cpu_system_ns), as_i64(resources.max_rss_bytes), as_i64(resources.roc_alloc_calls), as_i64(resources.roc_alloc_requested_bytes), as_i64(resources.roc_dealloc_calls), as_i64(resources.roc_realloc_calls), as_i64(resources.roc_realloc_requested_bytes)],
        ),
        Event::Step(result) => connection.execute(
            "INSERT INTO steps(run_id,ordinal,source_line,kind,role,status,duration_ns,expected_count,observed_count,diagnostic) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)",
            params![result.run_id, result.ordinal as i64, result.source_line as i64, result.kind, result.role, result.status, result.duration_ns.map(as_i64), result.expected_count.map(as_i64), result.observed_count.map(as_i64), result.diagnostic],
        ),
        Event::Cycle(cycle) => connection.execute(
            "INSERT INTO cycles(run_id,ordinal,step_ordinal,measurement_phase,trigger,patch_kind,duration_ns,roc_callback_ns,validate_ns,apply_ns,graph_apply_ns,gpui_apply_ns,staged_nodes,removed_nodes,live_nodes,parent_nodes_scanned) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
            params![cycle.run_id, as_i64(cycle.ordinal), cycle.step_ordinal.map(|value| value as i64), cycle.measurement_phase, cycle.trigger, cycle.patch_kind, as_i64(cycle.duration_ns), as_i64(cycle.roc_callback_ns), as_i64(cycle.validate_ns), as_i64(cycle.apply_ns), as_i64(cycle.graph_apply_ns), cycle.gpui_apply_ns.map(as_i64), as_i64(cycle.staged_nodes), as_i64(cycle.removed_nodes), as_i64(cycle.live_nodes), as_i64(cycle.parent_nodes_scanned)],
        ),
        Event::Finish { .. } => return Err("internal recorder finalization ordering error".into()),
    }
    .map(|_| ())
    .map_err(|error| format!("cannot write stats row: {error}"))
}

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
        "UPDATE measurement_status SET status=CASE WHEN status IN ('not_recorded','unavailable') THEN status WHEN ?1 THEN 'partial' ELSE 'complete' END, reason=CASE WHEN status IN ('not_recorded','unavailable') THEN reason WHEN ?1 THEN 'recorder omitted events' ELSE 'capture finalized without recorded loss' END, omitted_events=?2, rows_recorded=CASE name WHEN 'test_outcome' THEN (SELECT count(*) FROM runs) WHEN 'step_results' THEN (SELECT count(*) FROM steps) WHEN 'host_cycles' THEN (SELECT count(*) FROM cycles) WHEN 'patch_accounting' THEN (SELECT count(*) FROM cycles) WHEN 'gpui_application' THEN (SELECT count(*) FROM cycles) WHEN 'process_resources' THEN (SELECT count(*) FROM runs WHERE ended_ns IS NOT NULL) WHEN 'roc_allocations' THEN (SELECT count(*) FROM runs WHERE ended_ns IS NOT NULL) WHEN 'scale_verification' THEN (SELECT count(*) FROM steps WHERE expected_count IS NOT NULL AND expected_count=observed_count) ELSE 0 END",
        params![partial, as_i64(omitted)],
    ).map_err(|error| format!("cannot finalize measurement status: {error}"))?;
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
PRAGMA user_version=2;
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
    diagnostic TEXT,
    UNIQUE(run_id,ordinal)
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
    UNIQUE(run_id,ordinal),
    FOREIGN KEY(run_id,step_ordinal) REFERENCES steps(run_id,ordinal)
);
CREATE TABLE recording_gaps(
    id INTEGER PRIMARY KEY,
    family TEXT NOT NULL,
    lost_count INTEGER NOT NULL,
    reason TEXT NOT NULL
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
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stable_hash_is_repeatable() {
        assert_eq!(stable_hash(b"abc"), stable_hash(b"abc"));
        assert_ne!(stable_hash(b"abc"), stable_hash(b"abd"));
    }

    #[test]
    fn creates_and_finalizes_capture() {
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
            detail: Detail::Standard,
            buffer_mib: 1,
            max_mib: 16,
            backend: "semantic-headless",
            app_name: "test".into(),
            spec_name: Some("case".into()),
            spec_hash: Some(stable_hash(b"case")),
            benchmark: None,
        })
        .unwrap();
        run_start(1, "test", None, 0, 1);
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
            diagnostic: None,
        });
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
        assert_eq!(
            db.query_row("SELECT count(*) FROM steps", [], |row| row.get::<_, i64>(0))
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
            (1, 64, 1, 1, 128)
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
        for key in [
            "executable_hash",
            "cpu_model",
            "logical_cpu_count",
            "kernel_release",
            "page_size_bytes",
        ] {
            assert!(
                db.query_row("SELECT value FROM metadata WHERE key=?1", [key], |row| {
                    row.get::<_, String>(0)
                },)
                    .unwrap()
                    .len()
                    > 0
            );
        }
        assert!(!active());
        std::fs::remove_file(path).unwrap();
    }
}
