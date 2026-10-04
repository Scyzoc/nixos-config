{ config, pkgs, ... }:

let
  # Assistant du bureau (assets/assistant.py) : demande en français → Claude (claude -p) →
  # actions sur liste blanche (Spotify, lecture, volume, sites, applis, minuteurs, chrono).
  # Réponse en notification.
  #   assistant "mets Ciao de Werenoi sur Spotify"
  # Historique : ~/.local/state/assistant/history.jsonl
  assistant = pkgs.writeShellScriptBin "assistant" ''
    export ASSISTANT_PLAYERCTL=${pkgs.playerctl}/bin/playerctl
    export ASSISTANT_NOTIFY=${pkgs.libnotify}/bin/notify-send
    export ASSISTANT_WPCTL=${pkgs.wireplumber}/bin/wpctl
    export ASSISTANT_GDBUS=${pkgs.glib.bin}/bin/gdbus
    export ASSISTANT_HYPRCTL=hyprctl
    export ASSISTANT_XDG_OPEN=${pkgs.xdg-utils}/bin/xdg-open
    export ASSISTANT_GTK_LAUNCH=${pkgs.gtk3}/bin/gtk-launch
    export ASSISTANT_QUICKSHELL=${config.programs.quickshell.package}/bin/quickshell
    exec ${pkgs.python3}/bin/python3 ${../assets/assistant.py} "$@"
  '';
in
{
  home.packages = [ assistant ];

  # SUPER+K : demande écrite (menu Quickshell, AssistantPrompt.qml)
  # SUPER+SHIFT+K : demande vocale (voice-to-text --assistant : appuyer pour parler, rappuyer pour envoyer)
  wayland.windowManager.hyprland.settings.bind = [
    "$mainMod, K, exec, quickshell ipc -c launcher call assistant toggle"
    "$mainMod SHIFT, K, exec, voice-to-text --assistant"
  ];
}
