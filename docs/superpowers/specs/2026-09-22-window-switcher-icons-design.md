# Window Switcher Icons Design

## Goal

Make the SUPER+P window list faster to scan by showing each application's icon instead of its name, while keeping the application name searchable.

## Display and behavior

Each mapped, non-special Hyprland client remains one Rofi row. The visible row contains:

`app icon — window title — workspace number`

The workspace is shown as its compact identifier, such as `3`, rather than `workspace 3`. Existing focus-history ordering, special-workspace filtering, selection by client index, and focus dispatch remain unchanged.

## Implementation

`nixos/config/rofi/window/window.sh` will emit Rofi dmenu row metadata alongside each visible label:

- `icon` uses the first resolvable icon in this order: the client's window class, the `Icon=` value from a matching installed desktop entry, then a generic application icon. If an application has no desktop entry, its class remains the icon candidate before the generic fallback.
- `meta` contains the application name/class so Rofi's matching can find it without rendering it in the row.

Desktop entries and icons are discovered from the standard XDG data locations already available in the session. A desktop entry may match by `StartupWMClass`, desktop-file name, or the final component of a reverse-domain window class such as `md.Obsidian`. Icon resolution is performed once per distinct window class when the menu opens.

This uses Rofi's native dmenu metadata protocol and existing icon files. No dependency or per-application alias list is added.

## Edge cases

- Empty window titles continue to display `[untitled]`.
- Applications without desktop entries continue to use a directly resolvable class icon.
- Missing or unresolvable application classes and desktop icons use a generic application icon and retain `[unknown app]` as searchable metadata where applicable.
- Tabs, carriage returns, and newlines are normalized so they cannot split or corrupt Rofi rows.
- Workspace names or IDs are rendered directly without the `workspace ` prefix.

## Verification

- Run a shell syntax check on the modified script.
- Feed representative Hyprland client data through the row-formatting expression and verify visible labels and Rofi `icon`/`meta` metadata.
- Verify direct class icons, desktop-entry icon fallbacks, reverse-domain classes, and clients without desktop entries.
- Confirm the client array and selected index remain aligned.
