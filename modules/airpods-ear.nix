{ config, pkgs, lib, ... }:

# Pause/reprise (avec fondu) des lecteurs quand on retire/remet un AirPod.
#   airpods-ear pause    met en pause ce qui joue, mémorise les lecteurs
#   airpods-ear resume   relance les lecteurs mis en pause
# La détection d'oreille vient de airpods-anc (quickshell.nix) : les AirPods
# n'acceptent qu'UNE connexion AAP, une seconde ne reçoit rien.

let
  airpods-ear = pkgs.writeScriptBin "airpods-ear" ''
    #!${pkgs.python3}/bin/python3

    import fcntl
    import json
    import os
    import subprocess
    import sys
    import time

    PLAYERCTL = "${pkgs.playerctl}/bin/playerctl"
    WPCTL = "${pkgs.wireplumber}/bin/wpctl"
    PW_DUMP = "${pkgs.pipewire}/bin/pw-dump"
    FADE_OUT = 0.25        # durée du fondu à la pause (s)
    FADE_IN = 0.35         # durée du fondu à la reprise (s)
    FADE_STEPS = 8
    RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    STATE = RUNTIME + "/airpods-ear-paused"
    LOCK = RUNTIME + "/airpods-ear.lock"


    def run(*args):
        try:
            return subprocess.run(args, capture_output=True, text=True, timeout=5).stdout
        except Exception:
            return ""


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


    def main():
        if len(sys.argv) != 2 or sys.argv[1] not in ("pause", "resume"):
            sys.exit("usage : airpods-ear pause|resume")
        # Un seul appel à la fois : un « resume » rapide attend la fin du fondu
        with open(LOCK, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if sys.argv[1] == "pause":
                players = pause_all()
                if players:
                    with open(STATE, "w") as f:
                        json.dump(players, f)
            else:
                try:
                    with open(STATE) as f:
                        players = json.load(f)
                    os.remove(STATE)
                except (OSError, ValueError):
                    return
                resume(players)


    if __name__ == "__main__":
        main()
  '';

in
{
  home.packages = [ airpods-ear ];
}
