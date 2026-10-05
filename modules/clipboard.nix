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


  # SUPER+V : affiche / masque le presse-papiers Quickshell (config « launcher », voir app-launcher.nix)
  clipboard-manager = pkgs.writeShellScriptBin "clipboard-manager" ''
    ${quickshell}/bin/quickshell ipc -c launcher call clipboard toggle >/dev/null 2>&1
  '';
in
{

  # --- Scripts : menu (SUPER+V), index / aperçu / collage / suppression / vidage ---
  home.packages = [
    clipboard-manager
    clipboard-index
    clipboard-show
    clipboard-paste
    clipboard-delete
    clipboard-wipe
  ];
}
