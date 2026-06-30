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
      VPN_ACTIVE=$(nmcli -t -f NAME,TYPE connection show --active | grep -E ":(vpn|wireguard)$" | head -1 | cut -d: -f1)

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

      # Entrée VPN dynamique
      if [ -n "$VPN_ACTIVE" ]; then
        VPN_ENTRY="<span foreground='#a78bfa'>󰦝  VPN  ·  $VPN_ACTIVE</span>"
      else
        VPN_ENTRY="<span foreground='#a78bfa'>󰦜  VPN</span>"
      fi

      # Construction du menu
      if [ "$WIFI_STATE" = "enabled" ]; then
        OPTIONS="<span foreground='#60a5fa'>󰖩  Se connecter à un réseau</span>"
        OPTIONS="$OPTIONS\n<span foreground='#f87171'>󰖪  Désactiver le Wi-Fi</span>"
        OPTIONS="$OPTIONS\n<span foreground='#f87171'>󰚼  Oublier un réseau</span>"
        OPTIONS="$OPTIONS\n<span foreground='#4ade80'>󰩟  Voir mon adresse IP</span>"
        OPTIONS="$OPTIONS\n<span foreground='#fbbf24'>󰅢  Configuration IP manuelle</span>"
        OPTIONS="$OPTIONS\n$VPN_ENTRY"
        OPTIONS="$OPTIONS\n<span foreground='#38bdf8'>  Mode avion</span>"
        OPTIONS="$OPTIONS\n<span foreground='#94a3b8'>󰒓  Paramètres réseau avancés</span>"
      else
        OPTIONS="<span foreground='#60a5fa'>󰖩  Activer le Wi-Fi</span>"
        OPTIONS="$OPTIONS\n$VPN_ENTRY"
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
        *"VPN"*)                show_vpn_menu ;;
        *"Désactiver"*)         nmcli radio wifi off && notify "Wi-Fi désactivé" ;;
        *"Activer le Wi-Fi"*)   nmcli radio wifi on  && notify "Wi-Fi activé" ;;
        *"Mode avion"*)         toggle_airplane ;;
        *"Paramètres"*)         nm-connection-editor ;;
      esac
    }

    BACK="󰁍  Retour au menu"

    scan_and_connect() {
      notify "Recherche de réseaux..."
      nmcli device wifi rescan 2>/dev/null
      sleep 1.5

      SAVED=$(nmcli -t -f NAME,TYPE connection show | grep "802-11-wireless" | cut -d: -f1)

      WIFI_RAW=$(nmcli --terse --fields "SIGNAL,SECURITY,SSID" device wifi list 2>/dev/null \
        | sort -t: -k1 -rn \
        | head -30 \
        | while IFS=: read -r sig sec ssid; do
            [ -z "$ssid" ] && continue
            icon=$(signal_icon "$sig")
            echo "$icon   $ssid"
          done \
        | awk '!seen[$0]++')

      KNOWN="" UNKNOWN=""
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        ssid=$(echo "$line" | sed 's/^.   //')
        if echo "$SAVED" | grep -qxF "$ssid"; then
          KNOWN="$KNOWN$line\n"
        else
          UNKNOWN="$UNKNOWN$line\n"
        fi
      done <<< "$WIFI_RAW"

      WIFI_LIST=$(printf "$KNOWN$UNKNOWN")

      if [ -z "$WIFI_LIST" ]; then
        notify "Aucun réseau trouvé"
        show_main_menu
        return
      fi

      REFRESH="              <span foreground='#60a5fa'>󰑐  Actualiser</span>"
      CHOICE=$(printf "$BACK\n$REFRESH\n%s" "$WIFI_LIST" | rofi_net \
        -dmenu \
        -markup-rows \
        -i \
        -p "󰖩  Réseau" \
        -theme ~/.config/rofi/network.rasi \
        -active 1)

      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour"    && show_main_menu && return
      echo "$CHOICE" | grep -q "Actualiser" && scan_and_connect && return

      # Extraire le SSID (enlever l'icône + espaces)
      SSID=$(echo "$CHOICE" | sed 's/^.\{1\}[[:space:]]*//' | sed 's/^[[:space:]]*//')

      notify "Connexion à $SSID..."

      if nmcli device wifi connect "$SSID" 2>/dev/null; then
        notify "Connecté à $SSID"
      else
        PASS=$(rofi_net \
          -dmenu \
          -password \
          -p "󰌋  Mot de passe" \
          -theme ~/.config/rofi/network-input.rasi)
        if [ -z "$PASS" ]; then
          show_main_menu
          return
        fi
        if nmcli device wifi connect "$SSID" password "$PASS" 2>/dev/null; then
          notify "Connecté à $SSID"
        else
          notify "Échec de connexion à $SSID"
        fi
      fi
    }

    show_saved() {
      SAVED=$(nmcli -t -f NAME,TYPE connection show | grep "802-11-wireless" | cut -d: -f1)
      if [ -z "$SAVED" ]; then
        notify "Aucun réseau sauvegardé"
        show_main_menu
        return
      fi

      CHOICE=$(printf "$BACK\n%s" "$SAVED" | rofi_net \
        -dmenu \
        -i \
        -p "󰁾  Sauvegardés" \
        -theme ~/.config/rofi/network.rasi)
      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      notify "Connexion à $CHOICE..."
      if nmcli connection up "$CHOICE" 2>/dev/null; then
        notify "Connecté à $CHOICE"
      else
        notify "Échec de connexion à $CHOICE"
      fi
    }

    forget_network() {
      SAVED=$(nmcli -t -f NAME,TYPE connection show | grep "802-11-wireless" | cut -d: -f1)
      if [ -z "$SAVED" ]; then
        notify "Aucun réseau à oublier"
        show_main_menu
        return
      fi

      CHOICE=$(printf "$BACK\n%s" "$SAVED" | rofi_net \
        -dmenu \
        -i \
        -p "󰚼  Oublier" \
        -theme ~/.config/rofi/network.rasi)
      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      CONFIRM=$(printf "  Oui, oublier\n$BACK" | rofi_net \
        -dmenu \
        -p "Oublier « $CHOICE » ?" \
        -theme ~/.config/rofi/network.rasi \
        -no-custom)
      [ -z "$CONFIRM" ] && return
      echo "$CONFIRM" | grep -q "Retour" && show_main_menu && return

      nmcli connection delete "$CHOICE" 2>/dev/null
      notify "« $CHOICE » oublié"
    }

    show_ip() {
      IFACE=$(nmcli -t -f DEVICE,STATE dev | grep connected | head -1 | cut -d: -f1)
      if [ -z "$IFACE" ]; then
        notify "Aucune connexion active"
        show_main_menu
        return
      fi

      IP_ADDR=$(nmcli -t -f IP4.ADDRESS dev show "$IFACE" 2>/dev/null | head -1 | cut -d: -f2 | cut -d/ -f1)
      GATEWAY=$(nmcli -t -f IP4.GATEWAY dev show "$IFACE" 2>/dev/null | head -1 | cut -d: -f2)
      DNS=$(nmcli -t -f IP4.DNS dev show "$IFACE" 2>/dev/null | head -1 | cut -d: -f2)

      [ -z "$IP_ADDR" ] && IP_ADDR="N/A"
      [ -z "$GATEWAY" ] && GATEWAY="N/A"
      [ -z "$DNS" ]     && DNS="N/A"

      CHOICE=$(printf "$BACK\n󰩟  Interface  :  $IFACE\n󰩠  Adresse IP :  $IP_ADDR\n󰅶  Passerelle :  $GATEWAY\n󰇛  DNS        :  $DNS" \
        | rofi_net \
          -dmenu \
          -p "󰩟  Infos réseau" \
          -theme ~/.config/rofi/network.rasi \
          -no-custom)
      echo "$CHOICE" | grep -q "Retour" && show_main_menu
    }

    toggle_airplane() {
      RADIO_STATE=$(nmcli -t -f WIFI g)
      if [ "$RADIO_STATE" = "enabled" ]; then
        nmcli radio all off
        notify "Mode avion activé"
      else
        nmcli radio wifi on
        notify "Mode avion désactivé"
      fi
    }

    # Saisie avec valeur pré-remplie
    input_field() {
      local prompt="$1"
      local current="$2"
      printf "" | rofi_net \
        -dmenu \
        -p "$prompt" \
        -filter "$current" \
        -theme ~/.config/rofi/network-input.rasi
    }

    configure_ip() {
      # IFACE = nom du device (wlan0, eth0…)
      # CON   = nom de la connexion NM (ex: "Freebox-5G") — requis par nmcli connection modify
      IFACE=$(nmcli -t -f DEVICE,STATE dev | grep ":connected" | head -1 | cut -d: -f1)
      if [ -z "$IFACE" ]; then
        notify "Aucune connexion active"
        show_main_menu
        return
      fi
      CON=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$IFACE$" | head -1 | cut -d: -f1)
      if [ -z "$CON" ]; then
        notify "Impossible de trouver la connexion pour $IFACE"
        show_main_menu
        return
      fi

      # Choix du mode
      CURRENT_METHOD=$(nmcli -t -f ipv4.method connection show "$CON" 2>/dev/null | head -1 | cut -d: -f2)
      [ -z "$CURRENT_METHOD" ] && CURRENT_METHOD="auto"

      if [ "$CURRENT_METHOD" = "auto" ]; then
        MODE_LABEL="DHCP (actuel)"
      else
        MODE_LABEL="Statique (actuel)"
      fi

      MODE=$(printf "$BACK\n  Passer en IP statique\n  Passer en DHCP" \
        | rofi_net \
          -dmenu \
          -p "󰅢  IP — $CON  [$MODE_LABEL]" \
          -theme ~/.config/rofi/network.rasi \
          -no-custom)
      [ -z "$MODE" ] && return
      echo "$MODE" | grep -q "Retour" && show_main_menu && return

      # --- DHCP ---
      if echo "$MODE" | grep -q "DHCP"; then
        CONFIRM=$(printf "  Confirmer DHCP\n$BACK" | rofi_net \
          -dmenu \
          -p "󰅢  Activer DHCP sur $CON ?" \
          -theme ~/.config/rofi/network.rasi \
          -no-custom)
        [ -z "$CONFIRM" ] && return
        echo "$CONFIRM" | grep -q "Retour" && configure_ip && return
        nmcli connection modify "$CON" ipv4.method auto \
          ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
        nmcli connection down "$CON" 2>/dev/null
        nmcli connection up "$CON" 2>/dev/null
        notify "DHCP activé — attente d'une adresse sur $IFACE..."
        return
      fi

      # --- IP Statique : formulaire interactif ---
      # Pré-remplir avec les valeurs actuelles lues depuis le device
      F_IP=$(nmcli -t -f IP4.ADDRESS dev show "$IFACE" 2>/dev/null | head -1 | cut -d: -f2 | cut -d/ -f1)
      F_MASK=$(nmcli -t -f IP4.ADDRESS dev show "$IFACE" 2>/dev/null | head -1 | cut -d: -f2 | cut -d/ -f2)
      F_GW=$(nmcli -t -f IP4.GATEWAY dev show "$IFACE" 2>/dev/null | head -1 | cut -d: -f2)
      F_DNS1=$(nmcli -t -f IP4.DNS dev show "$IFACE" 2>/dev/null | head -1 | cut -d: -f2)
      F_DNS2=$(nmcli -t -f IP4.DNS dev show "$IFACE" 2>/dev/null | sed -n '2p' | cut -d: -f2)

      [ -z "$F_IP" ]   && F_IP="192.168.1.100"
      [ -z "$F_MASK" ] && F_MASK="24"
      [ -z "$F_GW" ]   && F_GW="192.168.1.1"
      [ -z "$F_DNS1" ] && F_DNS1="1.1.1.1"
      [ -z "$F_DNS2" ] && F_DNS2="8.8.8.8"

      # Boucle formulaire
      while true; do
        # Vérification : tous les champs obligatoires remplis ?
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
          | rofi_net \
            -dmenu \
            -p "󰅢  IP statique — $IFACE" \
            -theme ~/.config/rofi/network-form.rasi \
            -no-custom)

        [ -z "$FORM" ] && return
        echo "$FORM" | grep -q "Retour"    && show_main_menu && return
        echo "$FORM" | grep -q "─"         && continue
        echo "$FORM" | grep -q "requis"    && continue

        if echo "$FORM" | grep -q "Appliquer"; then
          # Validation basique
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
          # Application — on utilise CON (nom de connexion NM), pas IFACE (device)
          nmcli connection modify "$CON" ipv4.method manual
          nmcli connection modify "$CON" ipv4.addresses "$F_IP/$F_MASK"
          nmcli connection modify "$CON" ipv4.gateway "$F_GW"
          if [ -n "$F_DNS2" ]; then
            nmcli connection modify "$CON" ipv4.dns "$F_DNS1,$F_DNS2"
          else
            nmcli connection modify "$CON" ipv4.dns "$F_DNS1"
          fi
          nmcli connection up "$CON" 2>/dev/null
          notify "IP statique appliquée\n$F_IP/$F_MASK  via  $F_GW"
          return
        fi

        # Édition du champ sélectionné
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

    show_vpn_menu() {
      VPN_ACTIVE=$(nmcli -t -f NAME,TYPE connection show --active | grep -E ":(vpn|wireguard)$" | cut -d: -f1)
      VPN_ALL=$(nmcli -t -f NAME,TYPE connection show | grep -E ":(vpn|wireguard)$" | cut -d: -f1)

      if [ -z "$VPN_ALL" ]; then
        notify "Aucun profil VPN configuré\nAjoutez-en via les paramètres réseau."
        show_main_menu
        return
      fi

      if [ -n "$VPN_ACTIVE" ]; then
        PROMPT="󰦝  VPN actif : $VPN_ACTIVE"
        OPTIONS="$BACK\n󰦜  Déconnecter  :  $VPN_ACTIVE"
        while IFS= read -r vpn; do
          [ "$vpn" = "$VPN_ACTIVE" ] && continue
          OPTIONS="$OPTIONS\n󰦝  $vpn"
        done <<< "$VPN_ALL"
      else
        PROMPT="󰦜  VPN"
        OPTIONS="$BACK"
        while IFS= read -r vpn; do
          OPTIONS="$OPTIONS\n󰦝  $vpn"
        done <<< "$VPN_ALL"
      fi

      CHOICE=$(printf "$OPTIONS" | rofi_net \
        -dmenu \
        -p "$PROMPT" \
        -theme ~/.config/rofi/network.rasi \
        -no-custom)

      [ -z "$CHOICE" ] && return
      echo "$CHOICE" | grep -q "Retour" && show_main_menu && return

      if echo "$CHOICE" | grep -q "Déconnecter"; then
        nmcli connection down "$VPN_ACTIVE" 2>/dev/null
        notify "VPN déconnecté"
        return
      fi

      # Extraire le nom du VPN (enlever l'icône + espaces)
      VPN_NAME=$(echo "$CHOICE" | sed 's/^.\{1\}[[:space:]]*//' | sed 's/^[[:space:]]*//')
      notify "Connexion VPN : $VPN_NAME..."
      if nmcli connection up "$VPN_NAME" 2>/dev/null; then
        notify "VPN connecté : $VPN_NAME"
      else
        notify "Échec de connexion VPN : $VPN_NAME"
      fi
    }

    show_main_menu
  '';
