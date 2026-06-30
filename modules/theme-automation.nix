# theme-automation.nix
{ config, pkgs, lib, ... }:

let
  darkHour = "20:00:00";
  lightHour = "08:00:00";

  toggleTheme = mode: pkgs.writeShellScript "set-theme-${mode}" ''
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme '${if mode == "dark" then "prefer-dark" else "default"}'
    ${pkgs.libnotify}/bin/notify-send "Thème" "Passage en mode ${mode}" -u low
  '';

  themeCli = pkgs.writeShellScriptBin "theme" ''
    MODE="''${1:-}"
    GSETTINGS="${pkgs.glib}/bin/gsettings"
    NOTIFY="${pkgs.libnotify}/bin/notify-send"

    case "$MODE" in
      dark)
        $GSETTINGS set org.gnome.desktop.interface color-scheme 'prefer-dark'
        $NOTIFY "Thème" "Mode sombre activé" -u low
        ;;
      light)
        $GSETTINGS set org.gnome.desktop.interface color-scheme 'default'
        $NOTIFY "Thème" "Mode clair activé" -u low
        ;;
      auto)
        HOUR=$(date +%H)
        if [ "$HOUR" -ge 20 ] || [ "$HOUR" -lt 8 ]; then
          $GSETTINGS set org.gnome.desktop.interface color-scheme 'prefer-dark'
          $NOTIFY "Thème" "Mode auto → sombre (timers actifs)" -u low
        else
          $GSETTINGS set org.gnome.desktop.interface color-scheme 'default'
          $NOTIFY "Thème" "Mode auto → clair (timers actifs)" -u low
        fi
        ;;
      *)
        echo "Usage: theme dark|light|auto"
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ pkgs.glib themeCli ];

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
