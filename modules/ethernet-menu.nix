{ config, pkgs, lib, ... }:

let
  ethernet-menu = pkgs.writeShellScriptBin "ethernet-menu" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    ROFI_BIN="${pkgs.rofi}/bin/rofi"

    notify() {
      $NOTIFY "Ethernet" "$1" -i network-wired -t 3000
    }

    rofi_eth() {
      $ROFI_BIN -normal-window -name ethernet-menu "$@"
    }

    # Détecter l'interface filaire active (ou la première disponible)
    detect_iface() {
      nmcli -t -f DEVICE,TYPE,STATE dev \
        | grep ":ethernet:" \
        | grep ":connected" \
        | head -1 | cut -d: -f1
    }

    detect_any_eth() {
      nmcli -t -f DEVICE,TYPE,STATE dev \
        | grep ":ethernet:" \
        | grep -v ":unmanaged" \
        | head -1 | cut -d: -f1
    }

    BACK="󰁍  Retour au menu"

    # Saisie avec valeur pré-remplie
    input_field() {
      local prompt="$1"
      local current="$2"
      printf "" | rofi_eth \
        -dmenu \
        -p "$prompt" \
        -filter "$current" \
        -theme ~/.config/rofi/network-input.rasi
    }

    show_main_menu() {
      IFACE=$(detect_iface)
      ANY_ETH=$(detect_any_eth)

      if [ -z "$ANY_ETH" ]; then
        notify "Aucune interface Ethernet trouvée"
        exit 1
      fi

      TARGET_IFACE="''${IFACE:-$ANY_ETH}"

      # Lire état actuel
      CURRENT_IP=$(nmcli -t -f IP4.ADDRESS dev show "$TARGET_IFACE" 2>/dev/null \
        | head -1 | cut -d: -f2 | cut -d/ -f1)
      CURRENT_METHOD=$(nmcli -t -f NAME,DEVICE connection show --active \
        | grep ":$TARGET_IFACE$" | head -1 | cut -d: -f1 \
        | xargs -I{} nmcli -t -f ipv4.method connection show "{}" 2>/dev/null \
        | head -1 | cut -d: -f2)

      [ -z "$CURRENT_METHOD" ] && CURRENT_METHOD="auto"

      if [ "$CURRENT_METHOD" = "auto" ]; then
        MODE_LABEL="DHCP"
        IP_LINE="<span foreground='#4ade80'>󰩟  IP (DHCP)    :  ''${CURRENT_IP:-en attente...}</span>"
      else
        MODE_LABEL="IP statique"
        IP_LINE="<span foreground='#fbbf24'>󰩟  IP (statique):  ''${CURRENT_IP:-N/A}</span>"
      fi

      if [ -n "$IFACE" ]; then
        PROMPT="󰈀  $TARGET_IFACE — $MODE_LABEL"
        STATUS_ICON="<span foreground='#4ade80'>󰈀  $TARGET_IFACE — connecté</span>"
      else
        PROMPT="󰈀  $TARGET_IFACE — déconnecté"
        STATUS_ICON="<span foreground='#f87171'>󰈂  $TARGET_IFACE — déconnecté</span>"
      fi

      SELECTION=$(printf \
"$STATUS_ICON
$IP_LINE
<span foreground='#4ade80'>󰩠  Infos réseau</span>
<span foreground='#fbbf24'>󰅢  Configurer IP statique</span>
<span foreground='#60a5fa'>  Passer en DHCP</span>
<span foreground='#94a3b8'>󰒓  Paramètres réseau avancés</span>" \
        | rofi_eth \
          -dmenu \
          -markup-rows \
          -p "$PROMPT" \
          -theme ~/.config/rofi/network.rasi \
          -no-custom)

      [ -z "$SELECTION" ] && exit 0

      case "$SELECTION" in
        *"Infos réseau"*)           show_ip "$TARGET_IFACE" ;;
        *"IP statique"*)            configure_static_ip "$TARGET_IFACE" ;;
        *"DHCP"*)                   set_dhcp "$TARGET_IFACE" ;;
        *"Paramètres"*)             nm-connection-editor ;;
      esac
    }

    show_ip() {
      local iface="$1"
      IP_ADDR=$(nmcli -t -f IP4.ADDRESS dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2 | cut -d/ -f1)
      MASK=$(nmcli -t -f IP4.ADDRESS dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2 | cut -d/ -f2)
      GATEWAY=$(nmcli -t -f IP4.GATEWAY dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2)
      DNS=$(nmcli -t -f IP4.DNS dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2)
      MAC=$(nmcli -t -f GENERAL.HWADDR dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2-)
      SPEED=$(cat /sys/class/net/"$iface"/speed 2>/dev/null && echo " Mbps" || echo "N/A")

      [ -z "$IP_ADDR" ] && IP_ADDR="N/A"
      [ -z "$MASK" ]    && MASK="N/A"
      [ -z "$GATEWAY" ] && GATEWAY="N/A"
      [ -z "$DNS" ]     && DNS="N/A"

      CHOICE=$(printf \
"$BACK
󰈀  Interface  :  $iface
󰩠  Adresse IP :  $IP_ADDR/$MASK
󰅶  Passerelle :  $GATEWAY
󰇛  DNS        :  $DNS
  MAC        :  $MAC" \
        | rofi_eth \
          -dmenu \
          -p "󰩟  Infos Ethernet" \
          -theme ~/.config/rofi/network.rasi \
          -no-custom)

      echo "$CHOICE" | grep -q "Retour" && show_main_menu
    }

    set_dhcp() {
      local iface="$1"
      CON=$(nmcli -t -f NAME,DEVICE connection show --active \
        | grep ":$iface$" | head -1 | cut -d: -f1)

      if [ -z "$CON" ]; then
        # Chercher une connexion même inactive
        CON=$(nmcli -t -f NAME,DEVICE connection show \
          | grep ":$iface$" | head -1 | cut -d: -f1)
      fi

      if [ -z "$CON" ]; then
        notify "Impossible de trouver la connexion pour $iface"
        show_main_menu
        return
      fi

      CONFIRM=$(printf "  Confirmer DHCP\n$BACK" | rofi_eth \
        -dmenu \
        -p "  Activer DHCP sur $iface ?" \
        -theme ~/.config/rofi/network.rasi \
        -no-custom)
      [ -z "$CONFIRM" ] && return
      echo "$CONFIRM" | grep -q "Retour" && show_main_menu && return

      nmcli connection modify "$CON" ipv4.method auto \
        ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
      nmcli connection down "$CON" 2>/dev/null
      nmcli connection up "$CON" 2>/dev/null
      notify "DHCP activé sur $iface — attente d'une adresse..."
    }

    configure_static_ip() {
      local iface="$1"
      CON=$(nmcli -t -f NAME,DEVICE connection show --active \
        | grep ":$iface$" | head -1 | cut -d: -f1)

      if [ -z "$CON" ]; then
        CON=$(nmcli -t -f NAME,DEVICE connection show \
          | grep ":$iface$" | head -1 | cut -d: -f1)
      fi

      if [ -z "$CON" ]; then
        notify "Impossible de trouver la connexion pour $iface"
        show_main_menu
        return
      fi

      # Pré-remplir avec les valeurs actuelles
      F_IP=$(nmcli -t -f IP4.ADDRESS dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2 | cut -d/ -f1)
      F_MASK=$(nmcli -t -f IP4.ADDRESS dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2 | cut -d/ -f2)
      F_GW=$(nmcli -t -f IP4.GATEWAY dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2)
      F_DNS1=$(nmcli -t -f IP4.DNS dev show "$iface" 2>/dev/null \
        | head -1 | cut -d: -f2)
      F_DNS2=$(nmcli -t -f IP4.DNS dev show "$iface" 2>/dev/null \
        | sed -n '2p' | cut -d: -f2)

      [ -z "$F_IP" ]   && F_IP="192.168.1.100"
      [ -z "$F_MASK" ] && F_MASK="24"
      [ -z "$F_GW" ]   && F_GW="192.168.1.1"
      [ -z "$F_DNS1" ] && F_DNS1="1.1.1.1"
      [ -z "$F_DNS2" ] && F_DNS2="8.8.8.8"

      while true; do
        if [ -n "$F_IP" ] && [ -n "$F_MASK" ] && [ -n "$F_GW" ] && [ -n "$F_DNS1" ]; then
          APPLY_LINE="  Appliquer la configuration"
        else
          APPLY_LINE="󰅙  Remplir tous les champs requis"
        fi

        FORM=$(printf \
"$BACK
─────────────────────────────
󰩠  Adresse IP   :  $F_IP
󰒓  Masque CIDR  :  /$F_MASK
󰅶  Passerelle   :  $F_GW
󰇛  DNS primaire :  $F_DNS1
󰇚  DNS alternat :  $F_DNS2
─────────────────────────────
$APPLY_LINE" \
          | rofi_eth \
            -dmenu \
            -p "󰅢  IP statique — $iface" \
            -theme ~/.config/rofi/network-form.rasi \
            -no-custom)

        [ -z "$FORM" ] && return
        echo "$FORM" | grep -q "Retour" && show_main_menu && return
        echo "$FORM" | grep -q "─"      && continue
        echo "$FORM" | grep -q "requis" && continue

        if echo "$FORM" | grep -q "Appliquer"; then
          if ! echo "$F_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            notify "Adresse IP invalide : $F_IP"
            continue
          fi
          if ! echo "$F_MASK" | grep -qE '^[0-9]+$' || [ "$F_MASK" -lt 1 ] || [ "$F_MASK" -gt 32 ]; then
            notify "Masque invalide : /$F_MASK  (doit être entre 1 et 32)"
            continue
          fi
          if ! echo "$F_GW" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            notify "Passerelle invalide : $F_GW"
            continue
          fi

          nmcli connection modify "$CON" ipv4.method manual
          nmcli connection modify "$CON" ipv4.addresses "$F_IP/$F_MASK"
          nmcli connection modify "$CON" ipv4.gateway "$F_GW"
          if [ -n "$F_DNS2" ]; then
            nmcli connection modify "$CON" ipv4.dns "$F_DNS1,$F_DNS2"
          else
            nmcli connection modify "$CON" ipv4.dns "$F_DNS1"
          fi
          nmcli connection down "$CON" 2>/dev/null
          nmcli connection up "$CON" 2>/dev/null
          notify "IP statique appliquée\n$F_IP/$F_MASK  via  $F_GW"
          return
        fi

        case "$FORM" in
          *"Adresse IP"*)
            VAL=$(input_field "󰩠  Adresse IP" "$F_IP")
            [ -n "$VAL" ] && F_IP="$VAL" ;;
          *"Masque"*)
            VAL=$(input_field "󰒓  Masque CIDR  (ex: 24)" "$F_MASK")
            [ -n "$VAL" ] && F_MASK="$VAL" ;;
          *"Passerelle"*)
            VAL=$(input_field "󰅶  Passerelle" "$F_GW")
            [ -n "$VAL" ] && F_GW="$VAL" ;;
          *"DNS primaire"*)
            VAL=$(input_field "󰇛  DNS primaire  (ex: 1.1.1.1)" "$F_DNS1")
            [ -n "$VAL" ] && F_DNS1="$VAL" ;;
          *"DNS alternat"*)
            VAL=$(input_field "󰇚  DNS alternatif  (optionnel)" "$F_DNS2")
            F_DNS2="$VAL" ;;
        esac
      done
    }

    show_main_menu
  '';
in
{
  home.packages = [ ethernet-menu ];
}
