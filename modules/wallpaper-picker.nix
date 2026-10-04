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

  # Applique un fond d'écran (transition aléatoire) et notifie
  wallpaper-apply = pkgs.writeShellScriptBin "wallpaper-apply" ''
    F="$1"
    [ -f "$F" ] || exit 1
    ${pkgs.awww}/bin/awww img "$F" --transition-type random --transition-step 90 --transition-fps 60
    ${pkgs.libnotify}/bin/notify-send "Wallpaper" "Appliqué : ''${F##*/}" -i "$F"
  '';

  # Ancien sélecteur (rofi), gardé en secours si le menu Quickshell ne répond pas
  wallpaper-picker-rofi = pkgs.writeShellScriptBin "wallpaper-picker-rofi" ''
    if pgrep -x rofi > /dev/null; then
      pkill -x rofi
      exit 0
    fi
    export WALL_DIR="$HOME/Pictures/Wallpapers"

    if [ ! -d "$WALL_DIR" ]; then
      ${pkgs.libnotify}/bin/notify-send "Erreur" "Dossier $WALL_DIR introuvable."
      exit 1
    fi

    SELECTION=$(
      for file in "$WALL_DIR"/*; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        echo -en "$filename\0icon\x1f$file\n"
      done | ${pkgs.rofi}/bin/rofi -dmenu -i -p "󰋩 " -theme ~/.config/rofi/wallpaper.rasi
    )

    if [ -n "$SELECTION" ]; then
      ${wallpaper-apply}/bin/wallpaper-apply "$WALL_DIR/$SELECTION"
    fi
  '';

  # SUPER+W : affiche / masque le sélecteur Quickshell (config « launcher », voir app-launcher.nix)
  wallpaper-picker = pkgs.writeShellScriptBin "wallpaper-picker" ''
    ${quickshell}/bin/quickshell ipc -c launcher call wallpaper toggle >/dev/null 2>&1 \
      || exec ${wallpaper-picker-rofi}/bin/wallpaper-picker-rofi
  '';
in
{
  # --- Theme Rofi pour le sélecteur de secours (style Wofi/app-launcher) ---
  xdg.configFile."rofi/wallpaper.rasi".text = ''
    configuration {
      show-icons: true;
      font: "Inter 11";
      hover-select: true;
      me-select-entry: "";
      me-accept-entry: "MousePrimary";
    }
    * {
      background-color: transparent;
      text-color: #ffffff;
    }
    window {
      width: 1000px;
      height: 800px;
      border: 2px;
      border-color: rgba(255, 255, 255, 0.2);
      border-radius: 15px;
      background-color: rgba(0, 0, 0, 0.25);
    }
    listview {
      columns: 3;
      lines: 3;
      spacing: 20px;
      padding: 20px;
      cycle: true;
      scrollbar: true;
      fixed-columns: true;
    }
    element {
      orientation: vertical;
      padding: 10px;
      border-radius: 10px;
    }
    element selected {
      background-color: rgba(255, 255, 255, 0.15);
      border: 2px;
      border-color: #ffffff;
    }
    element-icon {
      size: 250px;
      horizontal-align: 0.5;
    }
    element-text {
      enabled: false;
    }
    inputbar {
      padding: 8px 12px;
      margin: 10px;
      border-radius: 10px;
      background-color: rgba(255, 255, 255, 0.05);
      border: 1px;
      border-color: rgba(255, 255, 255, 0.1);
      children: [prompt, textbox-prompt-sep, entry];
    }
    prompt {
      color: rgba(255, 255, 255, 0.7);
      font: "JetBrainsMono Nerd Font 14";
      vertical-align: 0.5;
      padding: 0px 4px 0px 0px;
    }
    textbox-prompt-sep {
      str: "│";
      expand: false;
      color: rgba(255, 255, 255, 0.2);
      vertical-align: 0.5;
      padding: 0px 8px;
    }
    entry {
      color: #ffffff;
      placeholder: "Rechercher...";
      placeholder-color: rgba(255, 255, 255, 0.3);
      vertical-align: 0.5;
    }
  '';

  # --- Scripts : sélecteur (SUPER+W), secours rofi, index et application ---
  home.packages = [ wallpaper-picker wallpaper-picker-rofi wallpaper-index wallpaper-apply ];
}
