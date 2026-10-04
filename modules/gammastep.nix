# gammastep.nix — Réduction lumière bleue via service systemd user
{ config, pkgs, lib, ... }:

{
  home.packages = [ pkgs.gammastep ];

  services.gammastep = {
    enable = true;
    provider = "manual";
    latitude = 48.8566;   # Paris — modifier selon ta position
    longitude = 2.3522;
    temperature = {
      day = 6500;
      night = 3500;
    };
    settings = {
      general = {
        fade = 1;
        brightness-day = 1.0;
        brightness-night = 0.85;
      };
    };
  };
}
