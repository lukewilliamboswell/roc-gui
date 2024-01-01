// ⚠️ GENERATED CODE ⚠️ - this entire file was generated by the `roc glue` CLI command

#![allow(unused_unsafe)]
#![allow(dead_code)]
#![allow(unused_mut)]
#![allow(non_snake_case)]
#![allow(non_camel_case_types)]
#![allow(non_upper_case_globals)]
#![allow(clippy::undocumented_unsafe_blocks)]
#![allow(clippy::redundant_static_lifetimes)]
#![allow(clippy::unused_unit)]
#![allow(clippy::missing_safety_doc)]
#![allow(clippy::let_and_return)]
#![allow(clippy::missing_safety_doc)]
#![allow(clippy::redundant_static_lifetimes)]
#![allow(clippy::needless_borrow)]
#![allow(clippy::clone_on_copy)]


#[derive(Clone, Copy, Default, Debug, PartialEq, PartialOrd, )]
#[repr(C)]
pub struct Bounds {
    pub height: f32,
    pub width: f32,
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(u8)]
pub enum KeyCode {
    Down = 0,
    Left = 1,
    Other = 2,
    Right = 3,
    Up = 4,
}

impl core::fmt::Debug for KeyCode {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Down => f.write_str("KeyCode::Down"),
            Self::Left => f.write_str("KeyCode::Left"),
            Self::Other => f.write_str("KeyCode::Other"),
            Self::Right => f.write_str("KeyCode::Right"),
            Self::Up => f.write_str("KeyCode::Up"),
        }
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(u8)]
pub enum discriminant_Event {
    KeyDown = 0,
    KeyUp = 1,
    Resize = 2,
    Tick = 3,
}

impl core::fmt::Debug for discriminant_Event {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::KeyDown => f.write_str("discriminant_Event::KeyDown"),
            Self::KeyUp => f.write_str("discriminant_Event::KeyUp"),
            Self::Resize => f.write_str("discriminant_Event::Resize"),
            Self::Tick => f.write_str("discriminant_Event::Tick"),
        }
    }
}

#[repr(C, align(8))]
pub union union_Event {
    KeyDown: KeyCode,
    KeyUp: KeyCode,
    Resize: Bounds,
    Tick: u64,
}

const _SIZE_CHECK_union_Event: () = assert!(core::mem::size_of::<union_Event>() == 8);
const _ALIGN_CHECK_union_Event: () = assert!(core::mem::align_of::<union_Event>() == 8);

const _SIZE_CHECK_Event: () = assert!(core::mem::size_of::<Event>() == 16);
const _ALIGN_CHECK_Event: () = assert!(core::mem::align_of::<Event>() == 8);

impl Event {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> discriminant_Event {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, discriminant_Event>(*bytes.as_ptr().add(8))
        }
    }

    /// Internal helper
    fn set_discriminant(&mut self, discriminant: discriminant_Event) {
        let discriminant_ptr: *mut discriminant_Event = (self as *mut Event).cast();

        unsafe {
            *(discriminant_ptr.add(8)) = discriminant;
        }
    }
}

#[repr(C)]
pub struct Event {
    payload: union_Event,
    discriminant: discriminant_Event,
}

impl Clone for Event {
    fn clone(&self) -> Self {
        use discriminant_Event::*;

        let payload = unsafe {
            match self.discriminant {
                KeyDown => union_Event {
                    KeyDown: self.payload.KeyDown.clone(),
                },
                KeyUp => union_Event {
                    KeyUp: self.payload.KeyUp.clone(),
                },
                Resize => union_Event {
                    Resize: self.payload.Resize.clone(),
                },
                Tick => union_Event {
                    Tick: self.payload.Tick.clone(),
                },
            }
        };

        Self {
            discriminant: self.discriminant,
            payload,
        }
    }
}

impl core::fmt::Debug for Event {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use discriminant_Event::*;

        unsafe {
            match self.discriminant {
                KeyDown => {
                    let field: &KeyCode = &self.payload.KeyDown;
                    f.debug_tuple("Event::KeyDown").field(field).finish()
                },
                KeyUp => {
                    let field: &KeyCode = &self.payload.KeyUp;
                    f.debug_tuple("Event::KeyUp").field(field).finish()
                },
                Resize => {
                    let field: &Bounds = &self.payload.Resize;
                    f.debug_tuple("Event::Resize").field(field).finish()
                },
                Tick => {
                    let field: &u64 = &self.payload.Tick;
                    f.debug_tuple("Event::Tick").field(field).finish()
                },
            }
        }
    }
}

