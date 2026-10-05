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
    KEY=$(printf '%s' "''${F##*/}" | ${pkgs.coreutils}/bin/md5sum | ${pkgs.coreutils}/bin/cut -c1-16)
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

  # Liste lue par le menu Quickshell (WallpaperPicker.qml) : une ligne « current <chemin> »
  # (fond affiché), puis une ligne par image de ~/Pictures/Wallpapers (voir wallpaper-thumb).
  # Miniatures créées en parallèle : ~6 s la première fois pour 50 images, ~0,4 s ensuite.
  wallpaper-index = pkgs.writeShellScriptBin "wallpaper-index" ''
    WALL_DIR="$HOME/Pictures/Wallpapers"
    ${pkgs.coreutils}/bin/mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-picker"
    printf 'current\t%s\n' "$(${pkgs.awww}/bin/awww query 2>/dev/null \
      | ${pkgs.gnused}/bin/sed -n 's/.*currently displaying: image: //p' | ${pkgs.coreutils}/bin/head -1)"
    [ -d "$WALL_DIR" ] || exit 0
    ${pkgs.findutils}/bin/find -L "$WALL_DIR" -maxdepth 1 -type f -print0 \
      | ${pkgs.findutils}/bin/xargs -0 -r -P 6 -n 1 ${wallpaper-thumb}
  '';

  # Dernier fond choisi : le cache d'awww est par nom de sortie (DP-3, DP-7…) et le
  # dock renomme les écrans à chaque branchement → un nouveau nom n'a pas d'image.
  wallpaperState = "${config.xdg.stateHome}/wallpaper/current";

  # Applique un fond d'écran (transition aléatoire) et notifie
  wallpaper-apply = pkgs.writeShellScriptBin "wallpaper-apply" ''
    F="$1"
    [ -f "$F" ] || exit 1
    ${pkgs.awww}/bin/awww img "$F" --transition-type random --transition-step 90 --transition-fps 60
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "${wallpaperState}")"
    printf '%s\n' "$F" > "${wallpaperState}"
    ${pkgs.libnotify}/bin/notify-send "Wallpaper" "Appliqué : ''${F##*/}" -i "$F"
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
      ${pkgs.hyprland}/bin/hyprctl dispatch exec ${pkgs.awww}/bin/awww-daemon >/dev/null
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        $AWWW query >/dev/null 2>&1 && break
        ${pkgs.coreutils}/bin/sleep 0.3
      done
    fi

    $AWWW img "$F" --transition-type none
  '';


  # SUPER+W : affiche / masque le sélecteur Quickshell (config « launcher », voir app-launcher.nix)
  wallpaper-picker = pkgs.writeShellScriptBin "wallpaper-picker" ''
    ${quickshell}/bin/quickshell ipc -c launcher call wallpaper toggle >/dev/null 2>&1
  '';
in
{

  # --- Scripts : sélecteur (SUPER+W), index et application ---
  home.packages = [ wallpaper-picker wallpaper-index wallpaper-apply wallpaper-restore ];
}
