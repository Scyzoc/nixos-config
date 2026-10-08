import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking

// Ethernet : affiché dès qu'un câble est branché (porteuse détectée) ; clic : ethernet-menu
//   blanc            câble branché, aucune connexion
//   orange clignotant attribution d'IP en cours (NetworkManager « connecting »)
//   vert             connecté
Pill {
    id: root

    // Carte filaire gérée par NetworkManager (exclut vmnet/veth, non gérés)
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.nmManaged) ?? null
    readonly property string ifname: wired?.name ?? ""
    property bool carrier: false
    readonly property bool connecting: wired?.state === ConnectionState.Connecting
    readonly property bool online: wired?.connected ?? false
    property string ip: ""

    readonly property color tint: online ? Theme.green : connecting ? Theme.peach : Theme.text

    tooltip: online ? "Ethernet" + (ip ? "\n" + ip : "")
           : connecting ? "Ethernet\nAttribution d'IP…"
           : "Ethernet\nCâble branché, pas de connexion"

    visible: carrier || online

    // Porteuse : lue au démarrage puis à chaque événement lien (branchement/débranchement)
    function parseLink(line) {
        if (line.indexOf(" " + ifname + ":") < 0) return;
        carrier = /[<,]LOWER_UP[,>]/.test(line);
    }
    Process {
        id: linkInit
        command: [Paths.ip, "-o", "link", "show", "dev", root.ifname || "lo"]
        environment: ({ LC_ALL: "C" })
        stdout: SplitParser { onRead: line => root.parseLink(line) }
    }
    Process {
        running: root.ifname !== ""
        command: [Paths.ip, "-o", "monitor", "link"]
        environment: ({ LC_ALL: "C" })
        stdout: SplitParser { onRead: line => root.parseLink(line) }
    }
    onIfnameChanged: if (ifname !== "") linkInit.running = true

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
    onOnlineChanged: if (!online) ip = ""

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

    onClicked: Hyprland.dispatch("exec ethernet-menu")
}
