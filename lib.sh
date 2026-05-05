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

_installSddmTheme() {
    local repo_root theme_src theme_dst conf_src conf_dst bg_dir wallpaper main_conf
    repo_root=$(pwd)
    theme_src="${repo_root}/sddm/themes/zeros"
    theme_dst="/usr/share/sddm/themes/zeros"
    conf_src="${repo_root}/sddm/sddm.conf.d/zeros.conf"
    conf_dst="/etc/sddm.conf.d/zeros.conf"
    bg_dir="${theme_dst}/backgrounds"
    wallpaper="${HOME}/.config/zeros/theme/currentwallpaper.png"
    main_conf="/etc/sddm.conf"

    if [[ ! -f "${theme_src}/Main.qml" ]]; then
        echo ":: SDDM theme source missing at ${theme_src}, skipping."
        return 0
    fi

    # Idempotency: bail out only when every artifact this function manages is
    # already in place, including /etc/sddm.conf (which overrides /etc/sddm.conf.d
    # in this SDDM build, so it MUST point at zeros).
    if [[ -f "${theme_dst}/Main.qml" \
        && -f "${theme_dst}/metadata.desktop" \
        && -d "${bg_dir}" \
        && -f "${conf_dst}" \
        && -f "${main_conf}" ]] \
        && grep -qE '^\s*Current\s*=\s*zeros\s*$' "${main_conf}" \
        && ! grep -qE '^\s*(GreeterEnvironment|InputMethod)\s*=\s*\S' "${main_conf}"; then
        echo ":: SDDM zeros theme already installed, skipping."
        return 0
    fi

    sudo install -d -m 755 "${theme_dst}"
    sudo install -m 644 "${theme_src}/Main.qml" "${theme_dst}/Main.qml"
    sudo install -m 644 "${theme_src}/metadata.desktop" "${theme_dst}/metadata.desktop"

    # User-owned backgrounds dir so wallpaper sync works without sudo.
    # 0755 keeps the file readable by the sddm greeter user.
    sudo install -d -m 755 -o "${USER}" -g "${USER}" "${bg_dir}"

    sudo install -d -m 755 /etc/sddm.conf.d
    sudo install -m 644 "${conf_src}" "${conf_dst}"

    # /etc/sddm.conf is loaded after /etc/sddm.conf.d/ and wins on conflict, so
    # the drop-in alone is not enough to switch themes. Patch it directly, and
    # clear any silent-specific env vars (the qtvirtualkeyboard plugin is
    # incompatible with Qt 6.11+ and makes SDDM fall back to its embedded theme).
    if [[ -f "${main_conf}" ]]; then
        if grep -qE '^\s*Current\s*=' "${main_conf}"; then
            sudo sed -i -E 's|^\s*Current\s*=.*|Current=zeros|' "${main_conf}"
        else
            if grep -qE '^\s*\[Theme\]\s*$' "${main_conf}"; then
                sudo sed -i -E '/^\s*\[Theme\]\s*$/a Current=zeros' "${main_conf}"
            else
                printf '\n[Theme]\nCurrent=zeros\n' | sudo tee -a "${main_conf}" >/dev/null
            fi
        fi
        sudo sed -i -E 's|^\s*GreeterEnvironment\s*=.*|GreeterEnvironment=|' "${main_conf}"
        sudo sed -i -E 's|^\s*InputMethod\s*=.*|InputMethod=|' "${main_conf}"
    else
        printf '[Theme]\nCurrent=zeros\n' | sudo tee "${main_conf}" >/dev/null
        sudo chmod 644 "${main_conf}"
    fi
    echo ":: pointed ${main_conf} at the zeros theme and cleared legacy greeter env."

    if [[ -f "${wallpaper}" ]]; then
        install -m 644 "${wallpaper}" "${bg_dir}/current.png"
        echo ":: seeded SDDM background from ${wallpaper}."
    else
        echo ":: no wallpaper at ${wallpaper} yet; SDDM will show black until one is set."
    fi
}

