# Boot/freeze issue tracking

ASUS G14 (AMD Phoenix 780M iGPU using DCN3.14 + NVIDIA dGPU, supergfxd Integrated mode, Hyprland on Wayland, SDDM-Wayland greeter, kernel 6.6.140 LTS).

**Important context:** the same hardware/config works on Arch by default. Failure is NixOS-specific (or at least specific to this stack), which shifts suspicion from "fundamental config wrong" to "kernel/userspace version skew".

## Symptoms
- Random hard freezes: keybindings dead, no new windows, only power-button reboot works.
- Sometimes at the SDDM greeter the keyboard is dead — same fix needed.
- Kernel/journal often keeps running for some seconds (asusd heartbeat) after compositor/input dies — classic "frozen-but-running" pattern.
- No kernel panic, no oops, no MCE, no thermal trip, no soft lockup, no `Hardware Error`. Journal just cuts mid-line.

## Investigation log (2026-05-24)

### Run 1 — initial diagnosis
Looked at journal across 4 prior boots. Two confirmed hard hangs:
- 09:09:38 → 11:27:20 (froze ~3 min after resume from suspend)
- 11:27:40 → 11:58:06 (froze ~30 min in, no recent suspend)

Findings on every boot/resume:
- `[drm] REG_WAIT timeout 1us * 1000 tries - dcn314_dsc_pg_control line:264/272/280/288`
- `[drm] PSR support 1, DC PSR ver 0, sink PSR ver 4`
- Greeter weston has SIGABRT'd twice in `gl-renderer.so` / `libdrm_amdgpu.so.1` — explains keyboard-dead-at-login (greeter dead, not kernel).
- Noise (not a cause): `/etc/udev/rules.d/99-nvidia-ac.rules` fires on every BAT0/ADP0/USBC change, fails to start non-existent `nvidia-powerd.service` (314 events in ~24h).

