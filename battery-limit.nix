{ pkgs, lib, ... }:

let
  # Valeurs autorisées : 50 à 100 % par pas de 5 (100 = pas de limite)
  levels = map toString (lib.genList (i: 50 + 5 * i) 11);
  levelsCase = lib.concatStringsSep "|" levels;

  # `battery-limit <50..100>` : fixe la limite de charge (ThinkPad, thinkpad_acpi).
  # `battery-limit restore`    : réapplique le dernier choix (démarrage).
  # Appelé depuis la barre (Battery.qml) via sudo sans mot de passe.
  battery-limit = pkgs.writeShellScriptBin "battery-limit" ''
    set -eu
    BAT=/sys/class/power_supply/BAT0
    STATE=/var/lib/battery-limit/limit

    case "''${1:-}" in
      ${levelsCase}) END=$1 ;;
      restore) END=$(${pkgs.coreutils}/bin/cat "$STATE" 2>/dev/null || echo 80) ;;
      *) echo "Usage : battery-limit 50|55|…|100|restore" >&2; exit 2 ;;
    esac
    case "$END" in ${levelsCase}) ;; *) END=80 ;; esac

    # Reprise de la charge 5 points sous la limite (évite les micro-cycles)
    START=$(( END - 5 ))

    # Le noyau refuse start >= end : l'ordre d'écriture dépend du sens
    if [ "$END" -ge "$(${pkgs.coreutils}/bin/cat $BAT/charge_control_end_threshold)" ]; then
      echo "$END"   > $BAT/charge_control_end_threshold
      echo "$START" > $BAT/charge_control_start_threshold
    else
      echo "$START" > $BAT/charge_control_start_threshold
      echo "$END"   > $BAT/charge_control_end_threshold
    fi

    ${pkgs.coreutils}/bin/mkdir -p /var/lib/battery-limit
    echo "$END" > "$STATE"
  '';
in
{
  environment.systemPackages = [ battery-limit ];

  # Arguments figés : seules les valeurs 50..100 (pas de 5) passent sans mot de passe
  security.sudo.extraConfig = lib.concatMapStrings
    (l: "user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/battery-limit ${l}\n") levels;

  # Réapplique le choix au démarrage. Pas d'ordre vis-à-vis de TLP : il ne gère
  # plus les seuils (et tlp.service démarre après multi-user.target → cycle).
  systemd.services.battery-limit = {
    description = "Limite de charge batterie (dernier choix)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${battery-limit}/bin/battery-limit restore";
    };
  };
}
