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