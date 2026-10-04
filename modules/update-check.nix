{ pkgs, ... }:

let
  check-nixos-updates = pkgs.writeShellScriptBin "check-nixos-updates" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    FLAKE_DIR="/etc/nixos"
    LOCK="$FLAKE_DIR/flake.lock"

    [ -f "$LOCK" ] || exit 0

    # Passer par root.inputs : le nœud "nixpkgs" peut être celui d'un autre input (ex: claude-desktop)
    CURRENT_REV=$(${pkgs.jq}/bin/jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' "$LOCK")
    LATEST_REV=$(${pkgs.coreutils}/bin/timeout 10 ${pkgs.git}/bin/git ls-remote https://github.com/NixOS/nixpkgs nixos-unstable 2>/dev/null | cut -f1)

    [ -z "$LATEST_REV" ] && exit 0

    # Hyprland : version installée (nixpkgs verrouillé), dans nixos-unstable, et dernière release upstream
    HYPR_CUR="${pkgs.hyprland.version}"
    HYPR_NIX=$(${pkgs.curl}/bin/curl -sf --max-time 10 \
      https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/pkgs/by-name/hy/hyprland/package.nix \
      | ${pkgs.gnugrep}/bin/grep -m1 -oP 'version = "\K[^"]+')
    HYPR_UP=$(${pkgs.coreutils}/bin/timeout 10 ${pkgs.git}/bin/git ls-remote --tags --refs https://github.com/hyprwm/Hyprland 'v*' 2>/dev/null \
      | ${pkgs.gnused}/bin/sed 's|.*refs/tags/v||' | ${pkgs.gnugrep}/bin/grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
      | ${pkgs.coreutils}/bin/sort -V | ${pkgs.coreutils}/bin/tail -1)
    : "''${HYPR_NIX:=$HYPR_CUR}"

    # newer A B : vrai si version A > version B
    newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | ${pkgs.coreutils}/bin/sort -V | ${pkgs.coreutils}/bin/tail -1)" = "$1" ]; }

    # Release upstream pas encore dans nixpkgs : signalée une seule fois par version
    STATE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/nixos-update-check"
    UPSTREAM_NOTE=""
    if [ -n "$HYPR_UP" ] && newer "$HYPR_UP" "$HYPR_NIX" && newer "$HYPR_UP" "$HYPR_CUR" \
       && [ "$(cat "$STATE_DIR/hyprland-upstream" 2>/dev/null)" != "$HYPR_UP" ]; then
      UPSTREAM_NOTE="Hyprland $HYPR_UP sorti (pas encore dans nixpkgs)."
      mkdir -p "$STATE_DIR"
      echo "$HYPR_UP" > "$STATE_DIR/hyprland-upstream"
    fi

    if [ "$CURRENT_REV" = "$LATEST_REV" ]; then
      [ -n "$UPSTREAM_NOTE" ] && $NOTIFY "󰖲 Nouvelle version de Hyprland" "$UPSTREAM_NOTE" -i software-update-available -u low
      exit 0
    fi

    BODY="nixpkgs a de nouveaux commits."
    if newer "$HYPR_NIX" "$HYPR_CUR"; then
      BODY="$BODY
    Hyprland $HYPR_CUR → $HYPR_NIX"
    fi
    [ -n "$UPSTREAM_NOTE" ] && BODY="$BODY
    $UPSTREAM_NOTE"

    if [ "$CURRENT_REV" != "$LATEST_REV" ]; then
      ACTION=$($NOTIFY "󰚰 Mises à jour NixOS disponibles" \
        "$BODY" \
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
