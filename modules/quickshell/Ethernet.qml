import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking

// Ethernet : affiché seulement quand un câble est connecté ; clic : ethernet-menu
Pill {
    id: root

    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    property string ip: ""

    tooltip: "Ethernet" + (ip ? "\n" + ip : "")

    visible: wired !== null

    Process {
        id: ipProc
        command: [Paths.ip, "-4", "-o", "addr", "show", "dev", root.wired?.name ?? "lo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/inet (\d+\.\d+\.\d+\.\d+)/);
                root.ip = m ? m[1] : "";
            }
        }
    }
    Timer { interval: 10000; running: root.wired !== null; repeat: true; triggeredOnStart: true; onTriggered: ipProc.running = true }

    BarText { text: Theme.ic(0xf0200); color: Theme.green }
    BarText { text: root.ip; color: Theme.green; visible: root.ip !== "" && !root.compact }

    onClicked: Hyprland.dispatch("exec ethernet-menu")
}
