import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking

// Wi-Fi ; clic : réseaux, connexion (mot de passe), réglages IP, mode avion, VPN
Pill {
    id: root

    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var networks: wifiDev ? wifiDev.networks.values : []
    readonly property var current: networks.find(n => n.connected) ?? null
    readonly property bool enabled_: Networking.wifiEnabled
    property string ip: ""
    property string pendingSsid: ""
    property string errorText: ""
    property bool showIpSettings: false
    property bool airplane: false
    tooltip: current !== null ? ip : ""
    readonly property color tint: airplane ? Theme.peach
                                : current ? Theme.green
                                : enabled_ ? Theme.red : Theme.muted

    // Mode avion = toutes les radios (Wi-Fi + Bluetooth) bloquées par rfkill
    Process {
        id: rfkillState
        command: [Paths.rfkill, "-n", "-o", "SOFT"]
        // Sortie localisée sinon ("bloqué" en français)
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n").filter(x => x !== "");
                root.airplane = l.length > 0 && l.every(x => x.trim() === "blocked");
            }
        }
    }
    Process {
        id: rfkillSet
        onExited: rfkillState.running = true
    }
    function setAirplane(on) {
        root.airplane = on;
        rfkillSet.command = [Paths.rfkill, on ? "block" : "unblock", "all"];
        rfkillSet.running = true;
    }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: rfkillState.running = true }

    // Accès internet selon NetworkManager : full / limited / portal / none / unknown
    // (check = test forcé à l'ouverture du menu, sinon dernier état connu)
    property string connectivity: "full"
    readonly property bool netProblem: current !== null && ["limited", "none", "portal"].indexOf(connectivity) >= 0
    Process {
        id: connProc
        command: [Paths.nmcli, "-t", "-f", "CONNECTIVITY", "general"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: root.connectivity = text.trim() || "unknown" }
    }
    Process {
        id: connCheck
        command: [Paths.nmcli, "networking", "connectivity", "check"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: root.connectivity = text.trim() || "unknown" }
    }
    Timer { interval: 15000; running: root.current !== null; repeat: true; triggeredOnStart: true; onTriggered: connProc.running = true }

    // Connecté sans internet : icône et SSID jaunes qui « respirent », bordure teintée
    readonly property color netColor: netProblem ? Theme.yellow : Theme.green
    property real warnPulse: 1
    SequentialAnimation on warnPulse {
        running: root.netProblem && !root.airplane
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.warnPulse = 1
    }

    function strength(n) {
        const s = n?.signalStrength ?? 0;
        return s <= 1 ? s * 100 : s;
    }
    function sigIcon(s) {
        if (s >= 80) return Theme.ic(0xf0928);
        if (s >= 60) return Theme.ic(0xf0925);
        if (s >= 40) return Theme.ic(0xf0922);
        if (s >= 20) return Theme.ic(0xf091f);
        return Theme.ic(0xf092f);
    }
    function secured(n) { return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Unknown; }

    Process {
        id: ipProc
        command: [Paths.ip, "-4", "-o", "addr", "show", "dev", root.wifiDev?.name ?? "wlan0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/inet (\d+\.\d+\.\d+\.\d+)/);
                root.ip = m ? m[1] : "";
            }
        }
    }
    onCurrentChanged: ipProc.running = true
    Timer { interval: 10000; running: root.current !== null; repeat: true; triggeredOnStart: true; onTriggered: ipProc.running = true }

    // Mode avion : pastille orange, l'avion arrive en vol et remplace le Wi-Fi
    color: airplane ? Qt.rgba(250 / 255, 179 / 255, 135 / 255, hovered ? 0.3 : 0.16)
                    : (hovered ? Theme.pillHover : Theme.pill)
    border.color: airplane ? Qt.rgba(250 / 255, 179 / 255, 135 / 255, 0.6)
                : netProblem ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.25 + 0.35 * warnPulse)
                : Theme.pillBorder
    Behavior on border.color { enabled: !root.netProblem || root.airplane; ColorAnimation { duration: 400 } }

    Item {
        id: stage
        implicitWidth: root.airplane ? plane.implicitWidth : wifiRow.implicitWidth
        implicitHeight: 20
        clip: true

        RowLayout {
            id: wifiRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            BarText {
                text: root.current ? root.sigIcon(root.strength(root.current)) : Theme.ic(0xf092e)
                color: root.current ? root.netColor : Theme.red
                Behavior on color { ColorAnimation { duration: 400 } }
                opacity: root.warnPulse
            }
            // VPN : bouclier juste après l'icône Wi-Fi (arrivée en fondu + zoom) ;
            // vert une fois connecté, orange clignotant pendant la connexion
            Item {
                readonly property bool shown: VpnState.active || VpnState.connecting
                implicitWidth: vpnIcon.implicitWidth
                implicitHeight: vpnIcon.implicitHeight
                visible: vpnIcon.opacity > 0
                BarText {
                    id: vpnIcon
                    property real blink: 1
                    property real fade: parent.shown ? 1 : 0
                    Behavior on fade { NumberAnimation { duration: 300 } }
                    text: Theme.ic(0xf0582)
                    color: VpnState.connecting ? Theme.peach : Theme.green
                    Behavior on color { ColorAnimation { duration: 300 } }
                    font.pixelSize: 13
                    opacity: fade * blink
                    scale: parent.shown ? 1 : 0.4
                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                    SequentialAnimation on blink {
                        running: VpnState.connecting
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutQuad }
                        onRunningChanged: if (!running) vpnIcon.blink = 1
                    }
                }
            }
            BarText {
                visible: root.current !== null && !root.compact
                text: root.current?.name ?? ""
                color: root.netColor
                Behavior on color { ColorAnimation { duration: 400 } }
                opacity: root.warnPulse
                font.family: Theme.labelFont
                font.weight: Font.Medium
                Layout.maximumWidth: 140
                elide: Text.ElideRight
            }
        }

        // Traînée derrière l'avion pendant l'arrivée
        Rectangle {
            id: trail
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: plane.left
            anchors.rightMargin: 1
            height: 2
            radius: 1
            width: 0
            opacity: 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Theme.peach }
            }
        }

        BarText {
            id: plane
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.ic(0xf001d)
            color: Theme.peach
            font.pixelSize: 16
            x: 0
            opacity: 0
            transformOrigin: Item.Center
        }

        states: State {
            name: "airplane"
            when: root.airplane
            PropertyChanges { target: plane; opacity: 1; x: 0; rotation: 0 }
            PropertyChanges { target: wifiRow; opacity: 0 }
        }

        transitions: [
            // Arrivée : l'avion entre par la gauche en montant, puis se stabilise
            Transition {
                to: "airplane"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: wifiRow; property: "opacity"; to: 0; duration: 250 }
                        NumberAnimation { target: wifiRow; property: "anchors.verticalCenterOffset"; from: 0; to: -12; duration: 250; easing.type: Easing.InCubic }
                    }
                    PropertyAction { target: wifiRow; property: "anchors.verticalCenterOffset"; value: 0 }
                    PropertyAction { target: plane; property: "x"; value: -34 }
                    PropertyAction { target: plane; property: "rotation"; value: 20 }
                    PropertyAction { target: plane; property: "anchors.verticalCenterOffset"; value: 8 }
                    ParallelAnimation {
                        NumberAnimation { target: plane; property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { target: plane; property: "x"; to: 0; duration: 700; easing.type: Easing.OutCubic }
                        NumberAnimation { target: plane; property: "anchors.verticalCenterOffset"; to: 0; duration: 700; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: plane; property: "rotation"; to: -8; duration: 450; easing.type: Easing.OutCubic }
                            NumberAnimation { target: plane; property: "rotation"; to: 0; duration: 350; easing.type: Easing.OutBack }
                        }
                        SequentialAnimation {
                            PropertyAction { target: trail; property: "opacity"; value: 0.9 }
                            NumberAnimation { target: trail; property: "width"; from: 0; to: 18; duration: 400; easing.type: Easing.OutCubic }
                            ParallelAnimation {
                                NumberAnimation { target: trail; property: "width"; to: 0; duration: 400 }
                                NumberAnimation { target: trail; property: "opacity"; to: 0; duration: 400 }
                            }
                        }
                    }
                }
            },
            // Retour : l'avion décolle vers la droite, le Wi-Fi redescend
            Transition {
                from: "airplane"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: plane; property: "x"; to: 40; duration: 450; easing.type: Easing.InCubic }
                        NumberAnimation { target: plane; property: "anchors.verticalCenterOffset"; to: -10; duration: 450; easing.type: Easing.InCubic }
                        NumberAnimation { target: plane; property: "rotation"; to: -20; duration: 450 }
                        NumberAnimation { target: plane; property: "opacity"; to: 0; duration: 450; easing.type: Easing.InQuad }
                    }
                    PropertyAction { target: plane; properties: "x,rotation,anchors.verticalCenterOffset"; value: 0 }
                    PropertyAction { target: wifiRow; property: "anchors.verticalCenterOffset"; value: 12 }
                    ParallelAnimation {
                        NumberAnimation { target: wifiRow; property: "opacity"; to: 1; duration: 300 }
                        NumberAnimation { target: wifiRow; property: "anchors.verticalCenterOffset"; to: 0; duration: 350; easing.type: Easing.OutBack }
                    }
                }
            }
        ]
    }

    onClicked: popup.toggle()

    BarPopup {
        id: popup
        target: root
        contentWidth: 320

        onVisibleChanged: {
            if (root.wifiDev) root.wifiDev.scannerEnabled = visible;
            if (!visible) { root.pendingSsid = ""; root.errorText = ""; root.showIpSettings = false; }
            else { rfkillState.running = true; VpnState.refresh(); connCheck.running = true; }
        }

        // En-tête (style menu batterie) : grosse icône Wi-Fi, SSID et détails à côté
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            BarText {
                text: root.airplane ? Theme.ic(0xf001d)
                    : root.current ? root.sigIcon(root.strength(root.current)) : Theme.ic(0xf092e)
                font.pixelSize: 40
                color: root.tint
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                // SSID + icône « connecté » juste après
                // Item (pas de layout) : la largeur du nom ne dépend pas de sa propre colonne
                Item {
                    Layout.fillWidth: true
                    implicitWidth: 0
                    implicitHeight: nameText.implicitHeight
                    BarText {
                        id: nameText
                        width: Math.min(implicitWidth, parent.width - (check.visible ? 26 : 0))
                        elide: Text.ElideRight
                        text: root.current?.name
                        ?? (root.airplane ? "Mode avion" : root.enabled_ ? "Déconnecté" : "Wi-Fi désactivé")
                        font.family: Theme.titleFont
                        font.pixelSize: 22
                        font.bold: true
                    }
                    BarText {
                        id: check
                        visible: root.current !== null
                        x: nameText.width + 8
                        anchors.verticalCenter: nameText.verticalCenter
                        text: Theme.ic(0xf05e0)    // md-check-circle
                        color: root.tint
                        font.pixelSize: 16
                    }
                }
                BarText {
                    font.family: Theme.labelFont
                    visible: root.current !== null
                    text: root.ip || "N/A"
                    color: Theme.subtext
                    font.pixelSize: 12
                }
                RowLayout {
                    visible: VpnState.active
                    spacing: 4
                    BarText { text: Theme.ic(0xf0582); color: Theme.green; font.pixelSize: 11 }
                    BarText { text: "VPN  ·  " + VpnState.ip; color: Theme.green; font.pixelSize: 11; font.family: Theme.labelFont }
                }
            }
            // Recherche de réseaux en cours : icône de chargement qui tourne
            Spinner {
                visible: root.wifiDev?.scannerEnabled ?? false
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
            }
            // Interrupteur Wi-Fi, à droite du nom (comme le menu Bluetooth)
            Toggle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                checked: root.enabled_
                accent: Theme.green    // vert si activé, gris sinon
                onToggled: Networking.wifiEnabled = !root.enabled_
            }
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
        // Mode avion / VPN / avancé : 3 boutons icône seule de même largeur (comme les profils d'énergie)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ActionButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Theme.ic(0xf001d)
                accent: Theme.peach
                highlighted: root.airplane
                onClicked: root.setAirplane(!root.airplane)
            }
            ActionButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Theme.ic(0xf0582)
                glowing: VpnState.connecting
                busy: VpnState.busy && !VpnState.connecting
                accent: Theme.green
                highlighted: VpnState.active
                onClicked: if (!VpnState.busy) VpnState.toggle()
            }
        }

        Separator { visible: root.enabled_ }

        BarText {
            font.family: Theme.labelFont
            visible: root.errorText !== ""
            text: root.errorText
            color: Theme.red
            font.pixelSize: 12
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, 460)
            contentHeight: list.implicitHeight
            clip: true
            visible: root.enabled_

            ColumnLayout {
                id: list
                width: parent.width
                spacing: 2

                Repeater {
                    // Un seul point d'accès par SSID (le plus fort), réseau connecté en tête
                    // ScriptModel : délégués conservés entre mises à jour (garde saisie et panneau ouverts)
                    model: ScriptModel {
                        values: {
                            const best = {};
                            for (const n of root.networks) {
                                if (!n.name) continue;
                                if (!best[n.name] || n.connected || root.strength(n) > root.strength(best[n.name]))
                                    if (!best[n.name]?.connected) best[n.name] = n;
                            }
                            return Object.values(best).sort((a, b) => (b.connected - a.connected) || (root.strength(b) - root.strength(a)));
                        }
                    }

                    ColumnLayout {
                        id: entry
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        Connections {
                            target: entry.modelData
                            function onConnectionFailed(reason) {
                                // Mot de passe absent ou refusé → champ de saisie tout de suite
                                const askPass = root.secured(entry.modelData)
                                    && (reason === ConnectionFailReason.NoSecrets
                                        || reason === ConnectionFailReason.WifiClientFailed
                                        || reason === ConnectionFailReason.WifiAuthTimeout);
                                root.errorText = askPass ? "" : "Échec de connexion à " + entry.modelData.name + " (" + ConnectionFailReason.toString(reason) + ")";
                                if (askPass) root.pendingSsid = entry.modelData.name;
                            }
                        }

                        ListRow {
                            icon: root.sigIcon(root.strength(entry.modelData))
                            iconColor: entry.modelData.connected ? Theme.green : Theme.subtext
                            label: entry.modelData.name
                            labelFont: Theme.labelFont
                            detail: root.secured(entry.modelData) ? Theme.ic(0xf033e) : ""
                            active: entry.modelData.connected
                            busy: entry.modelData.stateChanging
                            actionIcon: entry.modelData.connected ? Theme.ic(0xf0493) : ""
                            actionActive: root.showIpSettings
                            onActionClicked: root.showIpSettings = !root.showIpSettings
                            onClicked: {
                                root.errorText = "";
                                if (entry.modelData.connected) entry.modelData.disconnect();
                                else if (entry.modelData.known || !root.secured(entry.modelData)) entry.modelData.connect();
                                else root.pendingSsid = root.pendingSsid === entry.modelData.name ? "" : entry.modelData.name;
                            }
                        }

                        // Réglages IP : dépliage animé (même animation que le Bluetooth)
                        Item {
                            id: ipPanel
                            readonly property bool open: entry.modelData.connected && root.showIpSettings
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
                                sourceComponent: IpSettings {
                                    iface: root.wifiDev?.name ?? ""
                                    network: entry.modelData
                                    onForgotten: root.showIpSettings = false
                                }
                            }
                        }

                        // Saisie du mot de passe pour un réseau inconnu
                        RowLayout {
                            visible: root.pendingSsid === entry.modelData.name
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            onVisibleChanged: if (visible) pass.forceActiveFocus()

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.08)
                                border.color: pass.activeFocus ? Theme.blue : Theme.pillBorder
                                TextInput {
                                    id: pass
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    echoMode: TextInput.Password
                                    onAccepted: connectBtn.clicked()
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: pass.text === ""
                                        text: "Mot de passe"
                                        color: Theme.muted
                                        font: pass.font
                                    }
                                }
                            }
                            ActionButton {
                                id: connectBtn
                                icon: Theme.ic(0xf012c)
                                accent: Theme.green
                                onClicked: {
                                    entry.modelData.connectWithPsk(pass.text);
                                    pass.text = "";
                                    root.pendingSsid = "";
                                }
                            }
                        }
                    }
                }
            }
        }

    }
}
