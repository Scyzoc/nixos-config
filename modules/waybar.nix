{ config, pkgs, ... }:

let

  # --- SCRIPT STATUT BLUETOOTH (remplace le module natif qui se masque) ---
  bluetooth-status = pkgs.writeShellScriptBin "bluetooth-status" ''
    BT="${pkgs.bluez}/bin/bluetoothctl"
    ICON_BT=$(printf '\xef\x8a\x93')
    ICON_ON=$(printf '\xef\x8a\x94')
    ICON_OFF=$(printf '\xef\x8a\x93')

    # Verifie l'etat via D-Bus (rapide, sans TTY)
    if ! dbus-send --system --print-reply --dest=org.bluez /org/bluez/hci0 \
        org.freedesktop.DBus.Properties.Get \
        string:"org.bluez.Adapter1" string:"Powered" \
        2>/dev/null | grep -q "boolean true"; then
      printf '{"text":"%s","class":"off","tooltip":"Bluetooth desactive"}\n' "$ICON_OFF"
      exit 0
    fi

    # Cherche un appareil connecte (via pipe, fonctionne sans TTY)
    CONNECTED=$({ printf 'devices Connected\n'; sleep 0.5; } | $BT 2>/dev/null | grep "^Device " | head -1)

    if [ -n "$CONNECTED" ]; then
      MAC=$(echo "$CONNECTED" | awk '{print $2}')
      NAME=$(echo "$CONNECTED" | cut -d' ' -f3-)
      DEV_PATH="/org/bluez/hci0/dev_$(echo "$MAC" | tr ':' '_')"

      BATT=$(dbus-send --system --print-reply --dest=org.bluez "$DEV_PATH" \
        org.freedesktop.DBus.Properties.Get \
        string:"org.bluez.Battery1" string:"Percentage" \
        2>/dev/null | grep "byte" | awk '{print $2}')

      if [ -n "$BATT" ]; then
        printf '{"text":"%s %s %s%%","class":"connected","tooltip":"%s"}\n' "$ICON_ON" "$NAME" "$BATT" "$NAME"
      else
        printf '{"text":"%s %s","class":"connected","tooltip":"%s"}\n' "$ICON_ON" "$NAME" "$NAME"
      fi
    else
      printf '{"text":"%s","class":"on","tooltip":"Bluetooth actif"}\n' "$ICON_BT"
    fi
  '';

  # --- SCRIPT RESSOURCES ---
  sys-script = pkgs.writeShellScriptBin "sys-resource" ''
    STATE_FILE="/tmp/waybar_sys_mode"
    [ ! -f "$STATE_FILE" ] && echo "cpu" > "$STATE_FILE"
    MODE=$(cat "$STATE_FILE")

    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%d", usage}')
    RAM_USED=$(free -m | awk '/Mem:/ { printf("%.1f", $3/1024) }')
    RAM_TOTAL=$(free -m | awk '/Mem:/ { printf("%.1f", $2/1024) }')
    RAM_PERCENT=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)

    if [ "$CPU_USAGE" -gt 80 ] || [ "$RAM_PERCENT" -gt 85 ]; then
        CLASS="critical"; TEXT="󰍛 $CPU_USAGE%"
        [ "$RAM_PERCENT" -gt 85 ] && TEXT="󰾆 $RAM_PERCENT%"
    elif [ "$MODE" = "cpu" ]; then
        TEXT="󰍛 $CPU_USAGE%"; CLASS="cpu"
    else
        TEXT="󰾆 $RAM_PERCENT%"; CLASS="ram"
    fi

    echo "{\"text\": \"$TEXT\", \"class\": \"$CLASS\", \"tooltip\": \"󰍛 CPU: $CPU_USAGE%\n󰾆 RAM: $RAM_USED Go / $RAM_TOTAL Go ($RAM_PERCENT%)\"}"
  '';

  toggle-sys = pkgs.writeShellScriptBin "toggle-sys" ''
    STATE_FILE="/tmp/waybar_sys_mode"
    CURRENT=$(cat "$STATE_FILE")
    [ "$CURRENT" = "cpu" ] && echo "ram" > "$STATE_FILE" || echo "cpu" > "$STATE_FILE"
    pkill -RTMIN+8 waybar
  '';

  waybar-clock = pkgs.writeShellScriptBin "waybar-clock" ''
    WEATHER_CACHE="/tmp/waybar_weather_emoji"
    TOOLTIP_CACHE="/tmp/waybar_weather_tooltip"
    LAST_FETCH_FILE="/tmp/waybar_weather_last"
    NOW=$(date +%s)

    [ ! -f "$WEATHER_CACHE" ] && echo "🌤️" > "$WEATHER_CACHE"
    [ ! -f "$TOOLTIP_CACHE" ] && echo "Meteo en cours de chargement..." > "$TOOLTIP_CACHE"
    [ ! -f "$LAST_FETCH_FILE" ] && echo "0" > "$LAST_FETCH_FILE"

    LAST_FETCH=$(cat "$LAST_FETCH_FILE")
    CURRENT_TOOLTIP=$(cat "$TOOLTIP_CACHE")

    RETRY_TIME=900
    if [[ "$CURRENT_TOOLTIP" == *"chargement"* ]]; then
        RETRY_TIME=60
    fi

    if [ $((NOW - LAST_FETCH)) -ge $RETRY_TIME ]; then
        NEW_EMOJI=$(timeout 4s curl -s "wttr.in/Paris?format=%c" | tr -d '[:space:]')
        NEW_TOOLTIP=$(timeout 4s curl -s "wttr.in/Paris?format=Paris:+%C+%t+%w" | tr -d '\n\r' | sed 's/"/\\"/g')

        if [ -n "$NEW_EMOJI" ] && [ -n "$NEW_TOOLTIP" ]; then
            echo "$NEW_EMOJI" > "$WEATHER_CACHE"
            echo "$NEW_TOOLTIP" > "$TOOLTIP_CACHE"
            echo "$NOW" > "$LAST_FETCH_FILE"
        fi
    fi

    STATE_FILE="/tmp/waybar_clock_mode"
    [ ! -f "$STATE_FILE" ] && echo "time" > "$STATE_FILE"
    MODE=$(cat "$STATE_FILE")

    if [ "$MODE" = "time" ]; then
        EMOJI=$(cat "$WEATHER_CACHE")
        TEXT="$EMOJI  $(date +%H:%M)"
        TOOLTIP=$(cat "$TOOLTIP_CACHE")
    else
        TEXT="$(date +%d/%m/%Y)"
        CAL=$(${pkgs.util-linux}/bin/cal | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
        TOOLTIP="<tt><small>$CAL</small></tt>"
    fi

    echo "{\"text\": \"$TEXT\", \"tooltip\": \"$TOOLTIP\"}"
  '';

  toggle-clock = pkgs.writeShellScriptBin "toggle-clock" ''
    STATE_FILE="/tmp/waybar_clock_mode"
    [ ! -f "$STATE_FILE" ] && echo "time" > "$STATE_FILE"
    [ "$(cat $STATE_FILE)" = "time" ] && echo "date" > "$STATE_FILE" || echo "time" > "$STATE_FILE"
    pkill -RTMIN+9 waybar
  '';

  # Config commune bluetooth custom (identique pour les deux barres)
  btModule = {
    "exec" = "${bluetooth-status}/bin/bluetooth-status";
    "return-type" = "json";
    "interval" = 5;
    "on-click" = "bluetooth-menu";
    "on-click-right" = "blueman-manager";
  };

in

{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    systemd.targets = [ "hyprland-session.target" ];

    settings.mainBar = {
        output = "eDP-1";
        layer = "top";
        position = "top";
        height = 36;
        spacing = 4;
        margin-top = 5;
        margin-left = 10;
        margin-right = 10;

        modules-left = [ "hyprland/workspaces" ];

        "hyprland/workspaces" = {
          "persistent-workspaces" = {
            "eDP-1" = [ 1 2 3 4 5 ];
          };
        };
        modules-center = [ "custom/clock" ];
        modules-right = [ "custom/mpris-scroll" "pulseaudio" "custom/sys-resource" "custom/bluetooth" "network#eth" "network" "custom/battery" "custom/power" ];

        "custom/clock" = {
          "exec" = "${waybar-clock}/bin/waybar-clock";
          "return-type" = "json";
          "interval" = 1;
          "on-click" = "${toggle-clock}/bin/toggle-clock";
          "on-click-right" = "brave --app=https://calendar.notion.so/";
          "signal" = 9;
        };

        "custom/mpris-scroll" = {
          "exec" = "mpris-scroller";
          "return-type" = "json";
          "format" = "{}";
          "on-click" = "${pkgs.playerctl}/bin/playerctl play-pause";
          "on-click-middle" = "${pkgs.playerctl}/bin/playerctl previous";
          "on-click-right" = "${pkgs.playerctl}/bin/playerctl next";
        };

        "custom/sys-resource" = {
          "exec" = "${sys-script}/bin/sys-resource";
          "return-type" = "json";
          "interval" = 2;
          "on-click" = "${toggle-sys}/bin/toggle-sys";
          "signal" = 8;
        };

        "pulseaudio" = {
          "states" = {
            "vol-0" = 0; "vol-5" = 5; "vol-10" = 10; "vol-15" = 15; "vol-20" = 20;
            "vol-25" = 25; "vol-30" = 30; "vol-35" = 35; "vol-40" = 40; "vol-45" = 45;
            "vol-50" = 50; "vol-55" = 55; "vol-60" = 60; "vol-65" = 65; "vol-70" = 70;
            "vol-75" = 75; "vol-80" = 80; "vol-85" = 85; "vol-90" = 90; "vol-95" = 95;
          };
          "format" = "{icon} {volume}%";
          "format-muted" = "󰝟";
          "format-icons" = { "default" = [ "󰕿" "󰖀" "󰕾" ]; };
          "on-click" = "hyprctl dispatch exec '[float; center; size 700 500; animation popin] pavucontrol'";
        };

        "custom/bluetooth" = btModule;

        "network#eth" = {
          "interface" = "enp*";
          "format-ethernet" = "󰈀 {ipaddr}";
          "format-disconnected" = "";
          "format-disabled" = "";
          "tooltip-format" = "󰈀 {ifname} via {gwaddr}";
          "on-click" = "ethernet-menu";
        };

        "network" = {
          "interface" = "wlp*";
          "format-wifi" = "{icon}  {essid}";
          "format-linked" = "{icon}  {essid}";
          "format-disconnected" = "󰤮 ";
          "format-disabled" = "󰤮 ";
          "format-icons" = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
          "on-click" = "network-menu";
          "tooltip-format" = "󰩟 {ipaddr}\n󰓅 {signalStrength}%\n󰓅 {frequency}MHz";
        };

        "custom/battery" = {
          "exec" = "battery-status";
          "return-type" = "json";
          "interval" = 5;
          "on-click" = "bat-menu";
          "signal" = 7;
          "tooltip" = true;
        };

        "custom/power" = { "format" = "⏻"; "on-click" = "wlogout"; };
    };

    style = ''
      * {
        font-family: JetBrainsMono Nerd Font;
        font-size: 13px;
        border: none;
        min-height: 0;
        text-shadow: 0px 0px 2px rgba(0, 0, 0, 0.5);
      }

      window#waybar {
        background-color: rgba(0, 0, 0, 0.25);
        border: 1px solid rgba(255, 255, 255, 0.2);
        border-radius: 12px;
        color: #ffffff;
      }

      #workspaces {
        background-color: rgba(255, 255, 255, 0.05);
        margin: 4px;
        padding: 0 4px;
        border-radius: 8px;
        border: 1px solid rgba(255, 255, 255, 0.1);
      }

      #workspaces button {
        color: #ffffff;
        padding: 0 8px;
        margin: 3px 2px;
        border-radius: 6px;
      }

      #workspaces button.active {
        background-color: rgba(255, 255, 255, 0.2);
        color: #ffffff;
        border: 1px solid rgba(255, 255, 255, 0.3);
      }

      #workspaces button.empty {
        padding: 0 3px;
        min-width: 8px;
        color: rgba(255, 255, 255, 0.2);
        font-size: 8px;
      }

      #custom-clock, #pulseaudio, #custom-bluetooth, #network, #custom-battery, #custom-sys-resource, #custom-power {
        background-color: rgba(255, 255, 255, 0.05);
        padding: 0 10px;
        margin: 6px 2px;
        border-radius: 10px;
        border: 1px solid rgba(255, 255, 255, 0.1);
        color: #ffffff;
        transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.68);
      }

      #custom-clock:hover, #pulseaudio:hover, #custom-bluetooth:hover, #network:hover, #custom-battery:hover, #custom-sys-resource:hover, #custom-power:hover {
        background-color: rgba(255, 255, 255, 0.2);
        color: #ffffff;
        box-shadow: 0 0 10px rgba(255, 255, 255, 0.2);
      }

      #custom-power {
        padding: 0 12px;
        margin-right: 8px;
      }

      #custom-mpris-scroll {
        color: #1DB954;
        font-weight: bold;
        margin: 4px 0;
        margin-right: 18px;
        min-width: 20px;
      }

      #custom-mpris-scroll.youtube { color: #ff4444; }
      #custom-mpris-scroll.web     { color: #f9e2af; }
      #custom-mpris-scroll.Paused  { color: #6c7086; font-weight: normal; }

      #custom-sys-resource.cpu      { color: #89b4fa; }
      #custom-sys-resource.ram      { color: #f5c2e7; }
      #custom-sys-resource.critical { color: #f38ba8; animation: blink 0.5s linear infinite alternate; }

      #custom-clock { color: #ffffff; font-weight: bold; }

      #pulseaudio         { color: #89dceb; }
      #pulseaudio.vol-0   { color: #6c7086; }
      #pulseaudio.vol-5   { color: #6e758b; }
      #pulseaudio.vol-10  { color: #707a90; }
      #pulseaudio.vol-15  { color: #727f95; }
      #pulseaudio.vol-20  { color: #74849a; }
      #pulseaudio.vol-25  { color: #76899f; }
      #pulseaudio.vol-30  { color: #788ea4; }
      #pulseaudio.vol-35  { color: #7a93a9; }
      #pulseaudio.vol-40  { color: #7c98ae; }
      #pulseaudio.vol-45  { color: #7e9db3; }
      #pulseaudio.vol-50  { color: #80a2b8; }
      #pulseaudio.vol-55  { color: #82a7bd; }
      #pulseaudio.vol-60  { color: #84acc2; }
      #pulseaudio.vol-65  { color: #86b1c7; }
      #pulseaudio.vol-70  { color: #88b6cc; }
      #pulseaudio.vol-75  { color: #89bbd1; }
      #pulseaudio.vol-80  { color: #8bc0d6; }
      #pulseaudio.vol-85  { color: #8dc5db; }
      #pulseaudio.vol-90  { color: #8fcae0; }
      #pulseaudio.vol-95  { color: #91cfe5; }
      #pulseaudio.muted   { color: #f38ba8; }

      #network            { color: #a6e3a1; }
      #network.linked     { color: #fab387; }
      #network.disconnected { color: #f38ba8; }
      #network.disabled   { color: #6c7086; }
      #network#eth        { color: #a6e3a1; }

      #custom-bluetooth           { color: #89b4fa; }
      #custom-bluetooth.connected { color: #89b4fa; }
      #custom-bluetooth.off       { color: #f38ba8; }

      #custom-battery                  { color: #fab387; }
      #custom-battery.normal-high     { color: #a6e3a1; }
      #custom-battery.normal-med      { color: #f9e2af; }
      #custom-battery.normal-low      { color: #fab387; }
      #custom-battery.normal-vlow     { color: #e07060; }
      #custom-battery.eco             { color: #94e2d5; }
      #custom-battery.performance     { color: #f38ba8; }
      #custom-battery.charging        { color: #89b4fa; }
      #custom-battery.critical        { color: #f38ba8; animation: blink 0.5s linear infinite alternate; }

      #custom-power { color: #f38ba8; }

      @keyframes blink {
        to { background-color: rgba(243, 139, 168, 0.7); color: #11111b; }
      }
    '';
  };

  # Barre pour le deuxieme ecran (workspaces 6-10)
  programs.waybar.settings.secondBar = {
    output = [ "DP-4" "DP-5" "DP-6" ];
    layer = "top";
    position = "top";
    height = 36;
    spacing = 4;
    margin-top = 5;
    margin-left = 10;
    margin-right = 10;

    modules-left = [ "hyprland/workspaces" ];

    "hyprland/workspaces" = {
      "persistent-workspaces" = {
        "DP-4" = [ 6 7 8 9 10 ];
        "DP-5" = [ 6 7 8 9 10 ];
        "DP-6" = [ 6 7 8 9 10 ];
      };
    };

    modules-center = [ "custom/clock" ];
    modules-right = [ "custom/mpris-scroll" "pulseaudio" "custom/sys-resource" "custom/bluetooth" "network#eth" "network" "custom/battery" "custom/power" ];

    "custom/clock" = {
      "exec" = "${waybar-clock}/bin/waybar-clock";
      "return-type" = "json";
      "interval" = 1;
      "on-click" = "${toggle-clock}/bin/toggle-clock";
      "on-click-right" = "brave --app=https://calendar.notion.so/";
      "signal" = 9;
    };

    "custom/mpris-scroll" = {
      "exec" = "mpris-scroller";
      "return-type" = "json";
      "format" = "{}";
      "on-click" = "${pkgs.playerctl}/bin/playerctl play-pause";
      "on-click-middle" = "${pkgs.playerctl}/bin/playerctl previous";
      "on-click-right" = "${pkgs.playerctl}/bin/playerctl next";
    };

    "custom/sys-resource" = {
      "exec" = "${sys-script}/bin/sys-resource";
      "return-type" = "json";
      "interval" = 2;
      "on-click" = "${toggle-sys}/bin/toggle-sys";
      "signal" = 8;
    };

    "pulseaudio" = {
      "format" = "{icon} {volume}%";
      "format-muted" = "󰝟";
      "format-icons" = { "default" = [ "󰕿" "󰖀" "󰕾" ]; };
      "on-click" = "hyprctl dispatch exec '[float; center; size 700 500; animation popin] pavucontrol'";
    };

    "custom/bluetooth" = btModule;

    "network#eth" = {
      "interface" = "enp*";
      "format-ethernet" = "󰈀 {ipaddr}";
      "format-disconnected" = "";
      "format-disabled" = "";
      "tooltip-format" = "󰈀 {ifname} via {gwaddr}";
      "on-click" = "ethernet-menu";
    };

    "network" = {
      "interface" = "wlp*";
      "format-wifi" = "{icon}  {essid}";
      "format-linked" = "{icon}  {essid} (no internet)";
      "format-disconnected" = "󰤮 ";
      "format-disabled" = "󰤮 ";
      "format-icons" = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
      "on-click" = "network-menu";
      "tooltip-format" = "󰩟 {ipaddr}\n󰓅 {signalStrength}%\n󰓅 {frequency}MHz";
    };

    "custom/battery" = {
      "exec" = "battery-status";
      "return-type" = "json";
      "interval" = 5;
      "on-click" = "bat-menu";
      "signal" = 7;
      "tooltip" = true;
    };

    "custom/power" = { "format" = "⏻"; "on-click" = "wlogout"; };
  };

  # Force le mode "time" au demarrage de Waybar
  systemd.user.services.waybar.Service.ExecStartPre = "${pkgs.coreutils}/bin/rm -f /tmp/waybar_clock_mode";
}
