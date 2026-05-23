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

  home-manager.users.malay = { config, ... }: {
    xdg.configFile."rog".source =
      config.lib.file.mkOutOfStoreSymlink "${flakeRoot}/devices/g14/rog";
  };
}
