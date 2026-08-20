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


  services.asusd.enable = true;
  services.supergfxd.enable = true;

  # NVIDIA Optimus + supergfxd. Without the driver installed, supergfxd's
  # Hybrid setup errors at boot ("module nvidia_drm is missing") and Hybrid
  # is half-broken — dGPU detected, no driver, supergfxd can't manage it.
  # Integrated mode (dGPU off via PCI) doesn't strictly need the driver, but
  # ever switching back to Hybrid does.
  #
  # finegrained PM + offload is the modern Optimus mode: driver stays loaded
  # in Hybrid but the dGPU enters D3cold at idle, and apps explicitly opt in
  # to the dGPU with `nvidia-offload <cmd>`.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement = {
      enable = true;
      finegrained = true;
    };
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      # Verified via lspci: 01:00.0 NVIDIA, 65:00.0 AMD (0x65 = 101).
      amdgpuBusId = "PCI:101:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # supergfxd's upstream unit declares Before=display-manager.service, which
  # races the display stack at boot when the system comes up in Integrated
  # mode and can freeze the console. A short ExecStartPre lets DM init settle
  # before supergfxd tries to detach the dGPU. Replaces the arch-era
  # /etc/systemd/system/supergfxd.service.d/delay-start.conf drop-in.
  systemd.services.supergfxd.serviceConfig.ExecStartPre =
    "${pkgs.coreutils}/bin/sleep 5";

  # G14 wakes from suspend with the dGPU re-attached even when supergfxd is
  # set to Integrated. Bounce Vfio -> Integrated to power it back off.
  # No-op when we're already in Hybrid (the user wants the dGPU live).
  # Replaces the arch-era /usr/lib/systemd/system-sleep/force-igpu script.
  powerManagement.resumeCommands = ''
    if [ "$(${pkgs.supergfxctl}/bin/supergfxctl -g)" = "Integrated" ]; then
      ${pkgs.coreutils}/bin/sleep 4
      ${pkgs.supergfxctl}/bin/supergfxctl -m Vfio || true
      ${pkgs.coreutils}/bin/sleep 1
      ${pkgs.supergfxctl}/bin/supergfxctl -m Integrated || true
    fi
  '';

  # Tiny privileged helper so the rofi toggle can flip the supergfxd mode
  # without a sudo password prompt — rofi has no tty for sudo to prompt on,
  # so a direct `sudo sed` fails silently and the toggle appears to do
  # nothing. NOPASSWD is restricted to this one wrapper, which itself
  # whitelists only Hybrid/Integrated, so the user can't sudo arbitrary sed.
  environment.etc."gpu-set-mode" = {
    source = pkgs.writeShellScript "gpu-set-mode" ''
      set -eu
      case "''${1:-}" in
        Hybrid|Integrated) ;;
        *) echo "usage: gpu-set-mode {Hybrid|Integrated}" >&2; exit 1 ;;
      esac
      ${pkgs.gnused}/bin/sed -i \
        "s/\"mode\": \".*\"/\"mode\": \"$1\"/" /etc/supergfxd.conf
    '';
  };

  security.sudo.extraRules = [{
    users = [ "malay" ];
    commands = [{
      command = "/etc/gpu-set-mode";
      options = [ "NOPASSWD" ];
    }];
  }];

  # CPU undervolt: Curve Optimizer -15 on all cores (0xFFFFFFF1 = -15 as u32).
  # Volatile SMU setting, not firmware: any reboot/power-cycle clears it, and
  # booting a previous generation drops this unit entirely. Reapplied after
  # suspend/hibernate because resume can reset the SMU state.
  boot.extraModulePackages = [ config.boot.kernelPackages.ryzen-smu ];
  boot.kernelModules = [ "ryzen_smu" ];

  systemd.services.cpu-undervolt = {
    description = "Apply Curve Optimizer undervolt via ryzenadj";
    wantedBy = [ "multi-user.target" "post-resume.target" ];
    after = [ "post-resume.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ryzenadj}/bin/ryzenadj --set-coall=0xFFFFFFF1";
    };
  };

  environment.systemPackages = with pkgs; [
    asusctl
    supergfxctl
    ryzenadj
  ];

  home-manager.users.malay = { config, ... }: {
    xdg.configFile."rog".source =
      config.lib.file.mkOutOfStoreSymlink "${flakeRoot}/devices/g14/rog";
  };
}
