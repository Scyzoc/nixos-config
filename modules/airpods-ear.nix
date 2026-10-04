{ config, pkgs, lib, ... }:

# Détection d'oreille AirPods : pause quand on retire un écouteur, reprise
# quand on le remet. Parle le protocole Apple AAP (L2CAP PSM 0x1001), pas de root.

let
  airpods-ear = pkgs.writeScriptBin "airpods-ear" ''
    #!${pkgs.python3}/bin/python3

    import json
    import select
    import socket
    import subprocess
    import time

    BLUETOOTHCTL = "${pkgs.bluez}/bin/bluetoothctl"
    PLAYERCTL = "${pkgs.playerctl}/bin/playerctl"
    WPCTL = "${pkgs.wireplumber}/bin/wpctl"
    PW_DUMP = "${pkgs.pipewire}/bin/pw-dump"
    FADE_OUT = 0.25        # durée du fondu à la pause (s)
    FADE_IN = 0.35         # durée du fondu à la reprise (s)
    FADE_STEPS = 8
    AAP_PSM = 0x1001
    APPLE_MODALIAS = "bluetooth:v004C"

    HANDSHAKE = bytes.fromhex("00000400010002000000000000000000")
    FEATURES = bytes.fromhex("040004004d00ff00000000000000")
    NOTIFY = bytes.fromhex("040004000f00ffffffff")
    EAR_PREFIX = bytes.fromhex("040004000600")
    IN_EAR = 0x00


    def run(*args):
        try:
            return subprocess.run(args, capture_output=True, text=True, timeout=5).stdout
        except Exception:
            return ""


    def find_airpods():
        # Premier appareil Apple connecté (Modalias vendeur 004C)
        for line in run(BLUETOOTHCTL, "devices", "Connected").splitlines():
            parts = line.split()
            if len(parts) >= 2 and APPLE_MODALIAS in run(BLUETOOTHCTL, "info", parts[1]):
                return parts[1]
        return None


    def playing_players():
        out = run(PLAYERCTL, "-a", "-f", "{{playerInstance}}|{{status}}", "metadata")
        players = []
        for line in out.splitlines():
            name, _, status = line.rpartition("|")
            if status == "Playing":
                players.append(name)
        return players


    # Le fondu agit sur le volume logiciel des flux applicatifs (Brave, Spotify…),
    # pas sur celui des AirPods : leur volume absolu Bluetooth passe en mute à 0
    # et renvoie des valeurs en retard qui écrasent la restauration.

    def output_streams():
        try:
            nodes = json.loads(run(PW_DUMP))
        except ValueError:
            return []
        return [n["id"] for n in nodes
                if n.get("info", {}).get("props", {}).get("media.class") == "Stream/Output/Audio"]


    def get_volume(node):
        try:
            return float(run(WPCTL, "get-volume", str(node)).split()[1])
        except (IndexError, ValueError):
            return None


    def set_volume(node, v):
        run(WPCTL, "set-volume", str(node), "%.3f" % v)


    def stream_volumes():
        vols = {}
        for node in output_streams():
            v = get_volume(node)
            if v is not None:
                vols[node] = v
        return vols


    def fade(vols, start, end, duration):
        # start/end : facteurs (0 → 1) appliqués au volume d'origine de chaque flux
        t0 = time.monotonic()
        for i in range(1, FADE_STEPS + 1):
            k = start + (end - start) * i / FADE_STEPS
            for node, v in vols.items():
                set_volume(node, v * k)
            # Cadencé sur l'horloge : les appels wpctl prennent déjà du temps
            time.sleep(max(0.0, t0 + duration * i / FADE_STEPS - time.monotonic()))


    def restore(vols):
        for node, v in vols.items():
            set_volume(node, v)


    def pause_all():
        players = playing_players()
        if not players:
            return players
        vols = stream_volumes()
        try:
            # Fondu sortant, puis pause
            fade(vols, 1.0, 0.0, FADE_OUT)
            for p in players:
                run(PLAYERCTL, "-p", p, "pause")
            time.sleep(0.1)
        finally:
            restore(vols)
        return players


    def resume(players):
        vols = stream_volumes()
        try:
            # Reprise à volume nul, puis fondu entrant
            for node in vols:
                set_volume(node, 0.0)
            for p in players:
                run(PLAYERCTL, "-p", p, "play")
            time.sleep(0.05)
            # Flux recréés par le lecteur à la reprise
            for node in output_streams():
                if node not in vols:
                    v = get_volume(node)
                    if v is not None:
                        vols[node] = v
                        set_volume(node, 0.0)
            fade(vols, 0.0, 1.0, FADE_IN)
        finally:
            restore(vols)


    def listen(mac):
        s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
        s.settimeout(10)
        s.connect((mac, AAP_PSM))
        s.settimeout(None)
        for pkt in (HANDSHAKE, FEATURES, NOTIFY):
            s.send(pkt)

        in_ear = None          # nombre d'écouteurs dans les oreilles
        paused = []            # lecteurs mis en pause par nous
        count_before = 0       # nombre d'écouteurs avant la pause

        try:
            while True:
                r, _, _ = select.select([s], [], [], 30)
                if not r:
                    continue
                data = s.recv(1024)
                if not data:
                    return
                if not data.startswith(EAR_PREFIX) or len(data) < 8:
                    continue

                count = (data[6] == IN_EAR) + (data[7] == IN_EAR)
                if in_ear is None:
                    in_ear = count
                    continue

                if count < in_ear and not paused:
                    # Écouteur retiré : pause ce qui joue
                    paused = pause_all()
                    count_before = in_ear
                elif count >= count_before and paused:
                    # Écouteur(s) remis : reprise
                    resume(paused)
                    paused = []
                in_ear = count
        finally:
            s.close()


    def main():
        while True:
            mac = find_airpods()
            if mac:
                try:
                    listen(mac)
                except OSError:
                    pass
            time.sleep(5)


    if __name__ == "__main__":
        main()
  '';

in
{
  home.packages = [ airpods-ear ];

  systemd.user.services.airpods-ear-detection = {
    Unit = {
      Description = "AirPods : pause/reprise selon détection d'oreille";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${airpods-ear}/bin/airpods-ear";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "hyprland-session.target" ];
    };
  };
}
