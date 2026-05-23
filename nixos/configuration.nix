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

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" "exfat" ];

  # --- Networking ---
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Kolkata";

  # --- Bluetooth ---
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # --- Audio (PipeWire) ---
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # --- Input / locale ---
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  services.printing.enable = true;

  # --- Graphical session: Hyprland + SDDM ---
  # withUWSM ships a `hyprland-uwsm.desktop` wayland-session entry alongside the
  # plain "Hyprland" one — SDDM auto-discovers it. UWSM wraps the compositor in
  # systemd units and raises graphical-session.target, which is what user
  # services like udiskie / polkit-gnome (see home.nix) are bound to. The
  # autostart.conf `exec-once = uwsm-app -- ...` wrappers depend on this being
  # on. At the SDDM login screen you must pick "Hyprland (UWSM)", not plain
  # "Hyprland" — otherwise none of that wiring activates.
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

  # Mutable SDDM background dir (the theme reads from here; the theme dir in
  # /nix/store is read-only). World-readable so the sddm user can load the image;
  # owned by malay:users so custom-set-wallpaper can write without sudo.
  systemd.tmpfiles.rules = [
    "d /var/lib/sddm-backgrounds 0755 malay users -"
  ];

  # --- XDG portals (screen-share, file pickers) ---
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # --- Polkit + secrets ---
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.seahorse.enable = true;

  # --- Power / brightness (DDC-CI needs i2c) ---
  services.power-profiles-daemon.enable = true;
  hardware.i2c.enable = true;

  # --- Docker (daemon + CLI + compose v2 plugin). User must be in `docker` group. ---
  virtualisation.docker.enable = true;

  # --- Removable media auto-mount. udisks2 is the D-Bus side (system service);
  # udiskie runs in the user session and is started by graphical-session.target
  # (see home.nix). Mounts land at /run/media/$USER/<label>. ---
  services.udisks2.enable = true;

  # FHS-style /bin and /usr/bin via a fuse mount, so scripts with hardcoded
  # shebangs like #!/bin/bash work without patching.
  services.envfs.enable = true;

  # --- Fonts ---
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.caskaydia-mono
    noto-fonts
    noto-fonts-color-emoji
  ];

  # --- Env vars seen by the SDDM-launched session ---
  # QT_QPA_PLATFORMTHEME=qt6ct -> Qt5 *and* Qt6 apps load qt5ct/qt6ct as their
  # platform theme (the qt6ct plugin handles both via the same env var name on
  # newer builds).  Pick a Kvantum SVG style or any Qt style via the GUIs.
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
    vscode
    claude-code
    sddm-theme-zeros
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Auto-GC: drop store paths/generations older than 7 days.  Runs daily so the
  # /boot ESP doesn't fill up with stale systemd-boot entries either (the boot
  # loader's generation list mirrors what's reachable in the nix store).
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  system.stateVersion = "25.11";
}
