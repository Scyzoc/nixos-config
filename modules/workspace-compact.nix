{ pkgs, ... }:

# Compacte les workspaces du moniteur courant : déplace les fenêtres vers les
# premiers workspaces de ce moniteur, sans trou (ex : 13 seul → 11), en gardant
# la disposition des fenêtres (assets/ws-move.py). Lié à Super+Ctrl+Tab.
# ws-move <src> <dst> : déplace toutes les fenêtres d'un workspace vers un autre en
# gardant la disposition (assets/ws-move.py) ; glisser-déposer dans la barre Quickshell.
{
  home.packages = [
    (pkgs.writeShellScriptBin "ws-compact" ''
      HYPRCTL=${pkgs.hyprland}/bin/hyprctl exec ${pkgs.python3}/bin/python3 ${../assets/ws-move.py} --compact "$@"
    '')

    (pkgs.writeShellScriptBin "ws-move" ''
      HYPRCTL=${pkgs.hyprland}/bin/hyprctl exec ${pkgs.python3}/bin/python3 ${../assets/ws-move.py} "$@"
    '')
  ];
}
