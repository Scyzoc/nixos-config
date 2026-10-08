# shellcheck shell=bash
# ipinfo — tout savoir sur une adresse IP publique (ou un nom d'hôte).
#
# Empaqueté par modules/ipinfo.nix via writeShellApplication : les dépendances
# (curl, jq, dig, openssl…) viennent de runtimeInputs, nounset + pipefail actifs.
# Le module injecte IPINFO_VERSION et les défauts IPINFO_TIMEOUT, IPINFO_JOBS,
# IPINFO_CACHE_TTL et IPINFO_CACHE_DIR (surchargeables par l'environnement).
#
# Sources sans clé API, chacune avec un secours ou un message « indisponible » :
#   géoloc       ipwho.is (HTTPS) → secours ip-api.com (HTTP) ; 2e avis ipinfo.io
#   réputation   proxycheck.io → secours ip-api.com ; GreyNoise ; Tor Onionoo ; DNSBL
#   BGP          RIPEstat → secours Team Cymru (DNS)
#   opérateur    PeeringDB
#   bloc         RDAP : rdap.org → rdap.db.ripe.net → rdap.arin.net
#   exposition   Shodan InternetDB, HackerTarget

export LC_ALL=C.UTF-8
shopt -s nullglob

VERSION="${IPINFO_VERSION:-dev}"
TIMEOUT_S="${IPINFO_TIMEOUT:-8}"
JOBS="${IPINFO_JOBS:-8}"
CACHE_TTL="${IPINFO_CACHE_TTL:-21600}"
CACHE_DIR="${IPINFO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ipinfo}"
DNSBL_RESOLVER="${IPINFO_DNSBL_RESOLVER:-}"
DNSBL=(zen.spamhaus.org bl.spamcop.net b.barracudacentral.org dnsbl-1.uceprotect.net all.s5h.net)
SECTIONS_ALL=(geo net rep bgp op rdap expo)

# Quotas gratuits, comptés localement avant chaque appel : limite + période
declare -A QUOTA_MAX=([ipapi]=45 [proxycheck]=100 [hackertarget]=20)
declare -A QUOTA_PER=([ipapi]=%Y%m%d%H%M [proxycheck]=%Y%m%d [hackertarget]=%Y%m%d)
declare -A QUOTA_TXT=([ipapi]="45/min" [proxycheck]="100/jour" [hackertarget]="20/jour")

err() {
  if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then printf '\e[38;5;131m%s\e[0m\n' "$1" >&2
  else printf '%s\n' "$1" >&2; fi
}
die() { err "$1"; exit "${2:-2}"; }

# ── Options ─────────────────────────────────────────────────────
JSON=0; QUIET=0; ACTIF=0; NO_ACTIF=0; V6=0; REFRESH=0; FLAG=1; AIDE=0
SAVE=""; OUTFILE=""; CIBLE=""; ONLY=""; SKIP=""
while [ $# -gt 0 ]; do
  A=$1; V=""
  case "$A" in --*=*) V=${A#*=}; A=${A%%=*} ;; esac
  case "$A" in
    -h|--help) AIDE=1 ;;
    -V|--version) printf 'ipinfo %s\n' "$VERSION"; exit 0 ;;
    -j|--json) JSON=1 ;;
    -q|--quiet) QUIET=1 ;;
    -a|--actif|--active) ACTIF=1 ;;
    --no-active|--passif) NO_ACTIF=1 ;;
    -6) V6=1 ;;
    --refresh) REFRESH=1 ;;
    --no-flag) FLAG=0 ;;
    --only|--skip|--timeout|--jobs|--save|-o|--output|--dnsbl-resolver)
      if [ -z "$V" ]; then
        [ $# -ge 2 ] || die "Option $A : valeur manquante"
        V=$2; shift
      fi
      case "$A" in
        --only) ONLY=$V ;;
        --skip) SKIP=$V ;;
        --timeout) TIMEOUT_S=$V ;;
        --jobs) JOBS=$V ;;
        --save) SAVE=$V ;;
        -o|--output) OUTFILE=$V ;;
        --dnsbl-resolver) DNSBL_RESOLVER=$V ;;
      esac ;;
    -*) die "Option inconnue : $A  (ipinfo --help)" ;;
    *) [ -n "$CIBLE" ] && die "Une seule cible à la fois (« $CIBLE » et « $A »)"
       CIBLE=$A ;;
  esac
  shift
done

# ── Couleurs : TTY seulement, NO_COLOR coupe, CLICOLOR_FORCE force ─
couleurs_on() {
  [ -z "${NO_COLOR:-}" ] || return 1
  if [ -n "${CLICOLOR_FORCE:-}" ] && [ "$CLICOLOR_FORCE" != 0 ]; then return 0; fi
  [ -t 1 ]
}
B=""; D=""; R=""; G=""; Y=""; X=""; M=""; C=""
declare -A CAT=([geo]="" [net]="" [rep]="" [bgp]="" [op]="" [rdap]="" [expo]="" [actif]="")
if [ "$SAVE" != md ] && couleurs_on; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
  C=$'\e[38;5;110m'; G=$'\e[38;5;114m'; Y=$'\e[38;5;179m'
  M=$'\e[38;5;140m'; X=$'\e[38;5;131m'
  # Une couleur par catégorie de section
  CAT=([geo]=$'\e[38;5;110m' [net]=$'\e[38;5;74m' [rep]=$'\e[38;5;175m'
       [bgp]=$'\e[38;5;179m' [op]=$'\e[38;5;114m' [rdap]=$'\e[38;5;140m'
       [expo]=$'\e[38;5;174m' [actif]=$'\e[38;5;109m')
fi
# La console Linux n'affiche pas les emoji
[ "${TERM:-}" = linux ] && FLAG=0

aide() {
  cat <<EOF
${B}${C}IPINFO${R} ${D}$VERSION${R} — tout savoir sur une adresse IP publique

${B}${C}USAGE${R}
    ipinfo [OPTIONS] [CIBLE]

${B}${C}CIBLE${R}
    ${Y}(rien)${R}            ta propre IP publique (vue depuis Internet ; IPv6 avec -6)
    ${Y}8.8.8.8${R}           une adresse IPv4
    ${Y}2606:4700::1111${R}   une adresse IPv6
    ${Y}github.com${R}        un nom d'hôte : résolu UNE fois (A, sinon AAAA ; l'inverse
                      avec -6), et cette IP sert à toutes les sources et sondes

    Entrée validée strictement (pas de zéros en tête, IPv6 sans IPv4 imbriquée).
    Les adresses privées ou réservées (10.x, 172.16-31.x, 192.168.x, 127.x,
    169.254.x, 100.64-127.x CGNAT, plages de doc, multicast, fe80::, fc00::/7,
    2001:db8::…) sont refusées : aucune base publique n'a d'info dessus.

${B}${C}OPTIONS${R}
    ${B}-a, --actif${R}          ajoute des sondes envoyées directement à la cible :
                         ping, certificat TLS, serveur web, bannière SSH.
                         ${X}La cible voit alors ton IP${R} (rappel affiché à chaque fois).
    ${B}--no-active${R}          force le mode passif, même si -a est présent (alias).
    ${B}-q, --quiet${R}          une ligne TSV : IP, pays, ASN, FAI, ville (pour scripts)
    ${B}-j, --json${R}           JSON brut de toutes les sources (pour jq)
    ${B}--save json|md${R}       écrit le rapport dans un fichier au lieu de l'écran
    ${B}-o, --output F${R}       nom du fichier (.json ou .md : --save deviné)
    ${B}--only S,S${R}           n'interroge que ces sections (voir SECTIONS)
    ${B}--skip S,S${R}           saute ces sections
    ${B}-6${R}                   préfère l'IPv6 (résolution du nom, IP publique)
    ${B}--refresh${R}            ignore le cache et réinterroge les API
    ${B}--timeout N${R}          délai max par requête, en secondes (défaut $TIMEOUT_S)
    ${B}--jobs N${R}             requêtes simultanées au maximum (défaut $JOBS)
    ${B}--dnsbl-resolver IP${R}  résolveur DNS pour les listes noires (voir plus bas)
    ${B}--no-flag${R}            pas de drapeau emoji (terminal sans emoji)
    ${B}-V, --version${R}        version (commit de la config NixOS)
    ${B}-h, --help${R}           cette aide

    Sans -a, tout est ${B}passif${R} : seules des bases publiques tierces sont
    interrogées, la cible ne reçoit aucun paquet de ta part.

