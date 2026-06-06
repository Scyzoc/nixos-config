{ pkgs, ... }:

{
  # --- Theme Rofi pour le sélecteur de wallpapers (style Wofi/app-launcher) ---
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

  # --- Script wallpaper-picker ---
  home.packages = [
    (pkgs.writeShellScriptBin "wallpaper-picker" ''
      if pgrep -x rofi > /dev/null; then
        pkill -x rofi
        exit 0
      fi
      export WALL_DIR="$HOME/Pictures/Wallpapers"
      export AWWW_TRANSITION_FPS=60
      export AWWW_TRANSITION_STEP=90
      export AWWW_TRANSITION_TYPE=grow

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
        ${pkgs.awww}/bin/awww img "$WALL_DIR/$SELECTION" --transition-type random --transition-step 90 --transition-fps 60
        ${pkgs.libnotify}/bin/notify-send "Wallpaper" "Appliqué : $SELECTION" -i "$WALL_DIR/$SELECTION"
      fi
    '')
  ];
}
