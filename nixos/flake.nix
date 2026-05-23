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

      devices = builtins.attrNames (
        lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./devices)
      );

      flakeRoot =
        if builtins.pathExists /etc/nixos/flake-root
        then builtins.readFile /etc/nixos/flake-root
        else throw "/etc/nixos/flake-root missing — run install.sh first";

      mkHost = device: lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit flakeRoot; };
        modules = [
          ./configuration.nix
          ./devices/${device}/${device}.nix
          ./app-config.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.malay = import ./home.nix;
              extraSpecialArgs = { inherit flakeRoot; };
              backupFileExtension = "backup";
            };
          }
        ];
      };
    in {
      nixosConfigurations = lib.genAttrs devices mkHost;
    };
}
