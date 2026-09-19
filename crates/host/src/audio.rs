use crate::grant::{self, Lifetime, Origin, Rights};
use crate::{files, roc_host, roc_platform_abi::*};
use rodio::{Decoder, DeviceSinkBuilder, Player, Source, mixer::Mixer};
use std::{
    collections::HashMap,
    io::Cursor,
    mem::ManuallyDrop,
    num::{NonZeroU16, NonZeroU32},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    thread,
    time::Duration,
};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Grant {
    Denied,
    System,
    Null,
}

enum OutputKeepalive {
    System {
        _sink: rodio::MixerDeviceSink,
    },
    Null {
        stop: Arc<AtomicBool>,
        thread: Option<thread::JoinHandle<()>>,
    },
}

impl Drop for OutputKeepalive {
    fn drop(&mut self) {
        if let Self::Null { stop, thread } = self {
            stop.store(true, Ordering::Release);
            if let Some(handle) = thread.take() {
                let _ = handle.join();
            }
        }
    }
}

struct Output {
    mixer: Mixer,
    _keepalive: OutputKeepalive,
}
struct Track {
    player: Player,
    duration: Duration,
    stopped: bool,
}
struct Store {
    grant: Grant,
    next: u64,
    outputs: HashMap<u64, Output>,
    tracks: HashMap<u64, Track>,
    allocations: HashMap<usize, (u64, bool)>,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
static OPERATIONS: [AtomicU64; 7] = [const { AtomicU64::new(0) }; 7];
pub fn counters() -> ([u64; 7], usize, usize) {
    let operations = std::array::from_fn(|index| OPERATIONS[index].load(Ordering::Relaxed));
    let guard = store().lock().unwrap();
    (operations, guard.outputs.len(), guard.tracks.len())
}
/// What an audio output may do: reach the mixer, and derive the tracks played
/// through it. It is never read or written itself — a track is.
const OUTPUT_RIGHTS: Rights = Rights::CONNECT.union(Rights::DERIVE);

/// What a loaded track may do. Status is a read and transport control is a
/// write; neither is a subset of the output's rights, which is ordinary.
const TRACK_RIGHTS: Rights = Rights::READ.union(Rights::WRITE);

/// How an output grant arrives. The host flag enables the system device or a
/// paced null sink; the ordinary mixer service the contract describes is not yet
/// a person's decision.
const OUTPUT_ORIGIN: Origin = Origin::Provisioned;

/// A withdrawn grant and an invalid handle are different facts, so they carry
/// different codes rather than both reporting an invalid capability.
fn refusal(refusal: grant::Refusal, noun: &'static str) -> (u8, &'static str) {
    match refusal {
        grant::Refusal::Revoked => (7, "audio authority was withdrawn"),
        _ => (1, noun),
    }
}

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| {
        Mutex::new(Store {
            grant: Grant::Denied,
            next: 1,
            outputs: HashMap::new(),
            tracks: HashMap::new(),
            allocations: HashMap::new(),
        })
    })
}

pub fn configure(grant: Grant) {
    grant::forget_kind(grant::Kind::Audio);
    let mut guard = store().lock().unwrap();
    guard.grant = grant;
    guard.outputs.clear();
    guard.tracks.clear();
    guard.allocations.clear();
    for counter in &OPERATIONS {
        counter.store(0, Ordering::Relaxed);
    }
}

fn error(code: u8, message: &'static str) -> HostGlueAudioAcquireErr {
    HostGlueAudioAcquireErr {
        code,
        message: RocStr::from_str(message, roc_host()),
    }
}

fn allocate(guard: &mut Store, id: u64, track: bool) -> *mut u64 {
    let handle = unsafe { allocate_box(8, 8, false, roc_host()) as *mut u64 };
    unsafe { handle.write(id) };
    let base = unsafe { (handle as *mut u8).sub(size_of::<isize>()) } as usize;
    crate::register_resource_allocation(
        crate::resource_domain::AUDIO,
        &mut guard.allocations,
        base,
        (id, track),
    );
    handle
}

fn id(handle: *mut u64) -> Option<u64> {
    unsafe { handle.as_ref().copied() }
}

pub fn route_dealloc(base: *mut std::ffi::c_void) {
    let mut released = None;
    if let Ok(mut guard) = store().lock()
        && let Some((id, track)) =
            crate::remove_resource_allocation(&mut guard.allocations, base as usize)
    {
        if track {
            guard.tracks.remove(&id);
        } else {
            guard.outputs.remove(&id);
        }
        released = Some(id);
    }
    if let Some(id) = released {
        grant::release(grant::Kind::Audio, id);
    }
}

