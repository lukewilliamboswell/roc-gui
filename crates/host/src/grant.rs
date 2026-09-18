//! One grant model for every resource.
//!
//! `docs/resource-access.adoc` states what a grant is: resource identity,
//! operations, parent grant, application identity, lifetime, revocation state,
//! and budget. Before this module that sentence was implemented once, privately,
//! inside `files.rs`, and nowhere else: every other resource kept an ad-hoc
//! handle map with no lineage, no record of how its authority arrived, and no
//! revocation at all. A model that one resource implements is not a model.
//!
//! The seam is deliberate. This module owns a grant's *metadata and policy*;
//! each resource keeps its own typed payload — a `Dir`, a stream, a device
//! connection — and refers to it by the same id it already uses. Adopting the
//! kernel is therefore a matter of recording a grant when a handle is created,
//! asking before accepting an operation, and releasing when the handle dies. No
//! resource has to surrender its payload to a type-erased registry, and the
//! migration of the remaining resources is mechanical rather than a rewrite.

use std::{
    collections::{HashMap, HashSet},
    sync::{Mutex, OnceLock},
};

/// The resource family a grant belongs to. One variant per registry that hands
/// out handles, so a grant is addressable as `(kind, id)` without the resources
/// having to agree on a shared id space they do not otherwise need.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Kind {
    AppData,
    Assets,
    Audio,
    Clipboard,
    Device,
    Directory,
    Document,
    Http,
    Process,
    Sqlite,
    SystemMonitor,
    Tcp,
}

impl Kind {
    /// The name this kind carries in evidence. Stable: specifications and the
    /// App access surface both name grants with it.
    pub fn name(self) -> &'static str {
        match self {
            Self::AppData => "app-data",
            Self::Assets => "assets",
            Self::Audio => "audio",
            Self::Clipboard => "clipboard",
            Self::Device => "device",
            Self::Directory => "directory",
            Self::Document => "document",
            Self::Http => "http",
            Self::Process => "process",
            Self::Sqlite => "sqlite",
            Self::SystemMonitor => "system-monitor",
            Self::Tcp => "tcp",
        }
    }
}

/// What the operating system does if the application ignores the Roc API.
///
/// This is the distinction the platform must never blur, and the reason it is a
/// recorded field rather than a paragraph: a trusted surface that *asks* a
/// person is not the same as a broker that *hands over* authority the process
/// could not otherwise obtain, and only the second one survives an application
/// that does not cooperate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Enforcement {
    /// The broker returned authority the confined process could not have
    /// obtained for itself — a descriptor it was handed rather than a path it
    /// reopened. Scope survives an application that ignores the Roc API.
    Brokered,
    /// A person chose the resource in a surface the operating system owns, and
    /// the host then reached it with authority the process already held. Honest
    /// consent, and a real record of a real decision, but nothing outside the
    /// process enforces the scope.
    ConsentOnly,
}

impl Enforcement {
    pub fn name(self) -> &'static str {
        match self {
            Self::Brokered => "brokered",
            Self::ConsentOnly => "consent-only",
        }
    }
}

/// How authority arrived, and therefore what it is worth as evidence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Origin {
    /// A person chose this resource in a surface owned by the operating system.
    TrustedSelection(Enforcement),
    /// A command-line flag provisioned it. Development and automation authority,
    /// which `docs/resource-access.adoc` requires be visibly identified as such
    /// and never represented as user consent.
    Provisioned,
    /// A narrow service the platform provisions without a prompt, because it
    /// carries no user data and no authority beyond itself — shipped assets,
    /// private application storage, ordinary timers.
    Automatic,
}

impl Origin {
    pub fn name(self) -> &'static str {
        match self {
            Self::TrustedSelection(_) => "trusted-selection",
            Self::Provisioned => "provisioned",
            Self::Automatic => "automatic",
        }
    }

    /// The enforcement a grant of this origin carries. Provisioned and automatic
    /// authority is reached with the process's own authority by construction, so
    /// neither can be brokered, and saying so here keeps the answer in one place.
    pub fn enforcement(self) -> Enforcement {
        match self {
            Self::TrustedSelection(enforcement) => enforcement,
            Self::Provisioned | Self::Automatic => Enforcement::ConsentOnly,
        }
    }
}

