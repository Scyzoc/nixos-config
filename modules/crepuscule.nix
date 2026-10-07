# crepuscule.nix — Crépuscule : filtre anti-lumière bleue (gammastep) et mode sombre
# Interface Quickshell (quickshell-launcher/Crepuscule.qml), ouverte depuis le menu
# d'applications ; backend assets/crepuscule.py, config dans ~/.config/crepuscule/.
# Remplace l'ancien services.gammastep (lat/lon fixes).
{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;

  crepuscule-ctl = pkgs.writeShellScriptBin "crepuscule-ctl" ''
    export CREPUSCULE_SYSTEMCTL=${pkgs.systemd}/bin/systemctl
    export CREPUSCULE_GSETTINGS=${pkgs.glib}/bin/gsettings
    export CREPUSCULE_THEME=${config.home.profileDirectory}/bin/theme
    exec ${pkgs.python3}/bin/python3 ${../assets/crepuscule.py} "$@"
  '';

  # Affiche / masque la fenêtre (config Quickshell « launcher », voir app-launcher.nix)
  crepuscule = pkgs.writeShellScriptBin "crepuscule" ''
    ${quickshell}/bin/quickshell ipc -c launcher call crepuscule toggle >/dev/null 2>&1
  '';
in
{
  home.packages = [ pkgs.gammastep crepuscule crepuscule-ctl ];

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

  # Filtre : gammastep avec la config générée (horaires fixes ou soleil de la ville)
  systemd.user.services.crepuscule-filter = {
    Unit = {
      Description = "Filtre anti-lumière bleue (gammastep, réglé par Crépuscule)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecCondition = "${crepuscule-ctl}/bin/crepuscule-ctl enabled";
      ExecStartPre = "${crepuscule-ctl}/bin/crepuscule-ctl gen";
      ExecStart = "${pkgs.gammastep}/bin/gammastep -c %h/.config/crepuscule/gammastep.ini";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Heures du soleil recalculées chaque jour à midi (filtre inactif : le redémarrage
  # de gammastep ne se voit pas) ; Persistent rattrape un PC éteint à midi
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
      OnCalendar = "12:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
