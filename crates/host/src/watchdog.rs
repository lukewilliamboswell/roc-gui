//! A deadline for the windowed host paths.
//!
//! The GPUI run loop owns the main thread, so a block inside `Application::run`
//! cannot be observed from within it. This watchdog runs on a native thread that
//! never touches GPUI, reports the last milestone the host reached, and exits
//! hard. With `panic = "abort"` there is no unwinding to rely on, so a hard exit
//! is the only honest deadline.

use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::time::{Duration, Instant};

/// How far the windowed startup sequence progressed, in order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Milestone {
    Armed = 0,
    AppRunEntered = 1,
    WindowOpened = 2,
    FirstRender = 3,
    DriverStarted = 4,
}

impl Milestone {
    pub fn label(self) -> &'static str {
        match self {
            Self::Armed => "armed",
            Self::AppRunEntered => "app-run-entered",
            Self::WindowOpened => "window-opened",
            Self::FirstRender => "first-render",
            Self::DriverStarted => "driver-started",
        }
    }

    fn from_raw(raw: u8) -> Self {
        match raw {
            1 => Self::AppRunEntered,
            2 => Self::WindowOpened,
            3 => Self::FirstRender,
            4 => Self::DriverStarted,
            _ => Self::Armed,
        }
    }
}

static REACHED: AtomicU8 = AtomicU8::new(0);
static DONE: AtomicBool = AtomicBool::new(false);

/// Record that the host reached `value`. Milestones never move backwards, so an
/// out-of-order report cannot mask progress that already happened.
pub fn milestone(value: Milestone) {
    REACHED.fetch_max(value as u8, Ordering::Relaxed);
}

/// The last milestone reached so far.
pub fn reached() -> Milestone {
    Milestone::from_raw(REACHED.load(Ordering::Relaxed))
}

/// Stop the watchdog. Safe to call when it was never armed.
pub fn disarm() {
    DONE.store(true, Ordering::Relaxed);
}

/// True when the deadline has passed without the host finishing.
///
/// Split out so the decision is testable without spawning a thread or exiting
/// the process.
pub(crate) fn expired(done: bool, elapsed: Duration, deadline: Duration) -> bool {
    !done && elapsed >= deadline
}

const POLL: Duration = Duration::from_millis(50);

/// Arm a deadline for the windowed host. Exits the process with 101 if the host
/// has not called [`disarm`] in time.
pub fn arm(deadline: Duration) {
    std::thread::Builder::new()
        .name("roc-gui-watchdog".into())
        .spawn(move || {
            let started = Instant::now();
            loop {
                let done = DONE.load(Ordering::Relaxed);
                if expired(done, started.elapsed(), deadline) {
                    break;
                }
                if done {
                    return;
                }
                std::thread::sleep(POLL.min(deadline));
            }
            eprintln!(
                "FAIL: windowed host did not finish within {}ms (last milestone: {}){}",
                deadline.as_millis(),
                reached().label(),
                blocked_by_locked_screen()
            );
            std::process::exit(101);
        })
        .expect("failed to spawn the roc-gui watchdog thread");
}

/// Name the one environmental cause that looks exactly like a hung host.
///
/// A locked macOS screen never presents a frame, so every window specification
/// reaches `driver-started` and then waits for a frame that will not arrive.
/// The deadline alone reads as a defect in the host, which sends whoever hit it
/// looking in the wrong place.
fn blocked_by_locked_screen() -> &'static str {
    #[cfg(target_os = "macos")]
    {
        let locked = std::process::Command::new("ioreg")
            .args(["-n", "Root", "-d1", "-a"])
            .output()
            .ok()
            .and_then(|out| String::from_utf8(out.stdout).ok())
            .is_some_and(|text| {
                // ...<key>CGSSessionScreenIsLocked</key>\n\t<true/>...
                text.split("CGSSessionScreenIsLocked")
                    .nth(1)
                    .is_some_and(|rest| {
                        let value = rest.split("<key>").next().unwrap_or_default();
                        value.contains("<true/>")
                    })
            });
        if locked {
            return "\n       The screen is locked, so no frame is ever presented. \
Window specifications need an unlocked session; this is the environment, not the host.";
        }
    }
    ""
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn milestones_are_ordered_and_labelled() {
        assert!(Milestone::Armed < Milestone::AppRunEntered);
        assert!(Milestone::WindowOpened < Milestone::FirstRender);
        assert!(Milestone::FirstRender < Milestone::DriverStarted);
        assert_eq!(Milestone::WindowOpened.label(), "window-opened");
    }

    #[test]
    fn raw_milestones_round_trip_and_clamp() {
        for value in [
            Milestone::Armed,
            Milestone::AppRunEntered,
            Milestone::WindowOpened,
            Milestone::FirstRender,
            Milestone::DriverStarted,
        ] {
            assert_eq!(Milestone::from_raw(value as u8), value);
        }
        assert_eq!(Milestone::from_raw(200), Milestone::Armed);
    }

    #[test]
    fn a_finished_host_never_expires() {
        assert!(!expired(true, Duration::from_secs(600), Duration::ZERO));
    }

    #[test]
    fn an_unfinished_host_expires_once_the_deadline_passes() {
        assert!(!expired(
            false,
            Duration::from_millis(10),
            Duration::from_secs(5)
        ));
        assert!(expired(
            false,
            Duration::from_secs(5),
            Duration::from_secs(5)
        ));
        assert!(expired(false, Duration::ZERO, Duration::ZERO));
    }
}
