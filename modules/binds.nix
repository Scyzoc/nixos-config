# binds.nix — Gestionnaire des raccourcis Hyprland (SUPER+F1)
# Liste tous les binds (ceux de la config Nix + les tiens), permet d'en ajouter,
# modifier, désactiver ou remplacer sans toucher aux .nix. Menu Quickshell
# (quickshell-launcher/BindsMenu.qml), backend assets/binds.py :
#   binds list | add | update | delete | toggle | reset | apply | capture
# Les changements vivent dans ~/.local/state/binds/user.json et sont appliqués à
# chaud ; ~/.config/hypr/binds-user.lua les rejoue au démarrage de Hyprland.
{ config, lib, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;

  # Affiche / masque le menu (config Quickshell « launcher », voir app-launcher.nix)
  binds-menu = pkgs.writeShellScriptBin "binds-menu" ''
    ${quickshell}/bin/quickshell ipc -c launcher call binds toggle >/dev/null 2>&1
  '';

  binds = pkgs.writeShellScriptBin "binds" ''
    export HYPRCTL=${pkgs.hyprland}/bin/hyprctl BINDS_LUA=${pkgs.lua5_4}/bin/lua
    exec ${pkgs.python3}/bin/python3 ${../assets/binds.py} "$@"
  '';
in
{
  home.packages = [ binds binds-menu ];

  # Entrée du menu applications (SUPER+R)
  xdg.desktopEntries.binds = {
    name = "Raccourcis";
    genericName = "Gestionnaire de binds";
    comment = "Liste, ajoute, modifie et désactive les raccourcis clavier Hyprland";
    exec = "${binds-menu}/bin/binds-menu";
    icon = "input-keyboard";
    terminal = false;
    type = "Application";
    categories = [ "Settings" "Utility" ];
    settings.Keywords = "raccourcis;binds;clavier;touches;keybinds;hyprland;shortcuts;keyboard;";
  };

  # mkAfter : la couche utilisateur doit passer APRÈS tous les binds par défaut
  wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
    hl.bind("SUPER + F1", hl.dsp.exec_cmd("quickshell ipc -c launcher call binds toggle"))
    hl.layer_rule({ name = "layer-quickshell-binds", match = { namespace = "quickshell-binds" }, blur = true, ignore_alpha = 0.4 })
    -- Submap vide pendant la capture d'une combinaison (binds.py capture) : sans elle,
    -- appuyer sur SUPER+Q fermerait la fenêtre au lieu d'être enregistré
    hl.define_submap("bindcap", function()
      hl.bind("SUPER + CTRL + ALT + F12", hl.dsp.submap("reset"))
    end)
    pcall(dofile, (os.getenv("HOME") or "") .. "/.config/hypr/binds-user.lua")
  '';
}
