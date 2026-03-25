#!/bin/bash

source ~/.config/rofi/common/generic.sh






opt_package="󰣇 Package"
opt_aur="󰒋 AUR"
main_menu="$opt_package\n$opt_aur"
selected=$(_runrofimenu "$main_menu" "Install Software" "󰏔")

case $selected in
    $opt_package)
        xdg-terminal-exec --app-id=org.zeros.terminal $HOME/.config/rofi/sysmenu/_installer_pacman.sh
        ;;
    $opt_aur)
        xdg-terminal-exec --app-id=org.zeros.terminal $HOME/.config/rofi/sysmenu/_installer_aur.sh
        ;;
esac


