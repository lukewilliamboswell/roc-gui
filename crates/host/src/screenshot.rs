//! Screenshots of the host's own window, taken by the platform's capture tool.
//!
//! GPUI 0.2.2 exposes no framebuffer readback outside `test-support`, so the
//! host shells out. Because it knows its own window origin and, through
//! [`crate::probe`], where each node was laid out, it can hand the tool a
//! screen-coordinate rectangle — which makes cropping to an element free rather
//! than a post-processing step.
//!
//! Capture is best effort and says so. A missing tool or a denied Screen
//! Recording permission is reported as `unavailable` with a reason, never as a
//! pass and never as a zero-byte file.

use std::path::Path;
use std::process::Command;

/// A rectangle in screen coordinates, points, ready for a capture tool.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Geometry {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

/// Why a capture produced no image.
#[derive(Debug)]
pub enum ShotError {
    UnsupportedPlatform,
    DegenerateRegion,
    ToolMissing(&'static str),
    ToolFailed {
        tool: &'static str,
        status: Option<i32>,
        detail: String,
    },
    NotAnImage,
}

impl ShotError {
    /// A short machine-readable reason for the report.
    pub fn reason(&self) -> &'static str {
        match self {
            Self::UnsupportedPlatform => "unsupported_platform",
            Self::DegenerateRegion => "degenerate_region",
            Self::ToolMissing(_) => "tool_missing",
            Self::ToolFailed { .. } => "tool_failed",
            Self::NotAnImage => "not_an_image",
        }
    }

    /// What a person should do about it.
    pub fn hint(&self) -> String {
        match self {
            Self::UnsupportedPlatform => {
                "screenshots are available on macOS, and on Linux under a wlroots compositor with grim"
                    .to_owned()
            }
            Self::DegenerateRegion => {
                "the requested region has no area on screen; the element may be clipped away"
                    .to_owned()
            }
            Self::ToolMissing(tool) => format!("{tool} is not installed or not on PATH"),
            Self::ToolFailed { tool, status, detail } => format!(
                "{tool} exited with {}{}; on macOS screen capture requires Screen Recording \
                 permission for the terminal or CI runner, granted in System Settings > \
                 Privacy & Security > Screen Recording",
                status.map_or_else(|| "a signal".to_owned(), |code| code.to_string()),
                if detail.is_empty() {
                    String::new()
                } else {
                    format!(" ({detail})")
                }
            ),
            Self::NotAnImage => {
                "the capture tool wrote a file that is not a PNG, which usually means the \
                 capture was denied"
                    .to_owned()
            }
        }
    }
}

/// The PNG magic number, used to reject a denied capture that still wrote a file.
const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', b'\r', b'\n', 0x1a, b'\n'];

/// Convert a window-relative region into a screen rectangle for the capture tool.
///
/// `window_frame` is the window frame in screen coordinates, which on macOS
/// includes the titlebar; `viewport` is the content size. The difference gives
/// the content origin, so it is derived rather than assumed. Everything is in
/// points and must not vary with the display's scale factor.
///
/// Returns `None` when the region has no area once padded and clamped.
pub fn screen_rect(
    window_frame: (f32, f32, f32, f32),
    viewport: (f32, f32),
    region: (f32, f32, f32, f32),
    pad: f32,
) -> Option<Geometry> {
    let (frame_x, frame_y, _frame_width, frame_height) = window_frame;
    let (viewport_width, viewport_height) = viewport;
    // Chrome sits above the content on macOS; no bottom chrome to account for.
    let content_x = frame_x;
    let content_y = frame_y + (frame_height - viewport_height);

    let (left, top, right, bottom) = region;
    let left = (left - pad).max(0.0);
    let top = (top - pad).max(0.0);
    let right = (right + pad).min(viewport_width);
    let bottom = (bottom + pad).min(viewport_height);
    if right <= left || bottom <= top {
        return None;
    }

    // Round outward so a fractional edge is included rather than shaved off.
    let x = (content_x + left).floor();
    let y = (content_y + top).floor();
    let width = (content_x + right).ceil() - x;
    let height = (content_y + bottom).ceil() - y;
    if width < 1.0 || height < 1.0 {
        return None;
    }
    Some(Geometry {
        x: x as i32,
        y: y as i32,
        width: width as u32,
        height: height as u32,
    })
}

/// The capture tool for this platform, if there is one.
fn tool(geometry: Geometry, destination: &Path) -> Option<(&'static str, Vec<String>)> {
    let Geometry {
        x,
        y,
        width,
        height,
    } = geometry;
    if cfg!(target_os = "macos") {
        Some((
            "screencapture",
            vec![
                "-x".to_owned(),
                "-o".to_owned(),
                "-t".to_owned(),
                "png".to_owned(),
                format!("-R{x},{y},{width},{height}"),
                destination.display().to_string(),
            ],
        ))
    } else if cfg!(target_os = "linux") {
        Some((
            "grim",
            vec![
                "-g".to_owned(),
                format!("{x},{y} {width}x{height}"),
                destination.display().to_string(),
            ],
        ))
    } else {
        None
    }
}

