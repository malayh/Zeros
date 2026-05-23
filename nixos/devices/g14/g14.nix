{ config, lib, pkgs, flakeRoot, ... }:
{
  imports = [
    /etc/nixos/hardware-configuration.nix
  ];

  networking.hostName = "g14";

  # Hibernation: 32 GiB swapfile sized for hibernation-to-disk.
  # resumeDevice is the root fs (where /var/lib/swapfile lives). resume_offset
  # is the byte-position of the swapfile within that fs and is machine-local
  # (it depends on where the kernel placed the file). install.sh recomputes
  # it via `filefrag` on every rebuild and writes /etc/nixos/resume-offset.
  # The conditional keeps a first-boot rebuild (before the swapfile exists)
  # from breaking: no file -> no kernel param -> system still boots fine.
  swapDevices = [
    { device = "/var/lib/swapfile"; size = 32 * 1024; }
  ];
  boot.resumeDevice = config.fileSystems."/".device;
  boot.kernelParams = lib.optional (builtins.pathExists /etc/nixos/resume-offset)
    "resume_offset=${builtins.readFile /etc/nixos/resume-offset}";


  services.asusd = {
    enable = true;
    enableUserService = true;
  };
  services.supergfxd.enable = true;

  environment.systemPackages = with pkgs; [
    asusctl 
    supergfxctl
  ];

  # Device-local live-edit symlink: ~/.config/rog -> the g14's rog/ dir in the
  # working tree. Same shape as the shared dotfile bindings in home.nix; lives
  # here (and not home.nix) because rog/ is g14-specific — other devices won't
  # have asusd. rog-control-center and asusd write back to these files (fan
  # curves, aura, anime), so they must point at the live tree, not /nix/store.
  home-manager.users.malay = { config, ... }: {
    xdg.configFile."rog".source =
      config.lib.file.mkOutOfStoreSymlink "${flakeRoot}/devices/g14/rog";
  };
}
