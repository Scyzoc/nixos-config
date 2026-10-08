import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Détails d'une interface réseau (nmcli + compteurs du noyau), lus tant que `active`.
// Clic sur une ligne = copie de la valeur. Partagé par les menus Ethernet et Wi-Fi.
ColumnLayout {
    id: root

    required property string iface
    property bool active: false        // menu ouvert : lecture + débit en direct
    property bool online: false
    // Lignes propres au type de lien ([icône, libellé, valeur]), entre le trafic et la MAC
    property var linkRows: []

    property var v: ({})               // champs nmcli bruts (clé → valeur ou liste)
    property string method: ""         // auto / manual
    readonly property string conn: first("GENERAL.CONNECTION")

    spacing: 0

    function refresh() {
        if (iface !== "") devProc.running = true;
    }
    function first(k) { const x = v[k]; return Array.isArray(x) ? (x[0] ?? "") : (x ?? ""); }
    function all(k) { const x = v[k]; return Array.isArray(x) ? x : (x ? [x] : []); }
    // Option DHCP4 « nom = valeur »
    function dhcp(name) {
        for (const o of all("DHCP4.OPTION")) {
            const i = o.indexOf(" = ");
            if (i > 0 && o.slice(0, i) === name) return o.slice(i + 3);
        }
        return "";
    }
    function rate(b) {
        if (b >= 1e6) return (b / 1e6).toFixed(1).replace(".", ",") + " Mo/s";
        if (b >= 1e3) return Math.round(b / 1e3) + " ko/s";
        return Math.round(b) + " o/s";
    }

    onActiveChanged: {
        if (active) refresh();
        else { lastStat = null; rxRate = 0; txRate = 0; copied = ""; }
    }
    onOnlineChanged: if (active) refresh()
    // Champs (bail, IP…) qui évoluent pendant l'attribution
    Timer { interval: 3000; running: root.active; repeat: true; onTriggered: root.refresh() }

    Process {
        id: devProc
        command: [Paths.nmcli, "-t", "-f", "GENERAL,IP4,IP6,DHCP4", "dev", "show", root.iface || "lo"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const v = {};
                for (const l of text.split("\n")) {
                    const i = l.indexOf(":");
                    if (i <= 0) continue;
                    const val = l.slice(i + 1);
                    // IP4.DNS[1], IP4.DNS[2]… → liste
                    const m = l.slice(0, i).match(/^([^\[]+)\[\d+\]$/);
                    if (m) (v[m[1]] = v[m[1]] ?? []).push(val);
                    else v[l.slice(0, i)] = val;
                }
                root.v = v;
                const conn = v["GENERAL.CONNECTION"] ?? "";
                if (conn) { methodProc.command = [Paths.nmcli, "-g", "ipv4.method", "con", "show", conn]; methodProc.running = true; }
                else root.method = "";
            }
        }
    }
    Process {
        id: methodProc
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: root.method = text.trim() }
    }

    // Débit en direct (compteurs du noyau)
    property real rxRate: 0
    property real txRate: 0
    property var lastStat: null
    Process {
        id: statProc
        command: [Paths.cat, "/sys/class/net/" + root.iface + "/statistics/rx_bytes", "/sys/class/net/" + root.iface + "/statistics/tx_bytes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split("\n").map(Number);
                if (n.length < 2 || n.some(isNaN)) return;
                const now = Date.now();
                if (root.lastStat) {
                    const dt = (now - root.lastStat.t) / 1000;
                    if (dt > 0) {
                        root.rxRate = Math.max(0, (n[0] - root.lastStat.rx) / dt);
                        root.txRate = Math.max(0, (n[1] - root.lastStat.tx) / dt);
                    }
                }
                root.lastStat = { t: now, rx: n[0], tx: n[1] };
            }
        }
    }
    Timer { interval: 1000; running: root.active && root.iface !== ""; repeat: true; triggeredOnStart: true; onTriggered: statProc.running = true }

    property string copied: ""          // libellé de la ligne copiée (coche ~1,2 s)
    Timer { id: copiedReset; interval: 1200; onTriggered: root.copied = "" }
    function copy(label, value) {
        Quickshell.execDetached([Paths.wlCopy, value]);
        copied = label;
        copiedReset.restart();
    }

    // [icône, libellé, valeur] ; valeur vide → ligne masquée
    readonly property var rows: {
        const v6 = all("IP6.ADDRESS");
        const expiry = Number(dhcp("expiry"));
        const lease = expiry > 0 ? "jusqu'à " + Qt.formatDateTime(new Date(expiry * 1000), "HH:mm") : "";
        const product = first("GENERAL.PRODUCT").split(/ PCI| Gigabit| Ethernet| Wireless/)[0] || "";
        return [
            [0xf062e, "Méthode", method === "manual" ? "IP statique" : method === "auto" ? "DHCP" : ""],      // md-tune
            [0xf0a60, "IPv4", first("IP4.ADDRESS")],                                                          // md-ip_network
            [0xf11e2, "Passerelle", first("IP4.GATEWAY")],                                                    // md-router
            [0xf01d6, "DNS", all("IP4.DNS").join(", ")],                                                      // md-dns
            [0xf059f, "Domaine", all("IP4.DOMAIN").join(", ")],                                               // md-web
            [0xf0a5f, "IPv6", v6.find(a => !a.startsWith("fe80")) ?? ""],                                     // md-ip
            [0xf0150, "Bail DHCP", method === "auto" ? lease : ""],                                           // md-clock_outline
            [0xf04e2, "Trafic", online ? "↓ " + rate(rxRate) + "   ↑ " + rate(txRate) : ""],                  // md-swap_vertical
        ].concat(linkRows, [
            [0xf0efe, "MAC", first("GENERAL.HWADDR")],                                                        // md-identifier
            [0xf061a, "Carte", [product, first("GENERAL.DRIVER")].filter(x => x).join("  ·  ")],              // md-chip
        ]).filter(r => r[2] !== "");
    }

    Repeater {
        model: root.rows
        Rectangle {
            id: row
            required property var modelData
            readonly property bool isCopied: root.copied === modelData[1]
            Layout.fillWidth: true
            implicitHeight: 26
            radius: 6
            color: rowMouse.containsMouse ? Theme.rowHover : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 8
                BarText {
                    text: Theme.ic(row.modelData[0])
                    color: Theme.subtext
                    font.pixelSize: 13
                    Layout.preferredWidth: 16
                    horizontalAlignment: Text.AlignHCenter
                }
                BarText {
                    text: row.modelData[1]
                    color: Theme.muted
                    font.family: Theme.labelFont
                    font.pixelSize: 12
                    Layout.preferredWidth: 72
                }
                BarText {
                    text: row.modelData[2]
                    color: Theme.text
                    font.family: Theme.labelFont
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                BarText {
                    visible: rowMouse.containsMouse || row.isCopied
                    text: row.isCopied ? Theme.ic(0xf012c) : Theme.ic(0xf018f)    // md-check / md-content_copy
                    color: row.isCopied ? Theme.green : Theme.subtext
                    font.pixelSize: 12
                }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copy(row.modelData[1], row.modelData[2])
            }
        }
    }
}
