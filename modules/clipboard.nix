{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;
  cliphist = "${pkgs.cliphist}/bin/cliphist";

  # Liste lue par le menu Quickshell (ClipboardPicker.qml) : les lignes « id <aperçu> » de
  # cliphist (plus récente d'abord). Pour une image, un 3e champ donne le fichier décodé,
  # gardé en cache (~/.cache/clipboard-picker) tant que l'entrée existe. Tabulations.
  clipboard-index = pkgs.writeShellScriptBin "clipboard-index" ''
    CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/clipboard-picker"
    ${pkgs.coreutils}/bin/mkdir -p -m 700 "$CACHE"
    declare -A KEEP
    while IFS=$'\t' read -r ID REST; do
      case "$REST" in
        "[[ binary data "*)
          # « [[ binary data 12 KiB png 205x109 ]] » : le 6e mot est le format
          read -r _ _ _ _ _ EXT _ <<< "$REST"
          F="$CACHE/$ID.$EXT"
          [ -s "$F" ] || ${cliphist} decode "$ID" > "$F" 2>/dev/null
          KEEP["$ID.$EXT"]=1
          printf '%s\t%s\t%s\n' "$ID" "$REST" "$F"
          ;;
        *) printf '%s\t%s\n' "$ID" "$REST" ;;
      esac
    done < <(${cliphist} list)
    # Images dont l'entrée a disparu de l'historique
    for F in "$CACHE"/*; do
      [ -e "$F" ] || continue
      [ -n "''${KEEP[''${F##*/}]:-}" ] || ${pkgs.coreutils}/bin/rm -f "$F"
    done
  '';

  # Contenu complet d'une entrée (aperçu du menu), limité à 20 ko
  clipboard-show = pkgs.writeShellScriptBin "clipboard-show" ''
    ${cliphist} decode "$1" | ${pkgs.coreutils}/bin/head -c 20000
  '';

  # Copie une entrée puis la colle dans la fenêtre active (Ctrl+V) ; « copy » : copie seule
  clipboard-paste = pkgs.writeShellScriptBin "clipboard-paste" ''
    ${cliphist} decode "$1" | ${pkgs.wl-clipboard}/bin/wl-copy
    [ "''${2:-}" = copy ] && exit 0
    # Le temps que le menu se ferme et que la fenêtre reprenne le clavier
    ${pkgs.coreutils}/bin/sleep 0.4
    ${pkgs.wtype}/bin/wtype -M ctrl -k v -m ctrl
  '';

  # Retire une entrée de l'historique
  clipboard-delete = pkgs.writeShellScriptBin "clipboard-delete" ''
    printf '%s\t' "$1" | ${cliphist} delete
    ${pkgs.coreutils}/bin/rm -f "''${XDG_CACHE_HOME:-$HOME/.cache}/clipboard-picker/$1".*
  '';

  # Vide tout : historique cliphist, images en cache et presse-papiers courant
  clipboard-wipe = pkgs.writeShellScriptBin "clipboard-wipe" ''
    ${cliphist} wipe
    ${pkgs.coreutils}/bin/rm -rf "''${XDG_CACHE_HOME:-$HOME/.cache}/clipboard-picker"
    ${pkgs.wl-clipboard}/bin/wl-copy --clear
  '';

  # Ancien menu (rofi), gardé en secours si le menu Quickshell ne répond pas
  clipboard-manager-rofi = pkgs.writeShellScriptBin "clipboard-manager-rofi" ''
    if pgrep -x rofi > /dev/null; then
      pkill -x rofi
      exit 0
    fi

    SELECTED=$(${cliphist} list | ${pkgs.rofi}/bin/rofi -dmenu -i -p "󰅇 " -theme ~/.config/rofi/clipboard.rasi)

    [ -z "$SELECTED" ] && exit 0

    echo "$SELECTED" | ${cliphist} decode | ${pkgs.wl-clipboard}/bin/wl-copy

    sleep 0.4
    ${pkgs.wtype}/bin/wtype -M ctrl -k v -m ctrl
  '';

  # SUPER+V : affiche / masque le presse-papiers Quickshell (config « launcher », voir app-launcher.nix)
  clipboard-manager = pkgs.writeShellScriptBin "clipboard-manager" ''
    ${quickshell}/bin/quickshell ipc -c launcher call clipboard toggle >/dev/null 2>&1 \
      || exec ${clipboard-manager-rofi}/bin/clipboard-manager-rofi
  '';
in
{
  # --- Theme Rofi pour le presse-papiers de secours ---
  xdg.configFile."rofi/clipboard.rasi".text = ''
    configuration {
        show-icons: false;
        font: "Inter 12";
        me-select-entry: "";
        me-accept-entry: "MousePrimary";
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

  # --- Scripts : menu (SUPER+V), secours rofi, index / aperçu / collage / suppression / vidage ---
  home.packages = [
    clipboard-manager
    clipboard-manager-rofi
    clipboard-index
    clipboard-show
    clipboard-paste
    clipboard-delete
    clipboard-wipe
  ];
}
