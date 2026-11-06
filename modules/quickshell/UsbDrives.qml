import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Disques / clés USB : visible seulement quand un support amovible est branché.
// Clic : menu par volume (monter / démonter / ouvrir / copier le chemin) et éjection du disque.
Pill {
    id: root

    // [{ path, name, tran, size, parts: [{ path, label, fstype, size, used, mp }] }]
    property var drives: []
    readonly property bool present: drives.length > 0
    readonly property int mountedCount: drives.reduce((n, d) => n + d.parts.filter(p => p.mp !== "").length, 0)
    // Volume en cours de montage / démontage (chemin du périphérique) ; "" = rien
    property string busyPath: ""

    implicitWidth: present ? icon.implicitWidth + hpad * 2 : 0
    opacity: present ? 1 : 0
    visible: present || implicitWidth > 0.5
    clip: true
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    tooltip: drives.length === 0 ? "" : drives.map(d => d.name).join("\n") + "\nClic : gérer les disques"

    function fmtSize(b) {
        b = Number(b) || 0;
        const u = ["o", "Ko", "Mo", "Go", "To"];
        let i = 0;
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
        return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)).toString().replace(".", ",") + " " + u[i];
    }

    // lsblk (JSON, octets) → disques amovibles avec leurs volumes (partitions ou disque entier formaté)
    function parse(txt) {
        let data;
        try { data = JSON.parse(txt).blockdevices; } catch (e) { return null; }
        const skipFs = ["crypto_LUKS", "LVM2_member", "swap", "linux_raid_member"];
        const out = [];
        for (const d of data) {
            if (d.type !== "disk" || !(d.hotplug || d.tran === "usb") || !(Number(d.size) > 0)) continue;
            const parts = [];
            const walk = n => {
                if (n.fstype && skipFs.indexOf(n.fstype) < 0)
                    parts.push({
                        path: n.path, label: n.label || "", fstype: n.fstype, size: Number(n.size) || 0,
                        used: n.fsused ? Number(n.fsused) : -1,
                        mp: (n.mountpoints || []).find(m => m && m[0] === "/") ?? ""
                    });
                (n.children || []).forEach(walk);
            };
            walk(d);
            // Modèle seul s'il contient déjà la marque (« INTEL SS » + « INTEL SSDPEK… »)
            const v = (d.vendor || "").trim(), m = (d.model || "").trim();
            const vm = m && v && m.toLowerCase().startsWith(v.split(" ")[0].toLowerCase()) ? m : [v, m].filter(s => s).join(" ");
            out.push({ path: d.path, name: vm || d.name, tran: d.tran || "", size: Number(d.size), parts: parts });
        }
        return out;
    }

    Process {
        id: scan
        command: [Paths.lsblk, "-J", "-b", "-o", "NAME,PATH,LABEL,FSTYPE,SIZE,MOUNTPOINTS,FSUSED,HOTPLUG,TRAN,TYPE,VENDOR,MODEL"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r !== null && JSON.stringify(r) !== JSON.stringify(root.drives)) root.drives = r;
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!scan.running) scan.running = true }

    // Exécute une commande (échec → notification avec la sortie d'erreur), puis rescanne
    Process {
        id: act
        onExited: { root.busyPath = ""; scan.running = true; }
    }
    function run(path, args, okMsg, okBody) {
        if (act.running) return;
        busyPath = path;
        act.command = [Paths.sh, "-c",
            'n="$1"; ok="$2"; body="$3"; shift 3; out=$("$@" 2>&1) && { [ -n "$ok" ] && "$n" -a "Disques USB" "$ok" "$body"; exit 0; }; "$n" -a "Disques USB" -u critical "Échec" "$out"',
            "_", Paths.notifySend, okMsg || "", okBody || ""].concat(args);
        act.running = true;
    }
    function mountAll(d) {
        run(d.path + "#m", [Paths.sh, "-c", 'u="$1"; shift; for p in "$@"; do "$u" mount -b "$p" || exit 1; done', "_", Paths.udisksctl]
            .concat(d.parts.filter(p => p.mp === "").map(p => p.path)), "");
    }
    function unmountAll(d) {
        run(d.path + "#u", [Paths.sh, "-c", 'u="$1"; shift; for p in "$@"; do "$u" unmount -b "$p" || exit 1; done', "_", Paths.udisksctl]
            .concat(d.parts.filter(p => p.mp !== "").map(p => p.path)), "");
    }
    // Éjection : démonte les volumes montés puis coupe l'alimentation du disque
    function eject(d) {
        const mounted = d.parts.filter(p => p.mp !== "").map(p => p.path);
        run(d.path, [Paths.sh, "-c",
            'u="$1"; disk="$2"; shift 2; for p in "$@"; do "$u" unmount -b "$p" || exit 1; done; "$u" power-off -b "$disk"',
            "_", Paths.udisksctl, d.path].concat(mounted), "Disque éjecté", d.name + "\nTu peux le débrancher");
    }
    function open(mp) { Quickshell.execDetached([Paths.thunar, mp]); popup.visible = false; }

    BarText {
        id: icon
        text: Theme.ic(0xf0553)    // md-usb
        color: root.mountedCount > 0 ? Theme.green : Theme.text
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    onClicked: event => popup.toggle()

    BarPopup {
        id: popup
        target: root
        contentWidth: 320
        onSettledChanged: if (settled) scan.running = true

        PopupHeader { title: "Disques USB" }

        BarText {
            visible: root.drives.length === 0
            Layout.fillWidth: true
            Layout.leftMargin: 10
            text: "Aucun disque branché"
            color: Theme.subtext
            font.pixelSize: 12
            font.family: Theme.labelFont
        }

        Repeater {
            model: root.drives
            ColumnLayout {
                id: drive
                required property var modelData
                required property int index
                readonly property var parts: modelData.parts
                readonly property var mps: parts.filter(p => p.mp !== "").map(p => p.mp)
                readonly property bool mounted: mps.length > 0
                readonly property var toMount: parts.filter(p => p.mp === "")
                Layout.fillWidth: true
                spacing: 8

                Separator { visible: drive.index > 0 }

                // Une ligne par disque : icône (verte si monté) · nom + état · actions
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    BarText {
                        text: Theme.ic(0xf02ca)    // md-harddisk
                        color: drive.mounted ? Theme.green : Theme.subtext
                        font.pixelSize: 20
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        BarText {
                            text: drive.modelData.name
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.family: Theme.labelFont
                            font.weight: Font.DemiBold
                        }
                        BarText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.fmtSize(drive.modelData.size)
                                  + (drive.modelData.tran ? " · " + drive.modelData.tran.toUpperCase() : "")
                                  + " · " + (drive.parts.length === 0 ? "illisible"
                                             : drive.mounted ? "monté" : "non monté")
                            color: Theme.subtext
                            font.pixelSize: 11
                            font.family: Theme.labelFont
                        }
                    }
                    ActionButton {
                        visible: drive.mounted
                        implicitWidth: 30; implicitHeight: 28
                        icon: Theme.ic(0xf0770)    // md-folder_open
                        accent: Theme.sky
                        onClicked: root.open(drive.mps[0])
                    }
                    ActionButton {
                        visible: drive.parts.length > 0
                        implicitWidth: 30; implicitHeight: 28
                        icon: Theme.ic(drive.mounted ? 0xf0338 : 0xf0337)    // md-link_off / md-link
                        accent: drive.mounted ? Theme.red : Theme.green
                        busy: root.busyPath === drive.modelData.path + (drive.mounted ? "#u" : "#m")
                        onClicked: drive.mounted ? root.unmountAll(drive.modelData) : root.mountAll(drive.modelData)
                    }
                    ActionButton {
                        implicitWidth: 30; implicitHeight: 28
                        icon: Theme.ic(0xf01ea)    // md-eject
                        accent: Theme.peach
                        busy: root.busyPath === drive.modelData.path
                        onClicked: root.eject(drive.modelData)
                    }
                }
            }
        }
    }
}
