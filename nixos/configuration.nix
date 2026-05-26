{ config, pkgs, lib, ... }:

let
  sddm-theme-zeros = pkgs.stdenvNoCC.mkDerivation {
    pname = "sddm-theme-zeros";
    version = "1.0.0";
    src = ./sddm/theme;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/sddm/themes/zeros
      cp -r $src/. $out/share/sddm/themes/zeros/
      runHook postInstall
    '';
  };
in
{
  # Machine-specific bits (hardware-configuration import, hostName, swap +
  # hibernation offset, device-specific quirks) live under devices/<host>/.
  # The flake selects which devices/* module to merge in per host.

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" "exfat" ];
  
  # 6.18.33: brings 18mo of Phoenix amdgpu fixes (vs the 6.6 LTS we ran before)
  # AND the MT7922 BT fix e3ac0d9f1a20. nixpkgs ships linux_6_18 at .32 which
  # is one patch short of the BT fix, so we override the src to the upstream
  # .33 tarball. See nixos/bootissue.md.
  boot.kernelPackages = let
    linux_6_18_33 = pkgs.linux_6_18.override {
      argsOverride = rec {
        version = "6.18.33";
        modDirVersion = "6.18.33";
        src = pkgs.fetchurl {
          url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${version}.tar.xz";
          sha256 = "10mp1ypsdz42jr26g1xxbw806mvpy0n35418fhsgxxlr4lqgy5kg";
        };
      };
    };
  in pkgs.linuxPackagesFor linux_6_18_33;
  hardware.enableRedistributableFirmware = true;

  boot.kernelParams = [
    "pcie_aspm.policy=powersave"
  ];

  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Kolkata";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    extraConfig.pipewire."92-low-latency" = {
    "context.properties" = {
      "default.clock.rate" = 48000;
      "default.clock.quantum" = 64;
      "default.clock.min-quantum" = 32;
      "default.clock.max-quantum" = 256;
    };
  };
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  services.printing.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    package = pkgs.kdePackages.sddm;
    theme = "zeros";
    extraPackages = with pkgs.kdePackages; [
      qtsvg
      qtmultimedia
      qtvirtualkeyboard
    ];
  };
  services.flatpak.enable = true;
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
  };

  # Mutable SDDM background dir (the theme reads from here; the theme dir in
  # /nix/store is read-only). World-readable so the sddm user can load the image;
  # owned by malay:users so custom-set-wallpaper can write without sudo.
  systemd.tmpfiles.rules = [
    "d /var/lib/sddm-backgrounds 0755 malay users -"
    # Freeze-debug ring buffer: snapshots age out after 1d.
    "d /var/log/freeze-snapshots 0755 root root 1d"
  ];

  # Runs as root from system systemd so a wedged user bus / Hyprland can't
  # block it. See nixos/bootissue.md.
  systemd.services.freeze-snapshot = {
    description = "Snapshot user-session state for freeze diagnosis";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "freeze-snapshot" ''
        set +e
        ts=$(date +%Y%m%d-%H%M%S)
        out=/var/log/freeze-snapshots/$ts.log
        exec >"$out" 2>&1
        echo "=== date ==="; date
        echo "=== uptime ==="; uptime
        echo "=== last suspend/resume in this boot ==="
        ${pkgs.systemd}/bin/journalctl -b 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E "Suspending\.\.\.|System returned from sleep|PM: suspend (entry|exit)|Lid (closed|opened)" | tail -10
        echo "=== ps -u malay -L (state, wchan, cmd) ==="
        ${pkgs.procps}/bin/ps -u malay -Lo pid,tid,stat,wchan:32,cmd --no-headers
        hpid=$(${pkgs.procps}/bin/pgrep -u malay -x Hyprland | head -1)
        if [ -n "$hpid" ]; then
          echo "=== /proc/$hpid/status (Hyprland) ==="
          grep -E '^(State|Threads|VmRSS|voluntary|nonvoluntary)' /proc/$hpid/status
          echo "=== /proc/$hpid/wchan ==="
          cat /proc/$hpid/wchan; echo
          echo "=== /proc/$hpid/task/*/wchan ==="
          for t in /proc/$hpid/task/*/wchan; do
            tid=$(echo "$t" | ${pkgs.gnused}/bin/sed 's|.*/task/||;s|/wchan||')
            printf '%s\t' "$tid"; cat "$t"; echo
          done
          echo "=== open sockets (lsof -nP -p $hpid -ad u,unix,sock) ==="
          ${pkgs.lsof}/bin/lsof -nP -p $hpid 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E 'unix|sock|pipe' | head -40
        else
          echo "(no Hyprland process found)"
        fi
        sig=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1)
        if [ -n "$sig" ]; then
          # tmpfs gets wiped on reboot — copy Hyprland's log into persistent storage.
          hlog=/run/user/1000/hypr/$sig/hyprland.log
          if [ -f "$hlog" ]; then
            cp -f "$hlog" /var/log/freeze-snapshots/$ts.hyprland.log 2>/dev/null
          fi
          echo "=== IPC ping: hyprctl activeworkspace (timeout 2s; non-zero = WEDGED) ==="
          timeout --kill-after=1 2 ${pkgs.util-linux}/bin/runuser -u malay -- \
            env HYPRLAND_INSTANCE_SIGNATURE=$sig XDG_RUNTIME_DIR=/run/user/1000 \
            ${pkgs.hyprland}/bin/hyprctl activeworkspace 2>&1 | head -5
          echo "hyprctl exit=$?"
        else
          echo "(no hypr signature dir)"
        fi
        echo "=== dmesg tail (errors) ==="
        ${pkgs.util-linux}/bin/dmesg -T --level=err,warn 2>/dev/null | tail -20
      '';
    };
  };
  systemd.timers.freeze-snapshot = {
    description = "Run freeze-snapshot every 30s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };

  # gtk portal dropped — suspected freeze-trigger; see nixos/bootissue.md.
  # hyprland portal still active via programs.hyprland.enable.
  xdg.portal.enable = true;

  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.seahorse.enable = true;
  services.power-profiles-daemon.enable = true;
  hardware.i2c.enable = true;
  virtualisation.docker.enable = true;
  services.udisks2.enable = true;
  services.envfs.enable = true;
  programs.nix-ld.enable = true;

  # --- Fonts ---
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.caskaydia-mono
    noto-fonts
    noto-fonts-color-emoji
  ];

  environment.sessionVariables = {
    XDG_CURRENT_DESKTOP   = "Hyprland";
    XDG_SESSION_TYPE      = "wayland";
    NIXOS_OZONE_WL        = "1";
    QT_QPA_PLATFORMTHEME  = "qt6ct";
  };

  # --- User ---
  users.users.malay = {
    isNormalUser = true;
    description = "Malay";
    extraGroups = [ "networkmanager" "wheel" "video" "i2c" "docker" ];
    packages = with pkgs; [ ];
  };

  programs.firefox.enable = true;
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    sddm-theme-zeros
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  system.stateVersion = "25.11";
}
