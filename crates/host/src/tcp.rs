use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    io::{Read, Write},
    mem::ManuallyDrop,
    net::{Shutdown, SocketAddr, TcpStream},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

const TIMEOUT: Duration = Duration::from_secs(2);
/// Windows retransmits SYNs to a refusing loopback port for about two seconds
/// before it reports the refusal, so a shorter budget turns "nothing listens
/// there" into a timeout.
#[cfg(windows)]
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
#[cfg(not(windows))]
const CONNECT_TIMEOUT: Duration = TIMEOUT;
const MAX_READ_BYTES: u64 = 1024 * 1024;
const MAX_WRITE_BYTES: usize = 16 * 1024 * 1024;

type SharedStream = Arc<Mutex<Option<TcpStream>>>;

#[derive(Default)]
struct Store {
    endpoint: Option<SocketAddr>,
    next: u64,
    streams: HashMap<u64, SharedStream>,
    allocations: HashMap<usize, u64>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static OPERATIONS: [AtomicU64; 4] = [const { AtomicU64::new(0) }; 4];

/// What an open stream may do. A connection is already the authority; there is
/// nothing narrower to derive from it, so it never carries `DERIVE`.
const STREAM_RIGHTS: Rights = Rights::READ.union(Rights::WRITE);

/// How a stream grant arrives. An exact numeric socket address supplied by `--host-cap-tcp`. It performs
/// no DNS and serves development and automation; the trusted Connect broker that
/// would make this a person's decision is an open backlog entry.
const STREAM_ORIGIN: Origin = Origin::Provisioned;

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            ..Store::default()
        })
    })
}

pub fn configure(endpoint: Option<SocketAddr>) {
    let mut guard = store().lock().expect("TCP capability store poisoned");
    guard.endpoint = endpoint;
    guard.streams.clear();
    guard.allocations.clear();
    drop(guard);
    // Provisioning is being replaced; the grants that named the previous
    // endpoint cease to exist rather than having their authority taken away.
    grant::forget_kind(grant::Kind::Tcp);
    for counter in &OPERATIONS {
        counter.store(0, Ordering::Relaxed);
    }
}

pub fn counters() -> ([u64; 4], usize) {
    let operations = std::array::from_fn(|index| OPERATIONS[index].load(Ordering::Relaxed));
    (operations, active_count())
}

pub fn route_dealloc(allocation_base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("TCP capability store poisoned");
    let released =
        crate::remove_resource_allocation(&mut guard.allocations, allocation_base as usize);
    if let Some(id) = released {
        guard.streams.remove(&id);
    }
    drop(guard);
    if let Some(id) = released {
        grant::release(grant::Kind::Tcp, id);
    }
}

pub fn active_count() -> usize {
    store()
        .lock()
        .expect("TCP capability store poisoned")
        .streams
        .len()
}

fn capability(stream: TcpStream) -> *mut u64 {
    let mut guard = store().lock().expect("TCP capability store poisoned");
    let id = guard.next;
    guard.next = guard
        .next
        .checked_add(1)
        .expect("TCP capability ids exhausted");
    let handle = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            core::mem::align_of::<u64>(),
            false,
            roc_host(),
        ) as *mut u64
    };
    unsafe { handle.write(id) };
    let base = unsafe { (handle as *mut u8).sub(core::mem::size_of::<isize>()) };
    guard.streams.insert(id, Arc::new(Mutex::new(Some(stream))));
    crate::register_resource_allocation(
        crate::resource_domain::TCP,
        &mut guard.allocations,
        base as usize,
        id,
    );
    drop(guard);
    grant::record_root(
        grant::Kind::Tcp,
        id,
        STREAM_RIGHTS,
        STREAM_ORIGIN,
        Lifetime::Session,
    );
    handle
}

/// A stream, or why it is not usable. Revocation and an invalid handle are
/// different facts about the application and are reported as different failures.
fn lookup(handle: *mut u64) -> Result<SharedStream, Failure> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(Failure::InvalidCapability)?;
    grant::accept(grant::Kind::Tcp, id, Rights::READ).map_err(refusal)?;
    store()
        .lock()
        .ok()
        .and_then(|guard| guard.streams.get(&id).cloned())
        .ok_or(Failure::InvalidCapability)
}

/// The single mapping from a refused acceptance to this resource's reason.
fn refusal(refusal: grant::Refusal) -> Failure {
    match refusal {
        grant::Refusal::Revoked => Failure::Revoked,
        grant::Refusal::Unknown | grant::Refusal::Rights => Failure::InvalidCapability,
    }
}

#[repr(u8)]
#[derive(Clone, Copy)]
enum Failure {
    AccessDenied = 0,
    Closed = 1,
    ConnectionFailed = 2,
    InvalidCapability = 3,
    InvalidRequest = 4,
    ResourceLimit = 5,
    Timeout = 6,
    Revoked = 7,
}

fn io_failure(error: &std::io::Error) -> Failure {
    match error.kind() {
        std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock => Failure::Timeout,
        std::io::ErrorKind::NotConnected
        | std::io::ErrorKind::BrokenPipe
        | std::io::ErrorKind::ConnectionAborted
        | std::io::ErrorKind::ConnectionReset => Failure::Closed,
        _ => Failure::ConnectionFailed,
    }
}

