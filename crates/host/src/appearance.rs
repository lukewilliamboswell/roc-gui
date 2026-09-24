//! The system appearance, and the adaptive colours that follow it.
//!
//! An application colour reaches the host as one `u64`: an RGB value, the
//! control default, or an adaptive pair of a light and a dark value. A pair is
//! stored as the application wrote it and resolved each time it is painted, so
//! a change of appearance repaints the window without asking the application
//! to render again.
//!
//! The scheme a pair resolves to is the application's preference when it has
//! chosen one, and otherwise the system's. On Linux the system's appearance is
//! the XDG desktop portal's `org.freedesktop.appearance` settings, which GNOME,
//! KDE, and the other desktops publish; reduced motion falls back to GNOME's
//! `enable-animations` where the portal does not publish its own key. A
//! specification, and `--host-theme`, provision the system appearance instead,
//! so a case sees exactly the appearance it names and never the machine's.

use std::sync::{
    Condvar, Mutex, OnceLock,
    atomic::{AtomicBool, Ordering},
};

/// The default colour's encoding: bit 24 alone.
const DEFAULT_BITS: u64 = 0x0100_0000;
/// Marks an adaptive pair: light in bits 0-23, dark in bits 24-47.
const ADAPTIVE_BIT: u64 = 1 << 48;

/// A colour as the application wrote it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Paint {
    Rgb(u32),
    Adaptive { light: u32, dark: u32 },
}

impl Paint {
    /// Decode the platform's colour encoding; the default is `None`.
    pub fn decode(bits: u64) -> Option<Self> {
        if bits == DEFAULT_BITS {
            return None;
        }
        if bits & ADAPTIVE_BIT != 0 {
            return Some(Self::Adaptive {
                light: (bits & 0xff_ffff) as u32,
                dark: ((bits >> 24) & 0xff_ffff) as u32,
            });
        }
        Some(Self::Rgb((bits & 0xff_ffff) as u32))
    }

    /// The RGB value this colour paints with under the effective scheme.
    pub fn resolve(self) -> u32 {
        match self {
            Self::Rgb(value) => value,
            Self::Adaptive { light, dark } => {
                if effective_dark() {
                    dark
                } else {
                    light
                }
            }
        }
    }
}

/// The system's appearance.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Settings {
    pub dark: bool,
    pub reduced_motion: bool,
}

impl Settings {
    /// Bit 0 is a dark scheme and bit 1 reduced motion, as `Appearance.roc`
    /// decodes them.
    pub fn bits(self) -> u8 {
        u8::from(self.dark) | (u8::from(self.reduced_motion) << 1)
    }

    pub fn from_bits(bits: u8) -> Self {
        Self {
            dark: bits & 1 != 0,
            reduced_motion: bits & 2 != 0,
        }
    }

    /// Parse a `--host-theme` value: `light` or `dark`, optionally followed by
    /// `,reduced-motion`.
    pub fn parse(value: &str) -> Result<Self, String> {
        let mut parts = value.split(',');
        let dark = match parts.next() {
            Some("light") => false,
            Some("dark") => true,
            _ => return Err("--host-theme requires light or dark".into()),
        };
        let reduced_motion = match parts.next() {
            None => false,
            Some("reduced-motion") => true,
            Some(other) => return Err(format!("unknown --host-theme option: {other}")),
        };
        if parts.next().is_some() {
            return Err("--host-theme takes at most one option".into());
        }
        Ok(Self {
            dark,
            reduced_motion,
        })
    }
}

/// Which scheme adaptive colours resolve to.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Preference {
    #[default]
    System,
    Light,
    Dark,
}

struct State {
    system: Settings,
    preference: Preference,
}

struct Shared {
    state: Mutex<State>,
    changed: Condvar,
}

static SHARED: OnceLock<Shared> = OnceLock::new();
/// The effective scheme, read on every adaptive paint without a lock.
static EFFECTIVE_DARK: AtomicBool = AtomicBool::new(false);
/// How the window learns that it must repaint.
static REPAINT: OnceLock<async_channel::Sender<()>> = OnceLock::new();

fn shared() -> &'static Shared {
    SHARED.get_or_init(|| Shared {
        state: Mutex::new(State {
            system: Settings::default(),
            preference: Preference::System,
        }),
        changed: Condvar::new(),
    })
}

