final: prev: {
  # brave retiré de nixpkgs (failles non corrigées) → wrapper vers la version Flatpak
  # (flatpak install flathub com.brave.Browser). Garde le nom pkgs.brave pour les modules.
  brave = prev.writeShellScriptBin "brave" ''
    exec ${prev.flatpak}/bin/flatpak run com.brave.Browser "$@"
  '';
}
