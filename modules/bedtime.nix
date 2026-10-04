# bedtime.nix — Rappels pour aller se coucher, de plus en plus insistants à partir de 23h
# Overlay plein écran (layer-shell, fond flouté par Hyprland) + son.
{ config, pkgs, lib, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ps.pycairo ]);

  bedtime-overlay = pkgs.writeShellScriptBin "bedtime-overlay" ''
    export GI_TYPELIB_PATH=${lib.makeSearchPath "lib/girepository-1.0" [
      pkgs.gtk3
      pkgs.gtk-layer-shell
      pkgs.glib.out
      pkgs.pango.out
      pkgs.gdk-pixbuf
      pkgs.harfbuzz
      pkgs.atk
      pkgs.gobject-introspection
    ]}
    export GDK_BACKEND=wayland
    # grim : capture d'écran servant de fond flouté (même rendu que hyprlock)
    # systemd : boutons « Veille » (suspend) et « Éteindre » (poweroff) de l'overlay
    export PATH="${lib.makeBinPath [ pkgs.grim pkgs.systemd ]}:$PATH"
    exec ${pythonEnv}/bin/python3 ${../assets/bedtime-overlay.py} "$@"
  '';

  bedtimeReminder = pkgs.writeShellScriptBin "bedtime-reminder" ''
    export PATH="${lib.makeBinPath [ pkgs.pipewire pkgs.coreutils pkgs.procps pkgs.playerctl ]}:$PATH"

    SON="${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/dialog-warning.oga"

    H=$((10#$(date +%H)))
    M=$((10#$(date +%M)))

    ding() {
      pw-play "$SON" 2>/dev/null || true
    }

    # $1 = niveau (1-4), $2 = titre, $3 = message
    # Bloquant : le service oneshot doit rester vivant tant que l'overlay est affiché,
    # sinon systemd tue le groupe de contrôle et l'overlay disparaît aussitôt.
    rappel() {
      pkill -f bedtime-overlay.py 2>/dev/null || true
      # À partir du niveau 2 : coupe la musique/vidéo en cours pour décrocher.
      [ "$1" -ge 2 ] && (playerctl --all-players pause 2>/dev/null || true)
      [ "$1" -ge 3 ] && ding
      ${bedtime-overlay}/bin/bedtime-overlay "$1" "$2" "$3"
      # Niveau 4 : il revient 90 s après la fermeture, tant que le créneau dure.
      if [ "$1" -ge 4 ]; then
        sleep 90
        H=$((10#$(date +%H)))
        if [ "$H" -eq 0 ] || [ "$H" -eq 1 ] || { [ "$H" -ge 2 ] && [ "$H" -lt 5 ]; }; then
          playerctl --all-players pause 2>/dev/null || true
          ding
          ${bedtime-overlay}/bin/bedtime-overlay "$1" "$2" "$3"
        fi
      fi
    }

    if [ "$1" = "--test" ]; then
      rappel "''${2:-2}" "󰒲  Test du rappel" "Ceci est un aperçu de l'overlay."
      exit 0
    fi

    if   [ "$H" -eq 23 ] && [ "$M" -lt 30 ]; then
      # 23h00–23h29 : rappel doux, toutes les 30 min
      if [ $((M % 30)) -eq 0 ]; then
        rappel 1 "Il est 23h" "Pense à aller te coucher."
      fi

    elif [ "$H" -eq 23 ]; then
      # 23h30–23h59 : toutes les 10 min
      if [ $((M % 10)) -eq 0 ]; then
        rappel 2 "Sérieusement, au lit" "Tu avais dit 23h."
      fi

    elif [ "$H" -eq 0 ]; then
      # minuit–00h59 : toutes les 10 min + son
      if [ $((M % 10)) -eq 0 ]; then
        rappel 3 "Minuit est passé" "Va te coucher. Maintenant."
      fi

    elif [ "$H" -eq 1 ]; then
      # 01h–01h59 : toutes les 5 min + son
      if [ $((M % 5)) -eq 0 ]; then
        rappel 4 "Il est une heure du matin" "Tu vas le regretter demain."
      fi

    elif [ "$H" -ge 2 ] && [ "$H" -lt 5 ]; then
      # 02h–04h59 : toutes les 5 min + double son
      if [ $((M % 5)) -eq 0 ]; then
        rappel 4 "Là ça devient ridicule" "DORS."
      fi
    fi

    exit 0
  '';
in
{
  home.packages = [ bedtimeReminder bedtime-overlay pkgs.sound-theme-freedesktop ];

  systemd.user.services.bedtime-reminder = {
    Unit.Description = "Rappel pour aller se coucher";
    Service = {
      Type = "oneshot";
      # L'overlay bloque le service : niveau 4 = affichage + relance après 90 s.
      TimeoutStartSec = "900";
      ExecStart = "${bedtimeReminder}/bin/bedtime-reminder";
    };
  };

  systemd.user.timers.bedtime-reminder = {
    Unit.Description = "Déclencheur des rappels de coucher";
    Timer = {
      # toutes les 5 minutes ; le script décide s'il affiche l'overlay
      OnCalendar = "*-*-* 23,00,01,02,03,04:00/5:00";
      Persistent = false;
      AccuracySec = "30s";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
