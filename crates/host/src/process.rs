use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    fs::File,
    io::{Read, Write},
    mem::ManuallyDrop,
    os::fd::{AsRawFd, FromRawFd},
    process::{Child, Command, Stdio},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};

const MAX_ACTIVE: usize = 64;
const MAX_IO_BYTES: usize = 65_536;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GrantedProfile {
    LocalShell,
    TestProgram,
}

struct Pty {
    master: Mutex<File>,
    child: Mutex<Child>,
    canceled: AtomicBool,
    exited: AtomicBool,
    reading: AtomicBool,
}

struct Store {
    next: u64,
    configured: Option<GrantedProfile>,
    grants: HashMap<u64, GrantedProfile>,
    ptys: HashMap<u64, Arc<Pty>>,
    grant_allocations: HashMap<usize, u64>,
    pty_allocations: HashMap<usize, u64>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static SPAWNED: AtomicU64 = AtomicU64::new(0);
static READ_BYTES: AtomicU64 = AtomicU64::new(0);
static WRITTEN_BYTES: AtomicU64 = AtomicU64::new(0);
static CANCELED: AtomicU64 = AtomicU64::new(0);

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            configured: None,
            grants: HashMap::new(),
            ptys: HashMap::new(),
            grant_allocations: HashMap::new(),
            pty_allocations: HashMap::new(),
        })
    })
}

pub fn configure(profile: Option<GrantedProfile>) {
    store().lock().expect("process store poisoned").configured = profile;
}

fn allocate_handle(id: u64) -> (*mut u64, usize) {
    let handle = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            core::mem::align_of::<u64>(),
            false,
            roc_host(),
        ) as *mut u64
    };
    unsafe { handle.write(id) };
    let base = unsafe { (handle as *mut u8).sub(core::mem::size_of::<isize>()) } as usize;
    (handle, base)
}

fn next_id(guard: &mut Store) -> u64 {
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("process resource ids exhausted");
    id
}

type Reason =
    AccessDeniedOrBusyOrExitedOrInvalidCapabilityOrInvalidSizeOrIoOrResourceLimitOrUnsupported;
type Error = AcquireProcessErrOrCancelProcessErrOrReadProcessErrOrResizeProcessErrOrSpawnProcessErrOrWriteProcessErr;
type ErrorPayload = AcquireProcessErrOrCancelProcessErrOrReadProcessErrOrResizeProcessErrOrSpawnProcessErrOrWriteProcessErrPayload;
type ErrorTag = AcquireProcessErrOrCancelProcessErrOrReadProcessErrOrResizeProcessErrOrSpawnProcessErrOrWriteProcessErrTag;

fn error(tag: ErrorTag, reason: Reason) -> Error {
    let payload = match tag {
        ErrorTag::AcquireProcessErr => ErrorPayload {
            acquire_process_err: ManuallyDrop::new(reason),
        },
        ErrorTag::CancelProcessErr => ErrorPayload {
            cancel_process_err: ManuallyDrop::new(reason),
        },
        ErrorTag::ReadProcessErr => ErrorPayload {
            read_process_err: ManuallyDrop::new(reason),
        },
        ErrorTag::ResizeProcessErr => ErrorPayload {
            resize_process_err: ManuallyDrop::new(reason),
        },
        ErrorTag::SpawnProcessErr => ErrorPayload {
            spawn_process_err: ManuallyDrop::new(reason),
        },
        ErrorTag::WriteProcessErr => ErrorPayload {
            write_process_err: ManuallyDrop::new(reason),
        },
    };
    Error { payload, tag }
}

fn valid_size(columns: u16, rows: u16) -> bool {
    (1..=4096).contains(&columns) && (1..=4096).contains(&rows)
}

fn grant_profile(handle: *mut u64) -> Option<GrantedProfile> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.grants.get(&id).copied()
}

