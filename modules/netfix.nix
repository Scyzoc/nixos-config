{ pkgs, ... }:

let
  # Commande `netfix` : diagnostic réseau par couches + réparation automatique.
  # Usage : netfix        → diagnostique puis répare (escalade progressive)
  #         netfix -n     → diagnostic seul, ne touche à rien
  # Journal : ~/.cache/netfix.log
  nmcli      = "${pkgs.networkmanager}/bin/nmcli";
  ip         = "${pkgs.iproute2}/bin/ip";
  curl       = "${pkgs.curl}/bin/curl";
  getent     = "${pkgs.getent}/bin/getent";
  dig        = "${pkgs.dnsutils}/bin/dig";
  rfkill     = "${pkgs.util-linux}/bin/rfkill";
  resolvconf = "${pkgs.openresolv}/bin/resolvconf";
  awk        = "${pkgs.gawk}/bin/awk";
  timeout    = "${pkgs.coreutils}/bin/timeout";
  notify     = "${pkgs.libnotify}/bin/notify-send";
  xdgopen    = "${pkgs.xdg-utils}/bin/xdg-open";

  netfix = pkgs.writeShellScriptBin "netfix" ''
      set -uo pipefail
      # Sorties nmcli/rfkill en anglais (parsing stable), UTF-8 pour les accents
      export LC_ALL=C.UTF-8

      R='\e[0m'; BOLD='\e[1m'; DIM='\e[2m'
      RED='\e[38;5;203m'; YELLOW='\e[38;5;221m'; GREEN='\e[38;5;114m'; BLUE='\e[38;5;111m'; GRAY='\e[38;5;245m'

      # Wrappers setuid NixOS + chemins exacts des règles sudo NOPASSWD (configuration.nix)
      SUDO=/run/wrappers/bin/sudo
      PING=${pkgs.iputils}/bin/ping
      SYSTEMCTL=/run/current-system/sw/bin/systemctl
      WGQUICK=/run/current-system/sw/bin/wg-quick
      MODPROBE=/run/current-system/sw/bin/modprobe

      LOG="$HOME/.cache/netfix.log"
      mkdir -p "$HOME/.cache"

      DIAG_ONLY=0
      case "''${1:-}" in
        -n|--diag) DIAG_ONLY=1 ;;
        -h|--help)
          echo "Usage : netfix [-n]"
          echo "  (sans option)  diagnostic + réparation automatique"
          echo "  -n, --diag     diagnostic seul"
          exit 0 ;;
        "") ;;
        *) echo "Option inconnue : $1 (voir netfix -h)"; exit 2 ;;
      esac

      # ── Affichage ─────────────────────────────────────────────
      log()   { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
      title() { printf "\n$BLUE$BOLD==> %s$R\n" "$1"; }
      # Padding en caractères (printf %-Ns compte les octets → décalé avec les accents)
      lbl()   { printf '%s%*s' "$1" $(( 12 - ''${#1} )) ""; }
      ok()    { printf "  $GREEN✔$R  %s $GRAY%s$R\n"   "$(lbl "$1")" "$2"; log "OK   $1 : $2"; }
      warn()  { printf "  $YELLOW!$R  %s $YELLOW%s$R\n" "$(lbl "$1")" "$2"; log "WARN $1 : $2"; }
      ko()    { printf "  $RED✘$R  %s $RED%s$R\n"     "$(lbl "$1")" "$2"; log "KO   $1 : $2"; }
      act()   { printf "  $BLUE➜$R  %s\n" "$1"; log "FIX  $1"; }
      hint()  { printf "     $GRAY%s$R\n" "$1"; }

      # Attend qu'un device physique soit connecté (max $1 s)
      wait_link() {
        local i
        for i in $(seq 1 "''${1:-20}"); do
          if phys_connected >/dev/null; then sleep 2; return 0; fi
          sleep 1
        done
        return 1
      }

      is_vpn_dev() { case "$1" in tap*|tun*|wg*|proton*) return 0 ;; *) return 1 ;; esac; }

      # Premier device physique (ethernet/wifi) à l'état « connected »
      phys_connected() {
        local d t s
        while IFS=: read -r d t s; do
          [ -e "/sys/class/net/$d/device" ] || continue
          case "$t" in ethernet|wifi) ;; *) continue ;; esac
          [ "$s" = "connected" ] && { echo "$d"; return 0; }
        done < <(${nmcli} -t -f DEVICE,TYPE,STATE device 2>/dev/null)
        return 1
      }

      ping_ok() { $PING -c 2 -W 2 -q "$1" >/dev/null 2>&1; }

      # Serveur DNS qui répond vraiment (interrogé en direct, sans la libc)
      dns_probe() {
        ${dig} +time=2 +tries=2 +short "@$1" nixos.org A 2>/dev/null | grep -qE '^[0-9.]+$'
      }

      # Internet sans DNS : ICMP, puis TCP 443 (certains réseaux bloquent le ping)
      net_ok() {
        ping_ok 1.1.1.1 || ping_ok 9.9.9.9 || \
          ${curl} -s -m 5 -o /dev/null https://1.1.1.1 2>/dev/null || \
          ${curl} -s -m 5 -o /dev/null http://9.9.9.9 2>/dev/null
      }

      # Passerelle : ping, sinon entrée ARP valide (box qui ignore l'ICMP)
      gw_ok() {
        ping_ok "$1" && return 0
        ${ip} neigh show "$1" 2>/dev/null | grep -qE 'lladdr .* (REACHABLE|STALE|DELAY|PROBE)'
      }

      # ── Contexte : interfaces, route effective, passerelle ────
      detect() {
        ETH=""; WIFI=""
        local d t
        while IFS=: read -r d t; do
          [ -e "/sys/class/net/$d/device" ] || continue   # ignore docker0, vmnet*, veth*, tap*
          case "$t" in
            ethernet) [ -z "$ETH" ] && ETH=$d ;;
            wifi)     [ -z "$WIFI" ] && WIFI=$d ;;
          esac
        done < <(${nmcli} -t -f DEVICE,TYPE device 2>/dev/null)

        local r; r=$(${ip} -4 route get 1.1.1.1 2>/dev/null | head -1)
        DEV=$(${awk} '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$r")
        GW=$(${awk}  '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<<"$r")
        LDEV=$(phys_connected || true)
        CON=""
        [ -n "$LDEV" ] && CON=$(${nmcli} -g GENERAL.CONNECTION device show "$LDEV" 2>/dev/null)
      }

      # ── Diagnostic par couches : s'arrête à la première panne ─
      # Remplit FAIL avec le nom de la couche en panne (vide = tout va bien)
      diagnose() {
        FAIL=""
        detect

        # 1. NetworkManager
        if ! $SYSTEMCTL is-active --quiet NetworkManager; then
          ko "NetworkMgr" "service arrêté"; FAIL=nm; return
        fi
        ok "NetworkMgr" "actif"

        # 2. Radio Wi-Fi (info, bloquant seulement si aucun lien)
        RADIO_HARD=0
        if [ -n "$WIFI" ]; then
          if ${rfkill} -n -o TYPE,HARD list 2>/dev/null | ${awk} '$1=="wlan" && $2=="blocked" {f=1} END{exit !f}'; then
            RADIO_HARD=1; warn "Radio Wi-Fi" "bloquée matériellement (touche avion ?)"
          elif [ "$(${nmcli} radio wifi)" != "enabled" ] || \
               ${rfkill} -n -o TYPE,SOFT list 2>/dev/null | ${awk} '$1=="wlan" && $2=="blocked" {f=1} END{exit !f}'; then
            warn "Radio Wi-Fi" "désactivée"
          else
            ok "Radio Wi-Fi" "activée ($WIFI)"
          fi
        fi

        # 3. Lien physique
        if [ -z "$LDEV" ]; then
          local carrier=0
          [ -n "$ETH" ] && carrier=$(cat "/sys/class/net/$ETH/carrier" 2>/dev/null || echo 0)
          if [ "$carrier" = "1" ]; then
            ko "Lien" "câble branché ($ETH) mais non connecté"
          else
            ko "Lien" "aucune interface connectée"
          fi
          FAIL=lien; return
        fi
        ok "Lien" "$LDEV → $CON"

        # 4. Adresse IPv4
        local addr; addr=$(${ip} -4 -o addr show dev "$LDEV" scope global 2>/dev/null | ${awk} '{print $4; exit}')
        if [ -z "$addr" ] || [[ "$addr" == 169.254.* ]]; then
          ko "Adresse IP" "pas de bail DHCP sur $LDEV"; FAIL=ip; return
        fi
        ok "Adresse IP" "$addr"

        # 5. Route par défaut
        if [ -z "$DEV" ]; then
          ko "Route" "aucune route par défaut"; FAIL=route; return
        fi
        if is_vpn_dev "$DEV"; then
          ok "Route" "via VPN ($DEV)"
        else
          ok "Route" "via $GW ($DEV)"
        fi

        # 6. Conflit de sous-réseau (docker0 / vmnet qui capte la passerelle)
        if [ -n "$GW" ]; then
          local gwdev
          gwdev=$(${ip} -4 route get "$GW" 2>/dev/null | ${awk} '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
          case "$gwdev" in
            docker*|br-*|vmnet*|virbr*)
              ko "Sous-réseau" "passerelle $GW captée par $gwdev"; CONFLICT_DEV=$gwdev; FAIL=conflit; return ;;
          esac
        fi

        # 7. Internet (IP brute, sans DNS)
        if net_ok; then
          ok "Internet" "joignable (1.1.1.1 / 9.9.9.9)"
        else
          if is_vpn_dev "$DEV"; then
            ko "Internet" "injoignable — le VPN ($DEV) ne route pas"; FAIL=vpn; return
          fi
          if [ -n "$GW" ] && ! gw_ok "$GW"; then
            ko "Passerelle" "$GW ne répond pas"; FAIL=passerelle; return
          fi
          ok "Passerelle" "$GW répond"
          if [ "$(${nmcli} networking connectivity check 2>/dev/null)" = "portal" ]; then
            ko "Internet" "portail captif (connexion à valider)"; FAIL=portail; return
          fi
          ko "Internet" "la box/le partage ne sort pas sur internet"; FAIL=amont; return
        fi

        # 8. DNS : chaque serveur (la libc n'en lit que 3), puis résolution réelle
        local ns first="" alive="" dead=""
        for ns in $(${awk} '/^nameserver/ && n++ < 3 {print $2}' /etc/resolv.conf); do
          [ -z "$first" ] && first=$ns
          if dns_probe "$ns"; then alive="$alive$ns "; else dead="$dead$ns "; fi
        done
        if [ -z "$alive" ]; then
          ko "DNS" "aucun serveur ne répond (''${dead:-resolv.conf vide})"; FAIL=dns; return
        fi
        # Timeout large : la libc peut devoir passer au serveur suivant
        if ! ${timeout} 12 ${getent} ahosts nixos.org >/dev/null 2>&1 && \
           ! ${timeout} 12 ${getent} ahosts cloudflare.com >/dev/null 2>&1; then
          ko "DNS" "résolution système en échec (serveurs OK : $alive)"; FAIL=dns; return
        fi
        # Premier serveur muet = chaque requête attend le secours → navigation lente
        if [ "$first" != "''${alive%% *}" ]; then
          ko "DNS" "$first ne répond pas (secours lent via $alive)"; FAIL=dns; return
        fi
        if [ -n "$dead" ]; then
          warn "DNS" "OK via $alive— muets : $dead"
        else
          ok "DNS" "résolution OK ($alive)"
        fi

        # 9. Portail captif (HTTP intercepté)
        case "$(${nmcli} networking connectivity check 2>/dev/null)" in
          full)    ok "Portail" "aucun" ;;
          portal)  ko "Portail" "portail captif détecté"; FAIL=portail; return ;;
          *)       warn "Portail" "vérification NM non concluante" ;;
        esac

        # 10. HTTPS (TLS + horloge)
        if ${curl} -sS -m 8 -o /dev/null https://cache.nixos.org/nix-cache-info 2>/dev/null; then
          ok "HTTPS" "cache.nixos.org OK"
        else
          if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" != "yes" ]; then
            ko "HTTPS" "échec TLS — horloge non synchronisée"; FAIL=horloge; return
          fi
          ko "HTTPS" "échec (pare-feu, proxy ou filtrage)"; FAIL=https; return
        fi

        # 11. Qualité (informatif, jamais bloquant)
        local stats loss avg
        stats=$($PING -c 5 -i 0.3 -W 2 1.1.1.1 2>/dev/null)
        loss=$(grep -oP '\d+(?=% packet loss)' <<<"$stats")
        avg=$(grep -oP 'rtt min/avg/max/mdev = [0-9.]+/\K[0-9.]+' <<<"$stats")
        if [ "''${loss:-100}" -gt 0 ]; then
          warn "Qualité" "$loss% de perte, ''${avg:-?} ms"
        elif [ "''${avg%.*}" -gt 150 ] 2>/dev/null; then
          warn "Qualité" "latence élevée : $avg ms"
        else
          ok "Qualité" "$avg ms, 0% de perte"
        fi
        if [ "$LDEV" = "$WIFI" ]; then
          local sig; sig=$(${nmcli} -t -f IN-USE,SIGNAL device wifi list --rescan no 2>/dev/null | ${awk} -F: '$1=="*"{print $2; exit}')
          if [ -n "$sig" ] && [ "$sig" -lt 35 ]; then
            warn "Signal" "$sig% — faible, rapproche-toi du point d'accès"
          elif [ -n "$sig" ]; then
            ok "Signal" "$sig%"
          fi
        fi
      }

      # ── Réparations ───────────────────────────────────────────
      declare -A TRIES

      # Nettoie les DNS exclusifs AdGuard laissés par un VPN maison mort
      clean_vpn_dns() {
        $SYSTEMCTL is-active --quiet openvpn-maison && return 1
        local IF found=1
        for IF in $(${resolvconf} -i 2>/dev/null); do
          case "$IF" in
            tap*.ovpn) act "Retrait du DNS VPN orphelin ($IF)"; $SUDO ${resolvconf} -d "$IF"; found=0 ;;
          esac
        done
        return $found
      }

      # Remplace les DNS du réseau (v4 + v6, ex. relais iPhone muet) par des
      # résolveurs publics sur la connexion active — sans sudo, jusqu'à la reconnexion
      DNS_OVERRIDE=0
      override_dns() {
        local err
        act "DNS de secours sur $LDEV : 1.1.1.1 / 9.9.9.9 (jusqu'à la prochaine reconnexion)"
        if ! err=$(${nmcli} device modify "$LDEV" ipv4.dns "1.1.1.1 9.9.9.9" \
                     ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes 2>&1 >/dev/null); then
          ko "Réparation" "nmcli refuse le DNS de secours : ''${err:-erreur inconnue}"
          return 1
        fi
        DNS_OVERRIDE=1
      }

      stop_vpns() {
        local stopped=1
        if $SYSTEMCTL is-active --quiet openvpn-maison; then
          act "Arrêt du VPN maison"; $SUDO $SYSTEMCTL stop openvpn-maison; stopped=0
        fi
        if ${ip} link show proton >/dev/null 2>&1; then
          act "Arrêt du VPN ProtonVPN (wg-quick)"; $SUDO $WGQUICK down proton; stopped=0
        fi
        local name type
        while IFS=: read -r name type; do
          case "$type" in vpn|wireguard)
            act "Coupure de la connexion NM « $name »"; ${nmcli} connection down "$name" >/dev/null 2>&1; stopped=0 ;;
          esac
        done < <(${nmcli} -t -f NAME,TYPE connection show --active 2>/dev/null)
        clean_vpn_dns || true
        return $stopped
      }

      restart_nm() {
        act "Redémarrage de NetworkManager"
        $SUDO $SYSTEMCTL restart NetworkManager
        wait_link 25
      }

      reload_drivers() {
        local did=1 drv
        if [ -n "$WIFI" ]; then
          drv=$(basename "$(readlink "/sys/class/net/$WIFI/device/driver")" 2>/dev/null)
          if [ -n "$drv" ]; then
            act "Rechargement du pilote Wi-Fi ($drv)"
            $SUDO $MODPROBE -r "$drv" && sleep 2 && $SUDO $MODPROBE "$drv"; did=0
          fi
        fi
        if [ -n "$ETH" ] && $SYSTEMCTL cat wake-ethernet >/dev/null 2>&1; then
          act "Réveil forcé du port Ethernet (wake-ethernet)"
          $SUDO $SYSTEMCTL restart wake-ethernet; did=0
        fi
        [ $did -eq 0 ] && wait_link 30
        return $did
      }

      # Échelle commune aux pannes de connexion (lien / IP / route / passerelle)
      fix_connection() {
        TRIES[conn]=$(( ''${TRIES[conn]:-0} + 1 ))
        case "''${TRIES[conn]}" in
          1)
            if [ -n "$WIFI" ]; then
              if [ "$RADIO_HARD" = "1" ]; then
                act "Radio bloquée matériellement : impossible à débloquer par logiciel"
                hint "Désactive le mode avion (touche Fn) puis relance netfix."
              else
                ${rfkill} unblock wlan 2>/dev/null || $SUDO ${rfkill} unblock wlan
                [ "$(${nmcli} radio wifi)" = "enabled" ] || { act "Activation de la radio Wi-Fi"; ${nmcli} radio wifi on; sleep 3; }
              fi
            fi
            if [ -n "$LDEV" ]; then
              act "Reconnexion de $LDEV (nouveau bail DHCP)"
              ${nmcli} device disconnect "$LDEV" >/dev/null 2>&1
              sleep 1
              ${nmcli} device connect "$LDEV" >/dev/null 2>&1
            else
              if [ -n "$ETH" ] && [ "$(cat "/sys/class/net/$ETH/carrier" 2>/dev/null)" = "1" ]; then
                act "Connexion Ethernet ($ETH)"; ${nmcli} device connect "$ETH" >/dev/null 2>&1
              fi
              if [ -n "$WIFI" ] && [ "$RADIO_HARD" = "0" ]; then
                act "Scan Wi-Fi + connexion au meilleur réseau connu"
                ${nmcli} device wifi rescan >/dev/null 2>&1; sleep 4
                ${nmcli} device connect "$WIFI" >/dev/null 2>&1
              fi
            fi
            wait_link 20 ;;
          2) restart_nm ;;
          3) reload_drivers || return 1 ;;
          *) return 1 ;;
        esac
        return 0
      }

      fix() {
        TRIES[$1]=$(( ''${TRIES[$1]:-0} + 1 ))
        local n=''${TRIES[$1]}
        case "$1" in
          nm)
            [ "$n" -gt 1 ] && return 1
            act "Démarrage de NetworkManager"
            $SUDO $SYSTEMCTL restart NetworkManager; wait_link 25 ;;
          lien|ip|route|passerelle)
            fix_connection ;;
          conflit)
            [ "$n" -gt 1 ] && return 1
            act "Désactivation temporaire de $CONFLICT_DEV (chevauche le réseau actuel)"
            hint "Il reviendra au prochain démarrage de docker / vmware."
            $SUDO ${ip} link set "$CONFLICT_DEV" down ;;
          vpn)
            [ "$n" -gt 1 ] && return 1
            stop_vpns || return 1
            sleep 3 ;;
          amont)
            # Une seule reconnexion (parfois la box redonne un bail valide)
            [ "$n" -gt 1 ] && return 1
            fix_connection ;;
          dns)
            # 1. DNS VPN orphelin, sinon DNS de secours ; 2. secours si pas encore tenté
            case "$n" in
              1) clean_vpn_dns || override_dns || return 1 ;;
              2) [ "$DNS_OVERRIDE" = 1 ] && return 1; override_dns || return 1 ;;
              *) return 1 ;;
            esac
            # NM → resolvconf → redémarrage de nscd : laisse le temps de s'appliquer
            sleep 3 ;;
          portail)
            [ "$n" -gt 1 ] && return 1
            act "Ouverture du portail captif dans le navigateur"
            ${xdgopen} "http://neverssl.com" >/dev/null 2>&1 &
            hint "Valide la connexion dans le navigateur, puis appuie sur Entrée."
            read -r _ ;;
          horloge)
            [ "$n" -gt 1 ] && return 1
            act "Resynchronisation de l'horloge (systemd-timesyncd)"
            $SUDO $SYSTEMCTL restart systemd-timesyncd; sleep 5 ;;
          *) return 1 ;;
        esac
        return 0
      }

      advice() {
        case "$1" in
          lien|ip|route|passerelle)
            hint "Pistes : redémarrer la box / le partage de connexion, changer de réseau,"
            hint "vérifier le câble, ou redémarrer le PC (pilote bloqué)." ;;
          amont)   hint "Le PC est bien connecté, c'est la box ou l'opérateur qui ne sort pas. Redémarre la box." ;;
          dns)
            hint "Le DNS du réseau est muet. Partage iPhone : coupe puis réactive le Partage de connexion."
            hint "Test direct : dig @1.1.1.1 nixos.org" ;;
          https)   hint "Réseau filtré (école, entreprise ?) ou proxy obligatoire." ;;
          vpn)     hint "Le VPN est coupé mais la route reste : vérifie « ip route »." ;;
          conflit) hint "Change le sous-réseau docker (daemon.json « bip ») ou vmware." ;;
          nm)      hint "Consulte : journalctl -u NetworkManager -b" ;;
        esac
      }

      # ── Boucle principale ─────────────────────────────────────
      log "──── netfix $([ $DIAG_ONLY -eq 1 ] && echo '(diagnostic)' || echo '(réparation)')"
      FIXED=0
      for pass in 1 2 3 4 5 6; do
        title "Diagnostic réseau$([ "$pass" -gt 1 ] && echo " (passe $pass)")"
        diagnose
        [ -z "$FAIL" ] && break
        [ $DIAG_ONLY -eq 1 ] && break
        title "Réparation : $FAIL"
        if ! fix "$FAIL"; then
          ko "Réparation" "plus de solution automatique pour « $FAIL »"
          break
        fi
        FIXED=1
      done

      echo
      if [ -z "$FAIL" ]; then
        if [ $FIXED -eq 1 ]; then
          printf "$GREEN$BOLD  Réseau réparé et fonctionnel.$R\n"
          ${notify} -i network-wireless "netfix" "Réseau réparé" 2>/dev/null || true
        else
          printf "$GREEN$BOLD  Réseau fonctionnel, rien à réparer.$R\n"
        fi
        log "RESULTAT OK"
      else
        printf "$RED$BOLD  Panne non résolue : %s$R\n" "$FAIL"
        [ $DIAG_ONLY -eq 1 ] && hint "Lance « netfix » (sans -n) pour tenter la réparation." || advice "$FAIL"
        [ $DIAG_ONLY -eq 0 ] && ${notify} -u critical -i network-error "netfix" "Panne réseau non résolue : $FAIL" 2>/dev/null || true
        log "RESULTAT KO $FAIL"
      fi
      printf "$DIM$GRAY  Journal : %s$R\n\n" "$LOG"
      [ -z "$FAIL" ]
  '';

  # Lancement depuis le menu : garde la fenêtre ouverte pour lire le résultat
  netfix-app = pkgs.writeShellScript "netfix-app" ''
    ${netfix}/bin/netfix
    printf '\n  Appuie sur Entrée pour fermer…'
    read -r _
  '';
in
{
  # Entrée du menu applications (fenêtre kitty flottante, règles dans home.nix)
  xdg.desktopEntries.netfix = {
    name = "Netfix";
    genericName = "Réparation réseau";
    comment = "Diagnostique et répare la connexion internet";
    exec = "${pkgs.kitty}/bin/kitty --class netfix --title Netfix -e ${netfix-app}";
    icon = "network-wireless";
    terminal = false;
    type = "Application";
    categories = [ "Network" "System" ];
    settings.Keywords = "réseau;wifi;internet;dns;réparer;connexion;network;";
  };

  # Même fenêtre que le menu applications, lançable depuis la barre (menu Wi-Fi)
  home.packages = [
    netfix
    (pkgs.writeShellScriptBin "netfix-window" ''
      exec ${pkgs.kitty}/bin/kitty --class netfix --title Netfix -e ${netfix-app}
    '')
  ];
}