${B}${C}SECTIONS${R} ${D}(--only / --skip ; seules les API utiles sont appelées)${R}
    ${B}geo${R}    Localisation    ${D}ipwho.is (HTTPS), secours ip-api.com ; 2e avis ipinfo.io${R}
           pays, drapeau, région, ville, coordonnées, carte, fuseau, monnaie,
           anycast. ${D}Précision : ville du FAI, jamais l'adresse d'une personne.${R}
    ${B}net${R}    Réseau          ${D}même source que geo + DNS inverse${R}
           FAI, organisation, AS, PTR, type (résidentielle, mobile, datacenter…)
    ${B}rep${R}    Réputation      ${D}proxycheck.io (secours ip-api), GreyNoise, Tor, DNSBL${R}
           proxy/VPN, score de risque 0-100, appareils vus, nœud Tor,
           scanner Internet, listes noires
    ${B}bgp${R}    Routage BGP     ${D}RIPEstat, secours Team Cymru (DNS)${R}
           préfixe annoncé, bloc parent, RPKI, taille de l'AS, visibilité,
           voisins, transitaires
    ${B}op${R}     Opérateur       ${D}PeeringDB${R}   type, portée, trafic, peering, IX
    ${B}rdap${R}   Propriétaire    ${D}RDAP : rdap.org, secours RIPE puis ARIN${R}
           bloc, titulaire, dates, contact ${B}abuse${R} ${D}(alias : abuse, whois)${R}
    ${B}expo${R}   Exposition      ${D}Shodan InternetDB, HackerTarget${R}
           ports ouverts, logiciels, CVE, domaines hébergés sur la même IP

    Chaque section affiche l'heure de ses données (« en direct » ou « cache,
    il y a 2 h »), et la date fournie par la source quand elle existe
    (liste Tor publiée le…, dernier scan GreyNoise, fiche PeeringDB…).
    Une source en panne affiche « indisponible » sans bloquer les autres.

${B}${C}CACHE ET QUOTAS${R}
    Réponses gardées $((CACHE_TTL / 3600)) h dans ${Y}$CACHE_DIR${R}
    (--refresh pour forcer). Les appels aux API à quota sont comptés localement
    et refusés avant d'atteindre la limite : ip-api 45/min, proxycheck
    100/jour, HackerTarget 20/jour. GreyNoise et PeeringDB limitent aussi
    (réponse 429 → « quota atteint »).

${B}${C}LISTES NOIRES (DNSBL)${R} ${D}IPv4 seulement${R}
    zen.spamhaus.org, bl.spamcop.net, b.barracudacentral.org,
    dnsbl-1.uceprotect.net, all.s5h.net.
    ${Y}Les résolveurs publics (Cloudflare 1.1.1.1, Google, Quad9…) et beaucoup de
    résolveurs de FAI sont bloqués par Spamhaus${R} : ils répondent IP_CENSUREE
    (« refus »), pas un vrai résultat. ipinfo interroge donc chaque liste
    ${B}directement sur ses serveurs DNS faisant autorité${R}, et ne passe par ton
    résolveur que si ce n'est pas possible. --dnsbl-resolver IP impose un
    résolveur (ex. un unbound local en mode récursif).

${B}${C}VIE PRIVÉE${R}
    • Les requêtes HTTP respectent HTTPS_PROXY / https_proxy / ALL_PROXY
      (curl natif, aucun --noproxy) ; ip-api, en HTTP, utilise http_proxy
      (minuscules). Les requêtes DNS (PTR, DNSBL, Team Cymru) ne passent
      pas par le proxy.
    • ip-api.com gratuit est en HTTP clair : il n'est appelé qu'en secours.

${B}${C}EXEMPLES${R}
    ipinfo                          ma propre IP
    ipinfo IP_CENSUREE            qui est derrière cette IP ?
    ipinfo --only geo 8.8.8.8       juste la géoloc (2 requêtes)
    ipinfo --skip expo,op 1.1.1.1   tout sauf exposition et PeeringDB
    ipinfo -q 8.8.8.8               8.8.8.8<TAB>US<TAB>AS15169<TAB>Google LLC<TAB>…
    ipinfo -a monsite.fr            + certificat, serveur web, SSH
    ipinfo --save md github.com     rapport ipinfo-<ip>-<date>.md
    ipinfo -j 8.8.8.8 | jq .geo
    ipinfo -j 1.1.1.1 | jq '._meta.sources'

${B}${C}JSON (-j)${R}
    Clés : ip, host, reverse_dns, sections, geo (source normalisée), ipinfo,
    ipapi, rdap, shodan, proxycheck, greynoise, tor, ripestat {prefix,
    routing, neighbours, rpki}, cymru, peeringdb, dnsbl, reverse_ip,
    active {ping, tls, http, ssh}, _meta {version, generated, sources}.
    Une source muette ou non demandée vaut {}.

${B}${C}ENVIRONNEMENT${R}
    NO_COLOR, CLICOLOR_FORCE   couleurs (sinon : seulement dans un terminal)
    IPINFO_TIMEOUT, IPINFO_JOBS, IPINFO_CACHE_DIR, IPINFO_CACHE_TTL,
    IPINFO_DNSBL_RESOLVER      défauts réglés par le module Nix

${B}${C}CODES DE SORTIE${R}
    0     analyse réussie
    1     IP privée/réservée, nom introuvable, pas d'Internet, géoloc muette (-q)
    2     option ou entrée invalide
    130   interrompu (Ctrl-C)

${D}Voir aussi : monip (aperçu réseau local + IP publique en direct)${R}
EOF
}

if [ "$AIDE" = 1 ]; then
  if [ -t 1 ]; then aide | less -RFX; else aide; fi
  exit 0
fi

# ── Validation des options ──────────────────────────────────────
entier() { [[ $1 =~ ^[0-9]+$ ]] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
entier "$TIMEOUT_S" 1 120 || die "--timeout : entier entre 1 et 120 (secondes)"
entier "$JOBS" 1 32 || die "--jobs : entier entre 1 et 32"
[[ $CACHE_TTL =~ ^[0-9]+$ ]] || CACHE_TTL=21600
if [ -n "$OUTFILE" ] && [ -z "$SAVE" ]; then
  case "$OUTFILE" in
    *.json) SAVE=json ;;
    *.md) SAVE=md ;;
    *) die "-o : extension .json ou .md, ou précise --save json|md" ;;
  esac
fi
case "$SAVE" in ""|json|md) ;; *) die "--save : json ou md" ;; esac
[ "$QUIET" = 1 ] && { [ "$JSON" = 1 ] || [ -n "$SAVE" ]; } && die "-q est incompatible avec -j et --save"
[ "$JSON" = 1 ] && [ "$SAVE" = md ] && die "-j et --save md sont incompatibles"
[ "$SAVE" = json ] && JSON=1
[ "$NO_ACTIF" = 1 ] && ACTIF=0

section() {
  case "$1" in
    geo|loc|localisation) echo geo ;;
    net|reseau|réseau) echo net ;;
    rep|reputation|réputation) echo rep ;;
    bgp|routage) echo bgp ;;
    op|operateur|opérateur|peeringdb) echo op ;;
    rdap|abuse|whois|bloc) echo rdap ;;
    expo|exposition|shodan) echo expo ;;
    *) return 1 ;;
  esac
}
declare -A ON=()
if [ -n "$ONLY" ]; then
  IFS=, read -ra L <<< "$ONLY"
  for S in "${L[@]}"; do
    N=$(section "$S") || die "Section inconnue : $S  (geo, net, rep, bgp, op, rdap, expo)"
    ON[$N]=1
  done
else
  for S in "${SECTIONS_ALL[@]}"; do ON[$S]=1; done
fi
if [ -n "$SKIP" ]; then
  IFS=, read -ra L <<< "$SKIP"
  for S in "${L[@]}"; do
    N=$(section "$S") || die "Section inconnue : $S  (geo, net, rep, bgp, op, rdap, expo)"
    unset "ON[$N]"
  done
