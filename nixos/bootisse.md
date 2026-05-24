# Boot/freeze issue tracking

ASUS G14 (AMD Phoenix iGPU + NVIDIA dGPU, supergfxd Integrated mode, Hyprland on Wayland, SDDM).

## Symptoms
- System freezes randomly: keybindings stop working, can't open apps, only power-button reboot works.
- Sometimes on boot the keyboard doesn't work at the SDDM greeter — same fix needed (hold power).

## What the logs showed (2026-05-24 investigation)

Two real hard hangs today (journal stops mid-line, no graceful shutdown, no kernel oops/panic/OOM):
- Boot -4: `09:09:38 → 11:27:20`, froze ~3 min after a resume from suspend.
- Boot -3: `11:27:40 → 11:58:06`, froze ~30 min in, no recent suspend.

Other short-lived boots are config-test reboots, not freezes.

### Findings
- DCN3.14 (Phoenix) panel power-gating timeouts on every boot and resume:
  `[drm] REG_WAIT timeout 1us * 1000 tries - dcn314_dsc_pg_control line:264..288`
- PSR is active: `[drm] PSR support 1, DC PSR ver 0, sink PSR ver 4`.
- Kernel cmdline has `pcie_aspm=powersave`.
- SDDM greeter `weston` has SIGABRT'd twice in `gl-renderer.so` / `libdrm_amdgpu.so.1` — likely cause of "keyboard dead at login" (greeter is dead, not the kernel).
- Noise (not a freeze cause): `/etc/udev/rules.d/99-nvidia-ac.rules` fires on every power_supply change (BAT0/ADP0/USBC) trying to start a non-existent `nvidia-powerd.service` — 314 failed events in ~24h.
- Kernel cmdline carries `nvidia-drm.modeset=1 nvidia-drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1` even though the dGPU is removed from PCI in Integrated mode.

Primary hypothesis: AMD DCN3.14 + PSR (+ possibly ASPM) is causing "frozen-but-still-running" hangs — kernel alive, compositor/input dead → hard reboot only.

## Fix attempts (try one at a time, give each ~1 day of use)

### Attempt 1: Disable AMD PSR — IN PROGRESS (applied 2026-05-24)
Added `amdgpu.dcdebugmask=0x10` to `boot.kernelParams` in `configuration.nix`.
- Verify after reboot: `cat /proc/cmdline | grep dcdebugmask` and `dmesg | grep -i psr` should show PSR disabled.
- Watch for: any freeze in next ~24h of normal use (including suspend/resume cycles).
- Result: _pending_

### Attempt 2 (if #1 doesn't help): Drop `pcie_aspm=powersave`
Either remove the line or set `pcie_aspm=default`. Phoenix ASPM transitions have known regressions.

### Attempt 3 (if #2 doesn't help): Fix the nvidia-powerd udev rule
Restrict to `KERNEL=="ADP0"` and only when `nvidia-powerd.service` exists. Or stop pulling the rule in via `services.xserver.videoDrivers = [ "nvidia" ]` while in Integrated mode.

### Attempt 4 (independent — for greeter freeze): SDDM off Wayland
If keyboard-dead-at-login keeps happening: `services.displayManager.sddm.wayland.enable = false;` or move to `greetd` + `tuigreet`. Sidesteps the weston-greeter crash.

## Notes
- Skipped removing the `powerManagement.resumeCommands` Vfio→Integrated bounce for now — it's load-bearing per the comment in `devices/g14/g14.nix` ("G14 wakes from suspend with the dGPU re-attached"). Revisit if #1–#3 don't fix it.
