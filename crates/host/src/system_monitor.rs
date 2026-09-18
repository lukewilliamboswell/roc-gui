use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    sync::atomic::{AtomicU64, Ordering},
    sync::{Arc, Mutex, OnceLock},
};
use sysinfo::{Networks, System};

const MAX_ACTIVE: usize = 16;
const MAX_PROCESSES: usize = 10_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Grant {
    Denied,
    Real,
    Virtual { processes: usize, unavailable: bool },
}

struct RealSampler {
    system: System,
    networks: Networks,
    sequence: u64,
}
struct VirtualSampler {
    processes: usize,
    unavailable: bool,
    sequence: u64,
}
enum Source {
    Real(Box<Mutex<RealSampler>>),
    Virtual(Mutex<VirtualSampler>),
}
struct Sampler {
    source: Source,
    closed: Mutex<bool>,
    sampling: Mutex<bool>,
}
struct Store {
    grant: Grant,
    next: u64,
    samplers: HashMap<u64, Arc<Sampler>>,
    allocations: HashMap<usize, u64>,
}
static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static ACQUIRED: AtomicU64 = AtomicU64::new(0);
static SAMPLED: AtomicU64 = AtomicU64::new(0);
static CLOSED: AtomicU64 = AtomicU64::new(0);

/// What a sampler may do. Reading the host's own processes is observing something
/// the person did not direct at this application, which is capture and not read.
const SAMPLER_RIGHTS: Rights = Rights::CAPTURE;

/// How a sampler grant arrives. The host flag chooses a real `sysinfo` sampler or
/// a deterministic source; either way it is development provisioning, not a
/// person's decision.
const SAMPLER_ORIGIN: Origin = Origin::Provisioned;

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            grant: Grant::Denied,
            next: 1,
            samplers: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}
pub fn configure(grant: Grant) {
    grant::forget_kind(grant::Kind::SystemMonitor);
    store().lock().expect("system monitor store poisoned").grant = grant;
}
pub fn counters() -> (u64, u64, u64) {
    (
        ACQUIRED.load(Ordering::Relaxed),
        SAMPLED.load(Ordering::Relaxed),
        CLOSED.load(Ordering::Relaxed),
    )
}
pub fn active_count() -> usize {
    store()
        .lock()
        .expect("system monitor store poisoned")
        .samplers
        .values()
        .filter(|s| !*s.closed.lock().expect("sampler closed mutex poisoned"))
        .count()
}
pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut guard = store().lock().expect("system monitor store poisoned");
    let released = crate::remove_resource_allocation(&mut guard.allocations, base as usize);
    if let Some(id) = released {
        guard.samplers.remove(&id);
    }
    drop(guard);
    if let Some(id) = released {
        grant::release(grant::Kind::SystemMonitor, id);
    }
}

fn capability(source: Source) -> *mut u64 {
    let mut guard = store().lock().expect("system monitor store poisoned");
    let id = guard.next;
    guard.next = guard.next.checked_add(1).expect("sampler ids exhausted");
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
    guard.samplers.insert(
        id,
        Arc::new(Sampler {
            source,
            closed: Mutex::new(false),
            sampling: Mutex::new(false),
        }),
    );
    crate::register_resource_allocation(
        crate::resource_domain::SYSTEM_MONITOR,
        &mut guard.allocations,
        base,
        id,
    );
    drop(guard);
    grant::record_root(
        grant::Kind::SystemMonitor,
        id,
        SAMPLER_RIGHTS,
        SAMPLER_ORIGIN,
        Lifetime::Session,
    );
    handle
}
/// A sampler, or the code saying why it is not usable. A withdrawn grant and an
/// invalid handle are different facts and are reported as different codes.
fn lookup(handle: *mut u64) -> Result<Arc<Sampler>, u8> {
    let id = unsafe { handle.as_ref().copied() }.ok_or(INVALID_CAPABILITY)?;
    grant::accept(grant::Kind::SystemMonitor, id, Rights::CAPTURE).map_err(refusal)?;
    store()
        .lock()
        .ok()
        .and_then(|guard| guard.samplers.get(&id).cloned())
        .ok_or(INVALID_CAPABILITY)
}

