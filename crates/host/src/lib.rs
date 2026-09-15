//! Minimal GPUI host for the Roc action/state GUI platform.
#![allow(unsafe_op_in_unsafe_fn)]
#![cfg_attr(test, allow(dead_code, unused_imports))]

mod bridge;
mod files;
mod observatory;
mod roc_platform_abi;
mod runner;
mod spec;

use bridge::{
    BridgeState, ControlKey, Length, MountedGraph, Node, NodeKind, Overflow, Patch, ScrollAxis,
    Style, decode_commit, validate_tree,
};
use gpui::{div, prelude::*, px, rgb, size, *};
use roc_platform_abi::{
    DefaultAllocators, DefaultHandlers, HostGlueNodeCheckboxArgs, HostGlueNodeColumnArgs,
    HostGlueNodeRowArgs, HostGlueNodeScrollArgs, MountOrNoChangeOrReplace, RocErasedCallable,
    RocHost, RocStr, decref_erased_callable, make_roc_host, roc_gui_dispatch, roc_gui_init,
};
use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::c_void,
    path::PathBuf,
    sync::OnceLock,
    sync::atomic::{AtomicU64, Ordering},
    time::Instant,
};

actions!(
    roc_gui,
    [FocusNext, FocusPrevious, ActivateEnter, ActivateSpace]
);

unsafe extern "C" {
    fn roc_gui_complete(dispatcher: RocErasedCallable, completion: RocErasedCallable);
    fn roc_gui_run_task(task: RocErasedCallable) -> RocErasedCallable;
}

struct TaskRuntime {
    jobs: async_channel::Sender<usize>,
    completions: async_channel::Receiver<usize>,
    accepted: AtomicU64,
    completed: AtomicU64,
}

static TASK_RUNTIME: OnceLock<TaskRuntime> = OnceLock::new();

fn task_runtime() -> &'static TaskRuntime {
    TASK_RUNTIME.get_or_init(|| {
        let (job_sender, job_receiver) = async_channel::unbounded::<usize>();
        let (completion_sender, completion_receiver) = async_channel::unbounded::<usize>();
        let worker_count = std::thread::available_parallelism()
            .map(usize::from)
            .unwrap_or(4)
            .clamp(4, 16);
        for ordinal in 0..worker_count {
            let jobs = job_receiver.clone();
            let completions = completion_sender.clone();
            std::thread::Builder::new()
                .name(format!("roc-gui-worker-{ordinal}"))
                .spawn(move || {
                    while let Ok(task) = jobs.recv_blocking() {
                        let completion = unsafe { roc_gui_run_task(task as RocErasedCallable) };
                        if completions.send_blocking(completion as usize).is_err() {
                            break;
                        }
                    }
                })
                .expect("failed to start Roc task worker");
        }
        TaskRuntime {
            jobs: job_sender,
            completions: completion_receiver,
            accepted: AtomicU64::new(0),
            completed: AtomicU64::new(0),
        }
    })
}

static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

thread_local! {
    static BRIDGE: RefCell<BridgeState> = const { RefCell::new(BridgeState::new()) };
    static WINDOW_CONFIG: RefCell<WindowConfig> = RefCell::new(WindowConfig::default());
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct WindowConfig {
    title: String,
    width: u32,
    height: u32,
}

impl Default for WindowConfig {
    fn default() -> Self {
        Self {
            title: "Roc GUI".into(),
            width: 480,
            height: 240,
        }
    }
}

fn validate_window_config(config: WindowConfig) -> Result<WindowConfig, String> {
    if !(240..=16_384).contains(&config.width) || !(160..=16_384).contains(&config.height) {
        return Err(
            "window width must be 240..16384 and height must be 160..16384 logical pixels".into(),
        );
    }
    Ok(config)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_window_config(title: RocStr, width: u32, height: u32) {
    let title_value = title.as_str().to_owned();
    unsafe { title.decref(roc_host()) };
    let config = validate_window_config(WindowConfig {
        title: title_value,
        width,
        height,
    })
    .unwrap_or_else(|message| panic!("invalid native window configuration: {message}"));
    WINDOW_CONFIG.with(|current| *current.borrow_mut() = config);
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
    files::route_dealloc(pointer);
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

/// Begin a host-owned child sequence. Builders may be nested while recursively lowering.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_children_begin() -> u64 {
    BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .begin_children()
            .unwrap_or_else(|message| panic!("invalid native child build: {message}"))
    })
}