fn effective(state: &State) -> bool {
    match state.preference {
        Preference::System => state.system.dark,
        Preference::Light => false,
        Preference::Dark => true,
    }
}

pub fn effective_dark() -> bool {
    EFFECTIVE_DARK.load(Ordering::Acquire)
}

/// Install `state` and tell the window when what it paints has changed.
fn publish(state: &State) {
    let dark = effective(state);
    if EFFECTIVE_DARK.swap(dark, Ordering::AcqRel) != dark
        && let Some(repaint) = REPAINT.get()
    {
        let _ = repaint.try_send(());
    }
}

/// Choose the system appearance's source. `provisioned` is what a
/// specification or `--host-theme` names; without it, an interactive run
/// observes the desktop, and waits briefly for its first answer so the first
/// frame is drawn in the right scheme.
pub fn configure(provisioned: Option<Settings>, observe_system: bool) {
    let shared = shared();
    {
        let mut state = shared.state.lock().expect("appearance state poisoned");
        state.system = provisioned.unwrap_or_default();
        state.preference = Preference::System;
        publish(&state);
    }
    if provisioned.is_none() && observe_system {
        observe_desktop();
    }
}

/// A new system appearance, from the desktop or a specification step.
pub fn set_system(settings: Settings) {
    let shared = shared();
    let mut state = shared.state.lock().expect("appearance state poisoned");
    if state.system == settings {
        return;
    }
    state.system = settings;
    publish(&state);
    shared.changed.notify_all();
}

pub fn system() -> Settings {
    shared()
        .state
        .lock()
        .expect("appearance state poisoned")
        .system
}

pub fn prefer(preference: Preference) {
    let mut state = shared().state.lock().expect("appearance state poisoned");
    state.preference = preference;
    publish(&state);
}

/// Block until the system appearance differs from `known`, or the waiting
/// task is cancelled, and return the appearance then.
pub fn next_change(known: Settings) -> Settings {
    let shared = shared();
    let interrupt = crate::tasks::Interrupt::arm(move || {
        let _held = shared.state.lock();
        shared.changed.notify_all();
    });
    let mut state = shared.state.lock().expect("appearance state poisoned");
    while state.system == known && !interrupt.requested() {
        state = shared
            .changed
            .wait(state)
            .expect("appearance state poisoned");
    }
    state.system
}

/// The receiver the window repaints on. Only the first window takes it.
pub fn repaints() -> Option<async_channel::Receiver<()>> {
    let (sender, receiver) = async_channel::bounded(1);
    REPAINT.set(sender).ok().map(|()| receiver)
}

/// One change the desktop reports.
#[cfg(target_os = "linux")]
enum Change {
    Dark(bool),
    Reduced(bool),
}

/// A stream of changes; an answer the portal could not decode is `None`.
#[cfg(target_os = "linux")]
type Changes = std::pin::Pin<Box<dyn async_std::stream::Stream<Item = Option<Change>>>>;

