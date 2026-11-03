# Workspace UI design

The app uses a restrained native macOS style. System colors and controls remain the source of truth for light, dark, increased contrast, keyboard focus, and macOS appearance changes. New workspaces default to the static System background; existing theme preferences are preserved.

## Shared parts

- `workspaceFont` applies the selected workspace text scale with a 12 point floor.
- `workspaceSurfaceBackground` respects the user's Surface Opacity setting.
- `workspaceCard` adds the common 8 point card shape and subtle border to that surface.
- `WorkspaceSearchField` wraps macOS `NSSearchField`, including its native search and clear controls. Keep screen-specific prompts and accessibility identifiers at the call site.
- Dev Mode uses native menus for project and conversation actions, a grouped settings form, and a system progress indicator for active work.
- Dev Mode chat uses a plain transcript for Codex responses and content-sized, trailing bubbles for user messages. The activity indicator uses a system progress view with a subtle symbol effect, and Reduce Motion disables that effect.
- The Dev Mode composer receives focus on entry and submits with Return through the same permission checks as its Send button.
- During a Codex turn, intermediate agent messages appear only beside the working indicator. The chat stores the last agent message as its answer after a completed turn; failed or unconfirmed turns do not turn progress text into an answer.

Use these pieces for new workspace screens. Keep native buttons, pickers, search fields, and `ContentUnavailableView` for their built-in keyboard and accessibility behavior. Put actions next to the content they affect and keep state descriptions in text as well as color.

## Review checklist

Check each destination at narrow and wide window sizes, in light and dark appearance, with larger text, Reduce Motion, keyboard navigation, and VoiceOver. Confirm labels and focus order for icon-only actions. Verify contrast and text readability with the Surface Opacity setting at its lowest value. Code structure alone does not establish WCAG 2.1 conformance.
