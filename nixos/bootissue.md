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

## Notes
- `powerManagement.resumeCommands` Vfio→Integrated bounce in `devices/g14/g14.nix` is load-bearing per its comment ("G14 wakes from suspend with the dGPU re-attached"). Don't touch.
- Reference threads if more ammo needed: Ubuntu LP #2024774, drm/amd issue #2227, Arch BBS 298760, Framework community thread on 780M amdgpu issues.