/// How long a grant is meant to last. Persistence is not yet offered by any
/// resource; the variant exists so that when remembered grants land they are a
/// value in this enum rather than a second lifetime model beside it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lifetime {
    /// Until the process ends or the handle is released.
    Session,
}

impl Lifetime {
    pub fn name(self) -> &'static str {
        match self {
            Self::Session => "session",
        }
    }
}

/// What a handle may do. Shared across resources so that "read" means one thing
/// in evidence whether it is a directory, a document, or a database.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct Rights(u32);

impl Rights {
    /// Read the resource's own contents.
    pub const READ: Self = Self(1 << 0);
    /// Modify the resource's own contents.
    pub const WRITE: Self = Self(1 << 1);
    /// Enumerate what the resource contains without reading any of it.
    pub const LIST: Self = Self(1 << 2);
    /// Produce a narrower child grant beneath this one.
    pub const DERIVE: Self = Self(1 << 3);
    /// Open a connection or session to something outside the process.
    pub const CONNECT: Self = Self(1 << 4);
    /// Observe something the person did not direct at this application.
    pub const CAPTURE: Self = Self(1 << 5);

    pub const fn union(self, other: Self) -> Self {
        Self(self.0 | other.0)
    }

    pub const fn contains(self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }

    /// The rights set, lowest bit first, for evidence and the App access
    /// surface. Ordered so the same set always renders the same way.
    pub fn names(self) -> Vec<&'static str> {
        [
            (Self::READ, "read"),
            (Self::WRITE, "write"),
            (Self::LIST, "list"),
            (Self::DERIVE, "derive"),
            (Self::CONNECT, "connect"),
            (Self::CAPTURE, "capture"),
        ]
        .into_iter()
        .filter(|(right, _)| self.contains(*right))
        .map(|(_, name)| name)
        .collect()
    }
}

/// One grant, as `docs/resource-access.adoc` defines it. The resource's own
/// payload lives with the resource; what is here is everything the platform
/// must be able to say about the grant without knowing what kind it is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Grant {
    pub kind: Kind,
    pub id: u64,
    pub rights: Rights,
    pub origin: Origin,
    pub lifetime: Lifetime,
    /// The grant this one was derived from, absent for a root.
    pub parent: Option<u64>,
    /// The root this grant descends from; a root is its own root. Held directly
    /// rather than walked, so revocation is a comparison and cannot be made
    /// quadratic by a deep derivation chain.
    pub root: u64,
    pub revoked: bool,
}

impl Grant {
    /// A grant may act only while neither it nor its root has been revoked.
    /// `root` carries the whole ancestry, so this is the entire rule.
    pub fn is_live(&self) -> bool {
        !self.revoked
    }

    /// How this grant is named wherever a person or a specification reads it.
    ///
    /// One rendering, used by both the specification assertion and the trusted
    /// App access surface, for the same reason `runner::graph_claim` is one
    /// implementation: a grant must not be able to describe itself one way to
    /// the person it is shown to and another way to the test that checks it.
    ///
    /// Identifiers are deliberately absent. They are allocation order, which is
    /// a fact about the run rather than about the authority, and a specification
    /// that pinned them would fail for reasons that have nothing to do with what
    /// it is claiming. What is here is everything that describes the authority
    /// itself: what it is over, how it arrived, what that arrival is worth,
    /// whether it was derived, what it may do, and whether it still holds.
    pub fn describe(&self) -> String {
        let mut text = format!(
            "{} {}/{} {} {}",
            self.kind.name(),
            self.origin.name(),
            self.origin.enforcement().name(),
            if self.parent.is_none() {
                "root"
            } else {
                "derived"
            },
            self.rights.names().join(",")
        );
        if self.revoked {
            text.push_str(" revoked");
        }
        text
    }
}

