{ pkgs, ... }:

let
  # ============================================================
  # APPLICATION D'UN MODE (partagé entre menu et toggle)
  # ============================================================
  apply-power-mode = pkgs.writeShellScriptBin "apply-power-mode" ''
    MODE="$1"
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    STATE_FILE="/tmp/waybar_power_mode"

    case "$MODE" in
      eco)
        sudo cpupower frequency-set -g powersave 2>/dev/null
        ${pkgs.brightnessctl}/bin/brightnessctl set 30% 2>/dev/null
        for iface in /sys/class/net/wlp*; do
          iface=$(basename "$iface")
          ${pkgs.iw}/bin/iw dev "$iface" set power_save on 2>/dev/null
        done
        printf "lock=180\ndpms=210\n" > /tmp/hypridle_timeouts
        systemctl --user restart hypridle 2>/dev/null
        echo "eco" > "$STATE_FILE"
        $NOTIFY "Mode Éco" "CPU powersave · Luminosité 30% · Wi-Fi powersave ON" -i battery -t 2500
        ;;
      performance)
        sudo cpupower frequency-set -g performance 2>/dev/null
        ${pkgs.brightnessctl}/bin/brightnessctl set 80% 2>/dev/null
        for iface in /sys/class/net/wlp*; do
          iface=$(basename "$iface")
          ${pkgs.iw}/bin/iw dev "$iface" set power_save off 2>/dev/null
        done
        printf "lock=600\ndpms=630\n" > /tmp/hypridle_timeouts
        systemctl --user restart hypridle 2>/dev/null
        echo "performance" > "$STATE_FILE"
        $NOTIFY "Mode Performance" "CPU performance · Luminosité 80% · Hypridle 10min" -i battery -t 2500
        ;;
      normal)
        sudo cpupower frequency-set -g powersave 2>/dev/null
        for iface in /sys/class/net/wlp*; do
          iface=$(basename "$iface")
          ${pkgs.iw}/bin/iw dev "$iface" set power_save off 2>/dev/null
        done
        printf "lock=300\ndpms=330\n" > /tmp/hypridle_timeouts
        systemctl --user restart hypridle 2>/dev/null
        echo "normal" > "$STATE_FILE"
        $NOTIFY "Mode Normal" "TLP reprend la main · Hypridle 5min" -i battery -t 2500
        ;;
    esac

  '';

  # ============================================================
  # SCRIPT PRINCIPAL : affichage batterie + mode énergie (JSON)
  # ============================================================
  battery-status = pkgs.writeShellScriptBin "battery-status" ''
    BAT_PATH="/sys/class/power_supply/BAT0"
    STATE_FILE="/tmp/waybar_power_mode"

    [ ! -f "$STATE_FILE" ] && echo "normal" > "$STATE_FILE"
    MODE=$(cat "$STATE_FILE")

    CAP=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "?")
    STATUS=$(cat "$BAT_PATH/status" 2>/dev/null || echo "Unknown")

    # L'adaptateur secteur (AC/online) bascule instantanément, alors que
    # BAT0/status met plusieurs secondes à passer en "Charging" au branchement.
    # On considère donc la machine "en charge" dès que AC/online vaut 1,
    # sauf si la batterie est déjà pleine ("Full").
    AC_ONLINE=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo "0")
    if [ "$AC_ONLINE" = "1" ] && [ "$STATUS" != "Full" ]; then
      STATUS="Charging"
    fi

    # Icône : police "BatteryIcons" (assets/battery-icons-font.py)
    #   U+E000..U+E00A = niveau 0..100 % par pas de 10, U+E00C..U+E016 = idem en charge
    #   U+E00B = en charge sans jauge (niveau inconnu)
    if [ "$STATUS" = "Charging" ] && [ "$CAP" != "?" ]; then
      HEX=$(printf '%x' $(( 140 + (CAP + 5) / 10 )))
      GLYPH=$(printf "\xee\x80\x$HEX"); CLASS="charging"
    elif [ "$STATUS" = "Charging" ]; then
      GLYPH=$(printf '\xee\x80\x8b'); CLASS="charging"
    elif [ "$CAP" = "?" ]; then
      GLYPH=$(printf '\xee\x80\x80'); CLASS="unknown"
    else
      HEX=$(printf '%x' $(( 128 + (CAP + 5) / 10 )))
      GLYPH=$(printf "\xee\x80\x$HEX")
    fi
    ICON="<span font_family='BatteryIcons' font_size='14pt' rise='-1pt'>$GLYPH</span>"

    if [ "$STATUS" != "Charging" ]; then
      if [ "$CAP" != "?" ] && [ "$CAP" -le 15 ]; then
        CLASS="critical"
      elif [ "$MODE" = "normal" ] && [ "$CAP" != "?" ]; then
        if   [ "$CAP" -ge 75 ]; then CLASS="normal-high"
        elif [ "$CAP" -ge 50 ]; then CLASS="normal-med"
        elif [ "$CAP" -ge 25 ]; then CLASS="normal-low"
        else                         CLASS="normal-vlow"
        fi
      else
        CLASS="$MODE"
      fi
    fi

    case "$MODE" in
      eco)         MODE_LABEL="󱠰 Éco"        ;;
      performance) MODE_LABEL="󰓅 Performance" ;;
      *)           MODE_LABEL="⚡ Normal"     ;;
    esac

    TOOLTIP="$ICON $CAP%  ·  $STATUS\n\nMode actuel : $MODE_LABEL\n󰍹 Clic pour changer de profil"
    echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
  '';

in
{
  home.packages = [ apply-power-mode battery-status ];
}
