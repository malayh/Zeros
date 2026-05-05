#!/bin/bash
source lib.sh

: "${CREATE_OR_UPDATE_SWAP:=1}"
export CREATE_OR_UPDATE_SWAP

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

    # screen sharing (PipeWire pipeline for xdg-desktop-portal ScreenCast)
    pipewire
    wireplumber
    pipewire-pulse
    libpipewire

    # monitor control
    # ddcutil
    
)


_installPackages "${core_dependencies[@]}"
_stowdotfiles
_enableScreenSharing
_setupHibernation