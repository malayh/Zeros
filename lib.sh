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

_setupSddm() {
    local theme_dir="/usr/share/sddm/themes/sddm-astronaut-theme"
    local wallpaper="$HOME/.config/zeros/theme/currentwallpaper.png"
    local default_wallpaper="$theme_dir/Backgrounds/astronaut.png"

    sudo install -d -m 0755 /etc/sddm.conf.d
    install -d -m 0755 "$(dirname "$wallpaper")"

    if [ ! -f "$wallpaper" ]; then
        cp "$default_wallpaper" "$wallpaper"
        chmod 0644 "$wallpaper"
    fi

    printf '[Theme]\nCurrent=sddm-astronaut-theme\n' \
        | sudo tee /etc/sddm.conf >/dev/null

    printf '[General]\nInputMethod=qtvirtualkeyboard\n' \
        | sudo tee /etc/sddm.conf.d/virtualkbd.conf >/dev/null

    sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/astronaut.conf|' \
        "$theme_dir/metadata.desktop"

    sudo ln -sfn "$wallpaper" "$theme_dir/Backgrounds/currentwallpaper.png"

    sudo sed -i 's|^Background=.*|Background="Backgrounds/currentwallpaper.png"|' \
        "$theme_dir/Themes/astronaut.conf"

    sudo systemctl enable sddm.service
}

_enableScreenSharing() {
    local units=(pipewire.socket pipewire-pulse.socket wireplumber.service)
    for unit in "${units[@]}"; do
        if systemctl --user is-active --quiet "${unit}"; then
            echo ":: ${unit} is already active."
            continue
        fi
        systemctl --user enable --now "${unit}"
    done
}