fn lookup(handle: *mut u64) -> Option<Arc<Pty>> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.ptys.get(&id).cloned()
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_acquire() -> HostGlueProcessAcquireResult {
    let mut guard = store().lock().expect("process store poisoned");
    let Some(profile) = guard.configured else {
        return HostGlueProcessAcquireResult {
            payload: HostGlueProcessAcquireResultPayload {
                err: ManuallyDrop::new(error(ErrorTag::AcquireProcessErr, Reason::AccessDenied)),
            },
            tag: HostGlueProcessAcquireResultTag::Err,
        };
    };
    let id = next_id(&mut guard);
    let (handle, base) = allocate_handle(id);
    guard.grants.insert(id, profile);
    guard.grant_allocations.insert(base, id);
    HostGlueProcessAcquireResult {
        payload: HostGlueProcessAcquireResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: HostGlueProcessAcquireResultTag::Ok,
    }
}

fn open_pty(columns: u16, rows: u16, profile: GrantedProfile) -> std::io::Result<Pty> {
    let size = libc::winsize {
        ws_row: rows,
        ws_col: columns,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let mut master = -1;
    let mut slave = -1;
    if unsafe {
        libc::openpty(
            &mut master,
            &mut slave,
            std::ptr::null_mut(),
            std::ptr::null(),
            &size,
        )
    } != 0
    {
        return Err(std::io::Error::last_os_error());
    }
    let master_file = unsafe { File::from_raw_fd(master) };
    let slave_file = unsafe { File::from_raw_fd(slave) };
    let input = slave_file.try_clone()?;
    let output = slave_file.try_clone()?;
    let mut command = Command::new("/bin/sh");
    match profile {
        GrantedProfile::LocalShell => {
            command.arg("-i");
        }
        GrantedProfile::TestProgram => {
            command.args(["-c", "printf 'terminal-ready\\n'; while IFS= read -r line; do case \"$line\" in exit) printf 'terminal-bye\\n'; exit 0;; hang) while :; do sleep 1; done;; lines:*) n=${line#lines:}; i=1; while [ $i -le $n ]; do printf 'line-%06d\\n' $i; i=$((i+1)); done;; fail) printf 'fixture-error\\n' >&2; exit 7;; *) printf 'echo:%s\\n' \"$line\";; esac; done"]);
        }
    }
    command
        .env_clear()
        .env("TERM", "xterm-256color")
        .env("PATH", "/usr/bin:/bin")
        .stdin(Stdio::from(input))
        .stdout(Stdio::from(output))
        .stderr(Stdio::from(slave_file));
    use std::os::unix::process::CommandExt;
    unsafe {
        command.pre_exec(move || {
            if libc::setsid() < 0 {
                return Err(std::io::Error::last_os_error());
            }
            if libc::ioctl(0, libc::TIOCSCTTY as _, 0) < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let child = command.spawn()?;
    Ok(Pty {
        master: Mutex::new(master_file),
        child: Mutex::new(child),
        canceled: AtomicBool::new(false),
        exited: AtomicBool::new(false),
        reading: AtomicBool::new(false),
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_spawn(
    grant: *mut u64,
    config: AnonStructD5ea40ae766362a5,
) -> HostGlueProcessSpawnResult {
    let granted = grant_profile(grant);
    unsafe { decref_box(grant as RocBox, roc_host()) };
    let requested = match config.profile {
        LocalShellOrTestProgram::LocalShell => GrantedProfile::LocalShell,
        LocalShellOrTestProgram::TestProgram => GrantedProfile::TestProgram,
    };
    let failure = if granted.is_none() {
        Some(Reason::InvalidCapability)
    } else if granted != Some(requested) {
        Some(Reason::AccessDenied)
    } else if !valid_size(config.columns, config.rows) {
        Some(Reason::InvalidSize)
    } else if active_count() >= MAX_ACTIVE {
        Some(Reason::ResourceLimit)
    } else {
        None
    };
    let result = failure.map(Err).unwrap_or_else(|| {
        open_pty(config.columns, config.rows, requested).map_err(|_| Reason::Io)
    });
    match result {
        Err(reason) => HostGlueProcessSpawnResult {
            payload: HostGlueProcessSpawnResultPayload {
                err: ManuallyDrop::new(error(ErrorTag::SpawnProcessErr, reason)),
            },
            tag: HostGlueProcessSpawnResultTag::Err,
        },
        Ok(pty) => {
            let mut guard = store().lock().expect("process store poisoned");
            let id = next_id(&mut guard);
            let (handle, base) = allocate_handle(id);
            guard.ptys.insert(id, Arc::new(pty));
            guard.pty_allocations.insert(base, id);
            SPAWNED.fetch_add(1, Ordering::Relaxed);
            HostGlueProcessSpawnResult {
                payload: HostGlueProcessSpawnResultPayload {
                    ok: ManuallyDrop::new(handle),
                },
                tag: HostGlueProcessSpawnResultTag::Ok,
            }
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_read(handle: *mut u64, max_bytes: u32) -> HostGlueProcessReadResult {
    let pty = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some(pty) = pty else {
        return read_err(Reason::InvalidCapability);
    };
    if max_bytes == 0 || max_bytes as usize > MAX_IO_BYTES {
        return read_err(Reason::ResourceLimit);
    }
    if pty.reading.swap(true, Ordering::AcqRel) {
        return read_err(Reason::Busy);
    }
    struct Reading<'a>(&'a AtomicBool);
    impl Drop for Reading<'_> {
        fn drop(&mut self) {
            self.0.store(false, Ordering::Release);
        }
    }
    let _reading = Reading(&pty.reading);
    let fd = pty.master.lock().expect("pty master poisoned").as_raw_fd();
    let mut collected = Vec::with_capacity(max_bytes as usize);
    loop {
        if pty.canceled.load(Ordering::Acquire) {
            return read_ok(CanceledOrDataOrEndOfFile {
                payload: CanceledOrDataOrEndOfFilePayload { canceled: [] },
                tag: CanceledOrDataOrEndOfFileTag::Canceled,
            });
        }
        let mut descriptor = libc::pollfd {
            fd,
            events: libc::POLLIN | libc::POLLHUP,
            revents: 0,
        };
        let polled = unsafe {
            libc::poll(
                &mut descriptor,
                1,
                if collected.is_empty() { 20 } else { 20 },
            )
        };
        if polled < 0 {
            return read_err(Reason::Io);
        }
        if polled == 0 {
            if collected.is_empty() {
                continue;
            }
            READ_BYTES.fetch_add(collected.len() as u64, Ordering::Relaxed);
            return read_ok(CanceledOrDataOrEndOfFile {
                payload: CanceledOrDataOrEndOfFilePayload {
                    data: ManuallyDrop::new(unsafe {
                        RocListWith::<u8, false>::from_slice(&collected, roc_host())
                    }),
                },
                tag: CanceledOrDataOrEndOfFileTag::Data,
            });
        }
        let mut bytes = vec![0; (max_bytes as usize - collected.len()).min(8192)];
        match pty
            .master
            .lock()
            .expect("pty master poisoned")
            .read(&mut bytes)
        {
            Ok(0) if collected.is_empty() => {
                pty.exited.store(true, Ordering::Release);
                return read_ok(CanceledOrDataOrEndOfFile {
                    payload: CanceledOrDataOrEndOfFilePayload { end_of_file: [] },
                    tag: CanceledOrDataOrEndOfFileTag::EndOfFile,
                });
            }
            Ok(0) => {}
            Ok(count) => {
                collected.extend_from_slice(&bytes[..count]);
                if collected.len() == max_bytes as usize {
                    READ_BYTES.fetch_add(collected.len() as u64, Ordering::Relaxed);
                    return read_ok(CanceledOrDataOrEndOfFile {
                        payload: CanceledOrDataOrEndOfFilePayload {
                            data: ManuallyDrop::new(unsafe {
                                RocListWith::<u8, false>::from_slice(&collected, roc_host())
                            }),
                        },
                        tag: CanceledOrDataOrEndOfFileTag::Data,
                    });
                }
            }
            Err(error) if error.raw_os_error() == Some(libc::EIO) && collected.is_empty() => {
                pty.exited.store(true, Ordering::Release);
                return read_ok(CanceledOrDataOrEndOfFile {
                    payload: CanceledOrDataOrEndOfFilePayload { end_of_file: [] },
                    tag: CanceledOrDataOrEndOfFileTag::EndOfFile,
                });
            }
            Err(error) if error.raw_os_error() == Some(libc::EIO) => {
                READ_BYTES.fetch_add(collected.len() as u64, Ordering::Relaxed);
                return read_ok(CanceledOrDataOrEndOfFile {
                    payload: CanceledOrDataOrEndOfFilePayload {
                        data: ManuallyDrop::new(unsafe {
                            RocListWith::<u8, false>::from_slice(&collected, roc_host())
                        }),
                    },
                    tag: CanceledOrDataOrEndOfFileTag::Data,
                });
            }
            Err(_) => return read_err(Reason::Io),
        }
    }
}

fn read_err(reason: Reason) -> HostGlueProcessReadResult {
    HostGlueProcessReadResult {
        payload: HostGlueProcessReadResultPayload {
            err: ManuallyDrop::new(error(ErrorTag::ReadProcessErr, reason)),
        },
        tag: HostGlueProcessReadResultTag::Err,
    }
}
fn read_ok(value: CanceledOrDataOrEndOfFile) -> HostGlueProcessReadResult {
    HostGlueProcessReadResult {
        payload: HostGlueProcessReadResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostGlueProcessReadResultTag::Ok,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_write(
    handle: *mut u64,
    bytes: RocListWith<u8, false>,
) -> HostGlueProcessWriteResult {
    let owned = bytes.as_slice().to_vec();
    unsafe { bytes.decref(roc_host()) };
    let pty = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let result = match pty {
        None => Err(Reason::InvalidCapability),
        Some(_) if owned.len() > MAX_IO_BYTES => Err(Reason::ResourceLimit),
        Some(pty) if pty.canceled.load(Ordering::Acquire) || pty.exited.load(Ordering::Acquire) => {
            Err(Reason::Exited)
        }
        Some(pty) => pty
            .master
            .lock()
            .expect("pty master poisoned")
            .write(&owned)
            .map(|n| n as u32)
            .map_err(|_| Reason::Io),
    };
    match result {
        Ok(count) => {
            WRITTEN_BYTES.fetch_add(count as u64, Ordering::Relaxed);
            HostGlueProcessWriteResult {
                payload: HostGlueProcessWriteResultPayload {
                    ok: ManuallyDrop::new(count),
                },
                tag: HostGlueProcessWriteResultTag::Ok,
            }
        }
        Err(reason) => HostGlueProcessWriteResult {
            payload: HostGlueProcessWriteResultPayload {
                err: ManuallyDrop::new(error(ErrorTag::WriteProcessErr, reason)),
            },
            tag: HostGlueProcessWriteResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_resize(
    handle: *mut u64,
    size: AnonStruct93136bf334c2a2fc,
) -> HostGlueProcessResizeResult {
    let pty = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let result = match pty {
        None => Err(Reason::InvalidCapability),
        Some(_) if !valid_size(size.columns, size.rows) => Err(Reason::InvalidSize),
        Some(pty) if pty.canceled.load(Ordering::Acquire) => Err(Reason::Exited),
        Some(pty) => {
            let ws = libc::winsize {
                ws_row: size.rows,
                ws_col: size.columns,
                ws_xpixel: 0,
                ws_ypixel: 0,
            };
            if unsafe {
                libc::ioctl(
                    pty.master.lock().expect("pty master poisoned").as_raw_fd(),
                    libc::TIOCSWINSZ,
                    &ws,
                )
            } == 0
            {
                Ok(())
            } else {
                Err(Reason::Io)
            }
        }
    };
    match result {
        Ok(()) => HostGlueProcessResizeResult {
            payload: HostGlueProcessResizeResultPayload { ok: [] },
            tag: HostGlueProcessResizeResultTag::Ok,
        },
        Err(reason) => HostGlueProcessResizeResult {
            payload: HostGlueProcessResizeResultPayload {
                err: ManuallyDrop::new(error(ErrorTag::ResizeProcessErr, reason)),
            },
            tag: HostGlueProcessResizeResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_cancel(handle: *mut u64) -> HostGlueProcessCancelResult {
    let pty = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some(pty) = pty else {
        return HostGlueProcessCancelResult {
            payload: HostGlueProcessCancelResultPayload {
                err: ManuallyDrop::new(error(
                    ErrorTag::CancelProcessErr,
                    Reason::InvalidCapability,
                )),
            },
            tag: HostGlueProcessCancelResultTag::Err,
        };
    };
    let changed = !pty.exited.load(Ordering::Acquire) && !pty.canceled.swap(true, Ordering::AcqRel);
    if changed {
        let _ = pty.child.lock().expect("pty child poisoned").kill();
        CANCELED.fetch_add(1, Ordering::Relaxed);
    }
    HostGlueProcessCancelResult {
        payload: HostGlueProcessCancelResultPayload {
            ok: ManuallyDrop::new(if changed {
                AlreadyStoppedOrCanceled::Canceled
            } else {
                AlreadyStoppedOrCanceled::AlreadyStopped
            }),
        },
        tag: HostGlueProcessCancelResultTag::Ok,
    }
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let pty = {
        let mut guard = store().lock().expect("process store poisoned");
        let key = base as usize;
        if let Some(id) = guard.grant_allocations.remove(&key) {
            guard.grants.remove(&id);
        }
        guard
            .pty_allocations
            .remove(&key)
            .and_then(|id| guard.ptys.remove(&id))
    };
    if let Some(pty) = pty {
        pty.canceled.store(true, Ordering::Release);
        let _ = pty.child.lock().expect("pty child poisoned").kill();
    }
}

pub fn active_count() -> usize {
    let values: Vec<_> = store()
        .lock()
        .expect("process store poisoned")
        .ptys
        .values()
        .cloned()
        .collect();
    values
        .into_iter()
        .filter(|pty| {
            if pty.canceled.load(Ordering::Relaxed) || pty.exited.load(Ordering::Relaxed) {
                return false;
            }
            if pty
                .child
                .lock()
                .expect("pty child poisoned")
                .try_wait()
                .ok()
                .flatten()
                .is_some()
            {
                pty.exited.store(true, Ordering::Release);
                false
            } else {
                true
            }
        })
        .count()
}
pub fn counters() -> (u64, u64, u64, u64) {
    (
        SPAWNED.load(Ordering::Relaxed),
        READ_BYTES.load(Ordering::Relaxed),
        WRITTEN_BYTES.load(Ordering::Relaxed),
        CANCELED.load(Ordering::Relaxed),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_dimensions_are_bounded() {
        assert!(valid_size(1, 1));
        assert!(valid_size(4096, 4096));
        assert!(!valid_size(0, 24));
        assert!(!valid_size(80, 0));
        assert!(!valid_size(4097, 24));
    }

    #[test]
    fn counters_are_monotonic_snapshots() {
        let before = counters();
        let after = counters();
        assert!(
            after.0 >= before.0
                && after.1 >= before.1
                && after.2 >= before.2
                && after.3 >= before.3
        );
    }
}
