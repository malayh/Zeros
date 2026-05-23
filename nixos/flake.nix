{
  description = "Hyprland on Nixos";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      lib = nixpkgs.lib;

      # Every subdir under ./devices/ becomes a host:
      # `nixosConfigurations.<name>` is built from configuration.nix +
      # devices/<name>/<name>.nix.  Add a new device by creating
      # devices/<name>/<name>.nix — no flake edit needed.  install.sh picks
      # which host to build based on NIX_DEVICE in ./.env.
      devices = builtins.attrNames (
        lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./devices)
      );

      mkHost = device: lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./devices/${device}/${device}.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.malay = import ./home.nix;
              backupFileExtension = "backup";
            };
          }
        ];
      };
    in {
      nixosConfigurations = lib.genAttrs devices mkHost;
    };
}
