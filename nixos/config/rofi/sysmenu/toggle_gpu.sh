#!/usr/bin/env bash
#
# Flip the dGPU between Hybrid and Integrated by editing /etc/supergfxd.conf
# directly, then rebooting. supergfxd reads the new mode from the config on
# next boot and applies it from a clean state.
#
# Why not `supergfxctl -m <mode>`? With logind active, the daemon's default
# action is WaitLogout: it queues the change and waits for the session to end
# before persisting. systemctl reboot kills supergfxd before it writes, so
# the change never lands on disk and boot falls back to Hybrid.
#
# Why sed works on NixOS: /etc/supergfxd.conf is only a /nix/store symlink
# when services.supergfxd.settings is set. With settings = null (our setup
# in devices/g14/g14.nix), the daemon creates the file itself as a regular
# writable file — sed-editing it is fine and survives rebuild.
#
# The post-resume Vfio bounce and the supergfxd ExecStartPre delay live in
# devices/g14/g14.nix (the arch script used to install both imperatively).

source ~/.config/rofi/common/generic.sh

yes=' Yes'
no='󰜺 Cancel'
yesno_options="$yes\n$no"

set_mode() {
    sudo /etc/gpu-set-mode "$1"
}

gpu_mode=$(supergfxctl -g)
case $gpu_mode in
"Integrated")
    chosen="$(_runrofimenu "$yesno_options" "Enable dGPU and reboot?" "")"
    if [[ "$chosen" == "$yes" ]]; then
        set_mode Hybrid
        systemctl reboot
    fi
    ;;
"Hybrid")
    chosen="$(_runrofimenu "$yesno_options" "Use only iGPU and reboot?" "")"
    if [[ "$chosen" == "$yes" ]]; then
        set_mode Integrated
        systemctl reboot
    fi
    ;;
*)
    echo "Hybrid GPU not found or in unknown mode: $gpu_mode"
    exit 1
    ;;
esac
