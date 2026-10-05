{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;

  # Données du menu : ordre et catégories Unicode, noms / mots-clés français (CLDR),
  # limités aux emojis que dessine la police par défaut, + ponctuation, flèches et
  # caractères spéciaux (polices texte), + planches d'images aux tailles affichées par
  # le menu (28 px au repos, 33 px au survol) (assets/emoji-data.py)
  emojiData = pkgs.runCommand "emoji-data" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.uharfbuzz p.fonttools p.pillow ])) ];
  } ''
    mkdir $out
    python3 ${../assets/emoji-data.py} \
      ${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt \
      ${pkgs.cldr-annotations}/share/unicode/cldr/common \
      ${../fonts/AppleColorEmoji.ttf} \
      ${pkgs.inter}/share/fonts/truetype/InterVariable.ttf:${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf:${pkgs.noto-fonts}/share/fonts/noto/NotoSansMath-Regular.otf:${pkgs.noto-fonts}/share/fonts/noto/NotoSansSymbols2-Regular.otf \
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


  # SUPER+; : affiche / masque le menu Quickshell (config « launcher », voir app-launcher.nix)
  emoji-picker = pkgs.writeShellScriptBin "emoji-picker" ''
    ${quickshell}/bin/quickshell ipc -c launcher call emoji toggle >/dev/null 2>&1
  '';
in
{
  # Lu par le menu Quickshell (Paths.emojiDir)
  xdg.dataFile."emoji-picker".source = emojiData;
  # Nouvelles données → menus rechargés (images gardées en cache sinon)
  systemd.user.services.quickshell-launcher.Unit.X-Restart-Triggers = [ "${emojiData}" ];


  home.packages = [ emoji-picker emoji-paste ];
}