#[derive(Default)]
struct Registry {
    grants: HashMap<(Kind, u64), Grant>,
    /// Roots whose authority has been taken away, kept as the durable record of
    /// the revocation rather than only as a flag on the grants that existed at
    /// the time. A grant can be released while its root stays revoked, and a
    /// descendant recorded afterwards must still be refused, so the set outlives
    /// the entries.
    revoked_roots: HashSet<(Kind, u64)>,
    /// Counted here rather than by each resource so that "a grant was revoked"
    /// means one thing across the platform.
    recorded: u64,
    released: u64,
    revoked: u64,
    denied: u64,
}

static REGISTRY: OnceLock<Mutex<Registry>> = OnceLock::new();

fn registry() -> &'static Mutex<Registry> {
    REGISTRY.get_or_init(|| Mutex::new(Registry::default()))
}

fn with<T>(act: impl FnOnce(&mut Registry) -> T) -> T {
    act(&mut registry().lock().expect("grant registry poisoned"))
}

/// Record a root grant: authority that arrived from outside rather than being
/// derived from authority already held.
pub fn record_root(kind: Kind, id: u64, rights: Rights, origin: Origin, lifetime: Lifetime) {
    with(|registry| {
        registry.recorded += 1;
        registry.grants.insert(
            (kind, id),
            Grant {
                kind,
                id,
                rights,
                origin,
                lifetime,
                parent: None,
                root: id,
                revoked: false,
            },
        );
    });
}

/// Record a grant derived from an existing one.
///
/// "Never broadens authority" is a claim about *scope*, not about a rights
/// lattice: a project child stays beneath its parent, a redirect stays within
/// its destination, a selected file reveals no siblings. It is deliberately not
/// implemented as intersecting the child's rights with the parent's, because
/// rights are not comparable across resource shapes — a device grant may
/// `CONNECT` and a device connection may `READ`, and neither is a subset of the
/// other although the second is plainly derived from the first. Intersecting
/// them produced a connection that could do nothing, which is how this was
/// found.
///
/// What the kernel does enforce is the part it can know without understanding
/// the resource: a parent that does not hold [`Rights::DERIVE`] cannot produce a
/// child at all, a child inherits its parent's origin, lifetime and root so it
/// cannot claim to have been chosen by a person when its parent was provisioned
/// by a flag, and deriving from a revoked or absent parent produces nothing,
/// which is what makes revocation cover descendants that do not exist yet. The
/// rights a child carries are the resource's own business, and the resource
/// states them at the one place it creates the child.
/// The parent is passed as the [`Grant`] that [`accept`] returned, not as an id
/// to look up again, and that is the point. Deriving is exercising authority, so
/// the caller must have accepted the parent to do it — there is no way to reach
/// this function without having done so.
///
/// It also fixes lineage at the moment the authority was exercised rather than
/// at the moment the bookkeeping happens, which matters because an operation may
/// consume the parent handle. `Device.connect!` does exactly that: the Roc
/// handle is decref'd inside the call, so by the time the connection exists the
/// grant it came from may already have been released. Looking the parent up
/// again would find nothing and silently produce a connection with no lineage
/// and no revocation. The child keeps the root regardless, so revoking still
/// reaches it.
pub fn record_descendant(kind: Kind, id: u64, rights: Rights, parent: Grant) -> bool {
    if !parent.rights.contains(Rights::DERIVE) {
        return false;
    }
    with(|registry| {
        // Liveness is asked of the root now, not of the copy the caller is
        // holding: that copy was accepted at some earlier instant and says
        // nothing about a revocation since. Asking the root is also what lets a
        // parent be *released* and still derive, which is the ordinary case for
        // an operation that consumes its handle.
        if registry.revoked_roots.contains(&(parent.kind, parent.root)) {
            return false;
        }
        registry.recorded += 1;
        registry.grants.insert(
            (kind, id),
            Grant {
                kind,
                id,
                rights,
                origin: parent.origin,
                lifetime: parent.lifetime,
                parent: Some(parent.id),
                root: parent.root,
                revoked: false,
            },
        );
        true
    })
}

