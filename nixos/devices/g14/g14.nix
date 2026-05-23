{ config, lib, pkgs, ... }:
{
  # hardware-configuration.nix lives at /etc/nixos/ (machine-local, generated
  # by nixos-generate-config during the initial install). Importing it via an
  # absolute path keeps the flake free of any machine-specific files but
  # requires `--impure` at build time so Nix is allowed to read outside the
  # flake source. install.sh passes --impure already.
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

  # MT7922 combo Wi-Fi+BT chip races at boot: mt7921e finishes loading Wi-Fi
  # firmware *after* btusb has already attempted (and failed with -EINVAL) the
  # wmt func ctrl handshake, leaving hci0 DOWN with BD address 00:00:00:00:00:00.
  # Reloading btusb once mt7921e is fully up makes the BT side initialize
  # cleanly; bluetoothd auto-picks-up the re-appearing hci0 via netlink.
  systemd.services.btusb-reload = {
    description = "Reload btusb to work around MT7922 BT firmware-load race";
    after = [ "bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.kmod}/bin/modprobe -r btusb || true
      ${pkgs.kmod}/bin/modprobe btusb
    '';
  };
}