impl PartialEq for Event {
    fn eq(&self, other: &Self) -> bool {
        use discriminant_Event::*;

        if self.discriminant != other.discriminant {
            return false;
        }

        unsafe {
            match self.discriminant {
                KeyDown => self.payload.KeyDown == other.payload.KeyDown,
                KeyUp => self.payload.KeyUp == other.payload.KeyUp,
                Resize => self.payload.Resize == other.payload.Resize,
                Tick => self.payload.Tick == other.payload.Tick,
            }
        }
    }
}

impl PartialOrd for Event {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        use discriminant_Event::*;

        use std::cmp::Ordering::*;

        match self.discriminant.cmp(&other.discriminant) {
            Less => Option::Some(Less),
            Greater => Option::Some(Greater),
            Equal => unsafe {
                match self.discriminant {
                    KeyDown => self.payload.KeyDown.partial_cmp(&other.payload.KeyDown),
                    KeyUp => self.payload.KeyUp.partial_cmp(&other.payload.KeyUp),
                    Resize => self.payload.Resize.partial_cmp(&other.payload.Resize),
                    Tick => self.payload.Tick.partial_cmp(&other.payload.Tick),
                }
            },
        }
    }
}

impl Event {

    pub fn unwrap_KeyDown(mut self) -> KeyCode {
        debug_assert_eq!(self.discriminant, discriminant_Event::KeyDown);
        unsafe { self.payload.KeyDown }
    }

    pub fn is_KeyDown(&self) -> bool {
        matches!(self.discriminant, discriminant_Event::KeyDown)
    }

    pub fn unwrap_KeyUp(mut self) -> KeyCode {
        debug_assert_eq!(self.discriminant, discriminant_Event::KeyUp);
        unsafe { self.payload.KeyUp }
    }

    pub fn is_KeyUp(&self) -> bool {
        matches!(self.discriminant, discriminant_Event::KeyUp)
    }

    pub fn unwrap_Resize(mut self) -> Bounds {
        debug_assert_eq!(self.discriminant, discriminant_Event::Resize);
        unsafe { self.payload.Resize }
    }

    pub fn is_Resize(&self) -> bool {
        matches!(self.discriminant, discriminant_Event::Resize)
    }

    pub fn unwrap_Tick(mut self) -> u64 {
        debug_assert_eq!(self.discriminant, discriminant_Event::Tick);
        unsafe { self.payload.Tick }
    }

    pub fn is_Tick(&self) -> bool {
        matches!(self.discriminant, discriminant_Event::Tick)
    }
}



impl Event {

    pub fn KeyDown(payload: KeyCode) -> Self {
        Self {
            discriminant: discriminant_Event::KeyDown,
            payload: union_Event {
                KeyDown: payload,
            }
        }
    }

    pub fn KeyUp(payload: KeyCode) -> Self {
        Self {
            discriminant: discriminant_Event::KeyUp,
            payload: union_Event {
                KeyUp: payload,
            }
        }
    }

    pub fn Resize(payload: Bounds) -> Self {
        Self {
            discriminant: discriminant_Event::Resize,
            payload: union_Event {
                Resize: payload,
            }
        }
    }

    pub fn Tick(payload: u64) -> Self {
        Self {
            discriminant: discriminant_Event::Tick,
            payload: union_Event {
                Tick: payload,
            }
        }
    }
}

#[derive(Clone, Copy, Default, Debug, PartialEq, PartialOrd, )]
#[repr(C)]
pub struct Rgba {
    pub a: f32,
    pub b: f32,
    pub g: f32,
    pub r: f32,
}

#[derive(Clone, Copy, Default, Debug, PartialEq, PartialOrd, )]
#[repr(C)]
pub struct R2 {
    pub color: Rgba,
    pub height: f32,
    pub left: f32,
    pub top: f32,
    pub width: f32,
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, )]
#[repr(C)]
pub struct R3 {
    pub color: Rgba,
    pub left: f32,
    pub size: f32,
    pub text: roc_std::RocStr,
    pub top: f32,
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(u8)]
pub enum discriminant_Elem {
    Rect = 0,
    Text = 1,
}

impl core::fmt::Debug for discriminant_Elem {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Rect => f.write_str("discriminant_Elem::Rect"),
            Self::Text => f.write_str("discriminant_Elem::Text"),
        }
    }
}

#[repr(C, align(4))]
pub union union_Elem {
    Rect: R2,
    Text: core::mem::ManuallyDrop<R3>,
}

