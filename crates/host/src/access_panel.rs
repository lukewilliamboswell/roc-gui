//! The trusted App access surface.
//!
//! `docs/resource-access.adoc` says a person can withdraw a grant. Until this
//! existed, only a specification could: `grant::revoke` was reachable from a
//! test step and from nothing a person could press. A model whose most
//! reassuring sentence is unreachable is a model nobody has reason to believe.
//!
//! It is drawn by the host, as a sibling of the application's root, from
//! `grant::enumerate` — never by the application. That is the whole point. The
//! contract is explicit that an `Elem.dialog` rendered by application code is
//! not proof of trusted consent, and the same holds for withdrawal: a surface
//! an application draws is a surface an application can lie on, suppress, or
//! decline to offer. This one is not in the mounted graph, carries no node
//! identity, and is not reachable from any locator, so an application cannot
//! find it, style it, or know it is open.

use gpui::{
    Context, InteractiveElement, IntoElement, ParentElement, StatefulInteractiveElement, Styled,
    div, px, rgb,
};

use crate::grant;
use std::sync::atomic::{AtomicBool, Ordering};

/// Whether the surface is showing. Host-owned global state rather than a field
/// on the runtime entity: the action handler runs while GPUI is dispatching, and
/// a handler that leases the entity to flip a flag is a handler that can collide
/// with the frame being built. It is also what lets the window runner ask
/// whether the surface drew, which a specification that can only see the
/// application cannot.
static OPEN: AtomicBool = AtomicBool::new(false);

/// Whether the surface has actually rendered since it was last opened.
///
/// Asking only whether it is *meant* to be open answers a question about a
/// flag. A specification that checks the flag passes while the surface is
/// suppressed, which is how the first version of this case passed against a
/// window that never drew it, so the flag alone is not what a specification is
/// allowed to believe.
static DREW: AtomicBool = AtomicBool::new(false);

/// Showing, and having drawn at least once since it was opened.
pub fn is_open() -> bool {
    OPEN.load(Ordering::Relaxed) && DREW.load(Ordering::Relaxed)
}

/// Whether the host should draw it on this frame.
pub fn wants_draw() -> bool {
    OPEN.load(Ordering::Relaxed)
}

/// Flip the surface. Called by the host's own chord and by nothing else.
pub fn request_toggle() {
    DREW.store(false, Ordering::Relaxed);
    OPEN.fetch_xor(true, Ordering::Relaxed);
}

/// Ink and ground for the surface. Deliberately not the application's palette:
/// this is not the application's window furniture, and it should not be
/// mistakable for it.
const GROUND: u32 = 0x101820;
const PANEL: u32 = 0x1b2733;
const INK: u32 = 0xeef2f5;
const QUIET: u32 = 0x93a4b3;
const ALARM: u32 = 0xd06a5a;
const EDGE: u32 = 0x33475b;

/// One row's worth of what the surface knows, so the renderer never reaches
/// into the registry twice and cannot show a grant it is not also able to act
/// on.
struct Row {
    kind: grant::Kind,
    id: u64,
    origin: grant::Origin,
    description: String,
    revoked: bool,
    is_root: bool,
}

fn rows(entries: Vec<grant::Grant>) -> Vec<Row> {
    entries
        .into_iter()
        .map(|entry| Row {
            kind: entry.kind(),
            id: entry.number(),
            origin: entry.origin(),
            description: entry.describe(),
            revoked: entry.is_revoked(),
            is_root: entry.is_root(),
        })
        .collect()
}

/// What a person reads instead of a rights vocabulary. The type of the handle
/// is the permission, so the surface says what the authority is *over* and
/// leaves the bitfield to the evidence.
///
/// It says only what the resource is, never how it was obtained. An earlier
/// version read "A folder you chose", which drew above the line "provided by a
/// command-line flag" and asserted a decision nobody had made. Provenance is
/// [`arrival`]'s to state, once, where it can be true.
fn plain(kind: grant::Kind) -> &'static str {
    match kind {
        grant::Kind::AppData => "This application's private storage",
        grant::Kind::Assets => "Files shipped inside this application",
        grant::Kind::Audio => "Audio output",
        grant::Kind::Clipboard => "The clipboard",
        grant::Kind::Device => "A connected device",
        grant::Kind::Directory => "A folder",
        grant::Kind::Document => "A document",
        grant::Kind::Http => "A network destination",
        grant::Kind::Process => "A command session",
        grant::Kind::Sqlite => "A database opened from a folder or file",
        grant::Kind::SystemMonitor => "This computer's running processes",
        grant::Kind::Tcp => "A network connection",
        grant::Kind::Watch => "Changes to a folder or database",
    }
}

