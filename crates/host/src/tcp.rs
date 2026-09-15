use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    io::{Read, Write},
    mem::ManuallyDrop,
    net::{Shutdown, SocketAddr, TcpStream},
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};

const TIMEOUT: Duration = Duration::from_secs(2);
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

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            next: 1,
            ..Store::default()
        })
    })
}

pub fn configure(endpoint: Option<SocketAddr>) {
    store()
        .lock()
        .expect("TCP capability store poisoned")
        .endpoint = endpoint;
}

pub fn route_dealloc(allocation_base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("TCP capability store poisoned");
    if let Some(id) = guard.allocations.remove(&(allocation_base as usize)) {
        guard.streams.remove(&id);
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
    guard.allocations.insert(base as usize, id);
    handle
}

fn lookup(handle: *mut u64) -> Option<SharedStream> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.streams.get(&id).cloned()
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
    let endpoint = store()
        .lock()
        .expect("TCP capability store poisoned")
        .endpoint;
    let Some(endpoint) = endpoint else {
        return connect_err(Failure::AccessDenied);
    };
    match TcpStream::connect_timeout(&endpoint, TIMEOUT) {
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
    let shared = lookup(handle);
    unsafe {
        decref_box(handle as RocBox, roc_host());
    }
    if max_bytes == 0 || max_bytes > MAX_READ_BYTES {
        return read_err(Failure::InvalidRequest);
    }
    let Some(shared) = shared else {
        return read_err(Failure::InvalidCapability);
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
    let Some(shared) = shared else {
        return unit_err(Failure::InvalidCapability);
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
    let shared = lookup(handle);
    unsafe {
        decref_box(handle as RocBox, roc_host());
    }
    let Some(shared) = shared else {
        return unit_err(Failure::InvalidCapability);
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
