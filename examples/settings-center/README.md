# Settings Center

A polished control-center application for editing a substantial hierarchy of
typed preferences with safe preview, apply, revert, and persistence behavior.

The implemented profile path loads and atomically saves through an app-scoped
capability on worker tasks. Request identities keep obsolete completions from
overwriting a newer draft.

## Appearance

A control centre read by scanning. `Render.roc` holds one palette and a four-step
type scale — window title, panel title, a setting's own name and a form value,
and everything explanatory below that — so a heading, a name, and the line
describing it are never within two points of each other.

A catalogue row is a name over one line saying what the setting does, separated
from the next by a hairline. The category is its own field rather than a prefix
glued onto every name, which is what lets a category chip be a real filter that
composes with the search rather than being a search for the category's own word.

A status at rest is a sentence with a check mark, not a surface. Framing it gave
it exactly the shape of the text fields above it, so "Settings are saved" read as
one more thing to type in. Only a state waiting on an action — a storage failure
with its Retry, a validation message the Apply button is held back by — is
framed, and then in the failure colour.

Apply and Revert are a pair acting on the draft in front of the person. Reload
discards that draft and re-reads the store, so it sits apart at the far edge
rather than third in a row of three identical-looking buttons.

## Core capabilities

- A searchable catalogue narrowed by a category chip and a query that compose.
- A profile form with inline validation, dirty-state tracking, apply, and revert.
- Durable atomic saves through an app-scoped capability on worker tasks, with
  request identities so an obsolete completion cannot overwrite a newer draft.
- A modal rename whose Cancel cancels, and a managed setting shown as locked
  rather than silently ignored.
- A layout that holds together at three window sizes.

## Happy paths

- Find a setting by its name, its summary, or its category; hold a category and
  narrow it further with a query; release either without disturbing the other.
- Edit the profile, review its changed state, apply it, and reload it back.
- Empty the catalogue and be told which of the two narrowings emptied it, with
  one button that releases both.

## Error paths

- Invalid values identify the owning control and prevent only the unsafe apply operation.
- Failed or interrupted saves preserve the last valid configuration and the user's pending edits.
- Unsupported settings are shown as unavailable rather than silently ignored or recorded as defaults.

## High-level goals

- Become the comprehensive forms, validation, navigation, theme, and preference example.
- Establish atomic persistence and consistent dirty/apply/revert interaction patterns.
- SCM specs cover search, category composition, an empty result, validation, apply, revert, reload, a stale completion, a storage failure and its retry, the rename dialog, and the layout at three window sizes.
- A scaling case contains a realistic breadth of categorized settings and search terms.
