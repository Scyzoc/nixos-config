pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Enregistrement d'écran (screen-record, SUPER+SHIFT+Impr) : le script crée /tmp/screen_rec.lock
// (mtime = début) ; à l'arrêt il écrit /tmp/screen_rec.state = « done <fichier> » (→ doneFile,
// affiché ~5 s par l'île, Island.qml) ou « error » (croix à droite de l'heure, ScreenRec.qml).
Singleton {
    id: root

    // rec → error ; "" = rien (barre). La fin réussie passe par doneFile (île, cliquable)
    property bool recording: false
    property bool failed: false
    readonly property string phase: recording ? "rec" : failed ? "error" : ""
    readonly property bool active: phase !== ""
    property real startMs: 0
    property real now: Date.now()
    readonly property int elapsed: startMs > 0 ? Math.max(0, Math.floor((now - startMs) / 1000)) : 0
    readonly property string clock: {
        const p = n => (n < 10 ? "0" : "") + n;
        return p(Math.floor(elapsed / 60)) + ":" + p(elapsed % 60);
    }
    // Dernier enregistrement / dernière capture terminés (vidé par l'île après ~5 s)
    property string doneFile: ""
    property string doneKind: "record"     // record | shot
    property string doneLabel: ""
    property string lastShot: ""
    property string lastDone: ""
    property bool menuOpen: false          // menu déroulant (enregistrer sous / copier / dessiner) de l'île capture
    onDoneFileChanged: if (doneFile === "") menuOpen = false

    function open() {
        opener.command = root.doneKind === "shot" ? [Paths.userBin + "/screenshot", "--edit", root.doneFile]
                                                  : [Paths.userBin + "/screen-record", "open", root.doneFile];
        opener.running = true;
        root.doneFile = "";
    }

    // Action du menu de l'île. Capture : save | draw ; enregistrement : save | copy | folder
    function shotAction(kind) {
        const f = root.doneFile;
        if (root.doneKind === "shot")
            opener.command = [Paths.userBin + "/screenshot", kind === "save" ? "--save-as" : kind === "ocr" ? "--ocr" : "--edit", f];
        else
            opener.command = [Paths.userBin + "/screen-record", kind === "save" ? "save-as" : kind === "copy" ? "copy" : "open", f];
        opener.running = true;
        root.doneFile = "";
    }

    Process { id: opener }
    Timer {
        interval: 5000
        running: root.doneFile !== "" && !root.menuOpen
        onTriggered: root.doneFile = ""
    }

    Process {
        id: probe
        command: [Paths.sh, "-c", "s=$(" + Paths.stat + " -c %Y /tmp/screen_rec.lock 2>/dev/null); echo \"${s:-0} $(cat /tmp/screen_rec.state 2>/dev/null)\"; cat /tmp/screenshot.state 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                // Capture d'écran (screenshot) : « copy|save <fichier> »
                const shot = lines[1] ?? "";
                if (shot !== "" && shot !== root.lastShot) {
                    root.lastShot = shot;
                    root.doneKind = "shot";
                    root.doneLabel = shot.indexOf("save ") === 0 ? "Capture enregistrée" : "Capture copiée";
                    root.doneFile = shot.slice(5);
                }
                const p = lines[0].split(" ");
                const t = parseInt(p[0]) || 0;
                if (t > 0) {
                    if (!root.recording) { root.startMs = t * 1000; root.now = Date.now(); }
                    root.recording = true;
                    root.failed = false;
                    return;
                }
                const st = p.slice(1).join(" ");
                root.recording = false;
                root.failed = st === "error";
                if (st.indexOf("done ") === 0) {
                    const f = st.slice(5);
                    if (f !== root.lastDone) {
                        root.lastDone = f;
                        root.doneKind = "record";
                        root.doneLabel = "Enregistrement terminé";
                        root.doneFile = f;
                    }
                }
            }
        }
    }
    Timer {
        interval: 300
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }
    Timer {
        interval: 250
        repeat: true
        running: root.recording
        onTriggered: root.now = Date.now()
    }
}
