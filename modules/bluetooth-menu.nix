{ config, pkgs, lib, ... }:

let
  BT = "${pkgs.bluez}/bin/bluetoothctl";
  NOTIFY = "${pkgs.libnotify}/bin/notify-send";
  ROFI = "${pkgs.rofi}/bin/rofi";

  bluetooth-menu = pkgs.writeShellScriptBin "bluetooth-menu" ''
    BT="${BT}"
    NOTIFY="${NOTIFY}"
    ROFI="${ROFI}"
    BACK="󰁍  Retour au menu"

    notify() {
      $NOTIFY "Bluetooth" "$1" -i bluetooth -t 3000
    }

    # bluetoothctl ne produit aucune sortie en mode sous-commande sans TTY.
    # Cette fonction le lance en mode interactif via pipe, ce qui fonctionne.
    bt() {
      { printf '%s\n' "$*"; sleep 0.5; } | $BT 2>/dev/null
    }

    # Récupère le nom d'un appareil depuis son MAC
    device_name() {
      local mac="$1"
      bt "info $mac" | grep "Name:" | sed 's/.*Name: //' | xargs
    }

    show_main_menu() {
      BT_STATE=$(bt "show" | grep "Powered:" | awk '{print $2}')
      CONNECTED_MAC=$(bt "devices Connected" | grep "^Device " | head -1 | awk '{print $2}')
      CONNECTED_NAME=""
      [ -n "$CONNECTED_MAC" ] && CONNECTED_NAME=$(device_name "$CONNECTED_MAC")

      # Prompt dynamique
      if [ "$BT_STATE" = "yes" ]; then
        if [ -n "$CONNECTED_NAME" ]; then
          PROMPT="  $CONNECTED_NAME"
        else
          PROMPT="  Bluetooth actif"
        fi
      else
        PROMPT="  Bluetooth désactivé"
      fi

      if [ "$BT_STATE" = "yes" ]; then
        OPTIONS="<span foreground='#60a5fa'>󰂴  Connecter un appareil</span>"
        OPTIONS="$OPTIONS\n<span foreground='#f87171'>󰂲  Désactiver le Bluetooth</span>"
        OPTIONS="$OPTIONS\n<span foreground='#4ade80'>󰂰  Appareils associés</span>"
        if [ -n "$CONNECTED_NAME" ]; then
          OPTIONS="$OPTIONS\n<span foreground='#fbbf24'>󱐋  Déconnecter  $CONNECTED_NAME</span>"
        fi
        OPTIONS="$OPTIONS\n<span foreground='#f87171'>󱘖  Dissocier un appareil</span>"
        OPTIONS="$OPTIONS\n<span foreground='#38bdf8'>󰋑  Infos appareil</span>"
      else
        OPTIONS="<span foreground='#60a5fa'>  Activer le Bluetooth</span>"
      fi

      SELECTION=$(printf "$OPTIONS" | $ROFI \
        -dmenu \
        -markup-rows \
        -p "$PROMPT" \
        -theme ~/.config/rofi/network.rasi \
        -no-custom)

      [ -z "$SELECTION" ] && exit 0

      case "$SELECTION" in
        *"Connecter"*)      scan_and_connect ;;
        *"Appareils"*)      connect_paired ;;
        *"Déconnecter"*)    disconnect_device ;;
        *"Dissocier"*)      remove_device ;;
        *"Infos"*)          device_info ;;
        *"Désactiver"*)     echo "power off" | $BT 2>/dev/null; notify "Bluetooth désactivé" ;;
        *"Activer"*)        echo "power on"  | $BT 2>/dev/null; notify "Bluetooth activé"; sleep 1; show_main_menu ;;
      esac
    }

    scan_and_connect() {
      notify "Recherche d'appareils..."
      # Lance le scan 8 secondes dans une session unique puis l'arrête
      { printf 'scan on\n'; sleep 8; printf 'scan off\n'; } | $BT 2>/dev/null

      # Récupère la liste des appareils associés en une seule requête
      PAIRED_MACS=$(bt "devices Paired" | grep "^Device " | awk '{print $2}')

      # Liste uniquement les appareils non encore associés
      DEVICES=$(bt "devices" | grep "^Device " | while read -r _ mac name; do
        [ -z "$mac" ] && continue
        printf '%s\n' "$PAIRED_MACS" | grep -qx "$mac" && continue
        echo "󰂴  $name  [$mac]"
      done)

      if [ -z "$DEVICES" ]; then
        notify "Aucun appareil trouvé"
        show_main_menu
        return
      fi

      CHOICE=$(printf "$BACK\n%s" "$DEVICES" | $ROFI \
        -dmenu \
        -i \
        -p "󰂴  Appareil" \
        -theme ~/.config/rofi/network.rasi)

      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      # Extraire le MAC (entre crochets)
      MAC=$(echo "$CHOICE" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
      NAME=$(echo "$CHOICE" | sed 's/^.\{1\}[[:space:]]*//' | sed "s/  \[$MAC\]//")
      [ -z "$MAC" ] && return

      notify "Connexion à $NAME..."
      if { printf 'connect %s\n' "$MAC"; sleep 12; } | $BT 2>/dev/null | grep -q "successful"; then
        notify "Connecté à $NAME"
      else
        # Tente de pairer d'abord si pas encore fait
        notify "Association avec $NAME..."
        echo "pair $MAC"  | $BT 2>/dev/null
        echo "trust $MAC" | $BT 2>/dev/null
        if { printf 'connect %s\n' "$MAC"; sleep 12; } | $BT 2>/dev/null | grep -q "successful"; then
          notify "Connecté à $NAME"
        else
          notify "Échec de connexion à $NAME"
        fi
      fi
    }

    connect_paired() {
      CONNECTED_MACS=$(bt "devices Connected" | grep "^Device " | awk '{print $2}')
      PAIRED=$(bt "devices Paired" | grep "^Device " | while read -r _ mac name; do
        [ -z "$mac" ] && continue
        if printf '%s\n' "$CONNECTED_MACS" | grep -qx "$mac"; then
          echo "  $name  [$mac]"
        else
          echo "  $name  [$mac]"
        fi
      done)

      if [ -z "$PAIRED" ]; then
        notify "Aucun appareil associé"
        show_main_menu
        return
      fi

      CHOICE=$(printf "$BACK\n%s" "$PAIRED" | $ROFI \
        -dmenu \
        -i \
        -p "󰂰  Associés" \
        -theme ~/.config/rofi/network.rasi)

      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      MAC=$(echo "$CHOICE" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
      NAME=$(echo "$CHOICE" | sed 's/^.\{1\}[[:space:]]*//' | sed "s/  \[$MAC\]//")
      [ -z "$MAC" ] && return

      if printf '%s\n' "$CONNECTED_MACS" | grep -qx "$MAC"; then
        notify "Déjà connecté à $NAME"
      else
        notify "Connexion à $NAME..."
        if { printf 'connect %s\n' "$MAC"; sleep 12; } | $BT 2>/dev/null | grep -q "successful"; then
          notify "Connecté à $NAME"
        else
          notify "Échec de connexion à $NAME"
        fi
      fi
    }

    disconnect_device() {
      CONNECTED=$(bt "devices Connected" | grep "^Device " | while read -r _ mac name; do
        [ -z "$mac" ] && continue
        echo "  $name  [$mac]"
      done)

      if [ -z "$CONNECTED" ]; then
        notify "Aucun appareil connecté"
        show_main_menu
        return
      fi

      CHOICE=$(printf "$BACK\n%s" "$CONNECTED" | $ROFI \
        -dmenu \
        -i \
        -p "󱐋  Déconnecter" \
        -theme ~/.config/rofi/network.rasi)

      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      MAC=$(echo "$CHOICE" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
      NAME=$(echo "$CHOICE" | sed 's/^.\{1\}[[:space:]]*//' | sed "s/  \[$MAC\]//")
      [ -z "$MAC" ] && return

      echo "disconnect $MAC" | $BT 2>/dev/null
      notify "Déconnecté de $NAME"
    }

    remove_device() {
      PAIRED=$(bt "devices Paired" | grep "^Device " | while read -r _ mac name; do
        [ -z "$mac" ] && continue
        echo "  $name  [$mac]"
      done)

      if [ -z "$PAIRED" ]; then
        notify "Aucun appareil associé"
        show_main_menu
        return
      fi

      CHOICE=$(printf "$BACK\n%s" "$PAIRED" | $ROFI \
        -dmenu \
        -i \
        -p "󱘖  Dissocier" \
        -theme ~/.config/rofi/network.rasi)

      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      MAC=$(echo "$CHOICE" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
      NAME=$(echo "$CHOICE" | sed 's/^.\{1\}[[:space:]]*//' | sed "s/  \[$MAC\]//")
      [ -z "$MAC" ] && return

      CONFIRM=$(printf "  Oui, dissocier\n$BACK" | $ROFI \
        -dmenu \
        -p "Dissocier « $NAME » ?" \
        -theme ~/.config/rofi/network.rasi \
        -no-custom)

      [ -z "$CONFIRM" ] && return
      echo "$CONFIRM" | grep -q "Retour" && show_main_menu && return

      echo "remove $MAC" | $BT 2>/dev/null
      notify "« $NAME » dissocié"
    }

    device_info() {
      CONNECTED_MACS=$(bt "devices Connected" | grep "^Device " | awk '{print $2}')
      DEVICE_LIST=$(bt "devices Paired" | grep "^Device " | while read -r _ mac name; do
        [ -z "$mac" ] && continue
        if printf '%s\n' "$CONNECTED_MACS" | grep -qx "$mac"; then
          echo "  $name  [$mac]"
        else
          echo "  $name  [$mac]"
        fi
      done)

      if [ -z "$DEVICE_LIST" ]; then
        notify "Aucun appareil associé"
        show_main_menu
        return
      fi

      CHOICE=$(printf "$BACK\n%s" "$DEVICE_LIST" | $ROFI \
        -dmenu \
        -i \
        -p "󰋑  Infos" \
        -theme ~/.config/rofi/network.rasi)

      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      MAC=$(echo "$CHOICE" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
      [ -z "$MAC" ] && return

      INFO=$(bt "info $MAC")
      NAME=$(echo "$INFO"    | grep "Name:"      | sed 's/.*Name: //'      | xargs)
      ICON=$(echo "$INFO"    | grep "Icon:"      | sed 's/.*Icon: //'      | xargs)
      IS_PAIRED=$(echo "$INFO"  | grep "Paired:"    | sed 's/.*Paired: //'    | xargs)
      TRUSTED=$(echo "$INFO" | grep "Trusted:"   | sed 's/.*Trusted: //'   | xargs)
      CONN=$(echo "$INFO"    | grep "Connected:" | sed 's/.*Connected: //' | xargs)
      BATT=$(echo "$INFO"    | grep "Battery Percentage:" | sed 's/.*Battery Percentage: //' | sed 's/ (.*//' | xargs)

      [ -z "$NAME" ]      && NAME="N/A"
      [ -z "$ICON" ]      && ICON="N/A"
      [ -z "$IS_PAIRED" ] && IS_PAIRED="no"
      [ -z "$TRUSTED" ]   && TRUSTED="no"
      [ -z "$CONN" ]      && CONN="no"

      yn_icon() {
        [ "$1" = "yes" ] \
          && echo "<span foreground='#4ade80'>󰸞</span>" \
          || echo "<span foreground='#f87171'>󰅙</span>"
      }

      IS_PAIRED_ICON=$(yn_icon "$IS_PAIRED")
      TRUSTED_ICON=$(yn_icon "$TRUSTED")
      CONN_ICON=$(yn_icon "$CONN")

      BATT_LINE=""
      [ -n "$BATT" ] && BATT_LINE="\n󰁹  Batterie     :  $BATT%"

      printf "$BACK\n󰀄  Nom          :  $NAME\n󰾰  Adresse MAC  :  $MAC\n󰋑  Type         :  $ICON\n󰌷  Associé      :  $IS_PAIRED_ICON\n󰒘  De confiance :  $TRUSTED_ICON\n󰂱  Connecté     :  $CONN_ICON$BATT_LINE" \
        | $ROFI \
          -dmenu \
          -markup-rows \
          -p "󰋑  $NAME" \
          -theme ~/.config/rofi/network.rasi \
          -no-custom \
        | grep -q "Retour" && show_main_menu
    }

    show_main_menu
  '';
in
{
  home.packages = [ bluetooth-menu ];
}
