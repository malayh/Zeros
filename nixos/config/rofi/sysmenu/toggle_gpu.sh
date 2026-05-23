#!/usr/bin/env bash
#
# Flip the dGPU between Hybrid and Integrated via supergfxd, then reboot.
# Mode change is applied with `supergfxctl -m` (supergfxd's own setter) so
# it persists across reboots without touching /etc/supergfxd.conf — that file
# is a /nix/store symlink on NixOS and would be stomped on the next rebuild.
#
# supergfxctl + services.supergfxd.enable live in devices/g14/g14.nix; this
# script assumes both are already in place. If post-resume the GPU flips
# back to Hybrid (the old arch workaround used a sleep hook + delay-start
# drop-in for this), wire those declaratively in g14.nix rather than here.
source ~/.config/rofi/common/generic.sh

yes=' Yes'
no='󰜺 Cancel'
yesno_options="$yes\n$no"

gpu_mode=$(supergfxctl -g)
case $gpu_mode in
"Integrated")
    chosen="$(_runrofimenu "$yesno_options" "Enable dGPU and reboot?" "")"
    if [[ "$chosen" == "$yes" ]]; then
        supergfxctl -m Hybrid
        systemctl reboot
    fi
    ;;
"Hybrid")
    chosen="$(_runrofimenu "$yesno_options" "Use only iGPU and reboot?" "")"
    if [[ "$chosen" == "$yes" ]]; then
        supergfxctl -m Integrated
        systemctl reboot
    fi
    ;;
*)
    echo "Hybrid GPU not found or in unknown mode: $gpu_mode"
    exit 1
    ;;
esac
