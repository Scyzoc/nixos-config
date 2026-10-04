{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;

  # Données du menu : ordre et catégories Unicode, noms / mots-clés français (CLDR),
  # limités aux emojis que dessine la police par défaut, + planches d'images aux tailles
  # affichées par le menu (28 px au repos, 33 px au survol) (assets/emoji-data.py)
  emojiData = pkgs.runCommand "emoji-data" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.uharfbuzz p.fonttools p.pillow ])) ];
  } ''
    mkdir $out
    python3 ${../assets/emoji-data.py} \
      ${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt \
      ${pkgs.cldr-annotations}/share/unicode/cldr/common \
      ${../fonts/AppleColorEmoji.ttf} \
      $out 28 33
  '';

  # Colle un emoji dans la fenêtre active (Ctrl+V) ; « copy » : copie seule.
  # L'emoji arrive en codepoints hexa (« 1f44d-1f3fd ») : rien à échapper côté Hyprland
  emoji-paste = pkgs.writeShellScriptBin "emoji-paste" ''
    EMOJI=""
    for CP in ''${1//-/ }; do
      printf -v H '%08x' "0x$CP"
      printf -v C "\\U$H"
      EMOJI+=$C
    done
    [ -n "$EMOJI" ] || exit 1
    # Type imposé : sinon wl-copy le devine avec xdg-mime (~200 ms)
    printf '%s' "$EMOJI" | ${pkgs.wl-clipboard}/bin/wl-copy --type 'text/plain;charset=utf-8'
    [ "''${2:-}" = copy ] && exit 0
    # Attend juste que le menu ait disparu (la fenêtre reprend alors le clavier), 0,5 s max
    for _ in $(${pkgs.coreutils}/bin/seq 50); do
      hyprctl layers | grep -q quickshell-emoji || break
      ${pkgs.coreutils}/bin/sleep 0.01
    done
    ${pkgs.wtype}/bin/wtype -M ctrl -k v -m ctrl
  '';

  # Ancien menu (rofi), gardé en secours si le menu Quickshell ne répond pas
  emoji-picker-rofi = pkgs.writeShellScriptBin "emoji-picker-rofi" ''
    if pgrep -x rofi > /dev/null; then
      pkill -x rofi
      exit 0
    fi
    EMOJI=$(${pkgs.rofi}/bin/rofi -dmenu -i -separator "	" -columns 2 -display-columns 1 -p "󰞅 " -theme ~/.config/rofi/emoji.rasi < ${emojiData}/emoji.tsv | cut -f1)
    if [ -n "$EMOJI" ]; then
      printf '%s' "$EMOJI" | ${pkgs.wl-clipboard}/bin/wl-copy
      while pgrep -x rofi > /dev/null; do
        sleep 0.05
      done
      sleep 0.2
      ${pkgs.wtype}/bin/wtype -M ctrl -k v -m ctrl
    fi
  '';

  # SUPER+; : affiche / masque le menu Quickshell (config « launcher », voir app-launcher.nix)
  emoji-picker = pkgs.writeShellScriptBin "emoji-picker" ''
    ${quickshell}/bin/quickshell ipc -c launcher call emoji toggle >/dev/null 2>&1 \
      || exec ${emoji-picker-rofi}/bin/emoji-picker-rofi
  '';
in
{
  # Lu par le menu Quickshell (Paths.emojiDir)
  xdg.dataFile."emoji-picker".source = emojiData;
  # Nouvelles données → menus rechargés (images gardées en cache sinon)
  systemd.user.services.quickshell-launcher.Unit.X-Restart-Triggers = [ "${emojiData}" ];

  # --- Theme Rofi pour le selecteur de secours ---
  xdg.configFile."rofi/emoji.rasi".text = ''
    configuration {
        show-icons: false;
        font: "Inter 12";
        me-select-entry: "";
        me-accept-entry: "MousePrimary";
        pango-markup: true;
    }
    * {
        background-color: transparent;
        text-color: #ffffff;
    }
    window {
        width: 600px;
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
        placeholder: "Rechercher un emoji...";
        placeholder-color: rgba(255, 255, 255, 0.3);
        vertical-align: 0.5;
    }
    listview {
        columns: 6;
        lines: 10;
        spacing: 8px;
        scrollbar: false;
        padding: 10px;
    }
    element {
        padding: 8px;
        border-radius: 10px;
        vertical-align: 0.5;
        horizontal-align: 0.5;
    }
    element-text {
        background-color: transparent;
        text-color: #ffffff;
        font: "JetBrainsMono Nerd Font 22";
        horizontal-align: 0.5;
    }
    element selected {
        background-color: rgba(255, 255, 255, 0.1);
        border: 2px;
        border-color: #ffffff;
    }
  '';

  home.packages = [ emoji-picker emoji-picker-rofi emoji-paste ];
}