in
{
  # ==========================================================================
  # THEME ROFI — MENU RÉSEAU (style cohérent avec clipboard/emoji)
  # ==========================================================================
  xdg.configFile."rofi/network.rasi".text = ''
    configuration {
      show-icons: false;
      font: "Inter 12";
      disable-history: true;
      kb-mode-next: "";
      kb-mode-previous: "";
    }
    * {
      background-color: transparent;
      text-color: #ffffff;
    }
    window {
      width: 480px;
      border: 2px;
      border-color: rgba(255, 255, 255, 0.2);
      border-radius: 15px;
      background-color: rgba(0, 0, 0, 0.25);
      padding: 10px;
    }
    mainbox {
      spacing: 10px;
    }
    inputbar {
      padding: 8px 12px;
      margin: 0px 0px 4px 0px;
      background-color: rgba(255, 255, 255, 0.05);
      border: 1px;
      border-color: rgba(255, 255, 255, 0.1);
      border-radius: 10px;
      children: [prompt, textbox-prompt-sep, entry];
    }
    prompt {
      color: rgba(255, 255, 255, 0.85);
      font: "JetBrainsMono Nerd Font 13";
      vertical-align: 0.5;
      padding: 0px 4px 0px 0px;
    }
    textbox-prompt-sep {
      str: "│";
      expand: false;
      color: rgba(255, 255, 255, 0.2);
      vertical-align: 0.5;
      padding: 0px 8px;
    }
    entry {
      color: rgba(255, 255, 255, 0.4);
      placeholder: "Filtrer...";
      placeholder-color: rgba(255, 255, 255, 0.25);
      vertical-align: 0.5;
    }
    listview {
      lines: 10;
      spacing: 4px;
      scrollbar: false;
      padding: 2px;
    }
    element {
      padding: 10px 14px;
      border-radius: 10px;
    }
    element-text {
      background-color: transparent;
      text-color: #ffffff;
      font: "JetBrainsMono Nerd Font 12";
      vertical-align: 0.5;
    }
    element selected {
      background-color: rgba(255, 255, 255, 0.1);
      border: 2px;
      border-color: rgba(255, 255, 255, 0.9);
    }
    element-text selected {
      background-color: transparent;
      text-color: #ffffff;
    }
    element normal active {
      background-color: rgba(96, 165, 250, 0.1);
      border-radius: 10px;
      border: 0px 0px 1px 0px;
      border-color: rgba(96, 165, 250, 0.3);
      padding: 10px 14px 14px 14px;
    }
    element-text normal active {
      text-color: #60a5fa;
    }
    element selected active {
      background-color: rgba(96, 165, 250, 0.25);
      border: 2px;
      border-color: #60a5fa;
    }
    element-text selected active {
      text-color: #60a5fa;
    }
  '';

  # ==========================================================================
  # THEME ROFI — SAISIE TEXTE (IP, mot de passe, DNS…)
  # ==========================================================================
  xdg.configFile."rofi/network-input.rasi".text = ''
    configuration {
      show-icons: false;
      font: "Inter 12";
      disable-history: true;
      kb-mode-next: "";
      kb-mode-previous: "";
    }
    * {
      background-color: transparent;
      text-color: #ffffff;
    }
    window {
      width: 480px;
      border: 2px;
      border-color: rgba(255, 255, 255, 0.2);
      border-radius: 15px;
      background-color: rgba(0, 0, 0, 0.25);
      padding: 10px;
    }
    mainbox {
      spacing: 10px;
      children: [inputbar];
    }
    inputbar {
      padding: 8px 12px;
      background-color: rgba(255, 255, 255, 0.05);
      border: 1px;
      border-color: rgba(255, 255, 255, 0.1);
      border-radius: 10px;
      children: [prompt, textbox-prompt-sep, entry];
    }
    prompt {
      color: rgba(255, 255, 255, 0.85);
      font: "JetBrainsMono Nerd Font 13";
      vertical-align: 0.5;
      padding: 0px 4px 0px 0px;
    }
    textbox-prompt-sep {
      str: "│";
      expand: false;
      color: rgba(255, 255, 255, 0.2);
      vertical-align: 0.5;
      padding: 0px 8px;
    }
    entry {
      color: #ffffff;
      placeholder: "Saisir...";
      placeholder-color: rgba(255, 255, 255, 0.3);
      vertical-align: 0.5;
    }
    listview {
      enabled: false;
      height: 0;
      min-height: 0;
    }
    element { enabled: false; }
    element-text { enabled: false; }
  '';

  # ==========================================================================
  # THEME ROFI — FORMULAIRE IP STATIQUE
  # Lignes de séparation grisées, "Appliquer" en vert, champs éditables en blanc
  # ==========================================================================
  xdg.configFile."rofi/network-form.rasi".text = ''
    configuration {
      show-icons: false;
      font: "JetBrainsMono Nerd Font 12";
      disable-history: true;
      kb-mode-next: "";
      kb-mode-previous: "";
    }
    * {
      background-color: transparent;
      text-color: #ffffff;
    }
    window {
      width: 520px;
      border: 2px;
      border-color: rgba(255, 255, 255, 0.2);
      border-radius: 15px;
      background-color: rgba(17, 17, 27, 0.92);
      padding: 10px;
    }
    mainbox {
      spacing: 10px;
    }
    inputbar {
      padding: 8px 12px;
      margin: 0px 0px 4px 0px;
      background-color: rgba(255, 255, 255, 0.05);
      border: 1px;
      border-color: rgba(255, 255, 255, 0.1);
      border-radius: 10px;
      children: [prompt, textbox-prompt-sep, entry];
    }
    prompt {
      color: rgba(255, 255, 255, 0.85);
      font: "JetBrainsMono Nerd Font 13";
      vertical-align: 0.5;
      padding: 0px 4px 0px 0px;
    }
    textbox-prompt-sep {
      str: "│";
      expand: false;
      color: rgba(255, 255, 255, 0.2);
      vertical-align: 0.5;
      padding: 0px 8px;
    }
    entry {
      color: rgba(255,255,255,0);
      placeholder: "";
      vertical-align: 0.5;
    }
    listview {
      lines: 12;
      spacing: 2px;
      scrollbar: false;
      padding: 2px;
    }
    element {
      padding: 9px 14px;
      border-radius: 8px;
    }
    element-text {
      background-color: transparent;
      text-color: #ffffff;
      font: "JetBrainsMono Nerd Font 12";
      vertical-align: 0.5;
    }
    /* Ligne de séparation : grisée et non sélectionnable visuellement */
    element normal urgent {
      background-color: transparent;
    }
    element-text normal urgent {
      text-color: rgba(255, 255, 255, 0.25);
      font: "JetBrainsMono Nerd Font 10";
    }
    element selected {
      background-color: rgba(255, 255, 255, 0.08);
      border: 1px;
      border-color: rgba(255, 255, 255, 0.3);
    }
    element-text selected {
      text-color: #ffffff;
    }
    /* Bouton Appliquer : mis en évidence */
    element active {
      background-color: rgba(74, 222, 128, 0.12);
      border: 1px;
      border-color: rgba(74, 222, 128, 0.5);
      border-radius: 8px;
    }
    element-text active {
      text-color: #4ade80;
    }
    element selected active {
      background-color: rgba(74, 222, 128, 0.25);
      border: 2px;
      border-color: #4ade80;
    }
    element-text selected active {
      text-color: #4ade80;
    }
  '';

  # ==========================================================================
  # SCRIPT MENU RÉSEAU
  # ==========================================================================
  home.packages = [ network-menu ];
}
