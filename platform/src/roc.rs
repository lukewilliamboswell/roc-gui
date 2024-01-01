use crate::graphics::colors::Rgba;
use core::alloc::Layout;
use core::ffi::c_void;
use core::mem::{self, ManuallyDrop};
use roc_std::{RocList, RocStr, RocBox};
use std::ffi::CStr;
use std::fmt::Debug;
use std::mem::MaybeUninit;
use std::os::raw::c_char;
use std::time::Duration;
use winit::event::VirtualKeyCode;

#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    return libc::malloc(size);
}

#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    return libc::realloc(c_ptr, new_size);
}

#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    return libc::free(c_ptr);
}

#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: *mut RocStr, tag_id: u32) {
    match tag_id {
        0 => {
            eprintln!("Roc standard library hit a panic: {}", &*msg);
        }
        1 => {
            eprintln!("Application hit a panic: {}", &*msg);
        }
        _ => unreachable!(),
    }
    std::process::exit(1);
}

#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: *mut RocStr, msg: *mut RocStr, src: *mut RocStr) {
    eprintln!("[{}] {} = {}", &*loc, &*src, &*msg);
}

#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

type BoxedModel = roc_std::RocBox<std::ffi::c_void>;

#[derive(Debug)]
#[repr(C)]
pub struct ProgramForHost {
    pub init: RocFunctionInit,
    pub render: RocFunctionRender,
    pub update: RocFunctionUpdate,
}

pub fn main_for_host() -> ProgramForHost {
    extern "C" {
        fn roc__mainForHost_1_exposed_generic(_: *mut u8);
        fn roc__mainForHost_1_exposed_size() -> isize;
        fn roc__mainForHost_0_size() -> isize;
        fn roc__mainForHost_1_size() -> isize;
        fn roc__mainForHost_2_size() -> isize;
    }
    let size = unsafe { roc__mainForHost_1_exposed_size() } as usize;
    let mut captures = Vec::with_capacity(size);
    captures.resize(size, 0);

    unsafe {
        roc__mainForHost_1_exposed_generic(captures.as_mut_ptr());
    }

    let init_size = unsafe { roc__mainForHost_0_size() } as usize;
    let render_size = unsafe { roc__mainForHost_1_size() } as usize;
    let update_size = unsafe { roc__mainForHost_2_size() } as usize;

    dbg!(size);
    dbg!(init_size);
    dbg!(render_size);
    dbg!(update_size);

    let mut ret = ProgramForHost {
        init: RocFunctionInit {
            closure_data: Vec::with_capacity(init_size),
        },
        render: RocFunctionRender {
            closure_data: Vec::with_capacity(render_size),
        },
        update: RocFunctionUpdate {
            closure_data: Vec::with_capacity(update_size),
        },
    };

    let mut data_slice = captures.as_slice();
    ret.init.closure_data.extend(&data_slice[..init_size]);
    data_slice = &data_slice[init_size..];
    ret.init.closure_data.extend(&data_slice[..render_size]);
    data_slice = &data_slice[render_size..];
    ret.init.closure_data.extend(&data_slice[..update_size]);

    ret
}


#[repr(C)]
#[derive(Debug)]
pub struct RocFunctionInit {
    closure_data: Vec<u8>,
}

impl RocFunctionInit {
    pub fn force_thunk(mut self, arg0: roc_app::Bounds) -> BoxedModel {
        extern "C" {
            fn roc__mainForHost_0_caller(
                arg0: *const roc_app::Bounds,
                closure_data: *mut u8,
                output: *mut BoxedModel,
            );
        }

        let mut output = core::mem::MaybeUninit::uninit();

        unsafe {
            roc__mainForHost_0_caller(&arg0, self.closure_data.as_mut_ptr(), output.as_mut_ptr());

            output.assume_init()
        }
    }
}

#[repr(C)]
#[derive(Debug)]
pub struct RocFunctionUpdate {
    closure_data: Vec<u8>,
}

impl RocFunctionUpdate {
    pub fn force_thunk(mut self, model: BoxedModel, arg1: roc_app::Event) -> BoxedModel {

        extern "C" {
            fn roc__mainForHost_2_caller(
                model: *const BoxedModel,
                arg1: *const roc_app::Event,
                closure_data: *mut u8,
                output: *mut BoxedModel,
            );
        }

        let mut output = core::mem::MaybeUninit::uninit();

        unsafe {
            roc__mainForHost_2_caller(
                &model,
                &arg1,
                self.closure_data.as_mut_ptr(),
                output.as_mut_ptr(),
            );

            output.assume_init()
        }
    }
}

#[repr(C)]
#[derive(Debug)]
pub struct RocFunctionRender {
    closure_data: Vec<u8>,
}

#[repr(C)]
#[derive(Debug)]
pub struct RenderReturn {
    pub elems: RocList<roc_app::Elem>,
    pub model: BoxedModel,
}

impl RocFunctionRender {
    pub fn force_thunk(mut self, model: BoxedModel) -> RenderReturn {
        extern "C" {
            fn roc__mainForHost_1_caller(
                arg0: *const BoxedModel,
                closure_data: *mut u8,
                output: *mut RenderReturn,
            );
        }

        let mut output = core::mem::MaybeUninit::uninit();

        unsafe {
            roc__mainForHost_1_caller(&model, self.closure_data.as_mut_ptr(), output.as_mut_ptr());

            output.assume_init()
        }
    }
}