{ pkgs, ... }:

# Mode Cours : les notifications sont muettes sur la sortie audio du PC
# (haut-parleurs, HDMI…) mais gardent leur son si la sortie par défaut est
# Bluetooth (AirPods). swaync n'a pas de son natif : le son est joué par le
# script `notif-sound` (run-on receive, déclaré dans swaync.nix).
#   cours [toggle|on|off|auto|status]    lié à SUPER+SHIFT+C
# Automatique : le démon cours-sync (assets/cours-sync.py) lit l'emploi du temps
# Atlas et active le mode pendant les cours (hors cours annulés). Un forçage
# manuel (on/off) tient jusqu'au prochain début ou fin de cours.
let
  sound = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message-new-instant.oga";
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "cours" ''
      D="''${XDG_RUNTIME_DIR:-/tmp}"
      on() { [ -e "$D/cours-off" ] && return 1; [ -e "$D/cours-mode" ] || [ -e "$D/cours-auto" ]; }
      case "''${1:-toggle}" in
        status) on && echo on || echo off; exit 0 ;;
        auto)   rm -f "$D/cours-mode" "$D/cours-off" ;;
        on)     rm -f "$D/cours-off"; touch "$D/cours-mode" ;;
        off)    rm -f "$D/cours-mode"; touch "$D/cours-off" ;;
        toggle) if on; then "$0" off; else "$0" on; fi; exit 0 ;;
        *)      echo "usage : cours [toggle|on|off|auto|status]" >&2; exit 1 ;;
      esac
      if on; then
        ${pkgs.libnotify}/bin/notify-send -a "Cours" -h string:x-canonical-private-synchronous:cours \
          "Mode Cours activé" "Notifications muettes sauf sur les AirPods"
      else
        ${pkgs.libnotify}/bin/notify-send -a "Cours" -h string:x-canonical-private-synchronous:cours \
          "Mode Cours désactivé" "Le son des notifications est revenu"
      fi
    '')

    (pkgs.writeShellScriptBin "notif-sound" ''
      # En mode Cours : son uniquement si la sortie par défaut est Bluetooth
      if [ "$(cours status)" = on ]; then
        ${pkgs.wireplumber}/bin/wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep -qiE 'bluez' || exit 0
      fi
      exec ${pkgs.pipewire}/bin/pw-play ${sound}
    '')
  ];

  systemd.user.services.cours-sync = {
    Unit = {
      Description = "Mode Cours automatique (emploi du temps Atlas)";
      After = [ "hyprland-session.target" "network-online.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      Environment = [ "COURS_NOTIFY=${pkgs.libnotify}/bin/notify-send" ];
      ExecStart = "${pkgs.python3}/bin/python3 ${../assets/cours-sync.py} ${../assets/atlas-task.py}";
      Restart = "on-failure";
      RestartSec = 30;
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  wayland.windowManager.hyprland.extraConfig = ''
    hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("cours toggle"))
  '';
}