/// Why an operation was not accepted. Distinct outcomes, as the contract
/// requires: a handle that never existed and a handle whose authority was taken
/// away are different facts about the application, and a caller that collapses
/// them tells a person the wrong thing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// No grant is recorded for this handle.
    Unknown,
    /// The grant exists but it, or its root, has been revoked.
    Revoked,
    /// The grant is live but does not carry the right this operation needs.
    Rights,
}

/// The single point at which an operation is accepted against a grant. Every
/// resource operation goes through here, so revocation has one linearisation
/// point for the whole platform rather than one per resource.
pub fn accept(kind: Kind, id: u64, needs: Rights) -> Result<Grant, Refusal> {
    with(|registry| {
        let revoked_roots = &registry.revoked_roots;
        let outcome = match registry.grants.get(&(kind, id)) {
            None => Err(Refusal::Unknown),
            Some(grant)
                if !grant.is_live() || revoked_roots.contains(&(kind, grant.root)) =>
            {
                Err(Refusal::Revoked)
            }
            Some(grant) if !grant.rights.contains(needs) => Err(Refusal::Rights),
            Some(grant) => Ok(*grant),
        };
        if outcome.is_err() {
            registry.denied += 1;
        }
        outcome
    })
}

/// Revoke a grant and everything derived from it, at one instant. Operations
/// accepted before this point follow their own commit rule; operations that
/// reach [`accept`] afterwards fail, including from handles the application is
/// still holding. Bytes already returned to application state cannot be
/// recalled, and this does not pretend otherwise.
///
/// Returns how many grants were revoked, which is the count the evidence uses.
pub fn revoke(kind: Kind, id: u64) -> u64 {
    with(|registry| {
        let Some(target) = registry.grants.get(&(kind, id)).copied() else {
            return 0;
        };
        let root = target.root;
        registry.revoked_roots.insert((kind, root));
        let mut count = 0;
        for grant in registry.grants.values_mut() {
            if grant.kind == kind && grant.root == root && !grant.revoked {
                grant.revoked = true;
                count += 1;
            }
        }
        registry.revoked += count;
        count
    })
}

/// Revoke every root of one kind. What a person means by "stop using my files".
pub fn revoke_kind(kind: Kind) -> u64 {
    with(|registry| {
        let roots: Vec<(Kind, u64)> = registry
            .grants
            .values()
            .filter(|grant| grant.kind == kind)
            .map(|grant| (kind, grant.root))
            .collect();
        registry.revoked_roots.extend(roots);
        let mut count = 0;
        for grant in registry.grants.values_mut() {
            if grant.kind == kind && !grant.revoked {
                grant.revoked = true;
                count += 1;
            }
        }
        registry.revoked += count;
        count
    })
}

/// Drop a grant because its handle is gone. Releasing is not revoking: the
/// authority was not taken away, the application simply stopped holding it, and
/// the contract requires the two never be reported as the same event.
pub fn release(kind: Kind, id: u64) {
    with(|registry| {
        if registry.grants.remove(&(kind, id)).is_some() {
            registry.released += 1;
        }
    });
}

/// Every live grant, ordered so the same registry always renders the same way.
/// This is what the trusted App access surface lists and what specifications
/// assert against; both read it rather than each inventing an answer.
pub fn enumerate() -> Vec<Grant> {
    with(|registry| {
        let mut grants: Vec<Grant> = registry.grants.values().copied().collect();
        grants.sort_by_key(|grant| (grant.kind, grant.id));
        grants
    })
}

/// Recorded, released, revoked, and denied, in that order.
pub fn counters() -> [u64; 4] {
    with(|registry| {
        [
            registry.recorded,
            registry.released,
            registry.revoked,
            registry.denied,
        ]
    })
}

