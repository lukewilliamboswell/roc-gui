//! Minimal GPUI host for the Roc action/state GUI platform.
#![allow(unsafe_op_in_unsafe_fn)]
#![cfg_attr(test, allow(dead_code, unused_imports))]

mod bridge;
mod observatory;
mod roc_platform_abi;
mod runner;
mod spec;

use bridge::{BridgeState, MountedGraph, Node, NodeKind, Patch, decode_commit, validate_tree};
use gpui::{div, prelude::*, px, rgb, size, *};
use roc_platform_abi::{
    DefaultAllocators, DefaultHandlers, MountOrNoChangeOrReplace, RocErasedCallable, RocHost,
    RocListWith, RocStr, decref_erased_callable, make_roc_host, roc_gui_dispatch, roc_gui_init,
};
use std::{cell::RefCell, collections::HashMap, ffi::c_void, path::PathBuf, time::Instant};

static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

thread_local! {
    static BRIDGE: RefCell<BridgeState> = const { RefCell::new(BridgeState::new()) };
}

fn set_roc_host(host: *mut RocHost) {
    unsafe { ROC_HOST = host };
}

fn roc_host_ptr() -> *mut RocHost {
    let pointer = unsafe { ROC_HOST };
    if pointer.is_null() {
        eprintln!("roc-gui host error: RocHost is not initialized");
        std::process::abort();
    }
    pointer
}

fn roc_host() -> &'static RocHost {
    unsafe { &*roc_host_ptr() }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut c_void {
    observatory::note_roc_alloc(length);
    DefaultAllocators::roc_alloc(roc_host_ptr(), length, alignment)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_dealloc(pointer: *mut c_void, alignment: usize) {
    observatory::note_roc_dealloc();
    DefaultAllocators::roc_dealloc(roc_host_ptr(), pointer, alignment);
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_realloc(
    pointer: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    observatory::note_roc_realloc(new_length);
    DefaultAllocators::roc_realloc(roc_host_ptr(), pointer, new_length, alignment)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_dbg(roc_host_ptr(), bytes, len);
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_expect_failed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_expect_failed(roc_host_ptr(), bytes, len);
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_crashed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_crashed(roc_host_ptr(), bytes, len);
}

extern "C" fn counted_roc_alloc(
    _host: *mut RocHost,
    length: usize,
    alignment: usize,
) -> *mut c_void {
    roc_alloc(length, alignment)
}

extern "C" fn counted_roc_dealloc(_host: *mut RocHost, pointer: *mut c_void, alignment: usize) {
    roc_dealloc(pointer, alignment);
}

extern "C" fn counted_roc_realloc(
    _host: *mut RocHost,
    pointer: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    roc_realloc(pointer, new_length, alignment)
}

fn make_counted_roc_host(env: *mut c_void) -> RocHost {
    let mut host = make_roc_host(env);
    host.roc_alloc = counted_roc_alloc;
    host.roc_dealloc = counted_roc_dealloc;
    host.roc_realloc = counted_roc_realloc;
    host
}

fn stage_node(kind: NodeKind, children: Vec<u64>) -> u64 {
    BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .stage_node(kind, children)
            .unwrap_or_else(|message| panic!("invalid native node build: {message}"))
    })
}

/// Stage one owned text node and return its fresh host identity.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_text(value: RocStr) -> u64 {
    let text = value.as_str().to_owned();
    unsafe { value.decref(roc_host()) };
    stage_node(NodeKind::Text(text), vec![])
}

/// Stage one row whose children were already built during this transaction.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_row(children: RocListWith<u64, false>) -> u64 {
    let children_vec = children.as_slice().to_vec();
    unsafe { children.decref(roc_host()) };
    stage_node(NodeKind::Row, children_vec)
}

/// Stage one column whose children were already built during this transaction.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_column(children: RocListWith<u64, false>) -> u64 {
    let children_vec = children.as_slice().to_vec();
    unsafe { children.decref(roc_host()) };
    stage_node(NodeKind::Column, children_vec)
}

