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
  # Client de l'agent IA d'Atlas (assets/atlas-agent.py), utilisé par la fenêtre « Agent Atlas »
  atlas-agent = pkgs.writeShellScriptBin "atlas-agent" ''
    exec ${pkgs.python3}/bin/python3 ${../assets/atlas-agent.py} "$@"
  '';
in
{
  home.packages = [ atlas-task atlas-agent ];

  # SUPER+SHIFT+T : fenêtre de discussion avec l'agent IA d'Atlas (menu Quickshell, AtlasAgent.qml)
  # (SUPER+T ouvre l'appli Atlas complète ; l'ancien popup « Nouvelle tâche » AtlasTask.qml
  #  reste joignable par `quickshell ipc -c launcher call atlas toggle`)
  wayland.windowManager.hyprland.extraConfig = ''
    hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("quickshell ipc -c launcher call atlasagent toggle"))
    hl.layer_rule({ name = "layer-quickshell-atlas-agent", match = { namespace = "quickshell-atlas-agent" }, blur = true, ignore_alpha = 0.4 })
    hl.layer_rule({ name = "layer-quickshell-atlas", match = { namespace = "quickshell-atlas" }, blur = true, ignore_alpha = 0.4 })
  '';
}
