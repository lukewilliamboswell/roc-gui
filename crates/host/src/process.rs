use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};

const MAX_ACTIVE: usize = 64;
const MAX_IO_BYTES: usize = 65_536;
/// How long output carrying no program text is held back before it is
/// delivered anyway. Long enough to coalesce a terminal's own redraw with the
/// text that follows it, short enough that a drawing-only program still reads.
const CONTROL_HOLD: std::time::Duration = std::time::Duration::from_millis(500);
/// How long a read waits for more output before delivering what it holds.
///
/// A Windows pseudo console paints on its own frame timer and echoes a typed
/// line as its own frame, ahead of the reply the program writes; a gap as short
/// as a POSIX terminal's splits that echo from its reply, and a reader waiting
/// on one read sees neither. A window specification therefore waits for the
/// terminal in frames of its own rather than assuming one repaint covers it.
#[cfg(not(windows))]
const READ_IDLE_MS: u64 = 20;
#[cfg(windows)]
const READ_IDLE_MS: u64 = 60;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GrantedProfile {
    LocalShell,
    TestProgram,
}

struct Pty {
    terminal: sys::Terminal,
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

/// What a process grant may do: spawn a session, and derive that session from
/// itself. It never reads or writes — the PTY does.
const GRANT_RIGHTS: Rights = Rights::CONNECT.union(Rights::DERIVE);

/// What an open PTY may do.
const PTY_RIGHTS: Rights = Rights::READ.union(Rights::WRITE);

/// How a process grant arrives. The host chooses a fixed profile; nothing about
/// it is a person's decision, and the contract requires that be visible rather
/// than assumed.
const GRANT_ORIGIN: Origin = Origin::Provisioned;

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
    grant::forget_kind(grant::Kind::Process);
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
    AccessDeniedOrBusyOrExitedOrInvalidCapabilityOrInvalidSizeOrIoOrResourceLimitOrRevokedOrUnsupported;
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

/// The profile and the grant it was accepted against. `spawn` decrefs the grant
/// handle before the session exists, so the PTY is derived from the grant
/// accepted here rather than from a second lookup that would find nothing.
fn grant_profile(handle: *mut u64) -> Result<(GrantedProfile, grant::Grant), Reason> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(Reason::InvalidCapability)?;
    let entry = grant::accept(grant::Kind::Process, id, Rights::CONNECT).map_err(refusal)?;
    let profile = store()
        .lock()
        .ok()
        .and_then(|guard| guard.grants.get(&id).copied())
        .ok_or(Reason::InvalidCapability)?;
    Ok((profile, entry))
}

/// A withdrawn grant and an invalid handle are different facts about the
/// application, so they are different reasons rather than one.
fn refusal(refusal: grant::Refusal) -> Reason {
    match refusal {
        grant::Refusal::Revoked => Reason::Revoked,
        grant::Refusal::Unknown | grant::Refusal::Rights => Reason::InvalidCapability,
    }
}

