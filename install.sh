#!/bin/bash


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
    hyprpolkitagent

    # apps
    ghostty
    timeshift

    # clipboard manager
    cliphist
    wtype

    # # storing passwords and auth
    # libsecret
    # polkit-gnome
    
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


_isInstalled() {
    package="$1"
    check="$(sudo pacman -Qs --color always "${package}" | grep "local" | grep "${package} ")"
    if [ -n "${check}" ]; then
        echo 0
        return #true
    fi
    echo 1
    return #false
}

_installPackages() {
    for pkg; do
        if [[ $(_isInstalled "${pkg}") == 0 ]]; then
            echo ":: ${pkg} is already installed."
            continue
        fi
        yay --noconfirm -S "${pkg}"
    done
}

_stowdotfiles() {
    cd  dotfiles;
    for dir in $(ls); do
        stow $dir --target=$HOME;
    done 
}


_installPackages "${core_dependencies[@]}"
_stowdotfiles