fi
[ "$QUIET" = 1 ] && ON=()
[ "$QUIET" = 1 ] || [ ${#ON[@]} -gt 0 ] || die "Aucune section à afficher"
on() { [ -n "${ON[$1]:-}" ]; }

# ── Validation stricte des adresses ─────────────────────────────
OCT='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
V4RE="^($OCT\\.){3}$OCT\$"
HOSTRE='^([A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.?$'
is_v4() { [[ $1 =~ $V4RE ]]; }
is_host() { [ ${#1} -le 253 ] && [[ $1 =~ $HOSTRE ]] && [[ $1 =~ [A-Za-z] ]]; }

# IPv6 → 32 chiffres hexa (forme développée), échec si l'adresse est invalide
v6_expand() {
  local a=${1,,} g n=0 i out=""
  local -a H=() T=()
  [[ $a =~ ^[0-9a-f:]+$ ]] || return 1
  [[ $a == *:::* ]] && return 1
  [[ $a == :* && $a != ::* ]] && return 1
  [[ $a == *: && $a != *:: ]] && return 1
  if [[ $a == *::* ]]; then
    local head=${a%%::*} tail=${a#*::}
    [[ $tail == *::* ]] && return 1
    [ -n "$head" ] && IFS=: read -ra H <<< "$head"
    [ -n "$tail" ] && IFS=: read -ra T <<< "$tail"
    n=$((8 - ${#H[@]} - ${#T[@]}))
    [ "$n" -ge 1 ] || return 1
  else
    IFS=: read -ra H <<< "$a"
    [ ${#H[@]} -eq 8 ] || return 1
  fi
  for g in "${H[@]}"; do
    [[ $g =~ ^[0-9a-f]{1,4}$ ]] || return 1
    g="000$g"; out+=${g: -4}
  done
  for ((i = 0; i < n; i++)); do out+="0000"; done
  for g in "${T[@]}"; do
    [[ $g =~ ^[0-9a-f]{1,4}$ ]] || return 1
    g="000$g"; out+=${g: -4}
  done
  printf '%s' "$out"
}
is_v6() { v6_expand "$1" > /dev/null; }

if [ -n "$DNSBL_RESOLVER" ] && ! is_v4 "$DNSBL_RESOLVER" && ! is_v6 "$DNSBL_RESOLVER"; then
  die "--dnsbl-resolver : adresse IP attendue"
fi

# ── Cible : résolue une seule fois, cette IP sert partout ───────
resoudre() {
  local T L
  local -a TYPES=(A AAAA) REPS
  [ "$V6" = 1 ] && TYPES=(AAAA A)
  for T in "${TYPES[@]}"; do
    mapfile -t REPS < <(dig +short +time=3 +tries=2 "$T" "$1" 2> /dev/null)
    for L in "${REPS[@]}"; do
      if is_v4 "$L" || is_v6 "$L"; then printf '%s' "$L"; return 0; fi
    done
  done
  return 1
}

HOTE=""; IPADDR=""
if [ -z "$CIBLE" ]; then
  if [ "$V6" = 1 ]; then URLS=(https://api6.ipify.org https://ipv6.icanhazip.com)
  else URLS=(https://api.ipify.org https://ifconfig.me/ip https://ipv4.icanhazip.com); fi
  for U in "${URLS[@]}"; do
    IPADDR=$(curl -sf --max-time "$TIMEOUT_S" "$U" 2> /dev/null | tr -d '[:space:]')
    if is_v4 "$IPADDR" || is_v6 "$IPADDR"; then break; fi
    IPADDR=""
  done
  [ -n "$IPADDR" ] || die "Impossible de récupérer ton IP publique (pas d'Internet ?)" 1
elif is_v4 "$CIBLE" || is_v6 "$CIBLE"; then
  IPADDR=${CIBLE,,}
elif [[ $CIBLE =~ ^[0-9.]+$ ]]; then
  die "IPv4 invalide : $CIBLE"
elif is_host "$CIBLE"; then
  HOTE=${CIBLE%.}
  IPADDR=$(resoudre "$HOTE") || die "« $HOTE » : nom introuvable (ni A ni AAAA)" 1
else
  die "« $CIBLE » : ni une IP, ni un nom d'hôte valide"
fi

# Adresses privées / réservées : rien à chercher sur Internet
PRIVE=""; IPN=""
if is_v4 "$IPADDR"; then
  IFS=. read -r O1 O2 O3 O4 <<< "$IPADDR"
  if [ "$O1" -eq 0 ] || [ "$O1" -eq 10 ] || [ "$O1" -eq 127 ] || [ "$O1" -ge 224 ] \
     || { [ "$O1" -eq 100 ] && [ "$O2" -ge 64 ] && [ "$O2" -le 127 ]; } \
     || { [ "$O1" -eq 169 ] && [ "$O2" -eq 254 ]; } \
     || { [ "$O1" -eq 172 ] && [ "$O2" -ge 16 ] && [ "$O2" -le 31 ]; } \
     || { [ "$O1" -eq 192 ] && [ "$O2" -eq 168 ]; } \
     || { [ "$O1" -eq 192 ] && [ "$O2" -eq 0 ] && { [ "$O3" -eq 0 ] || [ "$O3" -eq 2 ]; }; } \
     || { [ "$O1" -eq 198 ] && { [ "$O2" -eq 18 ] || [ "$O2" -eq 19 ]; }; } \
     || { [ "$O1" -eq 198 ] && [ "$O2" -eq 51 ] && [ "$O3" -eq 100 ]; } \
     || { [ "$O1" -eq 203 ] && [ "$O2" -eq 0 ] && [ "$O3" -eq 113 ]; }; then
    PRIVE=1
  fi
  HP="$IPADDR"
else
  IPN=$(v6_expand "$IPADDR")
  case "$IPN" in
    0000000000000000000000000000000[01]|00000000000000000000ffff*|fe[89ab]*|f[cd]*|ff*|20010db8*) PRIVE=1 ;;
  esac
  HP="[$IPADDR]"
fi
[ -n "$PRIVE" ] && die "$IPADDR est une adresse privée/réservée : aucune info publique." 1

# ── Fichiers temporaires, cache, interruption propre ────────────
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ipinfo.XXXXXX")
nettoyer() { rm -rf -- "$TMP"; }
tuer_arbre() {
  local c
  for c in $(pgrep -P "$1" 2> /dev/null); do tuer_arbre "$c"; done
  kill -TERM "$1" 2> /dev/null
}
interrompu() {
  trap - INT TERM
  local P
  for P in $(jobs -p); do tuer_arbre "$P"; done
  [ -t 2 ] && printf '\r\e[2K' >&2
  err "Interrompu."
  exit 130
}
trap nettoyer EXIT
trap interrompu INT TERM

NOW=$(date +%s)
CACHE=1
if mkdir -p "$CACHE_DIR/http" "$CACHE_DIR/quota" 2> /dev/null && [ -w "$CACHE_DIR/http" ]; then
  find "$CACHE_DIR/http" -type f -mmin +"$((CACHE_TTL / 60 + 60))" -delete 2> /dev/null
  find "$CACHE_DIR/quota" -type f -mtime +2 -delete 2> /dev/null
else
  CACHE=0
fi

# Lance une tâche de fond, sans dépasser $JOBS en parallèle
run() {
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2> /dev/null || true; done
  "$@" &
}

# État d'une source : ok | cache | quota | panne (+ horodatage des données)
setst() { printf '%s %s\n' "$2" "${3:-$(date +%s)}" > "$TMP/$1.st"; }
etat() {
  local s=""
  [ -f "$TMP/$1.st" ] && read -r s _ < "$TMP/$1.st"
  printf '%s' "${s:-absent}"
}
dispo() { case "$(etat "$1")" in ok|cache) return 0 ;; esac; return 1; }

quota_ok() {
  [ "$CACHE" = 1 ] || return 0
  local f n=0
  f="$CACHE_DIR/quota/$1-$(date "+${QUOTA_PER[$1]}")"
  [ -s "$f" ] && n=$(< "$f")
  [[ $n =~ ^[0-9]+$ ]] || n=0
  [ "$n" -lt "${QUOTA_MAX[$1]}" ] || return 1
  printf '%s\n' $((n + 1)) > "$f"
}
# L'API dit « quota dépassé » : on bloque localement jusqu'à la prochaine période
quota_plein() {
  [ "$CACHE" = 1 ] && [ "$1" != - ] || return 0
  printf '%s\n' "${QUOTA_MAX[$1]}" > "$CACHE_DIR/quota/$1-$(date "+${QUOTA_PER[$1]}")"
}

# Réponse exploitable ? (JSON valide et non-erreur, jamais une page HTML)
analyser() {
  local r
  case "$1" in
    revip)
      if grep -qi 'API count exceeded' "$2"; then r=quota
      elif [ -s "$2" ] && ! grep -qiE '<html|^error' "$2"; then r=ok
      else r=panne; fi ;;
    ipwho) r=$(jq -r 'if .success == true then "ok"
                 elif ((.message // "") | test("limit"; "i")) then "quota" else "panne" end' "$2" 2> /dev/null) ;;
    ipapi) r=$(jq -r 'if .status == "success" then "ok" else "panne" end' "$2" 2> /dev/null) ;;
    proxy) r=$(jq -r 'if .status == "ok" or .status == "warning" then "ok"
                 elif .status == "denied" then "quota" else "panne" end' "$2" 2> /dev/null) ;;
    *) if jq -e 'type == "object" or type == "array"' "$2" > /dev/null 2>&1; then r=ok; else r=panne; fi ;;
  esac
  printf '%s' "${r:-panne}"
}

# Tâche de fond : essaie chaque URL jusqu'à une réponse valide, puis la met en cache
telecharger() {
  local name=$1 q=$2 cf=$3 url code s=panne raw="$TMP/$1.raw"; shift 3
  # Une nouvelle tentative sur erreur passagère, sauf pour les API à quota
  local -a retry=()
  [ "$q" = - ] && retry=(--retry 1 --retry-delay 1)
  for url in "$@"; do
    curl -sL --max-time "$TIMEOUT_S" -A "ipinfo-cli/$VERSION" -o "$raw" "${retry[@]}" \
      -w '%{http_code}' "$url" > "$TMP/$name.code" 2> /dev/null
    code=$(< "$TMP/$name.code")
    s=panne
    case "$code" in
      429) s=quota ;;
      2??|404) [ -f "$raw" ] && s=$(analyser "$name" "$raw") ;;
    esac
    if [ "$s" = ok ]; then
      mv "$raw" "$TMP/$name"
      setst "$name" ok
      if [ "$CACHE" = 1 ]; then cp "$TMP/$name" "$cf.$BASHPID" && mv "$cf.$BASHPID" "$cf"; fi
      return 0
    fi
    [ "$s" = quota ] && quota_plein "$q"
  done
  setst "$name" "$s"
}

# fetch NOM QUOTA URL… : cache valide → copie ; quota local épuisé → refus ; sinon en fond
fetch() {
  local name=$1 q=$2 cf ts; shift 2
  cf="$CACHE_DIR/http/$name-$(printf '%s' "$1" | md5sum | cut -c1-16)"
  if [ "$CACHE" = 1 ] && [ "$REFRESH" = 0 ] && [ -s "$cf" ]; then
    ts=$(stat -c %Y "$cf")
    if [ $((NOW - ts)) -lt "$CACHE_TTL" ]; then
      cp "$cf" "$TMP/$name"; setst "$name" cache "$ts"
      return 0
    fi
  fi
  if [ "$q" != - ] && ! quota_ok "$q"; then setst "$name" quota; return 0; fi
  run telecharger "$name" "$q" "$cf" "$@"
}

# ── Sources DNS (pas de cache : rapides et sans quota) ──────────
if is_v4 "$IPADDR"; then
  REV4="$O4.$O3.$O2.$O1"
  CYMRU_Q="$REV4.origin.asn.cymru.com"
else
  REV4=""; CYMRU_Q=""
  for ((i = 31; i >= 0; i--)); do CYMRU_Q+="${IPN:i:1}."; done
  CYMRU_Q+="origin6.asn.cymru.com"
fi

dns_rdns() { dig +short +time=3 +tries=1 -x "$IPADDR" > "$TMP/rdns" 2> /dev/null; }
dns_cymru() { dig +short +time=3 +tries=1 TXT "$CYMRU_Q" > "$TMP/cymru" 2> /dev/null; }
dns_cymru_as() { dig +short +time=3 +tries=1 TXT "AS$1.asn.cymru.com" > "$TMP/cymru_as" 2> /dev/null; }

# Liste noire : serveur faisant autorité d'abord (les résolveurs publics sont
# refusés par Spamhaus & co), résolveur système en dernier recours.
# Fichier bl_ZONE : 1re ligne = méthode, puis les réponses.
dnsbl_job() {
  local z=$1 q="$REV4.$1" ns out
  local -a nss=()
  if [ -n "$DNSBL_RESOLVER" ]; then
    { echo "résolveur $DNSBL_RESOLVER"; dig +short +time=3 +tries=1 @"$DNSBL_RESOLVER" A "$q"; } > "$TMP/bl_$z" 2> /dev/null
    return
  fi
  # NS de la zone, sinon de la zone parente ; on essaie les deux premiers
  mapfile -t nss < <(dig +short +time=2 +tries=2 NS "$z" 2> /dev/null | grep -v '^;' | head -2)
  [ ${#nss[@]} -eq 0 ] && mapfile -t nss < <(dig +short +time=2 +tries=2 NS "${z#*.}" 2> /dev/null | grep -v '^;' | head -2)
  for ns in "${nss[@]}"; do
    out=$(dig +norec +time=2 +tries=2 @"$ns" A "$q" +noall +comments +answer 2> /dev/null)
    if grep -q 'flags:[^;]* aa' <<< "$out"; then
      { echo direct; awk '$4 == "A" { print $5 }' <<< "$out"; } > "$TMP/bl_$z"
      return
    fi
  done
  { echo résolveur; dig +short +time=3 +tries=1 A "$q" 2> /dev/null; } > "$TMP/bl_$z"
}
# listee | refus | propre | panne | absent
bl_etat() {
  local f="$TMP/bl_$1" rep
  [ -s "$f" ] || { echo absent; return; }
  rep=$(tail -n +2 "$f" | grep -E '^127\.' | head -1)
  case "$rep" in
    "") if tail -n +2 "$f" | grep -q '^;;'; then echo panne; else echo propre; fi ;;
    127.255.255.*|IP_CENSUREE|127.0.0.1) echo refus ;;
    *) echo listee ;;
  esac
}

# ── Collecte ────────────────────────────────────────────────────
if [ "$ACTIF" = 1 ]; then
  err "⚠ Mode actif : $IPADDR va recevoir des paquets (ping, TLS, HTTP, SSH) directement depuis ton IP."
fi
if [ "$JSON" = 0 ] && [ "$QUIET" = 0 ] && [ -t 2 ]; then
  printf '  %sAnalyse de %s…%s' "$D" "$IPADDR" "$R" >&2
fi

NEED_GEO=0
{ on geo || on net || [ "$QUIET" = 1 ]; } && NEED_GEO=1
URL_IPAPI="http://ip-api.com/json/$IPADDR?fields=status,message,continent,country,countryCode,regionName,city,district,zip,lat,lon,timezone,offset,currency,isp,org,as,asname,reverse,mobile,proxy,hosting,query&lang=fr"

# Vague 1 : tout ce qui ne dépend que de l'IP
[ "$NEED_GEO" = 1 ] && fetch ipwho - "https://ipwho.is/$IPADDR?lang=fr"
on geo && fetch ipinfoio - "https://ipinfo.io/$IPADDR/json"
on net && run dns_rdns
if on rep; then
  fetch proxy proxycheck "https://proxycheck.io/v2/$IPADDR?vpn=1&asn=1&risk=1"
  is_v4 "$IPADDR" && fetch grey - "https://api.greynoise.io/v3/community/$IPADDR"
  fetch tor - "https://onionoo.torproject.org/details?search=$IPADDR&fields=nickname,flags,or_addresses,exit_addresses,first_seen,last_seen,running"
  if is_v4 "$IPADDR"; then
    for Z in "${DNSBL[@]}"; do run dnsbl_job "$Z"; done
  fi
fi
on bgp && fetch prefix - "https://stat.ripe.net/data/prefix-overview/data.json?resource=$IPADDR"
{ on bgp || on op; } && run dns_cymru
on rdap && fetch rdap - "https://rdap.org/ip/$IPADDR" \
  "https://rdap.db.ripe.net/ip/$IPADDR" "https://rdap.arin.net/registry/ip/$IPADDR"
if on expo; then
  fetch shodan - "https://internetdb.shodan.io/$IPADDR"
  fetch revip hackertarget "https://api.hackertarget.com/reverseiplookup/?q=$IPADDR"
fi

# Sondes actives (-a)
: > "$TMP/ping"; : > "$TMP/tls"; : > "$TMP/http"; : > "$TMP/ssh"
sonde_ping() { ping -c4 -i0.3 -W2 "$IPADDR" > "$TMP/ping" 2>&1; }
sonde_tls() {
  local sni=()
  [ -n "$HOTE" ] && sni=(-servername "$HOTE")
  echo | timeout 6 openssl s_client -connect "$HP:443" "${sni[@]}" 2> /dev/null \
    | openssl x509 -noout -subject -issuer -enddate -ext subjectAltName > "$TMP/tls" 2> /dev/null
}
sonde_http() {
  # Avec un nom d'hôte, --resolve force l'IP déjà résolue (pas de 2e résolution DNS)
  local u="${HOTE:-$HP}" res=()
  [ -n "$HOTE" ] && res=(--resolve "$HOTE:443:$IPADDR" --resolve "$HOTE:80:$IPADDR")
  curl -skI --max-time 5 "${res[@]}" "https://$u/" > "$TMP/http" 2> /dev/null \
    || curl -sI --max-time 5 "${res[@]}" "http://$u/" > "$TMP/http" 2> /dev/null
}
sonde_ssh() {
  # shellcheck disable=SC2016
  timeout 4 bash -c 'exec 3<>"/dev/tcp/$1/22" && read -r -t 3 L <&3 && printf "%s\n" "$L"' _ "$IPADDR" > "$TMP/ssh" 2> /dev/null
}
if [ "$ACTIF" = 1 ]; then
  run sonde_ping; run sonde_tls; run sonde_http; run sonde_ssh
fi
wait

# Secours ip-api : géoloc si ipwho.is muet, drapeaux proxy si proxycheck muet
if { [ "$NEED_GEO" = 1 ] && ! dispo ipwho; } || { on rep && ! dispo proxy; }; then
  fetch ipapi ipapi "$URL_IPAPI"
  wait
fi

GEO_OK=0
if dispo ipwho; then
  jq '{
    status: "success", continent, country, countryCode: .country_code,
    regionName: .region, city, zip: .postal, lat: .latitude, lon: .longitude,
    timezone: .timezone.id, offset: .timezone.offset, currency: (.currency.code? // null),
    isp: .connection.isp, org: .connection.org,
    as: (if .connection.asn then "AS\(.connection.asn) \(.connection.org // "")" else null end),
    asname: .connection.org, flag: .flag.emoji, query: .ip, source: "ipwho.is"
  }' "$TMP/ipwho" > "$TMP/geo" 2> /dev/null && GEO_OK=1
elif [ "$NEED_GEO" = 1 ] && dispo ipapi; then
  jq '. + {source: "ip-api.com"}' "$TMP/ipapi" > "$TMP/geo" 2> /dev/null && GEO_OK=1
fi

JSONS=(geo ipwho ipapi ipinfoio rdap shodan proxy grey tor prefix routing neigh rpki pdb)
jsonfix() {
  local F
  for F in "$@"; do jq -e . "$TMP/$F" > /dev/null 2>&1 || echo '{}' > "$TMP/$F"; done
}
jsonfix "${JSONS[@]}"

g() { jq -r "$1 | if . == null or . == \"\" then empty else tostring end" "$TMP/$2" 2> /dev/null; }

# ASN : RIPEstat, sinon Team Cymru, sinon la géoloc
ASN=""; PREFIXE=""
if dispo prefix; then
  ASN=$(g '.data.asns[0].asn' prefix)
  PREFIXE=$(jq -r 'if .data.announced then .data.resource else empty end' "$TMP/prefix" 2> /dev/null)
fi
CY_ASN=""; CY_PREFIX=""; CY_CC=""; CY_REG=""; CY_DATE=""
if [ -s "$TMP/cymru" ]; then
  IFS='|' read -r CY_ASN CY_PREFIX CY_CC CY_REG CY_DATE < <(head -1 "$TMP/cymru" | tr -d '"')
  CY_ASN=$(printf '%s' "$CY_ASN" | awk '{print $1}')
  CY_PREFIX=${CY_PREFIX// /}; CY_CC=${CY_CC// /}; CY_REG=${CY_REG// /}; CY_DATE=${CY_DATE// /}
  [[ $CY_ASN =~ ^[0-9]+$ ]] || CY_ASN=""
fi
[ -z "$ASN" ] && ASN=$CY_ASN
[ -z "$ASN" ] && ASN=$(g .as geo | sed -n 's/^AS\([0-9]*\).*/\1/p')

# Vague 2 : ce qui dépend de l'AS et du préfixe annoncé
if [ -n "$ASN" ] && { on bgp || on op; }; then
  if on bgp; then
    fetch routing - "https://stat.ripe.net/data/routing-status/data.json?resource=AS$ASN"
    fetch neigh - "https://stat.ripe.net/data/asn-neighbours/data.json?resource=AS$ASN"
    [ -n "$PREFIXE" ] && fetch rpki - "https://stat.ripe.net/data/rpki-validation/data.json?resource=AS$ASN&prefix=$PREFIXE"
    run dns_cymru_as "$ASN"
  fi
  on op && fetch pdb - "https://www.peeringdb.com/api/net?asn=$ASN"
  wait
fi
jsonfix routing neigh rpki pdb

# Vague 3 : noms des 3 principaux opérateurs amont
AMONTS=()
if on bgp && dispo neigh; then
  mapfile -t AMONTS < <(jq -r '[.data.neighbours[]? | select(.type == "left")] | sort_by(-.power) | .[0:3][] | .asn' "$TMP/neigh" 2> /dev/null)
  for U in "${AMONTS[@]}"; do
    fetch "up_$U" - "https://stat.ripe.net/data/as-overview/data.json?resource=AS$U"
  done
  wait
fi

[ "$JSON" = 0 ] && [ "$QUIET" = 0 ] && [ -t 2 ] && printf '\r\e[2K' >&2

RDNS=""
[ -s "$TMP/rdns" ] && RDNS=$(grep -v '^;' "$TMP/rdns" | sed 's/\.$//' | paste -sd, - | sed 's/,/, /g')
CY_NOM=""
[ -s "$TMP/cymru_as" ] && CY_NOM=$(head -1 "$TMP/cymru_as" | tr -d '"' | awk -F' [|] ' '{print $5}')

# ── Sortie une ligne (-q) ───────────────────────────────────────
if [ "$QUIET" = 1 ]; then
  champ() { local v; v=$(g "$1" geo); v=${v//$'\t'/ }; printf '%s' "${v:--}"; }
  if [ "$GEO_OK" = 0 ]; then
    printf '%s\t-\t-\t-\t-\n' "$IPADDR"
    die "Géoloc indisponible (ipwho.is et ip-api muets ou quota atteint)" 1
  fi
  QASN=$(g .as geo | awk '{print $1}')
  printf '%s\t%s\t%s\t%s\t%s\n' "$IPADDR" "$(champ .countryCode)" "${QASN:--}" "$(champ .isp)" "$(champ .city)"
  exit 0
fi

# ── Fichier de sortie (--save) ──────────────────────────────────
if [ -n "$SAVE" ]; then
  [ -n "$OUTFILE" ] || OUTFILE="ipinfo-${IPADDR//:/-}-$(date +%Y%m%d-%H%M%S).$SAVE"
  ( : > "$OUTFILE" ) 2> /dev/null || die "Impossible d'écrire $OUTFILE" 1
  exec 3>&1 > "$OUTFILE"
fi
fin_save() {
  if [ -n "$SAVE" ]; then
    exec 1>&3 3>&-
    printf 'Rapport enregistré : %s\n' "$OUTFILE" >&2
  fi
}

# ── JSON (-j / --save json) ─────────────────────────────────────
if [ "$JSON" = 1 ]; then
  ARGS=()
  for F in "${JSONS[@]}"; do ARGS+=(--slurpfile "$F" "$TMP/$F"); done
  : > "$TMP/revip.txt"; dispo revip && cp "$TMP/revip" "$TMP/revip.txt"
  META=$(for F in "$TMP"/*.st; do
           N=${F##*/}; read -r S T < "$F"; printf '%s\t%s\t%s\n' "${N%.st}" "$S" "$T"
         done | jq -Rn '[inputs | split("\t") | {key: .[0], value: {status: .[1],
                 fetched_at: (.[2] | tonumber | todate), from_cache: (.[1] == "cache")}}] | from_entries')
  DNSBLJ=$(for Z in "${DNSBL[@]}"; do
             [ -s "$TMP/bl_$Z" ] || continue
             printf '%s\t%s\t%s\t%s\n' "$Z" "$(head -1 "$TMP/bl_$Z")" "$(bl_etat "$Z")" \
               "$(tail -n +2 "$TMP/bl_$Z" | grep -E '^127\.' | paste -sd, -)"
           done | jq -Rn '[inputs | split("\t") | {key: .[0], value: {method: .[1], status: .[2],
                   answers: (.[3] | if . == "" then [] else split(",") end)}}] | from_entries')
  SECTIONSJ=$(printf '%s\n' "${!ON[@]}" | jq -Rn '[inputs | select(. != "")]')
  jq -n --arg ip "$IPADDR" --arg host "$HOTE" --arg rdns "$RDNS" --arg version "$VERSION" \
    --arg generated "$(date -Iseconds)" "${ARGS[@]}" \
    --argjson meta "${META:-"{}"}" --argjson dnsbl "${DNSBLJ:-"{}"}" --argjson sections "$SECTIONSJ" \
    --arg cy_asn "$CY_ASN" --arg cy_prefix "$CY_PREFIX" --arg cy_cc "$CY_CC" \
    --arg cy_reg "$CY_REG" --arg cy_date "$CY_DATE" --arg cy_nom "$CY_NOM" \
    --rawfile revip "$TMP/revip.txt" --rawfile ping "$TMP/ping" --rawfile tls "$TMP/tls" \
    --rawfile http "$TMP/http" --rawfile ssh "$TMP/ssh" \
    '{ip: $ip, host: $host, reverse_dns: $rdns, sections: $sections,
      geo: $geo[0], ipinfo: $ipinfoio[0], ipapi: $ipapi[0], rdap: $rdap[0], shodan: $shodan[0],
      proxycheck: $proxy[0], greynoise: $grey[0], tor: $tor[0],
      ripestat: {prefix: $prefix[0].data, routing: $routing[0].data, neighbours: $neigh[0].data, rpki: $rpki[0].data},
      cymru: (if $cy_asn == "" then {} else {asn: $cy_asn, prefix: $cy_prefix, country: $cy_cc,
              registry: $cy_reg, allocated: $cy_date, as_name: $cy_nom} end),
      peeringdb: ($pdb[0].data[0] // {}), dnsbl: $dnsbl, reverse_ip: $revip,
      active: {ping: $ping, tls: $tls, http: $http, ssh: $ssh},
      _meta: {version: $version, generated: $generated, sources: $meta}}'
  fin_save
  exit 0
fi

# ── Rendu texte (ou Markdown avec --save md) ────────────────────
MD=0; [ "$SAVE" = md ] && MD=1

# Padding à la main : printf compte les octets, pas les caractères accentués
row() {
  [ -n "$2" ] || return 0
  if [ "$MD" = 1 ]; then
    local k=$1 v=${2//|/\\|}
    printf '| %s | %s |\n' "${k#"${k%%[! ]*}"}" "$v"
    return 0
  fi
  local pad=$((15 - ${#1})); [ "$pad" -lt 1 ] && pad=1
  printf "    ${D}%s${R}%*s%s\n" "$1" "$pad" "" "$2"
}
heure() {
  if [ "$(date -d "@$1" +%F)" = "$(date +%F)" ]; then date -d "@$1" +%H:%M
  else date -d "@$1" '+%d/%m %H:%M'; fi
}
il_y_a() {
  local s=$((NOW - $1))
  if [ "$s" -lt 90 ]; then printf "à l'instant"
  elif [ "$s" -lt 3600 ]; then printf 'il y a %d min' $((s / 60))
  else printf 'il y a %d h %02d' $((s / 3600)) $((s % 3600 / 60)); fi
}
# Fraîcheur d'une section : « en direct HH:MM » ou « cache HH:MM, il y a … »
frais() {
  local n s t old="" vu=0
  for n in "$@"; do
    [ -f "$TMP/$n.st" ] || continue
    read -r s t < "$TMP/$n.st"
    case "$s" in
      ok) vu=1 ;;
      cache) vu=1; if [ -z "$old" ] || [ "$t" -lt "$old" ]; then old=$t; fi ;;
    esac
  done
  if [ -n "$old" ]; then printf 'cache de %s (%s)' "$(heure "$old")" "$(il_y_a "$old")"
  elif [ "$vu" = 1 ]; then printf 'en direct %s' "$(date +%H:%M)"; fi
}
titre() {
  local c=${CAT[$1]} t=$2 f; shift 2
  f=$(frais "$@")
  if [ "$MD" = 1 ]; then
    printf '\n## %s\n\n' "$t"
    [ -n "$f" ] && printf '_%s_\n\n' "$f"
    printf '| Champ | Valeur |\n|---|---|\n'
  else
    printf "\n  ${B}${c}%s${R}" "$t"
    [ -n "$f" ] && printf "  ${D}%s${R}" "$f"
    printf '\n'
  fi
}
LIGNE=$(printf '%64s' '' | sed 's/ /─/g')
line() { [ "$MD" = 1 ] || printf "${D}%s${R}\n" "$LIGNE"; }
joinv() { local IFS=,; printf '%s' "$*" | sed 's/,/, /g'; }
indispo() {
  case "$(etat "$1")" in
    quota) printf "${Y}quota atteint${R} ${D}(%s)${R}" "${2:-réessaie plus tard}" ;;
    *) printf "${D}indisponible (service injoignable ou réponse invalide)${R}" ;;
  esac
}

# ── En-tête ─────────────────────────────────────────────────────
CC=$(g .countryCode geo)
DRAPEAU=""
if [ "$FLAG" = 1 ] && [[ $CC =~ ^[A-Z]{2}$ ]]; then
  DRAPEAU=$(g .flag geo)
  if [ -z "$DRAPEAU" ]; then
    A1=$(printf '%d' "'${CC:0:1}"); A2=$(printf '%d' "'${CC:1:1}")
    printf -v DRAPEAU "\\U$(printf '%08X' $((0x1F1E6 + A1 - 65)))\\U$(printf '%08X' $((0x1F1E6 + A2 - 65)))"
  fi
fi
if [ "$MD" = 1 ]; then
  printf '# %s' "$IPADDR"
  [ -n "$HOTE" ] && printf ' (%s)' "$HOTE"
  [ -z "$CIBLE" ] && printf ' (mon IP publique)'
  printf '\n\n_Rapport ipinfo %s du %s_\n' "$VERSION" "$(date '+%d/%m/%Y %H:%M')"
else
  printf "\n  ${B}${M}󰩠  %s${R}" "$IPADDR"
  [ -n "$HOTE" ] && printf "  ${D}(%s)${R}" "$HOTE"
  [ -z "$CIBLE" ] && printf "  ${D}(ton IP publique)${R}"
  printf "\n"
  line
fi

# ── Localisation ────────────────────────────────────────────────
if on geo; then
  titre geo "󰍎  Localisation" ipwho ipapi ipinfoio
  if [ "$GEO_OK" = 1 ]; then
    row "Pays" "$(g .country geo)${CC:+ ($CC)}${DRAPEAU:+ $DRAPEAU}"
    row "Continent" "$(g .continent geo)"
    row "Région" "$(g .regionName geo)"
    VILLE=$(g .city geo); ZIP=$(g .zip geo); QUARTIER=$(g .district geo)
    row "Ville" "$VILLE${ZIP:+ $ZIP}${QUARTIER:+ — $QUARTIER}"
    VILLE2=$(g .city ipinfoio); PAYS2=$(g .country ipinfoio)
    if [ -n "$VILLE2" ] && [ "$VILLE2" != "$VILLE" ]; then
      row "Autre source" "${Y}$VILLE2, $PAYS2${R} ${D}(ipinfo.io — géoloc incertaine)${R}"
    fi
    LAT=$(g .lat geo); LON=$(g .lon geo)
    if [ -n "$LAT" ] && [ -n "$LON" ]; then
      row "Coordonnées" "$LAT, $LON  ${D}(approx.)${R}"
      row "Carte" "https://www.openstreetmap.org/?mlat=$LAT&mlon=$LON#map=11/$LAT/$LON"
    fi
    TZN=$(g .timezone geo)
    [ -n "$TZN" ] && row "Fuseau" "$TZN  ${D}il est $(TZ="$TZN" date '+%H:%M')${R}"
    MONNAIE=$(g .currency geo)
    [ -z "$MONNAIE" ] && MONNAIE=$(g ".\"$IPADDR\".currency.code" proxy)
    row "Monnaie" "$MONNAIE"
    SRC=$(g .source geo)
    [ "$SRC" = ip-api.com ] && SRC="$SRC ${Y}(secours, HTTP en clair)${R}"
    row "Source" "${D}$SRC${R}"
  else
    row "Géoloc" "$(indispo ipwho) ${D}— secours ip-api :${R} $(indispo ipapi "${QUOTA_TXT[ipapi]}")"
  fi
  [ "$(g .anycast ipinfoio)" = "true" ] && \
    row "Anycast" "${Y}oui${R} ${D}— servie depuis plusieurs lieux, la géoloc n'a pas de sens${R}"
fi

# ── Réseau ──────────────────────────────────────────────────────
if on net; then
  titre net "󰛳  Réseau" ipwho ipapi
  if [ "$GEO_OK" = 1 ]; then
    row "FAI" "$(g .isp geo)"
    row "Organisation" "$(g .org geo)"
    row "AS" "$(g .as geo)"
    row "Nom AS" "$(g .asname geo)"
  else
    row "FAI / AS" "$(indispo ipwho)"
  fi
  row "DNS inverse" "${RDNS:-$(g .reverse geo)}"

  # Type de connexion : proxycheck (si interrogé), sinon drapeaux ip-api
  PXT=$(g ".\"$IPADDR\".type" proxy)
  if [ -n "$PXT" ]; then
    case "$PXT" in
      Residential) T="${G}résidentielle${R}" ;;
      Business) T="${G}entreprise${R}" ;;
      Wireless) T="${Y}mobile / sans fil${R}" ;;
      Hosting) T="${Y}hébergeur / datacenter${R}" ;;
      VPN) T="${X}VPN${R}" ;;
      TOR) T="${X}Tor${R}" ;;
      *) T="$PXT" ;;
    esac
    row "Type" "$T"
  else
    FL=geo; [ -n "$(g .proxy geo)" ] || FL=ipapi
    if [ -n "$(g .proxy "$FL")" ]; then
      TYPES=()
      [ "$(g .mobile "$FL")" = "true" ] && TYPES+=("${Y}mobile (4G/5G)${R}")
      [ "$(g .proxy "$FL")" = "true" ] && TYPES+=("${X}proxy / VPN / Tor${R}")
      [ "$(g .hosting "$FL")" = "true" ] && TYPES+=("${Y}hébergeur / datacenter${R}")
      [ ${#TYPES[@]} -eq 0 ] && TYPES+=("${G}résidentielle / standard${R}")
      row "Type" "$(joinv "${TYPES[@]}")"
    fi
  fi
fi

# ── Réputation / anonymat ───────────────────────────────────────
if on rep; then
  titre rep "󰒃  Réputation et anonymat" proxy ipapi grey tor
  PX=".\"$IPADDR\""
  PXOUI=$(g "$PX.proxy" proxy)
  if [ -n "$PXOUI" ]; then
    PXTYPE=$(g "$PX.type" proxy); RISK=$(g "$PX.risk" proxy)
    if [ "$PXOUI" = "yes" ]; then
      row "Proxy / VPN" "${X}oui${R}${PXTYPE:+ ($PXTYPE)}"
    else
      row "Proxy / VPN" "${G}non${R}${PXTYPE:+ ${D}($PXTYPE)${R}}"
    fi
    if [[ $RISK =~ ^[0-9]+$ ]]; then
      if [ "$RISK" -ge 67 ]; then RC="$X"; elif [ "$RISK" -ge 34 ]; then RC="$Y"; else RC="$G"; fi
      row "Risque" "${RC}$RISK/100${R} ${D}(proxycheck.io)${R}"
    fi
    DEVA=$(g "$PX.devices.address" proxy); DEVS=$(g "$PX.devices.subnet" proxy)
    [ -n "$DEVA" ] && row "Appareils vus" "$DEVA sur l'IP${DEVS:+, $DEVS sur le sous-réseau}"
  elif [ -n "$(g .proxy ipapi)" ]; then
    if [ "$(g .proxy ipapi)" = true ]; then V="${X}oui${R}"; else V="${G}non${R}"; fi
    [ "$(g .hosting ipapi)" = true ] && V="$V ${D}(hébergeur)${R}"
    row "Proxy / VPN" "$V ${D}— ip-api, secours : proxycheck $(etat proxy)${R}"
  else
    row "Proxy / VPN" "$(indispo proxy "${QUOTA_TXT[proxycheck]}")"
  fi

  # Tor : on ne garde que les relais dont l'adresse correspond exactement
  if dispo tor; then
    TORPUB=$(g '.relays_published[0:16]' tor)
    TOR=$(jq -r --arg ip "$IPADDR" '
      [.relays[]? | select(((.or_addresses // []) + (.exit_addresses // []))
        | map(sub(":[0-9]+$"; "") | gsub("[\\[\\]]"; "") | ascii_downcase) | index($ip))]
      | if length == 0 then empty else
          (if any(.[]; .flags | index("Exit")) then "sortie" else "relais" end)
          + "|" + (map(.nickname) | .[0:4] | join(", "))
          + "|" + (map(.first_seen[0:10]) | min)
          + "|" + (map(.last_seen[0:16] // "") | max)
        end' "$TMP/tor" 2> /dev/null)
    if [ -n "$TOR" ]; then
      IFS='|' read -r TKIND TNOMS TDEPUIS TVU <<< "$TOR"
      if [ "$TKIND" = "sortie" ]; then
        row "Tor" "${X}nœud de sortie${R} ($TNOMS) ${D}depuis $TDEPUIS, vu le $TVU${R}"
      else
        row "Tor" "${Y}relais (pas de sortie)${R} ($TNOMS) ${D}depuis $TDEPUIS, vu le $TVU${R}"
      fi
    else
      row "Tor" "${G}non${R}${TORPUB:+ ${D}(liste publiée le $TORPUB UTC)${R}}"
    fi
  else
    row "Tor" "$(indispo tor)"
  fi

  if ! is_v4 "$IPADDR"; then
    row "Scanner" "${D}non couvert (GreyNoise : IPv4 seulement)${R}"
  elif dispo grey; then
    GMSG=$(g .message grey)
    if [ "$(g .noise grey)" = "true" ]; then
      GCL=$(g .classification grey); GNAME=$(g .name grey); GLAST=$(g .last_seen grey)
      case "$GCL" in malicious) GC="$X" ;; benign) GC="$G" ;; *) GC="$Y" ;; esac
      row "Scanner" "${GC}scanne Internet — $GCL${R}${GNAME:+ ($GNAME)}${GLAST:+ ${D}dernier scan vu le $GLAST${R}}"
    elif [ "$(g .riot grey)" = "true" ]; then
      row "Scanner" "${G}service connu et légitime${R} ($(g .name grey))"
    elif [ "$(g .noise grey)" = "false" ]; then
      row "Scanner" "${G}jamais vu en train de scanner${R} ${D}(GreyNoise)${R}"
    elif [ -n "$GMSG" ]; then
      row "Scanner" "${D}GreyNoise : $GMSG${R}"
    fi
  else
    row "Scanner" "$(indispo grey "GreyNoise communautaire")"
  fi

  if is_v4 "$IPADDR"; then
    LISTEES=(); REFUS=(); PANNES=(); NDIR=0
    for Z in "${DNSBL[@]}"; do
      case "$(bl_etat "$Z")" in
        listee) LISTEES+=("$Z") ;;
        refus) REFUS+=("$Z") ;;
        panne|absent) PANNES+=("$Z") ;;
      esac
      [ "$(head -1 "$TMP/bl_$Z" 2> /dev/null)" = direct ] && NDIR=$((NDIR + 1))
    done
    NBL=${#DNSBL[@]}
    NOK=$((NBL - ${#REFUS[@]} - ${#PANNES[@]}))
    DET="$NOK/$NBL vérifiées, $NDIR en direct"
    [ ${#REFUS[@]} -gt 0 ] && DET="$DET, refus : ${REFUS[*]}"
    [ ${#PANNES[@]} -gt 0 ] && DET="$DET, sans réponse : ${PANNES[*]}"
    if [ ${#LISTEES[@]} -gt 0 ]; then
      row "Listes noires" "${X}listée sur ${LISTEES[*]}${R} ${D}($DET)${R}"
    else
      row "Listes noires" "${G}propre${R} ${D}($DET)${R}"
    fi
    [ ${#REFUS[@]} -gt 0 ] && \
      row "  conseil" "${D}ton résolveur est refusé (résolveur public ?) → --dnsbl-resolver <IP>${R}"
  fi
fi

# ── Routage BGP (RIPEstat, secours Team Cymru) ──────────────────
if on bgp; then
  titre bgp "󰛳  Routage BGP" prefix routing neigh rpki
  if [ -z "$ASN" ]; then
    row "Préfixe" "${D}aucun AS trouvé (IP non routée, ou RIPEstat et Team Cymru muets)${R}"
  elif dispo prefix; then
    if [ -n "$PREFIXE" ]; then
      row "Préfixe" "$PREFIXE ${D}annoncé par AS$ASN${R}"
    else
      row "Préfixe" "${Y}non annoncé sur Internet${R}"
    fi
    row "Bloc parent" "$(jq -r '.data.block | if .resource then "\(.resource) — \(.desc | if length > 60 then .[0:60] + "…" else . end)" else empty end' "$TMP/prefix" 2> /dev/null)"
  else
    row "Préfixe" "${CY_PREFIX:-?} ${D}annoncé par AS$ASN${CY_NOM:+ ($CY_NOM)} — Team Cymru, RIPEstat muet${R}"
    row "Registre" "${CY_REG:+$CY_REG}${CY_DATE:+ ${D}(attribué le $CY_DATE)${R}}"
  fi
  if [ -n "$ASN" ]; then
    case "$(g .data.status rpki)" in
      valid) row "RPKI" "${G}valide${R} ${D}(route signée, protégée contre le détournement)${R}" ;;
      invalid*) row "RPKI" "${X}INVALIDE${R} ${D}(route non autorisée — détournement ?)${R}" ;;
      unknown) row "RPKI" "${Y}aucune signature ROA${R}" ;;
    esac
    if dispo routing; then
      row "Espace annoncé" "$(jq -r '.data.announced_space | select(.v4) |
        "\(.v4.prefixes) préfixes v4 (\(.v4.ips) IP), \(.v6.prefixes) v6"' "$TMP/routing" 2> /dev/null)"
      row "Visibilité" "$(jq -r '.data.visibility.v4 | select(.total_ris_peers) |
        "\(.ris_peers_seeing)/\(.total_ris_peers) routeurs RIS voient l AS"' "$TMP/routing" 2> /dev/null | sed "s/l AS/l'AS/")"
      row "AS actif depuis" "$(g '.data.first_seen.time[0:10]' routing)"
    elif dispo prefix; then
      row "Routage" "$(indispo routing)"
    fi
    if dispo neigh; then
      row "Voisins" "$(jq -r '.data.neighbour_counts | select(.unique) |
        "\(.unique) au total — \(.left) amont, \(.right) aval"' "$TMP/neigh" 2> /dev/null)"
      UPS=()
      for U in "${AMONTS[@]}"; do
        UPS+=("AS$U $(g .data.holder "up_$U" | sed 's/^[A-Z0-9-]* - //' | cut -c1-24 | sed 's/ *$//')")
      done
      [ ${#UPS[@]} -gt 0 ] && row "Transitaires" "$(joinv "${UPS[@]}")"
    fi
  fi
fi

# ── Opérateur (PeeringDB) ───────────────────────────────────────
if on op; then
  titre op "󰒍  Opérateur (PeeringDB)" pdb
  if [ -z "$ASN" ]; then
    row "Opérateur" "${D}AS inconnu${R}"
  elif ! dispo pdb; then
    row "PeeringDB" "$(indispo pdb "accès anonyme limité")"
  elif [ -z "$(g '.data[0].name' pdb)" ]; then
    row "PeeringDB" "${D}AS$ASN non inscrit${R}"
  else
    row "Nom" "$(g '.data[0].name' pdb)"
    row "Aussi connu" "$(g '.data[0].aka' pdb | cut -c1-60)"
    row "Type" "$(g '.data[0].info_type' pdb)"
    row "Portée" "$(g '.data[0].info_scope' pdb)"
    TRAFIC=$(g '.data[0].info_traffic' pdb); RATIO=$(g '.data[0].info_ratio' pdb)
    row "Trafic" "${TRAFIC}${TRAFIC:+${RATIO:+ — }}${RATIO:+${D}$RATIO${R}}"
    row "Peering" "$(g '.data[0].policy_general' pdb)"
    row "Présence" "$(jq -r '.data[0] | "\(.ix_count) points d échange (IX), \(.fac_count) datacenters"' "$TMP/pdb" 2> /dev/null | sed "s/d échange/d'échange/")"
    row "Site web" "$(g '.data[0].website' pdb)"
    row "Fiche màj" "${D}$(g '.data[0].updated[0:10]' pdb)${R}"
  fi
fi

# ── Propriétaire du bloc (RDAP) ─────────────────────────────────
if on rdap; then
  titre rdap "󰈙  Propriétaire du bloc (RDAP)" rdap
  if [ -n "$(g .handle rdap)" ]; then
    row "Nom réseau" "$(g .name rdap)"
    row "Handle" "$(g .handle rdap)"
    row "Plage" "$(jq -r 'if .startAddress then "\(.startAddress) – \(.endAddress)" else empty end' "$TMP/rdap" 2> /dev/null)"
    row "CIDR" "$(jq -r '[.cidr0_cidrs[]? | "\(.v4prefix // .v6prefix)/\(.length)"] | join(", ")' "$TMP/rdap" 2> /dev/null)"
    row "Titulaire" "$(jq -r '[.entities[]? | select(.roles | index("registrant")) | .vcardArray[1][]? | select(.[0] == "fn") | .[3]] | first // empty' "$TMP/rdap" 2> /dev/null)"
    row "Adresse" "$(jq -r '[.entities[]? | select(.roles | index("registrant")) | .vcardArray[1][]? | select(.[0] == "adr") | .[1].label // empty] | first // empty' "$TMP/rdap" 2> /dev/null | tr '\n' ' ' | sed 's/ *$//')"
    row "Description" "$(jq -r '[.remarks[]?.description[]?] | .[0:2] | join(" / ")' "$TMP/rdap" 2> /dev/null)"
    row "Registre" "$(g .port43 rdap)"
    row "Attribué le" "$(jq -r '[.events[]? | select(.eventAction == "registration") | .eventDate[0:10]] | first // empty' "$TMP/rdap" 2> /dev/null)"
    row "Modifié le" "$(jq -r '[.events[]? | select(.eventAction == "last changed") | .eventDate[0:10]] | first // empty' "$TMP/rdap" 2> /dev/null)"
    row "Abuse" "$(jq -r '[.. | objects | select((.roles? // []) | index("abuse")) | .vcardArray[1][]? | select(.[0] == "email") | .[3]] | unique | join(", ")' "$TMP/rdap" 2> /dev/null)"
  else
    row "RDAP" "$(indispo rdap) ${D}— rdap.org, RIPE et ARIN essayés${R}"
  fi
fi

# ── Exposition (Shodan InternetDB + domaines hébergés) ──────────
if on expo; then
  titre expo "󰖟  Exposition" shodan revip
  if ! dispo shodan; then
    row "Shodan" "$(indispo shodan)"
  elif [ -n "$(g .ip shodan)" ]; then
    row "Ports ouverts" "$(jq -r '.ports | map(tostring) | join(", ")' "$TMP/shodan" 2> /dev/null)"
    row "Noms d'hôte" "$(jq -r '.hostnames[0:5] | join(", ")' "$TMP/shodan" 2> /dev/null)"
    row "Tags" "$(jq -r '.tags | join(", ")' "$TMP/shodan" 2> /dev/null)"
    row "Logiciels" "$(jq -r '[.cpes[] | sub("^cpe:/[aoh]:"; "")] | .[0:6] | join(", ")' "$TMP/shodan" 2> /dev/null)"
    NV=$(jq -r '.vulns | length' "$TMP/shodan" 2> /dev/null)
    if [[ $NV =~ ^[0-9]+$ ]] && [ "$NV" -gt 0 ]; then
      row "Vulnérabilités" "${X}$NV CVE${R} ${D}$(jq -r '.vulns[0:5] | join(", ")' "$TMP/shodan")$([ "$NV" -gt 5 ] && printf ' …')${R}"
    fi
  else
    row "Shodan" "${D}aucune donnée (rien d'exposé ou pas encore scanné)${R}"
  fi
  if ! dispo revip; then
    row "Domaines" "$(indispo revip "HackerTarget ${QUOTA_TXT[hackertarget]}")"
  elif grep -qiE 'no (dns )?(a )?records' "$TMP/revip"; then
    row "Domaines" "${D}aucun domaine connu sur cette IP${R}"
  else
    ND=$(grep -c . "$TMP/revip")
    row "Domaines" "${B}$ND${R} hébergé(s) : $(head -8 "$TMP/revip" | paste -sd, - | sed 's/,/, /g')$([ "$ND" -gt 8 ] && printf ' …')"
  fi
fi

# ── Sondes actives ──────────────────────────────────────────────
if [ "$ACTIF" = 1 ]; then
  titre actif "󰓅  Sondes actives"
  PERTE=$(sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' "$TMP/ping")
  MOY=$(sed -n 's|^rtt [^=]*= [0-9.]*/\([0-9.]*\)/.*|\1|p' "$TMP/ping")
  TTL=$(sed -n 's/.*ttl=\([0-9]*\).*/\1/p' "$TMP/ping" | head -1)
  if [ -n "$MOY" ]; then
    row "Ping" "$MOY ms ${D}(perte $PERTE %)${R}"
  else
    row "Ping" "${D}pas de réponse ICMP (filtré)${R}"
  fi
  if [ -n "$TTL" ]; then
    if [ "$TTL" -le 64 ]; then OS="Linux / Unix / box"; INIT=64
    elif [ "$TTL" -le 128 ]; then OS="Windows"; INIT=128
    else OS="équipement réseau"; INIT=255; fi
    row "TTL" "$TTL ${D}→ probablement $OS, ~$((INIT - TTL)) sauts${R}"
  fi
  HSTAT=$(head -1 "$TMP/http" | tr -d '\r')
  if [ -n "$HSTAT" ]; then
    row "HTTP" "$HSTAT"
    for H in server x-powered-by location; do
      V=$(grep -i "^$H:" "$TMP/http" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//')
      row "  $H" "$V"
    done
  else
    row "HTTP" "${D}pas de serveur web (80/443)${R}"
  fi
  if [ -s "$TMP/tls" ]; then
    row "Certificat" "$(sed -n 's/^subject=.*CN *= *\([^,]*\).*/\1/p' "$TMP/tls")"
    SAN=$(grep -A1 'Subject Alternative Name' "$TMP/tls" | tail -1 | sed 's/DNS://g; s/^ *//')
    NSAN=$(printf '%s' "$SAN" | tr ',' '\n' | grep -c .)
    row "  domaines" "$(printf '%s' "$SAN" | cut -d, -f1-6)$([ "$NSAN" -gt 6 ] && printf ' … (%s)' "$NSAN")"
    row "  émetteur" "$(sed -n 's/^issuer=.*O *= *\([^,]*\).*/\1/p' "$TMP/tls")"
    FIN=$(sed -n 's/^notAfter=//p' "$TMP/tls")
    [ -n "$FIN" ] && row "  expire le" "$(date -d "$FIN" '+%d/%m/%Y' 2> /dev/null || printf '%s' "$FIN")"
  fi
  row "SSH" "$(tr -d '\r' < "$TMP/ssh")"
fi

# ── Pied de page ────────────────────────────────────────────────
PROXY_ENV="${HTTPS_PROXY:-${https_proxy:-${ALL_PROXY:-${all_proxy:-}}}}"
ENCACHE=0
for F in "$TMP"/*.st; do read -r S _ < "$F"; [ "$S" = cache ] && ENCACHE=1; done
if [ "$MD" = 1 ]; then
  printf '\n## Liens\n\n- https://www.abuseipdb.com/check/%s\n- https://www.shodan.io/host/%s\n' "$IPADDR" "$IPADDR"
  [ -n "$ASN" ] && printf -- '- https://bgp.he.net/AS%s\n- https://viz.greynoise.io/ip/%s\n' "$ASN" "$IPADDR"
else
  printf "\n"; line
  printf "  ${D}Plus : https://www.abuseipdb.com/check/%s · https://www.shodan.io/host/%s${R}\n" "$IPADDR" "$IPADDR"
  [ -n "$ASN" ] && printf "  ${D}       https://bgp.he.net/AS%s · https://viz.greynoise.io/ip/%s${R}\n" "$ASN" "$IPADDR"
  [ -n "$PROXY_ENV" ] && printf "  ${D}HTTP via le proxy %s (DNS en direct)${R}\n" "${PROXY_ENV##*@}"
  [ "$ENCACHE" = 1 ] && printf "  ${D}Une partie vient du cache (%d h) — --refresh pour réinterroger${R}\n" $((CACHE_TTL / 3600))
  [ "$CACHE" = 0 ] && printf "  ${D}Cache désactivé : %s non inscriptible${R}\n" "$CACHE_DIR"
  [ "$ACTIF" = 0 ] && printf "  ${D}ipinfo -a %s → + ping, certificat TLS, serveur web, SSH${R}\n" "${HOTE:-$IPADDR}"
  printf "\n"
fi
fin_save