/// Append one already-staged child to a host-owned child sequence.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_children_push(builder: u64, child: u64) {
    BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .push_child(builder, child)
            .unwrap_or_else(|message| panic!("invalid native child build: {message}"));
    });
}

fn finish_children(builder: u64) -> Vec<u64> {
    BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .finish_children(builder)
            .unwrap_or_else(|message| panic!("invalid native child build: {message}"))
    })
}

fn decode_layout_style(
    gap: u32,
    padding: u32,
    width_kind: u8,
    width: u32,
    height_kind: u8,
    height: u32,
    grow: bool,
    bg: u32,
    hover_bg: u32,
    active_bg: u32,
    fg: u32,
    border_color: u32,
    border_width: u32,
    radius: u32,
    font_size: u32,
    overflow_x: u8,
    overflow_y: u8,
) -> Style {
    Style {
        gap,
        padding,
        width: decode_length(width_kind, width),
        height: decode_length(height_kind, height),
        grow,
        bg: decode_color(bg),
        hover_bg: decode_color(hover_bg),
        active_bg: decode_color(active_bg),
        fg: decode_color(fg),
        border_color: decode_color(border_color),
        border_width,
        radius,
        font_size,
        overflow_x: decode_overflow(overflow_x),
        overflow_y: decode_overflow(overflow_y),
    }
}

/// Stage one styled, semantically named row.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_row(args: HostGlueNodeRowArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    unsafe { args.label.decref(roc_host()) };
    let style = decode_layout_style(
        args.gap,
        args.padding,
        args.width_kind,
        args.width,
        args.height_kind,
        args.height,
        args.grow,
        args.bg,
        args.hover_bg,
        args.active_bg,
        args.fg,
        args.border_color,
        args.border_width,
        args.radius,
        args.font_size,
        args.overflow_x,
        args.overflow_y,
    );
    stage_node(
        NodeKind::Row { label, style },
        finish_children(args.builder),
    )
}

/// Stage one styled, semantically named column.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_column(args: HostGlueNodeColumnArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    unsafe { args.label.decref(roc_host()) };
    let style = decode_layout_style(
        args.gap,
        args.padding,
        args.width_kind,
        args.width,
        args.height_kind,
        args.height,
        args.grow,
        args.bg,
        args.hover_bg,
        args.active_bg,
        args.fg,
        args.border_color,
        args.border_width,
        args.radius,
        args.font_size,
        args.overflow_x,
        args.overflow_y,
    );
    stage_node(
        NodeKind::Column { label, style },
        finish_children(args.builder),
    )
}

/// Stage one named vertical scroll region whose child was already built.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_scroll(args: HostGlueNodeScrollArgs) -> u64 {
    let owned_name = args.name.as_str().to_owned();
    unsafe { args.name.decref(roc_host()) };
    let axis = match args.axis {
        0 => ScrollAxis::Vertical,
        1 => ScrollAxis::Horizontal,
        2 => ScrollAxis::Both,
        other => panic!("invalid scroll axis {other}"),
    };
    stage_node(
        NodeKind::Scroll {
            name: owned_name,
            axis,
        },
        vec![args.child],
    )
}

/// Stage one semantically named button whose label was already built.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_button(name: RocStr, label: u64) -> u64 {
    let owned_name = name.as_str().to_owned();
    unsafe { name.decref(roc_host()) };
    stage_node(NodeKind::Button { name: owned_name }, vec![label])
}

fn decode_length(kind: u8, value: u32) -> Length {
    match kind {
        0 => Length::Auto,
        1 => Length::Fill,
        2 => Length::Px(value),
        _ => panic!("invalid length kind {kind}"),
    }
}

fn decode_overflow(value: u8) -> Overflow {
    match value {
        0 => Overflow::Visible,
        1 => Overflow::Clip,
        2 => Overflow::Scroll,
        _ => panic!("invalid overflow kind {value}"),
    }
}

