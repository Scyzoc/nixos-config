pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// État du VPN Maison (OpenVPN sur tap0), partagé par la pastille VPN et le menu Wi-Fi
Singleton {
    id: root

    property string ip: ""
    property bool busy: false
    // Connexion en cours (pas la déconnexion) : lueur orange sur le bouton VPN
    property bool connecting: false
    readonly property bool active: ip !== ""

    function refresh() { check.running = true; unit.running = true; }
    function toggle() {
        busy = true;
        connecting = !active;
        Quickshell.execDetached([Paths.sudo, "-n", Paths.systemctl, active ? "stop" : "start", "openvpn-maison"]);
        // Relecture rapprochée jusqu'à l'état visé ; settle = filet si rien ne change
        settle.restart();
        poll.start();
    }
    function done() {
        busy = false;
        connecting = false;
        poll.stop();
        settle.stop();
    }

    Process {
        id: check
        command: [Paths.ip, "-4", "-o", "addr", "show", "dev", "tap0", "up"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/inet (\d+\.\d+\.\d+\.\d+)/);
                root.ip = m ? m[1] : "";
                // État visé atteint (IP obtenue / tunnel tombé) → fin de l'effet
                if (root.busy && root.active === root.connecting) root.done();
            }
        }
    }
    // Connexion lancée hors de la barre (commande `homelab`) : l'unité démarre vite mais
    // le tunnel n'a pas encore d'IP (DHCP) → unité activating/active sans IP = connexion en cours
    Process {
        id: unit
        command: [Paths.systemctl, "is-active", "openvpn-maison"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (["activating", "active"].indexOf(text.trim()) >= 0 && !root.busy && !root.active) {
                    root.busy = true;
                    root.connecting = true;
                    settle.restart();
                    poll.start();
                }
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Timer { id: poll; interval: 1000; repeat: true; onTriggered: root.refresh() }
    Timer { id: settle; interval: 30000; onTriggered: { root.done(); root.refresh(); } }
}
