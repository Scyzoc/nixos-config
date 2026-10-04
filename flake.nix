{
  description = "Ma configuration NixOS multi-host";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude Desktop (non officiel, repackage du binaire Windows)
    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      # pas de follows : le flake dépend de nodePackages (retiré d'unstable)
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
          { nixpkgs.overlays = [ (import ./overlays/swaync-app-colors.nix) (import ./overlays/kitty-claude-notify-icon.nix) (import ./overlays/glaze-hyprland-pin.nix) (import ./overlays/cisco-packet-tracer-901.nix) (final: prev: { claude-desktop-with-fhs = inputs.claude-desktop.packages.${prev.system}.claude-desktop-with-fhs; }) ]; }
        ];
      };
    in
    {
      nixosConfigurations = {
        pc1 = mkSystem "pc1";  # ThinkPad L14 Gen 4
      };
    };
}
