{ pkgs, ... }:

# Workspace spécial (scratchpad) avec effet « zoom depuis le centre ».
# Hyprland n'a pas de style popin pour les workspaces (slide/fade seulement) :
# le workspace fait un fondu, et ce script anime les fenêtres flottantes —
# rétrécies au centre de l'écran quand il est caché, restaurées à leur taille
# (animation windows) quand il réapparaît. Les fenêtres tuilées ne font que le fondu.
# Lié à Super+X. Usage : special-zoom [nom] (défaut : magic)
{
  home.packages = [
    (pkgs.writeShellScriptBin "special-zoom" ''
      set -uo pipefail

      hyprctl="${pkgs.hyprland}/bin/hyprctl"
      jq="${pkgs.jq}/bin/jq"

      WS="''${1:-magic}"
      NAME="special:$WS"
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/special-zoom-$WS.json"
      F=0.1   # taille de départ (fraction de la taille réelle)

      # Moniteur courant : origine + taille logique (rotation 90/270 → w/h inversés)
      read -r mx my lw lh visible < <(
        "$hyprctl" -j monitors | "$jq" -r --arg n "$NAME" '
          .[] | select(.focused)
          | (if (.transform % 2) == 1 then [.height, .width] else [.width, .height] end) as $s
          | [.x, .y, (($s[0] / .scale) | floor), (($s[1] / .scale) | floor), (.specialWorkspace.name == $n)]
          | @tsv'
      )
      cx=$((mx + lw / 2)); cy=$((my + lh / 2))

      wins=$("$hyprctl" -j clients | "$jq" -c --arg n "$NAME" '
        [.[] | select(.workspace.name == $n and .floating)
             | {a: .address, x: .at[0], y: .at[1], w: .size[0], h: .size[1]}]')

      # Commandes pour rétrécir une liste de fenêtres vers le centre de l'écran
      shrink() {
        "$jq" -r --argjson cx "$cx" --argjson cy "$cy" --argjson f "$F" '
          .[] | ([(.w * $f | round), 1] | max) as $sw | ([(.h * $f | round), 1] | max) as $sh
          | "dispatch resizewindowpixel exact \($sw) \($sh),address:\(.a) ; "
          + "dispatch movewindowpixel exact \($cx - ($sw / 2 | floor)) \($cy - ($sh / 2 | floor)),address:\(.a) ; "' \
          | tr -d '\n'
      }

      if [ "$visible" = true ]; then
        # Masquer : mémorise la géométrie (relative au moniteur), rétrécit vers le
        # centre de façon visible, puis fondu une fois la fenêtre presque réduite
        printf '%s' "$wins" | "$jq" -c --argjson mx "$mx" --argjson my "$my" '
          map({key: .a, value: {x: (.x - $mx), y: (.y - $my), w, h}}) | from_entries' > "$STATE"
        if [ "$wins" != "[]" ]; then
          "$hyprctl" --batch "$(printf '%s' "$wins" | shrink)" >/dev/null
          sleep 0.18
        fi
        "$hyprctl" dispatch togglespecialworkspace "$WS" >/dev/null
        exit 0
      fi

      saved=$(cat "$STATE" 2>/dev/null || true)
      [ -n "$saved" ] || saved='{}'

      # Fenêtres arrivées pendant que le workspace était caché : pas encore
      # rétrécies → on le fait d'abord (invisible) et on attend la fin de l'animation
      prep=$(printf '%s' "$wins" | "$jq" -c --argjson s "$saved" '[.[] | select($s[.a] == null)]')
      if [ "$prep" != "[]" ]; then
        "$hyprctl" --batch "$(printf '%s' "$prep" | shrink)" >/dev/null
        sleep 0.25
      fi

      # Afficher : fondu + restauration de la taille (bornée au moniteur courant)
      restore=$(printf '%s' "$wins" | "$jq" -r --argjson s "$saved" \
        --argjson mx "$mx" --argjson my "$my" --argjson lw "$lw" --argjson lh "$lh" '
        .[] | ($s[.a] // {x: (.x - $mx), y: (.y - $my), w, h}) as $g
        | ([$g.w, $lw] | min) as $w | ([$g.h, $lh] | min) as $h
        | ([[$g.x, $lw - $w] | min, 0] | max) as $x | ([[$g.y, $lh - $h] | min, 0] | max) as $y
        | "dispatch resizewindowpixel exact \($w) \($h),address:\(.a) ; "
        + "dispatch movewindowpixel exact \($x + $mx) \($y + $my),address:\(.a) ; "' | tr -d '\n')

      "$hyprctl" --batch "dispatch togglespecialworkspace $WS ; $restore" >/dev/null
      rm -f "$STATE"
    '')
  ];
}
