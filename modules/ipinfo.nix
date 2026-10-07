{ config, pkgs, lib, ... }:

let
  monip = pkgs.writeShellScriptBin "monip" ''
    IP="${pkgs.iproute2}/bin/ip"
    CURL="${pkgs.curl}/bin/curl"
    JQ="${pkgs.jq}/bin/jq"

    # Couleurs
    B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
    C=$'\e[38;5;110m'   # cyan doux  (titres)
    G=$'\e[38;5;114m'   # vert       (actif)
    Y=$'\e[38;5;179m'   # jaune      (adresses)
    M=$'\e[38;5;140m'   # violet     (public)
    X=$'\e[38;5;131m'   # rouge      (down)

    W=62
    line() { printf "''${D}%s''${R}\n" "$(printf '─%.0s' $(seq 1 $W))"; }

    icon_for() {
      case "$1" in
        lo)          printf '󰑓' ;;
        e*|en*)      printf '󰈀' ;;
        w*|wl*)      printf '󰖩' ;;
        tun*|wg*|ppp*|proton*|nordlynx) printf '󰦝' ;;
        docker*|br-*|veth*|virbr*)      printf '󰡨' ;;
        *)           printf '󰛳' ;;
      esac
    }

    PING="${pkgs.iputils}/bin/ping"
    GETENT="${pkgs.getent}/bin/getent"

    # IP publique mise en cache (rafraîchie toutes les 30 s max)
    PUB=""
    PUB_TS=0
    WHY=""; BLOCK=""; FIX=()
    refresh_pub() {
      NOW=$(date +%s)
      if [ -z "$PUB" ] || [ $((NOW - PUB_TS)) -ge 30 ]; then
        PUB=""; RC=0
        for URL in https://ifconfig.me https://api.ipify.org https://icanhazip.com; do
          PUB=$($CURL -sf --max-time 4 "$URL" 2>/dev/null)
          RC=$?
          PUB=$(printf '%s' "$PUB" | tr -d '[:space:]')
          [ -n "$PUB" ] && break
        done
        PUB_TS=$NOW
        WHY=""; BLOCK=""; FIX=()
        [ -z "$PUB" ] && diagnose "$RC"
      fi
    }

    # Diagnostic en cascade : trouve la première couche qui casse
    diagnose() {
      CURL_RC=$1

      # 1. Interface connectée avec une IPv4 ?
      if [ -z "$($IP -4 -o addr show scope global up)" ]; then
        WHY="aucune interface réseau n'a d'adresse IPv4"
        BLOCK="Wi-Fi / Ethernet déconnecté ou DHCP sans réponse"
        FIX=("vérifier le câble ou se connecter au Wi-Fi (nmcli device wifi connect <SSID>)"
             "relancer la connexion : nmcli networking off && nmcli networking on"
             "rfkill list  → vérifier que le Wi-Fi n'est pas bloqué")
        return
      fi

      # 2. Route par défaut ?
      GW=$($IP -4 route show default | awk '{print $3; exit}')
      DEV=$($IP -4 route show default | awk '{print $5; exit}')
      if [ -z "$GW" ] && [ -z "$DEV" ]; then
        WHY="pas de route par défaut (aucune passerelle)"
        BLOCK="le DHCP n'a pas fourni de passerelle, ou un VPN a supprimé la route"
        FIX=("reconnecter l'interface : nmcli device reapply <interface>"
             "si VPN : le couper puis le relancer"
             "ip route  → vérifier la table de routage")
        return
      fi

      # 3. Passerelle joignable ? (sauf tunnel VPN point-à-point sans IP de passerelle)
      if [ -n "$GW" ] && ! $PING -c1 -W1 "$GW" >/dev/null 2>&1 \
         && ! $IP neigh show "$GW" | grep -qE 'REACHABLE|STALE|DELAY'; then
        WHY="la passerelle $GW ne répond pas"
        BLOCK="box / routeur injoignable via $DEV (signal faible, box figée, mauvais réseau)"
        FIX=("vérifier le signal Wi-Fi ou le câble"
             "redémarrer la box / le routeur"
             "se reconnecter : nmcli device disconnect $DEV && nmcli device connect $DEV")
        return
      fi

      # 4. Internet joignable par IP (sans DNS) ?
      if ! $PING -c1 -W2 1.1.1.1 >/dev/null 2>&1 && ! $PING -c1 -W2 8.8.8.8 >/dev/null 2>&1 \
         && ! $CURL -s --max-time 3 -o /dev/null http://1.1.1.1 2>/dev/null; then
        case "$DEV" in
          tun*|wg*|ppp*|proton*|nordlynx)
            WHY="le tunnel VPN ($DEV) ne transmet rien"
            BLOCK="serveur VPN injoignable ou tunnel mort"
            FIX=("couper le VPN pour tester la connexion directe"
                 "changer de serveur VPN / relancer le client") ;;
          *)
            WHY="la box répond mais Internet est coupé"
            BLOCK="liaison box ↔ FAI (fibre/ADSL/4G) ou pare-feu en amont"
            FIX=("regarder les voyants de la box (synchro / Internet)"
                 "redémarrer la box, sinon consulter l'état du réseau du FAI"
                 "réseau d'entreprise/école : le trafic sortant est peut-être filtré") ;;
        esac
        return
      fi

      # 5. DNS ?
      if ! $GETENT hosts ifconfig.me >/dev/null 2>&1; then
        WHY="Internet OK mais la résolution DNS échoue"
        BLOCK="serveur DNS injoignable ou mal configuré ($(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf))"
        FIX=("resolvectl status  → voir les serveurs DNS utilisés"
             "forcer un DNS : nmcli connection modify <con> ipv4.dns 1.1.1.1 && nmcli connection up <con>"
             "si VPN : son DNS peut être en panne, le couper")
        return
      fi

      # 6. Portail captif ?
      CODE=$($CURL -s --max-time 4 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204 2>/dev/null)
      if [ -n "$CODE" ] && [ "$CODE" != "204" ] && [ "$CODE" != "000" ]; then
        WHY="un portail captif intercepte le trafic (HTTP $CODE)"
        BLOCK="réseau public (hôtel, gare, école) qui exige une connexion web"
        FIX=("ouvrir un navigateur sur http://neverssl.com et accepter / s'identifier")
        return
      fi

      # 7. HTTPS / service
      case "$CURL_RC" in
        28) WHY="délai dépassé en HTTPS"
            BLOCK="connexion très lente ou HTTPS filtré"
            FIX=("retester dans quelques secondes"
                 "tester : curl -v https://ifconfig.me") ;;
        35|51|58|60)
            WHY="échec TLS/certificat (code curl $CURL_RC)"
            BLOCK="horloge système fausse, proxy/antivirus qui intercepte le HTTPS"
            FIX=("vérifier l'heure : timedatectl (NTP synchronized: yes)"
                 "désactiver le proxy éventuel (echo \$https_proxy)") ;;
        7)  WHY="connexion HTTPS refusée"
            BLOCK="pare-feu ou proxy qui bloque le port 443 sortant"
            FIX=("tester : curl -v https://ifconfig.me"
                 "vérifier le pare-feu du réseau / la variable https_proxy") ;;
        *)  WHY="les services d'IP publique ne répondent pas (code curl $CURL_RC)"
            BLOCK="ifconfig.me, ipify et icanhazip bloqués ou en panne"
            FIX=("tester à la main : curl -v https://ifconfig.me"
                 "réessayer plus tard") ;;
      esac
    }

    render() {
      printf "\n''${B}''${C}  󰩠  Aperçu réseau''${R}   ''${D}%s''${R}\n" "$(date '+%d/%m/%Y %H:%M:%S')"
      line

      # ── Interfaces ──────────────────────────────────────────────
      $IP -j addr show | $JQ -r '
        .[] | [
          .ifname,
          .operstate,
          (.address // "-"),
          ([.addr_info[]? | select(.family=="inet")  | "\(.local)/\(.prefixlen)"] | join(" ")),
          ([.addr_info[]? | select(.family=="inet6") | select(.scope=="global") | "\(.local)/\(.prefixlen)"] | join(" "))
        ] | @tsv' |
      while IFS=$'\t' read -r NAME STATE MAC V4 V6; do
        ICON=$(icon_for "$NAME")

        if [ "$STATE" = "UP" ] || [ "$NAME" = "lo" ]; then
          SC="$G"; SYM="●"
        elif [ -n "$V4" ]; then
          SC="$Y"; SYM="●"
        else
          SC="$X"; SYM="○"
        fi

        # Masquer les interfaces down et sans adresse
        [ "$SC" = "$X" ] && [ -z "$V4" ] && [ -z "$V6" ] && continue

        printf "\n  ''${SC}%s''${R} ''${B}%s %-12s''${R} ''${D}%s''${R}\n" "$SYM" "$ICON" "$NAME" "$STATE"
        [ -n "$V4" ] && for A in $V4; do
          printf "      ''${D}IPv4''${R}  ''${Y}%s''${R}\n" "$A"
        done
        [ -n "$V6" ] && for A in $V6; do
          printf "      ''${D}IPv6''${R}  ''${Y}%s''${R}\n" "$A"
        done
        [ "$MAC" != "-" ] && [ "$NAME" != "lo" ] && \
          printf "      ''${D}MAC   %s''${R}\n" "$MAC"
      done

      # ── Passerelle ──────────────────────────────────────────────
      GW=$($IP -4 route show default | awk '{print $3; exit}')
      DEV=$($IP -4 route show default | awk '{print $5; exit}')
      if [ -n "$GW" ]; then
        printf "\n"; line
        printf "  ''${C}󰑩  Passerelle''${R}  ''${Y}%s''${R} ''${D}via %s''${R}\n" "$GW" "$DEV"
      fi

      # ── IP publique ─────────────────────────────────────────────
      line
      if [ -n "$PUB" ]; then
        printf "  ''${M}󰖟  IP publique''${R}  ''${B}''${M}%s''${R}\n" "$PUB"
      else
        printf "  ''${X}󰖪  IP publique   indisponible''${R}\n"
        printf "      ''${D}Pourquoi''${R}  %s\n" "$WHY"
        printf "      ''${D}Bloque  ''${R}  ''${Y}%s''${R}\n" "$BLOCK"
        printf "      ''${D}Solution''${R}\n"
        for F in "''${FIX[@]}"; do
          printf "        ''${G}›''${R} %s\n" "$F"
        done
      fi
      line
    }

    # Mode ponctuel : monip --once
    if [ "$1" = "--once" ] || [ "$1" = "-1" ]; then
      refresh_pub
      render
      printf "\n"
      exit 0
    fi

    # Mode live : rafraîchi toutes les 2 s, q ou Ctrl-C pour quitter
    cleanup() { printf '\e[?25h\e[?1049l'; exit 0; }
    trap cleanup INT TERM

    printf '\e[?1049h\e[?25l'   # écran alternatif + curseur caché
    while true; do
      refresh_pub
      OUT=$(render)
      printf '\e[H\e[J%s\n\n  %s\n' "$OUT" "''${D}q pour quitter · maj toutes les 2 s''${R}"
      if [ -t 0 ]; then
        read -rsn1 -t 2 KEY && [ "$KEY" = "q" ] && cleanup
      else
        sleep 2
      fi
    done
  '';

  # Commande `ipinfo` : toutes les infos publiques sur une adresse IP (ou un nom d'hôte).
  # Sources sans clé API : ip-api.com (géoloc, FAI, drapeaux proxy/hébergeur),
  # ipwho.is (secours), RDAP (propriétaire du bloc, abuse), Shodan InternetDB
  # (ports ouverts, CVE), DNS inverse et listes noires DNSBL.
  # Usage : ipinfo                → sa propre IP publique
  #         ipinfo 8.8.8.8        → une IP
  #         ipinfo example.com    → résout le nom puis analyse l'IP
  #         ipinfo --json <ip>    → JSON brut fusionné
  ipinfo = pkgs.writeShellScriptBin "ipinfo" ''
    set -u
    export LC_ALL=C.UTF-8
    CURL="${pkgs.curl}/bin/curl"
    JQ="${pkgs.jq}/bin/jq"
    DIG="${pkgs.dnsutils}/bin/dig"

    B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
    C=$'\e[38;5;110m'; G=$'\e[38;5;114m'; Y=$'\e[38;5;179m'
    M=$'\e[38;5;140m'; X=$'\e[38;5;131m'

    usage() {
      printf "Usage : ipinfo [--json] [IP | nom d'hôte]\n"
      printf "  sans argument : analyse ta propre IP publique\n"
    }

    JSON=0; CIBLE=""
    for A in "$@"; do
      case "$A" in
        -h|--help) usage; exit 0 ;;
        -j|--json) JSON=1 ;;
        -*) printf "Option inconnue : %s\n" "$A" >&2; usage >&2; exit 2 ;;
        *) CIBLE="$A" ;;
      esac
    done

    is_v4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
    is_v6() { [[ "$1" == *:* && "$1" =~ ^[0-9a-fA-F:.]+$ ]]; }

    # ── Cible ───────────────────────────────────────────────────
    HOTE=""
    if [ -z "$CIBLE" ]; then
      IPADDR=$($CURL -sf --max-time 5 https://api.ipify.org || $CURL -sf --max-time 5 https://ifconfig.me)
      IPADDR=$(printf '%s' "$IPADDR" | tr -d '[:space:]')
      [ -z "$IPADDR" ] && { printf "''${X}Impossible de récupérer ton IP publique (pas d'Internet ?)''${R}\n" >&2; exit 1; }
    elif is_v4 "$CIBLE" || is_v6 "$CIBLE"; then
      IPADDR="$CIBLE"
    else
      HOTE="$CIBLE"
      IPADDR=$($DIG +short +time=3 +tries=1 A "$HOTE" | grep -E '^[0-9.]+$' | head -1)
      [ -z "$IPADDR" ] && IPADDR=$($DIG +short +time=3 +tries=1 AAAA "$HOTE" | grep ':' | head -1)
      [ -z "$IPADDR" ] && { printf "''${X}« %s » : ni une IP, ni un nom résolvable''${R}\n" "$HOTE" >&2; exit 1; }
    fi

    # Adresses privées / réservées : rien à chercher sur Internet
    PRIVE=""
    if is_v4 "$IPADDR"; then
      IFS=. read -r O1 O2 O3 O4 <<< "$IPADDR"
      for O in "$O1" "$O2" "$O3" "$O4"; do
        [ "$O" -gt 255 ] && { printf "''${X}IPv4 invalide : %s''${R}\n" "$IPADDR" >&2; exit 2; }
      done
      if [ "$O1" -eq 10 ] || [ "$O1" -eq 127 ] || [ "$O1" -eq 0 ] || [ "$O1" -ge 224 ] \
         || { [ "$O1" -eq 172 ] && [ "$O2" -ge 16 ] && [ "$O2" -le 31 ]; } \
         || { [ "$O1" -eq 192 ] && [ "$O2" -eq 168 ]; } \
         || { [ "$O1" -eq 169 ] && [ "$O2" -eq 254 ]; } \
         || { [ "$O1" -eq 100 ] && [ "$O2" -ge 64 ] && [ "$O2" -le 127 ]; }; then
        PRIVE=1
      fi
    else
      case "''${IPADDR,,}" in
        ::1|fe8*|fe9*|fea*|feb*|fc*|fd*|ff*) PRIVE=1 ;;
      esac
    fi
    if [ -n "$PRIVE" ]; then
      printf "''${Y}%s''${R} est une adresse privée/réservée : aucune info publique.\n" "$IPADDR"
      exit 1
    fi

    # ── Collecte en parallèle ───────────────────────────────────
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    CHAMPS="status,message,continent,country,countryCode,regionName,city,district,zip,lat,lon,timezone,offset,currency,isp,org,as,asname,reverse,mobile,proxy,hosting,query"
    $CURL -sf --max-time 6 "http://ip-api.com/json/$IPADDR?fields=$CHAMPS&lang=fr" -o "$TMP/geo" &
    $CURL -sfL --max-time 10 "https://rdap.org/ip/$IPADDR" -o "$TMP/rdap" &
    $CURL -s --max-time 8 "https://internetdb.shodan.io/$IPADDR" -o "$TMP/shodan" &
    $DIG +short +time=3 +tries=1 -x "$IPADDR" > "$TMP/rdns" 2>/dev/null &

    # Listes noires (IPv4 seulement) : ip inversée + zone
    DNSBL="zen.spamhaus.org bl.spamcop.net b.barracudacentral.org dnsbl-1.uceprotect.net all.s5h.net"
    if is_v4 "$IPADDR"; then
      REV="$O4.$O3.$O2.$O1"
      for Z in $DNSBL; do
        $DIG +short +time=3 +tries=1 A "$REV.$Z" > "$TMP/bl_$Z" 2>/dev/null &
      done
    fi
    wait

    # Secours géoloc : ipwho.is, remappé au format ip-api
    if [ "$($JQ -r '.status // empty' "$TMP/geo" 2>/dev/null)" != "success" ]; then
      $CURL -sf --max-time 6 "https://ipwho.is/$IPADDR?lang=fr" | $JQ '{
        status: (if .success then "success" else "fail" end), message,
        continent, country, countryCode: .country_code, regionName: .region, city,
        zip: .postal, lat: .latitude, lon: .longitude,
        timezone: .timezone.id, offset: .timezone.offset,
        isp: .connection.isp, org: .connection.org,
        as: (if .connection.asn then "AS\(.connection.asn) \(.connection.org)" else null end),
        asname: .connection.org, query: .ip
      }' > "$TMP/geo" 2>/dev/null
    fi

    for F in geo rdap shodan; do
      $JQ -e . "$TMP/$F" >/dev/null 2>&1 || echo '{}' > "$TMP/$F"
    done
    RDNS=$(grep -v '^;' "$TMP/rdns" | sed 's/\.$//' | paste -sd, - | sed 's/,/, /g')

    if [ "$JSON" = 1 ]; then
      $JQ -n --arg ip "$IPADDR" --arg host "$HOTE" --arg rdns "$RDNS" \
        --slurpfile geo "$TMP/geo" --slurpfile rdap "$TMP/rdap" --slurpfile shodan "$TMP/shodan" \
        '{ip: $ip, host: $host, reverse_dns: $rdns, geo: $geo[0], rdap: $rdap[0], shodan: $shodan[0]}'
      exit 0
    fi

    g() { $JQ -r "$1 | if . == null or . == \"\" then empty else tostring end" "$TMP/$2" 2>/dev/null; }
    # Padding à la main : printf compte les octets, pas les caractères accentués
    row() {
      [ -n "$2" ] || return 0
      local pad=$((14 - ''${#1})); [ "$pad" -lt 1 ] && pad=1
      printf "    ''${D}%s''${R}%*s%s\n" "$1" "$pad" "" "$2"
    }
    titre() { printf "\n  ''${B}''${C}%s''${R}\n" "$1"; }
    W=64
    line() { printf "''${D}%s''${R}\n" "$(printf '─%.0s' $(seq 1 $W))"; }

    # ── En-tête ─────────────────────────────────────────────────
    CC=$(g .countryCode geo)
    DRAPEAU=""
    if [[ "$CC" =~ ^[A-Z]{2}$ ]]; then
      A1=$(printf '%d' "\"''${CC:0:1}"); A2=$(printf '%d' "\"''${CC:1:1}")
      DRAPEAU=$(printf "\\U$(printf '%08X' $((0x1F1E6 + A1 - 65)))\\U$(printf '%08X' $((0x1F1E6 + A2 - 65)))")
    fi
    printf "\n  ''${B}''${M}󰩠  %s''${R}" "$IPADDR"
    [ -n "$HOTE" ] && printf "  ''${D}(%s)''${R}" "$HOTE"
    [ -z "$CIBLE" ] && printf "  ''${D}(ton IP publique)''${R}"
    printf "\n"
    line

    # ── Localisation ────────────────────────────────────────────
    titre "󰍎  Localisation"
    PAYS=$(g .country geo)
    row "Pays" "$PAYS''${CC:+ ($CC)}''${DRAPEAU:+ $DRAPEAU}"
    row "Continent" "$(g .continent geo)"
    row "Région" "$(g .regionName geo)"
    VILLE=$(g .city geo); ZIP=$(g .zip geo); QUARTIER=$(g .district geo)
    row "Ville" "$VILLE''${ZIP:+ $ZIP}''${QUARTIER:+ — $QUARTIER}"
    LAT=$(g .lat geo); LON=$(g .lon geo)
    if [ -n "$LAT" ] && [ -n "$LON" ]; then
      row "Coordonnées" "$LAT, $LON  ''${D}(approx.)''${R}"
      row "Carte" "https://www.openstreetmap.org/?mlat=$LAT&mlon=$LON#map=11/$LAT/$LON"
    fi
    TZN=$(g .timezone geo)
    [ -n "$TZN" ] && row "Fuseau" "$TZN  ''${D}il est $(TZ="$TZN" date '+%H:%M')''${R}"
    row "Monnaie" "$(g .currency geo)"

    # ── Réseau ──────────────────────────────────────────────────
    titre "󰛳  Réseau"
    row "FAI" "$(g .isp geo)"
    row "Organisation" "$(g .org geo)"
    row "AS" "$(g .as geo)"
    row "Nom AS" "$(g .asname geo)"
    row "DNS inverse" "''${RDNS:-$(g .reverse geo)}"

    # Type de connexion (drapeaux ip-api)
    TYPES=()
    [ "$(g .mobile geo)" = "true" ]  && TYPES+=("''${Y}mobile (4G/5G)''${R}")
    [ "$(g .proxy geo)" = "true" ]   && TYPES+=("''${X}proxy / VPN / Tor''${R}")
    [ "$(g .hosting geo)" = "true" ] && TYPES+=("''${Y}hébergeur / datacenter''${R}")
    if [ -n "$(g .proxy geo)" ]; then
      [ ''${#TYPES[@]} -eq 0 ] && TYPES+=("''${G}résidentielle / standard''${R}")
      row "Type" "$(IFS=,; printf '%s' "''${TYPES[*]}" | sed 's/,/, /g')"
    fi

    # ── Propriétaire du bloc (RDAP) ─────────────────────────────
    if [ "$($JQ -r '.handle // empty' "$TMP/rdap")" != "" ]; then
      titre "󰈙  Propriétaire du bloc (RDAP)"
      row "Nom réseau" "$(g .name rdap)"
      row "Handle" "$(g .handle rdap)"
      row "Plage" "$($JQ -r 'if .startAddress then "\(.startAddress) – \(.endAddress)" else empty end' "$TMP/rdap")"
      row "CIDR" "$($JQ -r '[.cidr0_cidrs[]? | "\(.v4prefix // .v6prefix)/\(.length)"] | join(", ")' "$TMP/rdap")"
      row "Titulaire" "$($JQ -r '[.entities[]? | select(.roles|index("registrant")) | .vcardArray[1][]? | select(.[0]=="fn") | .[3]] | first // empty' "$TMP/rdap")"
      row "Description" "$($JQ -r '[.remarks[]?.description[]?] | .[0:2] | join(" / ")' "$TMP/rdap")"
      row "Registre" "$(g .port43 rdap)"
      row "Attribué le" "$($JQ -r '[.events[]? | select(.eventAction=="registration") | .eventDate[0:10]] | first // empty' "$TMP/rdap")"
      row "Modifié le" "$($JQ -r '[.events[]? | select(.eventAction=="last changed") | .eventDate[0:10]] | first // empty' "$TMP/rdap")"
      row "Abuse" "$($JQ -r '[.. | objects | select((.roles? // []) | index("abuse")) | .vcardArray[1][]? | select(.[0]=="email") | .[3]] | unique | join(", ")' "$TMP/rdap")"
    fi

    # ── Exposition (Shodan InternetDB) ──────────────────────────
    titre "󰒃  Exposition (Shodan)"
    if [ "$($JQ -r '.ip // empty' "$TMP/shodan")" != "" ]; then
      row "Ports ouverts" "$($JQ -r '.ports | map(tostring) | join(", ")' "$TMP/shodan")"
      row "Noms d'hôte" "$($JQ -r '.hostnames[0:5] | join(", ")' "$TMP/shodan")"
      row "Tags" "$($JQ -r '.tags | join(", ")' "$TMP/shodan")"
      row "Logiciels" "$($JQ -r '[.cpes[] | sub("^cpe:/[aoh]:"; "")] | .[0:6] | join(", ")' "$TMP/shodan")"
      NV=$($JQ -r '.vulns | length' "$TMP/shodan")
      if [ "$NV" -gt 0 ]; then
        row "Vulnérabilités" "''${X}$NV CVE''${R} ''${D}$($JQ -r '.vulns[0:5] | join(", ")' "$TMP/shodan")$([ "$NV" -gt 5 ] && printf ' …')''${R}"
      fi
    else
      row "État" "''${D}aucune donnée (rien d'exposé ou pas encore scanné)''${R}"
    fi

    # ── Réputation (DNSBL) ──────────────────────────────────────
    if is_v4 "$IPADDR"; then
      titre "󰞀  Listes noires"
      LISTEES=(); INVERIF=()
      for Z in $DNSBL; do
        REP=$(grep -E '^127\.' "$TMP/bl_$Z" | head -1)
        case "$REP" in
          "") ;;
          127.255.255.*|IP_CENSUREE) INVERIF+=("$Z") ;;   # refus (résolveur public / quota)
          *) LISTEES+=("$Z") ;;
        esac
      done
      if [ ''${#LISTEES[@]} -gt 0 ]; then
        row "Listée sur" "''${X}''${LISTEES[*]}''${R}"
      else
        row "Résultat" "''${G}propre''${R} ''${D}($(printf '%s\n' $DNSBL | wc -l) listes testées)''${R}"
      fi
      [ ''${#INVERIF[@]} -gt 0 ] && row "Non vérifié" "''${D}''${INVERIF[*]} (refus du résolveur)''${R}"
    fi

    printf "\n"; line
    printf "  ''${D}Liens : https://ipinfo.io/%s · https://www.abuseipdb.com/check/%s · https://www.shodan.io/host/%s''${R}\n\n" "$IPADDR" "$IPADDR" "$IPADDR"
  '';
in
{
  home.packages = [ monip ipinfo ];
}