fn decode_color(value: u32) -> Option<u32> {
    (value != 0x0100_0000).then_some(value)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_checkbox(args: HostGlueNodeCheckboxArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    unsafe { args.label.decref(roc_host()) };
    stage_node(
        NodeKind::Checkbox {
            label,
            checked: args.checked,
            enabled: args.enabled,
            style: decode_layout_style(
                args.gap,
                args.padding,
                args.width_kind,
                args.width,
                args.height_kind,
                args.height,
                args.grow,
                args.bg,
                args.hover_bg,
                args.active_bg,
                args.fg,
                args.border_color,
                args.border_width,
                args.radius,
                args.font_size,
                args.overflow_x,
                args.overflow_y,
            ),
        },
        vec![],
    )
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

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_set_task_dispatch(dispatcher: RocErasedCallable) {
    assert!(
        !dispatcher.is_null(),
        "Roc installed a null task dispatcher"
    );
    BRIDGE.with(|bridge| {
        let previous = bridge.borrow_mut().task_dispatcher.replace(dispatcher);
        if let Some(previous) = previous {
            unsafe { decref_erased_callable(previous, roc_host()) };
        }
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_enqueue_task(task: RocErasedCallable) {
    assert!(!task.is_null(), "Roc enqueued a null task");
    let runtime = task_runtime();
    runtime.accepted.fetch_add(1, Ordering::Relaxed);
    runtime
        .jobs
        .send_blocking(task as usize)
        .expect("Roc task runtime stopped");
}

fn await_task_completion() -> Result<RocErasedCallable, String> {
    let runtime = task_runtime();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    loop {
        match runtime.completions.try_recv() {
            Ok(value) => {
                runtime.completed.fetch_add(1, Ordering::Relaxed);
                return Ok(value as RocErasedCallable);
            }
            Err(async_channel::TryRecvError::Closed) => return Err("task runtime stopped".into()),
            Err(async_channel::TryRecvError::Empty) if std::time::Instant::now() < deadline => {
                std::thread::yield_now();
            }
            Err(async_channel::TryRecvError::Empty) => {
                return Err("task did not complete within 10 seconds".into());
            }
        }
    }
}

fn task_counts() -> (u64, u64) {
    let runtime = task_runtime();
    (
        runtime.accepted.load(Ordering::Relaxed),
        runtime.completed.load(Ordering::Relaxed),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_work_start(kind: u8) {
    observatory::start_roc_work(kind);
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_work_end(kind: u8) {
    observatory::end_roc_work(kind);
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

fn complete(completion: RocErasedCallable) -> Patch {
    let dispatcher = BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .task_dispatcher
            .take()
            .expect("Roc task dispatcher is not installed")
    });
    unsafe { roc_gui_complete(dispatcher, completion) };
    BRIDGE.with(|bridge| {
        assert!(
            bridge.borrow().task_dispatcher.is_some(),
            "Roc completion did not install its successor"
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
        if let Some(dispatcher) = bridge.task_dispatcher.take() {
            unsafe { decref_erased_callable(dispatcher, roc_host()) };
        }
    });
    WINDOW_CONFIG.with(|config| *config.borrow_mut() = WindowConfig::default());
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
    is_root: bool,
}

fn apply_style(mut element: Stateful<Div>, style: &Style) -> Stateful<Div> {
    element = element
        .gap(px(style.gap as f32))
        .p(px(style.padding as f32));
    element = match style.width {
        Length::Auto => element,
        Length::Fill => element.w_full(),
        Length::Px(value) => element.w(px(value as f32)),
    };
    element = match style.height {
        Length::Auto => element,
        Length::Fill => element.h_full(),
        Length::Px(value) => element.h(px(value as f32)),
    };
    if style.grow {
        element = element.flex_grow();
    }
    if let Some(value) = style.bg {
        element = element.bg(rgb(value));
    }
    if let Some(value) = style.hover_bg {
        element = element.hover(move |s| s.bg(rgb(value)));
    }
    if let Some(value) = style.active_bg {
        element = element.active(move |s| s.bg(rgb(value)));
    }
    if let Some(value) = style.fg {
        element = element.text_color(rgb(value));
    }
    if let Some(value) = style.border_color {
        element = element.border_color(rgb(value));
    }
    if style.border_width > 0 {
        element = element.border(px(style.border_width as f32));
    }
    if style.radius > 0 {
        element = element.rounded(px(style.radius as f32));
    }
    if style.font_size > 0 {
        element = element.text_size(px(style.font_size as f32));
    }
    element = match style.overflow_x {
        Overflow::Visible => element,
        Overflow::Clip => element.overflow_x_hidden(),
        Overflow::Scroll => element.overflow_x_scroll(),
    };
    match style.overflow_y {
        Overflow::Visible => element,
        Overflow::Clip => element.overflow_y_hidden(),
        Overflow::Scroll => element.overflow_y_scroll(),
    }
}

impl Render for NodeView {
    fn render(&mut self, _: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let mut element = div().id(("node", self.node.id));
        if self.is_root {
            element = element.size_full().min_h_0().min_w_0();
        }
        match &self.node.kind {
            NodeKind::Column { style, .. } => {
                element = apply_style(element.flex().flex_col(), style);
            }
            NodeKind::Row { style, .. } => {
                element = apply_style(element.flex().flex_row().items_center(), style);
            }
            NodeKind::Scroll { axis, .. } => {
                element = element
                    .flex()
                    .flex_col()
                    .flex_grow()
                    .scrollbar_width(px(8.0));
                element = match axis {
                    ScrollAxis::Vertical => element.min_h_0().max_h_full().overflow_y_scroll(),
                    ScrollAxis::Horizontal => element.min_w_0().max_w_full().overflow_x_scroll(),
                    ScrollAxis::Both => element
                        .min_h_0()
                        .max_h_full()
                        .min_w_0()
                        .max_w_full()
                        .overflow_scroll(),
                };
            }
            NodeKind::Text(value) => {
                element = element.child(value.clone());
            }
            NodeKind::Button { .. } => {
                let node_id = self.node.id;
                let runtime = self.runtime.clone();
                let enter_runtime = self.runtime.clone();
                let space_runtime = self.runtime.clone();
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
                    .focusable()
                    .tab_index(0)
                    .focus(|style| style.border_2().border_color(rgb(0x9bdcf0)))
                    .on_action(move |_: &ActivateEnter, _, cx| {
                        let _ = enter_runtime.update(cx, |runtime, cx| {
                            runtime.activate_if_live(node_id, ControlKey::Enter, cx)
                        });
                    })
                    .on_action(move |_: &ActivateSpace, _, cx| {
                        let _ = space_runtime.update(cx, |runtime, cx| {
                            runtime.activate_if_live(node_id, ControlKey::Space, cx)
                        });
                    })
                    .cursor_pointer()
                    .on_click(move |event, _, cx| {
                        if event.mouse_position().is_some() {
                            let _ = runtime
                                .update(cx, |runtime, cx| runtime.event_if_live(node_id, cx));
                        }
                    });
            }
            NodeKind::Checkbox {
                label,
                checked,
                enabled,
                style,
            } => {
                let node_id = self.node.id;
                let runtime = self.runtime.clone();
                let mark = if *checked { "✓" } else { "" };
                element = element
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap(px(style.gap as f32))
                    .p(px(style.padding as f32))
                    .child(
                        div()
                            .w(px(18.0))
                            .h(px(18.0))
                            .border_1()
                            .rounded(px(3.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(mark),
                    )
                    .child(label.clone());
                element = match style.width {
                    Length::Auto => element,
                    Length::Fill => element.w_full(),
                    Length::Px(value) => element.w(px(value as f32)),
                };
                element = match style.height {
                    Length::Auto => element,
                    Length::Fill => element.h_full(),
                    Length::Px(value) => element.h(px(value as f32)),
                };
                if style.grow {
                    element = element.flex_grow();
                }
                if let Some(value) = style.bg {
                    element = element.bg(rgb(value));
                }
                if let Some(value) = style.fg {
                    element = element.text_color(rgb(value));
                }
                if let Some(value) = style.border_color {
                    element = element.border_color(rgb(value));
                }
                if style.border_width > 0 {
                    element = element.border(px(style.border_width as f32));
                }
                if style.radius > 0 {
                    element = element.rounded(px(style.radius as f32));
                }
                if style.font_size > 0 {
                    element = element.text_size(px(style.font_size as f32));
                }
                element = match style.overflow_x {
                    Overflow::Visible => element,
                    Overflow::Clip => element.overflow_x_hidden(),
                    Overflow::Scroll => element.overflow_x_scroll(),
                };
                element = match style.overflow_y {
                    Overflow::Visible => element,
                    Overflow::Clip => element.overflow_y_hidden(),
                    Overflow::Scroll => element.overflow_y_scroll(),
                };
                if let Some(value) = style.hover_bg {
                    element = element.hover(move |refinement| refinement.bg(rgb(value)));
                }
                if let Some(value) = style.active_bg {
                    element = element.active(move |refinement| refinement.bg(rgb(value)));
                }
                if *enabled {
                    let space_runtime = self.runtime.clone();
                    element = element
                        .focusable()
                        .tab_index(0)
                        .focus(|refinement| refinement.border_2().border_color(rgb(0x9bdcf0)))
                        .on_action(move |_: &ActivateSpace, _, cx| {
                            let _ = space_runtime.update(cx, |runtime, cx| {
                                runtime.activate_if_live(node_id, ControlKey::Space, cx)
                            });
                        })
                        .cursor_pointer()
                        .on_click(move |event, _, cx| {
                            if event.mouse_position().is_some() {
                                let _ = runtime
                                    .update(cx, |runtime, cx| runtime.event_if_live(node_id, cx));
                            }
                        });
                }
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

struct InitialMount {
    patch: Patch,
    cycle_started: Instant,
    roc_callback_ns: u64,
    roc_work: [observatory::RocWork; 4],
    roc_work_valid: bool,
}

impl Runtime {
    fn new(initial: InitialMount, cx: &mut Context<Self>) -> Self {
        let mut runtime = Self {
            graph: MountedGraph::default(),
            views: HashMap::new(),
            root: None,
            cycle_ordinal: 0,
        };
        if observatory::active() {
            runtime.apply_recorded(
                initial.patch,
                "init",
                initial.cycle_started,
                initial.roc_callback_ns,
                initial.roc_work,
                initial.roc_work_valid,
                cx,
            );
        } else {
            runtime.apply_unrecorded(initial.patch, cx);
        }
        let completions = task_runtime().completions.clone();
        cx.spawn(async move |runtime, cx| {
            while let Ok(completion) = completions.recv().await {
                task_runtime().completed.fetch_add(1, Ordering::Relaxed);
                if runtime
                    .update(cx, |runtime, cx| {
                        let patch = complete(completion as RocErasedCallable);
                        runtime.apply_unrecorded(patch, cx);
                    })
                    .is_err()
                {
                    break;
                }
            }
        })
        .detach();
        runtime
    }

    fn event_if_live(&mut self, id: u64, cx: &mut Context<Self>) {
        if !matches!(
            self.graph.node(id).map(|node| &node.kind),
            Some(NodeKind::Button { .. } | NodeKind::Checkbox { enabled: true, .. })
        ) {
            return;
        }
        if observatory::active() {
            let cycle_started = Instant::now();
            observatory::reset_roc_work();
            let roc_started = Instant::now();
            let patch = dispatch(id);
            let roc_callback_ns = elapsed_ns(roc_started);
            let (roc_work, roc_work_valid) = observatory::take_roc_work();
            self.apply_recorded(
                patch,
                "click",
                cycle_started,
                roc_callback_ns,
                roc_work,
                roc_work_valid,
                cx,
            );
        } else {
            let patch = dispatch(id);
            self.apply_unrecorded(patch, cx);
        }
    }

    fn activate_if_live(&mut self, id: u64, key: ControlKey, cx: &mut Context<Self>) {
        if self
            .graph
            .node(id)
            .is_some_and(|node| node.kind.accepts_key(key))
        {
            self.event_if_live(id, cx);
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
        roc_work: [observatory::RocWork; 4],
        roc_work_valid: bool,
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
            roc_work,
            roc_work_valid,
        });
        self.cycle_ordinal += 1;
    }

    fn apply_to_gpui(&mut self, applied: &bridge::GraphApply, cx: &mut Context<Self>) {
        if applied.retired_root {
            self.views.clear();
        }
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
                new_root.update(cx, |view, cx| {
                    view.is_root = true;
                    cx.notify();
                });
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
                is_root: false,
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
            .on_action(|_: &FocusNext, window, _| window.focus_next())
            .on_action(|_: &FocusPrevious, window, _| window.focus_prev())
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
    help: bool,
    host_smoke: bool,
    spec_path: Option<PathBuf>,
    stats_record: bool,
    stats_output: Option<PathBuf>,
    stats_detail: observatory::Detail,
    stats_buffer_mib: usize,
    stats_max_mib: u64,
    stats_job_count: usize,
    cap_dir: Option<PathBuf>,
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
        help: false,
        host_smoke: false,
        spec_path: None,
        stats_record: false,
        stats_output: None,
        stats_detail: observatory::Detail::Summary,
        stats_buffer_mib: 4,
        stats_max_mib: 4096,
        stats_job_count: 1,
        cap_dir: None,
    };
    let mut pending = arguments.peekable();
    while let Some(argument) = pending.next() {
        if argument == "--host-help" {
            parsed.help = true;
        } else if argument == "--host-smoke" {
            parsed.host_smoke = true;
        } else if argument == "--host-stats-record" {
            parsed.stats_record = true;
        } else if argument == "--host-run-spec" {
            let path = pending
                .next()
                .ok_or_else(|| "--host-run-spec requires a .scm path".to_string())?;
            parsed.spec_path = Some(path.into());
        } else if let Some(path) = argument.strip_prefix("--host-run-spec=") {
            parsed.spec_path = Some(path.into());
        } else if argument == "--host-cap-dir" {
            parsed.cap_dir = Some(
                pending
                    .next()
                    .ok_or_else(|| "--host-cap-dir requires a directory path".to_string())?
                    .into(),
            );
        } else if let Some(path) = argument.strip_prefix("--host-cap-dir=") {
            parsed.cap_dir = Some(path.into());
        } else if let Some(path) = argument.strip_prefix("--host-stats-output=") {
            parsed.stats_output = Some(path.into());
            parsed.stats_record = true;
        } else if let Some(value) = argument.strip_prefix("--host-stats-detail=") {
            parsed.stats_detail = observatory::Detail::parse(value)
                .ok_or_else(|| "stats detail must be summary or full".to_string())?;
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
    if parsed.host_smoke && parsed.spec_path.is_some() {
        return Err("--host-smoke and --host-run-spec are mutually exclusive".into());
    }
    Ok(parsed)
}

fn print_host_help(app_name: &str) {
    println!(
        "Usage: {app_name} [HOST OPTIONS]\n\
         \n\
         Host options:\n\
           --host-help                         Show this help and exit\n\
           --host-cap-dir PATH                 Grant read access to one directory\n\
           --host-run-spec PATH                Run one semantic .scm specification\n\
           --host-smoke                        Run the built-in headless smoke check\n\
           --host-stats-record                 Record an observatory capture\n\
           --host-stats-output=PATH            Set the capture output path\n\
           --host-stats-detail=summary|full    Select capture detail\n\
           --host-stats-buffer-mib=N           Set recorder buffer capacity\n\
           --host-stats-max-mib=N              Set maximum capture size\n\
           --host-stats-job-count=N            Record concurrent runner job count\n\
         \n\
         Options are passed through Roc after `--`, for example:\n\
           roc app.roc -- --host-help\n\
           roc app.roc -- --host-cap-dir ./documents"
    );
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
        backend: if args.spec_path.is_some() || args.host_smoke {
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
    if args.help {
        print_host_help(&args.app_name);
        set_roc_host(core::ptr::null_mut());
        return 0;
    }
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
    if let Err(message) = files::configure(args.cap_dir.as_deref()) {
        eprintln!("roc-gui capability error: {message}");
        set_roc_host(core::ptr::null_mut());
        return 2;
    }
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

    if args.host_smoke {
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

    let cycle_started = Instant::now();
    observatory::reset_roc_work();
    let roc_started = Instant::now();
    unsafe { roc_gui_init() };
    let roc_callback_ns = elapsed_ns(roc_started);
    let (roc_work, roc_work_valid) = observatory::take_roc_work();
    let initial = InitialMount {
        patch: take_patch(),
        cycle_started,
        roc_callback_ns,
        roc_work,
        roc_work_valid,
    };
    let window_config = WINDOW_CONFIG.with(|config| config.borrow().clone());

    Application::new().run(move |cx| {
        cx.bind_keys([
            KeyBinding::new("tab", FocusNext, None),
            KeyBinding::new("shift-tab", FocusPrevious, None),
            KeyBinding::new("enter", ActivateEnter, None),
            KeyBinding::new("space", ActivateSpace, None),
        ]);
        cx.on_window_closed(|cx| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();

        let bounds = Bounds::centered(
            None,
            size(
                px(window_config.width as f32),
                px(window_config.height as f32),
            ),
            cx,
        );
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some(window_config.title.clone().into()),
                    ..Default::default()
                }),
                ..Default::default()
            },
            move |_, cx| cx.new(|cx| Runtime::new(initial, cx)),
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
        WindowConfig, counted_roc_alloc, counted_roc_dealloc, counted_roc_realloc,
        make_counted_roc_host, validate_window_config,
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

    #[test]
    fn validates_initial_window_bounds() {
        assert!(
            validate_window_config(WindowConfig {
                title: "App".into(),
                width: 960,
                height: 640
            })
            .is_ok()
        );
        assert!(
            validate_window_config(WindowConfig {
                title: "App".into(),
                width: 239,
                height: 640
            })
            .is_err()
        );
        assert!(
            validate_window_config(WindowConfig {
                title: "App".into(),
                width: 960,
                height: 159
            })
            .is_err()
        );
    }
}