/// How the authority arrived, said the way a person would ask it. A flag is
/// named as a flag: the contract requires development provisioning never be
/// presented as somebody's decision.
fn arrival(origin: grant::Origin) -> &'static str {
    match origin {
        grant::Origin::TrustedSelection(grant::Enforcement::Brokered) => "you chose it",
        grant::Origin::TrustedSelection(grant::Enforcement::ConsentOnly) => {
            "you chose it — this build cannot enforce the limit"
        }
        grant::Origin::Provisioned => "provided by a command-line flag",
        grant::Origin::Automatic => "provided automatically; it holds nothing of yours",
    }
}

pub fn render(
    runtime_entity: &gpui::Entity<crate::Runtime>,
    cx: &mut Context<crate::Runtime>,
) -> impl IntoElement {
    // Recorded here, in the one place the surface is actually built, so that
    // "open" means drawn rather than intended.
    DREW.store(true, Ordering::Relaxed);
    let listed = rows(grant::enumerate());
    let count = listed.len();
    let empty = listed.is_empty();
    let entity = runtime_entity.clone();
    let _ = cx;

    div()
        .absolute()
        .top_0()
        .left_0()
        .size_full()
        .flex()
        .items_center()
        .justify_center()
        .bg(rgb(GROUND))
        .text_color(rgb(INK))
        .child(
            div()
                .flex()
                .flex_col()
                .gap(px(10.0))
                .w(px(640.0))
                .p(px(24.0))
                .rounded(px(12.0))
                .bg(rgb(PANEL))
                .border_1()
                .border_color(rgb(EDGE))
                .child(div().text_lg().child("App access"))
                .child(
                    div()
                        .text_color(rgb(QUIET))
                        .text_sm()
                        .child(if empty {
                            "This application is holding nothing of yours.".to_owned()
                        } else {
                            format!(
                                "{} grant(s). Withdrawing one withdraws everything derived from it.",
                                count
                            )
                        }),
                )
                .children(listed.into_iter().map(move |row| {
                    let entity = entity.clone();
                    let (kind, id) = (row.kind, row.id);
                    div()
                        .flex()
                        .items_center()
                        .gap(px(12.0))
                        .py(px(8.0))
                        .border_b_1()
                        .border_color(rgb(EDGE))
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .flex_grow(1.0)
                                .child(div().child(plain(row.kind).to_owned()))
                                .child(
                                    div()
                                        .text_sm()
                                        .text_color(rgb(QUIET))
                                        .child(arrival(row.origin).to_owned()),
                                )
                                // The exact grant, in the same words the
                                // evidence uses, under the sentence a person
                                // reads. Both, so the surface can be believed
                                // by someone deciding and checked by someone
                                // auditing.
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(rgb(EDGE))
                                        .child(row.description.clone()),
                                ),
                        )
                        .child(if row.revoked {
                            div()
                                .text_sm()
                                .text_color(rgb(ALARM))
                                .child("withdrawn")
                                .into_any_element()
                        } else if row.is_root {
                            div()
                                // Grant identifiers are local to a resource
                                // kind, so both parts are required for a
                                // unique GPUI element identity.
                                .id((kind.name(), id))
                                .px(px(12.0))
                                .py(px(4.0))
                                .rounded(px(6.0))
                                .border_1()
                                .border_color(rgb(ALARM))
                                .text_sm()
                                .text_color(rgb(ALARM))
                                .child("Withdraw")
                                .on_click(move |_, _, cx| {
                                    grant::revoke(kind, id);
                                    entity.update(cx, |_, cx| cx.notify());
                                })
                                .into_any_element()
                        } else {
                            // A derived grant is withdrawn with its root, so
                            // offering a control here would imply a choice that
                            // does not exist.
                            div()
                                .text_xs()
                                .text_color(rgb(QUIET))
                                .child("with its parent")
                                .into_any_element()
                        })
                }))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(QUIET))
                        .child(
                            "Work already finished stays finished. Withdrawing stops what happens next."
                                .to_owned(),
                        ),
                ),
        )
}
