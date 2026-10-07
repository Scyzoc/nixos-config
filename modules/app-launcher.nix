{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;
  launcherState = "${config.xdg.stateHome}/quickshell-launcher";

  # Chemins absolus utilisés par les menus Quickshell (PATH non garanti sous systemd).
  # userBin : scripts du profil (wallpaper-index / wallpaper-apply, wallpaper-picker.nix)
  launcher-paths = pkgs.writeText "Paths.qml" ''
    pragma Singleton
    import Quickshell

    Singleton {
        readonly property string kitty: "${pkgs.kitty}/bin/kitty"
        readonly property string brave: "${pkgs.brave}/bin/brave"
        readonly property string nwgDisplays: "${pkgs.nwg-displays}/bin/nwg-displays"
        readonly property string userBin: "${config.home.profileDirectory}/bin"
        readonly property string stateDir: "${launcherState}"
        readonly property string usageFile: "${launcherState}/usage.json"
        readonly property string emojiDir: "${config.xdg.dataHome}/emoji-picker"
        readonly property string emojiState: "${launcherState}/emoji.json"
    }
  '';

  # Config QML des menus (modules/quickshell-launcher/ : applications + fonds d'écran)
  # + thème partagé avec la barre
  launcherConfig = pkgs.runCommand "quickshell-launcher" { } ''
    mkdir $out
    cp ${./quickshell}/Theme.qml ${./quickshell}/ClickFx.qml $out/
    cp ${./quickshell-launcher}/*.qml $out/
    cp ${launcher-paths} $out/Paths.qml
  '';

  # SUPER+R : affiche / masque le menu Quickshell (déjà chargé par son service)
  app-launcher = pkgs.writeShellScriptBin "app-launcher" ''
    ${quickshell}/bin/quickshell ipc -c launcher call launcher toggle >/dev/null 2>&1
  '';

in
{
  home.packages = [ app-launcher ];

  # Menus plein écran (applications, fonds d'écran) : config Quickshell à part, service
  # à part (un bug d'un menu ne fait pas tomber la barre)
  programs.quickshell.configs.launcher = launcherConfig;

  systemd.user.services.quickshell-launcher = {
    Unit = {
      Description = "Menus d'applications et de fonds d'écran (Quickshell)";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
      X-Restart-Triggers = [ "${launcherConfig}" ];
    };
    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${launcherState}";
      ExecStart = "${quickshell}/bin/quickshell --config launcher";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };
}
