{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellScriptBin "internet-check" ''
      # ── Couleurs ANSI ──────────────────────────────────────────
      R='\e[0m';  BOLD='\e[1m';  DIM='\e[2m'
      BOX='\e[38;5;111m'     # bleu — cadre
      GRAY='\e[38;5;245m'    # gris — étiquettes
      WHITE='\e[38;5;255m'   # blanc — valeurs
      GREEN='\e[38;5;114m'   # vert — succès
      YELLOW='\e[38;5;221m'  # jaune — avertissement
      RED='\e[38;5;203m'     # rouge — erreur

      # ── Dimensions ────────────────────────────────────────────
      W=44   # largeur intérieure entre les deux │

      # ── Helpers ───────────────────────────────────────────────
      bar() { printf '─%.0s' $(seq 1 "$W"); }
      top() { printf "\n  $BOX╭$(bar)╮$R\n"; }
      mid() { printf "  $BOX├$(bar)┤$R\n"; }
      bot() { printf "  $BOX╰$(bar)╯$R\n"; }

      blank() { printf "  $BOX│$R%*s$BOX│$R\n" "$W" ""; }

      # Longueur visible UTF-8 (wc -m compte les caractères, pas les octets)
      vlen() { printf '%s' "$1" | wc -m; }

      # Padding à N colonnes visibles
      pad() {
        local str="$1" target="$2"
        local n; n=$(vlen "$str")
        local sp=$(( target - n < 0 ? 0 : target - n ))
        printf '%s%*s' "$str" "$sp" ""
      }

      # Ligne avec label (11 cols) + valeur (29 cols)
      row() {
        local label="$1" value="$2" color="''${3:-$WHITE}"
        local l; l=$(pad "$label" 11)
        local v; v=$(pad "$value" 29)
        printf "  $BOX│$R  $GRAY%s$R  $color$BOLD%s$R$BOX│$R\n" "$l" "$v"
      }

      # Ligne centrée (texte sans ANSI pour mesure correcte)
      center() {
        local text="$1" color="''${2:-$WHITE}"
        local len; len=$(vlen "$text")
        local lp=$(( (W - len) / 2 ))
        local rp=$(( W - len - lp ))
        printf "  $BOX│$R%*s$color$BOLD%s$R%*s$BOX│$R\n" "$lp" "" "$text" "$rp" ""
      }

      # ── Paramètres ────────────────────────────────────────────
      HOST="1.1.1.1"
      COUNT=4

      # ── Affichage pendant le ping ─────────────────────────────
      clear
      top
      blank
      center "  VERIFICATION RESEAU"
      blank
      mid
      blank
      row "Hote"   "$HOST  Cloudflare"
      row "Statut" "Envoi de $COUNT paquets..." "$GRAY"
      blank
      bot

      RESULT=$(ping -c "$COUNT" -W 2 "$HOST" 2>&1)

      # ── Affichage des résultats ───────────────────────────────
      clear
      top
      blank
      center "  VERIFICATION RESEAU"
      blank
      mid
      blank
      row "Hote" "$HOST  Cloudflare"

      if echo "$RESULT" | grep -qE "Network is unreachable|connect: Network"; then
        blank
        mid
        blank
        center "  AUCUNE INTERFACE RESEAU" "$RED"
        blank
        bot
        printf "\n  $DIM$GRAY Appuyez sur une touche pour fermer...$R\n\n"
        read -rn1
        exit 0
      fi

      PACKET_LOSS=$(echo "$RESULT" | grep -oP '\d+(?=% packet loss)')
      RTT_MIN=$(echo "$RESULT"     | grep -oP 'rtt min/avg/max/mdev = \K[0-9.]+')
      RTT_AVG=$(echo "$RESULT"     | grep -oP 'rtt min/avg/max/mdev = [0-9.]+/\K[0-9.]+')
      RTT_MAX=$(echo "$RESULT"     | grep -oP 'rtt min/avg/max/mdev = [0-9.]+/[0-9.]+/\K[0-9.]+')

      if [ -z "$PACKET_LOSS" ]; then
        blank
        mid
        blank
        center "  DIAGNOSTIC IMPOSSIBLE" "$RED"
        blank
        bot
        printf "\n  $DIM$GRAY Appuyez sur une touche pour fermer...$R\n\n"
        read -rn1
        exit 1
      fi

      RECV=$(( COUNT * (100 - PACKET_LOSS) / 100 ))

      if   [ "$PACKET_LOSS" -eq 0 ];  then LC=$GREEN
      elif [ "$PACKET_LOSS" -lt 50 ]; then LC=$YELLOW
      else                                 LC=$RED
      fi

      row "Latence"  "$RTT_MIN / $RTT_AVG / $RTT_MAX ms"
      row "Paquets"  "$RECV / $COUNT recus"
      row "Perte"    "$PACKET_LOSS%" "$LC"
      blank
      mid
      blank

      if   [ "$PACKET_LOSS" -eq 0 ];   then center "  INTERNET -> OK"   "$GREEN"
      elif [ "$PACKET_LOSS" -lt 100 ]; then center "  INSTABLE" "$YELLOW"
      else                                  center "  PAS D'INTERNET"   "$RED"
      fi

      blank
      bot
      printf "\n  $DIM$GRAY Appuyez sur une touche pour fermer...$R\n\n"
      read -rn1
    '')
  ];
}