fn connect_err(error: Failure) -> HostGlueTcpConnectResult {
    HostGlueTcpConnectResult {
        payload: HostGlueTcpConnectResultPayload {
            err: ManuallyDrop::new(error as u8),
        },
        tag: HostGlueTcpConnectResultTag::Err,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_tcp_connect() -> HostGlueTcpConnectResult {
    OPERATIONS[0].fetch_add(1, Ordering::Relaxed);
    let endpoint = store()
        .lock()
        .expect("TCP capability store poisoned")
        .endpoint;
    let Some(endpoint) = endpoint else {
        return connect_err(Failure::AccessDenied);
    };
    match TcpStream::connect_timeout(&endpoint, CONNECT_TIMEOUT) {
        Ok(stream) => {
            if stream.set_read_timeout(Some(TIMEOUT)).is_err()
                || stream.set_write_timeout(Some(TIMEOUT)).is_err()
            {
                return connect_err(Failure::ConnectionFailed);
            }
            HostGlueTcpConnectResult {
                payload: HostGlueTcpConnectResultPayload {
                    ok: ManuallyDrop::new(capability(stream)),
                },
                tag: HostGlueTcpConnectResultTag::Ok,
            }
        }
        Err(error) => connect_err(io_failure(&error)),
    }
}

fn read_err(error: Failure) -> HostGlueTcpReadUpToResult {
    HostGlueTcpReadUpToResult {
        payload: HostGlueTcpReadUpToResultPayload {
            err: ManuallyDrop::new(error as u8),
        },
        tag: HostGlueTcpReadUpToResultTag::Err,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_tcp_read_up_to(
    handle: *mut u64,
    max_bytes: u64,
) -> HostGlueTcpReadUpToResult {
    OPERATIONS[1].fetch_add(1, Ordering::Relaxed);
    let shared = lookup(handle);
    unsafe {
        decref_box(handle as RocBox, roc_host());
    }
    if max_bytes == 0 || max_bytes > MAX_READ_BYTES {
        return read_err(Failure::InvalidRequest);
    }
    let shared = match shared {
        Ok(shared) => shared,
        Err(failure) => return read_err(failure),
    };
    let mut guard = shared.lock().expect("TCP stream mutex poisoned");
    let Some(stream) = guard.as_mut() else {
        return read_err(Failure::Closed);
    };
    let mut bytes = vec![0; max_bytes as usize];
    match stream.read(&mut bytes) {
        Ok(length) => {
            bytes.truncate(length);
            HostGlueTcpReadUpToResult {
                payload: HostGlueTcpReadUpToResultPayload {
                    ok: ManuallyDrop::new(unsafe {
                        RocListWith::<u8, false>::from_slice(&bytes, roc_host())
                    }),
                },
                tag: HostGlueTcpReadUpToResultTag::Ok,
            }
        }
        Err(error) => read_err(io_failure(&error)),
    }
}

fn unit_err(error: Failure) -> HostGlueTcpWriteAllResult {
    HostGlueTcpWriteAllResult {
        payload: HostGlueTcpWriteAllResultPayload {
            err: ManuallyDrop::new(error as u8),
        },
        tag: HostGlueTcpWriteAllResultTag::Err,
    }
}

fn unit_ok() -> HostGlueTcpWriteAllResult {
    HostGlueTcpWriteAllResult {
        payload: HostGlueTcpWriteAllResultPayload { ok: [] },
        tag: HostGlueTcpWriteAllResultTag::Ok,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_tcp_write_all(
    handle: *mut u64,
    bytes: RocListWith<u8, false>,
) -> HostGlueTcpWriteAllResult {
    OPERATIONS[2].fetch_add(1, Ordering::Relaxed);
    let owned = bytes.as_slice().to_vec();
    unsafe {
        bytes.decref(roc_host());
    }
    let shared = lookup(handle);
    unsafe {
        decref_box(handle as RocBox, roc_host());
    }
    if owned.len() > MAX_WRITE_BYTES {
        return unit_err(Failure::ResourceLimit);
    }
    let shared = match shared {
        Ok(shared) => shared,
        Err(failure) => return unit_err(failure),
    };
    let mut guard = shared.lock().expect("TCP stream mutex poisoned");
    let Some(stream) = guard.as_mut() else {
        return unit_err(Failure::Closed);
    };
    match stream.write_all(&owned).and_then(|_| stream.flush()) {
        Ok(()) => unit_ok(),
        Err(error) => unit_err(io_failure(&error)),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_tcp_close(handle: *mut u64) -> HostGlueTcpWriteAllResult {
    OPERATIONS[3].fetch_add(1, Ordering::Relaxed);
    let shared = lookup(handle);
    unsafe {
        decref_box(handle as RocBox, roc_host());
    }
    let shared = match shared {
        Ok(shared) => shared,
        Err(failure) => return unit_err(failure),
    };
    let mut guard = shared.lock().expect("TCP stream mutex poisoned");
    if let Some(stream) = guard.take() {
        let _ = stream.shutdown(Shutdown::Both);
    }
    unit_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn configured_authority_is_one_exact_socket() {
        configure(Some("127.0.0.1:6379".parse().unwrap()));
        assert_eq!(
            store().lock().unwrap().endpoint.unwrap().to_string(),
            "127.0.0.1:6379"
        );
        configure(None);
    }

    #[test]
    fn timeout_is_distinct_from_closed() {
        assert!(matches!(
            io_failure(&std::io::Error::from(std::io::ErrorKind::TimedOut)),
            Failure::Timeout
        ));
        assert!(matches!(
            io_failure(&std::io::Error::from(std::io::ErrorKind::BrokenPipe)),
            Failure::Closed
        ));
    }
}
