final: prev:
let
  claudeCodeNotifyIcon = final.runCommand "claude-code-notify-icon"
    { nativeBuildInputs = [ final.librsvg ]; }
    ''
      mkdir -p $out
      rsvg-convert -w 256 -h 256 ${../assets/claude-code-icon.svg} -o $out/claude-code-notify.png
    '';
in
{
  # Icône de secours des notifications desktop de kitty (OSC 99) : kitty se
  # rabat sur son propre logo (chat) quand l'appli qui notifie ne fournit ni
  # icône ni nom (cas de Claude Code). On remplace uniquement ce fallback des
  # notifications — l'icône de fenêtre/barre des tâches de kitty n'est pas
  # touchée, `logo_png_file` reste inchangé partout ailleurs.
  kitty = prev.kitty.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace kitty/notifications.py \
        --replace-fail \
          "app_icon = get_custom_window_icon()[1] or logo_png_file" \
          "app_icon = get_custom_window_icon()[1] or '${claudeCodeNotifyIcon}/claude-code-notify.png'"
    '';
  });
}
