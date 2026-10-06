# Lid Keep-Awake

## Behavior

Add `Lid Keep-Awake: Off/On` to the existing Rofi power menu. Selecting the
row toggles it immediately. Enabling it arms the next lid-close action without
locking or blanking the screen immediately.

While enabled, closing the lid locks the session using `custom-lock-screen`
and turns off all displays. Background processes continue running. Opening
the lid restores the configured monitor layout, turns the displays on, and
disables the mode automatically. The session stays locked until the user
authenticates.

When disabled, the existing clamshell behavior remains in control: closing
the lid disables the internal monitor and opening it reloads the monitor
configuration. The feature works on battery and AC and resets at logout.

## Approach

Use a temporary, named systemd user service holding a native
`systemd-inhibit --what=handle-lid-switch:sleep --mode=block` lock. The service
belongs to the graphical session and has no persistent enablement. Report
the mode as enabled only after the inhibitor has been acquired; service
startup must acknowledge readiness from inside the inhibited command.

The alternatives are a permanent logind lid-policy change, which changes
behavior outside this mode, and a background process with a PID/state file,
which requires additional lifecycle and stale-state handling. The temporary
service keeps state and cleanup in the existing service manager.

Systemd documents separate lid-switch and sleep inhibitors, and releases
inhibitors when the holding process exits:
[Inhibitor Locks](https://systemd.io/INHIBITOR_LOCKS/).

## Integration

- Add one script providing enable, disable, toggle, status, and idle-display
  resume handling. Use the live service state as the source of truth.
- Branch inside `custom-activate-clamshell`, keeping the existing lid bindings
  and one owner for lid actions. Keep-awake takes precedence while active,
  including when external monitors are connected.
- Protect the display-off state against Hypridle's activity resume callback
  while keep-awake is active and the lid is closed. Retain the current idle
  lock and display timeouts, including the user's uncommitted edits.
- After confirmation, explicit Suspend and Hibernate from the power menu
  disable the mode before locking and executing the requested sleep action.
  Cancellation does not change the mode. Reboot and shutdown continue using
  their existing actions; session teardown releases the inhibitor.
- Mode disable stops only this feature's service. It does not remove other
  programs' inhibitors, change power profiles, or modify logind policy.

An explicit sleep request from outside this power menu may be blocked by the
sleep inhibitor. The menu remains the supported way to request sleep while
this mode is enabled.

## Failure handling

If inhibitor acquisition fails, keep the mode off and show an error through
the existing notification tools. Do not claim that lid-close sleep has been
prevented. Serialize feature transitions so rapid toggles and lid events do
not leave an inhibitor active after lid reopening. Invalid script actions
return a failure status.

## Verification

Run shell syntax checks and a small mocked command test covering enable
readiness/failure, toggles, normal clamshell, keep-awake close/open, repeated
events, idle display resume, and confirmed/cancelled explicit sleep. Check
that disabling the feature targets only its own service.

Hardware validation requires the live Hyprland and systemd session: enable,
close the lid with a running background job, reopen, verify that the lock
screen appears and the menu returns to Off, then repeat with an external
monitor. Sandbox checks cannot verify physical lid events.
