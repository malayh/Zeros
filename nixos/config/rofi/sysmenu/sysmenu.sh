#!/bin/bash

source ~/.config/rofi/common/generic.sh


opt_install="󰏔 Install software"
opt_screenshot="󰄀 Take screenshot"
opt_toggle_gpu="󰍹 Toggle GPU mode"
opt_color_picker=" Color picker"
opt_power_menu=" Power profile"
main_menu="$opt_install\n$opt_screenshot\n$opt_toggle_gpu\n$opt_color_picker\n$opt_power_menu"
chosen=$(_runrofimenu "$main_menu" "System Menu" "󰍹")

case $chosen in
    $opt_install)
        $HOME/.config/rofi/sysmenu/softwareinstall.sh
        ;;
    $opt_screenshot)
        $HOME/.config/rofi/sysmenu/screenshot.sh
        ;;
    $opt_screenrecord)
        echo "Starting screen recording..."
        ;;
    $opt_toggle_gpu)
        $HOME/.config/rofi/sysmenu/toggle_gpu.sh
        ;;
    $opt_color_picker)
        sleep 0.5 && hyprpicker -a
        ;;
    $opt_power_menu)
        $HOME/.config/rofi/powerprofile/powerprofile.sh
        ;;
esac

