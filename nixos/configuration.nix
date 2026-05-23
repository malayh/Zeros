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
  
  # Pinned to 6.6 LTS because linux-6.12.y and 7.0.y stable currently carry
  # the regression from c411cf1bfde9 / 70d37a8b9229 ("validate WMT event SKB
  # length before struct access"), which rejects MT7922's short FUNC_CTRL
  # response with -22 and leaves Bluetooth DOWN. Upstream fix is mainline
  # e3ac0d9f1a20 but not yet in any stable backport. linux-6.6.y has no
  # btmtk.c changes from 2026 and works out of the box. Revisit once a
  # 6.12.y/7.0.y stable release picks up e3ac0d9f1a20.
  # Trade-off: 6.6 predates the amdxdna (Ryzen AI NPU) driver in 6.10.
  boot.kernelPackages = pkgs.linuxPackages_6_6;
  hardware.enableRedistributableFirmware = true;

  boot.kernelParams = [
    "pcie_aspm=powersave"
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

  # Mutable SDDM background dir (the theme reads from here; the theme dir in
  # /nix/store is read-only). World-readable so the sddm user can load the image;
  # owned by malay:users so custom-set-wallpaper can write without sudo.
  systemd.tmpfiles.rules = [
    "d /var/lib/sddm-backgrounds 0755 malay users -"
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.seahorse.enable = true;
  services.power-profiles-daemon.enable = true;
  services.logind.lidSwitch = "ignore";
  services.logind.lidSwitchExternalPower = "ignore";
  services.logind.lidSwitchDocked = "ignore";
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
    vscode
    claude-code
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
