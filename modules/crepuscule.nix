# crepuscule.nix — Crépuscule : filtre anti-lumière bleue et mode sombre
# Interface Quickshell (quickshell-launcher/Crepuscule.qml), ouverte depuis le menu
# d'applications ; backend assets/crepuscule.py, config dans ~/.config/crepuscule/.
# Filtre = shader d'écran Hyprland : gammastep / hyprsunset sont inopérants avec
# AQ_NO_ATOMIC=1 (KMS legacy sans gamma ni CTM). Remplace l'ancien services.gammastep.
{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;

  crepuscule-ctl = pkgs.writeShellScriptBin "crepuscule-ctl" ''
    export CREPUSCULE_SYSTEMCTL=${pkgs.systemd}/bin/systemctl
    export CREPUSCULE_GSETTINGS=${pkgs.glib}/bin/gsettings
    export CREPUSCULE_HYPRCTL=${pkgs.hyprland}/bin/hyprctl
    export CREPUSCULE_THEME=${config.home.profileDirectory}/bin/theme
    exec ${pkgs.python3}/bin/python3 ${../assets/crepuscule.py} "$@"
  '';

  # Affiche / masque la fenêtre (config Quickshell « launcher », voir app-launcher.nix)
  crepuscule = pkgs.writeShellScriptBin "crepuscule" ''
    ${quickshell}/bin/quickshell ipc -c launcher call crepuscule toggle >/dev/null 2>&1
  '';
in
{
  home.packages = [ crepuscule crepuscule-ctl ];

  xdg.desktopEntries.crepuscule = {
    name = "Crépuscule";
    genericName = "Filtre lumière bleue";
    comment = "Filtre anti-lumière bleue et mode sombre selon l'heure ou le soleil";
    exec = "${crepuscule}/bin/crepuscule";
    icon = "redshift";
    terminal = false;
    type = "Application";
    categories = [ "Settings" "Utility" ];
    settings.Keywords = "lumière bleue;filtre;nuit;gammastep;redshift;sombre;thème;soleil;coucher;night;dark;";
  };

  # Filtre : démon qui pose le shader voulu (horaires fixes ou soleil de la ville, fondu
  # de 30 min), le réapplique après un rechargement d'Hyprland, l'enlève à l'arrêt
  systemd.user.services.crepuscule-filter = {
    Unit = {
      Description = "Filtre anti-lumière bleue (shader Hyprland, réglé par Crépuscule)";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecCondition = "${crepuscule-ctl}/bin/crepuscule-ctl enabled";
      ExecStart = "${crepuscule-ctl}/bin/crepuscule-ctl daemon";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  # Heures du soleil (mode sombre « soleil ») recalculées chaque jour ; Persistent
  # rattrape un PC éteint à cette heure
  systemd.user.services.crepuscule-daily = {
    Unit.Description = "Recalcul des heures de lever / coucher du soleil (Crépuscule)";
    Service = {
      Type = "oneshot";
      ExecStart = "${crepuscule-ctl}/bin/crepuscule-ctl apply";
    };
  };
  systemd.user.timers.crepuscule-daily = {
    Unit.Description = "Recalcul quotidien des heures du soleil (Crépuscule)";
    Timer = {
      OnCalendar = "00:05";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
