use rusqlite::{Connection, OpenFlags, params};
use std::{
    cell::RefCell,
    fs::OpenOptions,
    path::{Path, PathBuf},
    sync::{
        Arc, OnceLock,
        atomic::{AtomicU64, Ordering},
        mpsc::{Receiver, SyncSender, TrySendError, sync_channel},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub const SCHEMA_VERSION: u32 = 1;
static CLOCK_ORIGIN: OnceLock<Instant> = OnceLock::new();

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
    pub benchmark: Option<(u32, u32, u32, u64)>,
}

#[derive(Clone, Debug)]
pub struct Cycle {
    pub run_id: i64,
    pub ordinal: u64,
    pub trigger: &'static str,
    pub patch_kind: &'static str,
    pub duration_ns: u64,
    pub roc_callback_ns: u64,
    pub validate_ns: u64,
    pub apply_ns: u64,
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
    pub diagnostic: Option<String>,
}

enum Event {
    RunStart {
        id: i64,
        phase: &'static str,
        sample: Option<u32>,
        iteration: u32,
        started_ns: u64,
    },
    RunEnd {
        id: i64,
        outcome: &'static str,
        ended_ns: u64,
        diagnostic: Option<String>,
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

thread_local! {
    static RECORDER: RefCell<Option<Recorder>> = const { RefCell::new(None) };
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
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("fnv1a64:{hash:016x}")
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
        .checked_div(std::mem::size_of::<Event>().max(1))
        .unwrap_or(0)
        .max(64);
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
            RECORDER.with(|slot| {
                assert!(slot.borrow().is_none(), "stats recorder started twice");
                *slot.borrow_mut() = Some(Recorder {
                    sender,
                    omitted,
                    pending,
                    high_water,
                    join,
                });
            });
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

fn submit(event: Event) {
    RECORDER.with(|slot| {
        if let Some(recorder) = slot.borrow().as_ref() {
            let pending = recorder.pending.fetch_add(1, Ordering::Relaxed) + 1;
            recorder.high_water.fetch_max(pending, Ordering::Relaxed);
            match recorder.sender.try_send(event) {
                Ok(()) => {}
                Err(TrySendError::Full(_)) | Err(TrySendError::Disconnected(_)) => {
                    recorder.pending.fetch_sub(1, Ordering::Relaxed);
                    recorder.omitted.fetch_add(1, Ordering::Relaxed);
                }
            }
        }
    });
}

pub fn active() -> bool {
    RECORDER.with(|slot| slot.borrow().is_some())
}

pub fn run_start(
    id: i64,
    phase: &'static str,
    sample: Option<u32>,
    iteration: u32,
    started_ns: u64,
) {
    submit(Event::RunStart {
        id,
        phase,
        sample,
        iteration,
        started_ns,
    });
}

pub fn run_end(id: i64, outcome: &'static str, ended_ns: u64, diagnostic: Option<String>) {
    submit(Event::RunEnd {
        id,
        outcome,
        ended_ns,
        diagnostic,
    });
}

pub fn step(result: StepResult) {
    submit(Event::Step(result));
}

pub fn cycle(cycle: Cycle) {
    submit(Event::Cycle(cycle));
}

pub fn finish(application_outcome: &'static str) -> Result<(), String> {
    RECORDER.with(|slot| {
        let Some(recorder) = slot.borrow_mut().take() else {
            return Ok(());
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
    })
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

    while let Ok(first) = receiver.recv() {
        let transaction = connection
            .transaction()
            .map_err(|error| format!("stats transaction failed: {error}"))?;
        let mut events = vec![first];
        events.extend(receiver.try_iter().take(255));
        pending.fetch_sub(events.len() as u64, Ordering::Relaxed);
        let mut finish = None;
        for event in events {
            if let Event::Finish { .. } = event {
                finish = Some(event);
                break;
            }
            if output_limited {
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
        let output_bytes = database_bytes(&connection).unwrap_or(0);
        if output_bytes >= max_bytes {
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
    let benchmark = config.benchmark.unwrap_or((0, 0, 0, 0));
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
        ("host_os", std::env::consts::OS.into()),
        ("host_arch", std::env::consts::ARCH.into()),
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
        (
            "unavailable_sources",
            "gpu_timing,writer_thread_cpu_time".into(),
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
            "standard",
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
        } => connection.execute(
            "INSERT INTO runs(id,phase,sample_index,iteration_index,started_ns,outcome) VALUES(?1,?2,?3,?4,?5,'running')",
            params![id, phase, sample, iteration, as_i64(started_ns)],
        ),
        Event::RunEnd {
            id,
            outcome,
            ended_ns,
            diagnostic,
        } => connection.execute(
            "UPDATE runs SET ended_ns=?2,outcome=?3,diagnostic=?4 WHERE id=?1",
            params![id, as_i64(ended_ns), outcome, diagnostic],
        ),
        Event::Step(result) => connection.execute(
            "INSERT INTO steps(run_id,ordinal,source_line,kind,role,status,duration_ns,diagnostic) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)",
            params![result.run_id, result.ordinal as i64, result.source_line as i64, result.kind, result.role, result.status, result.duration_ns.map(as_i64), result.diagnostic],
        ),
        Event::Cycle(cycle) => connection.execute(
            "INSERT INTO cycles(run_id,ordinal,trigger,patch_kind,duration_ns,roc_callback_ns,validate_ns,apply_ns,staged_nodes,removed_nodes,live_nodes,parent_nodes_scanned) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)",
            params![cycle.run_id, as_i64(cycle.ordinal), cycle.trigger, cycle.patch_kind, as_i64(cycle.duration_ns), as_i64(cycle.roc_callback_ns), as_i64(cycle.validate_ns), as_i64(cycle.apply_ns), as_i64(cycle.staged_nodes), as_i64(cycle.removed_nodes), as_i64(cycle.live_nodes), as_i64(cycle.parent_nodes_scanned)],
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
    if omitted > 0 {
        connection.execute(
            "INSERT INTO recording_gaps(family,lost_count,reason) VALUES('writer_queue',?1,'bounded recorder admission refused events')",
            params![as_i64(omitted)],
        ).map_err(|error| format!("cannot write recording gap: {error}"))?;
    }
    let output_bytes = database_bytes(connection).unwrap_or(0);
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
        "UPDATE measurement_status SET status=CASE WHEN status IN ('not_recorded','unavailable') THEN status WHEN ?1 THEN 'partial' ELSE 'complete' END, reason=CASE WHEN status IN ('not_recorded','unavailable') THEN reason WHEN ?1 THEN 'recorder omitted events' ELSE 'capture finalized without recorded loss' END, omitted_events=?2, rows_recorded=CASE name WHEN 'test_outcome' THEN (SELECT count(*) FROM runs) WHEN 'step_results' THEN (SELECT count(*) FROM steps) WHEN 'host_cycles' THEN (SELECT count(*) FROM cycles) WHEN 'patch_accounting' THEN (SELECT count(*) FROM cycles) WHEN 'gpui_application' THEN (SELECT count(*) FROM cycles) ELSE 0 END",
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
    connection
        .execute(
            "UPDATE metadata SET value='complete' WHERE key='final_state'",
            [],
        )
        .map_err(|error| format!("cannot finalize state: {error}"))?;
    connection
        .execute(
            "UPDATE metadata SET value='1' WHERE key='clean_shutdown'",
            [],
        )
        .map_err(|error| format!("cannot mark clean shutdown: {error}"))?;
    connection
        .execute_batch("PRAGMA wal_checkpoint(TRUNCATE)")
        .map_err(|error| format!("cannot checkpoint {}: {error}", path.display()))?;
    Ok(())
}

fn database_bytes(connection: &Connection) -> rusqlite::Result<u64> {
    let pages: i64 = connection.query_row("PRAGMA page_count", [], |row| row.get(0))?;
    let page_size: i64 = connection.query_row("PRAGMA page_size", [], |row| row.get(0))?;
    Ok((pages.max(0) as u64).saturating_mul(page_size.max(0) as u64))
}

fn as_i64(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

const SCHEMA: &str = r#"
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA user_version=1;
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
    diagnostic TEXT
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
    diagnostic TEXT,
    UNIQUE(run_id,ordinal)
);
CREATE TABLE cycles(
    id INTEGER PRIMARY KEY,
    run_id INTEGER NOT NULL REFERENCES runs(id),
    ordinal INTEGER NOT NULL,
    trigger TEXT NOT NULL,
    patch_kind TEXT NOT NULL CHECK(patch_kind IN ('mount','no_change','replace')),
    duration_ns INTEGER NOT NULL,
    roc_callback_ns INTEGER NOT NULL,
    validate_ns INTEGER NOT NULL,
    apply_ns INTEGER NOT NULL,
    staged_nodes INTEGER NOT NULL,
    removed_nodes INTEGER NOT NULL,
    live_nodes INTEGER NOT NULL,
    parent_nodes_scanned INTEGER NOT NULL,
    UNIQUE(run_id,ordinal)
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
        step(StepResult {
            run_id: 1,
            ordinal: 0,
            source_line: 1,
            kind: "expect-visible",
            role: "assertion",
            status: "pass",
            duration_ns: None,
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
        std::fs::remove_file(path).unwrap();
    }
}
