pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Contrôle du bruit des AirPods, partagé par les barres de tous les écrans (une
// seule connexion) via airpods-anc (quickshell.nix) : connexion permanente, le
// mode est relu à chaque changement (même depuis la tige), batteries comprises
Singleton {
    id: root

    readonly property BluetoothDevice device: Bluetooth.devices.values
        .find(d => d.connected && d.name.toLowerCase().indexOf("airpod") >= 0) ?? null
    // 1 désactivé, 2 réduction de bruit, 3 transparence, 4 adaptatif ; 0 = inconnu
    property int mode: 0
    readonly property var modes: [
        { id: 2, label: "Réduction de bruit", icon: 0xf0a45, color: Theme.blue },    // md-ear_hearing_off
        { id: 4, label: "Adaptatif", icon: 0xf1396, color: Theme.mauve },            // md-circle_half_full
        { id: 3, label: "Transparence", icon: 0xf07c5, color: Theme.teal },          // md-ear_hearing
        { id: 1, label: "Désactivé", icon: 0xf1852, color: Theme.subtext }           // md-earbuds_outline
    ]
    readonly property string label: modes.find(x => x.id === mode)?.label ?? ""

    // Batteries au pourcent près (protocole Apple) : { left, right, case } → niveau ou null,
    // et { left, right, case } → en charge. Vide tant que les AirPods n'ont rien envoyé.
    property var battery: ({})
    property var charging: ({})
    function parseBattery(line) {
        const names = { L: "left", R: "right", C: "case" };
        const b = {}, c = {};
        for (const part of line.slice(2).split(" ")) {
            const m = part.match(/^([LRC])=(?:(\d+),([01])|-)$/);
            if (!m) continue;
            b[names[m[1]]] = m[2] !== undefined ? parseInt(m[2]) : null;
            c[names[m[1]]] = m[3] === "1";
        }
        battery = b;
        charging = c;
    }

    function set(m) {
        mode = m;    // affichage immédiat, confirmé par la notification des AirPods
        proc.write(m + "\n");
    }

    Process {
        id: proc
        command: [Paths.airpodsAnc, root.device?.address ?? ""]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                if (data.startsWith("B ")) root.parseBattery(data);
                else root.mode = parseInt(data) || 0;
            }
        }
        onExited: {
            root.mode = 0;
            root.battery = {};
            root.charging = {};
        }
    }
    // (Re)connexion tant que les AirPods sont là, arrêt sinon
    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.device !== null
        onTriggered: if (!proc.running) proc.running = true
        onRunningChanged: if (!running) proc.running = false
    }
}
