# workspace-link.nix — Workspaces liés par paires (ex : 1 ↔ 6)
# Aller sur un workspace lié affiche son jumeau sur l'écran auquel il est associé
# (groupes de la disposition, workspace-bind dans display-switch.nix), dans les
# deux sens. Inactif avec un seul écran. Paires réglées depuis l'onglet
# « Liaisons » du menu SUPER+P (quickshell-launcher/DisplayMenu.qml).
# Backend assets/workspace-link.py, config ~/.local/state/workspace-links.json.
{ pkgs, ... }:

let
  workspace-link = pkgs.writeShellScriptBin "workspace-link" ''
    HYPRCTL=${pkgs.hyprland}/bin/hyprctl exec ${pkgs.python3}/bin/python3 ${../assets/workspace-link.py} "$@"
  '';
in
{
  home.packages = [ workspace-link ];

  systemd.user.services.workspace-link = {
    Unit = {
      Description = "Workspaces liés : affiche le jumeau sur son écran";
      After       = [ "hyprland-session.target" ];
      PartOf      = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart  = "${workspace-link}/bin/workspace-link daemon";
      Restart    = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };
}
