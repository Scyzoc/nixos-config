{ config, pkgs, ... }:

let
  # Client MCP d'Atlas (assets/atlas-task.py) utilisé par le popup « Nouvelle tâche »
  #   atlas-task meta | cached         thèmes + projets (JSON)
  #   atlas-task create '<json>'       crée la tâche, notification en retour
  # Jeton : ~/.config/atlas/token, sinon celui du serveur MCP « atlas » de Claude Code
  atlas-task = pkgs.writeShellScriptBin "atlas-task" ''
    export ATLAS_NOTIFY=${pkgs.libnotify}/bin/notify-send
    exec ${pkgs.python3}/bin/python3 ${../assets/atlas-task.py} "$@"
  '';
in
{
  home.packages = [ atlas-task ];

  # SUPER+SHIFT+T : popup de création de tâche (menu Quickshell, AtlasTask.qml)
  # (SUPER+T ouvre l'appli Atlas complète)
  wayland.windowManager.hyprland.extraConfig = ''
    hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("quickshell ipc -c launcher call atlas toggle"))
    hl.layer_rule({ name = "layer-quickshell-atlas", match = { namespace = "quickshell-atlas" }, blur = true, ignore_alpha = 0.4 })
  '';
}
