{ pkgs, ... }:

{
  # --- Theme Rofi pour le presse-papiers ---
  xdg.configFile."rofi/clipboard.rasi".text = ''
    configuration {
        show-icons: false;
        font: "Inter 12";
    }
    * {
        background-color: transparent;
        text-color: #ffffff;
    }
    window {
        width: 500px;
        border: 2px;
        border-color: rgba(255, 255, 255, 0.2);
        border-radius: 15px;
        background-color: rgba(0, 0, 0, 0.25);
        padding: 10px;
    }
    mainbox { spacing: 10px; }
    inputbar {
        padding: 8px 12px;
        margin: 0px 0px 4px 0px;
        background-color: rgba(255, 255, 255, 0.05);
        border: 1px;
        border-color: rgba(255, 255, 255, 0.1);
        border-radius: 10px;
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
    listview { lines: 8; spacing: 6px; scrollbar: false; }
    element { padding: 10px; border-radius: 10px; }
    element-text {
        background-color: transparent;
        text-color: #ffffff;
        font: "Inter 10";
    }
    element selected {
        background-color: rgba(255, 255, 255, 0.1);
        border: 2px;
        border-color: #ffffff;
    }
  '';

  # --- Script clipboard-manager ---
  home.packages = [
    (pkgs.writeShellScriptBin "clipboard-manager" ''
      if pgrep -x rofi > /dev/null; then
        pkill -x rofi
        exit 0
      fi

      SELECTED=$(${pkgs.cliphist}/bin/cliphist list | ${pkgs.rofi}/bin/rofi -dmenu -i -p "󰅇 " -theme ~/.config/rofi/clipboard.rasi)

      [ -z "$SELECTED" ] && exit 0

      echo "$SELECTED" | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy

      sleep 0.4
      ${pkgs.wtype}/bin/wtype -M ctrl -k v -m ctrl
    '')
  ];
}