fn lookup(handle: *mut u64) -> Result<Arc<Pty>, Reason> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(Reason::InvalidCapability)?;
    grant::accept(grant::Kind::Process, id, PTY_RIGHTS).map_err(refusal)?;
    store()
        .lock()
        .ok()
        .and_then(|guard| guard.ptys.get(&id).cloned())
        .ok_or(Reason::InvalidCapability)
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
    crate::register_resource_allocation(
        crate::resource_domain::PROCESS,
        &mut guard.grant_allocations,
        base,
        id,
    );
    drop(guard);
    grant::record_root(
        grant::Kind::Process,
        id,
        GRANT_RIGHTS,
        GRANT_ORIGIN,
        Lifetime::Session,
    );
    HostGlueProcessAcquireResult {
        payload: HostGlueProcessAcquireResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: HostGlueProcessAcquireResultTag::Ok,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_spawn(
    grant: *mut u64,
    config: AnonStruct93136bf334c2a2fc,
) -> HostGlueProcessSpawnResult {
    let accepted = grant_profile(grant);
    unsafe { decref_box(grant as RocBox, roc_host()) };
    let failure = if let Err(reason) = accepted {
        Some(reason)
    } else if !valid_size(config.columns, config.rows) {
        Some(Reason::InvalidSize)
    } else if active_count() >= MAX_ACTIVE {
        Some(Reason::ResourceLimit)
    } else {
        None
    };
    let result = failure.map(Err).unwrap_or_else(|| {
        sys::Terminal::spawn(
            config.columns,
            config.rows,
            accepted.expect("validated process grant").0,
        )
        .map(|terminal| Pty {
            terminal,
            canceled: AtomicBool::new(false),
            exited: AtomicBool::new(false),
            reading: AtomicBool::new(false),
        })
        .map_err(|_| Reason::Io)
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
            crate::register_resource_allocation(
                crate::resource_domain::PROCESS,
                &mut guard.pty_allocations,
                base,
                id,
            );
            drop(guard);
            if let Ok((_, parent)) = accepted {
                grant::record_descendant(grant::Kind::Process, id, PTY_RIGHTS, parent);
            }
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

fn data(collected: &[u8]) -> HostGlueProcessReadResult {
    READ_BYTES.fetch_add(collected.len() as u64, Ordering::Relaxed);
    read_ok(CanceledOrDataOrEndOfFile {
        payload: CanceledOrDataOrEndOfFilePayload {
            data: ManuallyDrop::new(unsafe {
                RocListWith::<u8, false>::from_slice(collected, roc_host())
            }),
        },
        tag: CanceledOrDataOrEndOfFileTag::Data,
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_process_read(handle: *mut u64, max_bytes: u32) -> HostGlueProcessReadResult {
    let pty = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let pty = match pty {
        Ok(pty) => pty,
        Err(reason) => return read_err(reason),
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
    let mut collected = Vec::with_capacity(max_bytes as usize);
    let mut held_since: Option<std::time::Instant> = None;
    loop {
        if pty.canceled.load(Ordering::Acquire) {
            return read_ok(CanceledOrDataOrEndOfFile {
                payload: CanceledOrDataOrEndOfFilePayload { canceled: [] },
                tag: CanceledOrDataOrEndOfFileTag::Canceled,
            });
        }
        match pty.terminal.wait_readable(READ_IDLE_MS) {
            Err(_) => return read_err(Reason::Io),
            Ok(false) if collected.is_empty() => continue,
            Ok(false) if !pty.terminal.worth_delivering(&collected) => {
                // A program may draw with control sequences alone and then wait
                // for input, so the hold ends on its own rather than keeping
                // output, and this thread, indefinitely.
                let since = *held_since.get_or_insert_with(std::time::Instant::now);
                if since.elapsed() >= CONTROL_HOLD {
                    return data(&collected);
                }
                continue;
            }
            Ok(false) => return data(&collected),
            Ok(true) => {}
        }
        let mut bytes = vec![0; (max_bytes as usize - collected.len()).min(8192)];
        match pty.terminal.read(&mut bytes) {
            // End of output: the terminal's last client exited and the
            // terminal released its side of the stream.
            Ok(0) if collected.is_empty() => {
                pty.exited.store(true, Ordering::Release);
                return read_ok(CanceledOrDataOrEndOfFile {
                    payload: CanceledOrDataOrEndOfFilePayload { end_of_file: [] },
                    tag: CanceledOrDataOrEndOfFileTag::EndOfFile,
                });
            }
            Ok(0) => return data(&collected),
            Ok(count) => {
                collected.extend_from_slice(&bytes[..count]);
                if collected.len() == max_bytes as usize {
                    return data(&collected);
                }
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
        Err(reason) => Err(reason),
        Ok(_) if owned.len() > MAX_IO_BYTES => Err(Reason::ResourceLimit),
        Ok(pty) if pty.canceled.load(Ordering::Acquire) || pty.exited.load(Ordering::Acquire) => {
            Err(Reason::Exited)
        }
        Ok(pty) => pty
            .terminal
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
        Err(reason) => Err(reason),
        Ok(_) if !valid_size(size.columns, size.rows) => Err(Reason::InvalidSize),
        Ok(pty) if pty.canceled.load(Ordering::Acquire) => Err(Reason::Exited),
        Ok(pty) => pty
            .terminal
            .resize(size.columns, size.rows)
            .map_err(|_| Reason::Io),
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
    let pty = match pty {
        Ok(pty) => pty,
        Err(reason) => {
            return HostGlueProcessCancelResult {
                payload: HostGlueProcessCancelResultPayload {
                    err: ManuallyDrop::new(error(ErrorTag::CancelProcessErr, reason)),
                },
                tag: HostGlueProcessCancelResultTag::Err,
            };
        }
    };
    let changed = !pty.exited.load(Ordering::Acquire) && !pty.canceled.swap(true, Ordering::AcqRel);
    if changed {
        pty.terminal.kill();
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
    let mut released = Vec::new();
    let pty = {
        let mut guard = store().lock().expect("process store poisoned");
        let key = base as usize;
        if let Some(id) = crate::remove_resource_allocation(&mut guard.grant_allocations, key) {
            guard.grants.remove(&id);
            released.push(id);
        }
        crate::remove_resource_allocation(&mut guard.pty_allocations, key).and_then(|id| {
            released.push(id);
            guard.ptys.remove(&id)
        })
    };
    for id in released {
        grant::release(grant::Kind::Process, id);
    }
    if let Some(pty) = pty {
        pty.canceled.store(true, Ordering::Release);
        pty.terminal.kill();
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
            if pty.terminal.has_exited() {
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

/// A kernel pseudo-terminal with `/bin/sh` attached as its session leader.
#[cfg(unix)]
mod sys {
    use super::GrantedProfile;
    use std::{
        fs::File,
        io::{self, Read, Write},
        os::fd::{AsRawFd, FromRawFd, RawFd},
        process::{Child, Command, Stdio},
        sync::Mutex,
    };

    pub struct Terminal {
        master: Mutex<File>,
        child: Mutex<Child>,
    }

    pub fn resize_fd(fd: RawFd, columns: u16, rows: u16) -> io::Result<()> {
        let size = libc::winsize {
            ws_row: rows,
            ws_col: columns,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        if unsafe { libc::ioctl(fd, libc::TIOCSWINSZ, &size) } == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }

    impl Terminal {
        pub fn spawn(columns: u16, rows: u16, profile: GrantedProfile) -> io::Result<Self> {
            // macOS declares openpty's size as `*mut`, Linux as `*const`.
            let mut size = libc::winsize {
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
                    std::ptr::null_mut(),
                    &raw mut size,
                )
            } != 0
            {
                return Err(io::Error::last_os_error());
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
                        return Err(io::Error::last_os_error());
                    }
                    if libc::ioctl(0, libc::TIOCSCTTY as _, 0) < 0 {
                        return Err(io::Error::last_os_error());
                    }
                    Ok(())
                });
            }
            let child = command.spawn()?;
            Ok(Self {
                master: Mutex::new(master_file),
                child: Mutex::new(child),
            })
        }

        pub fn wait_readable(&self, timeout_ms: u64) -> io::Result<bool> {
            let fd = self.master.lock().expect("pty master poisoned").as_raw_fd();
            let mut descriptor = libc::pollfd {
                fd,
                events: libc::POLLIN | libc::POLLHUP,
                revents: 0,
            };
            let polled = unsafe { libc::poll(&mut descriptor, 1, timeout_ms as i32) };
            if polled < 0 {
                Err(io::Error::last_os_error())
            } else {
                Ok(polled > 0)
            }
        }

        pub fn worth_delivering(&self, collected: &[u8]) -> bool {
            !collected.is_empty()
        }

        /// Linux reports a hung-up master as `EIO` rather than end of file.
        pub fn read(&self, bytes: &mut [u8]) -> io::Result<usize> {
            match self.master.lock().expect("pty master poisoned").read(bytes) {
                Err(error) if error.raw_os_error() == Some(libc::EIO) => Ok(0),
                other => other,
            }
        }

        pub fn write(&self, bytes: &[u8]) -> io::Result<usize> {
            self.master
                .lock()
                .expect("pty master poisoned")
                .write(bytes)
        }

        pub fn resize(&self, columns: u16, rows: u16) -> io::Result<()> {
            resize_fd(
                self.master.lock().expect("pty master poisoned").as_raw_fd(),
                columns,
                rows,
            )
        }

        pub fn kill(&self) {
            let _ = self.child.lock().expect("pty child poisoned").kill();
        }

        pub fn has_exited(&self) -> bool {
            self.child
                .lock()
                .expect("pty child poisoned")
                .try_wait()
                .ok()
                .flatten()
                .is_some()
        }
    }
}

/// A Windows pseudo console (ConPTY) with the system shell attached.
#[cfg(windows)]
mod sys {
    use super::GrantedProfile;
    use std::{
        ffi::c_void,
        fs::File,
        io::{self, Read, Write},
        os::windows::io::{AsRawHandle, FromRawHandle},
        ptr,
        sync::{
            Mutex,
            atomic::{AtomicPtr, Ordering},
        },
        time::{Duration, Instant},
    };
    use windows_sys::Win32::{
        Foundation::{CloseHandle, ERROR_BROKEN_PIPE, HANDLE, INVALID_HANDLE_VALUE, WAIT_OBJECT_0},
        System::{
            Console::{COORD, ClosePseudoConsole, CreatePseudoConsole, HPCON, ResizePseudoConsole},
            Pipes::{CreatePipe, PeekNamedPipe},
            Threading::{
                CREATE_UNICODE_ENVIRONMENT, CreateProcessW, DeleteProcThreadAttributeList,
                EXTENDED_STARTUPINFO_PRESENT, InitializeProcThreadAttributeList,
                LPPROC_THREAD_ATTRIBUTE_LIST, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                PROCESS_INFORMATION, STARTF_USESTDHANDLES, STARTUPINFOEXW, TerminateProcess,
                UpdateProcThreadAttribute, WaitForSingleObject,
            },
        },
    };

    /// The same line protocol as the POSIX `test-program`, in the PowerShell
    /// every supported Windows installation ships.
    const TEST_PROGRAM: &str = "$out = [Console]::Out; $nl = [char]10
$out.Write('terminal-ready' + $nl)
while ($null -ne ($line = [Console]::In.ReadLine())) {
  if ($line -eq 'exit') { $out.Write('terminal-bye' + $nl); exit 0 }
  elseif ($line -eq 'hang') { while ($true) { Start-Sleep -Seconds 1 } }
  elseif ($line.StartsWith('lines:')) { $n = [int]$line.Substring(6); for ($i = 1; $i -le $n; $i++) { $out.Write(('line-{0:D6}' -f $i) + $nl) } }
  elseif ($line -eq 'fail') { [Console]::Error.Write('fixture-error' + $nl); exit 7 }
  else { $out.Write('echo:' + $line + $nl) }
}";

    struct Owned(HANDLE);
    unsafe impl Send for Owned {}
    unsafe impl Sync for Owned {}
    impl Drop for Owned {
        fn drop(&mut self) {
            if !self.0.is_null() && self.0 != INVALID_HANDLE_VALUE {
                unsafe { CloseHandle(self.0) };
            }
        }
    }
    impl Owned {
        fn into_file(self) -> File {
            let raw = self.0;
            std::mem::forget(self);
            unsafe { File::from_raw_handle(raw as _) }
        }
    }

    struct Console(HPCON);
    unsafe impl Send for Console {}
    impl Console {
        fn close(self) {
            unsafe { ClosePseudoConsole(self.0) };
        }
    }

    /// Startup control output is never held beyond this many bytes.
    const STARTUP_HOLD_LIMIT: usize = 64 * 1024;

    /// Whether VT output contains a printable character or line break outside
    /// CSI (`ESC [`), OSC (`ESC ]`, ended by BEL or `ESC \`), and other escapes.
    fn contains_text(bytes: &[u8]) -> bool {
        #[derive(PartialEq)]
        enum Mode {
            Text,
            Escape,
            Csi,
            Osc,
        }
        let mut mode = Mode::Text;
        for &byte in bytes {
            mode = match mode {
                Mode::Text if byte == 0x1b => Mode::Escape,
                Mode::Text if byte == b'\n' || (0x20..0x7f).contains(&byte) || byte >= 0x80 => {
                    return true;
                }
                Mode::Text => Mode::Text,
                Mode::Escape if byte == b'[' => Mode::Csi,
                Mode::Escape if byte == b']' => Mode::Osc,
                Mode::Escape => Mode::Text,
                Mode::Csi if (0x40..=0x7e).contains(&byte) => Mode::Text,
                Mode::Csi => Mode::Csi,
                Mode::Osc if byte == 0x07 => Mode::Text,
                Mode::Osc if byte == 0x1b => Mode::Escape,
                Mode::Osc => Mode::Osc,
            };
        }
        false
    }

    pub struct Terminal {
        output: Mutex<Option<File>>,
        input: Mutex<Option<File>>,
        console: AtomicPtr<c_void>,
        process: Owned,
        negotiating: std::sync::atomic::AtomicBool,
    }

    fn check(result: i32) -> io::Result<()> {
        if result != 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }

    fn hresult(code: i32) -> io::Result<()> {
        if code >= 0 {
            Ok(())
        } else {
            Err(io::Error::from_raw_os_error(code))
        }
    }

    fn pipe() -> io::Result<(Owned, Owned)> {
        let (mut read, mut write) = (ptr::null_mut(), ptr::null_mut());
        check(unsafe { CreatePipe(&mut read, &mut write, ptr::null(), 0) })?;
        Ok((Owned(read), Owned(write)))
    }

    fn coord(columns: u16, rows: u16) -> COORD {
        COORD {
            X: columns as i16,
            Y: rows as i16,
        }
    }

    fn wide(value: &str) -> Vec<u16> {
        value.encode_utf16().chain(Some(0)).collect()
    }

    fn system_root() -> String {
        std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into())
    }

    /// PowerShell's `-EncodedCommand` takes base64 UTF-16LE, which keeps the
    /// program out of Windows command-line quoting entirely.
    fn encoded_command(script: &str) -> String {
        const TABLE: &[u8; 64] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
        let mut encoded = String::with_capacity(bytes.len().div_ceil(3) * 4);
        for chunk in bytes.chunks(3) {
            let value = (chunk[0] as u32) << 16
                | (*chunk.get(1).unwrap_or(&0) as u32) << 8
                | *chunk.get(2).unwrap_or(&0) as u32;
            for index in 0..4 {
                encoded.push(if index <= chunk.len() {
                    TABLE[(value >> (18 - 6 * index) & 63) as usize] as char
                } else {
                    '='
                });
            }
        }
        encoded
    }

    fn command_line(profile: GrantedProfile) -> String {
        let system = system_root();
        match profile {
            GrantedProfile::LocalShell => format!("\"{system}\\System32\\cmd.exe\""),
            GrantedProfile::TestProgram => format!(
                "\"{system}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {}",
                encoded_command(TEST_PROGRAM)
            ),
        }
    }

    /// A minimal environment, like the POSIX `env_clear`, plus what Windows
    /// programs need to start at all. Windows requires the block sorted.
    fn environment_block() -> Vec<u16> {
        let system = system_root();
        let mut variables = vec![
            ("ComSpec".to_owned(), format!("{system}\\System32\\cmd.exe")),
            (
                "PATH".to_owned(),
                format!("{system}\\System32;{system};{system}\\System32\\WindowsPowerShell\\v1.0"),
            ),
            ("PATHEXT".to_owned(), ".COM;.EXE;.BAT;.CMD".to_owned()),
            ("SystemRoot".to_owned(), system.clone()),
            ("TERM".to_owned(), "xterm-256color".to_owned()),
            ("windir".to_owned(), system),
        ];
        for name in ["SystemDrive", "TEMP", "TMP"] {
            if let Ok(value) = std::env::var(name) {
                variables.push((name.to_owned(), value));
            }
        }
        variables.sort_by_key(|(name, _)| name.to_uppercase());
        let mut block = Vec::new();
        for (name, value) in variables {
            block.extend(format!("{name}={value}").encode_utf16());
            block.push(0);
        }
        block.push(0);
        block
    }

    fn launch(console: HPCON, profile: GrantedProfile) -> io::Result<Owned> {
        let mut size = 0usize;
        // The sizing call reports the required buffer through a failure.
        unsafe { InitializeProcThreadAttributeList(ptr::null_mut(), 1, 0, &mut size) };
        let mut storage = vec![0usize; size.div_ceil(size_of::<usize>())];
        let attributes = storage.as_mut_ptr() as LPPROC_THREAD_ATTRIBUTE_LIST;
        check(unsafe { InitializeProcThreadAttributeList(attributes, 1, 0, &mut size) })?;
        struct Attributes(LPPROC_THREAD_ATTRIBUTE_LIST);
        impl Drop for Attributes {
            fn drop(&mut self) {
                unsafe { DeleteProcThreadAttributeList(self.0) };
            }
        }
        let _attributes = Attributes(attributes);
        check(unsafe {
            UpdateProcThreadAttribute(
                attributes,
                0,
                PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE as usize,
                console as *const c_void,
                size_of::<HPCON>(),
                ptr::null_mut(),
                ptr::null_mut(),
            )
        })?;
        let mut startup: STARTUPINFOEXW = unsafe { std::mem::zeroed() };
        startup.StartupInfo.cb = size_of::<STARTUPINFOEXW>() as u32;
        // Explicitly invalid standard handles: otherwise a host whose own
        // stdio is redirected (as under the spec runner) hands those handles
        // to the child in place of the pseudo console.
        startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
        startup.StartupInfo.hStdInput = INVALID_HANDLE_VALUE;
        startup.StartupInfo.hStdOutput = INVALID_HANDLE_VALUE;
        startup.StartupInfo.hStdError = INVALID_HANDLE_VALUE;
        startup.lpAttributeList = attributes;
        let mut command = wide(&command_line(profile));
        let environment = environment_block();
        let mut information: PROCESS_INFORMATION = unsafe { std::mem::zeroed() };
        check(unsafe {
            CreateProcessW(
                ptr::null(),
                command.as_mut_ptr(),
                ptr::null(),
                ptr::null(),
                0,
                EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                environment.as_ptr() as *const c_void,
                ptr::null(),
                &startup.StartupInfo,
                &mut information,
            )
        })?;
        drop(Owned(information.hThread));
        Ok(Owned(information.hProcess))
    }

    impl Terminal {
        pub fn spawn(columns: u16, rows: u16, profile: GrantedProfile) -> io::Result<Self> {
            let (input_read, input_write) = pipe()?;
            let (output_read, output_write) = pipe()?;
            let mut console: HPCON = unsafe { std::mem::zeroed() };
            hresult(unsafe {
                CreatePseudoConsole(
                    coord(columns, rows),
                    input_read.0,
                    output_write.0,
                    0,
                    &mut console,
                )
            })?;
            // The pseudo console holds its own duplicates; keeping these would
            // stop the output pipe from ever reporting end of file.
            drop((input_read, output_write));
            let mut terminal = Self {
                output: Mutex::new(Some(output_read.into_file())),
                input: Mutex::new(Some(input_write.into_file())),
                console: AtomicPtr::new(console as *mut c_void),
                process: Owned(ptr::null_mut()),
                negotiating: std::sync::atomic::AtomicBool::new(true),
            };
            terminal.process = launch(console, profile)?;
            Ok(terminal)
        }

        /// `None` once the pseudo console has released the output pipe.
        fn available(&self) -> io::Result<Option<u32>> {
            let guard = self.output.lock().expect("pty output poisoned");
            let Some(output) = guard.as_ref() else {
                return Ok(None);
            };
            let mut available = 0u32;
            if unsafe {
                PeekNamedPipe(
                    output.as_raw_handle() as HANDLE,
                    ptr::null_mut(),
                    0,
                    ptr::null_mut(),
                    &mut available,
                    ptr::null_mut(),
                )
            } != 0
            {
                return Ok(Some(available));
            }
            let error = io::Error::last_os_error();
            if error.raw_os_error() == Some(ERROR_BROKEN_PIPE as i32) {
                Ok(None)
            } else {
                Err(error)
            }
        }

        /// A pseudo console keeps its output pipe open after the client exits,
        /// so the pipe only reaches end of file once the console is closed.
        /// Closing can wait for undrained output, so it runs beside the reader.
        fn release_console(&self) {
            let console = self.console.swap(ptr::null_mut(), Ordering::AcqRel);
            if !console.is_null() {
                let console = Console(console as HPCON);
                std::thread::spawn(move || console.close());
            }
        }

        /// Before the program's first output, the pseudo console negotiates
        /// modes, sets up its first frame, and titles the window, and it may
        /// flush any of that on its own. Until printable text arrives those
        /// control sequences are held back (not dropped), so a reader's first
        /// data carries the program's output rather than only terminal setup.
        /// Returns whether startup output is still being held.
        fn startup_pending(&self, available: u32) -> io::Result<bool> {
            if !self.negotiating.load(Ordering::Acquire) {
                return Ok(false);
            }
            if available as usize > STARTUP_HOLD_LIMIT {
                self.negotiating.store(false, Ordering::Release);
                return Ok(false);
            }
            let guard = self.output.lock().expect("pty output poisoned");
            let Some(output) = guard.as_ref() else {
                return Ok(false);
            };
            let mut peeked = vec![0u8; available as usize];
            let mut read = 0u32;
            if unsafe {
                PeekNamedPipe(
                    output.as_raw_handle() as HANDLE,
                    peeked.as_mut_ptr() as *mut c_void,
                    available,
                    &mut read,
                    ptr::null_mut(),
                    ptr::null_mut(),
                )
            } == 0
            {
                self.negotiating.store(false, Ordering::Release);
                return Ok(false);
            }
            if contains_text(&peeked[..read as usize]) {
                self.negotiating.store(false, Ordering::Release);
                return Ok(false);
            }
            Ok(true)
        }

        pub fn wait_readable(&self, timeout_ms: u64) -> io::Result<bool> {
            let deadline = Instant::now() + Duration::from_millis(timeout_ms);
            loop {
                match self.available()? {
                    None => return Ok(true),
                    Some(count) if count > 0 => {
                        if !self.startup_pending(count)? && self.available()? != Some(0) {
                            return Ok(true);
                        }
                    }
                    Some(_) => {}
                }
                if self.has_exited() {
                    self.release_console();
                }
                let now = Instant::now();
                if now >= deadline {
                    return Ok(false);
                }
                std::thread::sleep((deadline - now).min(Duration::from_millis(5)));
            }
        }

        /// The console repaints on its own after input or a resize, so a quiet
        /// gap can follow control output (cursor visibility, erase) that
        /// carries none of the program's text. That output is held until text
        /// arrives, end of output, or the read fills, and nothing is dropped.
        pub fn worth_delivering(&self, collected: &[u8]) -> bool {
            contains_text(collected)
        }

        pub fn read(&self, bytes: &mut [u8]) -> io::Result<usize> {
            let Some(available) = self.available()? else {
                return Ok(0);
            };
            if available == 0 {
                // Reading anyway would block on the pipe while holding the
                // lock. Callers read only after `wait_readable`, so this says
                // "nothing yet" rather than `Ok(0)`, which would mean the
                // terminal had closed.
                return Err(io::ErrorKind::WouldBlock.into());
            }
            let count = (available as usize).min(bytes.len());
            match self.output.lock().expect("pty output poisoned").as_mut() {
                Some(output) => output.read(&mut bytes[..count]),
                None => Ok(0),
            }
        }

        /// A POSIX terminal's line discipline accepts `\n` as Enter; a Windows
        /// console only ends a line on `\r`, so newlines are sent as returns.
        pub fn write(&self, bytes: &[u8]) -> io::Result<usize> {
            let translated: Vec<u8> = bytes
                .iter()
                .map(|&byte| if byte == b'\n' { b'\r' } else { byte })
                .collect();
            match self.input.lock().expect("pty input poisoned").as_mut() {
                Some(input) => input.write_all(&translated).map(|()| bytes.len()),
                None => Err(io::ErrorKind::BrokenPipe.into()),
            }
        }

        pub fn resize(&self, columns: u16, rows: u16) -> io::Result<()> {
            let console = self.console.load(Ordering::Acquire);
            if console.is_null() {
                return Err(io::ErrorKind::BrokenPipe.into());
            }
            hresult(unsafe { ResizePseudoConsole(console as HPCON, coord(columns, rows)) })
        }

        pub fn kill(&self) {
            if !self.process.0.is_null() {
                unsafe { TerminateProcess(self.process.0, 1) };
            }
        }

        pub fn has_exited(&self) -> bool {
            self.process.0.is_null()
                || unsafe { WaitForSingleObject(self.process.0, 0) } == WAIT_OBJECT_0
        }
    }

    impl Drop for Terminal {
        fn drop(&mut self) {
            // Close this side of both pipes first, so closing the console never
            // waits on output nobody will read.
            drop(self.output.get_mut().ok().and_then(Option::take));
            drop(self.input.get_mut().ok().and_then(Option::take));
            let console = *self.console.get_mut();
            if !console.is_null() {
                Console(console as HPCON).close();
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        fn read_until(terminal: &Terminal, needle: &str) -> String {
            let deadline = Instant::now() + Duration::from_secs(30);
            let mut seen = Vec::new();
            while Instant::now() < deadline {
                if terminal.wait_readable(20).unwrap() {
                    let mut bytes = [0; 4096];
                    let count = terminal.read(&mut bytes).unwrap();
                    if count == 0 {
                        break;
                    }
                    seen.extend_from_slice(&bytes[..count]);
                    if String::from_utf8_lossy(&seen).contains(needle) {
                        break;
                    }
                }
            }
            String::from_utf8_lossy(&seen).into_owned()
        }

        #[test]
        fn startup_control_sequences_are_not_text() {
            assert!(!contains_text(
                b"\x1b[?9001h\x1b[?1004h\x1b[?25l\x1b[2J\x1b[m\x1b[H"
            ));
            assert!(!contains_text(
                b"\x1b]0;C:\\Windows\\powershell.exe\x07\x1b[?25h\r"
            ));
            assert!(!contains_text(b"\x1b]0;title\x1b\\\x1b[K"));
            assert!(
                !contains_text(b"\x1b[3"),
                "an incomplete sequence is not text"
            );
            assert!(contains_text(b"\x1b[Hterminal-ready"));
            assert!(contains_text(b"\x1b[K\r\n"));
        }

        #[test]
        fn encoded_command_is_base64_utf16le() {
            assert_eq!(encoded_command("a"), "YQA=");
            assert_eq!(encoded_command("ab"), "YQBiAA==");
        }

        #[test]
        fn environment_block_is_sorted_and_terminated() {
            let block = environment_block();
            assert_eq!(&block[block.len() - 2..], &[0, 0]);
            let text = String::from_utf16(&block).unwrap();
            let names: Vec<String> = text
                .split('\0')
                .filter(|entry| !entry.is_empty())
                .map(|entry| entry.split('=').next().unwrap().to_uppercase())
                .collect();
            let mut sorted = names.clone();
            sorted.sort();
            assert_eq!(names, sorted);
        }

        #[test]
        fn test_program_speaks_its_protocol_through_the_pseudo_console() {
            let terminal = Terminal::spawn(80, 24, GrantedProfile::TestProgram).unwrap();
            // The first data a reader sees carries program text, not only
            // the console's control-sequence startup.
            assert!(terminal.wait_readable(30_000).unwrap());
            let mut first = [0u8; 4096];
            let count = terminal.read(&mut first).unwrap();
            assert!(
                contains_text(&first[..count]),
                "first read held only terminal setup"
            );
            let mut ready = String::from_utf8_lossy(&first[..count]).into_owned();
            if !ready.contains("terminal-ready") {
                ready += &read_until(&terminal, "terminal-ready");
            }
            assert!(ready.contains("terminal-ready"));
            terminal.resize(132, 43).unwrap();
            // Newlines are Enter, as they are for a POSIX line discipline.
            assert_eq!(terminal.write(b"hello\n").unwrap(), 6);
            assert!(read_until(&terminal, "echo:hello").contains("echo:hello"));
            terminal.write(b"exit\n").unwrap();
            assert!(read_until(&terminal, "terminal-bye").contains("terminal-bye"));
            let deadline = Instant::now() + Duration::from_secs(10);
            while !terminal.has_exited() && Instant::now() < deadline {
                std::thread::sleep(Duration::from_millis(10));
            }
            assert!(terminal.has_exited());
            read_until(&terminal, "\u{0}never");
            assert_eq!(terminal.available().unwrap(), None);
        }
    }
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

    #[cfg(unix)]
    #[test]
    fn resize_updates_the_kernel_pty_size() {
        let mut master = -1;
        let mut slave = -1;
        assert_eq!(
            unsafe {
                libc::openpty(
                    &mut master,
                    &mut slave,
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                )
            },
            0
        );
        sys::resize_fd(master, 132, 43).unwrap();
        let mut observed = std::mem::MaybeUninit::<libc::winsize>::zeroed();
        assert_eq!(
            unsafe { libc::ioctl(master, libc::TIOCGWINSZ, observed.as_mut_ptr()) },
            0
        );
        let observed = unsafe { observed.assume_init() };
        assert_eq!((observed.ws_col, observed.ws_row), (132, 43));
        unsafe {
            libc::close(master);
            libc::close(slave);
        }
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