/// Stage one semantically named button whose label was already built.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_button(name: RocStr, label: u64) -> u64 {
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    stage_node(NodeKind::Button { name: owned_name }, vec![label])
}

/// Commit the nodes staged by builder effects as one mount or replacement.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_apply(patch: MountOrNoChangeOrReplace) {
    let commit = decode_commit(&patch);
    unsafe { patch.decref(roc_host()) };
    BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .commit(commit)
            .unwrap_or_else(|message| panic!("invalid native graph commit: {message}"));
    });
}

/// Install the owned dispatcher for the next event turn.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_set_dispatch(dispatcher: RocErasedCallable) {
    assert!(!dispatcher.is_null(), "Roc installed a null dispatcher");
    BRIDGE.with(|bridge| {
        let previous = bridge.borrow_mut().dispatcher.replace(dispatcher);
        if let Some(previous) = previous {
            unsafe { decref_erased_callable(previous, roc_host()) };
        }
    });
}

fn take_patch() -> Patch {
    BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .pending
            .take()
            .expect("Roc dispatch did not emit a native patch")
    })
}

fn dispatch(event_id: u64) -> Patch {
    let dispatcher = BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .dispatcher
            .take()
            .expect("Roc dispatcher is not installed")
    });
    unsafe { roc_gui_dispatch(dispatcher, event_id) };
    BRIDGE.with(|bridge| {
        assert!(
            bridge.borrow().dispatcher.is_some(),
            "Roc dispatch did not install its successor"
        );
    });
    take_patch()
}

fn clear_bridge() {
    BRIDGE.with(|bridge| {
        let mut bridge = bridge.borrow_mut();
        bridge.pending = None;
        if let Some(dispatcher) = bridge.dispatcher.take() {
            unsafe { decref_erased_callable(dispatcher, roc_host()) };
        }
    });
}

fn button_with_name(nodes: &[Node], expected: &str) -> Option<u64> {
    nodes.iter().find_map(|node| {
        matches!(&node.kind, NodeKind::Button { name } if name == expected).then_some(node.id)
    })
}

fn contains_text(nodes: &[Node], expected: &str) -> bool {
    nodes
        .iter()
        .any(|node| matches!(&node.kind, NodeKind::Text(value) if value == expected))
}

fn headless_smoke() {
    unsafe { roc_gui_init() };
    let (initial_root, initial_nodes) = match take_patch() {
        Patch::Mount { root, nodes } => (root, nodes),
        other => panic!("expected initial mount, got {other:?}"),
    };
    validate_tree(initial_root, &initial_nodes).expect("invalid initial counter tree");
    assert!(contains_text(&initial_nodes, "Counter"));
    assert!(contains_text(&initial_nodes, "-1"));
    assert!(contains_text(&initial_nodes, "3"));
    let initial_plus = button_with_name(&initial_nodes, "Left increment")
        .expect("left counter increment button is missing");

    assert_eq!(
        dispatch(u64::MAX),
        Patch::NoChange,
        "stale event was not ignored"
    );

    let (first_target, first_nodes) = match dispatch(initial_plus) {
        Patch::Replace {
            old_root,
            root,
            nodes,
        } => {
            validate_tree(root, &nodes).expect("invalid first counter replacement");
            (old_root, nodes)
        }
        other => panic!("expected first subtree replacement, got {other:?}"),
    };
    assert_ne!(
        first_target, initial_root,
        "counter update replaced the application root"
    );
    assert!(contains_text(&first_nodes, "0"));
    assert!(
        !contains_text(&first_nodes, "Counter"),
        "static heading leaked into translated patch"
    );
    assert_eq!(
        dispatch(initial_plus),
        Patch::NoChange,
        "removed button id was not treated as stale"
    );

    let next_plus = button_with_name(&first_nodes, "Left increment")
        .expect("replacement increment button is missing");
    let second_nodes = match dispatch(next_plus) {
        Patch::Replace { root, nodes, .. } => {
            validate_tree(root, &nodes).expect("invalid second counter replacement");
            nodes
        }
        other => panic!("expected second subtree replacement, got {other:?}"),
    };
    assert!(
        contains_text(&second_nodes, "1"),
        "second handler did not receive the latest state"
    );
    eprintln!("PASS: Roc counter dispatched -1 -> 0 -> 1 using translated subtree patches");
}

