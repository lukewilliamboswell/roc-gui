//! Minimal GPUI host for the Roc action/state GUI platform.
#![allow(unsafe_op_in_unsafe_fn)]
#![cfg_attr(test, allow(dead_code, unused_imports))]

mod app_data;
mod assets;
mod audio;
mod bridge;
mod clipboard;
mod device;
mod files;
mod frame_spans;
mod http;
mod image_data;
mod input;
mod observatory;
mod probe;
mod process;
// Generated glue (scripts/regenerate_glue.py); variant names mirror the Roc types.
#[allow(clippy::enum_variant_names)]
mod roc_platform_abi;
mod runner;
mod screenshot;
mod spec;
mod sqlite;
mod system_monitor;
mod tcp;
mod timers;
mod watchdog;
mod window_runner;

use bridge::{
    Align, BridgeState, CanvasPrimitive, CanvasPrimitiveKind, CheckboxIndicator, ControlKey,
    ElementIdentity, FontFace, ImageFit, ImageFormat as BridgeImageFormat, Justify, Length,
    MountedGraph, Node, NodeKind, Overflow, Patch, ScrollAxis, Style, TextOverflow, decode_commit,
    validate_tree,
};
use gpui::{div, prelude::*, px, rgb, size, *};
use roc_platform_abi::{
    DefaultAllocators, DefaultHandlers, HostGlueCanvasEventRetRecord, HostGlueComponentResolve,
    HostGlueHttpAcquireResult, HostGlueHttpSendArgs, HostGlueHttpSendResult,
    HostGlueNodeActionButtonArgs, HostGlueNodeCanvasArgs, HostGlueNodeCheckboxArgs,
    HostGlueNodeColumnArgs, HostGlueNodeDialogArgs, HostGlueNodeImageArgs, HostGlueNodePanelArgs,
    HostGlueNodeRowArgs, HostGlueNodeScrollArgs, HostGlueNodeStyledTextArgs,
    HostGlueNodeTextInputArgs, HostGlueNodeTextInputRetRecord, HostGlueNodeTextareaArgs,
    HostGlueNodeVirtualListArgs, MountOrNoChangeOrReplace, RocErasedCallable, RocHost, RocStr,
    decref_erased_callable, incref_erased_callable, make_roc_host, roc_gui_dispatch, roc_gui_init,
};
use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::c_void,
    path::PathBuf,
    sync::atomic::{AtomicBool, AtomicPtr, AtomicU64, Ordering},
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, Instant},
};

actions!(
    roc_gui,
    [
        FocusNext,
        FocusPrevious,
        ActivateEnter,
        ActivateEscape,
        ActivateSpace
    ]
);

unsafe extern "C" {
    fn roc_gui_complete(dispatcher: RocErasedCallable, completion: RocErasedCallable, owner: u64);
    fn roc_gui_run_task(task: RocErasedCallable) -> RocErasedCallable;
}

#[derive(Debug)]
struct TaskEnvelope {
    callable: usize,
    owner: u64,
    epoch: u64,
}

impl TaskEnvelope {
    fn take_callable(&mut self) -> RocErasedCallable {
        std::mem::take(&mut self.callable) as RocErasedCallable
    }
}

impl Drop for TaskEnvelope {
    fn drop(&mut self) {
        if self.callable != 0 {
            unsafe { decref_erased_callable(self.take_callable(), roc_host()) };
        }
    }
}

struct TaskRuntime {
    jobs: async_channel::Sender<TaskEnvelope>,
    pending_jobs: async_channel::Receiver<TaskEnvelope>,
    completions: async_channel::Receiver<TaskEnvelope>,
    accepted: AtomicU64,
    completed: AtomicU64,
    /// The process-lived allocator remains valid after UI session retirement.
    allocator_host: usize,
}

static TASK_RUNTIME: OnceLock<TaskRuntime> = OnceLock::new();
static TASK_EPOCH: AtomicU64 = AtomicU64::new(1);
/// Retirement and publication share one short gate. A result cannot land just
/// after retirement drained the completion queue and lost its last consumer.
static TASK_PUBLICATION: Mutex<()> = Mutex::new(());
static NEXT_COMPONENT_DEFINITION: AtomicU64 = AtomicU64::new(1);
static GPUI_SMOKE: AtomicBool = AtomicBool::new(false);
static GPUI_SMOKE_RENDERS: AtomicU64 = AtomicU64::new(0);

fn task_runtime() -> &'static TaskRuntime {
    TASK_RUNTIME.get_or_init(|| {
        let (job_sender, job_receiver) = async_channel::unbounded::<TaskEnvelope>();
        let (completion_sender, completion_receiver) = async_channel::unbounded::<TaskEnvelope>();
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
                    while let Ok(mut task) = jobs.recv_blocking() {
                        if task.epoch != TASK_EPOCH.load(Ordering::Acquire) {
                            continue;
                        }
                        let completion = unsafe { roc_gui_run_task(task.take_callable()) };
                        task.callable = completion as usize;
                        let _publication = TASK_PUBLICATION.lock().expect("task publication gate");
                        if task.epoch == TASK_EPOCH.load(Ordering::Acquire) {
                            let _ = completions.send_blocking(task);
                        }
                    }
                })
                .expect("failed to start Roc task worker");
        }
        TaskRuntime {
            jobs: job_sender,
            pending_jobs: job_receiver,
            completions: completion_receiver,
            accepted: AtomicU64::new(0),
            completed: AtomicU64::new(0),
            allocator_host: ROC_HOST.load(Ordering::Acquire) as usize,
        }
    })
}

static ROC_HOST: AtomicPtr<RocHost> = AtomicPtr::new(core::ptr::null_mut());

#[derive(Default)]
struct StagedTurn {
    dispatcher: Option<RocErasedCallable>,
    jobs: Vec<TaskEnvelope>,
}

