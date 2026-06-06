{ config, pkgs, lib, ... }:

let
  network-menu = pkgs.writeShellScriptBin "network-menu" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    ROFI_BIN="${pkgs.rofi}/bin/rofi"

    notify() {
      $NOTIFY "Réseau" "$1" -i network-wireless -t 3000
    }

    # Wrapper rofi avec classe Hyprland propre (pour animation popin indépendante)
    rofi_net() {
      $ROFI_BIN -normal-window -name network-menu "$@"
    }

    # Icônes signal Wi-Fi (Nerd Font)
    signal_icon() {
      local sig=$1
      if   [ "$sig" -ge 75 ]; then echo "󰤨"
      elif [ "$sig" -ge 50 ]; then echo "󰤥"
      elif [ "$sig" -ge 25 ]; then echo "󰤢"
      else                         echo "󰤟"
      fi
    }

    show_main_menu() {
      WIFI_STATE=$(nmcli -t -f WIFI g)
      CURRENT_SSID=$(nmcli -t -f NAME,TYPE connection show --active | grep '802-11-wireless' | head -1 | cut -d: -f1)
      ETH_STATE=$(nmcli -t -f DEVICE,STATE dev | grep "ethernet" | grep "connected" | head -1 | cut -d: -f1)
      # Prompt dynamique
      if [ "$WIFI_STATE" = "enabled" ]; then
        if [ -n "$CURRENT_SSID" ]; then
          PROMPT="󰖩  $CURRENT_SSID"
        else
          PROMPT="󰖩  Wi-Fi actif"
        fi
      else
        PROMPT="󰖪  Wi-Fi désactivé"
      fi

      # Construction du menu
      if [ "$WIFI_STATE" = "enabled" ]; then
        OPTIONS="<span foreground='#60a5fa'>󰖩  Se connecter à un réseau</span>"
        OPTIONS="$OPTIONS\n<span foreground='#f87171'>󰖪  Désactiver le Wi-Fi</span>"
        OPTIONS="$OPTIONS\n<span foreground='#f87171'>󰚼  Oublier un réseau</span>"
        OPTIONS="$OPTIONS\n<span foreground='#4ade80'>󰩟  Voir mon adresse IP</span>"
        OPTIONS="$OPTIONS\n<span foreground='#fbbf24'>󰅢  Configuration IP manuelle</span>"
        OPTIONS="$OPTIONS\n<span foreground='#38bdf8'>  Mode avion</span>"
        OPTIONS="$OPTIONS\n<span foreground='#94a3b8'>󰒓  Paramètres réseau avancés</span>"
      else
        OPTIONS="<span foreground='#60a5fa'>󰖩  Activer le Wi-Fi</span>"
        OPTIONS="$OPTIONS\n<span foreground='#38bdf8'>  Mode avion</span>"
        OPTIONS="$OPTIONS\n<span foreground='#94a3b8'>󰒓  Paramètres réseau avancés</span>"
      fi

      SELECTION=$(printf "$OPTIONS" | rofi_net \
        -dmenu \
        -markup-rows \
        -p "$PROMPT" \
        -theme ~/.config/rofi/network.rasi \
        -no-custom)
      [ -z "$SELECTION" ] && exit 0

      case "$SELECTION" in
        *"Se connecter"*)       scan_and_connect ;;
        *"Oublier"*)            forget_network ;;
        *"adresse IP"*)         show_ip ;;
        *"Configuration IP"*)   configure_ip ;;