const _SIZE_CHECK_union_Elem: () = assert!(core::mem::size_of::<union_Elem>() == 40);
const _ALIGN_CHECK_union_Elem: () = assert!(core::mem::align_of::<union_Elem>() == 4);

const _SIZE_CHECK_Elem: () = assert!(core::mem::size_of::<Elem>() == 44);
const _ALIGN_CHECK_Elem: () = assert!(core::mem::align_of::<Elem>() == 4);

impl Elem {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> discriminant_Elem {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, discriminant_Elem>(*bytes.as_ptr().add(40))
        }
    }

    /// Internal helper
    fn set_discriminant(&mut self, discriminant: discriminant_Elem) {
        let discriminant_ptr: *mut discriminant_Elem = (self as *mut Elem).cast();

        unsafe {
            *(discriminant_ptr.add(40)) = discriminant;
        }
    }
}

#[repr(C)]
pub struct Elem {
    payload: union_Elem,
    discriminant: discriminant_Elem,
}

impl Clone for Elem {
    fn clone(&self) -> Self {
        use discriminant_Elem::*;

        let payload = unsafe {
            match self.discriminant {
                Rect => union_Elem {
                    Rect: self.payload.Rect.clone(),
                },
                Text => union_Elem {
                    Text: self.payload.Text.clone(),
                },
            }
        };

        Self {
            discriminant: self.discriminant,
            payload,
        }
    }
}

impl core::fmt::Debug for Elem {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use discriminant_Elem::*;

        unsafe {
            match self.discriminant {
                Rect => {
                    let field: &R2 = &self.payload.Rect;
                    f.debug_tuple("Elem::Rect").field(field).finish()
                },
                Text => {
                    let field: &R3 = &self.payload.Text;
                    f.debug_tuple("Elem::Text").field(field).finish()
                },
            }
        }
    }
}

impl PartialEq for Elem {
    fn eq(&self, other: &Self) -> bool {
        use discriminant_Elem::*;

        if self.discriminant != other.discriminant {
            return false;
        }

        unsafe {
            match self.discriminant {
                Rect => self.payload.Rect == other.payload.Rect,
                Text => self.payload.Text == other.payload.Text,
            }
        }
    }
}

impl PartialOrd for Elem {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        use discriminant_Elem::*;

        use std::cmp::Ordering::*;

        match self.discriminant.cmp(&other.discriminant) {
            Less => Option::Some(Less),
            Greater => Option::Some(Greater),
            Equal => unsafe {
                match self.discriminant {
                    Rect => self.payload.Rect.partial_cmp(&other.payload.Rect),
                    Text => self.payload.Text.partial_cmp(&other.payload.Text),
                }
            },
        }
    }
}

impl Elem {

    pub fn unwrap_Rect(mut self) -> R2 {
        debug_assert_eq!(self.discriminant, discriminant_Elem::Rect);
        unsafe { self.payload.Rect }
    }

    pub fn is_Rect(&self) -> bool {
        matches!(self.discriminant, discriminant_Elem::Rect)
    }

    pub fn unwrap_Text(mut self) -> R3 {
        debug_assert_eq!(self.discriminant, discriminant_Elem::Text);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.Text) }
    }

    pub fn is_Text(&self) -> bool {
        matches!(self.discriminant, discriminant_Elem::Text)
    }
}



impl Elem {

    pub fn Rect(payload: R2) -> Self {
        Self {
            discriminant: discriminant_Elem::Rect,
            payload: union_Elem {
                Rect: payload,
            }
        }
    }

    pub fn Text(payload: R3) -> Self {
        Self {
            discriminant: discriminant_Elem::Text,
            payload: union_Elem {
                Text: core::mem::ManuallyDrop::new(payload),
            }
        }
    }
}

impl Drop for Elem {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            discriminant_Elem::Rect => {}
            discriminant_Elem::Text => unsafe { core::mem::ManuallyDrop::drop(&mut self.payload.Text) },
        }
    }
}

#[derive(Clone, Debug, PartialEq, PartialOrd, )]
#[repr(C)]
pub struct GlueStuff {
    pub a: roc_std::RocList<Bounds>,
    pub b: roc_std::RocList<Event>,
    pub c: roc_std::RocList<Elem>,
}



pub fn mainForHost() -> GlueStuff {
    extern "C" {
        fn roc__mainForHost_1_exposed_generic(_: *mut GlueStuff);
    }

    let mut ret = core::mem::MaybeUninit::uninit();

    unsafe {
        roc__mainForHost_1_exposed_generic(ret.as_mut_ptr(), );

        ret.assume_init()
    }
}