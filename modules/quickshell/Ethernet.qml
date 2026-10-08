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
    onOnlineChanged: if (!online) ip = ""
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
    BarText {
        text: root.ip
        color: root.tint
        visible: root.online && root.ip !== "" && !root.compact
        font.family: Theme.labelFont
        font.weight: Font.Medium
    }

    readonly property int speed: wired?.linkSpeed ?? 0     // Mb/s
    readonly property string speedText: speed <= 0 ? "" : speed >= 1000 ? (speed / 1000) + " Gb/s" : speed + " Mb/s"

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

    onClicked: popup.toggle()

    BarPopup {
        id: popup
        target: root
        contentWidth: 330

        onVisibleChanged: {
            if (visible) connCheck.running = true;
            else { root.showIpSettings = false; root.errorText = ""; }
        }

        // En-tête (style menu Wi-Fi) : grosse icône, profil et état à côté
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            BarText {
                id: headIcon
                text: Theme.ic(0xf0200)
                font.pixelSize: 40
                color: root.tint
                opacity: root.blink
                Layout.alignment: Qt.AlignTop
            }
            ColumnLayout {
                Layout.fillWidth: true
                // Ligne du nom centrée sur la grosse icône (l'état dépasse en dessous)
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Math.max(0, (headIcon.implicitHeight - menuName.implicitHeight) / 2)
                spacing: 2
                Item {
                    Layout.fillWidth: true
                    implicitWidth: 0
                    implicitHeight: menuName.implicitHeight
                    BarText {
                        id: menuName
                        width: Math.min(implicitWidth, parent.width - headCtrl.width - 12 - (menuCheck.visible ? 26 : 0))
                        elide: Text.ElideRight
                        text: details.conn || "Ethernet"
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
                    Row {
                        id: headCtrl
                        anchors.right: parent.right
                        anchors.verticalCenter: menuName.verticalCenter
                        spacing: 12
                        Spinner {
                            visible: root.connecting || devAction.running
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        // Interrupteur : connecter / déconnecter la carte
                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.online || root.connecting
                            accent: Theme.green
                            onToggled: if (!devAction.running) root.setConnected(!(root.online || root.connecting))
                        }
                    }
                }
                BarText {
                    font.family: Theme.labelFont
                    text: root.statusText
                    color: root.connecting ? Theme.peach : Theme.subtext
                    font.pixelSize: 12
                }
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

        NetDetails {
            id: details
            Layout.fillWidth: true
            iface: root.ifname
            active: popup.visible
            online: root.online
            linkRows: [[0xf04c5, "Vitesse", root.speedText]]    // md-speedometer
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
                    const conn = details.conn;
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
