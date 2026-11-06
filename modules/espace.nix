{ pkgs, ... }:

let
  # Commande `espace` : TUI pour libérer de l'espace et ranger par extension (assets/espace.py)
  #   espace                                   menu interactif (nettoyage, gros fichiers, doublons…)
  #   espace ranger [DOSSIER] [--ext] [--oui]  rangement non interactif (aperçu sans --oui)
  # Les commandes root (générations Nix, GC, journal) passent par sudo dans le terminal.
  espace = pkgs.writeShellScriptBin "espace" ''
    export PATH=${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.procps pkgs.gdu pkgs.xdg-utils pkgs.nix ]}:/run/wrappers/bin:/run/current-system/sw/bin:$PATH
    exec ${pkgs.python3}/bin/python3 ${../assets/espace.py} "$@"
  '';
in
{
  home.packages = [ espace ];

  # Entrée du menu applications (SUPER+R) : TUI lancée dans une fenêtre kitty
  xdg.desktopEntries.espace = {
    name = "Espace";
    genericName = "Libérer de l'espace disque";
    comment = "Nettoyage, gros fichiers, doublons, rangement par extension";
    exec = "${pkgs.kitty}/bin/kitty --class espace --title Espace -e ${espace}/bin/espace";
    icon = "drive-harddisk";
    terminal = false;
    type = "Application";
    categories = [ "System" "Utility" ];
    settings.Keywords = "espace;disque;nettoyer;nettoyage;doublons;ranger;gros fichiers;storage;clean;";
  };
}
