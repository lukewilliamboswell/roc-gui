use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    sync::{Arc, Mutex, OnceLock},
};

const MAX_ACTIVE: usize = 32;
const MAX_REPORT: usize = 4096;
const MAGIC_REQUEST: u8 = 0xa5;
const MAGIC_RESPONSE: u8 = 0x5a;
const VERSION: u8 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GrantedDevice {
    Virtual { controls: u16 },
    Hid { vendor_id: u16, product_id: u16 },
}

struct VirtualState {
    controls: u16,
    sensitivity: u16,
    lighting: bool,
    profile: u8,
}

enum Transport {
    Virtual(Mutex<VirtualState>),
    Hid(Mutex<hidapi::HidDevice>),
}

struct Connection {
    transport: Transport,
    closed: Mutex<bool>,
}

struct Store {
    configured: Option<GrantedDevice>,
    next: u64,
    grants: HashMap<u64, GrantedDevice>,
    connections: HashMap<u64, Arc<Connection>>,
    grant_allocations: HashMap<usize, u64>,
    connection_allocations: HashMap<usize, u64>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static DISCOVERED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static CONNECTED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static TRANSACTIONS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static CLOSED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            configured: None,
            next: 1,
            grants: HashMap::new(),
            connections: HashMap::new(),
            grant_allocations: HashMap::new(),
            connection_allocations: HashMap::new(),
        })
    })
}

pub fn configure(device: Option<GrantedDevice>) {
    store().lock().expect("device store poisoned").configured = device;
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

fn next_id(store: &mut Store) -> u64 {
    let id = store.next;
    store.next = store.next.checked_add(1).expect("device ids exhausted");
    id
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("device store poisoned");
    let key = base as usize;
    if let Some(id) = crate::remove_resource_allocation(&mut guard.grant_allocations, key) {
        guard.grants.remove(&id);
    }
    if let Some(id) = crate::remove_resource_allocation(&mut guard.connection_allocations, key) {
        guard.connections.remove(&id);
    }
}

pub fn active_count() -> usize {
    store()
        .lock()
        .expect("device store poisoned")
        .connections
        .values()
        .filter(|connection| {
            !*connection
                .closed
                .lock()
                .expect("device closed mutex poisoned")
        })
        .count()
}
pub fn counters() -> (u64, u64, u64, u64) {
    use std::sync::atomic::Ordering;
    (
        DISCOVERED.load(Ordering::Relaxed),
        CONNECTED.load(Ordering::Relaxed),
        TRANSACTIONS.load(Ordering::Relaxed),
        CLOSED.load(Ordering::Relaxed),
    )
}

type Reason = AccessDeniedOrBusyOrClosedOrDisconnectedOrInvalidCapabilityOrInvalidRequestOrIoOrNotFoundOrProtocolOrResourceLimitOrTimeoutOrUnsupported;
type Error =
    AcquireDeviceErrOrCloseDeviceErrOrConnectDeviceErrOrDiscoverDeviceErrOrTransactDeviceErr;
type ErrorPayload =
    AcquireDeviceErrOrCloseDeviceErrOrConnectDeviceErrOrDiscoverDeviceErrOrTransactDeviceErrPayload;
type ErrorTag =
    AcquireDeviceErrOrCloseDeviceErrOrConnectDeviceErrOrDiscoverDeviceErrOrTransactDeviceErrTag;

fn error(tag: ErrorTag, reason: Reason) -> Error {
    let payload = match tag {
        ErrorTag::AcquireDeviceErr => ErrorPayload {
            acquire_device_err: ManuallyDrop::new(reason),
        },
        ErrorTag::CloseDeviceErr => ErrorPayload {
            close_device_err: ManuallyDrop::new(reason),
        },
        ErrorTag::ConnectDeviceErr => ErrorPayload {
            connect_device_err: ManuallyDrop::new(reason),
        },
        ErrorTag::DiscoverDeviceErr => ErrorPayload {
            discover_device_err: ManuallyDrop::new(reason),
        },
        ErrorTag::TransactDeviceErr => ErrorPayload {
            transact_device_err: ManuallyDrop::new(reason),
        },
    };
    Error { payload, tag }
}

fn grant(handle: *mut u64) -> Option<GrantedDevice> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.grants.get(&id).copied()
}

fn connection(handle: *mut u64) -> Option<Arc<Connection>> {
    let id = unsafe { handle.as_ref().copied()? };
    store().lock().ok()?.connections.get(&id).cloned()
}

