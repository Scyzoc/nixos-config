{ config, pkgs, lib, ... }:

# Multi-appui sur les AirPods : ils n'envoient qu'un « Play » par appui (jamais Next/Prev),
# donc on compte les appuis rapprochés : 1 = lecture/pause, 2 = suivant, 3 = précédent.
let
  media-tap = pkgs.writeShellScriptBin "media-tap" ''
    PLAYERCTL=${pkgs.playerctl}/bin/playerctl
    DIR="''${XDG_RUNTIME_DIR:-/tmp}"
    COUNT="$DIR/media-tap.count"
    LOCK="$DIR/media-tap.lock"
    WINDOW=0.45

    # Enregistre l'appui (sous verrou) et note son numéro
    n=$(
      ${pkgs.util-linux}/bin/flock "$LOCK" bash -c '
        c=$(cat "$0" 2>/dev/null || echo 0)
        echo $((c + 1)) | tee "$0"
      ' "$COUNT"
    )
    sleep "$WINDOW"

    # Seul le dernier appui de la salve déclenche l'action
    ${pkgs.util-linux}/bin/flock "$LOCK" bash -c '
      total=$(cat "$0" 2>/dev/null || echo 0)
      [ "$total" = "$1" ] || exit 1
      echo 0 > "$0"
    ' "$COUNT" "$n" || exit 0

    case "$n" in
      1) $PLAYERCTL play-pause ;;
      2) $PLAYERCTL next ;;
      *) $PLAYERCTL previous ;;
    esac
  '';
in
{
  home.packages = [ media-tap ];
}
