import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// CPU / RAM ; clic : détails + processus gourmands ; clic droit : bascule CPU/RAM
Pill {
    id: root

    property string mode: "cpu"
    property real cpu: 0
    property real ram: 0
    property real ramUsed: 0
    property real ramTotal: 0
    property var lastTotal: 0
    property var lastIdle: 0
    property var topProcs: []

    readonly property bool critical: cpu > 0.8 || ram > 0.85

    tooltip: "Processeur " + Math.round(cpu * 100) + " %\nMémoire " + ramUsed.toFixed(1) + " / " + ramTotal.toFixed(1) + " Go"
    readonly property bool showRam: (mode === "ram" && !(cpu > 0.8)) || ram > 0.85

    alert: critical

    Process {
        id: statProc
        command: [Paths.cat, "/proc/stat", "/proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const c = lines[0].split(/\s+/).slice(1).map(Number);
                const idle = c[3] + c[4];
                const total = c.reduce((a, b) => a + b, 0);
                if (root.lastTotal > 0 && total > root.lastTotal)
                    root.cpu = 1 - (idle - root.lastIdle) / (total - root.lastTotal);
                root.lastTotal = total;
                root.lastIdle = idle;

                const mem = {};
                for (const l of lines) {
                    const m = l.match(/^(\w+):\s+(\d+)/);
                    if (m) mem[m[1]] = Number(m[2]);
                }
                if (mem.MemTotal) {
                    root.ramTotal = mem.MemTotal / 1048576;
                    root.ramUsed = (mem.MemTotal - mem.MemAvailable) / 1048576;
                    root.ram = root.ramUsed / root.ramTotal;
                }
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: statProc.running = true }

    Process {
        id: topProc
        command: [Paths.top, "-b", "-n", "2", "-d", "0.5", "-o", "%CPU", "-e", "m", "-w", "256"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                // Colonnes : PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND
                const blocks = text.split(/^\s*PID\s+USER.*$/m);
                const rows = blocks[blocks.length - 1].trim().split("\n").slice(0, 6);
                root.topProcs = rows.map(l => {
                    const p = l.trim().split(/\s+/);
                    const unit = { k: 1 / 1048576, m: 1 / 1024, g: 1, t: 1024 }[p[5].slice(-1)] ?? 1 / 1024;
                    return { name: p.slice(11).join(" "), cpu: parseFloat(p[8]), mem: parseFloat(p[5]) * unit };
                });
            }
        }
    }
    Timer { interval: 2000; running: popup.visible; repeat: true; triggeredOnStart: true; onTriggered: topProc.running = true }

    readonly property color tint: root.critical ? Theme.red : (root.showRam ? Theme.pink : Theme.blue)
    BarText { text: root.showRam ? Theme.ic(0xf0f86) : Theme.ic(0xf035b); color: root.tint }
    // Chiffres à chasse fixe (tnum) : la pastille ne bouge pas à chaque relevé
    BarText {
        visible: !root.compact
        text: Math.round((root.showRam ? root.ram : root.cpu) * 100) + "%"
        color: root.tint
        font.family: Theme.labelFont
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }

    onClicked: event => {
        if (event.button === Qt.RightButton) mode = mode === "cpu" ? "ram" : "cpu";
        else popup.toggle();
    }

    BarPopup {
        id: popup
        target: root
        contentWidth: 300

        PopupHeader { title: "Système" }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                BarText { text: Theme.ic(0xf035b) + "  Processeur"; color: Theme.blue; Layout.fillWidth: true; font.family: Theme.labelFont }
                BarText { text: Math.round(root.cpu * 100) + "%"; font.family: Theme.labelFont }
            }
            Slider { Layout.fillWidth: true; interactive: false; value: root.cpu; accent: root.cpu > 0.8 ? Theme.red : Theme.blue }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                BarText { text: Theme.ic(0xf0f86) + "  Mémoire"; color: Theme.pink; Layout.fillWidth: true; font.family: Theme.labelFont }
                BarText { text: root.ramUsed.toFixed(1) + " / " + root.ramTotal.toFixed(1) + " Go"; font.family: Theme.labelFont }
            }
            Slider { Layout.fillWidth: true; interactive: false; value: root.ram; accent: root.ram > 0.85 ? Theme.red : Theme.pink }
        }

        Separator {}
        BarText { text: "Processus les plus actifs"; color: Theme.subtext; font.pixelSize: 12; font.family: Theme.labelFont }

        Repeater {
            model: root.topProcs
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                BarText { text: modelData.name; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 12; font.family: Theme.labelFont }
                BarText { text: modelData.cpu.toFixed(1) + "%"; color: Theme.blue; font.pixelSize: 12; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight; font.family: Theme.labelFont }
                BarText { text: modelData.mem.toFixed(1) + " Go"; color: Theme.pink; font.pixelSize: 12; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight; font.family: Theme.labelFont }
            }
        }

        ActionButton {
            Layout.alignment: Qt.AlignRight
            icon: Theme.ic(0xf0128)
            label: "Ouvrir btop"
            onClicked: {
                popup.visible = false;
                Hyprland.dispatch("exec [float; center; size 1100 700] kitty -e btop");
            }
        }
    }
}
