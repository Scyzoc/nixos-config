# theme-automation.nix
{ config, pkgs, lib, ... }:

let
  # Heures par défaut, écrites dans ~/.config/theme-automation/hours.conf au premier lancement.
  # Modifiables sans rebuild via : theme hours 21:00 08:00 (ou l'appli Crépuscule, crepuscule.nix)
  # MODE : hours (heures fixes), sun (lever / coucher du soleil, calculés par Crépuscule
  # dans sunConf), manual (le timer ne change plus rien, theme dark|light seulement)
  defaultDarkHour = "20:00";
  defaultLightHour = "08:00";

  confDir = "$HOME/.config/theme-automation";
  confFile = "${confDir}/hours.conf";
  stateFile = "${confDir}/last-mode";
  sunConf = "$HOME/.config/crepuscule/sun.conf";

  # Bloc commun : charge la conf (et la crée si absente)
  loadConf = ''
    mkdir -p "${confDir}"
    if [ ! -f "${confFile}" ]; then
      printf 'MODE=hours\nDARK_HOUR=%s\nLIGHT_HOUR=%s\n' "${defaultDarkHour}" "${defaultLightHour}" > "${confFile}"
    fi
    MODE=hours
    . "${confFile}"
    EFF_DARK=$DARK_HOUR
    EFF_LIGHT=$LIGHT_HOUR
    if [ "$MODE" = sun ] && [ -f "${sunConf}" ]; then
      . "${sunConf}"
      EFF_DARK=$SUNSET
      EFF_LIGHT=$SUNRISE
    fi
    DARK_MIN=$(( 10#''${EFF_DARK%%:*} * 60 + 10#''${EFF_DARK##*:} ))
    LIGHT_MIN=$(( 10#''${EFF_LIGHT%%:*} * 60 + 10#''${EFF_LIGHT##*:} ))
  '';

  # Détermine le mode attendu à l'instant présent : écrit "dark" ou "light" dans $WANTED
  computeMode = ''
    NOW_MIN=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
    if [ "$DARK_MIN" -gt "$LIGHT_MIN" ]; then
      # Plage sombre à cheval sur minuit (cas normal : 20h → 08h)
      if [ "$NOW_MIN" -ge "$DARK_MIN" ] || [ "$NOW_MIN" -lt "$LIGHT_MIN" ]; then
        WANTED=dark
      else
        WANTED=light
      fi
    else
      if [ "$NOW_MIN" -ge "$DARK_MIN" ] && [ "$NOW_MIN" -lt "$LIGHT_MIN" ]; then
        WANTED=dark
      else
        WANTED=light
      fi
    fi
  '';

  # Boîtes Ouvrir/Enregistrer (portail KDE) : aligne ~/.config/kdeglobals sur le
  # mode GTK courant — couleurs Breeze clair/sombre, icônes Papirus, police Adwaita.
  # Le fichier reste modifiable : la boîte y enregistre aussi ses préférences
  # ([KFileDialog Settings]), on ne remplace que les groupes de thème.
  kdeSync = pkgs.writeShellScript "kde-theme-sync" ''
    set -eu
    KG="$HOME/.config/kdeglobals"
    if [ "$(${pkgs.glib}/bin/gsettings get org.gnome.desktop.interface color-scheme)" = "'prefer-dark'" ]; then
      SCHEME=BreezeDark
    else
      SCHEME=BreezeLight
    fi
    ${pkgs.coreutils}/bin/touch "$KG"
    TMP=$(${pkgs.coreutils}/bin/mktemp)
    ${pkgs.gawk}/bin/awk '/^\[/ { skip = ($0 ~ /^\[(Colors:|ColorEffects:|General\]|Icons\]|KDE\]|WM\])/) } !skip' "$KG" > "$TMP"
    {
      ${pkgs.coreutils}/bin/cat "$TMP"
      ${pkgs.gnugrep}/bin/grep -v '^#' "${pkgs.kdePackages.breeze}/share/color-schemes/$SCHEME.colors"
      printf '\n[General]\nColorScheme=%s\nfont=Adwaita Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n' "$SCHEME"
      printf '\n[Icons]\nTheme=Papirus-Stock\n\n[KDE]\nwidgetStyle=Breeze\n'
    } > "$KG"
    ${pkgs.coreutils}/bin/rm -f "$TMP"
  '';

  # Après un changement de mode : resynchronise et relance le portail KDE s'il tourne
  kdeApply = "${kdeSync} && ${pkgs.systemd}/bin/systemctl --user try-restart plasma-xdg-desktop-portal-kde.service || true";

  # Service périodique : applique le thème attendu, notifie seulement si changement
  themeAuto = pkgs.writeShellScript "theme-auto" ''
    set -eu
    ${loadConf}
    [ "$MODE" = manual ] && exit 0
    ${computeMode}

    LAST=""
    [ -f "${stateFile}" ] && LAST=$(cat "${stateFile}") || true
    [ "$WANTED" = "$LAST" ] && exit 0

    # Déjà dans le bon mode (réglage modifié depuis Crépuscule) : pas de notification
    CUR=light
    [ "$(${pkgs.glib}/bin/gsettings get org.gnome.desktop.interface color-scheme)" = "'prefer-dark'" ] && CUR=dark
    if [ "$WANTED" = "$CUR" ]; then
      printf '%s' "$WANTED" > "${stateFile}"
      exit 0
    fi

    if [ "$WANTED" = "dark" ]; then
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
      ${pkgs.libnotify}/bin/notify-send "Thème" "Passage en mode sombre" -u low
    else
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'default'
      ${pkgs.libnotify}/bin/notify-send "Thème" "Passage en mode clair" -u low
    fi
    printf '%s' "$WANTED" > "${stateFile}"
    ${kdeApply}
  '';

  themeCli = pkgs.writeShellScriptBin "theme" ''
    set -eu
    GSETTINGS="${pkgs.glib}/bin/gsettings"
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    MODE="''${1:-}"

    case "$MODE" in
      dark)
        $GSETTINGS set org.gnome.desktop.interface color-scheme 'prefer-dark'
        $NOTIFY "Thème" "Mode sombre activé" -u low
        ${kdeApply}
        ;;
      light)
        $GSETTINGS set org.gnome.desktop.interface color-scheme 'default'
        $NOTIFY "Thème" "Mode clair activé" -u low
        ${kdeApply}
        ;;
      auto)
        ${loadConf}
        ${computeMode}
        rm -f "${stateFile}"
        ${themeAuto}
        ;;
      hours)
        ${loadConf}
        if [ $# -eq 1 ]; then
          echo "Mode         : $MODE"
          echo "Mode sombre  : $EFF_DARK"
          echo "Mode clair   : $EFF_LIGHT"
          echo "Modifier     : theme hours <dark HH:MM> [light HH:MM]"
          exit 0
        fi
        NEW_DARK="''${2:-$DARK_HOUR}"
        NEW_LIGHT="''${3:-$LIGHT_HOUR}"
        for H in "$NEW_DARK" "$NEW_LIGHT"; do
          case "$H" in
            [0-2][0-9]:[0-5][0-9]) ;;
            *) echo "Heure invalide : $H (format attendu HH:MM)"; exit 1 ;;
          esac
          if [ $(( 10#''${H%%:*} )) -gt 23 ]; then echo "Heure invalide : $H"; exit 1; fi
        done
        printf 'MODE=%s\nDARK_HOUR=%s\nLIGHT_HOUR=%s\n' "$MODE" "$NEW_DARK" "$NEW_LIGHT" > "${confFile}"
        rm -f "${stateFile}"
        ${themeAuto}
        echo "Sombre à $NEW_DARK, clair à $NEW_LIGHT"
        ;;
      mode)
        ${loadConf}
        NEW_MODE="''${2:-}"
        case "$NEW_MODE" in
          hours|sun|manual) ;;
          "") echo "Mode : $MODE (hours|sun|manual)"; exit 0 ;;
          *) echo "Mode invalide : $NEW_MODE (hours|sun|manual)"; exit 1 ;;
        esac
        printf 'MODE=%s\nDARK_HOUR=%s\nLIGHT_HOUR=%s\n' "$NEW_MODE" "$DARK_HOUR" "$LIGHT_HOUR" > "${confFile}"
        rm -f "${stateFile}"
        ${themeAuto}
        ;;
      *)
        echo "Usage: theme dark|light|auto|hours [HH:MM] [HH:MM]|mode [hours|sun|manual]"
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ pkgs.glib themeCli ];

  # Portail KDE (configuration.nix) lancé hors Plasma : on lui fournit le thème
  # de plateforme KDE + le style Breeze, sinon style Fusion sans icônes.
  xdg.configFile."systemd/user/plasma-xdg-desktop-portal-kde.service.d/theme.conf".text = ''
    [Service]
    Environment=QT_QPA_PLATFORMTHEME=kde
    Environment=QT_PLUGIN_PATH=${pkgs.kdePackages.plasma-integration}/lib/qt-6/plugins:${pkgs.kdePackages.breeze}/lib/qt-6/plugins
    ExecStartPre=${kdeSync}
  '';

  # --- SERVICE + TIMER SYSTEMD UTILISATEUR ---

  systemd.user.services.theme-auto = {
    Unit.Description = "Appliquer le thème clair/sombre selon l'heure configurée";
    Service = {
      Type = "oneshot";
      ExecStart = "${themeAuto}";
    };
  };

  systemd.user.timers.theme-auto = {
    Unit.Description = "Vérification périodique du thème clair/sombre";
    Timer = {
      OnCalendar = "*:0/5"; # toutes les 5 minutes
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
