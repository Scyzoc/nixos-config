import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Port console (switch réseau en USB) : visible quand un /dev/ttyUSB* ou /dev/ttyACM* existe ;
// clic : terminal avec la commande « console »
Pill {
    id: root

    property bool present: false

    // Apparition / disparition : largeur et opacité animées (Behavior sur implicitWidth dans Pill)
    implicitWidth: present ? icon.implicitWidth + hpad * 2 : 0
    opacity: present ? 1 : 0
    visible: present || implicitWidth > 0.5
    clip: true
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    tooltip: "Port console\nClic : ouvrir le terminal"

    Process {
        id: probe
        command: [Paths.sh, "-c", "ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.present = text.trim() !== "" }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: probe.running = true }

    BarText {
        id: icon
        text: Theme.ic(0xf0200)    // md-ethernet
        color: Theme.text
    }

    onClicked: Hyprland.dispatch('hl.dsp.exec_cmd("kitty --class console -e console")')
}
