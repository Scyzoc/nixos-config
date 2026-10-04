{ pkgs, ... }:

let
  # Extraction en double-clic depuis Thunar : unar crée automatiquement
  # un dossier si l'archive contient plusieurs entrées à la racine.
  extractHere = pkgs.writeShellScriptBin "extract-here" ''
    set -u
    NOTIFY="${pkgs.libnotify}/bin/notify-send"

    for archive in "$@"; do
      dir="$(${pkgs.coreutils}/bin/dirname "$archive")"
      name="$(${pkgs.coreutils}/bin/basename "$archive")"

      $NOTIFY -a "Extraction" -i package-x-generic "Extraction en cours" "$name"

      if ${pkgs.unar}/bin/unar -quiet -force-directory -output-directory "$dir" "$archive"; then
        $NOTIFY -a "Extraction" -i package-x-generic "Extraction terminée" "$name"
      else
        $NOTIFY -a "Extraction" -i dialog-error -u critical "Échec de l'extraction" "$name"
      fi
    done
  '';

  archiveMimes = [
    "application/zip"
    "application/x-zip-compressed"
    "application/vnd.rar"
    "application/x-rar-compressed"
    "application/x-7z-compressed"
    "application/x-tar"
    "application/gzip"
    "application/x-bzip2"
    "application/x-xz"
    "application/x-compressed-tar"
    "application/x-bzip-compressed-tar"
    "application/x-xz-compressed-tar"
  ];
in
{
  home.packages = [ extractHere pkgs.unar pkgs.p7zip ];

  xdg.desktopEntries.extract-here = {
    name = "Extraire ici";
    genericName = "Extraction d'archive";
    exec = "extract-here %F";
    icon = "package-x-generic";
    terminal = false;
    type = "Application";
    mimeType = archiveMimes;
    settings.NoDisplay = "true";
  };

  xdg.mimeApps.defaultApplications =
    builtins.listToAttrs
      (map (m: { name = m; value = "extract-here.desktop"; }) archiveMimes);
}
