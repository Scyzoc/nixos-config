{ pkgs, ... }:

# Cycle entre les workspaces non vides du moniteur courant, avec bouclage
# (ex : 1 → 2 → 3 → 1). Utilisé par Super+Tab / Super+Shift+Tab.
{
  home.packages = [
    (pkgs.writeShellScriptBin "ws-cycle" ''
      set -euo pipefail

      dir="''${1:-next}"

      mon=$(${pkgs.hyprland}/bin/hyprctl -j monitors | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
      cur=$(${pkgs.hyprland}/bin/hyprctl -j monitors | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .activeWorkspace.id')

      # workspaces non vides du moniteur + workspace courant, triés
      mapfile -t ws < <(
        ${pkgs.hyprland}/bin/hyprctl -j workspaces \
          | ${pkgs.jq}/bin/jq -r --arg m "$mon" --argjson c "$cur" \
              '.[] | select(.monitor == $m) | select(.windows > 0 or .id == $c) | .id' \
          | sort -n | uniq
      )

      n=''${#ws[@]}
      [ "$n" -le 1 ] && exit 0

      idx=0
      for i in "''${!ws[@]}"; do
        [ "''${ws[$i]}" = "$cur" ] && idx=$i
      done

      if [ "$dir" = "prev" ]; then
        target=''${ws[$(( (idx - 1 + n) % n ))]}
      else
        target=''${ws[$(( (idx + 1) % n ))]}
      fi

      ${pkgs.hyprland}/bin/hyprctl dispatch workspace "$target"
    '')
  ];
}