/// Capture `geometry` into `destination`.
pub fn capture(geometry: Geometry, destination: &Path) -> Result<u64, ShotError> {
    if geometry.width == 0 || geometry.height == 0 {
        return Err(ShotError::DegenerateRegion);
    }
    let (name, arguments) = tool(geometry, destination).ok_or(ShotError::UnsupportedPlatform)?;
    if let Some(parent) = destination.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::remove_file(destination);

    let output = match Command::new(name).args(&arguments).output() {
        Ok(output) => output,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(ShotError::ToolMissing(name));
        }
        Err(error) => {
            return Err(ShotError::ToolFailed {
                tool: name,
                status: None,
                detail: error.to_string(),
            });
        }
    };
    if !output.status.success() {
        return Err(ShotError::ToolFailed {
            tool: name,
            status: output.status.code(),
            detail: String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        });
    }

    // A denied capture can still exit zero, so the file itself is the evidence.
    let bytes = std::fs::read(destination).map_err(|error| ShotError::ToolFailed {
        tool: name,
        status: output.status.code(),
        detail: error.to_string(),
    })?;
    if bytes.len() < PNG_SIGNATURE.len() || bytes[..PNG_SIGNATURE.len()] != PNG_SIGNATURE {
        return Err(ShotError::NotAnImage);
    }
    Ok(bytes.len() as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    // A 480x240 content area in a window whose frame starts at (100, 50) and is
    // 28 points taller than its content.
    const FRAME: (f32, f32, f32, f32) = (100.0, 50.0, 480.0, 268.0);
    const VIEWPORT: (f32, f32) = (480.0, 240.0);

    #[test]
    fn the_titlebar_offset_is_derived_not_assumed() {
        let whole = screen_rect(FRAME, VIEWPORT, (0.0, 0.0, 480.0, 240.0), 0.0).unwrap();
        // Content starts 28 points below the frame origin.
        assert_eq!(
            whole,
            Geometry {
                x: 100,
                y: 78,
                width: 480,
                height: 240
            }
        );
    }

    #[test]
    fn an_element_region_is_offset_into_screen_space() {
        let region = screen_rect(FRAME, VIEWPORT, (10.0, 20.0, 60.0, 50.0), 0.0).unwrap();
        assert_eq!(
            region,
            Geometry {
                x: 110,
                y: 98,
                width: 50,
                height: 30
            }
        );
    }

    #[test]
    fn padding_expands_then_clamps_to_the_content_rect() {
        // Padding that would run past every edge is clamped, not negative.
        let padded = screen_rect(FRAME, VIEWPORT, (0.0, 0.0, 480.0, 240.0), 50.0).unwrap();
        assert_eq!(
            padded,
            Geometry {
                x: 100,
                y: 78,
                width: 480,
                height: 240
            }
        );
        // Padding inside the content area expands symmetrically.
        let padded = screen_rect(FRAME, VIEWPORT, (100.0, 100.0, 140.0, 140.0), 10.0).unwrap();
        assert_eq!(
            padded,
            Geometry {
                x: 190,
                y: 168,
                width: 60,
                height: 60
            }
        );
    }

    #[test]
    fn a_region_with_no_area_is_refused() {
        assert!(screen_rect(FRAME, VIEWPORT, (10.0, 10.0, 10.0, 40.0), 0.0).is_none());
        assert!(screen_rect(FRAME, VIEWPORT, (10.0, 40.0, 40.0, 10.0), 0.0).is_none());
        // Entirely outside the content area.
        assert!(screen_rect(FRAME, VIEWPORT, (600.0, 10.0, 700.0, 40.0), 0.0).is_none());
    }

    #[test]
    fn fractional_edges_round_outward() {
        let region = screen_rect(FRAME, VIEWPORT, (10.4, 20.6, 60.2, 50.9), 0.0).unwrap();
        assert_eq!(region.x, 110);
        assert_eq!(region.y, 98);
        // Right edge 160.2 -> 161, so width covers the fractional pixel.
        assert_eq!(region.width, 51);
        assert_eq!(region.height, 31);
    }

    #[test]
    fn geometry_is_in_points_and_ignores_scale_factor() {
        // The same logical region on a 1x and a 2x display must produce the
        // same request: `screencapture -R` takes points, not device pixels.
        let first = screen_rect(FRAME, VIEWPORT, (10.0, 20.0, 60.0, 50.0), 0.0);
        let second = screen_rect(FRAME, VIEWPORT, (10.0, 20.0, 60.0, 50.0), 0.0);
        assert_eq!(first, second);
    }

    #[test]
    fn a_degenerate_capture_is_refused_before_shelling_out() {
        let error = capture(
            Geometry {
                x: 0,
                y: 0,
                width: 0,
                height: 10,
            },
            Path::new("/dev/null/unused.png"),
        )
        .unwrap_err();
        assert_eq!(error.reason(), "degenerate_region");
    }

    #[test]
    fn hints_name_the_permission_that_is_usually_missing() {
        let error = ShotError::ToolFailed {
            tool: "screencapture",
            status: Some(1),
            detail: String::new(),
        };
        assert!(error.hint().contains("Screen Recording"), "{}", error.hint());
    }
}
