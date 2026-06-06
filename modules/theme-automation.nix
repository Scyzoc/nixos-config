# theme-automation.nix
{ config, pkgs, lib, ... }:

let
  # Définis tes heures de basculement ici
  darkHour = "20:00:00";
  lightHour = "08:00:00";

  # Script généré dynamiquement qui bascule le thème via gsettings
  toggleTheme = mode: pkgs.writeShellScript "set-theme-${mode}" ''
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme '${if mode == "dark" then "prefer-dark" else "default"}'
    
    # Optionnel : Envoyer une notification pour confirmer le changement
    ${pkgs.libnotify}/bin/notify-send "Thème" "Passage en mode ${mode}" -u low
  '';
in
{
  # S'assurer que le portail XDG et glib sont disponibles pour que gsettings fonctionne
  home.packages = [ pkgs.glib ];

  # --- SERVICES SYSTEMD UTILISATEUR ---

  systemd.user.services.set-dark-mode = {
    Unit.Description = "Appliquer le mode sombre";
    Service = {
      Type = "oneshot";
      ExecStart = "${toggleTheme "dark"}";
    };
  };

  systemd.user.services.set-light-mode = {
    Unit.Description = "Appliquer le mode clair";
    Service = {
      Type = "oneshot";
      ExecStart = "${toggleTheme "light"}";
    };
  };

  # --- TIMERS SYSTEMD UTILISATEUR ---

  systemd.user.timers.set-dark-mode = {
    Unit.Description = "Declencheur pour le mode sombre";
    Timer = {
      OnCalendar = darkHour;
      Persistent = true; # Si le PC était éteint à 20h, il passera en sombre au prochain démarrage
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.timers.set-light-mode = {
    Unit.Description = "Declencheur pour le mode clair";
    Timer = {
      OnCalendar = lightHour;
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
