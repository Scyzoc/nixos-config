{
  description = "Ma configuration NixOS multi-host";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      homeManagerModule = {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
        home-manager.users.user = import ./home.nix;
      };
      mkSystem = host: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/${host}
          home-manager.nixosModules.home-manager
          homeManagerModule
        ];
      };
    in
    {
      nixosConfigurations = {
        pc1 = mkSystem "pc1";  # ThinkPad L14 Gen 4
      };
    };
}
