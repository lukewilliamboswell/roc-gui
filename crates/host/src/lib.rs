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
mod http;
mod image_data;
mod input;
mod observatory;
mod probe;
mod process;
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
    Align, BridgeState, CanvasPrimitive, CanvasPrimitiveKind, ControlKey, ImageFit,
    ImageFormat as BridgeImageFormat, Justify, Length, MountedGraph, Node, NodeKind, Overflow,
    Patch, ScrollAxis, Style, decode_commit, validate_tree,
};
use gpui::{div, prelude::*, px, rgb, size, *};
use roc_platform_abi::{
    DefaultAllocators, DefaultHandlers, HostGlueCanvasEventRetRecord, HostGlueHttpAcquireResult,
    HostGlueHttpSendArgs, HostGlueHttpSendResult, HostGlueNodeActionButtonArgs,
    HostGlueNodeCanvasArgs, HostGlueNodeCheckboxArgs, HostGlueNodeColumnArgs,
    HostGlueNodeDialogArgs, HostGlueNodeImageArgs, HostGlueNodePanelArgs, HostGlueNodeRowArgs,
    HostGlueNodeScrollArgs, HostGlueNodeTextInputArgs, HostGlueNodeTextInputRetRecord,
    HostGlueNodeTextareaArgs, HostGlueNodeVirtualItemArgs, HostGlueNodeVirtualListArgs,
    MountOrNoChangeOrReplace, RocErasedCallable, RocHost, RocStr, decref_erased_callable,
    make_roc_host, roc_gui_dispatch, roc_gui_init,
};
use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::c_void,
    path::PathBuf,
    sync::atomic::{AtomicBool, AtomicU64, Ordering},
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
static GPUI_SMOKE: AtomicBool = AtomicBool::new(false);
static GPUI_SMOKE_RENDERS: AtomicU64 = AtomicU64::new(0);

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
    static INPUT_VALUE: RefCell<Option<String>> = const { RefCell::new(None) };
    static CANVAS_EVENT: RefCell<Option<CanvasEventPayload>> = const { RefCell::new(None) };
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
        },
        vec![args.child],
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_virtual_item(args: HostGlueNodeVirtualItemArgs) -> u64 {
    stage_node(NodeKind::VirtualItem { key: args.arg0 }, vec![args.arg1])
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_gui_node_virtual_list(args: HostGlueNodeVirtualListArgs) -> u64 {
    let name = args.name.as_str().to_owned();
    unsafe { args.name.decref(roc_host()) };
    stage_node(
        NodeKind::VirtualList {
            name,
            row_height: args.row_height,
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
    input_enabled: bool,
    focus_handle: Option<FocusHandle>,
    input: Option<Entity<input::TextInput>>,
    canvas_bounds: Arc<Mutex<Option<Bounds<Pixels>>>>,
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
    if style.font_weight > 0 {
        element = element.font_weight(FontWeight(style.font_weight as f32));
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
        let mut element = div().id(("node", self.node.id));
        let mut append_children = true;
        if self.is_root {
            element = element.size_full().min_h_0().min_w_0();
        }
        match &self.node.kind {
            NodeKind::Canvas {
                label,
                primitives,
                style,
            } => {
                let paint_items = primitives.clone();
                let hit_items = primitives.clone();
                let bounds_slot = self.canvas_bounds.clone();
                let down_bounds = self.canvas_bounds.clone();
                let down_runtime = self.runtime.clone();
                let paint_runtime = self.runtime.clone();
                let down_label = label.clone();
                let paint_label = label.clone();
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
                        let move_label = paint_label.clone();
                        window.on_mouse_event(move |event: &MouseMoveEvent, phase, _, cx| {
                            if phase == DispatchPhase::Bubble {
                                let x =
                                    f32::from(event.position.x - bounds.origin.x).round() as i32;
                                let y =
                                    f32::from(event.position.y - bounds.origin.y).round() as i32;
                                let _ = move_runtime.update(cx, |runtime, cx| {
                                    runtime.canvas_pointer(&move_label, 1, x, y, 0, cx)
                                });
                            }
                        });
                        let up_runtime = paint_runtime.clone();
                        let up_label = paint_label.clone();
                        window.on_mouse_event(move |event: &MouseUpEvent, phase, _, cx| {
                            if phase == DispatchPhase::Bubble && event.button == MouseButton::Left {
                                let x =
                                    f32::from(event.position.x - bounds.origin.x).round() as i32;
                                let y =
                                    f32::from(event.position.y - bounds.origin.y).round() as i32;
                                let _ = up_runtime.update(cx, |runtime, cx| {
                                    runtime.canvas_pointer(&up_label, 2, x, y, 0, cx)
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
                                runtime.canvas_pointer(&down_label, 0, x, y, target, cx)
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
                let inner = apply_style(
                    div().id(("dialog-surface", dialog_id)).flex().flex_col(),
                    style,
                )
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
            NodeKind::VirtualItem { .. } => {}
            NodeKind::VirtualList { row_height, .. } => {
                let list_id = self.node.id;
                let count = self.node.children.len();
                let runtime = self.runtime.clone();
                let height = *row_height;
                element = element
                    .flex()
                    .flex_col()
                    .flex_grow()
                    .min_h_0()
                    .max_h_full()
                    .child(
                        uniform_list(("virtual-list", list_id), count, move |range, _, cx| {
                            runtime
                                .update(cx, |runtime, cx| {
                                    runtime.virtual_range(list_id, range, height, cx)
                                })
                                .unwrap_or_default()
                        })
                        .size_full(),
                    );
            }
            NodeKind::Text(value) => {
                element = element.child(value.clone());
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
                element = apply_style(element, style)
                    .min_w_0()
                    .min_h_0()
                    .child(picture);
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
                style,
            } => {
                let node_id = self.node.id;
                let runtime = self.runtime.clone();
                let enabled_box = *enabled && self.input_enabled;
                let mark = if *checked { "✓" } else { "" };
                let box_bg = if *checked {
                    CHECKBOX_CHECKED_BG
                } else {
                    CHECKBOX_BG
                };
                let box_fg = if *checked {
                    CHECKBOX_CHECKED_FG
                } else {
                    CHECKBOX_BORDER
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
                                CHECKBOX_BORDER
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
                if style.font_weight > 0 {
                    element = element.font_weight(FontWeight(style.font_weight as f32));
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
            element.children(self.children.iter().cloned().map(AnyView::from))
        } else {
            element
        }
    }
}

struct Runtime {
    graph: MountedGraph,
    views: HashMap<u64, Entity<NodeView>>,
    virtual_views: HashMap<(u64, u64), VirtualCached>,
    focus_handles: HashMap<u64, FocusHandle>,
    root: Option<Entity<NodeView>>,
    cycle_ordinal: u64,
    active_dialog: Option<u64>,
    dialog_return_focus: Option<(u8, String)>,
    last_trigger_focus: Option<(u8, String)>,
    focused_identity: Option<(u64, (u8, String))>,
    focus_after_render: Option<u64>,
    editors: HashMap<String, Entity<input::TextInput>>,
    canvas_drag: Option<(String, u64)>,
}

struct VirtualCached {
    view: Entity<NodeView>,
    entities: u64,
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
            virtual_views: HashMap::new(),
            focus_handles: HashMap::new(),
            root: None,
            cycle_ordinal: 0,
            active_dialog: None,
            dialog_return_focus: None,
            last_trigger_focus: None,
            focused_identity: None,
            focus_after_render: None,
            editors: HashMap::new(),
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
        let (chooser_requests, chooser_pending) =
            std::sync::mpsc::channel::<files::ChooserRequest>();
        files::install_chooser(chooser_requests);
        let chooser_executor = cx.background_executor().clone();
        cx.spawn(async move |_, cx| {
            loop {
                chooser_executor
                    .timer(std::time::Duration::from_millis(50))
                    .await;
                let Ok(request) = chooser_pending.try_recv() else {
                    if cx.update(|_| ()).is_err() {
                        break;
                    }
                    continue;
                };
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
        let resolved_target = match phase {
            0 => {
                self.canvas_drag = Some((label.to_owned(), target));
                target
            }
            1 | 2 => match &self.canvas_drag {
                Some((active, target)) if active == label => *target,
                _ => return,
            },
            _ => return,
        };
        let id = self.graph.nodes_preorder().into_iter().find_map(|node| {
            matches!(&node.kind, NodeKind::Canvas { label: current, .. } if current == label)
                .then_some(node.id)
        });
        let Some(id) = id else { return };
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
        if !matches!(
            self.graph.node(id).map(|node| &node.kind),
            Some(
                NodeKind::Button { enabled: true, .. }
                    | NodeKind::Checkbox { enabled: true, .. }
                    | NodeKind::Dialog { .. }
            )
        ) {
            return;
        }
        if !matches!(
            self.graph.node(id).map(|node| &node.kind),
            Some(NodeKind::Dialog { .. })
        ) {
            self.last_trigger_focus = self
                .graph
                .node(id)
                .and_then(|node| node.kind.focus_identity());
        }
        self.dispatch_live_event(id, "click", cx);
    }

    fn text_event_if_live(
        &mut self,
        node_id: u64,
        event_id: u64,
        value: String,
        trigger: &'static str,
        cx: &mut Context<Self>,
    ) {
        if self
            .active_dialog
            .is_some_and(|dialog| !self.graph.is_descendant_of(node_id, dialog))
        {
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
            return;
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
        if !applied.staged_ids.is_empty() || !applied.removed_ids.is_empty() || applied.retired_root
        {
            let mut recycled = HashMap::<u64, u64>::new();
            for ((list, _), cached) in &self.virtual_views {
                *recycled.entry(*list).or_default() += cached.entities;
            }
            for (list, entities) in recycled {
                observatory::virtual_list_frame(list, 0, 0, entities, 0);
            }
            self.virtual_views.clear();
        }
        if applied.retired_root {
            self.views.clear();
        }
        self.materialize(&applied.staged_ids, cx);
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
                    .and_then(|identity| self.graph.find_focus_identity(&identity));
            }
            _ => {
                if let Some((id, identity)) = self.focused_identity.clone() {
                    if self.graph.node(id).is_none() {
                        self.focus_after_render = self.graph.find_focus_identity(&identity);
                    }
                }
            }
        }
        self.active_dialog = next_dialog;
        for (id, view) in &self.views {
            let enabled = next_dialog.is_none_or(|dialog| self.graph.is_descendant_of(*id, dialog));
            view.update(cx, |view, _| view.input_enabled = enabled);
        }
        if let Some(root_id) = applied.root {
            if let (Some((_parent_id, position)), Some(new_root), Some(parent_view)) = (
                applied.parent,
                self.views.get(&root_id).cloned(),
                applied
                    .parent
                    .and_then(|(parent, _)| self.views.get(&parent).cloned()),
            ) {
                parent_view.update(cx, |view, cx| {
                    view.node.children[position] = root_id;
                    view.children[position] = new_root.clone();
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
            self.focus_handles.remove(id);
        }
        let live_labels: std::collections::HashSet<String> = self
            .graph
            .nodes_preorder()
            .into_iter()
            .filter_map(|node| match &node.kind {
                NodeKind::TextInput { label, .. } => Some(label.clone()),
                _ => None,
            })
            .collect();
        self.editors.retain(|label, _| live_labels.contains(label));
    }

    fn materialize(&mut self, node_ids: &[u64], cx: &mut Context<Self>) {
        let virtualized = self.graph.virtual_descendant_ids();
        let eager = node_ids
            .iter()
            .copied()
            .filter(|id| !virtualized.contains(id))
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
            let value = node.clone();
            let input_enabled = self
                .active_dialog
                .is_none_or(|dialog| self.graph.is_descendant_of(node.id, dialog));
            let editor = self.editor_for_node(&node, input_enabled, cx);
            let focus_handle = if let Some(editor) = &editor {
                Some(editor.read(cx).focus_handle())
            } else {
                node.kind.focus_identity().map(|_| cx.focus_handle())
            };
            let view_focus = focus_handle.clone();
            let runtime = cx.entity().downgrade();
            let view = cx.new(|_| NodeView {
                node: value,
                children: vec![],
                runtime,
                is_root: false,
                input_enabled,
                focus_handle: view_focus,
                input: editor,
                canvas_bounds: Arc::new(Mutex::new(None)),
            });
            if let Some(handle) = focus_handle {
                self.focus_handles.insert(node.id, handle);
            }
            self.views.insert(node.id, view);
        }
        for id in &eager {
            let node = self.graph.node(*id).expect("applied node is missing");
            let children = node
                .children
                .iter()
                .filter(|id| !virtualized.contains(id))
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
            label,
            value,
            placeholder,
            enabled,
            ..
        } = &node.kind
        {
            let runtime = cx.entity().downgrade();
            let change_runtime = runtime.clone();
            let submit_runtime = runtime.clone();
            let node_id = node.id;
            let change: std::rc::Rc<dyn Fn(String, &mut App)> =
                std::rc::Rc::new(move |text, cx| {
                    let _ = change_runtime.update(cx, |runtime, cx| {
                        runtime.text_event_if_live(node_id, node_id, text, "text_change", cx)
                    });
                });
            let submit: std::rc::Rc<dyn Fn(String, &mut App)> =
                std::rc::Rc::new(move |text, cx| {
                    let _ = submit_runtime.update(cx, |runtime, cx| {
                        runtime.text_event_if_live(
                            node_id,
                            node_id | SUBMIT_EVENT_BIT,
                            text,
                            "text_submit",
                            cx,
                        )
                    });
                });
            if let Some(editor) = self.editors.get(label).cloned() {
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
                self.editors.insert(label.clone(), editor.clone());
                Some(editor)
            }
        } else {
            None
        }
    }

    fn build_virtual_node(&mut self, id: u64, cx: &mut Context<Self>) -> (Entity<NodeView>, u64) {
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
        let runtime = cx.entity().downgrade();
        let input_enabled = self
            .active_dialog
            .is_none_or(|dialog| self.graph.is_descendant_of(id, dialog));
        let input = self.editor_for_node(&node, input_enabled, cx);
        let focus_handle = if let Some(editor) = &input {
            Some(editor.read(cx).focus_handle())
        } else {
            node.kind.focus_identity().map(|_| cx.focus_handle())
        };
        let view_focus = focus_handle.clone();
        let view = cx.new(|_| NodeView {
            node,
            children,
            runtime,
            is_root: false,
            input_enabled,
            focus_handle: view_focus,
            input,
            canvas_bounds: Arc::new(Mutex::new(None)),
        });
        if let Some(handle) = focus_handle {
            self.focus_handles.insert(id, handle);
        }
        (view, descendants + 1)
    }

    fn virtual_range(
        &mut self,
        list_id: u64,
        range: std::ops::Range<usize>,
        row_height: u32,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let item_ids = self
            .graph
            .node(list_id)
            .expect("virtual list is missing")
            .children
            .clone();
        let wanted = range
            .filter_map(|index| item_ids.get(index).copied())
            .collect::<Vec<_>>();
        let wanted_set = wanted
            .iter()
            .copied()
            .collect::<std::collections::HashSet<_>>();
        let recycled = self
            .virtual_views
            .iter()
            .filter(|((owner, item), _)| *owner == list_id && !wanted_set.contains(item))
            .map(|(_, cached)| cached.entities)
            .sum();
        self.virtual_views
            .retain(|(owner, item), _| *owner != list_id || wanted_set.contains(item));
        let mut materialized = 0;
        for item in &wanted {
            if !self.virtual_views.contains_key(&(list_id, *item)) {
                let (view, entities) = self.build_virtual_node(*item, cx);
                materialized += entities;
                self.virtual_views
                    .insert((list_id, *item), VirtualCached { view, entities });
            }
        }
        let live_entities = self
            .virtual_views
            .iter()
            .filter(|((owner, _), _)| *owner == list_id)
            .map(|(_, cached)| cached.entities)
            .sum();
        observatory::virtual_list_frame(
            list_id,
            wanted.len() as u64,
            materialized,
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
                div()
                    .id(("virtual-row", key))
                    .h(px(row_height as f32))
                    .child(view)
                    .into_any_element()
            })
            .collect()
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
        if let Some(target) = self.focus_after_render.take() {
            if let Some(handle) = self.focus_handles.get(&target) {
                handle.focus(window);
            }
        }
        self.focused_identity = self
            .focus_handles
            .iter()
            .find(|(_, handle)| handle.is_focused(window))
            .map(|(id, _)| *id)
            .and_then(|id| {
                self.graph
                    .node(id)
                    .and_then(|node| node.kind.focus_identity())
                    .map(|identity| (id, identity))
            });
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
            .children(self.root.iter().cloned().map(AnyView::from))
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
                    return Err(format!("directory grant does not exist: {}", path.display()));
                }
                flags.push("--host-cap-dir".into());
                flags.push(path.display().to_string());
            }
            spec::Grant::AppData(_) => {
                let path = resolved.expect("app-data grant names a path");
                if !path.is_dir() {
                    return Err(format!("app-data grant does not exist: {}", path.display()));
                }
                app_data_seed = Some(path.display().to_string());
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
    if observatory::active() {
        if let Err(message) = observatory::finish(outcome) {
            eprintln!("roc-gui stats error: {message}");
        }
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
    if let Err(message) = clipboard::configure(
        args.cap_clipboard_system,
        args.cap_clipboard_fixture,
    ) {
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
    use super::{
        CanvasPrimitive, CanvasPrimitiveKind, WindowConfig, canvas_target, counted_roc_alloc,
        counted_roc_dealloc, counted_roc_realloc, make_counted_roc_host, validate_window_config,
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
}
