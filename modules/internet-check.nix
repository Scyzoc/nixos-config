{ config, pkgs, ... }:

let
  quickshell = config.programs.quickshell.package;

  # Flux de mesure lu par le menu Quickshell (modules/quickshell-launcher/SpeedTest.qml).
  # Une ligne par évènement :
  #   phase <detect|ping|dl|ul>   début d'une étape
  #   offline <noroute|noreply>   pas d'internet (détecté en ~1 s)
  #   ping <moy ms> <gigue ms> <perte %>
  #   dl|ul <Mbit/s>              débit instantané (toutes les 250 ms)
  #   dl_done|ul_done <Mbit/s>    débit final (moyenne hors montée en charge)
  #   done
  speedtest-stream = pkgs.writeShellScriptBin "speedtest-stream" ''
    PING=${pkgs.iputils}/bin/ping
    CURL=${pkgs.curl}/bin/curl
    IP=${pkgs.iproute2}/bin/ip
    AWK=${pkgs.gawk}/bin/awk

    HOST="1.1.1.1"
    HOST2="8.8.8.8"
    DL_URL="https://speed.cloudflare.com/__down?bytes=50000000"
    UL_URL="https://speed.cloudflare.com/__up"
    MAX_T=8          # durée max de chaque mesure de débit (s)
    STREAMS=4        # connexions parallèles
    UL_FILE=$(mktemp -p "''${XDG_RUNTIME_DIR:-/tmp}" speedtest-ul.XXXXXX)

    cleanup() {
      kill $(jobs -p) 2>/dev/null
      rm -f "$UL_FILE"
    }
    trap cleanup EXIT TERM INT

    # ── Détection instantanée : route par défaut + 2 pings en parallèle ──
    echo "phase detect"
    IF=$($IP route show default 2>/dev/null | $AWK '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    if [ -z "$IF" ]; then
      echo "offline noroute"
      exit 0
    fi
    $PING -c2 -i0.3 -W1 -n "$HOST"  >/dev/null 2>&1 & p1=$!
    $PING -c2 -i0.3 -W1 -n "$HOST2" >/dev/null 2>&1 & p2=$!
    ok=1
    wait $p1 && ok=0
    wait $p2 && ok=0
    if [ "$ok" -ne 0 ]; then
      echo "offline noreply"
      exit 0
    fi

    # ── Latence / gigue / perte ──
    echo "phase ping"
    OUT=$($PING -c8 -i0.2 -W1 -n "$HOST" 2>&1)
    LOSS=$(echo "$OUT" | ${pkgs.gnugrep}/bin/grep -oP '\d+(?=% packet loss)')
    STATS=$(echo "$OUT" | ${pkgs.gnugrep}/bin/grep -oP 'rtt min/avg/max/mdev = [0-9.]+/[0-9.]+/[0-9.]+/\K[0-9.]+')
    AVG=$(echo "$OUT" | ${pkgs.gnugrep}/bin/grep -oP 'rtt min/avg/max/mdev = [0-9.]+/\K[0-9.]+')
    echo "ping ''${AVG:-0} ''${STATS:-0} ''${LOSS:-100}"

    # ── Mesure de débit par compteur d'octets de l'interface ──
    # measure <dl|ul> <rx_bytes|tx_bytes>
    measure() {
      local kind=$1 stat=/sys/class/net/$IF/statistics/$2
      local prev tprev t0 now cur mbps sum=0 n=0 ticks=0 all=0
      echo "phase $kind"
      prev=$(cat "$stat"); t0=$(date +%s%N); tprev=$t0
      while :; do
        sleep 0.25
        now=$(date +%s%N); cur=$(cat "$stat")
        mbps=$($AWK -v d=$((cur - prev)) -v ns=$((now - tprev)) 'BEGIN { printf "%.2f", d * 8 * 1000 / ns }')
        prev=$cur; tprev=$now
        echo "$kind $mbps"
        ticks=$((ticks + 1))
        all=$($AWK -v a="$all" -v m="$mbps" 'BEGIN { print a + m }')
        # les ~1,25 premières secondes (montée en charge TCP) ne comptent pas dans la moyenne
        if [ "$ticks" -gt 5 ]; then
          sum=$($AWK -v a="$sum" -v m="$mbps" 'BEGIN { print a + m }')
          n=$((n + 1))
        fi
        [ $(( (now - t0) / 1000000 )) -ge $((MAX_T * 1000)) ] && break
        [ -z "$(jobs -r)" ] && break
      done
      kill $(jobs -p) 2>/dev/null
      wait 2>/dev/null
      if [ "$n" -gt 0 ]; then
        $AWK -v s="$sum" -v n="$n" -v k="$kind" 'BEGIN { printf "%s_done %.2f\n", k, s / n }'
      else
        $AWK -v s="$all" -v n="$ticks" -v k="$kind" 'BEGIN { printf "%s_done %.2f\n", k, (n > 0 ? s / n : 0) }'
      fi
    }

    for _ in $(seq $STREAMS); do
      $CURL -s -o /dev/null -m "$MAX_T" "$DL_URL" &
    done
    measure dl rx_bytes

    head -c 25000000 /dev/zero > "$UL_FILE"
    for _ in $(seq $STREAMS); do
      $CURL -s -o /dev/null -m "$MAX_T" --data-binary @"$UL_FILE" "$UL_URL" &
    done
    measure ul tx_bytes

    echo "done"
  '';

  # SUPER+I : affiche / masque le test de débit (menu Quickshell du service launcher)
  internet-check = pkgs.writeShellScriptBin "internet-check" ''
    ${quickshell}/bin/quickshell ipc -c launcher call speedtest toggle >/dev/null 2>&1
  '';
in
{
  home.packages = [ speedtest-stream internet-check ];
}
