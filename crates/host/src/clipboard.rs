use crate::{roc_host, roc_platform_abi::*};
use std::{
    collections::HashMap,
    mem::ManuallyDrop,
    path::Path,
    sync::{Mutex, OnceLock},
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

pub fn configure(system: bool, fixture: Option<&Path>) -> Result<(), String> {
    if system && fixture.is_some() {
        return Err("choose either system or fixture clipboard authority".into());
    }
    if fixture.is_some_and(|path| !path.is_dir()) {
        return Err("clipboard fixture grant must name a directory".into());
    }
    let mut guard = store()
        .lock()
        .map_err(|_| "clipboard unavailable".to_string())?;
    guard.grant = if fixture.is_some() {
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
    Ok(())
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
    guard.allocations.insert(base, id);
    handle
}

fn valid(handle: *mut u64, guard: &Store) -> bool {
    unsafe { handle.as_ref() }.is_some_and(|id| guard.handles.contains_key(id))
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    if let Ok(mut guard) = store().lock() {
        if let Some(id) = guard.allocations.remove(&(base as usize)) {
            guard.handles.remove(&id);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_clipboard_acquire() -> HostGlueClipboardAcquireResult {
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
    let result = {
        let guard = store().lock().unwrap();
        if !valid(handle, &guard) {
            Err((1, "invalid clipboard capability"))
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
    let owned = text.as_str().to_owned();
    unsafe { text.decref(roc_host()) };
    let result = {
        let mut guard = store().lock().unwrap();
        if !valid(handle, &guard) {
            Err((1, "invalid clipboard capability"))
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
