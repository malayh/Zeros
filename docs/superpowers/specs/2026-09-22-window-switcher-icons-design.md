# Window Switcher Icons Design

## Goal

Make the SUPER+P window list faster to scan by showing each application's icon instead of its name, while keeping the application name searchable.

## Display and behavior

Each mapped, non-special Hyprland client remains one Rofi row. The visible row contains:

`app icon — window title — workspace number`

The workspace is shown as its compact identifier, such as `3`, rather than `workspace 3`. Existing focus-history ordering, special-workspace filtering, selection by client index, and focus dispatch remain unchanged.

## Implementation

`nixos/config/rofi/window/window.sh` will emit Rofi dmenu row metadata alongside each visible label:

- `icon` names the application icon using the client's window class, falling back to its initial class and then a generic application icon.
- `meta` contains the application name/class so Rofi's matching can find it without rendering it in the row.

This uses Rofi's native dmenu metadata protocol and the existing Papirus icon theme. No dependency or shared-menu abstraction is added.

## Edge cases

- Empty window titles continue to display `[untitled]`.
- Missing application classes use a generic application icon and retain `[unknown app]` as searchable metadata.
- Tabs, carriage returns, and newlines are normalized so they cannot split or corrupt Rofi rows.
- Workspace names or IDs are rendered directly without the `workspace ` prefix.

## Verification

- Run a shell syntax check on the modified script.
- Feed representative Hyprland client data through the row-formatting expression and verify visible labels and Rofi `icon`/`meta` metadata.
- Confirm the client array and selected index remain aligned.