const INVALID_CAPABILITY: u8 = 3;
const REVOKED: u8 = 6;

fn refusal(refusal: grant::Refusal) -> u8 {
    match refusal {
        grant::Refusal::Revoked => REVOKED,
        grant::Refusal::Unknown | grant::Refusal::Rights => INVALID_CAPABILITY,
    }
}

fn acquire_err(code: u8) -> HostGlueSystemAcquireResult {
    HostGlueSystemAcquireResult {
        payload: HostGlueSystemAcquireResultPayload {
            err: ManuallyDrop::new(code),
        },
        tag: HostGlueSystemAcquireResultTag::Err,
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn roc_system_acquire() -> HostGlueSystemAcquireResult {
    if active_count() >= MAX_ACTIVE {
        return acquire_err(5);
    }
    let grant = store().lock().expect("system monitor store poisoned").grant;
    let source = match grant {
        Grant::Denied => return acquire_err(0),
        Grant::Real => Source::Real(Box::new(Mutex::new(RealSampler {
            system: System::new_all(),
            networks: Networks::new_with_refreshed_list(),
            sequence: 0,
        }))),
        Grant::Virtual {
            processes,
            unavailable,
        } => Source::Virtual(Mutex::new(VirtualSampler {
            processes,
            unavailable,
            sequence: 0,
        })),
    };
    ACQUIRED.fetch_add(1, Ordering::Relaxed);
    HostGlueSystemAcquireResult {
        payload: HostGlueSystemAcquireResultPayload {
            ok: ManuallyDrop::new(capability(source)),
        },
        tag: HostGlueSystemAcquireResultTag::Ok,
    }
}

// Flat constructor mirroring the generated glue snapshot record fields.
#[allow(clippy::too_many_arguments)]
fn snapshot(
    sequence: u64,
    available: bool,
    cpu: u16,
    used: u64,
    total: u64,
    disk_read: u64,
    disk_written: u64,
    received: u64,
    transmitted: u64,
    processes: Vec<AnonStruct916a0c1ad2ed4712>,
) -> AnonStruct98efc21233c140ff {
    AnonStruct98efc21233c140ff {
        disk_read_bytes: disk_read,
        disk_written_bytes: disk_written,
        memory_total_bytes: total,
        memory_used_bytes: used,
        network_received_bytes: received,
        network_transmitted_bytes: transmitted,
        sequence,
        processes: unsafe { RocList::from_slice(&processes, roc_host()) },
        cpu_tenths: cpu,
        cpu_available: available,
        disk_available: available,
        memory_available: available,
        network_available: available,
        processes_available: available,
    }
}

fn real_sample(state: &mut RealSampler) -> AnonStruct98efc21233c140ff {
    state.system.refresh_all();
    state.networks.refresh();
    state.sequence += 1;
    let mut processes = state
        .system
        .processes()
        .values()
        .map(|process| AnonStruct916a0c1ad2ed4712 {
            memory_bytes: process.memory(),
            pid: u64::from(process.pid().as_u32()),
            name: RocStr::from_str(&process.name().to_string_lossy(), roc_host()),
            cpu_tenths: (process.cpu_usage().clamp(0.0, 6553.5) * 10.0).round() as u16,
        })
        .collect::<Vec<_>>();
    processes.sort_by(|a, b| {
        b.cpu_tenths
            .cmp(&a.cpu_tenths)
            .then_with(|| b.memory_bytes.cmp(&a.memory_bytes))
            .then_with(|| a.pid.cmp(&b.pid))
    });
    processes.truncate(MAX_PROCESSES);
    let (disk_read, disk_written) =
        state
            .system
            .processes()
            .values()
            .fold((0u64, 0u64), |(read, written), process| {
                let usage = process.disk_usage();
                (
                    read.saturating_add(usage.total_read_bytes),
                    written.saturating_add(usage.total_written_bytes),
                )
            });
    let (received, transmitted) =
        state
            .networks
            .values()
            .fold((0u64, 0u64), |(received, transmitted), data| {
                (
                    received.saturating_add(data.total_received()),
                    transmitted.saturating_add(data.total_transmitted()),
                )
            });
    snapshot(
        state.sequence,
        true,
        (state.system.global_cpu_usage().clamp(0.0, 100.0) * 10.0).round() as u16,
        state.system.used_memory(),
        state.system.total_memory(),
        disk_read,
        disk_written,
        received,
        transmitted,
        processes,
    )
}

fn virtual_sample(state: &mut VirtualSampler) -> AnonStruct98efc21233c140ff {
    state.sequence += 1;
    if state.unavailable {
        return snapshot(state.sequence, false, 0, 0, 0, 0, 0, 0, 0, vec![]);
    }
    let processes = (0..bounded_process_count(state.processes))
        .map(|index| AnonStruct916a0c1ad2ed4712 {
            memory_bytes: 8_000_000 + index as u64 * 4096,
            pid: 1000 + index as u64,
            name: RocStr::from_str(&format!("service-{index:04}"), roc_host()),
            cpu_tenths: ((index * 17 + state.sequence as usize) % 800) as u16,
        })
        .collect();
    snapshot(
        state.sequence,
        true,
        427,
        6_442_450_944 + state.sequence * 4096,
        17_179_869_184,
        state.sequence * 8192,
        state.sequence * 4096,
        state.sequence * 2048,
        state.sequence * 1024,
        processes,
    )
}

fn bounded_process_count(count: usize) -> usize {
    count.min(MAX_PROCESSES)
}

fn sample_err(code: u8) -> HostGlueSystemSampleResult {
    HostGlueSystemSampleResult {
        payload: HostGlueSystemSampleResultPayload {
            err: ManuallyDrop::new(code),
        },
        tag: HostGlueSystemSampleResultTag::Err,
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn roc_system_sample(handle: *mut u64) -> HostGlueSystemSampleResult {
    let sampler = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let sampler = match sampler {
        Ok(sampler) => sampler,
        Err(code) => return sample_err(code),
    };
    if *sampler
        .closed
        .lock()
        .expect("sampler closed mutex poisoned")
    {
        return sample_err(2);
    }
    let Ok(mut sampling) = sampler.sampling.try_lock() else {
        return sample_err(1);
    };
    if *sampling {
        return sample_err(1);
    }
    *sampling = true;
    let value = match &sampler.source {
        Source::Real(state) => real_sample(&mut state.lock().expect("real sampler poisoned")),
        Source::Virtual(state) => {
            virtual_sample(&mut state.lock().expect("virtual sampler poisoned"))
        }
    };
    *sampling = false;
    SAMPLED.fetch_add(1, Ordering::Relaxed);
    HostGlueSystemSampleResult {
        payload: HostGlueSystemSampleResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostGlueSystemSampleResultTag::Ok,
    }
}

fn unit_err(code: u8) -> HostGlueSystemCloseResult {
    HostGlueSystemCloseResult {
        payload: HostGlueSystemCloseResultPayload {
            err: ManuallyDrop::new(code),
        },
        tag: HostGlueSystemCloseResultTag::Err,
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn roc_system_close(handle: *mut u64) -> HostGlueSystemCloseResult {
    let sampler = lookup(handle);
    unsafe { decref_box(handle as RocBox, roc_host()) };
    let sampler = match sampler {
        Ok(sampler) => sampler,
        Err(code) => return unit_err(code),
    };
    let mut closed = sampler
        .closed
        .lock()
        .expect("sampler closed mutex poisoned");
    if !*closed {
        *closed = true;
        CLOSED.fetch_add(1, Ordering::Relaxed);
    }
    HostGlueSystemCloseResult {
        payload: HostGlueSystemCloseResultPayload { ok: [] },
        tag: HostGlueSystemCloseResultTag::Ok,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn virtual_process_count_is_bounded() {
        assert_eq!(bounded_process_count(12_000), MAX_PROCESSES);
    }
    #[test]
    fn unavailable_fixture_is_structural() {
        assert!(!matches!(
            Grant::Virtual {
                processes: 4,
                unavailable: true
            },
            Grant::Virtual {
                unavailable: false,
                ..
            }
        ));
    }
}