thread_local! {
    static BRIDGE: RefCell<BridgeState> = const { RefCell::new(BridgeState::new()) };
    static WINDOW_CONFIG: RefCell<WindowConfig> = RefCell::new(WindowConfig::default());
    static INPUT_VALUE: RefCell<Option<String>> = const { RefCell::new(None) };
    static CANVAS_EVENT: RefCell<Option<CanvasEventPayload>> = const { RefCell::new(None) };
    static STAGED_TURN: RefCell<StagedTurn> = RefCell::new(StagedTurn::default());
    static COMPONENT_SETUP: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

#[derive(Clone, Copy)]
struct CanvasEventPayload {
    phase: u8,
    x: i32,
    y: i32,
    target: u64,
}

const SUBMIT_EVENT_BIT: u64 = 1 << 63;

#[derive(Clone, Debug, PartialEq, Eq)]
struct WindowConfig {
    title: String,
    width: u32,
    height: u32,
    /// The colour behind the root element, and the ink text inherits when it
    /// names none. `None` keeps the host's own ground.
    background: Option<u32>,
    foreground: Option<u32>,
}

impl Default for WindowConfig {
    fn default() -> Self {
        Self {
            title: "Roc GUI".into(),
            width: 480,
            height: 240,
            background: None,
            foreground: None,
        }
    }
}

/// The application's chosen window ground, or None for the host's own.
fn window_ground() -> Option<u32> {
    WINDOW_CONFIG.with(|config| config.borrow().background)
}

fn window_ink() -> Option<u32> {
    WINDOW_CONFIG.with(|config| config.borrow().foreground)
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
pub extern "C" fn roc_gui_window_config(
    title: RocStr,
    width: u32,
    height: u32,
    background: u32,
    foreground: u32,
) {
    let title_value = title.as_str().to_owned();
    unsafe { title.decref(roc_host()) };
    let config = validate_window_config(WindowConfig {
        title: title_value,
        width,
        height,
        background: decode_color(background),
        foreground: decode_color(foreground),
    })
    .unwrap_or_else(|message| panic!("invalid native window configuration: {message}"));
    WINDOW_CONFIG.with(|current| *current.borrow_mut() = config);
}

fn set_roc_host(host: *mut RocHost) {
    ROC_HOST.store(host, Ordering::Release);
}

fn roc_host_ptr() -> *mut RocHost {
    let mut pointer = ROC_HOST.load(Ordering::Acquire);
    if pointer.is_null() {
        pointer = TASK_RUNTIME.get().map_or(core::ptr::null_mut(), |runtime| {
            runtime.allocator_host as *mut RocHost
        });
    }
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
    assets::route_dealloc(pointer);
    audio::route_dealloc(pointer);
    sqlite::route_dealloc(pointer);
    app_data::route_dealloc(pointer);
    clipboard::route_dealloc(pointer);
    device::route_dealloc(pointer);
    system_monitor::route_dealloc(pointer);
    tcp::route_dealloc(pointer);
    process::route_dealloc(pointer);
    timers::route_dealloc(pointer);
    http::route_dealloc(pointer);
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

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_component_setup(enabled: bool) {
    COMPONENT_SETUP.with(|setup| setup.set(enabled));
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_component_define() -> u64 {
    assert!(
        COMPONENT_SETUP.with(|setup| setup.get()),
        "components must be defined during setup"
    );
    NEXT_COMPONENT_DEFINITION
        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
            value.checked_add(1)
        })
        .expect("component definition identity exhausted")
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_boundary(instance: u64, child: u64) -> u64 {
    stage_node(NodeKind::Boundary { instance }, vec![child])
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_retain_subtree(root: u64) -> u64 {
    BRIDGE.with(|bridge| {
        bridge
            .borrow_mut()
            .retain_subtree(root)
            .unwrap_or_else(|message| panic!("invalid retained component: {message}"))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_component_work(kind: u8, amount: u64) {
    observatory::note_component_work(kind, amount);
}

fn with_component_registry<T>(
    operation: impl FnOnce(&mut bridge::ComponentRegistry) -> Result<T, String>,
) -> T {
    BRIDGE.with(|bridge| {
        operation(
            bridge
                .borrow_mut()
                .components
                .get_or_insert_with(Default::default),
        )
        .unwrap_or_else(|message| panic!("invalid component reconciliation: {message}"))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_begin_render(owner: u64) {
    with_component_registry(|registry| registry.begin_render(owner));
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_scope_enter(tag: u8, label: RocStr, position: u64) {
    let label_text = label.as_str().to_owned();
    unsafe { label.decref(roc_host()) };
    with_component_registry(|registry| registry.scope_enter(tag, &label_text, position));
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_scope_exit() {
    with_component_registry(|registry| registry.scope_exit());
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_component_resolve(
    definition: u64,
    key_kind: u8,
    key_name: RocStr,
    key_id: u64,
) -> HostGlueComponentResolve {
    let key_text = key_name.as_str().to_owned();
    unsafe { key_name.decref(roc_host()) };
    let (instance, root) = with_component_registry(|registry| {
        registry.resolve(definition, key_kind, &key_text, key_id)
    });
    HostGlueComponentResolve { instance, root }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_component_enter(instance: u64) {
    with_component_registry(|registry| registry.component_enter(instance));
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_component_exit() {
    with_component_registry(|registry| registry.component_exit());
}

/// Stage one owned text node and return its fresh host identity.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_text(value: RocStr) -> u64 {
    let text = value.as_str().to_owned();
    unsafe { value.decref(roc_host()) };
    stage_node(NodeKind::Text(text), vec![])
}

/// Stage one text node that carries its own type rather than inheriting it.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_styled_text(args: HostGlueNodeStyledTextArgs) -> u64 {
    let value = args.value.as_str().to_owned();
    unsafe { args.value.decref(roc_host()) };
    stage_node(
        NodeKind::StyledText {
            value,
            fg: decode_color(args.fg),
            font_size: args.font_size,
            font_weight: args.font_weight,
            font_face: decode_font_face(args.font_face),
        },
        vec![],
    )
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

/// Decode the flat hosted style fields of any styled node argument record into
/// the canonical `Style`. Every styled node passes the same field names, so one
/// macro keeps them in step as the style vocabulary grows.
macro_rules! decode_layout_style {
    ($args:expr) => {
        Style {
            gap: $args.gap,
            padding: [
                $args.padding_top,
                $args.padding_right,
                $args.padding_bottom,
                $args.padding_left,
            ],
            width: decode_length($args.width_kind, $args.width),
            height: decode_length($args.height_kind, $args.height),
            min_width: decode_length($args.min_width_kind, $args.min_width),
            min_height: decode_length($args.min_height_kind, $args.min_height),
            max_width: decode_length($args.max_width_kind, $args.max_width),
            max_height: decode_length($args.max_height_kind, $args.max_height),
            grow: $args.grow,
            bg: decode_color($args.bg),
            hover_bg: decode_color($args.hover_bg),
            active_bg: decode_color($args.active_bg),
            disabled_bg: decode_color($args.disabled_bg),
            disabled_fg: decode_color($args.disabled_fg),
            focus_color: decode_color($args.focus_color),
            fg: decode_color($args.fg),
            border_color: decode_color($args.border_color),
            border_width: [
                $args.border_top,
                $args.border_right,
                $args.border_bottom,
                $args.border_left,
            ],
            radius: $args.radius,
            font_size: $args.font_size,
            font_weight: $args.font_weight,
            shadow: $args.shadow,
            shadow_y: $args.shadow_y,
            shadow_color: decode_color($args.shadow_color),
            shadow_alpha: $args.shadow_alpha,
            font_face: decode_font_face($args.font_face),
            text_overflow: decode_text_overflow($args.text_overflow),
            overflow_x: decode_overflow($args.overflow_x),
            overflow_y: decode_overflow($args.overflow_y),
            align: decode_align($args.align),
            justify: decode_justify($args.justify),
        }
    };
}

/// Stage one styled, semantically named row.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_row(args: HostGlueNodeRowArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    unsafe { args.label.decref(roc_host()) };
    let style = decode_layout_style!(args);
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
    let style = decode_layout_style!(args);
    stage_node(
        NodeKind::Column { label, style },
        finish_children(args.builder),
    )
}

/// Stage one modal dialog and its ordinary child subtree.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_dialog(args: HostGlueNodeDialogArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    unsafe { args.label.decref(roc_host()) };
    let style = decode_layout_style!(args);
    stage_node(
        NodeKind::Dialog { label, style },
        finish_children(args.builder),
    )
}

/// Stage one styled, semantically labelled panel.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_panel(args: HostGlueNodePanelArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    unsafe { args.label.decref(roc_host()) };
    let style = decode_layout_style!(args);
    stage_node(
        NodeKind::Panel { label, style },
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
            style: decode_layout_style!(args),
        },
        vec![args.child],
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_virtual_item(key: u64, content: u64) -> u64 {
    // Roc passes `U64, U64` as two arguments. The glue's two-field struct only
    // shares that layout under SysV/AAPCS64; Win64 passes it by reference.
    stage_node(NodeKind::VirtualItem { key }, vec![content])
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_virtual_list(args: HostGlueNodeVirtualListArgs) -> u64 {
    let name = args.name.as_str().to_owned();
    unsafe { args.name.decref(roc_host()) };
    stage_node(
        NodeKind::VirtualList {
            name,
            row_height: args.row_height,
            row_gap: args.row_gap,
            style: decode_layout_style!(args),
        },
        finish_children(args.builder),
    )
}

/// Stage one styled action button.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_action_button(args: HostGlueNodeActionButtonArgs) -> u64 {
    let caption = args.caption.as_str().to_owned();
    let label = args.label.as_str().to_owned();
    unsafe {
        args.caption.decref(roc_host());
        args.label.decref(roc_host());
    }
    stage_node(
        NodeKind::Button {
            caption,
            label,
            enabled: args.enabled,
            style: decode_layout_style!(args),
        },
        vec![],
    )
}

fn decode_length(kind: u8, value: u32) -> Length {
    match kind {
        0 => Length::Auto,
        1 => Length::Fill,
        2 => Length::Px(value),
        _ => panic!("invalid length kind {kind}"),
    }
}

fn decode_align(value: u8) -> Align {
    match value {
        0 => Align::Native,
        1 => Align::Start,
        2 => Align::Center,
        3 => Align::End,
        4 => Align::Baseline,
        5 => Align::Stretch,
        _ => panic!("invalid align {value}"),
    }
}

fn decode_justify(value: u8) -> Justify {
    match value {
        0 => Justify::Native,
        1 => Justify::Start,
        2 => Justify::Center,
        3 => Justify::End,
        4 => Justify::Between,
        5 => Justify::Around,
        _ => panic!("invalid justify {value}"),
    }
}

/// The platform's fixed-pitch family. GPUI takes one family name, so the host
/// names the face each operating system actually ships rather than a generic
/// word that only one font stack resolves.
const MONOSPACE_FAMILY: &str = if cfg!(target_os = "macos") {
    "Menlo"
} else if cfg!(target_os = "windows") {
    "Consolas"
} else {
    "monospace"
};

fn decode_font_face(value: u8) -> FontFace {
    match value {
        0 => FontFace::Default,
        1 => FontFace::Monospace,
        _ => panic!("invalid font face {value}"),
    }
}

fn decode_text_overflow(value: u8) -> TextOverflow {
    match value {
        0 => TextOverflow::Wrap,
        1 => TextOverflow::NoWrap,
        2 => TextOverflow::Ellipsis,
        _ => panic!("invalid text overflow {value}"),
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
            indicator: CheckboxIndicator {
                box_bg: decode_color(args.box_bg),
                box_checked_bg: decode_color(args.box_checked_bg),
                box_border: decode_color(args.box_border),
                mark_color: decode_color(args.mark_color),
            },
            style: decode_layout_style!(args),
        },
        vec![],
    )
}

/// Stage one controlled multiline text editor.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_textarea(args: HostGlueNodeTextareaArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    let value = args.value.as_str().to_owned();
    let placeholder = args.placeholder.as_str().to_owned();
    unsafe { args.decref(roc_host()) };
    stage_node(
        NodeKind::Textarea {
            label,
            value,
            placeholder,
            enabled: args.enabled,
            read_only: args.read_only,
            style: decode_layout_style!(args),
        },
        vec![],
    )
}

/// Stage encoded image bytes; no path or URI is resolved by this node.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_image(args: HostGlueNodeImageArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    let bytes = args.bytes.as_slice().to_vec();
    image_data::note_staged(bytes.len());
    let format = match args.format {
        0 => BridgeImageFormat::Bmp,
        1 => BridgeImageFormat::Gif,
        2 => BridgeImageFormat::Jpeg,
        3 => BridgeImageFormat::Png,
        4 => BridgeImageFormat::Svg,
        5 => BridgeImageFormat::Tiff,
        6 => BridgeImageFormat::Webp,
        other => panic!("invalid image format {other}"),
    };
    let fit = match args.fit {
        0 => ImageFit::Contain,
        1 => ImageFit::Cover,
        2 => ImageFit::Fill,
        3 => ImageFit::None,
        4 => ImageFit::ScaleDown,
        other => panic!("invalid image fit {other}"),
    };
    unsafe { args.decref(roc_host()) };
    stage_node(
        NodeKind::Image {
            label,
            bytes,
            format,
            fit,
            grayscale: args.grayscale,
            style: decode_layout_style!(args),
        },
        vec![],
    )
}

/// Stage one retained vector canvas and its keyed hit-testable primitives.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_canvas(args: HostGlueNodeCanvasArgs) -> u64 {
    let label = args.label.as_str().to_owned();
    assert!(!label.is_empty(), "canvas label must not be empty");
    let primitives = args
        .primitives
        .as_slice()
        .iter()
        .map(|item| CanvasPrimitive {
            kind: match item.kind {
                0 => CanvasPrimitiveKind::Ellipse,
                1 => CanvasPrimitiveKind::Line,
                2 => CanvasPrimitiveKind::Rectangle,
                other => panic!("invalid canvas primitive kind {other}"),
            },
            key: item.key,
            label: item.label.as_str().to_owned(),
            x: item.x,
            y: item.y,
            width: item.width,
            height: item.height,
            x2: item.x2,
            y2: item.y2,
            fill: decode_color(item.fill),
            stroke: decode_color(item.stroke),
            stroke_width: item.stroke_width,
            radius: item.radius,
        })
        .collect::<Vec<_>>();
    assert!(
        primitives.iter().all(|item| item.key != 0),
        "canvas primitive keys must be non-zero"
    );
    let mut keys = std::collections::HashSet::with_capacity(primitives.len());
    assert!(
        primitives.iter().all(|item| keys.insert(item.key)),
        "canvas primitive keys must be unique"
    );
    let style = Style {
        width: decode_length(args.width_kind, args.width),
        height: decode_length(args.height_kind, args.height),
        grow: args.grow,
        bg: decode_color(args.bg),
        border_color: decode_color(args.border_color),
        border_width: [args.border_width; 4],
        radius: args.radius,
        overflow_x: Overflow::Clip,
        overflow_y: Overflow::Clip,
        ..Style::default()
    };
    unsafe { args.decref(roc_host()) };
    stage_node(
        NodeKind::Canvas {
            label,
            primitives,
            style,
        },
        vec![],
    )
}

/// Consume the direct-manipulation payload installed for a canvas dispatch.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_canvas_event() -> HostGlueCanvasEventRetRecord {
    let event = CANVAS_EVENT
        .with(|slot| slot.borrow_mut().take())
        .unwrap_or(CanvasEventPayload {
            phase: 2,
            x: 0,
            y: 0,
            target: 0,
        });
    HostGlueCanvasEventRetRecord {
        phase: event.phase,
        x: event.x,
        y: event.y,
        target: event.target,
    }
}

/// Stage one controlled single-line editor and allocate its two event routes.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_text_input(
    args: HostGlueNodeTextInputArgs,
) -> HostGlueNodeTextInputRetRecord {
    let label = args.label.as_str().to_owned();
    let value = args.value.as_str().to_owned();
    let placeholder = args.placeholder.as_str().to_owned();
    assert!(!label.is_empty(), "text input label must not be empty");
    assert!(
        value.len() <= input::MAX_TEXT_BYTES && placeholder.len() <= input::MAX_TEXT_BYTES,
        "text input value and placeholder are each limited to one MiB"
    );
    unsafe { args.decref(roc_host()) };
    let id = stage_node(
        NodeKind::TextInput {
            label,
            value,
            placeholder,
            enabled: args.enabled,
            style: decode_layout_style!(args),
        },
        vec![],
    );
    HostGlueNodeTextInputRetRecord {
        change: id,
        id,
        submit: id | SUBMIT_EVENT_BIT,
    }
}

/// Consume the private event payload installed immediately before dispatch.
#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_input_value() -> RocStr {
    let value = INPUT_VALUE
        .with(|slot| slot.borrow_mut().take())
        .unwrap_or_default();
    RocStr::from_str(&value, roc_host())
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
    STAGED_TURN.with(|turn| {
        let previous = turn.borrow_mut().dispatcher.replace(dispatcher);
        if let Some(previous) = previous {
            unsafe { decref_erased_callable(previous, roc_host()) };
        }
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_timer_start(interval_ms: u64) -> *mut u64 {
    timers::start(interval_ms)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_timer_next(handle: *mut u64) -> bool {
    timers::next(handle)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_timer_cancel(handle: *mut u64) -> bool {
    timers::cancel(handle)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_http_send(args: HostGlueHttpSendArgs) -> HostGlueHttpSendResult {
    http::send(args)
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_http_acquire() -> HostGlueHttpAcquireResult {
    http::acquire()
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_enqueue_task(owner: u64, task: RocErasedCallable) {
    assert!(!task.is_null(), "Roc enqueued a null task");
    STAGED_TURN.with(|turn| {
        turn.borrow_mut().jobs.push(TaskEnvelope {
            callable: task as usize,
            owner,
            epoch: TASK_EPOCH.load(Ordering::Acquire),
        })
    });
}

/// Publish a turn only after the mounted graph accepted its patch. Jobs cannot
/// race validation or observe a session that failed to mount.
pub(crate) fn accept_transaction(graph: &MountedGraph, applied: &bridge::GraphApply) {
    let turn = STAGED_TURN.with(|staged| std::mem::take(&mut *staged.borrow_mut()));
    BRIDGE.with(|bridge| {
        let mut bridge = bridge.borrow_mut();
        if let Some(components) = &mut bridge.components {
            components.commit(graph, applied);
        }
        if let Some(next) = turn.dispatcher {
            if let Some(previous) = bridge.dispatcher.replace(next) {
                unsafe { decref_erased_callable(previous, roc_host()) };
            }
        }
    });
    observatory::commit_component_work();
    for job in turn.jobs {
        if job.owner == 0 || graph.boundary_root(job.owner).is_some() {
            let runtime = task_runtime();
            runtime.accepted.fetch_add(1, Ordering::Relaxed);
            runtime
                .jobs
                .send_blocking(job)
                .expect("Roc task runtime stopped");
        }
    }
}

pub(crate) fn reject_transaction() {
    BRIDGE.with(|bridge| {
        if let Some(components) = &mut bridge.borrow_mut().components {
            components.abort();
        }
    });
    let turn = STAGED_TURN.with(|staged| std::mem::take(&mut *staged.borrow_mut()));
    if let Some(callable) = turn.dispatcher {
        unsafe { decref_erased_callable(callable, roc_host()) };
    }
    observatory::reject_component_work();
}

/// How long one task may run before a specification calls it hung.
///
/// This catches a task that will never finish, so it is deliberately generous
/// rather than a latency bound. A Windows specification's first read waits for
/// a pseudo console to start a shell, which on a freshly provisioned machine
/// costs seconds before the program prints anything at all.
pub(crate) const TASK_BUDGET: std::time::Duration = std::time::Duration::from_secs(30);

/// How long a wait holds its core before it starts sleeping between polls.
///
/// Long enough that no application driven by a timer is still pending: the
/// shortest interval a specification arms is a millisecond, so a task that has
/// not completed in fifty of them is waiting on something else entirely.
const SPIN_BEFORE_SLEEPING: std::time::Duration = std::time::Duration::from_millis(50);

fn await_task_completion() -> Result<TaskEnvelope, String> {
    let runtime = task_runtime();
    let started = std::time::Instant::now();
    let deadline = started + TASK_BUDGET;
    loop {
        match runtime.completions.try_recv() {
            Ok(value) => {
                if value.epoch != TASK_EPOCH.load(Ordering::Acquire) {
                    continue;
                }
                runtime.completed.fetch_add(1, Ordering::Relaxed);
                return Ok(value);
            }
            Err(async_channel::TryRecvError::Closed) => return Err("task runtime stopped".into()),
            Err(async_channel::TryRecvError::Empty) if std::time::Instant::now() < deadline => {
                // Two regimes, and sleeping in the wrong one is a bug: a timer
                // application can complete a task every millisecond, so any
                // sleep here would let its work run on while this waits, and a
                // specification counting ticks would see one too many. Past the
                // threshold no such task is pending, the wait is on something
                // slow like a console starting, and holding a core would slow
                // the very work being waited for.
                if started.elapsed() < SPIN_BEFORE_SLEEPING {
                    std::thread::yield_now();
                } else {
                    std::thread::sleep(std::time::Duration::from_millis(1));
                }
            }
            Err(async_channel::TryRecvError::Empty) => {
                return Err(format!(
                    "task did not complete within {} seconds",
                    TASK_BUDGET.as_secs()
                ));
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

// A stand-in for the Roc dispatcher, installed only by host tests.
//
// The event route into Roc is a linked symbol, so a test that wants to drive
// GPUI's own dispatch tree — press, patch, release — has no application to
// answer the click. This seam lets a test answer it in Rust. It is compiled
// out of the shipped binary.
#[cfg(test)]
thread_local! {
    static TEST_DISPATCHER: RefCell<Option<Box<dyn Fn(u64) -> Patch>>> =
        const { RefCell::new(None) };
}

#[cfg(test)]
fn install_test_dispatcher(dispatcher: impl Fn(u64) -> Patch + 'static) {
    TEST_DISPATCHER.with(|slot| *slot.borrow_mut() = Some(Box::new(dispatcher)));
}

fn dispatch(event_id: u64) -> Patch {
    observatory::begin_component_work();
    #[cfg(test)]
    {
        let answered =
            TEST_DISPATCHER.with(|slot| slot.borrow().as_ref().map(|dispatch| dispatch(event_id)));
        if let Some(patch) = answered {
            return patch;
        }
    }
    let dispatcher = BRIDGE.with(|bridge| {
        bridge
            .borrow()
            .dispatcher
            .expect("Roc dispatcher is not installed")
    });
    unsafe { incref_erased_callable(dispatcher, 1) };
    unsafe { roc_gui_dispatch(dispatcher, event_id) };
    STAGED_TURN.with(|turn| {
        assert!(
            turn.borrow().dispatcher.is_some(),
            "Roc dispatch did not install its successor"
        );
    });
    take_patch()
}

fn dispatch_input(event_id: u64, value: String) -> Patch {
    INPUT_VALUE.with(|slot| {
        assert!(
            slot.borrow_mut().replace(value).is_none(),
            "nested textarea input dispatch"
        );
    });
    let patch = dispatch(event_id);
    INPUT_VALUE.with(|slot| {
        slot.borrow_mut().take();
    });
    patch
}

fn dispatch_canvas(event_id: u64, event: CanvasEventPayload) -> Patch {
    CANVAS_EVENT.with(|slot| {
        assert!(
            slot.borrow_mut().replace(event).is_none(),
            "nested canvas dispatch"
        );
    });
    let patch = dispatch(event_id);
    CANVAS_EVENT.with(|slot| {
        slot.borrow_mut().take();
    });
    patch
}

fn complete(mut completion: TaskEnvelope) -> Patch {
    observatory::begin_component_work();
    if completion.epoch != TASK_EPOCH.load(Ordering::Acquire) {
        return Patch::NoChange;
    }
    let dispatcher = BRIDGE.with(|bridge| {
        bridge
            .borrow()
            .dispatcher
            .expect("Roc session dispatcher is not installed")
    });
    unsafe { incref_erased_callable(dispatcher, 1) };
    unsafe { roc_gui_complete(dispatcher, completion.take_callable(), completion.owner) };
    STAGED_TURN.with(|turn| {
        assert!(
            turn.borrow().dispatcher.is_some(),
            "Roc completion did not install its successor"
        );
    });
    take_patch()
}

fn clear_bridge() {
    let retired = {
        let _publication = TASK_PUBLICATION.lock().expect("task publication gate");
        TASK_EPOCH.fetch_add(1, Ordering::AcqRel);
        let mut retired = Vec::new();
        if let Some(runtime) = TASK_RUNTIME.get() {
            while let Ok(ready) = runtime.completions.try_recv() {
                retired.push(ready);
            }
            // Waiting workers may all be blocked inside effects. Queued jobs
            // have not started and need not keep their captures until one wakes.
            while let Ok(pending) = runtime.pending_jobs.try_recv() {
                retired.push(pending);
            }
            runtime.accepted.store(0, Ordering::Relaxed);
            runtime.completed.store(0, Ordering::Relaxed);
        }
        retired
    };
    drop(retired);
    reject_transaction();
    observatory::clear_component_work();
    COMPONENT_SETUP.with(|setup| setup.set(false));
    BRIDGE.with(|bridge| {
        let mut bridge = bridge.borrow_mut();
        bridge.pending = None;
        bridge.components = None;
        if let Some(dispatcher) = bridge.dispatcher.take() {
            unsafe { decref_erased_callable(dispatcher, roc_host()) };
        }
    });
    WINDOW_CONFIG.with(|config| *config.borrow_mut() = WindowConfig::default());
    INPUT_VALUE.with(|slot| {
        slot.borrow_mut().take();
    });
    CANVAS_EVENT.with(|slot| {
        slot.borrow_mut().take();
    });
}

fn button_with_name(nodes: &[Node], expected: &str) -> Option<u64> {
    nodes.iter().find_map(|node| {
        matches!(&node.kind, NodeKind::Button { label, .. } if label == expected).then_some(node.id)
    })
}

fn contains_text(nodes: &[Node], expected: &str) -> bool {
    nodes
        .iter()
        .any(|node| {
            matches!(&node.kind, NodeKind::Text(value) | NodeKind::StyledText { value, .. } if value == expected)
        })
}

fn headless_smoke() {
    observatory::begin_component_work();
    unsafe { roc_gui_init() };
    let (initial_root, initial_nodes) = match take_patch() {
        Patch::Mount { root, nodes } => (root, nodes),
        other => panic!("expected initial mount, got {other:?}"),
    };
    validate_tree(initial_root, &initial_nodes).expect("invalid initial counter tree");
    let mut graph = MountedGraph::default();
    let applied = graph
        .apply(Patch::Mount {
            root: initial_root,
            nodes: initial_nodes.clone(),
        })
        .expect("invalid smoke mount");
    accept_transaction(&graph, &applied);
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
    let applied = graph
        .apply(Patch::NoChange)
        .expect("invalid smoke no-change");
    accept_transaction(&graph, &applied);

    let (first_target, first_nodes) = match dispatch(initial_plus) {
        Patch::Replace {
            old_root,
            root,
            nodes,
        } => {
            validate_tree(root, &nodes).expect("invalid first counter replacement");
            let applied = graph
                .apply(Patch::Replace {
                    old_root,
                    root,
                    nodes: nodes.clone(),
                })
                .expect("invalid smoke update");
            accept_transaction(&graph, &applied);
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
    let applied = graph
        .apply(Patch::NoChange)
        .expect("invalid smoke no-change");
    accept_transaction(&graph, &applied);

    let next_plus = button_with_name(&first_nodes, "Left increment")
        .expect("replacement increment button is missing");
    let second_nodes = match dispatch(next_plus) {
        Patch::Replace {
            old_root,
            root,
            nodes,
        } => {
            validate_tree(root, &nodes).expect("invalid second counter replacement");
            let applied = graph
                .apply(Patch::Replace {
                    old_root,
                    root,
                    nodes: nodes.clone(),
                })
                .expect("invalid smoke update");
            accept_transaction(&graph, &applied);
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
    /// Where this node sits, named rather than numbered. Two mounted nodes
    /// from different patches with the same identity are the same control, and
    /// share this one GPUI entity — which is what lets a press survive a
    /// rerender under the finger.
    identity: ElementIdentity,
    children: Vec<Entity<NodeView>>,
    runtime: WeakEntity<Runtime>,
    is_root: bool,
    input_enabled: bool,
    focus_handle: Option<FocusHandle>,
    input: Option<Entity<input::TextInput>>,
    canvas_bounds: Arc<Mutex<Option<Bounds<Pixels>>>>,
    /// The scroll position of a scroll region or virtual list, owned by the
    /// view rather than by GPUI's per-element state. Held here so that a node
    /// which keeps its identity across a patch keeps its scroll position too,
    /// and so that a window specification can reach the same offset cell the
    /// production wheel handler writes.
    scroll: Option<ScrollTracker>,
}

/// The retained scroll position of one scrolling node.
///
/// Two shapes because GPUI has two: a scroll region is a `div` with overflow,
/// and a virtual list is a `uniform_list` whose rows below the fold do not
/// exist as elements at all and must be reached by index.
#[derive(Clone)]
pub(crate) enum ScrollTracker {
    Region(ScrollHandle),
    List(UniformListScrollHandle),
}

impl ScrollTracker {
    fn for_kind(kind: &NodeKind) -> Option<Self> {
        match kind {
            NodeKind::Scroll { .. } => Some(Self::Region(ScrollHandle::new())),
            NodeKind::VirtualList { .. } => Some(Self::List(UniformListScrollHandle::new())),
            _ => None,
        }
    }

    /// The scroll region's own rectangle, in window coordinates.
    ///
    /// Not the probe's: the probe marker is a child of the scrolling element
    /// and therefore travels with the content, so after a scroll it no longer
    /// describes the viewport the content is clipped to. GPUI records the
    /// container's bounds on the handle at every prepaint, which does not move.
    pub(crate) fn viewport(&self) -> Bounds<Pixels> {
        match self {
            Self::Region(handle) => handle.bounds(),
            Self::List(handle) => handle.0.borrow().base_handle.bounds(),
        }
    }

    /// Move the content by `delta` logical pixels along the scroll axes.
    ///
    /// Positive `y` scrolls towards the end of the content, which is the
    /// direction a wheel-down gesture moves it. GPUI clamps the offset against
    /// the content size on the next prepaint, so an overlarge request settles
    /// at the end rather than past it.
    pub(crate) fn scroll_by(&self, delta: Point<Pixels>) {
        let base = match self {
            Self::Region(handle) => handle.clone(),
            Self::List(handle) => handle.0.borrow().base_handle.clone(),
        };
        let offset = base.offset();
        base.set_offset(point(offset.x - delta.x, offset.y - delta.y));
    }

    /// Bring child `index` of a virtual list into view.
    pub(crate) fn scroll_to_row(&self, index: usize) -> bool {
        match self {
            Self::List(handle) => {
                handle.scroll_to_item(index, ScrollStrategy::Center);
                true
            }
            Self::Region(_) => false,
        }
    }
}

/// Place the container's children across and along its layout axis. `Native`
/// leaves the element's own alignment alone, which is how a row keeps centring
/// its children unless the application says otherwise.
fn apply_axes(mut element: Stateful<Div>, style: &Style) -> Stateful<Div> {
    element = match style.align {
        Align::Native => element,
        Align::Start => element.items_start(),
        Align::Center => element.items_center(),
        Align::End => element.items_end(),
        Align::Baseline => element.items_baseline(),
        Align::Stretch => {
            element.style().align_items = Some(AlignItems::Stretch);
            element
        }
    };
    match style.justify {
        Justify::Native => element,
        Justify::Start => element.justify_start(),
        Justify::Center => element.justify_center(),
        Justify::End => element.justify_end(),
        Justify::Between => element.justify_between(),
        Justify::Around => element.justify_around(),
    }
}

fn apply_style(mut element: Stateful<Div>, style: &Style) -> Stateful<Div> {
    element = apply_axes(element, style)
        .gap(px(style.gap as f32))
        .pt(px(style.padding[0] as f32))
        .pr(px(style.padding[1] as f32))
        .pb(px(style.padding[2] as f32))
        .pl(px(style.padding[3] as f32));
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
    // A Px floor or ceiling is what stops a fixed side being squeezed by a
    // sibling's overflow, or grown past the space it should occupy.
    if let Length::Px(value) = style.min_width {
        element = element.min_w(px(value as f32));
    }
    if let Length::Px(value) = style.min_height {
        element = element.min_h(px(value as f32));
    }
    if let Length::Px(value) = style.max_width {
        element = element.max_w(px(value as f32));
    }
    if let Length::Px(value) = style.max_height {
        element = element.max_h(px(value as f32));
    }
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
    element = element
        .border_t(px(style.border_width[0] as f32))
        .border_r(px(style.border_width[1] as f32))
        .border_b(px(style.border_width[2] as f32))
        .border_l(px(style.border_width[3] as f32));
    if style.radius > 0 {
        element = element.rounded(px(style.radius as f32));
    }
    if style.font_size > 0 {
        element = element.text_size(px(style.font_size as f32));
    }
    if let FontFace::Monospace = style.font_face {
        element = element.font_family(MONOSPACE_FAMILY);
    }
    if style.font_weight > 0 {
        element = element.font_weight(FontWeight(style.font_weight as f32));
    }
    // A raised surface separates from its ground by shadow where a hairline
    // border has too little contrast to read. The blur is the element's own,
    // so a paper-light palette can choose both the colour and how much of it.
    if style.shadow > 0 {
        let rgba = style.shadow_color.unwrap_or(0x000000);
        let alpha = (style.shadow_alpha.min(100) as f32) / 100.0;
        element = element.shadow(vec![BoxShadow {
            color: gpui::Rgba {
                r: ((rgba >> 16) & 0xff) as f32 / 255.0,
                g: ((rgba >> 8) & 0xff) as f32 / 255.0,
                b: (rgba & 0xff) as f32 / 255.0,
                a: alpha,
            }
            .into(),
            offset: gpui::point(px(0.0), px(style.shadow_y as f32)),
            blur_radius: px(style.shadow as f32),
            spread_radius: px(0.0),
        }]);
    }
    element = match style.text_overflow {
        TextOverflow::Wrap => element,
        TextOverflow::NoWrap => element.whitespace_nowrap(),
        TextOverflow::Ellipsis => element.whitespace_nowrap().text_ellipsis(),
    };
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

pub(crate) fn canvas_target(primitives: &[CanvasPrimitive], x: i32, y: i32) -> Option<u64> {
    primitives.iter().rev().find_map(|item| {
        let hit = match item.kind {
            CanvasPrimitiveKind::Rectangle => {
                x >= item.x
                    && y >= item.y
                    && i64::from(x) <= i64::from(item.x) + i64::from(item.width)
                    && i64::from(y) <= i64::from(item.y) + i64::from(item.height)
            }
            CanvasPrimitiveKind::Ellipse => {
                let rx = f64::from(item.width) / 2.0;
                let ry = f64::from(item.height) / 2.0;
                rx > 0.0 && ry > 0.0 && {
                    let dx = (f64::from(x - item.x) - rx) / rx;
                    let dy = (f64::from(y - item.y) - ry) / ry;
                    dx * dx + dy * dy <= 1.0
                }
            }
            CanvasPrimitiveKind::Line => {
                let ax = f64::from(item.x);
                let ay = f64::from(item.y);
                let dx = f64::from(item.x2 - item.x);
                let dy = f64::from(item.y2 - item.y);
                let length_sq = dx * dx + dy * dy;
                let projection = if length_sq == 0.0 {
                    0.0
                } else {
                    (((f64::from(x) - ax) * dx + (f64::from(y) - ay) * dy) / length_sq)
                        .clamp(0.0, 1.0)
                };
                let nearest_x = ax + projection * dx;
                let nearest_y = ay + projection * dy;
                let distance_x = f64::from(x) - nearest_x;
                let distance_y = f64::from(y) - nearest_y;
                let tolerance = f64::from(item.stroke_width.max(6)) / 2.0;
                distance_x * distance_x + distance_y * distance_y <= tolerance * tolerance
            }
        };
        hit.then_some(item.key)
    })
}

const FOCUS_RING: u32 = 0xf2a65a;
const DISABLED_BG: u32 = 0x24333c;
const DISABLED_FG: u32 = 0x6d7d87;
const CHECKBOX_BORDER: u32 = 0x8fa3ad;
const CHECKBOX_BG: u32 = 0x1b2b33;
const CHECKBOX_CHECKED_BG: u32 = 0x9bdcf0;
const CHECKBOX_CHECKED_FG: u32 = 0x13222a;

fn trace_ellipse(builder: &mut PathBuilder, center: Point<Pixels>, radii: Size<f32>) {
    const KAPPA: f32 = 0.5522848;
    let cx = f32::from(center.x);
    let cy = f32::from(center.y);
    let (rx, ry) = (radii.width, radii.height);
    if rx <= 0.0 || ry <= 0.0 {
        return;
    }
    let (ox, oy) = (rx * KAPPA, ry * KAPPA);
    builder.move_to(point(px(cx - rx), px(cy)));
    builder.cubic_bezier_to(
        point(px(cx), px(cy - ry)),
        point(px(cx - rx), px(cy - oy)),
        point(px(cx - ox), px(cy - ry)),
    );
    builder.cubic_bezier_to(
        point(px(cx + rx), px(cy)),
        point(px(cx + ox), px(cy - ry)),
        point(px(cx + rx), px(cy - oy)),
    );
    builder.cubic_bezier_to(
        point(px(cx), px(cy + ry)),
        point(px(cx + rx), px(cy + oy)),
        point(px(cx + ox), px(cy + ry)),
    );
    builder.cubic_bezier_to(
        point(px(cx - rx), px(cy)),
        point(px(cx - ox), px(cy + ry)),
        point(px(cx - rx), px(cy + oy)),
    );
    builder.close();
}

/// The host's own disabled treatment suits the default dark ground. An
/// application that names its own disabled colours gets those instead, at full
/// opacity: a chosen colour is already the colour it wants to be, and fading it
/// is what left a saturated pill still reading as live on a near-black ground.
fn apply_disabled(element: Stateful<Div>, style: &Style) -> Stateful<Div> {
    let element = element
        .bg(rgb(style.disabled_bg.unwrap_or(DISABLED_BG)))
        .text_color(rgb(style.disabled_fg.unwrap_or(DISABLED_FG)))
        .cursor_default();
    match (style.disabled_bg, style.disabled_fg) {
        (None, None) => element.opacity(0.55),
        _ => element,
    }
}

fn apply_focus_ring(element: Stateful<Div>, style: &Style) -> Stateful<Div> {
    let ring = rgb(style.focus_color.unwrap_or(FOCUS_RING));
    element.focus(move |focused| focused.border_2().border_color(ring))
}

impl Render for NodeView {
    fn render(&mut self, _: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        // A component boundary owns identity and updates, but contributes no
        // flex item, padding, or other native layout box.
        if matches!(self.node.kind, NodeKind::Boundary { .. }) {
            return AnyView::from(self.children[0].clone()).into_any_element();
        }
        // The element key is the view's own, not the mounted node id: a node id
        // is never reused, so keying by it gave every control a new GPUI
        // element on every patch and threw away the element state — including
        // the pending mouse-down that turns a press and a release into a
        // click. This view is already the node's stable identity, so a
        // constant key inside it is both stable and unique.
        let mut element = div().id("node");
        let mut append_children = true;
        if self.is_root {
            element = element.size_full().min_h_0().min_w_0();
        }
        match &self.node.kind {
            NodeKind::Boundary { .. } => unreachable!("boundary rendered above"),
            NodeKind::Canvas {
                label: _,
                primitives,
                style,
            } => {
                let paint_items = primitives.clone();
                let hit_items = primitives.clone();
                let bounds_slot = self.canvas_bounds.clone();
                let down_bounds = self.canvas_bounds.clone();
                let down_runtime = self.runtime.clone();
                let paint_runtime = self.runtime.clone();
                let canvas_id = self.node.id;
                let drawing = canvas(
                    move |bounds, _, _| {
                        *bounds_slot.lock().expect("canvas bounds poisoned") = Some(bounds);
                    },
                    move |bounds, _, window, _| {
                        for item in &paint_items {
                            match item.kind {
                                CanvasPrimitiveKind::Rectangle => {
                                    let item_bounds = Bounds::new(
                                        point(
                                            bounds.origin.x + px(item.x as f32),
                                            bounds.origin.y + px(item.y as f32),
                                        ),
                                        size(px(item.width as f32), px(item.height as f32)),
                                    );
                                    window.paint_quad(quad(
                                        item_bounds,
                                        px(item.radius as f32),
                                        item.fill.map(rgb).unwrap_or_else(|| rgba(0x00000000)),
                                        px(item.stroke_width as f32),
                                        item.stroke.map(rgb).unwrap_or_else(|| rgba(0x00000000)),
                                        Default::default(),
                                    ));
                                }
                                CanvasPrimitiveKind::Ellipse => {
                                    let center = point(
                                        bounds.origin.x
                                            + px(item.x as f32 + item.width as f32 / 2.0),
                                        bounds.origin.y
                                            + px(item.y as f32 + item.height as f32 / 2.0),
                                    );
                                    let radii =
                                        size(item.width as f32 / 2.0, item.height as f32 / 2.0);
                                    if let Some(fill) = item.fill {
                                        let mut builder = PathBuilder::fill();
                                        trace_ellipse(&mut builder, center, radii);
                                        if let Ok(path) = builder.build() {
                                            window.paint_path(path, rgb(fill));
                                        }
                                    }
                                    if let (Some(stroke), true) =
                                        (item.stroke, item.stroke_width > 0)
                                    {
                                        let mut builder =
                                            PathBuilder::stroke(px(item.stroke_width as f32));
                                        trace_ellipse(&mut builder, center, radii);
                                        if let Ok(path) = builder.build() {
                                            window.paint_path(path, rgb(stroke));
                                        }
                                    }
                                }
                                CanvasPrimitiveKind::Line => {
                                    let mut builder =
                                        PathBuilder::stroke(px(item.stroke_width.max(1) as f32));
                                    builder.move_to(point(
                                        bounds.origin.x + px(item.x as f32),
                                        bounds.origin.y + px(item.y as f32),
                                    ));
                                    builder.line_to(point(
                                        bounds.origin.x + px(item.x2 as f32),
                                        bounds.origin.y + px(item.y2 as f32),
                                    ));
                                    if let Ok(path) = builder.build() {
                                        window.paint_path(
                                            path,
                                            item.stroke
                                                .map(rgb)
                                                .unwrap_or_else(|| rgba(0x00000000)),
                                        );
                                    }
                                }
                            }
                        }
                        let move_runtime = paint_runtime.clone();
                        window.on_mouse_event(move |event: &MouseMoveEvent, phase, _, cx| {
                            if phase == DispatchPhase::Bubble {
                                let x =
                                    f32::from(event.position.x - bounds.origin.x).round() as i32;
                                let y =
                                    f32::from(event.position.y - bounds.origin.y).round() as i32;
                                let _ = move_runtime.update(cx, |runtime, cx| {
                                    runtime.canvas_pointer_for_node(canvas_id, 1, x, y, 0, cx)
                                });
                            }
                        });
                        let up_runtime = paint_runtime.clone();
                        window.on_mouse_event(move |event: &MouseUpEvent, phase, _, cx| {
                            if phase == DispatchPhase::Bubble && event.button == MouseButton::Left {
                                let x =
                                    f32::from(event.position.x - bounds.origin.x).round() as i32;
                                let y =
                                    f32::from(event.position.y - bounds.origin.y).round() as i32;
                                let _ = up_runtime.update(cx, |runtime, cx| {
                                    runtime.canvas_pointer_for_node(canvas_id, 2, x, y, 0, cx)
                                });
                            }
                        });
                    },
                )
                .size_full();
                element = apply_style(element, style)
                    .child(drawing)
                    .cursor(CursorStyle::Crosshair)
                    .on_mouse_down(MouseButton::Left, move |event, _, cx| {
                        if let Some(bounds) = *down_bounds.lock().expect("canvas bounds poisoned") {
                            let x = f32::from(event.position.x - bounds.origin.x).round() as i32;
                            let y = f32::from(event.position.y - bounds.origin.y).round() as i32;
                            let target = canvas_target(&hit_items, x, y).unwrap_or(0);
                            let _ = down_runtime.update(cx, |runtime, cx| {
                                runtime.canvas_pointer_for_node(canvas_id, 0, x, y, target, cx)
                            });
                        }
                    });
            }
            NodeKind::Column { style, .. } | NodeKind::Panel { style, .. } => {
                element = apply_style(element.flex().flex_col(), style);
            }
            NodeKind::Dialog { style, .. } => {
                let dialog_id = self.node.id;
                let runtime = self.runtime.clone();
                let inner = apply_style(div().id("dialog-surface").flex().flex_col(), style)
                    .children(self.children.iter().cloned().map(AnyView::from));
                element = element
                    .absolute()
                    .top_0()
                    .left_0()
                    .size_full()
                    .flex()
                    .items_center()
                    .justify_center()
                    .bg(rgba(0x00000099))
                    .on_action(move |_: &ActivateEscape, _, cx| {
                        let _ = runtime.update(cx, |runtime, cx| {
                            runtime.activate_if_live(dialog_id, ControlKey::Escape, cx)
                        });
                    })
                    .child(inner);
                append_children = false;
            }
            NodeKind::Row { style, .. } => {
                element = apply_style(element.flex().flex_row().items_center(), style);
            }
            NodeKind::Scroll { axis, style, .. } => {
                element = apply_style(element.flex().flex_col().flex_grow(), style)
                    .scrollbar_width(px(8.0));
                // Tracking hands GPUI the view's own offset cell in place of
                // the one it would keep in per-element state. The wheel handler
                // writes through the same cell either way, so this changes
                // nothing about interactive scrolling; what it adds is a
                // durable position and a handle a specification can reach.
                if let Some(ScrollTracker::Region(handle)) = &self.scroll {
                    element = element.track_scroll(handle);
                }
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
            NodeKind::VirtualItem { .. } => {}
            NodeKind::VirtualList {
                row_height,
                row_gap,
                style,
                ..
            } => {
                let list_id = self.node.id;
                let count = self.node.children.len();
                let runtime = self.runtime.clone();
                let height = *row_height;
                let gap = *row_gap;
                element = apply_style(element.flex().flex_col().flex_grow(), style)
                    .min_h_0()
                    .max_h_full()
                    .child({
                        let list = uniform_list("virtual-list", count, move |range, _, cx| {
                            runtime
                                .update(cx, |runtime, cx| {
                                    runtime.virtual_range(list_id, range, height, gap, cx)
                                })
                                .unwrap_or_default()
                        })
                        .size_full();
                        match &self.scroll {
                            Some(ScrollTracker::List(handle)) => list.track_scroll(handle.clone()),
                            _ => list,
                        }
                    });
            }
            NodeKind::Text(value) => {
                element = element.child(value.clone());
            }
            // A typographic step is about the string alone, so it costs no
            // container: the colour, size, weight, and face are the text
            // element's own and nothing else about the layout changes.
            NodeKind::StyledText {
                value,
                fg,
                font_size,
                font_weight,
                font_face,
            } => {
                element = element.child(value.clone());
                if let Some(color) = fg {
                    element = element.text_color(rgb(*color));
                }
                if *font_size > 0 {
                    element = element.text_size(px(*font_size as f32));
                }
                if *font_weight > 0 {
                    element = element.font_weight(FontWeight(*font_weight as f32));
                }
                if let FontFace::Monospace = font_face {
                    element = element.font_family(MONOSPACE_FAMILY);
                }
            }
            NodeKind::Textarea {
                label,
                value,
                placeholder,
                enabled,
                read_only,
                style,
            } => {
                let node_id = self.node.id;
                let runtime = self.runtime.clone();
                let current = value.clone();
                let shown = if value.is_empty() {
                    placeholder.clone()
                } else {
                    value.clone()
                };
                element = apply_style(element.flex().flex_col().child(shown), style)
                    .scrollbar_width(px(8.0));
                if *enabled && !*read_only && self.input_enabled {
                    if let Some(handle) = &self.focus_handle {
                        element = element.track_focus(handle).tab_index(0);
                    }
                    element = apply_focus_ring(element.cursor(CursorStyle::IBeam), style)
                        .on_key_down(move |event, _, cx| {
                            let mut next = current.clone();
                            if event.keystroke.key == "backspace" {
                                next.pop();
                            } else if event.keystroke.key == "enter" {
                                next.push('\n');
                            } else if let Some(text) = &event.keystroke.key_char {
                                next.push_str(text);
                            } else {
                                return;
                            }
                            cx.stop_propagation();
                            let _ = runtime
                                .update(cx, |runtime, cx| runtime.input_if_live(node_id, next, cx));
                        });
                } else if !*enabled {
                    element = apply_disabled(element, style);
                }
                let _ = label;
            }
            NodeKind::Image {
                bytes,
                format,
                fit,
                grayscale,
                style,
                ..
            } => {
                let native_format = match format {
                    BridgeImageFormat::Bmp => gpui::ImageFormat::Bmp,
                    BridgeImageFormat::Gif => gpui::ImageFormat::Gif,
                    BridgeImageFormat::Jpeg => gpui::ImageFormat::Jpeg,
                    BridgeImageFormat::Png => gpui::ImageFormat::Png,
                    BridgeImageFormat::Svg => gpui::ImageFormat::Svg,
                    BridgeImageFormat::Tiff => gpui::ImageFormat::Tiff,
                    BridgeImageFormat::Webp => gpui::ImageFormat::Webp,
                };
                let object_fit = match fit {
                    ImageFit::Contain => ObjectFit::Contain,
                    ImageFit::Cover => ObjectFit::Cover,
                    ImageFit::Fill => ObjectFit::Fill,
                    ImageFit::None => ObjectFit::None,
                    ImageFit::ScaleDown => ObjectFit::ScaleDown,
                };
                // The declared box is authoritative and `fit` maps pixels into
                // it. A Fill or fixed side also needs its flex minimum
                // released, or the picture lays out past the space it was
                // given instead of fitting it.
                let mut picture = img(std::sync::Arc::new(gpui::Image::from_bytes(
                    native_format,
                    bytes.clone(),
                )))
                .size_full()
                .min_w_0()
                .min_h_0()
                .object_fit(object_fit)
                .grayscale(*grayscale);
                // Clip the decoded picture to the element's own radius. The
                // container's rounded quad is painted behind the child, so
                // without this a 16-point media corner has a square picture
                // sitting over it.
                if style.radius > 0 {
                    picture = picture.rounded(px(style.radius as f32));
                }
                // Releasing the container's flex minimum is what stops an
                // intrinsically larger picture laying out past the box it was
                // given. It must not overrule a floor the application declared,
                // though: min_w_0 on a box with min_width: Px(88) is how a
                // square thumbnail ended up 61.5 points wide beside a caption.
                element = apply_style(element, style);
                if matches!(style.min_width, Length::Auto) {
                    element = element.min_w_0();
                }
                if matches!(style.min_height, Length::Auto) {
                    element = element.min_h_0();
                }
                element = element.child(picture);
            }
            NodeKind::TextInput { enabled, style, .. } => {
                element = apply_style(element.flex().items_center(), style);
                if !enabled || !self.input_enabled {
                    element = apply_disabled(element, style);
                }
                if let Some(editor) = &self.input {
                    element = element.child(editor.clone());
                }
            }
            NodeKind::Button {
                caption,
                enabled,
                style,
                ..
            } => {
                let node_id = self.node.id;
                let runtime = self.runtime.clone();
                let enter_runtime = self.runtime.clone();
                let space_runtime = self.runtime.clone();
                element = apply_style(
                    element
                        .flex()
                        .items_center()
                        .justify_center()
                        .child(caption.clone()),
                    style,
                );
                if *enabled && self.input_enabled {
                    if let Some(handle) = &self.focus_handle {
                        element = element.track_focus(handle).tab_index(0);
                    }
                    element = apply_focus_ring(element, style)
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
                } else {
                    element = apply_disabled(element, style);
                }
            }
            NodeKind::Checkbox {
                label,
                checked,
                enabled,
                indicator,
                style,
            } => {
                let node_id = self.node.id;
                let runtime = self.runtime.clone();
                let enabled_box = *enabled && self.input_enabled;
                let mark = if *checked { "✓" } else { "" };
                let box_bg = if *checked {
                    indicator.box_checked_bg.unwrap_or(CHECKBOX_CHECKED_BG)
                } else {
                    indicator.box_bg.unwrap_or(CHECKBOX_BG)
                };
                let box_border = indicator.box_border.unwrap_or(CHECKBOX_BORDER);
                let box_fg = if *checked {
                    indicator.mark_color.unwrap_or(CHECKBOX_CHECKED_FG)
                } else {
                    box_border
                };
                element = apply_axes(element.flex().flex_row().items_center(), style)
                    .gap(px(style.gap as f32))
                    .pt(px(style.padding[0] as f32))
                    .pr(px(style.padding[1] as f32))
                    .pb(px(style.padding[2] as f32))
                    .pl(px(style.padding[3] as f32))
                    .child(
                        div()
                            .w(px(18.0))
                            .h(px(18.0))
                            .border_1()
                            .border_color(rgb(if enabled_box {
                                box_border
                            } else {
                                style.disabled_fg.unwrap_or(DISABLED_FG)
                            }))
                            .bg(rgb(box_bg))
                            .text_color(rgb(box_fg))
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
                // A Px floor or ceiling is what stops a fixed side being squeezed by a
                // sibling's overflow, or grown past the space it should occupy.
                if let Length::Px(value) = style.min_width {
                    element = element.min_w(px(value as f32));
                }
                if let Length::Px(value) = style.min_height {
                    element = element.min_h(px(value as f32));
                }
                if let Length::Px(value) = style.max_width {
                    element = element.max_w(px(value as f32));
                }
                if let Length::Px(value) = style.max_height {
                    element = element.max_h(px(value as f32));
                }
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
                element = element
                    .border_t(px(style.border_width[0] as f32))
                    .border_r(px(style.border_width[1] as f32))
                    .border_b(px(style.border_width[2] as f32))
                    .border_l(px(style.border_width[3] as f32));
                if style.radius > 0 {
                    element = element.rounded(px(style.radius as f32));
                }
                if style.font_size > 0 {
                    element = element.text_size(px(style.font_size as f32));
                }
                if let FontFace::Monospace = style.font_face {
                    element = element.font_family(MONOSPACE_FAMILY);
                }
                if style.font_weight > 0 {
                    element = element.font_weight(FontWeight(style.font_weight as f32));
                }
                element = match style.text_overflow {
                    TextOverflow::Wrap => element,
                    TextOverflow::NoWrap => element.whitespace_nowrap(),
                    TextOverflow::Ellipsis => element.whitespace_nowrap().text_ellipsis(),
                };
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
                if *enabled && self.input_enabled {
                    let space_runtime = self.runtime.clone();
                    if let Some(handle) = &self.focus_handle {
                        element = element.track_focus(handle).tab_index(0);
                    }
                    element = apply_focus_ring(element, style)
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
                } else {
                    element = apply_disabled(element, style);
                }
            }
        }
        if probe::enabled() {
            element = element.child(probe::marker(self.node.id));
        }
        if append_children {
            element
                .children(self.children.iter().cloned().map(AnyView::from))
                .into_any_element()
        } else {
            element.into_any_element()
        }
    }
}

struct Runtime {
    graph: MountedGraph,
    /// How many patches this runtime has applied.
    ///
    /// A painted question is only answerable about a generation the window has
    /// drawn, so every applied patch moves this forward and every frame stamps
    /// the generation it drew. See [`crate::probe::Frame`].
    generation: u64,
    views: HashMap<u64, Entity<NodeView>>,
    /// Where each mounted node sits, for the graph currently mounted. Captured
    /// so that when a patch retires those nodes their views can still be found
    /// by identity rather than by the id that is about to disappear.
    identities: HashMap<u64, ElementIdentity>,
    /// Views whose nodes the last patch retired, indexed by identity. A staged
    /// node that names the same control claims the entity back instead of
    /// getting a fresh one. Held only until the next patch.
    recyclable: HashMap<ElementIdentity, Entity<NodeView>>,
    virtual_views: HashMap<(u64, u64), VirtualCached>,
    virtual_row_owners: HashMap<u64, u64>,
    virtual_lists: HashMap<u64, VirtualListCache>,
    virtual_entities: HashMap<u64, VirtualCached>,
    preserved_virtual: std::collections::HashSet<u64>,
    virtual_constructions: u64,
    focus_handles: HashMap<u64, FocusHandle>,
    /// The live scroll position of every mounted scrolling node, by id. The
    /// same tracker the node's view holds, so writing through it moves the
    /// production element rather than a copy of its state.
    scroll_trackers: HashMap<u64, ScrollTracker>,
    /// Where each canvas actually paints, by node id. The node's own div may be
    /// inset by its style, and a primitive's coordinates are relative to the
    /// painted surface rather than to that div, so this is the origin a
    /// primitive's rectangle is measured from — the same slot the painter and
    /// the hit test use.
    canvas_surfaces: HashMap<u64, Arc<Mutex<Option<Bounds<Pixels>>>>>,
    root: Option<Entity<NodeView>>,
    cycle_ordinal: u64,
    active_dialog: Option<u64>,
    dialog_return_focus: Option<ElementIdentity>,
    last_trigger_focus: Option<ElementIdentity>,
    focused_identity: Option<(u64, ElementIdentity)>,
    /// The focused control's position in the focus order when it was last
    /// rendered. It is the only thing that survives the control itself.
    focused_position: Option<usize>,
    focus_after_render: Option<u64>,
    editors: HashMap<ElementIdentity, Entity<input::TextInput>>,
    editor_nodes: HashMap<ElementIdentity, u64>,
    canvas_drag: Option<(ElementIdentity, u64)>,
}

#[derive(Clone)]
struct VirtualCached {
    view: Entity<NodeView>,
    entities: u64,
}

#[derive(Default)]
struct VirtualListCache {
    rows: std::collections::HashSet<u64>,
    entities: u64,
}

struct InitialMount {
    patch: Patch,
    cycle_started: Instant,
    roc_callback_ns: u64,
    roc_work: [observatory::RocWork; observatory::ROC_WORK_KINDS],
    roc_work_valid: bool,
}

impl Runtime {
    fn new(initial: InitialMount, cx: &mut Context<Self>) -> Self {
        let mut runtime = Self {
            graph: MountedGraph::default(),
            generation: 0,
            views: HashMap::new(),
            identities: HashMap::new(),
            recyclable: HashMap::new(),
            virtual_views: HashMap::new(),
            virtual_row_owners: HashMap::new(),
            virtual_lists: HashMap::new(),
            virtual_entities: HashMap::new(),
            preserved_virtual: std::collections::HashSet::new(),
            virtual_constructions: 0,
            focus_handles: HashMap::new(),
            scroll_trackers: HashMap::new(),
            canvas_surfaces: HashMap::new(),
            root: None,
            cycle_ordinal: 0,
            active_dialog: None,
            dialog_return_focus: None,
            last_trigger_focus: None,
            focused_identity: None,
            focused_position: None,
            focus_after_render: None,
            editors: HashMap::new(),
            editor_nodes: HashMap::new(),
            canvas_drag: None,
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
                if completion.epoch != TASK_EPOCH.load(Ordering::Acquire) {
                    continue;
                }
                task_runtime().completed.fetch_add(1, Ordering::Relaxed);
                if runtime
                    .update(cx, |runtime, cx| {
                        let patch = complete(completion);
                        runtime.apply_unrecorded(patch, cx);
                    })
                    .is_err()
                {
                    break;
                }
            }
        })
        .detach();
        // The chooser wakes on the request rather than polling for it. A person
        // who presses Open waits for the panel, and every millisecond between
        // the press and the panel is time the application looks unresponsive
        // for no reason.
        let (chooser_requests, chooser_pending) =
            async_channel::unbounded::<files::ChooserRequest>();
        files::install_chooser(chooser_requests);
        cx.spawn(async move |_, cx| {
            while let Ok(request) = chooser_pending.recv().await {
                let prompt = cx.update(|cx| {
                    cx.prompt_for_paths(PathPromptOptions {
                        files: false,
                        directories: true,
                        multiple: false,
                        prompt: Some("Open".into()),
                    })
                });
                let Ok(prompt) = prompt else { break };
                let chosen = match prompt.await {
                    Ok(Ok(Some(paths))) => paths.into_iter().next(),
                    _ => None,
                };
                let _ = request.reply.send(chosen);
            }
        })
        .detach();
        let executor = cx.background_executor().clone();
        cx.spawn(async move |_, cx| {
            loop {
                executor.timer(std::time::Duration::from_millis(100)).await;
                if cx
                    .update(|cx| {
                        clipboard::observe_system(
                            cx.read_from_clipboard().and_then(|item| item.text()),
                        );
                        if let Some(text) = clipboard::take_system_write() {
                            cx.write_to_clipboard(ClipboardItem::new_string(text));
                        }
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

    fn canvas_pointer(
        &mut self,
        label: &str,
        phase: u8,
        x: i32,
        y: i32,
        target: u64,
        cx: &mut Context<Self>,
    ) {
        let id = self.graph.nodes_preorder().into_iter().find_map(|node| {
            matches!(&node.kind, NodeKind::Canvas { label: current, .. } if current == label)
                .then_some(node.id)
        });
        if let Some(id) = id {
            self.canvas_pointer_for_node(id, phase, x, y, target, cx);
        }
    }

    fn canvas_pointer_for_node(
        &mut self,
        id: u64,
        phase: u8,
        x: i32,
        y: i32,
        target: u64,
        cx: &mut Context<Self>,
    ) {
        if !matches!(
            self.graph.node(id).map(|node| &node.kind),
            Some(NodeKind::Canvas { .. })
        ) {
            return;
        }
        let Some(identity) = self.identities.get(&id).cloned() else {
            return;
        };
        let resolved_target = match phase {
            0 => {
                self.canvas_drag = Some((identity.clone(), target));
                target
            }
            1 | 2 => match &self.canvas_drag {
                Some((active, target)) if *active == identity => *target,
                _ => return,
            },
            _ => return,
        };
        let event = CanvasEventPayload {
            phase,
            x,
            y,
            target: resolved_target,
        };
        let patch = dispatch_canvas(id, event);
        self.apply_unrecorded(patch, cx);
        if phase == 2 {
            self.canvas_drag = None;
        }
    }

    fn event_if_live(&mut self, id: u64, cx: &mut Context<Self>) {
        if self
            .active_dialog
            .is_some_and(|dialog| !self.graph.is_descendant_of(id, dialog))
        {
            return;
        }
        if !self
            .graph
            .node(id)
            .is_some_and(|node| node.kind.dispatches_click())
        {
            return;
        }
        if !matches!(
            self.graph.node(id).map(|node| &node.kind),
            Some(NodeKind::Dialog { .. })
        ) {
            self.last_trigger_focus = self.identities.get(&id).cloned();
        }
        self.dispatch_live_event(id, "click", cx);
    }

    fn text_event_if_live(
        &mut self,
        identity: &ElementIdentity,
        node_id: u64,
        event_id: u64,
        value: String,
        trigger: &'static str,
        cx: &mut Context<Self>,
    ) {
        let acknowledgement = self
            .editors
            .get(identity)
            .cloned()
            .map(|editor| (editor, value.clone()));
        if self
            .active_dialog
            .is_some_and(|dialog| !self.graph.is_descendant_of(node_id, dialog))
        {
            if let Some((editor, submitted)) = acknowledgement {
                editor.update(cx, |editor, cx| editor.acknowledge(&submitted, cx));
            }
            return;
        }
        let valid = self
            .graph
            .node(node_id)
            .is_some_and(|node| match &node.kind {
                NodeKind::TextInput { enabled: true, .. } => {
                    event_id == node_id || event_id == (node_id | SUBMIT_EVENT_BIT)
                }
                _ => false,
            });
        if !valid {
            if let Some((editor, submitted)) = acknowledgement {
                editor.update(cx, |editor, cx| editor.acknowledge(&submitted, cx));
            }
            return;
        }
        if let Some((editor, submitted)) = &acknowledgement {
            editor.update(cx, |editor, _| editor.begin_acknowledgement(submitted));
        }
        if observatory::active() {
            let cycle_started = Instant::now();
            observatory::reset_roc_work();
            let roc_started = Instant::now();
            let patch = dispatch_input(event_id, value);
            let roc_callback_ns = elapsed_ns(roc_started);
            let (roc_work, roc_work_valid) = observatory::take_roc_work();
            self.apply_recorded(
                patch,
                trigger,
                cycle_started,
                roc_callback_ns,
                roc_work,
                roc_work_valid,
                cx,
            );
        } else {
            let patch = dispatch_input(event_id, value);
            self.apply_unrecorded(patch, cx);
        }
        if let Some((editor, submitted)) = acknowledgement {
            editor.update(cx, |editor, cx| editor.acknowledge(&submitted, cx));
        }
    }

    fn dispatch_live_event(&mut self, id: u64, trigger: &'static str, cx: &mut Context<Self>) {
        if observatory::active() {
            let cycle_started = Instant::now();
            observatory::reset_roc_work();
            let roc_started = Instant::now();
            let patch = dispatch(id);
            let roc_callback_ns = elapsed_ns(roc_started);
            let (roc_work, roc_work_valid) = observatory::take_roc_work();
            self.apply_recorded(
                patch,
                trigger,
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

    fn input_if_live(&mut self, id: u64, value: String, cx: &mut Context<Self>) {
        if self
            .active_dialog
            .is_some_and(|dialog| !self.graph.is_descendant_of(id, dialog))
        {
            return;
        }
        if !matches!(
            self.graph.node(id).map(|node| &node.kind),
            Some(NodeKind::Textarea {
                enabled: true,
                read_only: false,
                ..
            })
        ) {
            return;
        }
        if observatory::active() {
            let cycle_started = Instant::now();
            observatory::reset_roc_work();
            let roc_started = Instant::now();
            let patch = dispatch_input(id, value);
            let roc_callback_ns = elapsed_ns(roc_started);
            let (roc_work, roc_work_valid) = observatory::take_roc_work();
            self.apply_recorded(
                patch,
                "input",
                cycle_started,
                roc_callback_ns,
                roc_work,
                roc_work_valid,
                cx,
            );
        } else {
            let patch = dispatch_input(id, value);
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

    /// Apply a patch to the mounted graph without recording a cycle.
    ///
    /// The counterpart to [`Self::apply_recorded`], for patches that are not
    /// themselves a measurable interaction.
    fn apply_unrecorded(&mut self, patch: Patch, cx: &mut Context<Self>) {
        let applied = self.graph.apply(patch).unwrap_or_else(|message| {
            reject_transaction();
            panic!("invalid native graph patch: {message}")
        });
        accept_transaction(&self.graph, &applied);
        self.apply_to_gpui(&applied, cx);
    }

    // Carries per-cycle measurement facts straight into the observatory record.
    #[allow(clippy::too_many_arguments)]
    fn apply_recorded(
        &mut self,
        patch: Patch,
        trigger: &'static str,
        cycle_started: Instant,
        roc_callback_ns: u64,
        roc_work: [observatory::RocWork; observatory::ROC_WORK_KINDS],
        roc_work_valid: bool,
        cx: &mut Context<Self>,
    ) {
        let applied = self.graph.apply_measured(patch).unwrap_or_else(|message| {
            reject_transaction();
            panic!("invalid native graph patch: {message}")
        });
        accept_transaction(&self.graph, &applied);
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
            component_work: observatory::component_cycle_work(),
            retained_nodes: applied.facts.retained_nodes,
            validation_visits: applied.facts.validation_visits,
        });
        self.cycle_ordinal += 1;
    }

    /// Where a painted read is admitted, once the window has drawn this graph.
    fn painted(&self) -> Result<probe::Frame<'_>, probe::Stale> {
        probe::frame(self.generation)
    }

    fn apply_to_gpui(&mut self, applied: &bridge::GraphApply, cx: &mut Context<Self>) {
        if applied.facts.kind == "no_change" {
            return;
        }
        let retired_identities = applied
            .removed_ids
            .iter()
            .filter_map(|id| {
                self.identities
                    .get(id)
                    .cloned()
                    .map(|identity| (*id, identity))
            })
            .collect::<Vec<_>>();
        let virtual_parent = applied
            .parent
            .filter(|(parent, _)| self.virtual_entities.contains_key(parent));
        let old_virtual_root = virtual_parent.map(|(parent, position)| {
            self.virtual_entities[&parent].view.read(cx).children[position].clone()
        });
        let old_virtual_entities = old_virtual_root.as_ref().map_or(0, |root| {
            self.virtual_entities[&root.read(cx).node.id].entities
        });
        // Count only this list's materialized tree. Nested list rows have
        // separate cache ownership, and retained frontiers contribute no
        // retirements even though their ancestors are replaced.
        let mut removed_virtual = 0;
        let mut retired_views = old_virtual_root.into_iter().collect::<Vec<_>>();
        while let Some(view) = retired_views.pop() {
            let view = view.read(cx);
            if self.graph.node(view.node.id).is_none() {
                removed_virtual += 1;
                retired_views.extend(view.children.iter().cloned());
            }
        }
        self.preserved_virtual.extend(
            applied
                .retained_roots
                .iter()
                .copied()
                .filter(|id| self.virtual_entities.contains_key(id)),
        );
        // Offer every view whose node this patch retired back to the staged
        // nodes, indexed by identity. A whole-root rebuild stages a complete
        // new set of node ids for what is, to the person using the
        // application, the same controls; without this each of them would get
        // a fresh GPUI entity and lose whatever element state it was carrying.
        self.recyclable.clear();
        let mut doomed: std::collections::HashSet<u64> =
            applied.removed_ids.iter().copied().collect();
        if applied.retired_root {
            doomed.extend(self.views.keys().copied());
        }
        for id in doomed {
            if let Some(view) = self
                .views
                .get(&id)
                .or_else(|| self.virtual_entities.get(&id).map(|cached| &cached.view))
            {
                let identity = view.read(cx).identity.clone();
                self.recyclable.insert(identity, view.clone());
            }
        }
        // Every applied patch leaves the window a frame behind, which is what
        // makes a painted read of the new tree refuse until it catches up.
        self.generation += 1;
        {
            let mut affected = std::collections::HashSet::new();
            for id in &applied.removed_ids {
                if self.virtual_row_owners.contains_key(id) {
                    affected.insert(*id);
                }
                if let Some(list) = self.virtual_lists.get(id) {
                    affected.extend(list.rows.iter().copied());
                }
            }
            for item in affected {
                let old_list = self.virtual_row_owners[&item];
                let cached = self
                    .uncache_virtual_row(old_list, item)
                    .expect("affected virtual row");
                let owner = self
                    .graph
                    .parent(item)
                    .map(|(parent, _)| parent)
                    .filter(|parent| {
                        matches!(
                            self.graph.node(*parent).map(|node| &node.kind),
                            Some(NodeKind::VirtualList { .. })
                        )
                    });
                if let Some(owner) = owner {
                    // A retained visible item can move to a newly staged list
                    // without rebuilding any of its native descendants.
                    self.cache_virtual_row(owner, item, cached);
                } else {
                    observatory::virtual_list_frame(old_list, 0, 0, cached.entities, 0);
                    self.offer_subtree(cached.view, cx);
                }
            }
        }
        if applied.retired_root {
            self.views.clear();
        }
        refresh_identities(&self.graph, applied, &mut self.identities);
        self.materialize(&applied.staged_ids, cx);
        if let (Some(root), Some((parent, _))) = (applied.root, virtual_parent) {
            let constructions_before = self.virtual_constructions;
            let (_, new_virtual_entities) = self.build_virtual_node(root, cx);
            let mut ancestor = Some(parent);
            let mut changed_list = None;
            while let Some(id) = ancestor {
                // A list view does not materialize its rows as ordinary
                // children. A nested list's local work stops at that edge.
                if matches!(
                    self.graph.node(id).map(|node| &node.kind),
                    Some(NodeKind::VirtualList { .. })
                ) {
                    changed_list = Some(id);
                    break;
                }
                if let Some(cached) = self.virtual_entities.get_mut(&id) {
                    cached.entities = cached
                        .entities
                        .checked_sub(old_virtual_entities)
                        .expect("virtual ancestor count underflow")
                        + new_virtual_entities;
                }
                if let Some(list) = self.virtual_row_owners.get(&id).copied() {
                    let cached = self
                        .virtual_views
                        .get_mut(&(list, id))
                        .expect("indexed virtual row");
                    cached.entities = cached
                        .entities
                        .checked_sub(old_virtual_entities)
                        .expect("virtual row count underflow")
                        + new_virtual_entities;
                    let summary = self
                        .virtual_lists
                        .get_mut(&list)
                        .expect("indexed virtual list");
                    summary.entities = summary
                        .entities
                        .checked_sub(old_virtual_entities)
                        .expect("virtual list count underflow")
                        + new_virtual_entities;
                }
                ancestor = self.graph.parent(id).map(|(parent, _)| parent);
            }
            if let Some(list) = changed_list {
                let (items, entities) = self.virtual_lists.get(&list).map_or((0, 0), |summary| {
                    (summary.rows.len() as u64, summary.entities)
                });
                observatory::virtual_list_frame(
                    list,
                    items,
                    self.virtual_constructions - constructions_before,
                    removed_virtual,
                    entities,
                );
            }
        }
        let next_dialog = self.graph.active_dialog();
        match (self.active_dialog.is_some(), next_dialog) {
            (false, Some(dialog)) => {
                self.dialog_return_focus = self.last_trigger_focus.take();
                self.focus_after_render = self.graph.first_focusable_in(dialog);
            }
            (true, None) => {
                self.focus_after_render = self
                    .dialog_return_focus
                    .take()
                    .and_then(|identity| self.find_native_identity(&identity));
            }
            _ => {
                if let Some((id, identity)) = self.focused_identity.clone() {
                    if self.graph.node(id).is_none() {
                        // The same control under a new id keeps focus. A
                        // control that is gone hands focus to whatever now
                        // holds its place, rather than dropping it and
                        // leaving a person's next Tab starting from nowhere.
                        self.focus_after_render =
                            self.find_native_identity(&identity).or_else(|| {
                                self.focused_position
                                    .and_then(|was_at| self.graph.focus_destination(was_at))
                            });
                    }
                }
            }
        }
        if self.active_dialog != next_dialog {
            for (id, view) in self.views.iter().chain(
                self.virtual_entities
                    .iter()
                    .map(|(id, cached)| (id, &cached.view)),
            ) {
                let enabled =
                    next_dialog.is_none_or(|dialog| self.graph.is_descendant_of(*id, dialog));
                view.update(cx, |view, cx| {
                    view.input_enabled = enabled;
                    if let Some(editor) = &view.input {
                        let accepts_input =
                            matches!(view.node.kind, NodeKind::TextInput { enabled: true, .. });
                        editor.update(cx, |editor, cx| {
                            editor.set_enabled(enabled && accepts_input, cx)
                        });
                    }
                    cx.notify();
                });
            }
        }
        self.active_dialog = next_dialog;
        if let Some(root_id) = applied.root {
            if let (Some((_parent_id, position)), Some(new_root), Some(parent_view)) = (
                applied.parent,
                self.native_view(root_id),
                applied
                    .parent
                    .and_then(|(parent, _)| self.native_view(parent)),
            ) {
                parent_view.update(cx, |view, cx| {
                    view.node.children[position] = root_id;
                    view.children[position] = new_root.clone();
                    if view.is_root && matches!(view.node.kind, NodeKind::Boundary { .. }) {
                        new_root.update(cx, |child, cx| {
                            child.is_root = true;
                            cx.notify();
                        });
                    }
                    cx.notify();
                });
            } else if applied.parent.is_some() {
                // The replacement is inside a virtual row. Its complete graph
                // is already committed; the next list callback reconstructs
                // only the affected visible subtree from that graph.
                if let Some(root) = &self.root {
                    root.update(cx, |_, cx| cx.notify());
                }
            } else {
                let new_root = self.views[&root_id].clone();
                let mut layout_root = new_root.clone();
                loop {
                    let next = layout_root.update(cx, |view, cx| {
                        view.is_root = true;
                        cx.notify();
                        matches!(view.node.kind, NodeKind::Boundary { .. })
                            .then(|| view.children[0].clone())
                    });
                    match next {
                        Some(child) => layout_root = child,
                        None => break,
                    }
                }
                self.root = Some(new_root);
                cx.notify();
            }
        }
        for id in &applied.removed_ids {
            self.views.remove(id);
            self.virtual_entities.remove(id);
            self.preserved_virtual.remove(id);
            self.focus_handles.remove(id);
            self.scroll_trackers.remove(id);
            self.canvas_surfaces.remove(id);
        }
        for (retired, identity) in retired_identities {
            if self.editor_nodes.get(&identity) == Some(&retired) {
                self.editor_nodes.remove(&identity);
                self.editors.remove(&identity);
            }
        }
        if self
            .canvas_drag
            .as_ref()
            .is_some_and(|(identity, _)| self.find_native_identity(identity).is_none())
        {
            self.canvas_drag = None;
        }
    }

    fn find_native_identity(&self, identity: &ElementIdentity) -> Option<u64> {
        self.identities.iter().find_map(|(id, candidate)| {
            (candidate == identity && self.graph.node(*id).is_some()).then_some(*id)
        })
    }

    fn native_view(&self, id: u64) -> Option<Entity<NodeView>> {
        self.views.get(&id).cloned().or_else(|| {
            self.virtual_entities
                .get(&id)
                .map(|cached| cached.view.clone())
        })
    }

    /// Give a staged node its GPUI entity.
    ///
    /// A retired view of the same identity and the same kind is claimed back
    /// rather than replaced. Nothing of the old node's content survives — the
    /// view is refreshed from the staged node, and every handler is rebuilt
    /// from it on the next render, so a click still routes to the live node id
    /// and a control that left the tree still drops its press. What survives
    /// is the entity, and with it GPUI's element state: the pending press, the
    /// scroll offset, the focus handle.
    fn claim_view(
        &mut self,
        node: Node,
        input_enabled: bool,
        cx: &mut Context<Self>,
    ) -> Entity<NodeView> {
        let identity = self.identities.get(&node.id).cloned().unwrap_or_default();
        // An empty identity is not an identity: it would make every unplaced
        // node the same control as every other.
        let claimed = (!identity.is_empty())
            .then(|| self.recyclable.remove(&identity))
            .flatten()
            .filter(|view| view.read(cx).node.kind.tag() == node.kind.tag());
        // Reusing the tracker is what keeps a list where the person left it
        // when the application rerenders under them; a fresh one would jump the
        // content back to the top on every patch.
        let scroll = claimed
            .as_ref()
            .and_then(|view| view.read(cx).scroll.clone())
            .or_else(|| ScrollTracker::for_kind(&node.kind));
        let editor = self.editor_for_node(&node, input_enabled, cx);
        let focus_handle = if let Some(editor) = &editor {
            Some(editor.read(cx).focus_handle())
        } else if node.kind.focus_identity().is_some() {
            // Reusing the handle is what keeps keyboard focus on a control
            // whose application rerendered under it, rather than restoring it
            // a frame later.
            claimed
                .as_ref()
                .and_then(|view| view.read(cx).focus_handle.clone())
                .or_else(|| Some(cx.focus_handle()))
        } else {
            None
        };
        match claimed {
            Some(view) => {
                view.update(cx, |existing, cx| {
                    existing.node = node;
                    existing.children = vec![];
                    existing.is_root = false;
                    existing.input_enabled = input_enabled;
                    existing.focus_handle = focus_handle;
                    existing.input = editor;
                    existing.scroll = scroll;
                    cx.notify();
                });
                view
            }
            None => {
                let runtime = cx.entity().downgrade();
                cx.new(|_| NodeView {
                    node,
                    identity,
                    children: vec![],
                    runtime,
                    is_root: false,
                    input_enabled,
                    focus_handle,
                    input: editor,
                    canvas_bounds: Arc::new(Mutex::new(None)),
                    scroll,
                })
            }
        }
    }

    /// Index a retired view and everything under it by identity.
    fn offer_subtree(&mut self, view: Entity<NodeView>, cx: &mut Context<Self>) {
        if self.preserved_virtual.contains(&view.read(cx).node.id) {
            return;
        }
        let (identity, children) = {
            let node = view.read(cx);
            (node.identity.clone(), node.children.clone())
        };
        self.recyclable.insert(identity, view);
        for child in children {
            self.offer_subtree(child, cx);
        }
    }

    fn materialize(&mut self, node_ids: &[u64], cx: &mut Context<Self>) {
        for id in node_ids {
            if matches!(
                self.graph.node(*id).map(|node| &node.kind),
                Some(NodeKind::TextInput { .. })
            ) {
                if let Some(identity) = self
                    .identities
                    .get(id)
                    .filter(|identity| self.editors.contains_key(*identity))
                {
                    self.editor_nodes.insert(identity.clone(), *id);
                }
            }
        }
        let eager = node_ids
            .iter()
            .copied()
            .filter(|id| !self.graph.is_virtual_descendant(*id))
            .collect::<Vec<_>>();
        for id in &eager {
            let node = self
                .graph
                .node(*id)
                .expect("applied node is missing")
                .clone();
            assert!(
                !self.views.contains_key(&node.id),
                "node id {} was reused",
                node.id
            );
            let input_enabled = self
                .active_dialog
                .is_none_or(|dialog| self.graph.is_descendant_of(node.id, dialog));
            let view = self.claim_view(node, input_enabled, cx);
            if let Some(handle) = view.read(cx).focus_handle.clone() {
                self.focus_handles.insert(*id, handle);
            }
            if let Some(tracker) = view.read(cx).scroll.clone() {
                self.scroll_trackers.insert(*id, tracker);
            }
            if matches!(view.read(cx).node.kind, NodeKind::Canvas { .. }) {
                self.canvas_surfaces
                    .insert(*id, view.read(cx).canvas_bounds.clone());
            }
            self.views.insert(*id, view);
        }
        for id in &eager {
            let node = self.graph.node(*id).expect("applied node is missing");
            let children = node
                .children
                .iter()
                .filter(|id| !self.graph.is_virtual_descendant(**id))
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

    fn editor_for_node(
        &mut self,
        node: &Node,
        input_enabled: bool,
        cx: &mut Context<Self>,
    ) -> Option<Entity<input::TextInput>> {
        if let NodeKind::TextInput {
            label: _,
            value,
            placeholder,
            enabled,
            ..
        } = &node.kind
        {
            let identity = self
                .identities
                .get(&node.id)
                .cloned()
                .expect("input identity is missing");
            let change_identity = identity.clone();
            let submit_identity = identity.clone();
            let runtime = cx.entity().downgrade();
            let change_runtime = runtime.clone();
            let submit_runtime = runtime.clone();
            let node_id = node.id;
            let change: input::TextCallback = std::rc::Rc::new(move |text, cx| {
                let _ = change_runtime.update(cx, |runtime, cx| {
                    runtime.text_event_if_live(
                        &change_identity,
                        node_id,
                        node_id,
                        text,
                        "text_change",
                        cx,
                    )
                });
            });
            let submit: input::TextCallback = std::rc::Rc::new(move |text, cx| {
                let _ = submit_runtime.update(cx, |runtime, cx| {
                    runtime.text_event_if_live(
                        &submit_identity,
                        node_id,
                        node_id | SUBMIT_EVENT_BIT,
                        text,
                        "text_submit",
                        cx,
                    )
                });
            });
            self.editor_nodes.insert(identity.clone(), node.id);
            if let Some(editor) = self.editors.get(&identity).cloned() {
                editor.update(cx, |editor, cx| {
                    editor.configure(
                        value,
                        placeholder,
                        *enabled && input_enabled,
                        change,
                        submit,
                        cx,
                    )
                });
                Some(editor)
            } else {
                let editor = cx.new(|cx| {
                    input::TextInput::new(
                        value.clone(),
                        placeholder.clone(),
                        *enabled && input_enabled,
                        change,
                        submit,
                        cx,
                    )
                });
                self.editors.insert(identity, editor.clone());
                Some(editor)
            }
        } else {
            None
        }
    }

    fn build_virtual_node(&mut self, id: u64, cx: &mut Context<Self>) -> (Entity<NodeView>, u64) {
        if self.preserved_virtual.remove(&id) {
            if let Some(cached) = self.virtual_entities.get(&id) {
                return (cached.view.clone(), cached.entities);
            }
        }
        let node = self
            .graph
            .node(id)
            .expect("virtual node is missing")
            .clone();
        let (children, descendants) = if matches!(node.kind, NodeKind::VirtualList { .. }) {
            (vec![], 0)
        } else {
            let built = node
                .children
                .iter()
                .map(|child| self.build_virtual_node(*child, cx))
                .collect::<Vec<_>>();
            let count = built.iter().map(|(_, count)| *count).sum();
            (built.into_iter().map(|(view, _)| view).collect(), count)
        };
        let input_enabled = self
            .active_dialog
            .is_none_or(|dialog| self.graph.is_descendant_of(id, dialog));
        let view = self.claim_view(node, input_enabled, cx);
        view.update(cx, |view, _| view.children = children);
        if let Some(handle) = view.read(cx).focus_handle.clone() {
            self.focus_handles.insert(id, handle);
        }
        if let Some(tracker) = view.read(cx).scroll.clone() {
            self.scroll_trackers.insert(id, tracker);
        }
        if matches!(view.read(cx).node.kind, NodeKind::Canvas { .. }) {
            self.canvas_surfaces
                .insert(id, view.read(cx).canvas_bounds.clone());
        }
        let entities = descendants + 1;
        self.virtual_constructions += 1;
        self.virtual_entities.insert(
            id,
            VirtualCached {
                view: view.clone(),
                entities,
            },
        );
        (view, entities)
    }

    fn forget_virtual_subtree(&mut self, root: Entity<NodeView>, cx: &App) {
        let mut pending = vec![root];
        while let Some(view) = pending.pop() {
            let view = view.read(cx);
            pending.extend(view.children.iter().cloned());
            if let Some(list) = self.virtual_lists.get(&view.node.id) {
                let rows = list.rows.iter().copied().collect::<Vec<_>>();
                for row in rows {
                    if let Some(cached) = self.uncache_virtual_row(view.node.id, row) {
                        pending.push(cached.view);
                    }
                }
            }
            self.virtual_entities.remove(&view.node.id);
            self.preserved_virtual.remove(&view.node.id);
            self.focus_handles.remove(&view.node.id);
            self.scroll_trackers.remove(&view.node.id);
            self.canvas_surfaces.remove(&view.node.id);
        }
    }

    fn cache_virtual_row(&mut self, list: u64, item: u64, cached: VirtualCached) {
        assert!(
            !self.virtual_row_owners.contains_key(&item),
            "virtual row already cached"
        );
        self.virtual_row_owners.insert(item, list);
        let summary = self.virtual_lists.entry(list).or_default();
        summary.rows.insert(item);
        summary.entities += cached.entities;
        self.virtual_views.insert((list, item), cached);
    }

    fn uncache_virtual_row(&mut self, list: u64, item: u64) -> Option<VirtualCached> {
        let cached = self.virtual_views.remove(&(list, item))?;
        self.virtual_row_owners.remove(&item);
        let summary = self
            .virtual_lists
            .get_mut(&list)
            .expect("cached virtual list");
        summary.rows.remove(&item);
        summary.entities = summary
            .entities
            .checked_sub(cached.entities)
            .expect("cached virtual list count underflow");
        if summary.rows.is_empty() {
            self.virtual_lists.remove(&list);
        }
        Some(cached)
    }

    fn virtual_range(
        &mut self,
        list_id: u64,
        range: std::ops::Range<usize>,
        row_height: u32,
        row_gap: u32,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let list = self.graph.node(list_id).expect("virtual list is missing");
        let wanted = range
            .filter_map(|index| list.children.get(index).copied())
            .collect::<Vec<_>>();
        let wanted_set = wanted
            .iter()
            .copied()
            .collect::<std::collections::HashSet<_>>();
        let evicted = self
            .virtual_lists
            .get(&list_id)
            .into_iter()
            .flat_map(|summary| summary.rows.iter().copied())
            .filter(|item| !wanted_set.contains(item))
            .collect::<Vec<_>>();
        let mut recycled = 0;
        for item in evicted {
            let cached = self
                .uncache_virtual_row(list_id, item)
                .expect("virtual cache disappeared");
            recycled += cached.entities;
            self.forget_virtual_subtree(cached.view, cx);
        }
        let abandoned = self
            .preserved_virtual
            .iter()
            .copied()
            .filter(|id| {
                let mut child = *id;
                while let Some((parent, _)) = self.graph.parent(child) {
                    if parent == list_id {
                        return !wanted_set.contains(&child);
                    }
                    child = parent;
                }
                false
            })
            .collect::<Vec<_>>();
        for id in abandoned {
            if let Some(cached) = self.virtual_entities.get(&id).cloned() {
                recycled += cached.entities;
                self.forget_virtual_subtree(cached.view, cx);
            }
        }
        let construction_start = self.virtual_constructions;
        for item in &wanted {
            if !self.virtual_views.contains_key(&(list_id, *item)) {
                let (view, entities) = self.build_virtual_node(*item, cx);
                self.cache_virtual_row(list_id, *item, VirtualCached { view, entities });
            }
        }
        let live_entities = self
            .virtual_lists
            .get(&list_id)
            .map_or(0, |summary| summary.entities);
        observatory::virtual_list_frame(
            list_id,
            wanted.len() as u64,
            self.virtual_constructions - construction_start,
            recycled,
            live_entities,
        );
        wanted
            .into_iter()
            .map(|id| {
                let view = self.virtual_views[&(list_id, id)].view.clone();
                let key = match self.graph.node(id).map(|node| &node.kind) {
                    Some(NodeKind::VirtualItem { key }) => *key,
                    _ => panic!("virtual list child is not an item"),
                };
                // The gap is held clear inside the row's own height, which is
                // what keeps a list's scroll arithmetic exactly row_height per
                // row while its rows still read as separate surfaces.
                div()
                    .id(("virtual-row", key))
                    .h(px(row_height as f32))
                    .pb(px(row_gap.min(row_height.saturating_sub(1)) as f32))
                    .child(view)
                    .into_any_element()
            })
            .collect()
    }
}

/// Bring an identity map up to date with the patch just applied.
///
/// A replacement changes identities only inside the replaced subtree, and among
/// its parent's children where a changed name shifts an occurrence. Recomputing
/// the whole graph instead would make a small update in a large application pay
/// for every node it did not touch, on every event.
fn refresh_identities(
    graph: &MountedGraph,
    applied: &bridge::GraphApply,
    identities: &mut HashMap<u64, ElementIdentity>,
) {
    for id in &applied.removed_ids {
        identities.remove(id);
    }
    let retained = applied
        .retained_roots
        .iter()
        .copied()
        .collect::<std::collections::HashSet<_>>();
    let refresh = |root: u64,
                   own: bridge::IdentitySegment,
                   parent: &[bridge::IdentitySegment],
                   identities: &mut HashMap<u64, ElementIdentity>| {
        let mut pending = vec![(root, own, parent.to_vec())];
        while let Some((id, own, parent)) = pending.pop() {
            if retained.contains(&id) && identities.contains_key(&id) {
                continue;
            }
            let mut identity = if matches!(own, bridge::IdentitySegment::Boundary { .. }) {
                vec![]
            } else {
                parent
            };
            identity.push(own);
            identities.insert(id, identity.clone());
            pending.extend(
                graph
                    .child_segments(id)
                    .into_iter()
                    .map(|(child, own)| (child, own, identity.clone())),
            );
        }
    };
    let parent_identity = match (applied.retired_root, applied.parent) {
        (false, Some((parent, _))) => identities.get(&parent).cloned(),
        _ => None,
    };
    let (Some((parent, _)), Some(parent_identity)) = (applied.parent, parent_identity) else {
        if let Some(root) = applied.root.and_then(|id| graph.node(id)) {
            refresh(
                root.id,
                bridge::IdentitySegment::of(root, 0, 0),
                &[],
                identities,
            );
        }
        return;
    };
    if let Some(root) = applied.root
        && let Some(segment @ bridge::IdentitySegment::Boundary { .. }) = graph.cached_segment(root)
    {
        // A component token fixes this segment independently of its siblings.
        // Replacing the boundary cannot renumber any sibling occurrence.
        refresh(root, segment.clone(), &parent_identity, identities);
        return;
    }
    let staged = applied
        .staged_ids
        .iter()
        .copied()
        .collect::<std::collections::HashSet<_>>();
    for (child, segment) in graph.child_segments(parent) {
        let settled = !staged.contains(&child)
            && identities.get(&child).and_then(|identity| identity.last()) == Some(&segment);
        if !settled {
            refresh(child, segment, &parent_identity, identities);
        }
    }
}

fn elapsed_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}

impl Render for Runtime {
    fn render(&mut self, window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        if GPUI_SMOKE.load(Ordering::Relaxed) {
            GPUI_SMOKE_RENDERS.fetch_add(1, Ordering::Relaxed);
        }
        watchdog::milestone(watchdog::Milestone::FirstRender);
        // What this frame is drawing, so a painted read can tell whether the
        // window has caught up with the graph it is being asked about.
        probe::begin_frame(self.generation);
        if let Some(target) = self.focus_after_render.take()
            && let Some(handle) = self.focus_handles.get(&target)
        {
            handle.focus(window);
        }
        let focused_now = self
            .focus_handles
            .iter()
            .find(|(_, handle)| handle.is_focused(window))
            .map(|(id, _)| *id);
        self.focused_position = focused_now.and_then(|id| {
            self.graph
                .focus_order()
                .into_iter()
                .position(|other| other == id)
        });
        self.focused_identity = focused_now.and_then(|id| {
            self.graph
                .node(id)
                .and_then(|_| self.identities.get(&id).cloned())
                .map(|identity| (id, identity))
        });
        // The application's tree hangs below one `FrameSpans`, the element that
        // performs and therefore measures the host's layout-request, prepaint,
        // and paint work for the whole subtree.
        frame_spans::FrameSpans::new(
            div()
                .id("roc-gui-root")
                .on_action(|_: &FocusNext, window, _| window.focus_next())
                .on_action(|_: &FocusPrevious, window, _| window.focus_prev())
                .size_full()
                .flex()
                .items_center()
                .justify_center()
                .bg(rgb(window_ground().unwrap_or(0x16252c)))
                .text_color(rgb(window_ink().unwrap_or(0xeeeeea)))
                .text_lg()
                .children(self.root.iter().cloned().map(AnyView::from)),
        )
    }
}

struct HostArgs {
    app_name: String,
    help: bool,
    host_smoke: bool,
    host_gpui_smoke: bool,
    spec_path: Option<PathBuf>,
    window_spec_path: Option<PathBuf>,
    window_report: Option<PathBuf>,
    window_shot_dir: Option<PathBuf>,
    window_timeout_ms: u32,
    window_require_shots: bool,
    describe_specs: Vec<PathBuf>,
    stats_record: bool,
    stats_output: Option<PathBuf>,
    stats_detail: observatory::Detail,
    stats_buffer_mib: usize,
    stats_max_mib: u64,
    stats_job_count: usize,
    cap_dir: Option<PathBuf>,
    cap_dir_canceled: bool,
    cap_http_origin: Option<String>,
    cap_app_data: Option<PathBuf>,
    cap_assets: Option<PathBuf>,
    cap_clipboard_system: bool,
    cap_clipboard_fixture: bool,
    cap_tcp: Option<std::net::SocketAddr>,
    cap_process: Option<process::GrantedProfile>,
    cap_audio: audio::Grant,
    cap_device: Option<device::GrantedDevice>,
    cap_system_monitor: system_monitor::Grant,
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
        host_gpui_smoke: false,
        spec_path: None,
        window_spec_path: None,
        window_report: None,
        window_shot_dir: None,
        window_timeout_ms: 15_000,
        window_require_shots: true,
        describe_specs: Vec::new(),
        stats_record: false,
        stats_output: None,
        stats_detail: observatory::Detail::Summary,
        stats_buffer_mib: 4,
        stats_max_mib: 4096,
        stats_job_count: 1,
        cap_dir: None,
        cap_dir_canceled: false,
        cap_http_origin: None,
        cap_app_data: None,
        cap_assets: None,
        cap_clipboard_system: false,
        cap_clipboard_fixture: false,
        cap_tcp: None,
        cap_process: None,
        cap_audio: audio::Grant::System,
        cap_device: None,
        cap_system_monitor: system_monitor::Grant::Denied,
    };
    let mut pending = arguments.peekable();
    while let Some(argument) = pending.next() {
        if argument == "--host-help" {
            parsed.help = true;
        } else if argument == "--host-smoke" {
            parsed.host_smoke = true;
        } else if argument == "--host-gpui-smoke" {
            parsed.host_gpui_smoke = true;
        } else if argument == "--host-stats-record" {
            parsed.stats_record = true;
        } else if argument == "--host-run-spec" {
            let path = pending
                .next()
                .ok_or_else(|| "--host-run-spec requires a .scm path".to_string())?;
            parsed.spec_path = Some(path.into());
        } else if let Some(path) = argument.strip_prefix("--host-run-spec=") {
            parsed.spec_path = Some(path.into());
        } else if argument == "--host-run-window-spec" {
            let path = pending
                .next()
                .ok_or_else(|| "--host-run-window-spec requires a .scm path".to_string())?;
            parsed.window_spec_path = Some(path.into());
        } else if let Some(path) = argument.strip_prefix("--host-run-window-spec=") {
            parsed.window_spec_path = Some(path.into());
        } else if argument == "--host-window-report" {
            parsed.window_report = Some(
                pending
                    .next()
                    .ok_or_else(|| "--host-window-report requires a path".to_string())?
                    .into(),
            );
        } else if let Some(path) = argument.strip_prefix("--host-window-report=") {
            parsed.window_report = Some(path.into());
        } else if argument == "--host-window-shot-dir" {
            parsed.window_shot_dir = Some(
                pending
                    .next()
                    .ok_or_else(|| "--host-window-shot-dir requires a directory path".to_string())?
                    .into(),
            );
        } else if let Some(path) = argument.strip_prefix("--host-window-shot-dir=") {
            parsed.window_shot_dir = Some(path.into());
        } else if argument == "--host-window-timeout-ms" {
            let value = pending
                .next()
                .ok_or_else(|| "--host-window-timeout-ms requires 1000..=600000".to_string())?;
            parsed.window_timeout_ms = value
                .parse()
                .ok()
                .filter(|value| (1_000..=600_000).contains(value))
                .ok_or_else(|| "--host-window-timeout-ms requires 1000..=600000".to_string())?;
        } else if let Some(value) = argument.strip_prefix("--host-window-timeout-ms=") {
            parsed.window_timeout_ms = value
                .parse()
                .ok()
                .filter(|value| (1_000..=600_000).contains(value))
                .ok_or_else(|| "--host-window-timeout-ms requires 1000..=600000".to_string())?;
        } else if argument == "--host-window-allow-missing-shots" {
            parsed.window_require_shots = false;
        } else if argument == "--host-describe-specs" {
            // Consumes the rest: describing a specification is pure parsing,
            // so one process can answer for the whole suite.
            parsed
                .describe_specs
                .extend(pending.by_ref().map(PathBuf::from));
            if parsed.describe_specs.is_empty() {
                return Err("--host-describe-specs requires at least one .scm path".into());
            }
        } else if argument == "--host-cap-dir" {
            parsed.cap_dir = Some(
                pending
                    .next()
                    .ok_or_else(|| "--host-cap-dir requires a directory path".to_string())?
                    .into(),
            );
        } else if let Some(path) = argument.strip_prefix("--host-cap-dir=") {
            parsed.cap_dir = Some(path.into());
        } else if argument == "--host-cap-dir-canceled" {
            parsed.cap_dir_canceled = true;
        } else if argument == "--host-cap-http-origin" {
            parsed.cap_http_origin = Some(
                pending
                    .next()
                    .ok_or_else(|| "--host-cap-http-origin requires an origin".to_string())?,
            );
        } else if let Some(origin) = argument.strip_prefix("--host-cap-http-origin=") {
            parsed.cap_http_origin = Some(origin.to_owned());
        } else if argument == "--host-cap-app-data" {
            parsed.cap_app_data = Some(
                pending
                    .next()
                    .ok_or_else(|| "--host-cap-app-data requires a directory path".to_string())?
                    .into(),
            );
        } else if let Some(path) = argument.strip_prefix("--host-cap-app-data=") {
            parsed.cap_app_data = Some(path.into());
        } else if argument == "--host-cap-assets" {
            parsed.cap_assets = Some(
                pending
                    .next()
                    .ok_or_else(|| "--host-cap-assets requires a directory path".to_string())?
                    .into(),
            );
        } else if let Some(path) = argument.strip_prefix("--host-cap-assets=") {
            parsed.cap_assets = Some(path.into());
        } else if argument == "--host-cap-clipboard" {
            parsed.cap_clipboard_system = true;
        } else if argument == "--host-cap-audio-null" {
            parsed.cap_audio = audio::Grant::Null;
        } else if argument == "--host-cap-clipboard-fixture" {
            parsed.cap_clipboard_fixture = true;
        } else if argument == "--host-cap-tcp" {
            let endpoint = pending
                .next()
                .ok_or_else(|| "--host-cap-tcp requires an IP:PORT endpoint".to_string())?;
            parsed.cap_tcp =
                Some(endpoint.parse().map_err(|_| {
                    "--host-cap-tcp requires a numeric IP:PORT endpoint".to_string()
                })?);
        } else if let Some(endpoint) = argument.strip_prefix("--host-cap-tcp=") {
            parsed.cap_tcp =
                Some(endpoint.parse().map_err(|_| {
                    "--host-cap-tcp requires a numeric IP:PORT endpoint".to_string()
                })?);
        } else if argument == "--host-cap-process" {
            parsed.cap_process = Some(parse_process_profile(&pending.next().ok_or_else(
                || "--host-cap-process requires local-shell or test-program".to_string(),
            )?)?);
        } else if let Some(profile) = argument.strip_prefix("--host-cap-process=") {
            parsed.cap_process = Some(parse_process_profile(profile)?);
        } else if argument == "--host-cap-device" {
            parsed.cap_device = Some(parse_device_grant(&pending.next().ok_or_else(|| {
                "--host-cap-device requires virtual[:COUNT] or VID:PID".to_string()
            })?)?);
        } else if let Some(value) = argument.strip_prefix("--host-cap-device=") {
            parsed.cap_device = Some(parse_device_grant(value)?);
        } else if argument == "--host-cap-system-monitor" {
            parsed.cap_system_monitor = system_monitor::Grant::Real;
        } else if argument == "--host-cap-system-monitor-fixture" {
            parsed.cap_system_monitor = parse_system_monitor_fixture(&pending.next().ok_or_else(|| "--host-cap-system-monitor-fixture requires standard, unavailable, or processes:N".to_string())?)?;
        } else if let Some(value) = argument.strip_prefix("--host-cap-system-monitor-fixture=") {
            parsed.cap_system_monitor = parse_system_monitor_fixture(value)?;
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
    if usize::from(parsed.host_smoke)
        + usize::from(parsed.host_gpui_smoke)
        + usize::from(parsed.spec_path.is_some())
        + usize::from(parsed.window_spec_path.is_some())
        + usize::from(!parsed.describe_specs.is_empty())
        > 1
    {
        return Err(
            "host smoke modes, --host-run-spec, --host-run-window-spec, and \
             --host-describe-specs are mutually exclusive"
                .into(),
        );
    }
    if parsed.window_spec_path.is_none()
        && (parsed.window_report.is_some()
            || parsed.window_shot_dir.is_some()
            || !parsed.window_require_shots)
    {
        return Err("--host-window-* options require --host-run-window-spec".into());
    }
    Ok(parsed)
}

fn parse_process_profile(value: &str) -> Result<process::GrantedProfile, String> {
    match value {
        "local-shell" => Ok(process::GrantedProfile::LocalShell),
        "test-program" => Ok(process::GrantedProfile::TestProgram),
        _ => Err("process capability must be local-shell or test-program".into()),
    }
}

fn parse_device_grant(value: &str) -> Result<device::GrantedDevice, String> {
    if value == "virtual" {
        return Ok(device::GrantedDevice::Virtual { controls: 12 });
    }
    if let Some(count) = value.strip_prefix("virtual:") {
        let controls = count
            .parse::<u16>()
            .map_err(|_| "virtual device control count must be an integer".to_string())?;
        if !(1..=1000).contains(&controls) {
            return Err("virtual device control count must be 1..1000".into());
        }
        return Ok(device::GrantedDevice::Virtual { controls });
    }
    let Some((vendor, product)) = value.split_once(':') else {
        return Err("device capability must be virtual[:COUNT] or hexadecimal VID:PID".into());
    };
    let vendor_id = u16::from_str_radix(vendor, 16)
        .map_err(|_| "device vendor id must be hexadecimal".to_string())?;
    let product_id = u16::from_str_radix(product, 16)
        .map_err(|_| "device product id must be hexadecimal".to_string())?;
    Ok(device::GrantedDevice::Hid {
        vendor_id,
        product_id,
    })
}

fn parse_system_monitor_fixture(value: &str) -> Result<system_monitor::Grant, String> {
    if value == "standard" {
        return Ok(system_monitor::Grant::Virtual {
            processes: 24,
            unavailable: false,
        });
    }
    if value == "unavailable" {
        return Ok(system_monitor::Grant::Virtual {
            processes: 0,
            unavailable: true,
        });
    }
    if let Some(count) = value.strip_prefix("processes:") {
        let processes = count
            .parse::<usize>()
            .map_err(|_| "system monitor process count must be an integer".to_string())?;
        if !(1..=10_000).contains(&processes) {
            return Err("system monitor process count must be 1..10000".into());
        }
        return Ok(system_monitor::Grant::Virtual {
            processes,
            unavailable: false,
        });
    }
    Err("system monitor fixture must be standard, unavailable, or processes:N".into())
}

/// Describe one specification as JSON: the runner it needs and the capabilities
/// it declares.
///
/// The host owns the `.scm` vocabulary, so it is the only parser. A spec runner
/// asks this mode what a case needs and turns the answer into the very flags an
/// interactive grant would use; nothing infers a capability from a file name.
fn describe_spec(path: &std::path::Path) -> Result<String, String> {
    let text = std::fs::read_to_string(path).map_err(|error| error.to_string())?;
    let case = spec::parse(&text).map_err(|error| error.to_string())?;
    let runner = if spec::check_runner(&case, spec::Runner::Semantic).is_ok() {
        "semantic"
    } else {
        "window"
    };
    // Specifications live in `specs/` beside the application they exercise.
    let application = path
        .parent()
        .and_then(std::path::Path::parent)
        .ok_or_else(|| "specification has no application directory".to_string())?;

    let mut flags: Vec<String> = Vec::new();
    let mut app_data_seed: Option<String> = None;
    let mut servers: Vec<(String, u32)> = Vec::new();
    for grant in &case.grants {
        let resolved = match grant.path() {
            Some(relative) => Some(resolve_grant_path(application, relative)?),
            None => None,
        };
        match grant {
            spec::Grant::Directory(_) => {
                let path = resolved.expect("directory grant names a path");
                if !path.is_dir() {
                    return Err(format!(
                        "directory grant does not exist: {}",
                        path.display()
                    ));
                }
                flags.push("--host-cap-dir".into());
                flags.push(path.display().to_string());
            }
            spec::Grant::DirectoryCanceled => flags.push("--host-cap-dir-canceled".into()),
            spec::Grant::AppData(_) => {
                let path = resolved.expect("app-data grant names a path");
                if !path.is_dir() {
                    return Err(format!("app-data grant does not exist: {}", path.display()));
                }
                app_data_seed = Some(path.display().to_string());
            }
            spec::Grant::Assets(_) => {
                let path = resolved.expect("assets grant names a path");
                if !path.is_dir() {
                    return Err(format!("assets grant does not exist: {}", path.display()));
                }
                flags.push("--host-cap-assets".into());
                flags.push(path.display().to_string());
            }
            spec::Grant::Clipboard { system } => flags.push(
                if *system {
                    "--host-cap-clipboard"
                } else {
                    "--host-cap-clipboard-fixture"
                }
                .into(),
            ),
            spec::Grant::AudioNull => flags.push("--host-cap-audio-null".into()),
            spec::Grant::HttpOrigin(origin) => {
                flags.push("--host-cap-http-origin".into());
                flags.push(origin.clone());
            }
            spec::Grant::Tcp(endpoint) => {
                flags.push("--host-cap-tcp".into());
                flags.push(endpoint.clone());
            }
            spec::Grant::Process(profile) => {
                flags.push("--host-cap-process".into());
                flags.push(profile.clone());
            }
            spec::Grant::Device(identifier) => {
                flags.push("--host-cap-device".into());
                flags.push(identifier.clone());
            }
            spec::Grant::SystemMonitor(kind) => {
                flags.push("--host-cap-system-monitor-fixture".into());
                flags.push(kind.clone());
            }
            spec::Grant::Server { port, .. } => {
                let path = resolved.expect("server grant names a path");
                if !path.is_file() {
                    return Err(format!("server grant does not exist: {}", path.display()));
                }
                servers.push((path.display().to_string(), *port));
            }
        }
    }

    let mut json = String::from("{\"path\":");
    json.push_str(&json_string(&path.display().to_string()));
    json.push_str(",\"runner\":");
    json.push_str(&json_string(runner));
    json.push_str(",\"flags\":[");
    for (index, flag) in flags.iter().enumerate() {
        if index > 0 {
            json.push(',');
        }
        json.push_str(&json_string(flag));
    }
    json.push_str("],\"app_data_seed\":");
    match &app_data_seed {
        Some(seed) => json.push_str(&json_string(seed)),
        None => json.push_str("null"),
    }
    json.push_str(",\"servers\":[");
    for (index, (script, port)) in servers.iter().enumerate() {
        if index > 0 {
            json.push(',');
        }
        json.push_str("{\"script\":");
        json.push_str(&json_string(script));
        json.push_str(&format!(",\"port\":{port}}}"));
    }
    json.push_str("]}");
    Ok(json)
}

/// Resolve one specification-supplied path against the application directory.
///
/// A path that leaves the application directory is refused here, before it can
/// reach a capability. Both sides are canonicalized, so a symbolic link cannot
/// step outside what the textual path promised.
fn resolve_grant_path(application: &std::path::Path, relative: &str) -> Result<PathBuf, String> {
    let root = application
        .canonicalize()
        .map_err(|error| format!("cannot resolve application directory: {error}"))?;
    let candidate = root.join(relative);
    let resolved = candidate
        .canonicalize()
        .map_err(|error| format!("cannot resolve grant path {relative}: {error}"))?;
    if !resolved.starts_with(&root) {
        return Err(format!(
            "grant path {relative} leaves the application directory"
        ));
    }
    Ok(resolved)
}

fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            value if (value as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", value as u32)),
            value => out.push(value),
        }
    }
    out.push('"');
    out
}

fn print_host_help(app_name: &str) {
    println!(
        "Usage: {app_name} [HOST OPTIONS]\n\
         \n\
         Host options:\n\
           --host-help                         Show this help and exit\n\
           --host-cap-dir PATH                 Grant read access to one directory\n\
           --host-cap-dir-canceled             Answer the directory chooser with a cancellation\n\
           --host-cap-http-origin ORIGIN       Grant HTTP access to one origin\n\
           --host-cap-app-data PATH            Grant private application-data storage\n\
           --host-cap-assets PATH              Provision the application content directory\n\
           --host-cap-clipboard                Grant system text clipboard access\n\
           --host-cap-clipboard-fixture        Grant a specification-driven clipboard source\n\
           --host-cap-tcp IP:PORT              Grant access to one TCP endpoint\n\
           --host-cap-process PROFILE         Grant local-shell or test-program PTY profile\n\
		   --host-cap-device DEVICE            Grant one virtual or VID:PID HID device\n\
		   --host-cap-system-monitor           Grant read-only local system sampling\n\
           --host-run-spec PATH                Run one semantic .scm specification\n\
           --host-run-window-spec PATH         Run one .scm specification against the real window\n\
           --host-window-report=PATH           Write the window run's JSON report here\n\
           --host-window-shot-dir=PATH         Write window screenshots into this directory\n\
           --host-window-timeout-ms=N          Per-step window deadline (1000..600000)\n\
           --host-window-allow-missing-shots   Report unavailable screenshots instead of failing\n\
           --host-describe-specs PATH...       Print each .scm's runner and grants as JSON\n\
           --host-smoke                        Run the built-in headless smoke check\n\
          --host-gpui-smoke                   Open, render, and close a real GPUI window\n\
           --host-stats-record                 Record an observatory capture\n\
           --host-stats-output=PATH            Set the capture output path\n\
           --host-stats-detail=summary|full    Select capture detail\n\
           --host-stats-buffer-mib=N           Set recorder buffer capacity\n\
           --host-stats-max-mib=N              Set maximum capture size\n\
           --host-stats-job-count=N            Record concurrent runner job count\n\
         \n\
         Options are passed through Roc after `--`, for example:\n\
           roc app.roc -- --host-help\n\
           roc app.roc -- --host-cap-dir ./documents\n\
           roc app.roc -- --host-cap-tcp 127.0.0.1:6379"
    );
}

/// Tear the host down and exit with `code`.
///
/// `cx.quit()` reaches `[NSApp terminate:]` on macOS, which ends the process
/// without unwinding back to `main`, so a windowed run cannot report its status
/// by returning. It must finalize here instead.
pub(crate) fn finish_and_exit(code: i32) -> ! {
    let outcome = if code == 0 { "success" } else { "failure" };
    if observatory::active()
        && let Err(message) = observatory::finish(outcome)
    {
        eprintln!("roc-gui stats error: {message}");
    }
    clear_bridge();
    set_roc_host(core::ptr::null_mut());
    std::process::exit(code)
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
            if cfg!(target_os = "macos") {
                "gpui-macos"
            } else if cfg!(target_os = "windows") {
                "gpui-windows"
            } else {
                "gpui-wayland"
            }
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

/// Process entry point for the linked Roc application.
///
/// # Safety
///
/// Must only be called once, by the C runtime startup code, on the main thread
/// before any other host function runs. Its allocator context lives for the
/// process lifetime so a retired session's workers can release owned results.
/// UI dispatch authority is retired separately before returning. The C
/// arguments are ignored; arguments are read through `std::env` instead.
#[unsafe(no_mangle)]
#[cfg(not(test))]
pub unsafe extern "C" fn main(_argc: i32, _argv: *const *const i8) -> i32 {
    let host = Box::leak(Box::new(make_counted_roc_host(core::ptr::null_mut())));
    set_roc_host(host);

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
    if !args.describe_specs.is_empty() {
        let mut status = 0;
        for path in &args.describe_specs {
            match describe_spec(path) {
                Ok(line) => println!("{line}"),
                Err(message) => {
                    eprintln!("{}: {message}", path.display());
                    status = 2;
                }
            }
        }
        set_roc_host(core::ptr::null_mut());
        return status;
    }

    let parsed_spec = match args.spec_path.as_ref() {
        Some(path) => match std::fs::read(path) {
            Ok(source) => match std::str::from_utf8(&source) {
                Ok(text) => match spec::parse(text) {
                    Ok(case) => {
                        if let Err(message) = spec::check_runner(&case, spec::Runner::Semantic) {
                            eprintln!("{}: {message}", path.display());
                            set_roc_host(core::ptr::null_mut());
                            return 2;
                        }
                        Some((case, observatory::stable_hash(&source)))
                    }
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
    // A specification never opens an interactive chooser: a window case drives
    // the production window, so an operating-system panel would wait for a
    // person who is not there.
    if let Err(message) = files::configure(
        args.cap_dir.as_deref(),
        args.spec_path.is_none() && args.window_spec_path.is_none() && !args.host_smoke,
        args.cap_dir_canceled,
    ) {
        eprintln!("roc-gui capability error: {message}");
        set_roc_host(core::ptr::null_mut());
        return 2;
    }
    if let Err(message) = http::configure(args.cap_http_origin.as_deref()) {
        eprintln!("roc-gui capability error: {message}");
        set_roc_host(core::ptr::null_mut());
        return 2;
    }
    if let Err(message) = app_data::configure(args.cap_app_data.as_deref()) {
        eprintln!("roc-gui application-data capability error: {message}");
        set_roc_host(core::ptr::null_mut());
        return 2;
    }
    assets::configure(args.cap_assets.as_deref());
    if let Err(message) =
        clipboard::configure(args.cap_clipboard_system, args.cap_clipboard_fixture)
    {
        eprintln!("roc-gui clipboard capability error: {message}");
        set_roc_host(core::ptr::null_mut());
        return 2;
    }
    tcp::configure(args.cap_tcp);
    process::configure(args.cap_process);
    sqlite::configure();
    audio::configure(args.cap_audio);
    device::configure(args.cap_device);
    system_monitor::configure(args.cap_system_monitor);
    let window_spec = match args.window_spec_path.as_ref() {
        Some(path) => match std::fs::read_to_string(path) {
            Ok(text) => match spec::parse(&text) {
                Ok(case) => {
                    if let Err(message) = spec::check_runner(&case, spec::Runner::Window) {
                        eprintln!("{}: {message}", path.display());
                        set_roc_host(core::ptr::null_mut());
                        return 2;
                    }
                    Some(case)
                }
                Err(error) => {
                    eprintln!("{}: {error}", path.display());
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
    observatory::begin_component_work();
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
    let window_report = args
        .window_report
        .clone()
        .unwrap_or_else(|| PathBuf::from("report.json"));
    let window_shot_dir = args
        .window_shot_dir
        .clone()
        .unwrap_or_else(|| PathBuf::from("."));
    let window_timeout_ms = args.window_timeout_ms;
    let window_require_shots = args.window_require_shots;
    let window_config = WINDOW_CONFIG.with(|config| config.borrow().clone());
    GPUI_SMOKE.store(args.host_gpui_smoke, Ordering::Relaxed);
    GPUI_SMOKE_RENDERS.store(0, Ordering::Relaxed);
    let gpui_smoke = args.host_gpui_smoke;

    if gpui_smoke {
        watchdog::arm(Duration::from_secs(10));
    }
    if window_spec.is_some() {
        probe::enable();
        // Generous relative to the per-step deadline: this only catches a host
        // that never reaches its own reporting, not a slow specification.
        watchdog::arm(
            Duration::from_millis(u64::from(args.window_timeout_ms)) + Duration::from_secs(30),
        );
    }

    Application::new().run(move |cx| {
        watchdog::milestone(watchdog::Milestone::AppRunEntered);
        input::bind_keys(cx);
        cx.bind_keys([
            KeyBinding::new("tab", FocusNext, None),
            KeyBinding::new("shift-tab", FocusPrevious, None),
            KeyBinding::new("enter", ActivateEnter, None),
            KeyBinding::new("escape", ActivateEscape, None),
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
        let window = cx
            .open_window(
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
        watchdog::milestone(watchdog::Milestone::WindowOpened);
        cx.activate(true);
        // `Platform::quit` on macOS terminates the process from inside
        // `Application::run`, which never returns, so the tail of this function
        // cannot be where a windowed capture is finalized. GPUI runs quit
        // observers synchronously before terminating; finalizing here is what
        // makes a window capture readable at all. `finish` is idempotent, so
        // the tail below remains correct on platforms whose run does return.
        cx.on_app_quit(|_| {
            if observatory::active() {
                observatory::run_end(1, "pass", observatory::now_ns(), None);
                if let Err(message) = observatory::finish("success") {
                    eprintln!("roc-gui stats error: {message}");
                }
            }
            // Some platforms terminate inside GPUI's quit path. Retire the
            // session here as well as in the returning run-loop tail; late
            // workers retain only the process-lived allocator context.
            clear_bridge();
            set_roc_host(core::ptr::null_mut());
            async {}
        })
        .detach();
        if let Some(case) = window_spec {
            window_runner::spawn(
                case,
                window,
                window_runner::Options {
                    report_path: window_report,
                    shot_dir: window_shot_dir,
                    timeout: Duration::from_millis(u64::from(window_timeout_ms)),
                    require_shots: window_require_shots,
                },
                cx,
            );
        }
        if gpui_smoke {
            cx.spawn(async move |cx| {
                watchdog::milestone(watchdog::Milestone::DriverStarted);
                cx.background_executor().timer(Duration::from_secs(2)).await;
                let renders = window
                    .update(cx, |_, _, _| GPUI_SMOKE_RENDERS.load(Ordering::Relaxed))
                    .expect("GPUI smoke window closed before validation");
                assert!(renders > 0, "no GPUI views rendered");
                eprintln!("PASS: GPUI mounted and rendered {renders} frame(s)");
                watchdog::disarm();
                cx.update(|cx| cx.quit()).unwrap();
            })
            .detach();
        }
    });

    if args.host_gpui_smoke {
        let renders = GPUI_SMOKE_RENDERS.load(Ordering::Relaxed);
        if renders == 0 {
            eprintln!("FAIL: GPUI window closed before the mounted graph rendered");
            clear_bridge();
            set_roc_host(core::ptr::null_mut());
            return 1;
        }
    }

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
    use super::{ActivateEnter, InitialMount, Runtime, install_test_dispatcher};
    use super::{
        CanvasPrimitive, CanvasPrimitiveKind, WindowConfig, canvas_target, counted_roc_alloc,
        counted_roc_dealloc, counted_roc_realloc, make_counted_roc_host, validate_window_config,
    };
    use crate::bridge::{Length, MountedGraph, Node, NodeKind, Patch, Style};
    use crate::observatory;
    use gpui::{
        Bounds, Modifiers, MouseButton, Pixels, Point, TestAppContext, VisualTestContext,
        WindowBounds, WindowOptions, point, px, size,
    };
    use std::cell::RefCell;
    use std::rc::Rc;
    use std::time::Instant;

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

    /// Use the generated callable allocator and final-drop ABI, without
    /// inventing a second representation for the transaction ownership tests.
    fn counted_callable(
        dropped: &std::sync::Arc<std::sync::atomic::AtomicU64>,
    ) -> crate::roc_platform_abi::RocErasedCallable {
        use crate::roc_platform_abi::{
            RocHost, roc_erased_callable_allocate, roc_erased_callable_capture_ptr,
        };
        use std::sync::{Arc, atomic::Ordering};
        extern "C" fn never_called(
            _: *mut RocHost,
            _: *mut u8,
            _: *const u8,
            _: *mut u8,
            _: *mut u8,
            _: *mut *const std::ffi::c_void,
        ) {
            unreachable!("a lifetime test invoked a Roc callable");
        }
        extern "C" fn on_drop(capture: *mut u8, _: *mut RocHost) {
            let counter = unsafe {
                Arc::from_raw(capture.cast::<*const std::sync::atomic::AtomicU64>().read())
            };
            counter.fetch_add(1, Ordering::Relaxed);
        }
        if super::ROC_HOST.load(Ordering::Acquire).is_null() {
            let host = Box::into_raw(Box::new(make_counted_roc_host(core::ptr::null_mut())));
            if super::ROC_HOST
                .compare_exchange(
                    core::ptr::null_mut(),
                    host,
                    Ordering::AcqRel,
                    Ordering::Acquire,
                )
                .is_err()
            {
                unsafe { drop(Box::from_raw(host)) };
            }
        }
        unsafe {
            let callable = roc_erased_callable_allocate(
                super::roc_host(),
                never_called,
                Some(on_drop),
                std::mem::size_of::<usize>(),
            );
            roc_erased_callable_capture_ptr(callable)
                .cast::<*const std::sync::atomic::AtomicU64>()
                .write(Arc::into_raw(dropped.clone()));
            callable
        }
    }

    #[test]
    fn rejected_transaction_releases_candidate_and_worker_but_preserves_session() {
        use std::sync::{
            Arc,
            atomic::{AtomicU64, Ordering},
        };
        let old_drops = Arc::new(AtomicU64::new(0));
        let next_drops = Arc::new(AtomicU64::new(0));
        let task_drops = Arc::new(AtomicU64::new(0));
        let old = counted_callable(&old_drops);
        super::BRIDGE.with(|bridge| bridge.borrow_mut().dispatcher = Some(old));
        super::roc_gui_set_dispatch(counted_callable(&next_drops));
        super::roc_gui_enqueue_task(0, counted_callable(&task_drops));

        super::reject_transaction();
        super::reject_transaction();

        assert_eq!(old_drops.load(Ordering::Relaxed), 0);
        assert_eq!(next_drops.load(Ordering::Relaxed), 1);
        assert_eq!(task_drops.load(Ordering::Relaxed), 1);
        let retained = super::BRIDGE.with(|bridge| bridge.borrow_mut().dispatcher.take());
        assert_eq!(retained, Some(old));
        unsafe { super::decref_erased_callable(old, super::roc_host()) };
        assert_eq!(old_drops.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn accepted_transaction_discards_a_worker_whose_owner_was_removed() {
        use std::sync::{
            Arc,
            atomic::{AtomicU64, Ordering},
        };
        let drops = Arc::new(AtomicU64::new(0));
        let mut graph = MountedGraph::default();
        let applied = graph.apply(Patch::NoChange).expect("empty accepted turn");
        super::roc_gui_enqueue_task(42, counted_callable(&drops));

        super::accept_transaction(&graph, &applied);

        assert_eq!(drops.load(Ordering::Relaxed), 1);
        super::STAGED_TURN.with(|turn| assert!(turn.borrow().jobs.is_empty()));
    }

    #[test]
    fn stale_epoch_completion_is_dropped_without_invoking_the_session() {
        use std::sync::{
            Arc,
            atomic::{AtomicU64, Ordering},
        };
        let drops = Arc::new(AtomicU64::new(0));
        let completion = super::TaskEnvelope {
            callable: counted_callable(&drops) as usize,
            owner: 0,
            epoch: super::TASK_EPOCH.load(Ordering::Acquire).wrapping_sub(1),
        };

        assert!(matches!(super::complete(completion), Patch::NoChange));

        assert_eq!(drops.load(Ordering::Relaxed), 1);
        super::STAGED_TURN.with(|turn| assert!(turn.borrow().dispatcher.is_none()));
        observatory::reject_component_work();
    }

    #[test]
    fn validates_initial_window_bounds() {
        assert!(
            validate_window_config(WindowConfig {
                title: "App".into(),
                width: 960,
                height: 640,
                ..WindowConfig::default()
            })
            .is_ok()
        );
        assert!(
            validate_window_config(WindowConfig {
                title: "App".into(),
                width: 239,
                height: 640,
                ..WindowConfig::default()
            })
            .is_err()
        );
        assert!(
            validate_window_config(WindowConfig {
                title: "App".into(),
                width: 960,
                height: 159,
                ..WindowConfig::default()
            })
            .is_err()
        );
    }

    #[test]
    fn canvas_hit_testing_prefers_the_topmost_precise_shape() {
        let primitive = |kind, key, x, y, width, height, x2, y2| CanvasPrimitive {
            kind,
            key,
            label: format!("shape {key}"),
            x,
            y,
            width,
            height,
            x2,
            y2,
            fill: Some(0xffffff),
            stroke: Some(0),
            stroke_width: 2,
            radius: 0,
        };
        let shapes = vec![
            primitive(CanvasPrimitiveKind::Rectangle, 1, 0, 0, 30, 30, 0, 0),
            primitive(CanvasPrimitiveKind::Ellipse, 2, 10, 10, 20, 20, 0, 0),
            primitive(CanvasPrimitiveKind::Line, 3, 0, 40, 0, 0, 40, 40),
        ];
        assert_eq!(canvas_target(&shapes, 20, 20), Some(2));
        assert_eq!(canvas_target(&shapes, 20, 0), Some(1));
        assert_eq!(canvas_target(&shapes, 20, 40), Some(3));
        assert_eq!(canvas_target(&shapes, 20, 34), None);
    }

    /// A transport tree: one full-bleed column holding one full-bleed button.
    /// Every node id is fresh, exactly as a whole-root `Action.update` rebuild
    /// produces, so consecutive trees share nothing but their semantic names.
    fn transport_tree(base: u64, caption: &str, label: &str) -> (u64, Vec<Node>) {
        let fill = Style {
            width: Length::Fill,
            height: Length::Fill,
            ..Style::default()
        };
        let column = base;
        let button = base + 1;
        (
            column,
            vec![
                Node {
                    id: column,
                    kind: NodeKind::Column {
                        label: "Transport".into(),
                        style: fill,
                    },
                    children: vec![button],
                },
                Node {
                    id: button,
                    kind: NodeKind::Button {
                        caption: caption.into(),
                        label: label.into(),
                        enabled: true,
                        style: fill,
                    },
                    children: vec![],
                },
            ],
        )
    }

    /// Identities are refreshed incrementally, because recomputing the whole
    /// graph on every event would make a small update in a large application
    /// pay for every node it did not touch. The incremental result has to be
    /// the result a full recompute would have given, including where a
    /// replacement shifts a repeated sibling name's occurrence.
    #[test]
    fn an_incremental_identity_refresh_matches_a_full_recompute() {
        let row = |id: u64, label: &str, children: Vec<u64>| Node {
            id,
            kind: NodeKind::Row {
                label: label.into(),
                style: Style::default(),
            },
            children,
        };
        let mut graph = MountedGraph::default();
        graph
            .apply(Patch::Mount {
                root: 1,
                nodes: vec![
                    row(1, "Shell", vec![2, 3, 4]),
                    row(2, "Slot", vec![]),
                    row(3, "Slot", vec![]),
                    row(4, "Footer", vec![]),
                ],
            })
            .expect("mount");
        let mut identities = graph.element_identities();

        // The replacement renames the first "Slot", which moves the second one
        // from the second occurrence of that name to the first.
        let applied = graph
            .apply(Patch::Replace {
                old_root: 2,
                root: 10,
                nodes: vec![row(10, "Header", vec![11]), row(11, "Title", vec![])],
            })
            .expect("replace");
        super::refresh_identities(&graph, &applied, &mut identities);
        assert_eq!(identities, graph.element_identities());
    }

    /// A one-row virtual list, so a press can be aimed at a control the list
    /// materialises rather than one the eager tree holds.
    fn queue_tree(base: u64) -> (u64, Vec<Node>) {
        let fill = Style {
            width: Length::Fill,
            height: Length::Fill,
            ..Style::default()
        };
        (
            base,
            vec![
                Node {
                    id: base,
                    kind: NodeKind::Column {
                        label: "Queue".into(),
                        style: fill,
                    },
                    children: vec![base + 1],
                },
                Node {
                    id: base + 1,
                    kind: NodeKind::VirtualList {
                        name: "Tracks".into(),
                        row_height: 40,
                        row_gap: 0,
                        style: Style::default(),
                    },
                    children: vec![base + 2],
                },
                Node {
                    id: base + 2,
                    kind: NodeKind::VirtualItem { key: 7 },
                    children: vec![base + 3],
                },
                Node {
                    id: base + 3,
                    kind: NodeKind::Button {
                        caption: "Track seven".into(),
                        label: "Play track seven".into(),
                        enabled: true,
                        style: fill,
                    },
                    children: vec![],
                },
            ],
        )
    }

    fn initial_mount(patch: Patch) -> InitialMount {
        InitialMount {
            patch,
            cycle_started: Instant::now(),
            roc_callback_ns: 0,
            roc_work: [observatory::RocWork::default(); observatory::ROC_WORK_KINDS],
            roc_work_valid: false,
        }
    }

    fn recording_dispatcher() -> Rc<RefCell<Vec<u64>>> {
        let clicks: Rc<RefCell<Vec<u64>>> = Rc::new(RefCell::new(Vec::new()));
        let recorded = clicks.clone();
        install_test_dispatcher(move |event_id| {
            recorded.borrow_mut().push(event_id);
            Patch::NoChange
        });
        clicks
    }

    #[gpui::test]
    fn retained_component_keeps_native_entity_and_pending_press(cx: &mut TestAppContext) {
        let clicks = recording_dispatcher();
        let (root, mut nodes) = transport_tree(1000, "Press", "Press");
        nodes[0].children = vec![1002];
        nodes.push(Node {
            id: 1002,
            kind: NodeKind::Boundary { instance: 7 },
            children: vec![1001],
        });
        let (runtime, cx) = cx
            .add_window_view(|_, cx| Runtime::new(initial_mount(Patch::Mount { root, nodes }), cx));
        cx.run_until_parked();
        let original = runtime.read_with(cx, |runtime, _| runtime.views[&1001].entity_id());
        let point = point(px(60.0), px(60.0));
        cx.simulate_mouse_move(point, None, Modifiers::none());
        cx.simulate_mouse_down(point, MouseButton::Left, Modifiers::none());
        runtime.update(cx, |runtime, cx| {
            let mut next = runtime.graph.node(1000).unwrap().clone();
            next.id = 2000;
            runtime.apply_unrecorded(
                Patch::ReplaceRetaining {
                    old_root: 1000,
                    root: 2000,
                    nodes: vec![next],
                    retained_roots: vec![1002],
                },
                cx,
            );
            assert_eq!(runtime.views[&1001].entity_id(), original);
        });
        cx.run_until_parked();
        cx.simulate_mouse_up(point, MouseButton::Left, Modifiers::none());
        assert_eq!(clicks.borrow().as_slice(), &[1001]);
    }

    #[gpui::test]
    fn a_local_virtual_component_update_keeps_its_row_and_press(cx: &mut TestAppContext) {
        let clicks = recording_dispatcher();
        let (root, mut nodes) = queue_tree(1000);
        nodes
            .iter_mut()
            .find(|node| node.id == 1002)
            .unwrap()
            .children = vec![1004];
        nodes.push(Node {
            id: 1004,
            kind: NodeKind::Boundary { instance: 50 },
            children: vec![1003],
        });
        let (runtime, cx) = cx
            .add_window_view(|_, cx| Runtime::new(initial_mount(Patch::Mount { root, nodes }), cx));
        cx.run_until_parked();
        let (row, button) = runtime.read_with(cx, |runtime, _| {
            (
                runtime.virtual_views[&(1001, 1002)].view.entity_id(),
                runtime.virtual_entities[&1003].view.entity_id(),
            )
        });
        let on_button = point(px(20.0), px(20.0));
        cx.simulate_mouse_move(on_button, None, Modifiers::none());
        cx.simulate_mouse_down(on_button, MouseButton::Left, Modifiers::none());
        runtime.update(cx, |runtime, cx| {
            let mut next_button = runtime.graph.node(1003).unwrap().clone();
            next_button.id = 1006;
            runtime.apply_unrecorded(
                Patch::Replace {
                    old_root: 1004,
                    root: 1005,
                    nodes: vec![
                        Node {
                            id: 1005,
                            kind: NodeKind::Boundary { instance: 50 },
                            children: vec![1006],
                        },
                        next_button,
                    ],
                },
                cx,
            );
            assert_eq!(runtime.virtual_views[&(1001, 1002)].view.entity_id(), row);
            assert_eq!(runtime.virtual_entities[&1006].view.entity_id(), button);
            assert_eq!(runtime.virtual_views[&(1001, 1002)].entities, 3);
            assert!(!runtime.virtual_entities.contains_key(&1003));
        });
        cx.run_until_parked();
        cx.simulate_mouse_up(on_button, MouseButton::Left, Modifiers::none());
        assert_eq!(clicks.borrow().as_slice(), &[1006]);
    }

    #[gpui::test]
    fn retiring_a_nested_virtual_list_does_not_subtract_its_rows_from_the_outer_cache(
        cx: &mut TestAppContext,
    ) {
        let (root, mut nodes) = queue_tree(1000);
        let button = nodes.pop().unwrap();
        nodes.extend([
            Node {
                id: 1003,
                kind: NodeKind::Boundary { instance: 50 },
                children: vec![1004],
            },
            Node {
                id: 1004,
                kind: NodeKind::VirtualList {
                    name: "Nested".into(),
                    row_height: 20,
                    row_gap: 0,
                    style: Style::default(),
                },
                children: vec![1005],
            },
            Node {
                id: 1005,
                kind: NodeKind::VirtualItem { key: 9 },
                children: vec![1006],
            },
            Node {
                id: 1006,
                ..button.clone()
            },
        ]);
        let (runtime, cx) = cx
            .add_window_view(|_, cx| Runtime::new(initial_mount(Patch::Mount { root, nodes }), cx));
        cx.run_until_parked();
        runtime.update(cx, |runtime, cx| {
            // Drive the production range callback for both mounted lists.
            drop(runtime.virtual_range(1001, 0..1, 40, 0, cx));
            drop(runtime.virtual_range(1004, 0..1, 20, 0, cx));
            assert_eq!(runtime.virtual_views[&(1001, 1002)].entities, 3);
            assert_eq!(runtime.virtual_views[&(1004, 1005)].entities, 2);
            runtime.apply_unrecorded(
                Patch::Replace {
                    old_root: 1003,
                    root: 2003,
                    nodes: vec![
                        Node {
                            id: 2003,
                            kind: NodeKind::Boundary { instance: 50 },
                            children: vec![2004],
                        },
                        Node { id: 2004, ..button },
                    ],
                },
                cx,
            );
            assert_eq!(runtime.virtual_views[&(1001, 1002)].entities, 3);
            assert_eq!(runtime.virtual_lists[&1001].entities, 3);
            assert!(!runtime.virtual_lists.contains_key(&1004));
            assert!(!runtime.virtual_row_owners.contains_key(&1005));
        });
    }

    #[gpui::test]
    fn equally_named_inputs_in_different_components_have_separate_editors(cx: &mut TestAppContext) {
        let input = |id| Node {
            id,
            kind: NodeKind::TextInput {
                label: "Name".into(),
                value: String::new(),
                placeholder: String::new(),
                enabled: true,
                style: Style::default(),
            },
            children: vec![],
        };
        let nodes = vec![
            Node {
                id: 1,
                kind: NodeKind::Column {
                    label: "Form".into(),
                    style: Style::default(),
                },
                children: vec![2, 4],
            },
            Node {
                id: 2,
                kind: NodeKind::Boundary { instance: 10 },
                children: vec![3],
            },
            input(3),
            Node {
                id: 4,
                kind: NodeKind::Boundary { instance: 20 },
                children: vec![5],
            },
            input(5),
        ];
        let (runtime, cx) = cx.add_window_view(|_, cx| {
            Runtime::new(initial_mount(Patch::Mount { root: 1, nodes }), cx)
        });
        runtime.read_with(cx, |runtime, cx| {
            assert_ne!(
                runtime.views[&3]
                    .read(cx)
                    .input
                    .as_ref()
                    .unwrap()
                    .entity_id(),
                runtime.views[&5]
                    .read(cx)
                    .input
                    .as_ref()
                    .unwrap()
                    .entity_id()
            );
            assert_ne!(runtime.identities[&3], runtime.identities[&5]);
        });
    }

    #[gpui::test]
    fn an_edit_queued_before_rerender_is_acknowledged_when_its_route_is_stale(
        cx: &mut TestAppContext,
    ) {
        install_test_dispatcher(|_| panic!("stale native edit reached Roc"));
        let node = |id| Node {
            id,
            kind: NodeKind::TextInput {
                label: "Name".into(),
                value: "saved".into(),
                placeholder: String::new(),
                enabled: true,
                style: Style::default(),
            },
            children: vec![],
        };
        let (runtime, cx) = cx.add_window_view(|_, cx| {
            Runtime::new(
                initial_mount(Patch::Mount {
                    root: 1,
                    nodes: vec![node(1)],
                }),
                cx,
            )
        });
        let editor = runtime.read_with(cx, |runtime, cx| {
            runtime.views[&1].read(cx).input.as_ref().unwrap().clone()
        });
        cx.update(|window, cx| {
            editor.update(cx, |editor, cx| {
                gpui::EntityInputHandler::replace_text_in_range(
                    editor,
                    Some(0..5),
                    "queued",
                    window,
                    cx,
                );
            });
            // Apply before the deferred native input callback. The reused
            // editor still has the original controlled value.
            runtime.update(cx, |runtime, cx| {
                runtime.apply_unrecorded(
                    Patch::Replace {
                        old_root: 1,
                        root: 2,
                        nodes: vec![node(2)],
                    },
                    cx,
                )
            });
        });
        cx.run_until_parked();
        editor.read_with(cx, |editor, _| {
            assert_eq!(editor.displayed_value(), "saved")
        });
    }

    /// The baseline the two tests below are measured against: with nothing
    /// intervening, a press and a release over GPUI's dispatch tree do reach
    /// the production click handler and the Roc event route.
    #[gpui::test]
    fn a_press_and_release_on_a_still_control_clicks(cx: &mut TestAppContext) {
        let clicks = recording_dispatcher();
        let (root, nodes) = transport_tree(1000, "Pause", "Pause");
        let initial = initial_mount(Patch::Mount { root, nodes });
        let (_runtime, cx) = cx.add_window_view(|_, cx| Runtime::new(initial, cx));
        let on_button = point(px(60.0), px(60.0));
        cx.run_until_parked();
        cx.simulate_mouse_move(on_button, None, Modifiers::none());
        cx.simulate_mouse_down(on_button, MouseButton::Left, Modifiers::none());
        cx.simulate_mouse_up(on_button, MouseButton::Left, Modifiers::none());
        assert_eq!(clicks.borrow().as_slice(), &[1001]);
    }

    /// The defect this guards: an application that rebuilds its tree while a
    /// person is holding a control used to lose the press entirely, because
    /// every GPUI element was keyed by a mounted node id that is never reused.
    /// The release then landed on an element that had never seen the press.
    ///
    /// Input here goes through GPUI's own dispatch tree, which is the only
    /// place the press/release pairing actually lives. The window runner's
    /// `click` step calls the production handler directly and cannot see this.
    #[gpui::test]
    fn a_control_rerendered_under_the_finger_still_completes_its_click(cx: &mut TestAppContext) {
        let clicks = recording_dispatcher();
        let (root, nodes) = transport_tree(1000, "Pause", "Pause");
        let initial = initial_mount(Patch::Mount { root, nodes });
        let (runtime, cx) = cx.add_window_view(|_, cx| Runtime::new(initial, cx));
        let on_button = point(px(60.0), px(60.0));
        cx.run_until_parked();
        cx.simulate_mouse_move(on_button, None, Modifiers::none());
        cx.simulate_mouse_down(on_button, MouseButton::Left, Modifiers::none());
        assert!(
            clicks.borrow().is_empty(),
            "a press alone dispatched a click"
        );

        // Twenty whole-root rebuilds under the held finger, every node id new
        // each time: a 50 ms playback timer held for a second, or a 5 ms one
        // held for a tenth of a second.
        let mut root = 1000;
        let mut live_button = 1001;
        for generation in 1..=20u64 {
            let base = 1000 + generation * 10;
            let (next_root, nodes) = transport_tree(base, "Pause", "Pause");
            runtime.update(cx, |runtime, cx| {
                runtime.apply_unrecorded(
                    Patch::Replace {
                        old_root: root,
                        root: next_root,
                        nodes,
                    },
                    cx,
                )
            });
            root = next_root;
            live_button = base + 1;
            cx.run_until_parked();
        }

        cx.simulate_mouse_up(on_button, MouseButton::Left, Modifiers::none());
        assert_eq!(
            clicks.borrow().as_slice(),
            &[live_button],
            "the press was lost across the rebuilds, or was routed to a retired node"
        );
    }

    /// Keyboard activation has to survive the same rebuilds. Focus lives on a
    /// focus handle owned by the view, so the view being claimed back by
    /// identity is what keeps the focused control focused rather than losing
    /// and restoring it a frame later.
    #[gpui::test]
    fn keyboard_activation_survives_rebuilds_under_the_focused_control(cx: &mut TestAppContext) {
        let clicks = recording_dispatcher();
        let (root, nodes) = transport_tree(1000, "Pause", "Pause");
        let initial = initial_mount(Patch::Mount { root, nodes });
        let (runtime, cx) = cx.add_window_view(|_, cx| Runtime::new(initial, cx));
        runtime.update(cx, |runtime, cx| {
            runtime.focus_after_render = Some(1001);
            cx.notify();
        });
        cx.run_until_parked();

        let mut root = 1000;
        let mut live_button = 1001;
        for generation in 1..=5u64 {
            let base = 1000 + generation * 10;
            let (next_root, nodes) = transport_tree(base, "Pause", "Pause");
            runtime.update(cx, |runtime, cx| {
                runtime.apply_unrecorded(
                    Patch::Replace {
                        old_root: root,
                        root: next_root,
                        nodes,
                    },
                    cx,
                )
            });
            root = next_root;
            live_button = base + 1;
            cx.run_until_parked();
        }

        cx.dispatch_action(ActivateEnter);
        assert_eq!(
            clicks.borrow().as_slice(),
            &[live_button],
            "keyboard focus did not survive the rebuilds"
        );
    }

    /// A virtual list's rows are rebuilt from the graph on every patch, so a
    /// control inside one is exposed to the same lost press as one outside it.
    /// The row views are offered back by identity too.
    #[gpui::test]
    fn a_control_inside_a_virtual_list_keeps_its_press_across_a_rebuild(cx: &mut TestAppContext) {
        let clicks = recording_dispatcher();
        let (root, nodes) = queue_tree(1000);
        let initial = initial_mount(Patch::Mount { root, nodes });
        let (runtime, cx) = cx.add_window_view(|_, cx| Runtime::new(initial, cx));
        let on_first_row = point(px(20.0), px(20.0));
        cx.run_until_parked();
        cx.simulate_mouse_move(on_first_row, None, Modifiers::none());
        cx.simulate_mouse_down(on_first_row, MouseButton::Left, Modifiers::none());

        let mut root = 1000;
        let mut live_button = 1003;
        for generation in 1..=5u64 {
            let base = 1000 + generation * 10;
            let (next_root, nodes) = queue_tree(base);
            runtime.update(cx, |runtime, cx| {
                runtime.apply_unrecorded(
                    Patch::Replace {
                        old_root: root,
                        root: next_root,
                        nodes,
                    },
                    cx,
                )
            });
            root = next_root;
            live_button = base + 3;
            cx.run_until_parked();
        }

        cx.simulate_mouse_up(on_first_row, MouseButton::Left, Modifiers::none());
        assert_eq!(
            clicks.borrow().as_slice(),
            &[live_button],
            "a press inside a virtual list was lost across the rebuilds"
        );
    }

    /// The other half of the rule: element identity is semantic, so a press on
    /// a control that leaves the tree is dropped rather than handed to whatever
    /// took its place.
    #[gpui::test]
    fn a_press_on_a_control_that_is_replaced_is_dropped(cx: &mut TestAppContext) {
        let clicks = recording_dispatcher();
        let (root, nodes) = transport_tree(1000, "Pause", "Pause");
        let initial = initial_mount(Patch::Mount { root, nodes });
        let (runtime, cx) = cx.add_window_view(|_, cx| Runtime::new(initial, cx));
        let on_button = point(px(60.0), px(60.0));
        cx.run_until_parked();
        cx.simulate_mouse_move(on_button, None, Modifiers::none());
        cx.simulate_mouse_down(on_button, MouseButton::Left, Modifiers::none());
        let (next_root, nodes) = transport_tree(2000, "Play", "Play");
        runtime.update(cx, |runtime, cx| {
            runtime.apply_unrecorded(
                Patch::Replace {
                    old_root: 1000,
                    root: next_root,
                    nodes,
                },
                cx,
            )
        });
        cx.run_until_parked();
        cx.simulate_mouse_up(on_button, MouseButton::Left, Modifiers::none());
        assert!(
            clicks.borrow().is_empty(),
            "a press on a control that left the tree was handed to its replacement"
        );
    }
}

/// Roc-shaped symbols so the host's own test binary links without a compiled
/// Roc application.
///
/// Nothing under `cargo test` calls into Roc: the event route is answered by
/// [`install_test_dispatcher`] instead. These exist only because the test
/// binary links the whole host, and are absent from the shipped staticlib.
#[cfg(test)]
mod roc_test_symbols {
    use crate::roc_platform_abi::RocErasedCallable;

    #[unsafe(no_mangle)]
    extern "C" fn roc_gui_init() {
        unreachable!("a host test called into Roc");
    }

    #[unsafe(no_mangle)]
    extern "C" fn roc_gui_dispatch(_dispatcher: RocErasedCallable, _event: u64) {
        unreachable!("a host test called into Roc");
    }

    #[unsafe(no_mangle)]
    extern "C" fn roc_gui_complete(
        _dispatcher: RocErasedCallable,
        _completion: RocErasedCallable,
        _owner: u64,
    ) {
        unreachable!("a host test called into Roc");
    }

    #[unsafe(no_mangle)]
    extern "C" fn roc_gui_run_task(_task: RocErasedCallable) -> RocErasedCallable {
        unreachable!("a host test called into Roc");
    }
}
