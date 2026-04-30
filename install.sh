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
    power-profiles-daemon

    # display manager
    sddm
    sddm-astronaut-theme

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
    impala                        
    bluetui

    # audio
    wiremix
    pamixer

    # theme
    ttf-jetbrains-mono-nerd
    ttf-cascadia-mono-nerd
    bibata-cursor-theme
    swaybg
    imagemagick
    nwg-look 
    qt5ct 
    qt6ct 
    kvantum 
    kvantum-qt5

    # asus rog/tuf specific
    # asusctl
    # rog-control-center
    # supergfxctl

    # screenshot
    slurp
    grim
    wayfreeze
    satty
    hyprpicker

    # monitor control
    # ddcutil
    
)


_installPackages "${core_dependencies[@]}"
_stowdotfiles
_setupSddm