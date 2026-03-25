#!/bin/bash
source lib.sh

core_dependencies=(
    #general tools
    stow
    unzip
    wget
    curl
    jq
    btop
    fzf
    
    # hyperland and related packages
    uwsm
    hypridle  
    hyprland
    hyprlock
    hyprpaper
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xdg-terminal-exec
    waybar
    rofi-wayland
    mako

    # apps
    ghostty
    timeshift
    

    # clipboard manager
    cliphist
    wtype

    # storing passwords and auth
    libsecret
    gnome-keyring
    polkit-gnome
    
    # network, bluetooth
    # impala                        
    # network-manager-applet
    bluetui

    # # audio
    # wiremix
    # pamixer

    # fonts
    ttf-jetbrains-mono-nerd
    ttf-cascadia-mono-nerd

    # theme
    bibata-cursor-theme
    # nwg-look
    # qt5-wayland
    # kvantum-qt5

    # asus rog/tuf specific
    # asusctl
    # rog-control-center
    # supergfxctl

    # screenshot
    # slurp
    # grim
    # wayfreeze
    # satty
    # hyprpicker
    # gpu-screen-recorder

    # monitor control
    # ddcutil
    
)


_installPackages "${core_dependencies[@]}"
_stowdotfiles