fn acquire_err(reason: Reason) -> HostGlueDeviceAcquireResult {
    HostGlueDeviceAcquireResult {
        payload: HostGlueDeviceAcquireResultPayload {
            err: ManuallyDrop::new(error(ErrorTag::AcquireDeviceErr, reason)),
        },
        tag: HostGlueDeviceAcquireResultTag::Err,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_device_acquire() -> HostGlueDeviceAcquireResult {
    let mut guard = store().lock().expect("device store poisoned");
    let Some(configured) = guard.configured else {
        return acquire_err(Reason::AccessDenied);
    };
    let id = next_id(&mut guard);
    let (handle, base) = allocate_handle(id);
    guard.grants.insert(id, configured);
    guard.grant_allocations.insert(base, id);
    HostGlueDeviceAcquireResult {
        payload: HostGlueDeviceAcquireResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: HostGlueDeviceAcquireResultTag::Ok,
    }
}

fn info(config: GrantedDevice) -> Result<Vec<(String, String, u16, u16)>, Reason> {
    match config {
        GrantedDevice::Virtual { .. } => Ok(vec![(
            "Roc Labs".into(),
            "Aurora Control Pad".into(),
            0x0001,
            0x1209,
        )]),
        GrantedDevice::Hid {
            vendor_id,
            product_id,
        } => {
            let api = hidapi::HidApi::new().map_err(|_| Reason::Io)?;
            let found = api
                .device_list()
                .filter(|d| d.vendor_id() == vendor_id && d.product_id() == product_id)
                .take(64)
                .map(|d| {
                    (
                        d.manufacturer_string().unwrap_or("HID device").to_owned(),
                        d.product_string().unwrap_or("HID device").to_owned(),
                        product_id,
                        vendor_id,
                    )
                })
                .collect::<Vec<_>>();
            if found.is_empty() {
                Err(Reason::NotFound)
            } else {
                Ok(found)
            }
        }
    }
}

fn discover_err(reason: Reason) -> HostGlueDeviceDiscoverResult {
    HostGlueDeviceDiscoverResult {
        payload: HostGlueDeviceDiscoverResultPayload {
            err: ManuallyDrop::new(error(ErrorTag::DiscoverDeviceErr, reason)),
        },
        tag: HostGlueDeviceDiscoverResultTag::Err,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_device_discover(handle: *mut u64) -> HostGlueDeviceDiscoverResult {
    let configured = grant(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some(configured) = configured else {
        return discover_err(Reason::InvalidCapability);
    };
    match info(configured) {
        Err(reason) => discover_err(reason),
        Ok(found) => {
            let values = found
                .iter()
                .map(
                    |(manufacturer, product, product_id, vendor_id)| AnonStruct27556b2f7cb4f65f {
                        manufacturer: RocStr::from_str(manufacturer, roc_host()),
                        product: RocStr::from_str(product, roc_host()),
                        product_id: *product_id,
                        vendor_id: *vendor_id,
                    },
                )
                .collect::<Vec<_>>();
            DISCOVERED.fetch_add(values.len() as u64, std::sync::atomic::Ordering::Relaxed);
            HostGlueDeviceDiscoverResult {
                payload: HostGlueDeviceDiscoverResultPayload {
                    ok: ManuallyDrop::new(unsafe { RocList::from_slice(&values, roc_host()) }),
                },
                tag: HostGlueDeviceDiscoverResultTag::Ok,
            }
        }
    }
}

fn connect_err(reason: Reason) -> HostGlueDeviceConnectResult {
    HostGlueDeviceConnectResult {
        payload: HostGlueDeviceConnectResultPayload {
            err: ManuallyDrop::new(error(ErrorTag::ConnectDeviceErr, reason)),
        },
        tag: HostGlueDeviceConnectResultTag::Err,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_device_connect(handle: *mut u64) -> HostGlueDeviceConnectResult {
    let configured = grant(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some(configured) = configured else {
        return connect_err(Reason::InvalidCapability);
    };
    if active_count() >= MAX_ACTIVE {
        return connect_err(Reason::ResourceLimit);
    }
    let transport = match configured {
        GrantedDevice::Virtual { controls } => Transport::Virtual(Mutex::new(VirtualState {
            controls,
            sensitivity: 800,
            lighting: true,
            profile: 1,
        })),
        GrantedDevice::Hid {
            vendor_id,
            product_id,
        } => {
            let api = match hidapi::HidApi::new() {
                Ok(api) => api,
                Err(_) => return connect_err(Reason::Io),
            };
            match api.open(vendor_id, product_id) {
                Ok(device) => Transport::Hid(Mutex::new(device)),
                Err(_) => return connect_err(Reason::NotFound),
            }
        }
    };
    let mut guard = store().lock().expect("device store poisoned");
    let id = next_id(&mut guard);
    let (cap, base) = allocate_handle(id);
    guard.connections.insert(
        id,
        Arc::new(Connection {
            transport,
            closed: Mutex::new(false),
        }),
    );
    guard.connection_allocations.insert(base, id);
    CONNECTED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    HostGlueDeviceConnectResult {
        payload: HostGlueDeviceConnectResultPayload {
            ok: ManuallyDrop::new(cap),
        },
        tag: HostGlueDeviceConnectResultTag::Ok,
    }
}

fn virtual_exchange(state: &mut VirtualState, request: &[u8]) -> Result<Vec<u8>, Reason> {
    if request.len() < 3 || request[0] != MAGIC_REQUEST || request[1] != VERSION {
        return Err(Reason::Protocol);
    }
    let op = request[2];
    let mut response = vec![MAGIC_RESPONSE, VERSION, op, 0];
    match op {
        1 if request.len() == 3 => {
            response.extend_from_slice(&state.controls.to_le_bytes());
            response.extend_from_slice(&state.sensitivity.to_le_bytes());
            response.push(state.lighting as u8);
            response.push(state.profile);
        }
        2 if request.len() == 7 => {
            let sensitivity = u16::from_le_bytes([request[3], request[4]]);
            if !(100..=3200).contains(&sensitivity)
                || request[5] > 1
                || !(1..=5).contains(&request[6])
            {
                return Err(Reason::InvalidRequest);
            }
            state.sensitivity = sensitivity;
            state.lighting = request[5] == 1;
            state.profile = request[6];
            response.extend_from_slice(&request[3..]);
        }
        3 if request.len() == 3 => {
            state.sensitivity = 800;
            state.lighting = true;
            state.profile = 1;
        }
        _ => return Err(Reason::Unsupported),
    }
    Ok(response)
}

fn transact_err(reason: Reason) -> HostGlueDeviceTransactResult {
    HostGlueDeviceTransactResult {
        payload: HostGlueDeviceTransactResultPayload {
            err: ManuallyDrop::new(error(ErrorTag::TransactDeviceErr, reason)),
        },
        tag: HostGlueDeviceTransactResultTag::Err,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_device_transact(
    handle: *mut u64,
    request: RocListWith<u8, false>,
) -> HostGlueDeviceTransactResult {
    let bytes = request.as_slice().to_vec();
    unsafe { request.decref(roc_host()) };
    let connected = connection(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    if bytes.is_empty() || bytes.len() > MAX_REPORT {
        return transact_err(Reason::ResourceLimit);
    }
    let Some(connected) = connected else {
        return transact_err(Reason::InvalidCapability);
    };
    if *connected
        .closed
        .lock()
        .expect("device closed mutex poisoned")
    {
        return transact_err(Reason::Closed);
    }
    let result = match &connected.transport {
        Transport::Virtual(state) => {
            virtual_exchange(&mut state.lock().expect("virtual device poisoned"), &bytes)
        }
        Transport::Hid(device) => {
            let device = device.lock().expect("HID device poisoned");
            let mut report = Vec::with_capacity(bytes.len() + 1);
            report.push(0);
            report.extend_from_slice(&bytes);
            if device.write(&report).is_err() {
                Err(Reason::Disconnected)
            } else {
                let mut response = vec![0; MAX_REPORT];
                match device.read_timeout(&mut response, 2000) {
                    Ok(0) => Err(Reason::Timeout),
                    Ok(n) => {
                        response.truncate(n);
                        Ok(response)
                    }
                    Err(_) => Err(Reason::Disconnected),
                }
            }
        }
    };
    match result {
        Err(reason) => transact_err(reason),
        Ok(response) => {
            TRANSACTIONS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            HostGlueDeviceTransactResult {
                payload: HostGlueDeviceTransactResultPayload {
                    ok: ManuallyDrop::new(unsafe {
                        RocListWith::<u8, false>::from_slice(&response, roc_host())
                    }),
                },
                tag: HostGlueDeviceTransactResultTag::Ok,
            }
        }
    }
}

fn close_err(reason: Reason) -> HostGlueDeviceCloseResult {
    HostGlueDeviceCloseResult {
        payload: HostGlueDeviceCloseResultPayload {
            err: ManuallyDrop::new(error(ErrorTag::CloseDeviceErr, reason)),
        },
        tag: HostGlueDeviceCloseResultTag::Err,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_device_close(handle: *mut u64) -> HostGlueDeviceCloseResult {
    let connected = connection(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let Some(connected) = connected else {
        return close_err(Reason::InvalidCapability);
    };
    let mut closed = connected
        .closed
        .lock()
        .expect("device closed mutex poisoned");
    if !*closed {
        *closed = true;
        CLOSED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }
    HostGlueDeviceCloseResult {
        payload: HostGlueDeviceCloseResultPayload { ok: [] },
        tag: HostGlueDeviceCloseResultTag::Ok,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn virtual_device_uses_framed_protocol_and_persists_apply() {
        let mut state = VirtualState {
            controls: 100,
            sensitivity: 800,
            lighting: true,
            profile: 1,
        };
        assert_eq!(
            virtual_exchange(&mut state, &[0xa5, 1, 2, 0xdc, 0x05, 0, 4]).unwrap(),
            vec![0x5a, 1, 2, 0, 0xdc, 0x05, 0, 4]
        );
        assert_eq!(
            virtual_exchange(&mut state, &[0xa5, 1, 1]).unwrap(),
            vec![0x5a, 1, 1, 0, 100, 0, 0xdc, 0x05, 0, 4]
        );
    }
    #[test]
    fn malformed_frames_are_rejected() {
        let mut state = VirtualState {
            controls: 12,
            sensitivity: 800,
            lighting: true,
            profile: 1,
        };
        assert_eq!(
            virtual_exchange(&mut state, &[1, 1, 1]),
            Err(Reason::Protocol)
        );
    }
}