_setupHibernation() {
    local swapfile="/swapfile"
    local manage_swap="${CREATE_OR_UPDATE_SWAP:-1}"
    local fstype mem_mib target_bytes current_bytes
    local swap_changed=0 hooks_changed=0

    fstype=$(findmnt -no FSTYPE /)
    mem_mib=$(awk '/^MemTotal:/ {printf "%d\n", ($2/1024)+1}' /proc/meminfo)
    target_bytes=$(( mem_mib * 1024 * 1024 ))

    # 2a. Manage /swapfile
    if [[ "${manage_swap}" == "1" ]]; then
        if [[ -f "${swapfile}" ]]; then
            current_bytes=$(stat -c %s "${swapfile}")
            if (( current_bytes < target_bytes )); then
                echo ":: ${swapfile} is ${current_bytes} bytes, resizing to ${target_bytes} bytes (${mem_mib} MiB)."
                swap_changed=1
            else
                echo ":: ${swapfile} already >= RAM size (${current_bytes} bytes), leaving as-is."
            fi
        else
            echo ":: ${swapfile} missing, creating ${mem_mib} MiB swap file."
            swap_changed=1
        fi

        if (( swap_changed == 1 )); then
            sudo swapoff "${swapfile}" 2>/dev/null || true
            if [[ "${fstype}" == "btrfs" ]]; then
                sudo rm -f "${swapfile}"
                sudo btrfs filesystem mkswapfile --size "${mem_mib}m" --uuid clear "${swapfile}"
            else
                if [[ ! -f "${swapfile}" ]]; then
                    sudo install -m 600 /dev/null "${swapfile}"
                fi
                sudo fallocate -l "${mem_mib}M" "${swapfile}"
                sudo chmod 600 "${swapfile}"
                sudo mkswap "${swapfile}"
            fi
            sudo swapon "${swapfile}"
        else
            if ! swapon --show=NAME --noheadings 2>/dev/null | grep -qx "${swapfile}"; then
                sudo swapon "${swapfile}"
            fi
        fi

        if ! grep -qE '^\s*/swapfile\s' /etc/fstab; then
            echo ":: adding /swapfile entry to /etc/fstab."
            echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab >/dev/null
        else
            echo ":: /swapfile entry already in /etc/fstab."
        fi
    else
        echo ":: CREATE_OR_UPDATE_SWAP=0, skipping swap file management."
        if [[ ! -f "${swapfile}" ]]; then
            echo ":: ${swapfile} not present and swap management disabled, skipping resume= wiring."
            return 0
        fi
    fi

    # 2b. Compute resume= and resume_offset=
    local resume_uuid resume_offset
    resume_uuid=$(findmnt -no UUID -T "${swapfile}")
    if [[ -z "${resume_uuid}" ]]; then
        echo ":: could not determine UUID for partition holding ${swapfile}, aborting hibernation setup."
        return 1
    fi
    if [[ "${fstype}" == "btrfs" ]]; then
        resume_offset=$(sudo btrfs inspect-internal map-swapfile -r "${swapfile}" 2>/dev/null)
        if [[ -z "${resume_offset}" ]]; then
            resume_offset=$(sudo btrfs inspect-internal map-swapfile "${swapfile}" 2>/dev/null \
                | awk -F'[: ]+' '/[Rr]esume offset/ {print $NF; exit}')
        fi
    else
        resume_offset=$(sudo filefrag -v "${swapfile}" | awk '$1=="0:"{print substr($4,1,length($4)-2); exit}')
    fi
    if [[ -z "${resume_offset}" ]]; then
        echo ":: could not determine resume_offset for ${swapfile}, aborting hibernation setup."
        return 1
    fi

    # 2c. mkinitcpio resume hook
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    if grep -qE '^HOOKS=.*\bresume\b' "${mkinitcpio_conf}"; then
        echo ":: mkinitcpio.conf already has the resume hook."
    elif grep -qE '^HOOKS=.*\bfilesystems\b' "${mkinitcpio_conf}"; then
        echo ":: adding resume hook to ${mkinitcpio_conf} (before filesystems)."
        sudo sed -i -E 's/^(HOOKS=\([^)]*)\bfilesystems\b/\1resume filesystems/' "${mkinitcpio_conf}"
        hooks_changed=1
    else
        echo ":: could not find filesystems hook in ${mkinitcpio_conf}, aborting hibernation setup."
        return 1
    fi
    if (( hooks_changed == 1 )); then
        echo ":: regenerating initramfs (mkinitcpio -P)."
        sudo mkinitcpio -P
    fi

    # 2d. GRUB cmdline
    local grub_default="/etc/default/grub"
    local current_line desired_inner current_inner
    current_line=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "${grub_default}" | head -n1)
    if [[ -z "${current_line}" ]]; then
        echo ":: GRUB_CMDLINE_LINUX_DEFAULT not found in ${grub_default}, aborting GRUB step."
        return 1
    fi
    current_inner=$(printf '%s' "${current_line}" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"$/\1/')
    desired_inner=$(printf '%s' "${current_inner}" \
        | sed -E 's/(^|[[:space:]])resume=[^[:space:]]*/\1/g; s/(^|[[:space:]])resume_offset=[^[:space:]]*/\1/g' \
        | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
    if [[ -n "${desired_inner}" ]]; then
        desired_inner="${desired_inner} resume=UUID=${resume_uuid} resume_offset=${resume_offset}"
    else
        desired_inner="resume=UUID=${resume_uuid} resume_offset=${resume_offset}"
    fi

    if [[ "${current_inner}" == "${desired_inner}" ]]; then
        echo ":: GRUB cmdline already has correct resume=/resume_offset=."
    else
        echo ":: updating GRUB cmdline with resume=UUID=${resume_uuid} resume_offset=${resume_offset}."
        sudo sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${desired_inner}\"|" "${grub_default}"
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
}