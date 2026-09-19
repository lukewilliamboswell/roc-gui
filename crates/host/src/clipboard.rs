use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

pub const MAX_TEXT_BYTES: usize = 64 * 1024;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Grant {
    Denied,
    System,
    Fixture,
}

struct Store {
    grant: Grant,
    next: u64,
    sequence: u64,
    text: String,
    handles: HashMap<u64, ()>,
    allocations: HashMap<usize, u64>,
    pending_write: Option<String>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static OPERATIONS: [AtomicU64; 3] = [const { AtomicU64::new(0) }; 3];
/// What a clipboard handle may do. Reading the clipboard observes something the
/// person did not direct at this application, which is capture; writing it is a
/// write. Neither derives anything narrower.
const CLIPBOARD_RIGHTS: Rights = Rights::CAPTURE.union(Rights::WRITE);

/// How it arrives. The host flag chooses the system clipboard or a fixture; the
/// trusted activation the contract asks for is an open backlog entry.
const CLIPBOARD_ORIGIN: Origin = Origin::Provisioned;

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            grant: Grant::Denied,
            next: 1,
            sequence: 0,
            text: String::new(),
            handles: HashMap::new(),
            allocations: HashMap::new(),
            pending_write: None,
        })
    })
}

pub fn configure(system: bool, fixture: bool) -> Result<(), String> {
    grant::forget_kind(grant::Kind::Clipboard);
    if system && fixture {
        return Err("choose either system or fixture clipboard authority".into());
    }
    let mut guard = store()
        .lock()
        .map_err(|_| "clipboard unavailable".to_string())?;
    guard.grant = if fixture {
        Grant::Fixture
    } else if system {
        Grant::System
    } else {
        Grant::Denied
    };
    guard.sequence = 0;
    guard.text.clear();
    guard.pending_write = None;
    guard.handles.clear();
    guard.allocations.clear();
    for counter in &OPERATIONS {
        counter.store(0, Ordering::Relaxed);
    }
    Ok(())
}

pub fn counters() -> ([u64; 3], usize) {
    let operations = std::array::from_fn(|index| OPERATIONS[index].load(Ordering::Relaxed));
    let handles = store()
        .lock()
        .expect("clipboard capability store poisoned")
        .handles
        .len();
    (operations, handles)
}

fn error(code: u8, message: &'static str) -> HostGlueClipboardAcquireErr {
    HostGlueClipboardAcquireErr {
        code,
        message: RocStr::from_str(message, roc_host()),
    }
}

fn allocate_handle(guard: &mut Store) -> *mut u64 {
    let id = guard.next;
    guard.next = guard.next.checked_add(1).expect("clipboard ids exhausted");
    let handle = unsafe { allocate_box(8, 8, false, roc_host()) as *mut u64 };
    unsafe { handle.write(id) };
    let base = unsafe { (handle as *mut u8).sub(core::mem::size_of::<isize>()) } as usize;
    guard.handles.insert(id, ());
    crate::register_resource_allocation(
        crate::resource_domain::CLIPBOARD,
        &mut guard.allocations,
        base,
        id,
    );
    grant::record_root(
        grant::Kind::Clipboard,
        id,
        CLIPBOARD_RIGHTS,
        CLIPBOARD_ORIGIN,
        Lifetime::Session,
    );
    handle
}