fn null_output() -> Output {
    let (mixer, mut source) = rodio::mixer::mixer(
        NonZeroU16::new(2).unwrap(),
        NonZeroU32::new(44_100).unwrap(),
    );
    let stop = Arc::new(AtomicBool::new(false));
    let worker_stop = stop.clone();
    let thread = thread::Builder::new()
        .name("roc-gui-null-audio".into())
        .spawn(move || {
            while !worker_stop.load(Ordering::Acquire) {
                for _ in 0..88 {
                    if source.next().is_none() {
                        break;
                    }
                }
                thread::sleep(Duration::from_millis(1));
            }
        })
        .expect("failed to start null audio sink");
    Output {
        mixer,
        _keepalive: OutputKeepalive::Null {
            stop,
            thread: Some(thread),
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_audio_acquire() -> HostGlueAudioAcquireResult {
    OPERATIONS[0].fetch_add(1, Ordering::Relaxed);
    let mut guard = store().lock().unwrap();
    let output = match guard.grant {
        Grant::Denied => {
            return HostGlueAudioAcquireResult {
                payload: HostGlueAudioAcquireResultPayload {
                    err: ManuallyDrop::new(error(0, "audio output was not granted")),
                },
                tag: HostGlueAudioAcquireResultTag::Err,
            };
        }
        Grant::Null => null_output(),
        Grant::System => match DeviceSinkBuilder::open_default_sink() {
            Ok(mut sink) => {
                sink.log_on_drop(false);
                Output {
                    mixer: sink.mixer().clone(),
                    _keepalive: OutputKeepalive::System { _sink: sink },
                }
            }
            Err(_) => {
                return HostGlueAudioAcquireResult {
                    payload: HostGlueAudioAcquireResultPayload {
                        err: ManuallyDrop::new(error(6, "default audio output is unavailable")),
                    },
                    tag: HostGlueAudioAcquireResultTag::Err,
                };
            }
        },
    };
    let id = guard.next;
    guard.next += 1;
    guard.outputs.insert(id, output);
    grant::record_root(
        grant::Kind::Audio,
        id,
        OUTPUT_RIGHTS,
        OUTPUT_ORIGIN,
        Lifetime::Session,
    );
    let handle = allocate(&mut guard, id, false);
    HostGlueAudioAcquireResult {
        payload: HostGlueAudioAcquireResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: HostGlueAudioAcquireResultTag::Ok,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_audio_load(
    output_handle: *mut u64,
    dir_handle: *mut u64,
    name: RocStr,
) -> HostGlueAudioLoadResult {
    OPERATIONS[1].fetch_add(1, Ordering::Relaxed);
    let filename = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    let bytes = files::read_bounded(dir_handle, &filename);
    unsafe {
        decref_box(dir_handle as RocBox, roc_host());
    }
    let output_id = id(output_handle);
    unsafe {
        decref_box(output_handle as RocBox, roc_host());
    }
    let fail = |code, message| HostGlueAudioLoadResult {
        payload: HostGlueAudioLoadResultPayload {
            err: ManuallyDrop::new(error(code, message)),
        },
        tag: HostGlueAudioLoadResultTag::Err,
    };
    let bytes = match bytes {
        Ok(bytes) => bytes,
        Err(files::BoundedReadError::InvalidCapability) => {
            return fail(1, "invalid directory capability");
        }
        Err(files::BoundedReadError::InvalidName) => return fail(2, "invalid audio file name"),
        Err(files::BoundedReadError::ResourceLimit) => {
            return fail(3, "audio file exceeds the load limit");
        }
        Err(files::BoundedReadError::Io) => return fail(7, "audio file could not be read"),
    };
    let byte_len = bytes.len() as u64;
    let Ok(decoder) = Decoder::builder()
        .with_data(Cursor::new(bytes))
        .with_byte_len(byte_len)
        .build()
    else {
        return fail(5, "audio media could not be decoded");
    };
    let Some(duration) = decoder.total_duration() else {
        return fail(4, "audio duration is unavailable");
    };
    let mut guard = store().lock().unwrap();
    let parent = match output_id
        .ok_or(grant::Refusal::Unknown)
        .and_then(|value| grant::accept(grant::Kind::Audio, value, Rights::CONNECT))
    {
        Ok(parent) => parent,
        Err(why) => {
            let (code, message) = refusal(why, "invalid audio output capability");
            return fail(code, message);
        }
    };
    let Some(output) = output_id.and_then(|value| guard.outputs.get(&value)) else {
        return fail(1, "invalid audio output capability");
    };
    let (player, source) = Player::new();
    output.mixer.add(source);
    player.append(decoder);
    player.pause();
    let track_id = guard.next;
    guard.next += 1;
    guard.tracks.insert(
        track_id,
        Track {
            player,
            duration,
            stopped: false,
        },
    );
    // A track is the output's child, so losing the output loses everything
    // playing through it, and a track can never outlive the authority that
    // opened the device.
    grant::record_descendant(grant::Kind::Audio, track_id, TRACK_RIGHTS, parent);
    let track = allocate(&mut guard, track_id, true);
    HostGlueAudioLoadResult {
        payload: HostGlueAudioLoadResultPayload {
            ok: ManuallyDrop::new(HostGlueAudioLoadOk {
                duration_ms: duration.as_millis() as u64,
                track,
            }),
        },
        tag: HostGlueAudioLoadResultTag::Ok,
    }
}

fn with_track(
    handle: *mut u64,
    f: impl FnOnce(&mut Track) -> Result<(), (u8, &'static str)>,
) -> HostGlueAudioPlayResult {
    let track_id = id(handle);
    unsafe {
        decref_box(handle as RocBox, roc_host());
    }
    let accepted = track_id
        .ok_or(grant::Refusal::Unknown)
        .and_then(|value| grant::accept(grant::Kind::Audio, value, TRACK_RIGHTS));
    let result = match accepted {
        Err(why) => Err(refusal(why, "invalid audio track capability")),
        Ok(_) => store()
            .lock()
            .unwrap()
            .tracks
            .get_mut(&track_id.unwrap_or(0))
            .ok_or((1, "invalid audio track capability"))
            .and_then(f),
    };
    match result {
        Ok(()) => HostGlueAudioPlayResult {
            payload: HostGlueAudioPlayResultPayload { ok: [] },
            tag: HostGlueAudioPlayResultTag::Ok,
        },
        Err((code, message)) => HostGlueAudioPlayResult {
            payload: HostGlueAudioPlayResultPayload {
                err: ManuallyDrop::new(error(code, message)),
            },
            tag: HostGlueAudioPlayResultTag::Err,
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_audio_play(handle: *mut u64) -> HostGlueAudioPlayResult {
    OPERATIONS[2].fetch_add(1, Ordering::Relaxed);
    with_track(handle, |track| {
        if track.stopped {
            return Err((1, "stopped audio track capability"));
        }
        track.player.play();
        Ok(())
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn roc_audio_pause(handle: *mut u64) -> HostGlueAudioPauseResult {
    OPERATIONS[3].fetch_add(1, Ordering::Relaxed);
    with_track(handle, |track| {
        if track.stopped {
            return Err((1, "stopped audio track capability"));
        }
        track.player.pause();
        Ok(())
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn roc_audio_seek(handle: *mut u64, position_ms: u64) -> HostGlueAudioSeekResult {
    OPERATIONS[4].fetch_add(1, Ordering::Relaxed);
    with_track(handle, |track| {
        if track.stopped {
            return Err((1, "stopped audio track capability"));
        }
        track
            .player
            .try_seek(Duration::from_millis(
                position_ms.min(track.duration.as_millis() as u64),
            ))
            .map_err(|_| (4, "audio track does not support seeking"))
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn roc_audio_stop(handle: *mut u64) -> HostGlueAudioStopResult {
    OPERATIONS[6].fetch_add(1, Ordering::Relaxed);
    with_track(handle, |track| {
        track.player.stop();
        track.stopped = true;
        Ok(())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_audio_status(handle: *mut u64) -> HostGlueAudioStatusResult {
    OPERATIONS[5].fetch_add(1, Ordering::Relaxed);
    let track_id = id(handle);
    unsafe {
        decref_box(handle as RocBox, roc_host());
    }
    let guard = store().lock().unwrap();
    let readable = track_id
        .ok_or(grant::Refusal::Unknown)
        .and_then(|value| grant::accept(grant::Kind::Audio, value, Rights::READ));
    let Some(track) = readable
        .ok()
        .and_then(|_| track_id)
        .and_then(|value| guard.tracks.get(&value))
    else {
        return HostGlueAudioStatusResult {
            payload: HostGlueAudioStatusResultPayload {
                err: ManuallyDrop::new(error(1, "invalid audio track capability")),
            },
            tag: HostGlueAudioStatusResultTag::Err,
        };
    };
    let state = if track.stopped || track.player.empty() {
        3
    } else if track.player.is_paused() {
        2
    } else {
        1
    };
    HostGlueAudioStatusResult {
        payload: HostGlueAudioStatusResultPayload {
            ok: ManuallyDrop::new(HostGlueAudioStatusOk {
                duration_ms: track.duration.as_millis() as u64,
                position_ms: track.player.get_pos().as_millis() as u64,
                state,
            }),
        },
        tag: HostGlueAudioStatusResultTag::Ok,
    }
}
