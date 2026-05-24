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

### Attempt 4 — switch to 6.12 LTS — IN PROGRESS (applied 2026-05-24)
MT7922 BT fix `e3ac0d9f1a20` is confirmed in **6.12.91** (verified via direct grep of `cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.12.91`). Our MT7922 is vendor `0489:e0f6` — covered by the fix. Changed `boot.kernelPackages = pkgs.linuxPackages_6_6` → `linuxPackages_6_12`.

What this brings beyond the BT fix:
- 18 months of amdgpu work between 6.6 and 6.12, incl. mainline `disable_dsc_power_gate=true` patch for the `dcn314_dsc_pg_control` warnings.
- Lots of Phoenix suspend/resume stabilization.

Why this is the highest-ROI attempt: the same hardware/config works on Arch (mainline). Kernel version is the biggest delta.

Avoided: 6.18.y (G14 amdgpu boot crash reports since 6.18.7, [Arch BBS 311920](https://bbs.archlinux.org/viewtopic.php?id=311920)). 7.0.y also fixed but stable-branch-only, drops support when next mainline lands ~July 2026.

Verify after reboot:
- `uname -r` → `6.12.91` or newer
- `bluetoothctl show` → bluetooth functional, no `-22` errors in `dmesg | grep btmtk`
- `dmesg | grep dcn314_dsc_pg_control` → should be silent
- Use the system normally for ~24h including suspend/resume cycles — watch for freezes

Result: _pending_

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