#[cfg(target_os = "linux")]
fn observe_desktop() {
    use async_std::stream::StreamExt;
    use std::time::Duration;
    let (first, answered) = std::sync::mpsc::channel::<()>();
    let spawned = std::thread::Builder::new()
        .name("roc-gui-appearance".into())
        .spawn(move || {
            async_std::task::block_on(async move {
                use ashpd::desktop::settings::{ColorScheme, Settings as Portal};
                const APPEARANCE: &str = "org.freedesktop.appearance";
                let Ok(portal) = Portal::new().await else {
                    let _ = first.send(());
                    return;
                };
                let dark = matches!(portal.color_scheme().await, Ok(ColorScheme::PreferDark));
                let own_motion = portal.read::<u32>(APPEARANCE, "reduced-motion").await.ok();
                let reduced_motion = match own_motion {
                    Some(value) => value == 1,
                    None => portal
                        .read::<bool>("org.gnome.desktop.interface", "enable-animations")
                        .await
                        .is_ok_and(|enabled| !enabled),
                };
                set_system(Settings {
                    dark,
                    reduced_motion,
                });
                let _ = first.send(());
                let schemes =
                    portal
                        .receive_color_scheme_changed()
                        .await
                        .ok()
                        .map(|stream| -> Changes {
                            Box::pin(stream.map(|scheme| {
                                Some(Change::Dark(scheme == ColorScheme::PreferDark))
                            }))
                        });
                let motions =
                    if own_motion.is_some() {
                        portal
                            .receive_setting_changed_with_args::<u32>(APPEARANCE, "reduced-motion")
                            .await
                            .ok()
                            .map(|stream| -> Changes {
                                Box::pin(stream.map(|value| {
                                    value.ok().map(|value| Change::Reduced(value == 1))
                                }))
                            })
                    } else {
                        portal
                            .receive_setting_changed_with_args::<bool>(
                                "org.gnome.desktop.interface",
                                "enable-animations",
                            )
                            .await
                            .ok()
                            .map(|stream| -> Changes {
                                Box::pin(stream.map(|value| {
                                    value.ok().map(|enabled| Change::Reduced(!enabled))
                                }))
                            })
                    };
                // Both watches on this one thread: poll each until both end.
                let mut watches = [schemes, motions];
                std::future::poll_fn(move |context| {
                    use std::task::Poll;
                    loop {
                        let mut open = false;
                        let mut progressed = false;
                        for slot in watches.iter_mut() {
                            let Some(stream) = slot else { continue };
                            match stream.as_mut().poll_next(context) {
                                Poll::Ready(Some(change)) => {
                                    open = true;
                                    progressed = true;
                                    match change {
                                        Some(Change::Dark(dark)) => {
                                            set_system(Settings { dark, ..system() })
                                        }
                                        Some(Change::Reduced(reduced_motion)) => {
                                            set_system(Settings {
                                                reduced_motion,
                                                ..system()
                                            })
                                        }
                                        None => {}
                                    }
                                }
                                Poll::Ready(None) => *slot = None,
                                Poll::Pending => open = true,
                            }
                        }
                        if !open {
                            return Poll::Ready(());
                        }
                        if !progressed {
                            return Poll::Pending;
                        }
                    }
                })
                .await;
            });
        });
    if spawned.is_ok() {
        let _ = answered.recv_timeout(Duration::from_millis(250));
    }
}

#[cfg(not(target_os = "linux"))]
fn observe_desktop() {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colours_decode_as_the_platform_encodes_them() {
        assert_eq!(Paint::decode(DEFAULT_BITS), None);
        assert_eq!(Paint::decode(0x12_3456), Some(Paint::Rgb(0x12_3456)));
        assert_eq!(
            Paint::decode(ADAPTIVE_BIT | (0x0a0b0c << 24) | 0xf0f1f2),
            Some(Paint::Adaptive {
                light: 0xf0f1f2,
                dark: 0x0a0b0c
            })
        );
    }

    /// The one test that changes the process-wide appearance, so no other
    /// test sees it move.
    #[test]
    fn a_pair_follows_the_system_unless_the_application_prefers() {
        let light = Settings::default();
        let dark = Settings {
            dark: true,
            reduced_motion: false,
        };
        configure(Some(light), false);
        let pair = Paint::Adaptive {
            light: 0xeeeeee,
            dark: 0x111111,
        };
        assert_eq!(pair.resolve(), 0xeeeeee);
        assert_eq!(Paint::Rgb(0x123456).resolve(), 0x123456);

        let waiter = std::thread::spawn(move || next_change(light));
        set_system(dark);
        assert_eq!(waiter.join().unwrap(), dark);
        assert_eq!(pair.resolve(), 0x111111);

        prefer(Preference::Light);
        assert_eq!(pair.resolve(), 0xeeeeee);
        assert_eq!(
            system(),
            dark,
            "a preference is not the system's appearance"
        );
        prefer(Preference::System);
        assert_eq!(pair.resolve(), 0x111111);
        configure(Some(light), false);
        assert_eq!(pair.resolve(), 0xeeeeee);
    }

    #[test]
    fn settings_round_trip_and_parse() {
        for bits in 0..4 {
            assert_eq!(Settings::from_bits(bits).bits(), bits);
        }
        assert_eq!(
            Settings::parse("dark,reduced-motion"),
            Ok(Settings {
                dark: true,
                reduced_motion: true
            })
        );
        assert!(Settings::parse("sepia").is_err());
    }
}
