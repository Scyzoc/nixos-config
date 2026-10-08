{ config, pkgs, lib, flakeRev, ... }:

let
  cfg = config.programs.ipinfo;

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

  # Commande `ipinfo` : tout savoir sur une IP publique ou un nom d'hôte.
  # Le script vit dans assets/ipinfo.sh (ipinfo --help pour l'aide complète) ;
  # writeShellApplication garantit ses dépendances et le passe à shellcheck.
  ipinfo = pkgs.writeShellApplication {
    name = "ipinfo";
    runtimeInputs = with pkgs; [
      bash coreutils curl dnsutils findutils gawk gnugrep gnused iputils jq less openssl procps
    ];
    bashOptions = [ "nounset" "pipefail" ];
    # SC2059 : les codes couleur sont volontairement dans les formats printf
    excludeShellChecks = [ "SC2059" ];
    text = ''
      IPINFO_VERSION=${lib.escapeShellArg flakeRev}
      : "''${IPINFO_TIMEOUT:=${toString cfg.timeout}}"
      : "''${IPINFO_JOBS:=${toString cfg.jobs}}"
      : "''${IPINFO_CACHE_TTL:=${toString cfg.cacheTtl}}"
    '' + lib.optionalString (cfg.cacheDir != null) ''
      if [ -z "''${IPINFO_CACHE_DIR:-}" ]; then IPINFO_CACHE_DIR=${lib.escapeShellArg cfg.cacheDir}; fi
    '' + builtins.readFile ../assets/ipinfo.sh;
  };
in
{
  options.programs.ipinfo = {
    enable = lib.mkEnableOption "la commande ipinfo (infos publiques sur une adresse IP)" // { default = true; };
    timeout = lib.mkOption {
      type = lib.types.ints.between 1 120;
      default = 8;
      description = "Délai max par requête HTTP, en secondes (surchargeable : --timeout).";
    };
    jobs = lib.mkOption {
      type = lib.types.ints.between 1 32;
      default = 8;
      description = "Nombre maximal de requêtes simultanées (surchargeable : --jobs).";
    };
    cacheDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/user/.cache/ipinfo";
      description = "Dossier du cache et des compteurs de quota. null = \${XDG_CACHE_HOME:-~/.cache}/ipinfo.";
    };
    cacheTtl = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 6 * 3600;
      description = "Durée de vie du cache, en secondes (--refresh pour l'ignorer).";
    };
  };

  config = lib.mkMerge [
    { home.packages = [ monip ]; }
    (lib.mkIf cfg.enable { home.packages = [ ipinfo ]; })
  ];
}
