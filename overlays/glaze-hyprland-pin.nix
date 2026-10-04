final: prev: {
  # glaze 8.0.0 casse le build Hyprland 0.56.1 (CMakeLists exige `glaze 7...<8`,
  # find_package échoue en version et retombe sur FetchContent réseau, bloqué
  # par le sandbox nix). On repin sur la dernière 7.x compatible.
  glaze = prev.glaze.overrideAttrs (old: {
    version = "7.9.1";
    src = prev.fetchFromGitHub {
      owner = "stephenberry";
      repo = "glaze";
      tag = "v7.9.1";
      hash = "sha256-NRRq5MGF2f5PW0teYnq58ELzson+U6KHVPaY6r30KLA=";
    };
  });
}
