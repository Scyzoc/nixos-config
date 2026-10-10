# atlas-workspace.nix — Espaces de travail par projet Atlas
# SUPER+H : liste des projets Atlas (menu Quickshell, quickshell-launcher/ProjectLauncher.qml).
# Un clic ouvre les fenêtres du projet (terminaux, Claude Code, navigateur, page Atlas…)
# sur le workspace vide le plus proche ; la roue dentée édite la recette.
# Backend assets/atlas-workspace.py, recettes ~/.config/atlas/workspaces.json.
# Claude Code : hook SessionStart (ajouté à ~/.claude/settings.json à l'activation) qui,
# dans le dossier d'un projet, donne son id Atlas et la consigne de créer / terminer les
# tâches au fil du travail (MCP « atlas », déjà global dans ~/.claude.json).
{ config, pkgs, ... }:

let
  atlas-workspace = pkgs.writeShellScriptBin "atlas-workspace" ''
    export HYPRCTL=${pkgs.hyprland}/bin/hyprctl
    export KITTY=${pkgs.kitty}/bin/kitty
    export BRAVE=${pkgs.brave}/bin/brave
    export ATLAS_TASK=${config.home.profileDirectory}/bin/atlas-task
    exec ${pkgs.python3}/bin/python3 ${../assets/atlas-workspace.py} "$@"
  '';
  hookCmd = "${config.home.profileDirectory}/bin/atlas-workspace context";

  # Ajoute le hook s'il manque (settings.json reste modifiable par Claude Code)
  add-hook = pkgs.writeText "atlas-hook.py" ''
    import json, os, sys
    p = os.path.expanduser("~/.claude/settings.json")
    try:
        s = json.load(open(p))
    except (OSError, ValueError):
        s = {}
    starts = s.setdefault("hooks", {}).setdefault("SessionStart", [])
    if any(h.get("command") == sys.argv[1] for g in starts for h in g.get("hooks", [])):
        sys.exit(0)
    starts.append({"hooks": [{"type": "command", "command": sys.argv[1], "timeout": 5}]})
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".tmp", "w") as f:
        json.dump(s, f, indent=2, ensure_ascii=False)
    os.chmod(p + ".tmp", 0o600)
    os.replace(p + ".tmp", p)
  '';
in
{
  home.packages = [ atlas-workspace ];

  home.activation.atlasClaudeHook = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 ${add-hook} ${pkgs.lib.escapeShellArg hookCmd}
  '';

  wayland.windowManager.hyprland.settings = {
    bind = [ "$mainMod, H, exec, quickshell ipc -c launcher call projects toggle" ];
    layerrule = [
      "blur on, match:namespace quickshell-projects"
      "ignore_alpha 0.4, match:namespace quickshell-projects"
    ];
  };
}