struct NodeView {
    node: Node,
    children: Vec<Entity<NodeView>>,
    runtime: WeakEntity<Runtime>,
}

impl Render for NodeView {
    fn render(&mut self, _: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let mut element = div().id(("node", self.node.id));
        match &self.node.kind {
            NodeKind::Column => {
                element = element.flex().flex_col().gap_3();
            }
            NodeKind::Row => {
                element = element.flex().flex_row().items_center().gap_3();
            }
            NodeKind::Text(value) => {
                element = element.child(value.clone());
            }
            NodeKind::Button { .. } => {
                let node_id = self.node.id;
                let runtime = self.runtime.clone();
                element = element
                    .flex()
                    .items_center()
                    .justify_center()
                    .px_3()
                    .py_2()
                    .rounded_md()
                    .bg(rgb(0x315469))
                    .hover(|style| style.bg(rgb(0x3e6a83)))
                    .active(|style| style.bg(rgb(0x274453)))
                    .cursor_pointer()
                    .on_click(move |_, _, cx| {
                        let _ =
                            runtime.update(cx, |runtime, cx| runtime.event_if_live(node_id, cx));
                    });
            }
        }
        element.children(self.children.iter().cloned().map(AnyView::from))
    }
}

struct Runtime {
    graph: MountedGraph,
    views: HashMap<u64, Entity<NodeView>>,
    root: Option<Entity<NodeView>>,
    cycle_ordinal: u64,
}

impl Runtime {
    fn new(cx: &mut Context<Self>) -> Self {
        let mut runtime = Self {
            graph: MountedGraph::default(),
            views: HashMap::new(),
            root: None,
            cycle_ordinal: 0,
        };
        if observatory::active() {
            let cycle_started = Instant::now();
            let roc_started = Instant::now();
            unsafe { roc_gui_init() };
            let roc_callback_ns = elapsed_ns(roc_started);
            let patch = take_patch();
            runtime.apply_recorded(patch, "init", cycle_started, roc_callback_ns, cx);
        } else {
            unsafe { roc_gui_init() };
            let patch = take_patch();
            runtime.apply_unrecorded(patch, cx);
        }
        runtime
    }

    fn event_if_live(&mut self, id: u64, cx: &mut Context<Self>) {
        if !matches!(
            self.graph.node(id).map(|node| &node.kind),
            Some(NodeKind::Button { .. })
        ) {
            return;
        }
        if observatory::active() {
            let cycle_started = Instant::now();
            let roc_started = Instant::now();
            let patch = dispatch(id);
            let roc_callback_ns = elapsed_ns(roc_started);
            self.apply_recorded(patch, "click", cycle_started, roc_callback_ns, cx);
        } else {
            let patch = dispatch(id);
            self.apply_unrecorded(patch, cx);
        }
    }

    /// Return GPUI's most recently prepainted bounds for a live node. A node
    /// has no actionable bounds until it has participated in a real frame.
    fn apply_unrecorded(&mut self, patch: Patch, cx: &mut Context<Self>) {
        let applied = self
            .graph
            .apply(patch)
            .unwrap_or_else(|message| panic!("invalid native graph patch: {message}"));
        self.apply_to_gpui(&applied, cx);
    }

