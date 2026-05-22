#!/bin/bash

source ~/.config/rofi/common/generic.sh

which supergfxctl || {
  sudo pacman -S --noconfirm --needed supergfxctl
  sudo systemctl enable supergfxd
  sudo sed -i '/"vfio_enable":/ s/false/true/' /etc/supergfxd.conf
}

yes=' Yes'
no='󰜺 Cancel'
yesno_options="$yes\n$no"

gpu_mode=$(supergfxctl -g)
case $gpu_mode in
"Integrated")
    chosen="$(_runrofimenu "$yesno_options" "Enable dGPU and reboot?" "")"
    if [[ "$chosen" == "$yes" ]]; then
        sudo sed -i "s/\"mode\": \".*\"/\"mode\": \"Hybrid\"/" /etc/supergfxd.conf

        # Let hybrid mode be the default after system sleep
        sudo rm -rf /usr/lib/systemd/system-sleep/force-igpu

        # Remove the startup delay override (not needed for Hybrid mode)
        sudo rm -rf /etc/systemd/system/supergfxd.service.d/delay-start.conf

        systemctl reboot
    fi
    ;;
"Hybrid")
    chosen="$(_runrofimenu "$yesno_options" "Use only iGPU and reboot?" "")"
    if [[ "$chosen" == "$yes" ]]; then
        sudo sed -i "s/\"mode\": \".*\"/\"mode\": \"Integrated\"/" /etc/supergfxd.conf
      
        # Force igpu mode after system sleep (or dgpu could get activated)
        sudo mkdir -p /usr/lib/systemd/system-sleep
        sudo cp -p $HOME/.config/scripts/force-igpu /usr/lib/systemd/system-sleep/

        # Delay supergfxd startup to avoid race condition with display manager
        # that can cause system freeze when booting in Integrated mode
        sudo mkdir -p /etc/systemd/system/supergfxd.service.d
        sudo cp -p $HOME/.config/extra/delay-start.conf /etc/systemd/system/supergfxd.service.d/
        systemctl reboot
    fi

    ;;
*)
    echo "Hybrid GPU not found or in unknown mode."
    exit 1
    ;;
esac