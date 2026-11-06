pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Enregistrement vocal en cours (voice-to-text, SUPER+SHIFT+V ou assistant) : le script crée
// /tmp/voice_to_text.lock (enregistrement) puis /tmp/voice_to_text.state (busy/done/sent/error) ;
// on les surveille ici, et cava (micro) ne tourne que pendant l'enregistrement.
Singleton {
    id: root

    readonly property int bars: 20
    // rec (micro ouvert) → busy (transcription) → done / sent (collé / envoyé) ou error ; "" = rien
    property string phase: ""
    readonly property bool active: phase !== ""
    property real startMs: 0
    property real now: Date.now()
    property var levels: []
    // Texte transcrit en direct (assets/voice-live.py → /tmp/voice_live.txt)
    property string live: ""
    readonly property int elapsed: startMs > 0 ? Math.max(0, Math.floor((now - startMs) / 1000)) : 0
    readonly property string clock: {
        const p = n => (n < 10 ? "0" : "") + n;
        return p(Math.floor(elapsed / 60)) + ":" + p(elapsed % 60);
    }

    Process {
        id: probe
        command: [Paths.sh, "-c", "s=$(" + Paths.stat + " -c %Y /tmp/voice_to_text.lock 2>/dev/null); echo \"${s:-0} $(cat /tmp/voice_to_text.state 2>/dev/null)\"; cat /tmp/voice_live.txt 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n");
                const p = (nl < 0 ? text : text.slice(0, nl)).trim().split(" ");
                root.live = nl < 0 ? "" : text.slice(nl + 1).trim();
                const t = parseInt(p[0]) || 0;
                if (t > 0) {
                    if (root.phase !== "rec") { root.startMs = t * 1000; root.now = Date.now(); }
                    root.phase = "rec";
                } else {
                    root.phase = p[1] ?? "";
                }
            }
        }
    }
    Timer {
        interval: 200
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }
    Timer {
        interval: 250
        repeat: true
        running: root.phase === "rec"    // arrêté ensuite : la durée reste figée pendant le fondu
        onTriggered: root.now = Date.now()
    }

    Process {
        running: root.phase === "rec"
        command: [Paths.sh, "-c", "c=$(mktemp); printf '[general]\\nbars=" + root.bars + "\\nframerate=60\\n[input]\\nmethod=pulse\\nsource=default\\n[output]\\nmethod=raw\\ndata_format=ascii\\nascii_max_range=100\\nbar_delimiter=59\\n[smoothing]\\nnoise_reduction=60\\n' > \"$c\"; exec " + Paths.cava + " -p \"$c\""]
        stdout: SplitParser {
            onRead: line => root.levels = line.split(";").filter(x => x !== "").map(Number)
        }
        onRunningChanged: if (!running) root.levels = []
    }
}
