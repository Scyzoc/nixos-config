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

    pkill -RTMIN+7 waybar
  '';

  # ============================================================
  # MENU ROFI : popup dépliant depuis la Waybar
  # ============================================================
  power-menu = pkgs.writeShellScriptBin "bat-menu" ''
    if pgrep -x rofi > /dev/null; then
      pkill -x rofi
      exit 0
    fi

    STATE_FILE="/tmp/waybar_power_mode"
    [ ! -f "$STATE_FILE" ] && echo "normal" > "$STATE_FILE"
    MODE=$(cat "$STATE_FILE")

    # Indicateur sur le mode actif
    mark_eco=""; mark_normal=""; mark_perf=""
    case "$MODE" in
      eco)         mark_eco="  " ;;
      performance) mark_perf="  " ;;
      *)           mark_normal="  " ;;
    esac

    OPTIONS="󱠰  Éco$mark_eco\n⚡  Normal$mark_normal\n󰓅  Performance$mark_perf"

    case "$MODE" in
      eco)         SEL=0 ;;
      normal)      SEL=1 ;;
      performance) SEL=2 ;;
      *)           SEL=1 ;;
    esac

    MENU_W=180
    MENU_Y=43   # juste sous la Waybar (margin-top 5 + height 34 + gap 4)

    # Injecter position et taille dans le thème Rofi (layer shell natif, pas de -normal-window)
    # Ancré en haut à droite, avec un décalage de 10px depuis le bord droit et sous la Waybar
    THEME_POS=$(printf 'window { location: north east; anchor: north east; x-offset: -10px; y-offset: %dpx; width: %dpx; }' \
      "$MENU_Y" "$MENU_W")

    CHOICE=$(printf "$OPTIONS" | ${pkgs.rofi}/bin/rofi \
      -dmenu \
      -p "" \
      -selected-row "$SEL" \
      -theme ~/.config/rofi/power-menu.rasi \
      -theme-str "$THEME_POS" \
      -no-custom)

    [ -z "$CHOICE" ] && exit 0

    case "$CHOICE" in
      *Éco*)         ${apply-power-mode}/bin/apply-power-mode eco ;;
      *Normal*)      ${apply-power-mode}/bin/apply-power-mode normal ;;
      *Performance*) ${apply-power-mode}/bin/apply-power-mode performance ;;
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

    if [ "$STATUS" = "Charging" ]; then
      ICON="󱐋"; CLASS="charging"
    elif [ "$CAP" = "?" ]; then
      ICON="󰂑"; CLASS="unknown"
    elif [ "$CAP" -ge 90 ]; then ICON="󰁹"
    elif [ "$CAP" -ge 80 ]; then ICON="󰂂"
    elif [ "$CAP" -ge 70 ]; then ICON="󰂁"
    elif [ "$CAP" -ge 60 ]; then ICON="󰂀"
    elif [ "$CAP" -ge 50 ]; then ICON="󰁿"
    elif [ "$CAP" -ge 40 ]; then ICON="󰁾"
    elif [ "$CAP" -ge 30 ]; then ICON="󰁽"
    elif [ "$CAP" -ge 20 ]; then ICON="󰁼"
    elif [ "$CAP" -ge 10 ]; then ICON="󰁻"
    else                          ICON="󰁺"
    fi

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
    echo "{\"text\": \"$ICON $CAP%\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
  '';

in
{
  # ============================================================
  # THEME ROFI — MENU POPUP POWER (dépliant depuis Waybar)
  # ============================================================
  xdg.configFile."rofi/power-menu.rasi".text = ''
    configuration {
      show-icons: false;
      font: "JetBrainsMono Nerd Font 13";
      disable-history: true;
      kb-mode-next: "";
      kb-mode-previous: "";
    }
    * {
      background-color: transparent;
      text-color: #ffffff;
    }
    window {
      width: 180px;
      border: 2px;
      border-color: rgba(255, 255, 255, 0.2);
      border-radius: 0px 0px 15px 15px;
      background-color: rgba(0, 0, 0, 0.25);
      padding: 4px;
    }
    mainbox {
      spacing: 4px;
      children: [listview];
    }
    inputbar { enabled: false; height: 0; min-height: 0; }
    listview {
      lines: 3;
      spacing: 4px;
      scrollbar: false;
      padding: 2px;
      fixed-height: false;
    }
    element {
      padding: 8px 12px;
      border-radius: 10px;
      orientation: horizontal;
    }
    element-text {
      background-color: transparent;
      text-color: #ffffff;
      font: "JetBrainsMono Nerd Font 13";
      vertical-align: 0.5;
    }
    element selected {
      background-color: rgba(255, 255, 255, 0.1);
      border: 2px;
      border-color: rgba(255, 255, 255, 0.9);
    }
    element-text selected {
      text-color: #ffffff;
    }
  '';

  home.packages = [ apply-power-mode battery-status power-menu ];
}
