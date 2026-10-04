{ pkgs, ... }:

let
  check-nixos-updates = pkgs.writeShellScriptBin "check-nixos-updates" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    FLAKE_DIR="/etc/nixos"
    LOCK="$FLAKE_DIR/flake.lock"

    [ -f "$LOCK" ] || exit 0

    CURRENT_REV=$(${pkgs.jq}/bin/jq -r '.nodes.nixpkgs.locked.rev' "$LOCK")
    LATEST_REV=$(${pkgs.coreutils}/bin/timeout 10 ${pkgs.git}/bin/git ls-remote https://github.com/NixOS/nixpkgs nixos-unstable 2>/dev/null | cut -f1)

    [ -z "$LATEST_REV" ] && exit 0

    if [ "$CURRENT_REV" != "$LATEST_REV" ]; then
      ACTION=$($NOTIFY "󰚰 Mises à jour NixOS disponibles" \
        "nixpkgs a de nouveaux commits." \
        -i software-update-available -u normal \
        -A "update=Lancer les MàJ")

      # Synchrone : le service est Type=simple, pas de timeout de démarrage
      # (un process détaché serait tué avec le cgroup du service).
      if [ "$ACTION" = "update" ]; then
        LOG=$(mktemp /tmp/nixos-update-XXXXXX.log)
        if ${pkgs.nix}/bin/nix flake update nixpkgs --flake "$FLAKE_DIR" > "$LOG" 2>&1; then
          $NOTIFY "󰄬 Mises à jour NixOS" "flake.lock mis à jour, rebuild pour appliquer." -i software-update-available -u normal
        else
          $NOTIFY "󰀪 Échec mise à jour NixOS" "Voir $LOG" -i dialog-error -u critical
        fi
      fi
    fi
  '';
in
{
  home.packages = [ check-nixos-updates ];

  systemd.user.services.nixos-update-check = {
    Unit = {
      Description = "Vérifie les mises à jour nixpkgs disponibles";
      After = [ "hyprland-session.target" "network-online.target" ];
      PartOf = [ "hyprland-session.target" ];
      # Ne pas relancer la vérif (et la notif) à chaque home-manager switch
      X-SwitchMethod = "keep-old";
    };
    Service = {
      # simple : notify-send -A attend le clic, pas de timeout de démarrage
      Type = "simple";
      # Reste "active" après exécution → sd-switch ne le relance pas au rebuild
      RemainAfterExit = true;
      ExecStart = "${check-nixos-updates}/bin/check-nixos-updates";
    };
    Install = {
      WantedBy = [ "hyprland-session.target" ];
    };
  };
}
