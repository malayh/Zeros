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

  # MT7922 combo Wi-Fi+BT chip won't initialize the BT side at boot: the BT
  # vendor `wmt func ctrl` command fails with -EINVAL ("Failed to send wmt
  # func ctrl (-22)" in dmesg), leaving hci0 DOWN with BD address
  # 00:00:00:00:00:00.  Two module quirks are responsible:
  #
  #   - mt7921e ASPM (PCIe Active State Power Management) puts the chip into
  #     a low-power state during init that rejects the BT enable command.
  #   - btusb USB autosuspend then prevents BT from recovering after the
  #     fact (also breaks BT across system suspend/resume).
  #
  # Both have module parameters that just need turning off.  After this
  # bluetoothd brings hci0 up on its own — no reload service needed.
  boot.extraModprobeConfig = ''
    options mt7921e disable_aspm=1
    options btusb enable_autosuspend=0
  '';
}
