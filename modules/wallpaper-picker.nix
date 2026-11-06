{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;
  magick = "${pkgs.imagemagick}/bin/magick";

  # Miniature + luminosité moyenne d'une image, en cache (~/.cache/wallpaper-picker),
  # recalculées seulement si l'image a changé. Affiche « luminosité <miniature> <image> »
  # (séparés par des tabulations) ; rien si le fichier n'est pas une image lisible.
  wallpaper-thumb = pkgs.writeShellScript "wallpaper-thumb" ''
    F="$1"
    CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-picker"
    KEY=$(printf '%s' "$F" | ${pkgs.coreutils}/bin/md5sum | ${pkgs.coreutils}/bin/cut -c1-16)
    THUMB="$CACHE/$KEY.jpg"
    LUM="$CACHE/$KEY.lum"
    if [ ! -s "$THUMB" ] || [ ! -s "$LUM" ] || [ "$F" -nt "$THUMB" ]; then
      ${magick} "$F[0]" -auto-orient -thumbnail '640x360^' -gravity center -extent 640x360 \
        -quality 88 "$THUMB.tmp.jpg" 2>/dev/null || exit 0
      ${pkgs.coreutils}/bin/mv "$THUMB.tmp.jpg" "$THUMB"
      ${magick} "$THUMB" -colorspace Gray -format '%[fx:mean]' info: > "$LUM"
    fi
    printf '%s\t%s\t%s\n' "$(${pkgs.coreutils}/bin/cat "$LUM")" "$THUMB" "$F"
  '';

  # Dossier lu par le sélecteur : « wallpaper-dir » l'affiche (défaut ~/Pictures/Wallpapers),
  # « wallpaper-dir set <chemin> » le change (~ accepté, le dossier doit exister).
  wallpaper-dir = pkgs.writeShellScriptBin "wallpaper-dir" ''
    STATE="${config.xdg.stateHome}/wallpaper/dir"
    if [ "$1" = set ]; then
      D="$2"
      case "$D" in "~") D="$HOME" ;; "~/"*) D="$HOME/''${D#\~/}" ;; esac
      [ -d "$D" ] || exit 1
      D=$(${pkgs.coreutils}/bin/realpath "$D")
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$STATE")"
      printf '%s\n' "$D" > "$STATE"
      exit 0
    fi
    D=$(${pkgs.coreutils}/bin/cat "$STATE" 2>/dev/null)
    [ -d "$D" ] || D="$HOME/Pictures/Wallpapers"
    printf '%s\n' "$D"
  '';

  # Met une image à la corbeille (récupérable)
  wallpaper-delete = pkgs.writeShellScriptBin "wallpaper-delete" ''
    [ -f "$1" ] && ${pkgs.glib}/bin/gio trash "$1"
  '';

  # Liste lue par le menu Quickshell (WallpaperPicker.qml) : une ligne « current <chemin> »
  # (fond affiché), puis une ligne par image de ~/Pictures/Wallpapers (voir wallpaper-thumb).
  # Miniatures créées en parallèle : ~6 s la première fois pour 50 images, ~0,4 s ensuite.
  wallpaper-index = pkgs.writeShellScriptBin "wallpaper-index" ''
    WALL_DIR=$(${wallpaper-dir}/bin/wallpaper-dir)
    ${pkgs.coreutils}/bin/mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-picker"
    printf 'dir\t%s\n' "$WALL_DIR"
    printf 'span\t%s\n' "$(${wallpaper-span-mode}/bin/wallpaper-span-mode)"
    CUR=$(${pkgs.coreutils}/bin/cat "${wallpaperState}" 2>/dev/null)
    [ -f "$CUR" ] || CUR=$(${pkgs.awww}/bin/awww query 2>/dev/null \
      | ${pkgs.gnused}/bin/sed -n 's/.*currently displaying: image: //p' | ${pkgs.coreutils}/bin/head -1)
    printf 'current\t%s\n' "$CUR"
    [ -d "$WALL_DIR" ] || exit 0
    ${pkgs.findutils}/bin/find -L "$WALL_DIR" -maxdepth 1 -type f -print0 \
      | ${pkgs.findutils}/bin/xargs -0 -r -P 6 -n 1 ${wallpaper-thumb}
  '';

  # Dernier fond choisi : le cache d'awww est par nom de sortie (DP-3, DP-7…) et le
  # dock renomme les écrans à chaque branchement → un nouveau nom n'a pas d'image.
  wallpaperState = "${config.xdg.stateHome}/wallpaper/current";

  # Mode « étendu » : une seule image répartie sur tous les écrans (drapeau d'état 0/1)
  spanFlag = "${config.xdg.stateHome}/wallpaper/span";
  wallpaper-span = pkgs.writeShellScript "wallpaper-span" ''
    export AWWW=${pkgs.awww}/bin/awww MAGICK=${magick} HYPRCTL=${pkgs.hyprland}/bin/hyprctl
    export SPAN_CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-picker/span"
    exec ${pkgs.python3}/bin/python3 ${../assets/wallpaper-span.py} "$@"
  '';
  # wallpaper-span-mode [on|off|toggle|state] : change le mode et réapplique le fond actuel
  wallpaper-span-mode = pkgs.writeShellScriptBin "wallpaper-span-mode" ''
    FLAG="${spanFlag}"
    CUR=$(${pkgs.coreutils}/bin/cat "$FLAG" 2>/dev/null); [ "$CUR" = 1 ] || CUR=0
    case "$1" in
      on) NEW=1 ;; off) NEW=0 ;; toggle) NEW=$((1 - CUR)) ;;
      *) echo "$CUR"; exit 0 ;;
    esac
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$FLAG")"
    echo "$NEW" > "$FLAG"
    F=$(${pkgs.coreutils}/bin/cat "${wallpaperState}" 2>/dev/null)
    [ -f "$F" ] && exec ${wallpaper-apply}/bin/wallpaper-apply "$F"
    echo "$NEW"
  '';

  # Applique un fond d'écran (fondu doux, courbe ease-out) et notifie
  wallpaper-apply = pkgs.writeShellScriptBin "wallpaper-apply" ''
    F="$1"
    [ -f "$F" ] || exit 1
    if [ "$(${pkgs.coreutils}/bin/cat "${spanFlag}" 2>/dev/null)" = 1 ]; then
      ${wallpaper-span} "$F" fade || exit 1
    else
      ${pkgs.awww}/bin/awww img "$F" \
        --transition-type fade --transition-duration 1.2 \
        --transition-bezier .25,.1,.25,1 --transition-fps 144
    fi
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "${wallpaperState}")"
    printf '%s\n' "$F" > "${wallpaperState}"
  '';

  # Réaffiche le dernier fond sur tous les écrans, sans transition. Appelé après chaque
  # (dé)branchement d'écran (display-switch.nix) : un écran au nom jamais vu, ou
  # reconfiguré (résolution / échelle) juste après son apparition, restait sans fond.
  wallpaper-restore = pkgs.writeShellScriptBin "wallpaper-restore" ''
    AWWW=${pkgs.awww}/bin/awww
    F=$(${pkgs.coreutils}/bin/cat "${wallpaperState}" 2>/dev/null)
    if [ ! -f "$F" ]; then
      F=$($AWWW query 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's/.*currently displaying: image: //p' | ${pkgs.coreutils}/bin/head -1)
    fi
    [ -f "$F" ] || exit 0

    # Démon absent (planté) : relancé via Hyprland pour qu'il ne dépende pas de l'appelant
    if ! $AWWW query >/dev/null 2>&1; then
      ${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.exec_cmd("${pkgs.awww}/bin/awww-daemon")' >/dev/null
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        $AWWW query >/dev/null 2>&1 && break
        ${pkgs.coreutils}/bin/sleep 0.3
      done
    fi

    if [ "$(${pkgs.coreutils}/bin/cat "${spanFlag}" 2>/dev/null)" = 1 ]; then
      ${wallpaper-span} "$F" none
    else
      $AWWW img "$F" --transition-type none
    fi
  '';


  # SUPER+W : affiche / masque le sélecteur Quickshell (config « launcher », voir app-launcher.nix)
  wallpaper-picker = pkgs.writeShellScriptBin "wallpaper-picker" ''
    ${quickshell}/bin/quickshell ipc -c launcher call wallpaper toggle >/dev/null 2>&1
  '';
in
{

  # --- Scripts : sélecteur (SUPER+W), index et application ---
  home.packages = [ wallpaper-picker wallpaper-index wallpaper-apply wallpaper-restore wallpaper-dir wallpaper-delete wallpaper-span-mode ];
}