    fn apply_recorded(
        &mut self,
        patch: Patch,
        trigger: &'static str,
        cycle_started: Instant,
        roc_callback_ns: u64,
        cx: &mut Context<Self>,
    ) {
        let applied = self
            .graph
            .apply_measured(patch)
            .unwrap_or_else(|message| panic!("invalid native graph patch: {message}"));
        let graph_apply_ns = applied.facts.apply_ns;
        let gpui_started = Instant::now();
        self.apply_to_gpui(&applied, cx);
        let gpui_apply_ns = elapsed_ns(gpui_started);
        observatory::cycle(observatory::Cycle {
            run_id: 1,
            ordinal: self.cycle_ordinal,
            step_ordinal: None,
            measurement_phase: "interactive",
            trigger,
            patch_kind: applied.facts.kind,
            duration_ns: elapsed_ns(cycle_started),
            roc_callback_ns,
            validate_ns: applied.facts.validate_ns,
            apply_ns: graph_apply_ns.saturating_add(gpui_apply_ns),
            graph_apply_ns,
            gpui_apply_ns: Some(gpui_apply_ns),
            staged_nodes: applied.facts.staged,
            removed_nodes: applied.facts.removed,
            live_nodes: applied.facts.live,
            parent_nodes_scanned: applied.facts.scanned,
        });
        self.cycle_ordinal += 1;
    }

    fn apply_to_gpui(&mut self, applied: &bridge::GraphApply, cx: &mut Context<Self>) {
        self.materialize(&applied.staged_ids, cx);
        if let Some(root_id) = applied.root {
            let new_root = self.views[&root_id].clone();
            if let Some((parent_id, position)) = applied.parent {
                let parent_view = self.views[&parent_id].clone();
                parent_view.update(cx, |view, cx| {
                    view.node.children[position] = root_id;
                    view.children[position] = new_root.clone();
                    cx.notify();
                });
            } else {
                self.root = Some(new_root);
                cx.notify();
            }
        }
        for id in &applied.removed_ids {
            self.views.remove(id);
        }
    }

    fn materialize(&mut self, node_ids: &[u64], cx: &mut Context<Self>) {
        for id in node_ids {
            let node = self.graph.node(*id).expect("applied node is missing");
            assert!(
                !self.views.contains_key(&node.id),
                "node id {} was reused",
                node.id
            );
            let runtime = cx.entity().downgrade();
            let value = node.clone();
            let view = cx.new(|_| NodeView {
                node: value,
                children: vec![],
                runtime,
            });
            self.views.insert(node.id, view);
        }
        for id in node_ids {
            let node = self.graph.node(*id).expect("applied node is missing");
            let children = node
                .children
                .iter()
                .map(|id| {
                    self.views
                        .get(id)
                        .expect("validated child is missing")
                        .clone()
                })
                .collect();
            self.views[&node.id].update(cx, |view, _| view.children = children);
        }
    }
}

fn elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}

impl Render for Runtime {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("roc-gui-root")
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .bg(rgb(0x16252c))
            .text_color(rgb(0xeeeeea))
            .text_lg()
            .children(self.root.iter().cloned().map(AnyView::from))
    }
}

struct HostArgs {
    app_name: String,
    headless_smoke: bool,
    spec_path: Option<PathBuf>,
    stats_record: bool,
    stats_output: Option<PathBuf>,
    stats_detail: observatory::Detail,
    stats_buffer_mib: usize,
    stats_max_mib: u64,
    stats_job_count: usize,
}