/// `Ok` when the handle may act, otherwise the code and message saying why. A
/// withdrawn grant and an invalid handle are different facts.
fn valid(handle: *mut u64, guard: &Store) -> Result<(), (u8, &'static str)> {
    let id = unsafe { handle.as_ref() }.ok_or((1, "invalid clipboard capability"))?;
    if !guard.handles.contains_key(id) {
        return Err((1, "invalid clipboard capability"));
    }
    match grant::accept(grant::Kind::Clipboard, *id, Rights::CAPTURE) {
        Ok(_) => Ok(()),
        Err(grant::Refusal::Revoked) => Err((3, "clipboard authority was withdrawn")),
        Err(_) => Err((1, "invalid clipboard capability")),
    }
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut released = None;
    if let Ok(mut guard) = store().lock()
        && let Some(id) = crate::remove_resource_allocation(&mut guard.allocations, base as usize)
    {
        guard.handles.remove(&id);
        released = Some(id);
    }
    if let Some(id) = released {
        grant::release(grant::Kind::Clipboard, id);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_clipboard_acquire() -> HostGlueClipboardAcquireResult {
    OPERATIONS[0].fetch_add(1, Ordering::Relaxed);
    let mut guard = store().lock().unwrap();
    if guard.grant == Grant::Denied {
        HostGlueClipboardAcquireResult {
            payload: HostGlueClipboardAcquireResultPayload {
                err: ManuallyDrop::new(error(0, "clipboard access was not granted")),
            },
            tag: HostGlueClipboardAcquireResultTag::Err,
        }
    } else {
        let handle = allocate_handle(&mut guard);
        HostGlueClipboardAcquireResult {
            payload: HostGlueClipboardAcquireResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostGlueClipboardAcquireResultTag::Ok,
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_clipboard_read_text(handle: *mut u64) -> HostGlueClipboardReadTextResult {
    OPERATIONS[1].fetch_add(1, Ordering::Relaxed);
    let result = {
        let guard = store().lock().unwrap();
        if let Err(failure) = valid(handle, &guard) {
            Err(failure)
        } else {
            Ok((guard.sequence, guard.text.clone()))
        }
    };
    unsafe { decref_box(handle as RocBox, roc_host()) };
    match result {
        Ok((sequence, text)) => HostGlueClipboardReadTextResult {
            payload: HostGlueClipboardReadTextResultPayload {
                ok: ManuallyDrop::new(HostGlueClipboardReadTextOk {
                    sequence,
                    text: RocStr::from_str(&text, roc_host()),
                }),
            },
            tag: HostGlueClipboardReadTextResultTag::Ok,
        },
        Err((code, message)) => HostGlueClipboardReadTextResult {
            payload: HostGlueClipboardReadTextResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGlueClipboardReadTextResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_clipboard_write_text(
    handle: *mut u64,
    text: RocStr,
) -> HostGlueClipboardWriteTextResult {
    OPERATIONS[2].fetch_add(1, Ordering::Relaxed);
    let owned = text.as_str().to_owned();
    unsafe { text.decref(roc_host()) };
    let result = {
        let mut guard = store().lock().unwrap();
        if let Err(failure) = valid(handle, &guard) {
            Err(failure)
        } else if owned.len() > MAX_TEXT_BYTES {
            Err((2, "clipboard text exceeds 64 KiB"))
        } else {
            if guard.grant == Grant::Fixture {
                if guard.text != owned {
                    guard.sequence = guard.sequence.saturating_add(1);
                    guard.text = owned;
                }
            } else {
                guard.pending_write = Some(owned);
            }
            Ok(())
        }
    };
    unsafe { decref_box(handle as RocBox, roc_host()) };
    match result {
        Ok(()) => HostGlueClipboardWriteTextResult {
            payload: HostGlueClipboardWriteTextResultPayload { ok: [] },
            tag: HostGlueClipboardWriteTextResultTag::Ok,
        },
        Err((code, message)) => HostGlueClipboardWriteTextResult {
            payload: HostGlueClipboardWriteTextResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGlueClipboardWriteTextResultTag::Err,
        },
    }
}

pub fn observe_system(text: Option<String>) {
    let Some(text) = text else { return };
    if text.len() > MAX_TEXT_BYTES {
        return;
    }
    let mut guard = store().lock().unwrap();
    if guard.grant == Grant::System && guard.text != text {
        guard.sequence = guard.sequence.saturating_add(1);
        guard.text = text;
    }
}

pub fn take_system_write() -> Option<String> {
    let mut guard = store().lock().unwrap();
    if guard.grant == Grant::System {
        guard.pending_write.take()
    } else {
        None
    }
}

pub fn inject_fixture(text: String) -> Result<(), String> {
    if text.len() > MAX_TEXT_BYTES {
        return Err("fixture clipboard text exceeds 64 KiB".into());
    }
    let mut guard = store().lock().unwrap();
    if guard.grant != Grant::Fixture {
        return Err("clipboard fixture injection requires a fixture grant".into());
    }
    if guard.text != text {
        guard.sequence = guard.sequence.saturating_add(1);
        guard.text = text;
    }
    Ok(())
}
