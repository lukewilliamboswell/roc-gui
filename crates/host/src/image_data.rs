use crate::{roc_host, roc_platform_abi::*};
use std::{
    io::Cursor,
    mem::ManuallyDrop,
    sync::atomic::{AtomicU64, Ordering},
};

const MAX_ENCODED_BYTES: usize = 64 * 1024 * 1024;
const MAX_DIMENSION: u32 = 32_768;
const MAX_PIXELS: u64 = 200_000_000;
static STAGED: AtomicU64 = AtomicU64::new(0);
static STAGED_BYTES: AtomicU64 = AtomicU64::new(0);
static INSPECTED: AtomicU64 = AtomicU64::new(0);
static FAILURES: AtomicU64 = AtomicU64::new(0);

pub fn note_staged(bytes: usize) {
    STAGED.fetch_add(1, Ordering::Relaxed);
    STAGED_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
}
pub fn counters() -> [u64; 4] {
    [
        STAGED.load(Ordering::Relaxed),
        STAGED_BYTES.load(Ordering::Relaxed),
        INSPECTED.load(Ordering::Relaxed),
        FAILURES.load(Ordering::Relaxed),
    ]
}

fn fail(code: u8) -> HostGlueImageInspectResult {
    FAILURES.fetch_add(1, Ordering::Relaxed);
    HostGlueImageInspectResult {
        payload: HostGlueImageInspectResultPayload {
            err: ManuallyDrop::new(code),
        },
        tag: HostGlueImageInspectResultTag::Err,
    }
}

fn raster_format(code: u8) -> Option<image::ImageFormat> {
    match code {
        0 => Some(image::ImageFormat::Bmp),
        1 => Some(image::ImageFormat::Gif),
        2 => Some(image::ImageFormat::Jpeg),
        3 => Some(image::ImageFormat::Png),
        5 => Some(image::ImageFormat::Tiff),
        6 => Some(image::ImageFormat::WebP),
        _ => None,
    }
}

fn dimensions(bytes: &[u8], format: u8) -> Result<(u32, u32), u8> {
    if bytes.is_empty() || bytes.len() > MAX_ENCODED_BYTES {
        return Err(2);
    }
    let (width, height) = if format == 4 {
        let tree = usvg::Tree::from_data(bytes, &usvg::Options::default()).map_err(|_| 0u8)?;
        let size = tree.size();
        (size.width().round() as u32, size.height().round() as u32)
    } else {
        let image_format = raster_format(format).ok_or(3u8)?;
        image::ImageReader::with_format(Cursor::new(bytes), image_format)
            .into_dimensions()
            .map_err(|_| 0u8)?
    };
    if width == 0
        || height == 0
        || width > MAX_DIMENSION
        || height > MAX_DIMENSION
        || u64::from(width) * u64::from(height) > MAX_PIXELS
    {
        Err(1)
    } else {
        Ok((width, height))
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn roc_image_inspect(
    bytes: RocListWith<u8, false>,
    format: u8,
) -> HostGlueImageInspectResult {
    let owned = bytes.as_slice().to_vec();
    unsafe { bytes.decref(roc_host()) };
    INSPECTED.fetch_add(1, Ordering::Relaxed);
    match dimensions(&owned, format) {
        Err(code) => fail(code),
        Ok((width, height)) => HostGlueImageInspectResult {
            payload: HostGlueImageInspectResultPayload {
                ok: ManuallyDrop::new(AnonStructB3b29ac2cb34a461 { height, width }),
            },
            tag: HostGlueImageInspectResultTag::Ok,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_empty_and_unknown_formats() {
        assert_eq!(dimensions(&[], 3), Err(2));
        assert_eq!(dimensions(b"not an image", 255), Err(3));
    }
}