fn parse_host_args() -> Result<HostArgs, String> {
    let mut arguments = std::env::args();
    let executable = arguments.next().unwrap_or_else(|| "roc-gui-app".into());
    let app_name = std::path::Path::new(&executable)
        .file_stem()
        .and_then(|name| name.to_str())
        .unwrap_or("roc-gui-app")
        .to_owned();
    let mut parsed = HostArgs {
        app_name,
        headless_smoke: false,
        spec_path: None,
        stats_record: false,
        stats_output: None,
        stats_detail: observatory::Detail::Standard,
        stats_buffer_mib: 4,
        stats_max_mib: 4096,
        stats_job_count: 1,
    };
    let mut pending = arguments.peekable();
    while let Some(argument) = pending.next() {
        if argument == "--headless-smoke" {
            parsed.headless_smoke = true;
        } else if argument == "--host-stats-record" {
            parsed.stats_record = true;
        } else if argument == "--host-run-spec" {
            let path = pending
                .next()
                .ok_or_else(|| "--host-run-spec requires a .scm path".to_string())?;
            parsed.spec_path = Some(path.into());
        } else if let Some(path) = argument.strip_prefix("--host-run-spec=") {
            parsed.spec_path = Some(path.into());
        } else if let Some(path) = argument.strip_prefix("--host-stats-output=") {
            parsed.stats_output = Some(path.into());
            parsed.stats_record = true;
        } else if let Some(value) = argument.strip_prefix("--host-stats-detail=") {
            parsed.stats_detail = observatory::Detail::parse(value)
                .ok_or_else(|| "stats detail must be summary, standard, or full".to_string())?;
            parsed.stats_record = true;
        } else if let Some(value) = argument.strip_prefix("--host-stats-buffer-mib=") {
            parsed.stats_buffer_mib = value
                .parse()
                .map_err(|_| "stats buffer MiB must be an integer".to_string())?;
            parsed.stats_record = true;
        } else if let Some(value) = argument.strip_prefix("--host-stats-max-mib=") {
            parsed.stats_max_mib = value
                .parse()
                .map_err(|_| "stats maximum MiB must be an integer".to_string())?;
            parsed.stats_record = true;
        } else if let Some(value) = argument.strip_prefix("--host-stats-job-count=") {
            parsed.stats_job_count = value
                .parse()
                .map_err(|_| "stats job count must be a positive integer".to_string())?;
            if parsed.stats_job_count == 0 {
                return Err("stats job count must be a positive integer".into());
            }
            parsed.stats_record = true;
        } else {
            return Err(format!("unknown host argument: {argument}"));
        }
    }
    if parsed.headless_smoke && parsed.spec_path.is_some() {
        return Err("--headless-smoke and --host-run-spec are mutually exclusive".into());
    }
    Ok(parsed)
}

fn start_requested_recorder(
    args: &HostArgs,
    parsed_spec: Option<&spec::Spec>,
    spec_hash: Option<String>,
) -> Result<Option<PathBuf>, String> {
    if !args.stats_record && args.spec_path.is_none() {
        return Ok(None);
    }
    let path = args
        .stats_output
        .clone()
        .unwrap_or_else(|| observatory::default_path(&args.app_name));
    let benchmark = parsed_spec.and_then(|case| case.benchmark).map(|value| {
        (
            value.warmups,
            value.samples,
            value.iterations,
            value.scale,
            value.initial_size,
            value.change_size,
        )
    });
    observatory::start(observatory::Config {
        path: path.clone(),
        detail: args.stats_detail,
        buffer_mib: args.stats_buffer_mib,
        max_mib: args.stats_max_mib,
        backend: if args.spec_path.is_some() || args.headless_smoke {
            "semantic-headless"
        } else {
            "gpui-wayland"
        },
        app_name: args.app_name.clone(),
        spec_name: parsed_spec.map(|case| case.name.clone()),
        spec_hash,
        benchmark,
        job_count: args.stats_job_count,
        patch_expected: parsed_spec.is_some_and(|case| {
            case.steps
                .iter()
                .any(|step| matches!(step.command, spec::Command::ExpectPatch(_)))
        }),
    })?;
    Ok(Some(path))
}

