import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Ethernet : affiché dès qu'un câble est branché (porteuse détectée) ; clic : détails + réglages IP
//   blanc            câble branché, aucune connexion
//   orange clignotant attribution d'IP en cours (NetworkManager « connecting »)
//   vert             connecté
Pill {
    id: root

    // Carte filaire gérée par NetworkManager (exclut vmnet/veth, non gérés)
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.nmManaged) ?? null
    readonly property string ifname: wired?.name ?? ""
    readonly property bool carrier: wired?.hasLink ?? false
    readonly property bool connecting: wired?.state === ConnectionState.Connecting
    readonly property bool online: wired?.connected ?? false
    property string ip: ""

    readonly property color tint: online ? Theme.green : connecting ? Theme.peach : Theme.text
    readonly property string statusText: online ? "Connecté" + (speedText ? "  ·  " + speedText : "")
                                       : connecting ? "Attribution d'IP…"
                                       : "Câble branché, pas de connexion"

    tooltip: online ? "Ethernet" + (ip ? "\n" + ip : "") : "Ethernet\n" + statusText

    visible: carrier || online
    onVisibleChanged: if (!visible) popup.visible = false

    Process {
        id: ipProc
        command: [Paths.ip, "-4", "-o", "addr", "show", "dev", root.ifname || "lo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/inet (\d+\.\d+\.\d+\.\d+)/);
                root.ip = m ? m[1] : "";
            }
        }
    }
    Timer { interval: 10000; running: root.online; repeat: true; triggeredOnStart: true; onTriggered: ipProc.running = true }
    onOnlineChanged: {
        if (!online) ip = "";
        if (popup.visible) details.refresh();
    }
    onConnectingChanged: if (popup.visible) details.refresh()

    // Attribution d'IP : l'icône (orange) clignote
    property real blink: 1
    SequentialAnimation on blink {
        running: root.connecting && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.2; duration: 450; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutQuad }
        onRunningChanged: if (!running) root.blink = 1
    }

    BarText {
        text: Theme.ic(0xf0200)    // md-ethernet
        color: root.tint
        opacity: root.blink
        Behavior on color { ColorAnimation { duration: 250 } }
    }
    BarText { text: root.ip; color: root.tint; visible: root.online && root.ip !== "" && !root.compact }

    // ---- Détails (nmcli), lus à l'ouverture du menu ----

    readonly property int speed: wired?.linkSpeed ?? 0     // Mb/s
    readonly property string speedText: speed <= 0 ? "" : speed >= 1000 ? (speed / 1000) + " Gb/s" : speed + " Mb/s"

    QtObject {
        id: details
        property var v: ({})            // champs nmcli bruts (clé → valeur ou liste)
        property string method: ""      // auto / manual
        function refresh() {
            if (root.ifname === "") return;
            devProc.running = true;
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
    }

    Process {
        id: devProc
        command: [Paths.nmcli, "-t", "-f", "GENERAL,IP4,IP6,DHCP4", "dev", "show", root.ifname || "lo"]
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
                details.v = v;
                const conn = v["GENERAL.CONNECTION"] ?? "";
                if (conn) { methodProc.command = [Paths.nmcli, "-g", "ipv4.method", "con", "show", conn]; methodProc.running = true; }
                else details.method = "";
            }
        }
    }
    Process {
        id: methodProc
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: details.method = text.trim() }
    }

    // Débit en direct (compteurs du noyau), seulement menu ouvert
    property real rxRate: 0
    property real txRate: 0
    property var lastStat: null
    Process {
        id: statProc
        command: [Paths.cat, "/sys/class/net/" + root.ifname + "/statistics/rx_bytes", "/sys/class/net/" + root.ifname + "/statistics/tx_bytes"]
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
    Timer { interval: 1000; running: popup.visible && root.ifname !== ""; repeat: true; triggeredOnStart: true; onTriggered: statProc.running = true }
    function rate(b) {
        if (b >= 1e6) return (b / 1e6).toFixed(1).replace(".", ",") + " Mo/s";
        if (b >= 1e3) return Math.round(b / 1e3) + " ko/s";
        return Math.round(b) + " o/s";
    }

    // Accès internet (même test que le menu Wi-Fi)
    property string connectivity: "full"
    readonly property bool netProblem: online && ["limited", "none", "portal"].indexOf(connectivity) >= 0
    Process {
        id: connCheck
        command: [Paths.nmcli, "networking", "connectivity", "check"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: root.connectivity = text.trim() || "unknown" }
    }

    // Connexion / déconnexion de la carte (profil choisi par NetworkManager)
    property string errorText: ""
    Process {
        id: devAction
        environment: ({ LC_ALL: "C" })
        stderr: StdioCollector { id: devErr }
        onExited: code => {
            root.errorText = code === 0 ? "" : (devErr.text.trim().replace(/^Error: /, "") || "Échec");
            details.refresh();
        }
    }
    function setConnected(on) {
        errorText = "";
        devAction.command = [Paths.nmcli, "dev", on ? "connect" : "disconnect", ifname];
        devAction.running = true;
    }

    property bool showIpSettings: false
    property string copied: ""          // libellé de la ligne copiée (coche ~1,2 s)
    Timer { id: copiedReset; interval: 1200; onTriggered: root.copied = "" }
    function copy(label, value) {
        Quickshell.execDetached([Paths.wlCopy, value]);
        copied = label;
        copiedReset.restart();
    }

    // Lignes du tableau de détails : [icône, libellé, valeur] ; valeur vide → ligne masquée
    readonly property var rows: {
        const d = details;
        const addr = d.first("IP4.ADDRESS");
        const v6 = d.all("IP6.ADDRESS");
        const v6g = v6.find(a => !a.startsWith("fe80")) ?? "";
        const expiry = Number(d.dhcp("expiry"));
        const lease = expiry > 0 ? "jusqu'à " + Qt.formatDateTime(new Date(expiry * 1000), "HH:mm") : "";
        const product = (d.first("GENERAL.PRODUCT").split(/ PCI| Gigabit| Ethernet/)[0] || "");
        return [
            [0xf062e, "Méthode", d.method === "manual" ? "IP statique" : d.method === "auto" ? "DHCP" : ""],      // md-tune
            [0xf0a60, "IPv4", addr],                                                                              // md-ip_network
            [0xf11e2, "Passerelle", d.first("IP4.GATEWAY")],                                                      // md-router
            [0xf01d6, "DNS", d.all("IP4.DNS").join(", ")],                                                        // md-dns
            [0xf059f, "Domaine", d.all("IP4.DOMAIN").join(", ")],                                                 // md-web
            [0xf0a5f, "IPv6", v6g],                                                                               // md-ip
            [0xf0150, "Bail DHCP", d.method === "auto" ? lease : ""],                                             // md-clock_outline
            [0xf04e2, "Trafic", online ? "↓ " + rate(rxRate) + "   ↑ " + rate(txRate) : ""],                      // md-swap_vertical
            [0xf04c5, "Vitesse", speedText],                                                                      // md-speedometer
            [0xf0efe, "MAC", d.first("GENERAL.HWADDR")],                                                          // md-identifier
            [0xf061a, "Carte", [product, d.first("GENERAL.DRIVER")].filter(x => x).join("  ·  ")],                // md-chip
        ].filter(r => r[2] !== "");
    }

    onClicked: popup.toggle()

    BarPopup {
        id: popup
        target: root
        contentWidth: 330

        onVisibleChanged: {
            if (visible) { details.refresh(); connCheck.running = true; }
            else { root.showIpSettings = false; root.errorText = ""; root.lastStat = null; root.rxRate = 0; root.txRate = 0; }
        }
        // Champs (bail, IP…) qui évoluent pendant l'attribution
        Timer { interval: 3000; running: popup.visible; repeat: true; onTriggered: details.refresh() }

        // En-tête (style menu Wi-Fi) : grosse icône, profil et état à côté
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            BarText {
                text: Theme.ic(0xf0200)
                font.pixelSize: 40
                color: root.tint
                opacity: root.blink
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Item {
                    Layout.fillWidth: true
                    implicitWidth: 0
                    implicitHeight: menuName.implicitHeight
                    BarText {
                        id: menuName
                        width: Math.min(implicitWidth, parent.width - (menuCheck.visible ? 26 : 0))
                        elide: Text.ElideRight
                        text: details.first("GENERAL.CONNECTION") || "Ethernet"
                        font.family: Theme.titleFont
                        font.pixelSize: 22
                        font.bold: true
                    }
                    BarText {
                        id: menuCheck
                        visible: root.online
                        x: menuName.width + 8
                        anchors.verticalCenter: menuName.verticalCenter
                        text: Theme.ic(0xf05e0)    // md-check-circle
                        color: root.tint
                        font.pixelSize: 16
                    }
                }
                BarText {
                    font.family: Theme.labelFont
                    text: root.statusText
                    color: root.connecting ? Theme.peach : Theme.subtext
                    font.pixelSize: 12
                }
            }
            Spinner {
                visible: root.connecting || devAction.running
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
            }
            // Interrupteur : connecter / déconnecter la carte
            Toggle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                checked: root.online || root.connecting
                accent: Theme.green
                onToggled: if (!devAction.running) root.setConnected(!(root.online || root.connecting))
            }
        }

        BarText {
            font.family: Theme.labelFont
            visible: root.errorText !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.errorText
            color: Theme.red
            font.pixelSize: 12
        }

        // Problème de connexion : bandeau rouge + lancement de netfix
        Rectangle {
            visible: root.netProblem
            Layout.fillWidth: true
            implicitHeight: netRow.implicitHeight + 16
            radius: 10
            color: Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.12)
            border.color: Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.5)
            border.width: 1

            RowLayout {
                id: netRow
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 10
                spacing: 8
                BarText { text: Theme.ic(0xf0026); color: Theme.red; font.pixelSize: 16 }    // md-alert
                BarText {
                    font.family: Theme.labelFont
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Theme.red
                    font.pixelSize: 12
                    text: root.connectivity === "portal"
                          ? "Portail captif : connexion à valider dans le navigateur"
                          : (root.connectivity === "none" ? "Aucun accès au réseau" : "Connecté, mais pas d'accès à internet")
                }
                ActionButton {
                    icon: Theme.ic(0xf0be0)    // md-wrench_outline
                    label: "Netfix"
                    accent: Theme.red
                    onClicked: {
                        popup.visible = false;
                        Quickshell.execDetached([Paths.userBin + "/netfix-window"]);
                    }
                }
            }
        }

        Separator {}

        // Détails : clic sur une ligne = copie de la valeur
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
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

        // Réglages IP (DHCP / statique) : seulement avec une connexion active
        Separator { visible: root.online }
        RowLayout {
            visible: root.online
            Layout.fillWidth: true
            spacing: 6
            ActionButton {
                Layout.fillWidth: true
                icon: Theme.ic(0xf0493)    // md-cog
                label: "Réglages IP"
                accent: Theme.blue
                highlighted: root.showIpSettings
                onClicked: root.showIpSettings = !root.showIpSettings
            }
            ActionButton {
                icon: Theme.ic(0xf0450)    // md-refresh
                accent: Theme.green
                busy: devAction.running
                // Renouvelle le bail : réactivation du profil
                onClicked: {
                    const conn = details.first("GENERAL.CONNECTION");
                    if (devAction.running || !conn) return;
                    root.errorText = "";
                    devAction.command = [Paths.nmcli, "con", "up", conn];
                    devAction.running = true;
                }
            }
        }

        // Dépliage animé (même animation que le menu Wi-Fi)
        Item {
            id: ipPanel
            readonly property bool open: root.online && root.showIpSettings
            Layout.fillWidth: true
            Layout.preferredHeight: open ? (ipSettings.item?.implicitHeight ?? 0) : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            visible: Layout.preferredHeight > 0
            clip: true
            opacity: open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Loader {
                id: ipSettings
                width: parent.width
                y: ipPanel.open ? 0 : -14
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                active: ipPanel.open || ipPanel.Layout.preferredHeight > 0
                sourceComponent: IpSettings { iface: root.ifname }
            }
        }
    }
}