### Attempt 1 — Disable AMD PSR (FAILED to stop freezes)
Added `amdgpu.dcdebugmask=0x10` to `boot.kernelParams`. **Correctly disabled PSR** on 6.6 (confirmed: no `PSR support` line in subsequent boot; kernel source `drivers/gpu/drm/amd/include/amd_shared.h` at v6.6 shows `DC_DISABLE_PSR = 0x10` — `DC_DISABLE_PSR_SU` doesn't exist until 6.8).

Result: **two more hard hangs the same day, both with PSR disabled.**
- 13:33:47 → 15:07:58 (~1.5h, no recent suspend, last lines: asusd heartbeat + ADP0 udev kick)
- 15:08:26 → 15:09:48 (~1.5 min, froze right after greeter login, no precipitating event in logs)

Both: shutdown_targets=0, oops=0, no kernel-level errors before the cut. Confirmed hard hangs.

→ PSR is unlikely to be the (sole) cause. Leaving the param in for now since it costs ~nothing, removing it later when actual cause found.

### Attempt 2 (planned: drop `pcie_aspm=powersave`) — INVALIDATED
Investigation showed this param is a **no-op as written**: kernel 6.6 only accepts `pcie_aspm=off|force`, not `=powersave`. Effective ASPM policy is `[default]` (BIOS). L1 ASPM is enabled on some buses (NVMe / wireless on 02/03/04) from BIOS default, not from our cmdline. So "drop the line" doesn't change anything.

Side-effect cleanup needed:
- Correct syntax for policy is `pcie_aspm.policy=powersave` (module param form). Replacing the existing line with this gets the actually-intended powersave behavior with no battery cost. Not a fix for the freeze.
- For actual freeze-bisect of ASPM, use `pcie_aspm=off` for one session (real battery cost, but conclusive).

### What's been ruled out
- **PSR** — disabled, still freezes.
- **ASPM-as-bug** — we never actually had aggressive ASPM (param was invalid). BIOS default ASPM has been on all along, including on Arch where the system worked. Weak suspect.
- **DMUB/PSP firmware** — current `linux-firmware-20260410` ships `dcn_3_1_4_dmcub.bin`, kernel confirms `DMUB hardware initialized: version=0x08005700`. Up to date.
- **NVIDIA driver hangs** — only `nvidia_wmi_ec_backlight` loaded (WMI shim, harmless), main `nvidia` / `nvidia_drm` modules NOT loaded (supergfxd Integrated mode is working). Cmdline `nvidia-drm.modeset=1` etc. are no-ops.
- **`dcn314_dsc_pg_control` REG_WAIT** — known DSC power-gate quirk; mainline fix `disable_dsc_power_gate=true` (amd-gfx July 2025, landed ~6.12/6.13). Not in 6.6. Fires during init, not at freeze instant. Noise marker, not the cause.

## Current hypothesis

**Kernel version mismatch.** Works on Arch (latest mainline, ~6.12+); fails on NixOS pinned to 6.6 LTS. Lots of Phoenix display + suspend/resume fixes landed between 6.6 and 6.12. We can't move past 6.6 because of the MT7922 Bluetooth regression (see comment in `configuration.nix`), unless that has been backported to 6.12.y stable by now.

## Next attempts (in order of expected ROI)

### Attempt 3 — fix the no-op pcie_aspm line (correctness, not a freeze fix)
Replace `"pcie_aspm=powersave"` with `"pcie_aspm.policy=powersave"`. Apply the actually-intended ASPM powersaving. Won't fix freezes but stops misleading future investigations.

### Attempt 4 — switch to 6.12 LTS — BLOCKED, REVERTED (2026-05-24)
Switched `linuxPackages_6_6` → `linuxPackages_6_12`. Got **6.12.90**, which is exactly one point release behind the fix: `e3ac0d9f1a20` landed in 6.12.91 (released 2026-05-23). On reboot:
```
Bluetooth: hci0: Failed to send wmt func ctrl (-22)
hci0: ... DOWN
No default controller available
```
nixpkgs lag confirmed by checking both channels:
- `nixos-25.11` → 6.12.90 / 7.0.9
- `nixos-unstable` → 6.12.90 / 7.0.9
Both broken branches; neither has the fix yet. Reverted to `linuxPackages_6_6` (6.6.140 — never affected by the btmtk regression).

Superseded by Attempt 4b — went straight to 6.18.33 via src override instead of waiting for nixpkgs.

### Attempt 4b — 6.18.33 via src override (2026-05-24)
Same nixpkgs-lag situation on 6.18: ships `linux_6_18` at 6.18.32 (one patch short of fix `e3ac0d9f1a20`, which is in 6.18.33). Rather than wait for nixpkgs to bump, override `linux_6_18.src` to the upstream 6.18.33 tarball from cdn.kernel.org. Patch-level bump (32→33) so all of nixpkgs's 6.18 patches still apply cleanly.

Picked 6.18 over 6.12.91 because:
- Same BT fix is in both, same override-shape cost.
- 6.18 has ~6 more months of Phoenix amdgpu fixes than 6.12 — better chance of resolving the freezes, which is the actual goal.
- 6.18 includes `disable_dsc_power_gate=true` default (kills the `dcn314_dsc_pg_control` REG_WAIT noise).

Cost: ~30–60 min first compile, then cached.

Watch on next freeze run:
- Did `Failed to send wmt func ctrl` go away? (BT working = override applied correctly)
- Did the hard hangs go away? (real test)
- Is `dcn314_dsc_pg_control` REG_WAIT gone from journal? (sanity check we're on 6.18)

### Attempt 5 — binary-search ASPM
One boot with `pcie_aspm=off`. If freezes stop, ASPM is involved. Real battery cost while testing.

### Attempt 6 — capture more on the next freeze
Add to `boot.kernelParams`:
- `drm.debug=0x1e` (atomic + driver + KMS)
- `amdgpu.dyndbg="+p"` (enable amdgpu dynamic debug prints)
- Persistent journal (already on?) so last messages survive the hard reset

Tradeoff: very chatty log. Only worth it once everything else is exhausted.

### Attempt 7 (independent — for greeter freeze): SDDM off Wayland
If keyboard-dead-at-greeter keeps happening: `services.displayManager.sddm.wayland.enable = false;` or move to `greetd` + `tuigreet`. Sidesteps the weston-greeter SIGABRT.

## New symptom class — 2026-05-25 (kernel 6.18.33)

After moving to 6.18.33 (Attempt 4b applied), got a freeze with a *different* shape:
- **Existing windows stayed interactable** — could scroll/click inside Brave + nautilus.
- **Hyprland binds dead** — SUPER+keys did nothing (couldn't bring up rofi).
- **Waybar icon clicks dead** — clicking a launcher icon on waybar did nothing.
- **No new windows could be spawned** at all (any path: bind, waybar, scripted).
- Hard reset via power button (no path back to login).

Journal cut at 09:55:15 from user session; system journal (asusd heartbeat etc.) kept going till 09:57:10 — so kernel/system was alive ~2 minutes after the user session went dark. Not a kernel hang.

**What this means:** input forwarding to focused surfaces still works, but Hyprland's main-loop dispatch path is wedged (binds + IPC + spawn all block). Classic "compositor main thread stuck on a blocking syscall" pattern. The pixman_region32_init_rect spam from boot is unrelated (fires at 09:41:46 init, not 09:55).

**Suspects (new):**
- `xdg-desktop-portal-gtk` SIGSEGV'd 2026-05-24 21:11 (coredump on disk). Portal calls were still firing at 09:55:00/09:55:15 (the two "Inhibiting other than idle not supported" lines were the last user-session log entries). A wedged portal can stall any client that makes a sync portal call — and if Hyprland's main thread initiates a portal call (e.g. for GlobalShortcuts) and the broker takes too long, the whole compositor stalls.
- uwsm-app spawn path: every launch goes `keybind → Hyprland → exec → uwsm-app → systemd-run --user → user dbus`. If user dbus is stuck (e.g. on a portal call), all spawns block — Hyprland itself doesn't normally synchronously wait, but waybar's click handlers and other helpers will.
- **Hyprland logs are disabled by default** — `debug:disable_logs=true` means we have no record of what dispatcher fired right before the wedge. Need to flip this before we can pin a cause.

### Attempt 5 — drop gtk portal + enable Hyprland logs + install snapshot timer (2026-05-25)

Three changes shipped:

1. **Dropped `xdg-desktop-portal-gtk`** from `configuration.nix` extraPortals, and dropped `xdg.portal.config.common.default = "*"`. gtk portal's `UseIn=gnome` so without the wildcard default it wouldn't be picked for Hyprland anyway — the wildcard was forcing it in. Now only `xdg-desktop-portal-hyprland` (auto from `programs.hyprland.enable`) + `gnome-keyring.portal` are active. Screen sharing unaffected (hyprland portal owns ScreenCast/Screenshot/GlobalShortcuts). FileChooser/Settings interfaces now unserved — flatpak file pickers may fall back, native GTK/Qt apps unaffected (they don't use portal FileChooser by default).

2. **Enabled Hyprland debug logs** via new `nixos/config/hypr/debug.conf` (`debug { disable_logs = false }`) sourced from `hyprland.conf`. Output goes to the journal under `uwsm_Hyprland[<pid>]` and to `/run/user/1000/hypr/<sig>/hyprland.log`. Hyprland config file change only — picked up on next session start (or `hyprctl reload`), no nixos-rebuild needed.

3. **System-level freeze-snapshot timer** added to `configuration.nix`: writes a snapshot of user-process state to `/var/log/freeze-snapshots/` every 30s. Runs as root from system systemd so a wedged user bus / Hyprland can't block it. Captures `ps -L` with wchan, `/proc/<hyprland>/wchan` per-thread, `lsof` of Hyprland sockets, a `timeout 2 hyprctl version` ping (non-zero exit = wedged), and dmesg errors. Files age out after 1d.

On next freeze: post-reboot, read the *most recent* file in `/var/log/freeze-snapshots/` — the one timestamped just before the journal goes dark shows what each Hyprland thread was blocked on (wchan), whether IPC was already wedged, and what unix sockets were open. Combined with the Hyprland debug log tail, this should let us pin which dispatcher / which portal call / which child wait was the trigger.

Watch on next freeze:
- Does the freeze still happen with gtk portal gone? (if no → gtk portal was the cause)
- Last snapshot's `hyprctl exit` field: was IPC already wedged?
- Last snapshot's Hyprland-thread wchans: are any blocked in `futex_wait`, `epoll_wait` on a known fd, `do_sys_poll` on the dbus socket?
- Hyprland journal log tail: which dispatcher was last invoked?

### Attempt 5 — outcome (2026-05-26)

Freeze recurred at ~14:55 IST despite gtk portal removed. So **gtk portal is NOT the trigger** — ruled out.

What the snapshots showed:
- Last successful snapshot at 14:54:48: Hyprland main thread in `do_epoll_wait`, all worker threads in `futex_do_wait` (normal idle state). `hyprctl version` exit=0. **System internally healthy at this point.**
- Next scheduled snapshot would have been 14:55:18, but the user power-keyed at 14:55:04 (16s after last good snapshot), so no snapshot caught the wedge state.
- Journal: `Lid opened.` at 14:55:02 → `Power key pressed short.` at 14:55:04. The user had the lid closed from 10:23:21 (4.5 hours of lid-closed runtime).
- Two auto-suspend cycles in this boot: 13:22→13:33 and **14:41:25 → 14:45:07** (s2idle). The freeze symptoms appeared ~10 min after the second resume.

This **matches** the earlier "froze ~3 min after resume from suspend" data point from Run 1. Suspend/resume is now a strong contributory suspect — but not exclusive (we have prior freezes with no recent suspend too).

**Cannot disambiguate from this freeze alone:**
1. Whether Hyprland's main loop actually wedged in those 16 seconds, OR
2. Whether the user opened the lid, saw no display output (a display-wake bug), and power-keyed reflexively before testing inputs.

**Gap in instrumentation:** Hyprland's debug log lives at `/run/user/1000/hypr/<sig>/hyprland.log` — tmpfs, wiped on reboot. Had `debug:disable_logs=false` on but lost everything on the forced reboot.

### Boot -1 weston SIGABRT (2026-05-26) — recurrence of Run-1 greeter bug

After the user power-keyed the wedged session, the next boot got stuck before SDDM displayed and had to be power-cycled again. Cause:

- 14:56:07 SDDM started weston-kiosk greeter (Mesa 25.2.6, kernel 6.18.33, AMD Radeon 780M)
- 14:56:08 weston SIGABRT'd — stack: `__assert_fail` → `atomic_flip_handler` (drm-backend.so) → `drmHandleEvent` (libdrm.so.2) → `on_drm_input`. Weston aborts on its first atomic page-flip event.
- No greeter visible → user power-cycled at 14:56:59.

Same crash class as documented in Run 1 (weston greeter SIGABRT in gl-renderer.so / libdrm_amdgpu.so.1). Fix is sitting in Attempt 7 (set `services.displayManager.sddm.wayland.enable = false`). User opted to leave it for now since it only manifests on the boot-after-wedge path; will revisit if it becomes routine.

### Attempt 6 — better instrumentation (2026-05-26)

Changes to freeze-snapshot:
1. **Copy Hyprland's tmpfs log to `/var/log/freeze-snapshots/<ts>.hyprland.log` every 30s.** Persistent across reboots.
2. **IPC ping now uses `hyprctl activeworkspace` instead of `version`.** activeworkspace exercises more of the dispatch path; `version` is a static-string handler. If main loop is wedged, this should catch it where version wouldn't.
3. **Snapshot now includes the last 10 suspend/resume/lid events** so we don't have to cross-reference journalctl.

Watch on next freeze:
- Most recent `*.hyprland.log` in `/var/log/freeze-snapshots/` — what was the last dispatcher to fire? Any error/warning before silence?
- Newest snapshot's "last suspend/resume" block — did a suspend happen shortly before the freeze?
- `hyprctl activeworkspace` exit status across the last 3-4 snapshots — when did it first start hanging?

### Freeze 2026-05-27 11:25 — ROOT CAUSE FOUND: envfs FUSE hang

User reported during the wedge: browser still usable, keyboard switching between Hyprland workspaces still works, **but new terminals don't start, `df -kH` hangs, `ls`/`cd` (bash builtins) still work, waybar buttons that exec scripts don't fire.** That symptom set is "anything needing a new process hangs; anything purely in-process is fine."

Snapshots:
- `20260527-112448.log` (last good): IPC `hyprctl exit=0`, Hyprland in `do_epoll_wait` (healthy). Dmesg tail in this same snapshot ALREADY shows the smoking gun:
  ```
  [Wed May 27 11:23:59] INFO: task pet:69745 blocked for more than 122 seconds.
  ```
  So the freeze began ~11:21:57 (122s before the warning).
- `20260527-112518.log` and `.hyprland.log`: **0 bytes**. The freeze-snapshot script itself couldn't even write `=== date ===` (its first echo). Means the snapshot shell — running as root — also couldn't make progress as soon as it tried to `pgrep`/`ps` (which `stat` PATH entries via envfs).
- Then nothing until reboot at 11:27.

Full kernel stack for the `pet` D-state thread (from journal of previous boot):
```
__do_sys_newstat
  → vfs_statx → filename_lookup → path_lookupat → walk_component → lookup_fast
    → fuse_dentry_revalidate → __fuse_simple_request → request_wait_answer → schedule
```

`pet` is `/home/malay/.vscode/extensions/ms-python.vscode-python-envs-1.20.1-linux-x64/python-env-tools/bin/pet server` — the python-envs VS Code extension's environment discovery daemon. It periodically `stat()`s python interpreters across PATH, which includes `/usr/bin` and `/bin`. Both are envfs FUSE mounts (`services.envfs.enable = true;`):

```
envfs on /usr/bin type fuse (ro,nosuid,nodev,relatime,user_id=0,group_id=0,...)
envfs on /bin     type fuse (ro,nosuid,nodev,relatime,user_id=0,group_id=0,...)
```

What broke: the userspace `mount.envfs` daemon (PID 929 in the wedged boot) stopped replying to FUSE requests. No crash log, no OOM, no journal message about it dying — it simply went unresponsive. Once that happens, **every** subsequent `stat`/`open`/`readlink` on a path under `/usr/bin/*` or `/bin/*` blocks in D state in `request_wait_answer`. There's no timeout — D-state waits for FUSE replies are uninterruptible.

Cascade once envfs wedged:
- Bash builtins (`ls`/`cd` on cwd not under /usr or /bin) → still work.
- Anything that walks `$PATH` (new shell, `df`, `which`, waybar button scripts, `pgrep` from the snapshot script) → blocks at first `/usr/bin/...` stat. Forever.
- Existing processes (browser, Hyprland epoll loop, IPC handlers that don't touch fs) → keep running. Hence IPC returned 0 *and* the workspace switching still worked.

**This is the same shape as previous "freezes" too.** The recurring pattern was always: last-good snapshot shows compositor healthy + IPC responding, but nothing on the user side can be invoked. We've been chasing a Hyprland/amdgpu bug for weeks; the compositor was a victim, not the cause.

Suspend/resume correlation in Run 1 (earlier freezes after resume) is now explainable too: resume kicks PATH-traversing background work (xdg autostart, dbus activations, asusd polling external scripts), any of which can be the first thing to hit the wedged FUSE mount.

### Attempt 8 (planned) — kill envfs

Set `services.envfs.enable = false;` in `configuration.nix`. Rationale:
- `programs.nix-ld.enable = true;` already covers the dynamic-linker shim half of "make non-Nix binaries work."
- `/usr/bin/env` works in NixOS without envfs (it's symlinked to the coreutils env via system activation).
- Things that hard-code `/usr/bin/<tool>` paths are rare and fixable per-case (wrappers, `programs.<tool>.enable`, or patching the script).
- The python-envs VS Code extension's `pet` will lose its envfs-mediated view of `/usr/bin`. It still works via `$PATH`-relative discovery; will just see fewer pythons. Acceptable.

Drop everything in one toggle. The risk is small ("might lose a `/usr/bin/foo` shim somewhere"); the reward is large ("kernel can never wedge here again").

## Notes
- `powerManagement.resumeCommands` Vfio→Integrated bounce in `devices/g14/g14.nix` is load-bearing per its comment ("G14 wakes from suspend with the dGPU re-attached"). Don't touch.
- Reference threads if more ammo needed: Ubuntu LP #2024774, drm/amd issue #2227, Arch BBS 298760, Framework community thread on 780M amdgpu issues.