#[unsafe(no_mangle)]
#[cfg(not(test))]
pub unsafe extern "C" fn main(_argc: i32, _argv: *const *const i8) -> i32 {
    let mut host = make_counted_roc_host(core::ptr::null_mut());
    set_roc_host(&mut host);

    let args = match parse_host_args() {
        Ok(args) => args,
        Err(message) => {
            eprintln!("roc-gui host error: {message}");
            set_roc_host(core::ptr::null_mut());
            return 2;
        }
    };
    let parsed_spec = match args.spec_path.as_ref() {
        Some(path) => match std::fs::read(path) {
            Ok(source) => match std::str::from_utf8(&source) {
                Ok(text) => match spec::parse(text) {
                    Ok(case) => Some((case, observatory::stable_hash(&source))),
                    Err(error) => {
                        eprintln!("{}: {error}", path.display());
                        set_roc_host(core::ptr::null_mut());
                        return 2;
                    }
                },
                Err(error) => {
                    eprintln!("{}: invalid UTF-8: {error}", path.display());
                    set_roc_host(core::ptr::null_mut());
                    return 2;
                }
            },
            Err(error) => {
                eprintln!("cannot read {}: {error}", path.display());
                set_roc_host(core::ptr::null_mut());
                return 2;
            }
        },
        None => None,
    };
    let stats_path = match start_requested_recorder(
        &args,
        parsed_spec.as_ref().map(|(case, _)| case),
        parsed_spec.as_ref().map(|(_, hash)| hash.clone()),
    ) {
        Ok(path) => path,
        Err(message) => {
            eprintln!("roc-gui stats error: {message}");
            set_roc_host(core::ptr::null_mut());
            return 2;
        }
    };

    if let Some((case, _)) = parsed_spec.as_ref() {
        let result = runner::run(case);
        let outcome = if result.is_ok() { "success" } else { "failure" };
        let finalized = observatory::finish(outcome);
        clear_bridge();
        set_roc_host(core::ptr::null_mut());
        if let Err(message) = result {
            eprintln!("FAIL: {}: {message}", case.name);
            return 1;
        }
        if let Err(message) = finalized {
            eprintln!("roc-gui stats error: {message}");
            return 1;
        }
        eprintln!("PASS: {}", case.name);
        if let Some(path) = stats_path {
            eprintln!("capture: {}", path.display());
        }
        return 0;
    }

    if args.headless_smoke {
        if observatory::active() {
            observatory::run_start(1, "test", None, 0, observatory::now_ns());
        }
        headless_smoke();
        if observatory::active() {
            observatory::run_end(1, "pass", observatory::now_ns(), None);
        }
        let finalized = observatory::finish("success");
        clear_bridge();
        set_roc_host(core::ptr::null_mut());
        return if finalized.is_ok() { 0 } else { 1 };
    }

    if observatory::active() {
        observatory::run_start(1, "interactive", None, 0, observatory::now_ns());
    }

    Application::new().run(|cx| {
        cx.on_window_closed(|cx| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();

        let bounds = Bounds::centered(None, size(px(480.), px(240.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some("Roc GUI".into()),
                    ..Default::default()
                }),
                ..Default::default()
            },
            |_, cx| cx.new(Runtime::new),
        )
        .expect("failed to open GPUI window");
        cx.activate(true);
    });

    if observatory::active() {
        observatory::run_end(1, "pass", observatory::now_ns(), None);
    }
    let finalized = observatory::finish("success");
    clear_bridge();
    set_roc_host(core::ptr::null_mut());
    if let Err(message) = finalized {
        eprintln!("roc-gui stats error: {message}");
    }
    if let Some(path) = stats_path {
        eprintln!("capture: {}", path.display());
    }
    0
}

#[cfg(test)]
mod tests {
    use super::{
        counted_roc_alloc, counted_roc_dealloc, counted_roc_realloc, make_counted_roc_host,
    };

    #[test]
    fn host_internal_allocators_use_counted_runtime_routes() {
        let host = make_counted_roc_host(core::ptr::null_mut());

        assert_eq!(
            host.roc_alloc as usize,
            counted_roc_alloc as *const () as usize
        );
        assert_eq!(
            host.roc_dealloc as usize,
            counted_roc_dealloc as *const () as usize
        );
        assert_eq!(
            host.roc_realloc as usize,
            counted_roc_realloc as *const () as usize
        );
    }
}
