//! Keystrokes as the application's shortcuts see them.
//!
//! The mounted graph decides which region a keystroke reaches
//! (`MountedGraph::resolve_shortcut`); this module supplies what only GPUI
//! knows: how a chord is spelled, whether a keystroke matches one, and which
//! keystrokes the host's own keymap takes before any application shortcut.
//! Both runners call it, so a semantic run refuses exactly the chords a
//! window would never deliver.

use crate::bridge::NodeKind;
use gpui::{KeyContext, KeybindingKeystroke, Keymap, Keystroke};

/// The canonical spelling of one declared chord, or why it cannot be one.
///
/// A shortcut is one chord, spelled as GPUI spells keybindings. A chord the
/// host's root always takes can never reach an application, so declaring one
/// is refused rather than left silently dead.
pub(crate) fn canonical_chord(written: &str) -> Result<String, String> {
    if written.is_empty() || written.contains(char::is_whitespace) {
        return Err(format!("{written:?} is not one key chord"));
    }
    let keystroke = Keystroke::parse(written).map_err(|error| error.to_string())?;
    let canonical = keystroke.unparse();
    if root_takes(&keystroke) {
        return Err(format!("{canonical} belongs to the host"));
    }
    Ok(canonical)
}

/// A keystroke as the window's platform delivers it for a chord: a printable
/// key with no command modifier carries the character it types.
pub(crate) fn delivered(chord: &str) -> Result<Keystroke, String> {
    Keystroke::parse(chord)
        .map(Keystroke::with_simulated_ime)
        .map_err(|error| error.to_string())
}

/// Whether a keystroke would type a character into a focused text field.
pub(crate) fn types_character(keystroke: &Keystroke) -> bool {
    let modifiers = keystroke.modifiers;
    keystroke.key_char.is_some()
        && !(modifiers.control || modifiers.alt || modifiers.platform || modifiers.function)
}

/// Whether a keystroke matches a declared chord in canonical spelling, by
/// GPUI's own rule for matching a typed keystroke against a keybinding.
pub(crate) fn matches(keystroke: &Keystroke, declared: &str) -> bool {
    Keystroke::parse(declared).is_ok_and(|declared| {
        keystroke.should_match(&KeybindingKeystroke::from_keystroke(declared))
    })
}

/// Whether the host's root takes a keystroke wherever focus is: Tab and
/// Shift-Tab move focus, Escape dismisses, and the App access chord opens the
/// trusted surface.
fn root_takes(keystroke: &Keystroke) -> bool {
    let keymap = Keymap::new(crate::host_bindings());
    let (matched, _) = keymap.bindings_for_input(std::slice::from_ref(keystroke), &[]);
    matched.iter().any(|binding| {
        let action = binding.action();
        action.partial_eq(&crate::FocusNext)
            || action.partial_eq(&crate::FocusPrevious)
            || action.partial_eq(&crate::ActivateEscape)
            || action.partial_eq(&crate::ToggleAppAccess)
    })
}

/// Whether the host takes a keystroke before any application shortcut, with
/// keyboard focus on a control of kind `focused`.
///
/// GPUI offers a keystroke to the keymap's actions along the focus path
/// first, and to key listeners only when no action handled it. This answers
/// from the same keymaps the window installs: the root's own chords, a
/// focused button's or checkbox's activation, a focused text input's editing
/// chords in its key context, and the keys a focused textarea edits with.
pub(crate) fn host_takes(focused: Option<&NodeKind>, keystroke: &Keystroke) -> bool {
    if root_takes(keystroke) {
        return true;
    }
    let keymap = Keymap::new(crate::host_bindings());
    let (matched, _) = keymap.bindings_for_input(std::slice::from_ref(keystroke), &[]);
    let activates = matched.iter().any(|binding| {
        let action = binding.action();
        match focused {
            Some(NodeKind::Button { enabled: true, .. }) => {
                action.partial_eq(&crate::ActivateEnter) || action.partial_eq(&crate::ActivateSpace)
            }
            Some(NodeKind::Checkbox { enabled: true, .. }) => {
                action.partial_eq(&crate::ActivateSpace)
            }
            _ => false,
        }
    });
    if activates {
        return true;
    }
    match focused {
        Some(NodeKind::TextInput { enabled: true, .. }) => {
            let editing = Keymap::new(crate::input::bindings());
            let context = KeyContext::parse("TextInput").expect("the text input's key context");
            let (matched, _) =
                editing.bindings_for_input(std::slice::from_ref(keystroke), &[context]);
            !matched.is_empty() || types_character(keystroke)
        }
        Some(NodeKind::Textarea {
            enabled: true,
            read_only: false,
            ..
        }) => {
            keystroke.key == "backspace" || keystroke.key == "enter" || keystroke.key_char.is_some()
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chords_are_spelled_one_way() {
        assert_eq!(canonical_chord("shift-ctrl-k").unwrap(), "ctrl-shift-k");
        #[cfg(not(target_os = "macos"))]
        assert_eq!(canonical_chord("secondary-k").unwrap(), "ctrl-k");
        assert_eq!(canonical_chord("down").unwrap(), "down");
        assert_eq!(canonical_chord("[").unwrap(), "[");
    }

    #[test]
    fn a_chord_the_host_always_takes_is_refused() {
        for chord in ["tab", "shift-tab", "escape", "secondary-shift-a"] {
            let refused = canonical_chord(chord).unwrap_err();
            assert!(
                refused.contains("belongs to the host"),
                "{chord}: {refused}"
            );
        }
        assert!(canonical_chord("ctrl-k ctrl-j").is_err());
        assert!(canonical_chord("").is_err());
    }

    #[test]
    fn a_typed_character_is_text_and_a_command_chord_is_not() {
        assert!(types_character(&delivered("j").unwrap()));
        assert!(types_character(&delivered("shift-j").unwrap()));
        assert!(!types_character(&delivered("ctrl-j").unwrap()));
        assert!(!types_character(&delivered("down").unwrap()));
    }

    #[test]
    fn a_keystroke_matches_its_declared_chord_however_it_was_spelled() {
        let pressed = delivered("shift-ctrl-k").unwrap();
        assert!(matches(&pressed, &canonical_chord("ctrl-shift-k").unwrap()));
        assert!(!matches(&pressed, "ctrl-k"));
    }

    #[test]
    fn the_focused_control_takes_its_own_keys_first() {
        let button = NodeKind::Button {
            role: crate::bridge::ButtonRole::Button,
            caption: "Go".into(),
            label: "Go".into(),
            enabled: true,
            hover_enter: false,
            hover_exit: false,
            style: Box::default(),
        };
        let input = NodeKind::TextInput {
            label: "Filter".into(),
            value: String::new(),
            placeholder: String::new(),
            enabled: true,
            style: Box::default(),
        };
        let enter = delivered("enter").unwrap();
        assert!(host_takes(Some(&button), &enter));
        assert!(!host_takes(None, &enter));
        assert!(host_takes(Some(&input), &delivered("left").unwrap()));
        assert!(host_takes(Some(&input), &delivered("q").unwrap()));
        assert!(!host_takes(Some(&input), &delivered("down").unwrap()));
        assert!(!host_takes(Some(&input), &delivered("ctrl-k").unwrap()));
        assert!(host_takes(None, &delivered("tab").unwrap()));
    }
}