/// Forget one kind's grants without revoking them. Host configuration replaces
/// a resource's provisioning wholesale; the grants that referred to the previous
/// configuration did not have their authority taken away, they ceased to exist.
pub fn forget_kind(kind: Kind) {
    with(|registry| {
        registry.grants.retain(|(held, _), _| *held != kind);
        registry.revoked_roots.retain(|(held, _)| *held != kind);
    });
}

/// Forget everything. The semantic runner mounts one application per lifecycle
/// and a grant from a previous one must not be visible to the next.
pub fn reset() {
    with(|registry| *registry = Registry::default());
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The registry is one process-wide thing, as it is in production, so the
    /// tests take turns with it rather than each racing the others' `reset`.
    /// A failing test poisons the lock; recovering the guard keeps the failure
    /// reported as itself rather than as a cascade of poisoning in its
    /// neighbours.
    static TURN: Mutex<()> = Mutex::new(());

    fn fresh() -> std::sync::MutexGuard<'static, ()> {
        let guard = TURN.lock().unwrap_or_else(|error| error.into_inner());
        reset();
        guard
    }

    #[test]
    fn a_parent_that_cannot_derive_produces_no_children() {
        let _turn = fresh();
        record_root(
            Kind::Directory,
            1,
            Rights::READ.union(Rights::LIST),
            Origin::TrustedSelection(Enforcement::ConsentOnly),
            Lifetime::Session,
        );
        let root = accept(Kind::Directory, 1, Rights::READ).expect("root reads");
        assert!(
            !record_descendant(Kind::Directory, 2, Rights::READ, root),
            "a grant without DERIVE is a leaf, whatever else it can do"
        );
        assert_eq!(accept(Kind::Directory, 2, Rights::READ), Err(Refusal::Unknown));
    }

    #[test]
    fn a_child_carries_the_rights_its_resource_gave_it() {
        // Rights are not comparable across resource shapes. A device grant may
        // connect; the connection it derives may read and write. Neither is a
        // subset of the other, and the kernel must not pretend otherwise.
        let _turn = fresh();
        record_root(
            Kind::Device,
            1,
            Rights::CONNECT.union(Rights::DERIVE),
            Origin::Provisioned,
            Lifetime::Session,
        );
        let device = accept(Kind::Device, 1, Rights::CONNECT).expect("grant connects");
        assert!(record_descendant(
            Kind::Device,
            2,
            Rights::READ.union(Rights::WRITE),
            device
        ));
        let connection = accept(Kind::Device, 2, Rights::WRITE).expect("connection writes");
        assert_eq!(connection.root, 1, "and is still bound to its grant");
    }

    #[test]
    fn a_child_inherits_how_its_parent_was_obtained() {
        let _turn = fresh();
        record_root(
            Kind::Directory,
            1,
            Rights::READ.union(Rights::DERIVE),
            Origin::Provisioned,
            Lifetime::Session,
        );
        let root = accept(Kind::Directory, 1, Rights::READ).expect("root reads");
        record_descendant(Kind::Directory, 2, Rights::READ, root);
        let child = accept(Kind::Directory, 2, Rights::READ).expect("child reads");
        assert_eq!(
            child.origin,
            Origin::Provisioned,
            "a flag-provisioned root must not produce children that claim consent"
        );
        assert_eq!(child.root, 1);
    }

    #[test]
    fn revoking_a_root_takes_its_descendants_with_it() {
        let _turn = fresh();
        record_root(
            Kind::Directory,
            1,
            Rights::READ.union(Rights::DERIVE),
            Origin::TrustedSelection(Enforcement::ConsentOnly),
            Lifetime::Session,
        );
        let root = accept(Kind::Directory, 1, Rights::READ).expect("root reads");
        record_descendant(
            Kind::Directory,
            2,
            Rights::READ.union(Rights::DERIVE),
            root,
        );
        let child = accept(Kind::Directory, 2, Rights::READ).expect("child reads");
        record_descendant(Kind::Directory, 3, Rights::READ, child);
        assert_eq!(revoke(Kind::Directory, 1), 3);
        for id in 1..=3 {
            assert_eq!(accept(Kind::Directory, id, Rights::READ), Err(Refusal::Revoked));
        }
    }

    #[test]
    fn revocation_reaches_a_grandchild_revoked_through_its_parent() {
        let _turn = fresh();
        record_root(
            Kind::Directory,
            1,
            Rights::READ.union(Rights::DERIVE),
            Origin::Automatic,
            Lifetime::Session,
        );
        let root = accept(Kind::Directory, 1, Rights::READ).expect("root reads");
        record_descendant(Kind::Directory, 2, Rights::READ, root);
        // Revoking the child names the root, because the rule is about ancestry
        // rather than about which handle the caller happened to hold.
        assert_eq!(revoke(Kind::Directory, 2), 2);
        assert_eq!(accept(Kind::Directory, 1, Rights::READ), Err(Refusal::Revoked));
    }

    #[test]
    fn a_revoked_parent_grants_no_further_children() {
        let _turn = fresh();
        // The root can derive, so what stops the child below is the revocation
        // and not a missing right.
        record_root(
            Kind::Directory,
            1,
            Rights::READ.union(Rights::DERIVE),
            Origin::Automatic,
            Lifetime::Session,
        );
        let root = accept(Kind::Directory, 1, Rights::READ).expect("root reads");
        assert!(record_descendant(Kind::Directory, 9, Rights::READ, root));
        revoke(Kind::Directory, 1);
        assert!(
            !record_descendant(Kind::Directory, 2, Rights::READ, root),
            "an accepted parent that is later revoked derives nothing, so \
             revocation covers descendants that do not exist yet"
        );
        assert_eq!(accept(Kind::Directory, 2, Rights::READ), Err(Refusal::Unknown));
    }

    #[test]
    fn releasing_a_handle_is_not_revoking_its_authority() {
        let _turn = fresh();
        record_root(
            Kind::Directory,
            1,
            Rights::READ,
            Origin::Automatic,
            Lifetime::Session,
        );
        release(Kind::Directory, 1);
        assert_eq!(counters()[1], 1, "released");
        assert_eq!(counters()[2], 0, "and nothing revoked");
    }

    #[test]
    fn kinds_do_not_revoke_one_another() {
        let _turn = fresh();
        record_root(
            Kind::Directory,
            1,
            Rights::READ,
            Origin::Automatic,
            Lifetime::Session,
        );
        record_root(
            Kind::Tcp,
            1,
            Rights::CONNECT,
            Origin::Provisioned,
            Lifetime::Session,
        );
        assert_eq!(revoke_kind(Kind::Directory), 1);
        assert!(accept(Kind::Tcp, 1, Rights::CONNECT).is_ok());
    }

    #[test]
    fn a_grant_describes_its_authority_and_not_the_run_it_happened_in() {
        let _turn = fresh();
        record_root(
            Kind::Directory,
            1,
            Rights::READ.union(Rights::LIST).union(Rights::DERIVE),
            Origin::TrustedSelection(Enforcement::ConsentOnly),
            Lifetime::Session,
        );
        let root = accept(Kind::Directory, 1, Rights::READ).expect("root reads");
        record_descendant(Kind::Directory, 2, Rights::READ, root);
        assert_eq!(
            enumerate()
                .iter()
                .map(Grant::describe)
                .collect::<Vec<_>>(),
            vec![
                "directory trusted-selection/consent-only root read,list,derive",
                "directory trusted-selection/consent-only derived read",
            ]
        );
        revoke(Kind::Directory, 1);
        assert!(
            enumerate().iter().all(|entry| entry.describe().ends_with(" revoked")),
            "a revoked grant says so wherever it is read"
        );
    }

    #[test]
    fn provisioned_and_automatic_authority_is_never_brokered() {
        assert_eq!(Origin::Provisioned.enforcement(), Enforcement::ConsentOnly);
        assert_eq!(Origin::Automatic.enforcement(), Enforcement::ConsentOnly);
        assert_eq!(
            Origin::TrustedSelection(Enforcement::Brokered).enforcement(),
            Enforcement::Brokered
        );
    }
}
