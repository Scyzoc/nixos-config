import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Réglages IPv4 de la connexion active : DHCP ou IP statique (via net-ipconfig / nmcli)
// + oubli du réseau (corbeille : 1er clic arme, 2e clic oublie)
Rectangle {
    id: root

    required property string iface
    property var network: null          // réseau Wi-Fi affiché (pour « Oublier »)
    property bool confirmForget: false
    signal forgotten()
    property string conn: ""
    property string method: "auto"      // méthode choisie dans le panneau
    property string current: "auto"     // méthode réellement configurée
    property string status: ""
    property bool applying: false

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 20
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.04)
    border.color: Theme.pillBorder

    function isIp(s) {
        const m = s.trim().match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
        return !!m && m.slice(1).every(x => Number(x) <= 255);
    }
    // Accepte "24", "/24" ou "255.255.255.0" ; renvoie le préfixe ou -1
    function prefixOf(s) {
        s = s.trim().replace(/^\//, "");
        if (/^\d{1,2}$/.test(s)) return Number(s) <= 32 ? Number(s) : -1;
        if (!isIp(s)) return -1;
        const bits = s.split(".").map(x => Number(x).toString(2).padStart(8, "0")).join("");
        return /^1*0*$/.test(bits) ? bits.indexOf("0") < 0 ? 32 : bits.indexOf("0") : -1;
    }
    function dnsValid(s) {
        const parts = s.split(/[\s,]+/).filter(x => x !== "");
        return parts.length > 0 && parts.every(isIp);
    }
    readonly property bool staticValid: isIp(ipField.text) && prefixOf(maskField.text) >= 0
                                        && isIp(gwField.text) && dnsValid(dnsField.text)

    function load() {
        status = "";
        showProc.running = true;
    }
    function apply() {
        if (method === "manual" && !staticValid) { status = "Champs invalides"; return; }
        applying = true;
        status = "Application…";
        setProc.command = method === "auto"
            ? [Paths.netIpconfig, "set", conn, "auto"]
            : [Paths.netIpconfig, "set", conn, "manual",
               ipField.text.trim() + "/" + prefixOf(maskField.text), gwField.text.trim(), dnsField.text.trim()];
        setProc.running = true;
    }

    Process {
        id: showProc
        command: [Paths.netIpconfig, "show", root.iface]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = {};
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=");
                    if (i > 0) v[l.slice(0, i)] = l.slice(i + 1);
                }
                root.conn = v.conn ?? "";
                root.current = v.method === "manual" ? "manual" : "auto";
                root.method = root.current;
                const a = (v.addr ?? "").split("/");
                ipField.text = a[0] ?? "";
                maskField.text = a[1] ?? "24";
                gwField.text = v.gw ?? "";
                dnsField.text = v.dns ?? "";
            }
        }
    }

    Process {
        id: setProc
        stdout: StdioCollector { id: setOut }
        onExited: code => {
            root.applying = false;
            root.status = code === 0 ? "Appliqué" : ("Erreur : " + setOut.text.trim());
            if (code === 0) root.load();
        }
    }

    Component.onCompleted: load()

    // Désarme la corbeille si le 2e clic ne vient pas
    Timer { id: disarm; interval: 3000; onTriggered: root.confirmForget = false }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 8

        // Une ligne : méthode · appliquer · oublier (icônes seules)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ActionButton {
                implicitHeight: 28
                label: "DHCP"
                accent: Theme.green
                highlighted: root.method === "auto"
                onClicked: root.method = "auto"
            }
            ActionButton {
                implicitHeight: 28
                label: "Statique"
                accent: Theme.yellow
                highlighted: root.method === "manual"
                onClicked: root.method = "manual"
            }
            Item { Layout.fillWidth: true }
            // Visible seulement s'il y a quelque chose à appliquer
            ActionButton {
                visible: root.method !== root.current || root.method === "manual"
                implicitWidth: 30
                implicitHeight: 28
                icon: root.applying ? Theme.ic(0xf0772) : Theme.ic(0xf012c)
                accent: Theme.green
                onClicked: if (!root.applying) root.apply()
            }
            ActionButton {
                visible: root.network !== null
                implicitWidth: 30
                implicitHeight: 28
                icon: Theme.ic(0xf0a7a)
                accent: Theme.red
                highlighted: root.confirmForget
                onClicked: {
                    if (!root.confirmForget) { root.confirmForget = true; disarm.restart(); return; }
                    root.network.forget();
                    root.forgotten();
                }
            }
        }

        GridLayout {
            visible: root.method === "manual"
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 6
            rowSpacing: 6
            Field { id: ipField; label: "Adresse IP"; placeholder: "192.168.1.50"; valid: root.isIp(text) }
            Field { id: maskField; label: "Masque"; placeholder: "24 ou 255.255.255.0"; valid: root.prefixOf(text) >= 0 }
            Field { id: gwField; label: "Passerelle"; placeholder: "192.168.1.1"; valid: root.isIp(text) }
            Field { id: dnsField; label: "DNS"; placeholder: "1.1.1.1, 8.8.8.8"; valid: root.dnsValid(text) }
        }

        // Statut : seulement quand il y a quelque chose à dire
        BarText {
            visible: root.status !== "" || root.confirmForget
            Layout.fillWidth: true
            text: root.confirmForget ? "Recliquer pour oublier" : root.status
            color: root.confirmForget || root.status.indexOf("Erreur") === 0 || root.status === "Champs invalides"
                   ? Theme.red : Theme.subtext
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
}
