{ pkgs, ... }:

let
  driver-update = pkgs.writeShellScriptBin "driver-update" ''
    set -uo pipefail

    FLAKE_DIR="/etc/nixos"
    HOST="pc1"
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    JQ="${pkgs.jq}/bin/jq"
    GIT="${pkgs.git}/bin/git"

    C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
    C_BLUE=$'\e[34m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'

    titre()  { printf '\n%s%s󰢻 %s%s\n' "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"; }
    ok()     { printf '%s󰄬%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
    warn()   { printf '%s%s%s %s\n' "$C_YELLOW" "󰀦" "$C_RESET" "$1"; }
    err()    { printf '%s󰀪%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
    info()   { printf '%s󰋼%s %s\n' "$C_DIM" "$C_RESET" "$1"; }

    usage() {
      cat <<'USAGE'
󰢻 driver-update — mise à jour des pilotes (NixOS)

Sur NixOS les pilotes ne s'installent pas séparément : kernel, firmware,
microcode et mesa/amdgpu viennent tous de nixpkgs. Mettre à jour les
pilotes = mettre à jour le flake puis rebuild.

Usage : driver-update [COMMANDE]

  MATÉRIEL (ce que la machine contient)
  hardware    CPU, GPU, réseau, audio, disques, batterie + pilote kernel lié

  LOGICIEL (ce qui pilote ce matériel)
  software    Kernel, mesa, firmware, microcode, nixpkgs, générations

  status      Les deux sections d'affilée (défaut)
  check       Vérifie si nixpkgs a du neuf (sans rien modifier)
  update      Met à jour nixpkgs + rebuild switch  ← la vraie mise à jour
  dry         Comme update mais build seulement (aucun switch)
  rollback    Revient à la génération précédente
  help        Cette aide
USAGE
    }

    cmd_hardware() {
      printf '\n%s%s╭─ 󰍛 MATÉRIEL %s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"

      titre "Processeur"
      ${pkgs.gnugrep}/bin/grep -m1 'model name' /proc/cpuinfo | ${pkgs.gnused}/bin/sed 's/.*: /  /'
      printf '  Cœurs         : %s\n' "$(${pkgs.coreutils}/bin/nproc)"

      titre "Carte graphique"
      ${pkgs.pciutils}/bin/lspci -nn | ${pkgs.gnugrep}/bin/grep -Ei 'vga|3d|display' | ${pkgs.gnused}/bin/sed 's/^/  /' || true
      for d in /sys/class/drm/card*/device/driver; do
        [ -e "$d" ] || continue
        CARD=$(printf '%s' "$d" | ${pkgs.gnused}/bin/sed 's|/sys/class/drm/||;s|/device/driver||')
        printf '  %-13s : pilote %s\n' "$CARD" "$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "$d")")"
      done

      titre "Réseau"
      ${pkgs.pciutils}/bin/lspci -nnk | ${pkgs.gnugrep}/bin/grep -A3 -Ei 'ethernet|network controller' \
        | ${pkgs.gnugrep}/bin/grep -Ei 'ethernet|network controller|Kernel driver in use' | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*/  /' || true

      titre "Audio"
      ${pkgs.pciutils}/bin/lspci -nnk | ${pkgs.gnugrep}/bin/grep -A3 -Ei 'audio' \
        | ${pkgs.gnugrep}/bin/grep -Ei 'audio|Kernel driver in use' | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*/  /' || true

      titre "Stockage"
      ${pkgs.util-linux}/bin/lsblk -d -o NAME,SIZE,MODEL,TRAN 2>/dev/null | ${pkgs.gnused}/bin/sed 's/^/  /' || true

      titre "Batterie"
      for b in /sys/class/power_supply/BAT*; do
        [ -d "$b" ] || continue
        CAP=$(${pkgs.coreutils}/bin/cat "$b/capacity" 2>/dev/null || echo '?')
        ST=$(${pkgs.coreutils}/bin/cat "$b/status" 2>/dev/null || echo '?')
        HEALTH=""
        if [ -r "$b/energy_full" ] && [ -r "$b/energy_full_design" ]; then
          HEALTH=$(${pkgs.gawk}/bin/awk -v f="$(${pkgs.coreutils}/bin/cat "$b/energy_full")" -v d="$(${pkgs.coreutils}/bin/cat "$b/energy_full_design")" 'BEGIN{if(d>0)printf " — santé %d%%", f*100/d}')
        fi
        printf '  %-13s : %s%% (%s)%s\n' "$(${pkgs.coreutils}/bin/basename "$b")" "$CAP" "$ST" "$HEALTH"
      done

      titre "Périphériques USB"
      ${pkgs.usbutils}/bin/lsusb 2>/dev/null | ${pkgs.gnugrep}/bin/grep -v 'root hub' | ${pkgs.gnused}/bin/sed 's/^/  /' || true
    }

    cmd_software() {
      printf '\n%s%s╭─ 󰅴 LOGICIEL %s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"

      titre "Noyau"
      printf '  En cours      : %s\n' "$(${pkgs.coreutils}/bin/uname -r)"
      if [ -e /run/booted-system ] && \
         [ "$(${pkgs.coreutils}/bin/readlink -f /run/booted-system/kernel)" != "$(${pkgs.coreutils}/bin/readlink -f /run/current-system/kernel)" ]; then
        warn "un autre kernel est installé — redémarrage nécessaire"
      else
        ok "kernel booté = kernel installé"
      fi

      titre "Pile graphique (mesa)"
      if command -v glxinfo >/dev/null 2>&1; then
        glxinfo -B 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E 'OpenGL renderer|OpenGL core profile version|OpenGL ES profile version' | ${pkgs.gnused}/bin/sed 's/^/  /'
      else
        info "glxinfo absent"
      fi
      if command -v vulkaninfo >/dev/null 2>&1; then
        vulkaninfo --summary 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E 'driverName|driverInfo|apiVersion' | ${pkgs.coreutils}/bin/head -3 | ${pkgs.gnused}/bin/sed 's/^[[:space:]]*/  /'
      fi

      titre "Firmware / microcode"
      if [ -d /run/current-system/firmware ] || [ -d /lib/firmware ]; then
        ok "firmware redistribuable présent"
      else
        warn "aucun répertoire firmware trouvé"
      fi
      if ${pkgs.coreutils}/bin/ls /sys/devices/system/cpu/cpu0/microcode >/dev/null 2>&1; then
        ok "microcode CPU chargé"
      else
        info "microcode : active hardware.cpu.amd.updateMicrocode = true;"
      fi

      titre "Modules kernel chargés (matériel)"
      ${pkgs.kmod}/bin/lsmod 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E '^(amdgpu|i915|nouveau|r8168|r8169|iwlwifi|btusb|snd_hda_intel|xe) ' \
        | ${pkgs.gawk}/bin/awk '{printf "  %-16s (utilisé %s fois)\n", $1, $3}' || info "aucun module notable"

      titre "Version NixOS / nixpkgs"
      printf '  NixOS         : %s\n' "$(${pkgs.coreutils}/bin/cat /run/current-system/nixos-version 2>/dev/null || echo inconnu)"
      printf '  Génération    : %s\n' "$(${pkgs.coreutils}/bin/readlink /nix/var/nix/profiles/system | ${pkgs.gnused}/bin/sed 's|.*system-||;s|-link||')"
      if [ -f "$FLAKE_DIR/flake.lock" ]; then
        LOCKED_DATE=$($JQ -r '.nodes.nixpkgs.locked.lastModified' "$FLAKE_DIR/flake.lock")
        printf '  nixpkgs figé  : %s\n' "$(${pkgs.coreutils}/bin/date -d "@$LOCKED_DATE" '+%d/%m/%Y %H:%M')"
      fi

      printf '\n'
      info "Lance « driver-update check » pour voir s'il y a du neuf."
    }

    cmd_status() {
      cmd_hardware
      cmd_software
    }

    cmd_check() {
      titre "Recherche de mises à jour nixpkgs"
      [ -f "$FLAKE_DIR/flake.lock" ] || { err "flake.lock introuvable dans $FLAKE_DIR"; return 1; }

      CURRENT_REV=$($JQ -r '.nodes.nixpkgs.locked.rev' "$FLAKE_DIR/flake.lock")
      BRANCH=$($JQ -r '.nodes.nixpkgs.original.ref // "nixos-unstable"' "$FLAKE_DIR/flake.lock")
      info "branche suivie : $BRANCH"

      LATEST_REV=$(${pkgs.coreutils}/bin/timeout 20 $GIT ls-remote https://github.com/NixOS/nixpkgs "$BRANCH" 2>/dev/null | ${pkgs.coreutils}/bin/cut -f1)
      if [ -z "$LATEST_REV" ]; then
        err "impossible de joindre github.com (pas de réseau ?)"
        return 1
      fi

      printf '  local  : %s\n' "''${CURRENT_REV:0:12}"
      printf '  amont  : %s\n' "''${LATEST_REV:0:12}"

      if [ "$CURRENT_REV" = "$LATEST_REV" ]; then
        ok "déjà à jour — rien à faire"
        return 0
      fi
      warn "des mises à jour sont disponibles (kernel / mesa / firmware inclus)"
      info "lance « driver-update update » pour les appliquer"
      return 10
    }

    cmd_update() {
      MODE="''${1:-switch}"
      titre "Mise à jour des pilotes"

      if [ ! -w "$FLAKE_DIR" ] && [ "$(id -u)" -ne 0 ]; then
        info "élévation sudo nécessaire pour écrire dans $FLAKE_DIR"
      fi

      info "1/3 — indexation git (les flakes ignorent les fichiers non trackés)"
      sudo ${pkgs.git}/bin/git -C "$FLAKE_DIR" add -A 2>/dev/null || warn "git add a échoué (dépôt absent ?)"

      info "2/3 — mise à jour de nixpkgs"
      if ! sudo ${pkgs.nix}/bin/nix flake update nixpkgs --flake "$FLAKE_DIR"; then
        err "échec de « nix flake update »"
        return 1
      fi
      ok "flake.lock mis à jour"

      info "3/3 — rebuild ($MODE) — kernel, firmware, mesa"
      if sudo ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$MODE" --flake "$FLAKE_DIR#$HOST"; then
        ok "pilotes à jour"
        if [ "$MODE" = "switch" ]; then
          NEW_KERNEL=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f /run/current-system/kernel)" 2>/dev/null || echo inconnu)
          RUNNING=$(${pkgs.coreutils}/bin/uname -r)
          printf '  kernel en cours : %s\n' "$RUNNING"
          if [ -e /run/booted-system ] && [ "$(${pkgs.coreutils}/bin/readlink -f /run/booted-system/kernel)" != "$(${pkgs.coreutils}/bin/readlink -f /run/current-system/kernel)" ]; then
            warn "nouveau kernel installé — redémarrage nécessaire pour l'activer"
            $NOTIFY "󰑓 Pilotes mis à jour" "Nouveau kernel installé. Redémarre pour l'activer." -i software-update-available -u normal 2>/dev/null || true
          else
            $NOTIFY "󰄬 Pilotes mis à jour" "Kernel, firmware et mesa sont à jour." -i software-update-available -u normal 2>/dev/null || true
          fi
        fi
        return 0
      fi

      err "échec du rebuild — le système n'a pas changé"
      info "reviens en arrière avec « driver-update rollback » si besoin"
      $NOTIFY "󰀪 Échec mise à jour pilotes" "Le rebuild a échoué, système inchangé." -i dialog-error -u critical 2>/dev/null || true
      return 1
    }

    cmd_rollback() {
      titre "Retour à la génération précédente"
      sudo ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --rollback --flake "$FLAKE_DIR#$HOST" \
        && ok "génération précédente restaurée" \
        || { err "rollback échoué"; return 1; }
    }

    case "''${1:-status}" in
      status)          cmd_status ;;
      hardware|hw|mat*) cmd_hardware ;;
      software|sw|log*) cmd_software ;;
      check)           cmd_check ;;
      update|upgrade)  cmd_update switch ;;
      dry|build)       cmd_update build ;;
      rollback)        cmd_rollback ;;
      help|-h|--help)  usage ;;
      *)               err "commande inconnue : $1"; printf '\n'; usage; exit 1 ;;
    esac
  '';
in
{
  home.packages = [
    driver-update
    pkgs.pciutils
    pkgs.usbutils
    pkgs.mesa-demos
  ];
}
