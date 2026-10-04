{ config, lib, pkgs, ... }:

let
  # Arrêt / veille programmés via timers systemd utilisateur (survit à un redémarrage de la barre)
  #   power-schedule poweroff|suspend <minutes>   programme l'action
  #   power-schedule cancel                       annule
  #   power-schedule status                       affiche "<action> <epoch>" ou rien
  power-schedule = pkgs.writeShellScript "power-schedule" ''
    SYSTEMCTL=/run/current-system/sw/bin/systemctl
    RUN=/run/current-system/sw/bin/systemd-run
    DATE=${pkgs.coreutils}/bin/date
    NOTIFY=${pkgs.libnotify}/bin/notify-send

    if [ "$1" = status ]; then
      [ "$($SYSTEMCTL --user is-active qs-power.timer 2>/dev/null)" = active ] || exit 0
      $SYSTEMCTL --user show qs-power.timer -p Description --value | ${pkgs.gnused}/bin/sed -n 's/^qs-power:\([a-z]*\):\([0-9]*\)$/\1 \2/p'
      exit 0
    fi

    $SYSTEMCTL --user stop qs-power.timer qs-power-warn.timer 2>/dev/null
    $SYSTEMCTL --user reset-failed qs-power.service qs-power-warn.service 2>/dev/null

    if [ "$1" = cancel ]; then
      $NOTIFY -a "Alimentation" "Programmation annulée"
      exit 0
    fi

    ACTION="$1"; MIN="$2"
    case "$ACTION" in
      poweroff) LABEL="Arrêt" ;;
      suspend)  LABEL="Mise en veille" ;;
      reboot)   LABEL="Redémarrage" ;;
      *) exit 1 ;;
    esac

    AT=$($DATE -d "+$MIN min" '+%Y-%m-%d %H:%M:%S')
    EPOCH=$($DATE -d "$AT" +%s)
    $RUN --user --quiet --unit=qs-power --description="qs-power:$ACTION:$EPOCH" \
      --on-calendar="$AT" $SYSTEMCTL "$ACTION"

    # Avertissement 1 minute avant
    if [ "$MIN" -gt 1 ]; then
      WARN=$($DATE -d "$AT 1 min ago" '+%Y-%m-%d %H:%M:%S')
      $RUN --user --quiet --unit=qs-power-warn --on-calendar="$WARN" \
        $NOTIFY -a "Alimentation" -u critical "$LABEL dans 1 minute" "Annule-le depuis le bouton d'alimentation de la barre"
    fi

    $NOTIFY -a "Alimentation" "$LABEL programmé" "À $($DATE -d "$AT" +%H:%M)"
  '';

  # Config IPv4 de la connexion Wi-Fi active (DHCP ou statique) via nmcli
  #   net-ipconfig show <interface>                          -> lignes clé=valeur
  #   net-ipconfig set <connexion> auto
  #   net-ipconfig set <connexion> manual <ip/prefix> <passerelle> <dns>
  net-ipconfig = pkgs.writeShellScript "net-ipconfig" ''
    NMCLI=${pkgs.networkmanager}/bin/nmcli
    SED=${pkgs.gnused}/bin/sed
    NOTIFY=${pkgs.libnotify}/bin/notify-send

    case "$1" in
      show)
        IF="$2"
        CONN=$($NMCLI -g GENERAL.CONNECTION dev show "$IF" 2>/dev/null)
        [ -z "$CONN" ] && exit 1
        printf 'conn=%s\n' "$CONN"
        printf 'method=%s\n' "$($NMCLI -g ipv4.method con show "$CONN")"
        printf 'addr=%s\n' "$($NMCLI -g IP4.ADDRESS dev show "$IF" | $SED 's/ | .*//')"
        printf 'gw=%s\n' "$($NMCLI -g IP4.GATEWAY dev show "$IF")"
        printf 'dns=%s\n' "$($NMCLI -g IP4.DNS dev show "$IF" | $SED 's/ | /, /g')"
        ;;
      set)
        CONN="$2"; METHOD="$3"
        if [ "$METHOD" = auto ]; then
          ERR=$($NMCLI con mod "$CONN" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns "" 2>&1)
          LABEL="DHCP"
        else
          DNS=$(echo "$6" | ${pkgs.coreutils}/bin/tr -s ' ,' ',' | $SED 's/^,//; s/,$//')
          ERR=$($NMCLI con mod "$CONN" ipv4.method manual ipv4.addresses "$4" ipv4.gateway "$5" ipv4.dns "$DNS" 2>&1)
          LABEL="IP statique $4"
        fi
        if [ -n "$ERR" ]; then
          echo "$ERR"
          $NOTIFY -a "Réseau" -u critical "Configuration refusée" "$ERR"
          exit 1
        fi
        # Réactive la connexion pour appliquer
        if ERR=$($NMCLI con up "$CONN" 2>&1); then
          $NOTIFY -a "Réseau" "$CONN" "$LABEL appliqué"
        else
          echo "$ERR"
          $NOTIFY -a "Réseau" -u critical "Échec de reconnexion" "$ERR"
          exit 1
        fi
        ;;
    esac
  '';

  # Contrôle du bruit des AirPods (protocole Apple AAP, canal L2CAP PSM 0x1001)
  #   airpods-anc <MAC>   reste connecté : affiche le mode à chaque changement
  #                       (y compris depuis la tige) ; lit un mode par ligne sur stdin
  #   Modes : 1 désactivé, 2 réduction de bruit, 3 transparence, 4 adaptatif
  #   Batteries (au 1er échange puis à chaque changement), une ligne :
  #     « B L=85,0 R=90,1 C=40,0 »  (niveau %, 1 = en charge ; « L=- » : absent)
  airpods-anc = pkgs.writeScript "airpods-anc" ''
    #!${pkgs.python3}/bin/python3
    import select, socket, sys

    HANDSHAKE = bytes.fromhex("00000400010002000000000000000000")
    # Toutes les notifications (masque complet : sans le bit de « fffffeff », pas de batterie)
    NOTIFICATIONS = bytes.fromhex("040004000f00ffffffff")
    NOISE = bytes.fromhex("0400040009000d")
    BATTERY = bytes.fromhex("040004000400")
    # Élément : type, 01, niveau, état (1 en charge, 2 sur batterie, 4 absent), 01
    PARTS = {0x04: "L", 0x02: "R", 0x08: "C", 0x01: "S"}

    s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
    s.settimeout(10)
    try:
        s.connect((sys.argv[1], 0x1001))
    except OSError as e:
        print("erreur", e, file=sys.stderr)
        sys.exit(1)
    s.settimeout(None)
    s.send(HANDSHAKE)
    s.send(NOTIFICATIONS)

    while True:
        r, _, _ = select.select([s, sys.stdin], [], [])
        if s in r:
            try:
                p = s.recv(1024)
            except OSError:
                break
            if not p:
                break
            if p[:7] == NOISE and len(p) > 7:
                print(p[7], flush=True)
            elif p[:6] == BATTERY and len(p) > 6:
                out = []
                for i in range(p[6]):
                    c = p[7 + 5 * i:12 + 5 * i]
                    if len(c) < 5 or c[0] not in PARTS:
                        continue
                    absent = c[3] == 0x04 or c[2] > 100
                    out.append(PARTS[c[0]] + "=" + ("-" if absent else f"{c[2]},{int(c[3] == 0x01)}"))
                print("B " + " ".join(out), flush=True)
        if sys.stdin in r:
            line = sys.stdin.readline()
            if not line:
                break
            m = line.strip()
            if m in ("1", "2", "3", "4"):
                s.send(NOISE + bytes([int(m), 0, 0, 0]))
  '';

  # Chemins absolus des binaires utilisés par la barre (PATH non garanti sous systemd)
  paths = pkgs.writeText "Paths.qml" ''
    pragma Singleton
    import Quickshell

    Singleton {
        readonly property string curl: "${pkgs.curl}/bin/curl"
        readonly property string ip: "${pkgs.iproute2}/bin/ip"
        readonly property string cat: "${pkgs.coreutils}/bin/cat"
        readonly property string top: "${pkgs.procps}/bin/top"
        readonly property string hyprlock: "${pkgs.hyprlock}/bin/hyprlock"
        readonly property string systemctl: "/run/current-system/sw/bin/systemctl"
        readonly property string sudo: "/run/wrappers/bin/sudo"
        readonly property string userBin: "${config.home.profileDirectory}/bin"
        readonly property string powerSchedule: "${power-schedule}"
        readonly property string netIpconfig: "${net-ipconfig}"
        readonly property string nmcli: "${pkgs.networkmanager}/bin/nmcli"
        readonly property string rfkill: "${pkgs.util-linux}/bin/rfkill"
        readonly property string brightnessctl: "${pkgs.brightnessctl}/bin/brightnessctl"
        readonly property string airpodsAnc: "${airpods-anc}"
        readonly property string batteryLimit: "/run/current-system/sw/bin/battery-limit"
        readonly property string mkdir: "${pkgs.coreutils}/bin/mkdir"
        readonly property string notifySend: "${pkgs.libnotify}/bin/notify-send"
        readonly property string pwPlay: "${pkgs.pipewire}/bin/pw-play"
        readonly property string alarmSound: "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
        readonly property string stateDir: "${config.xdg.stateHome}/quickshell-bar"
    }
  '';

  # Config QML (modules/quickshell/) + Paths.qml généré
  barConfig = pkgs.runCommand "quickshell-bar" { } ''
    cp -r ${./quickshell} $out
    chmod -R u+w $out
    cp ${paths} $out/Paths.qml
  '';
in
{
  programs.quickshell = {
    enable = true;
    configs.bar = barConfig;
    activeConfig = "bar";
    # Barre principale : démarrée avec la session Hyprland
    systemd.enable = true;
    systemd.target = "hyprland-session.target";
  };
}
