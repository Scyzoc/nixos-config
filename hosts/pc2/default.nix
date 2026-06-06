{ lib, ... }:

{
  imports = [
    ../../configuration.nix
    ./hardware-configuration.nix
    ./networking.nix
  ];

  # Overrides PC2 (Intel) — neutralise les spécificités ThinkPad L14 AMD de configuration.nix

  # Pas de r8168/r8169 ni vmware kernel modules sur PC2
  boot.extraModulePackages = lib.mkForce [];
  boot.blacklistedKernelModules = lib.mkForce [];
  boot.kernelModules = lib.mkForce [ "kvm-intel" ];

  # Pas de param amdgpu sur Intel
  boot.kernelParams = lib.mkForce [];
}
