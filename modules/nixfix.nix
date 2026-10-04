{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellScriptBin "nixfix" ''
      set -uo pipefail

      R='\e[0m'; BOLD='\e[1m'; DIM='\e[2m'
      RED='\e[38;5;203m'; YELLOW='\e[38;5;221m'; GREEN='\e[38;5;114m'; BLUE='\e[38;5;111m'; GRAY='\e[38;5;245m'

      FLAKE="/etc/nixos"
      HOST="pc1"
      LOG=$(mktemp)
      trap 'rm -f "$LOG"' EXIT

      echo -e "$BLUE''${BOLD}==> Build test (sans switch) : $FLAKE#$HOST$R"
      if sudo nixos-rebuild build --flake "$FLAKE#$HOST" 2>&1 | tee "$LOG"; then
        echo -e "\n$GREEN''${BOLD}OK — build reussi, aucune erreur.$R"
        exit 0
      fi

      echo -e "\n$RED''${BOLD}==> Build en echec — diagnostic$R\n"

      DRV=$(grep -oP "For full logs, run:\s*\n?\s*nix log \K[^\s]+" "$LOG" | tail -1)
      if [ -z "$DRV" ]; then
        DRV=$(grep -oP "builder for '\K[^']+(?=' failed)" "$LOG" | tail -1)
      fi

      if [ -z "$DRV" ]; then
        echo -e "$YELLOW Impossible d'isoler le paquet fautif automatiquement.$R"
        echo -e "$GRAY Relis la sortie ci-dessus, cherche le premier 'error:'.$R"
        exit 1
      fi

      PKGNAME=$(basename "$DRV" .drv)
      echo -e "$GRAY Paquet fautif :$R $BOLD$PKGNAME$R"
      echo -e "$GRAY Derivation    :$R $DRV\n"

      PKGLOG=$(nix log "$DRV" 2>&1)

      echo -e "$BLUE''${BOLD}==> Signatures d'erreur connues$R"
      MATCHED=0

      if echo "$PKGLOG" | grep -qE "could not find git for clone|Network is unreachable|Could not resolve host|SSL_ERROR|Connection refused"; then
        MATCHED=1
        echo -e "$RED  [reseau en sandbox]$R Le build tente d'aller sur internet (FetchContent/git clone) — interdit en sandbox nix."
        echo -e "$GRAY    Cause typique : mismatch de version entre une dependance et ce qu'exige le paquet"
        echo -e "$GRAY    (ex: paquet veut 'lib < 8' mais nixpkgs fournit 'lib 8.x').$R"
        echo -e "$GRAY    Fix : overlay qui pin la dependance a une version compatible (voir overlays/*.nix).$R"
      fi

      if echo "$PKGLOG" | grep -qE "error: attribute '[^']+' missing"; then
        MATCHED=1
        ATTR=$(echo "$PKGLOG" | grep -oP "error: attribute '\K[^']+" | head -1)
        echo -e "$RED  [attribut manquant]$R '$ATTR' n'existe plus (ou a ete renomme) dans cette revision de nixpkgs."
        echo -e "$GRAY    Fix : cherche le nouveau nom (changelog nixpkgs / release notes) et adapte la config.$R"
      fi

      if echo "$PKGLOG" | grep -qE "undefined reference|error: .*was not declared|fatal error: .*\.h(pp)?: No such file"; then
        MATCHED=1
        echo -e "$RED  [erreur de compilation]$R Incompatibilite entre le code source et une lib liee."
        echo -e "$GRAY    Fix : pin la lib fautive a une version plus ancienne compatible, ou attends un correctif upstream.$R"
      fi

      if echo "$PKGLOG" | grep -qE "hash mismatch|NAR hash mismatch"; then
        MATCHED=1
        echo -e "$RED  [hash invalide]$R Le hash fige dans une derivation (fetchurl/fetchFromGitHub) ne correspond plus a la source."
        echo -e "$GRAY    Fix : recalcule le hash reel et mets-le a jour.$R"
      fi

      if [ "$MATCHED" -eq 0 ]; then
        echo -e "$YELLOW  Aucune signature connue detectee.$R"
      fi

      echo -e "\n$BLUE''${BOLD}==> Dernieres lignes du log complet$R"
      echo "$PKGLOG" | tail -30

      echo -e "\n$GRAY Log complet :$R nix log $DRV"
      exit 1
    '')
  ];
}
