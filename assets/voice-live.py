#!/usr/bin/env python3
# Transcription en direct pendant la dictée (voice-to-text) : lance whisper-stream (micro) et
# écrit le texte courant dans /tmp/voice_live.txt, affiché par la barre (VoiceRec.qml).
# whisper-stream réécrit sa ligne avec « ESC[2K \r » à chaque pas et passe à la ligne quand
# une fenêtre est validée.
import os, re, signal, subprocess, sys, threading

LIVE = "/tmp/voice_live.txt"
NOISE = re.compile(r"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*")   # [Musique], (rires), *bruit*


def clean(s):
    return re.sub(r"\s+", " ", NOISE.sub("", s)).strip()


def write(text):
    tmp = LIVE + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, LIVE)


def main():
    model = sys.argv[1]
    proc = subprocess.Popen(
        ["whisper-stream", "-m", model, "-l", "fr", "-t", "4",
         "--step", "1500", "--length", "8000", "--keep", "300"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    # whisper-stream s'arrête sur SIGINT ; tué d'office s'il traîne
    def stop(*_):
        proc.send_signal(signal.SIGINT)
        threading.Timer(1.0, proc.kill).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    done, cur, buf, last = [], "", b"", None
    while True:
        chunk = proc.stdout.read1(4096)
        if not chunk:
            break
        buf += chunk
        while True:
            i_nl, i_cl = buf.find(b"\n"), buf.find(b"\x1b[2K\r")
            idx = [i for i in (i_nl, i_cl) if i >= 0]
            if not idx:
                break
            i = min(idx)
            cur += buf[:i].decode("utf-8", "replace")
            if i == i_nl:
                if clean(cur) and "Start speaking" not in cur:
                    done.append(clean(cur))
                cur, buf = "", buf[i + 1:]
            else:
                cur, buf = "", buf[i + 5:]
        text = " ".join(done + [clean(cur + buf.decode("utf-8", "replace"))]).strip()
        if text != last:
            write(text)
            last = text
    proc.wait()


if __name__ == "__main__":
    main()
