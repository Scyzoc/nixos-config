{ ... }:

{
  imports = [
    ../../configuration.nix
    ./hardware-configuration.nix
    ../../networking.nix
    ../../battery-limit.nix
    ../../private-repo-sync.nix
  ];
}
