import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Menu d'alimentation (remplace wlogout) + arrêt/veille/redémarrage programmés
// Les actions destructrices sont confirmées par un 2e clic
Pill {
    id: root

    property string armed: ""
    property string planAction: ""           // action choisie (déplie le planificateur ; "" = replié)
    property string schedAction: ""          // action programmée en cours ("" = aucune)
    property real schedAt: 0                 // échéance (ms epoch)

    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property int remaining: schedAction === "" ? 0 : Math.max(0, Math.round((schedAt - clock.date.getTime()) / 1000))

    // Infobulle seulement quand une action est programmée (compte à rebours)
    tooltip: schedAction === "" ? ""
             : ({ poweroff: "Arrêt", suspend: "Mise en veille", reboot: "Redémarrage" }[schedAction] ?? schedAction)
               + " dans " + fmtRemaining(remaining)

    function fmtRemaining(s) {
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        if (h > 0) return h + "h" + (m < 10 ? "0" : "") + m;
        if (m > 0) return m + " min";
        return s + " s";
    }
    function actionLabel(a) { return a === "suspend" ? "Veille" : a === "reboot" ? "Redémarrage" : "Arrêt"; }

    // État lu depuis le timer systemd (qs-power.timer)
    Process {
        id: status
        command: [Paths.powerSchedule, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(" ");
                if (p.length === 2) {
                    root.schedAction = p[0];
                    root.schedAt = Number(p[1]) * 1000;
                } else {
                    root.schedAction = "";
                    root.schedAt = 0;
                }
            }
        }
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: status.running = true }

    Process {
        id: scheduler
        onExited: status.running = true
    }
    function schedule(args) {
        scheduler.command = [Paths.powerSchedule].concat(args);
        scheduler.running = true;
        planAction = "";
    }

    BarText { text: Theme.ic(0x23fb); color: Theme.red }
    BarText {
        visible: root.schedAction !== ""
        text: (root.schedAction === "suspend" ? Theme.ic(0xf04b2) : root.schedAction === "reboot" ? Theme.ic(0xf0709) : "")
              + " " + root.fmtRemaining(root.remaining)
        color: Theme.yellow
        font.pixelSize: 12
    }

    onClicked: popup.toggle()

    function run(action) {
        if (action.confirm && armed !== action.id) { armed = action.id; return; }
        armed = "";
        popup.visible = false;
        if (action.id === "logout") Hyprland.dispatch("exit");
        else Quickshell.execDetached(action.cmd);
    }

    BarPopup {
        id: popup
        target: root
        contentWidth: 250
        onVisibleChanged: {
            root.armed = "";
            root.planAction = "";
            if (visible) status.running = true;
        }

        Repeater {
            model: [
                { id: "lock", label: "Verrouiller", icon: 0xf033e, color: Theme.blue, confirm: false, cmd: [Paths.hyprlock] },
                { id: "suspend", label: "Veille", icon: 0xf04b2, color: Theme.mauve, confirm: false, cmd: [Paths.systemctl, "suspend"] },
                { id: "logout", label: "Déconnexion", icon: 0xf0343, color: Theme.yellow, confirm: true, cmd: [] },
                { id: "reboot", label: "Redémarrer", icon: 0xf0709, color: Theme.peach, confirm: true, cmd: [Paths.systemctl, "reboot"] },
                { id: "poweroff", label: "Éteindre", icon: 0xf0425, color: Theme.red, confirm: true, cmd: [Paths.systemctl, "poweroff"] }
            ]
            ListRow {
                required property var modelData
                icon: Theme.ic(modelData.icon)
                iconColor: modelData.color
                label: root.armed === modelData.id ? "Confirmer ?" : modelData.label
                active: root.armed === modelData.id
                onClicked: root.run(modelData)
            }
        }

        Separator {}

        // Programmation en cours
        RowLayout {
            visible: root.schedAction !== ""
            Layout.fillWidth: true
            spacing: 8
            BarText { text: Theme.ic(0xf0954); color: Theme.yellow; font.pixelSize: 16 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                BarText {
                    font.family: Theme.labelFont
                    text: root.actionLabel(root.schedAction) + " à " + Qt.formatDateTime(new Date(root.schedAt), "HH:mm")
                    font.bold: true
                }
                BarText { text: "dans " + root.fmtRemaining(root.remaining); color: Theme.subtext; font.pixelSize: 11; font.family: Theme.labelFont }
            }
            ActionButton {
                icon: Theme.ic(0xf0156)
                label: "Annuler"
                accent: Theme.red
                onClicked: root.schedule(["cancel"])
            }
        }

        BarText {
            font.family: Theme.labelFont
            // Boutons en icônes seules : l'action choisie est rappelée ici
            text: (root.schedAction === "" ? "Programmer" : "Reprogrammer")
                  + (root.planAction !== "" ? " : " + root.actionLabel(root.planAction) : "")
            color: Theme.subtext
            font.pixelSize: 12
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "poweroff", label: "Arrêt", icon: 0xf0425, color: Theme.red },
                    { id: "suspend", label: "Veille", icon: 0xf04b2, color: Theme.mauve },
                    { id: "reboot", label: "Redémarrer", icon: 0xf0709, color: Theme.peach }
                ]
                // Icône seule, 3 boutons de même largeur (base identique + partage égal)
                ActionButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: Theme.ic(modelData.icon)
                    accent: modelData.color
                    highlighted: root.planAction === modelData.id
                    onClicked: root.planAction = root.planAction === modelData.id ? "" : modelData.id
                }
            }
        }

        // Planificateur : déplié par le choix Arrêt / Veille / Redémarrer (même animation
        // que les réglages Bluetooth / Wi-Fi)
        Item {
            id: planner
            readonly property bool open: root.planAction !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: open ? plannerBody.implicitHeight : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            visible: Layout.preferredHeight > 0
            clip: true
            opacity: open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            ColumnLayout {
                id: plannerBody
                width: parent.width
                y: planner.open ? 0 : -14
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                spacing: 6

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: [
                            { min: 15, label: "15 min" }, { min: 30, label: "30 min" }, { min: 45, label: "45 min" },
                            { min: 60, label: "1 h" }, { min: 90, label: "1 h 30" }, { min: 120, label: "2 h" }
                        ]
                        ActionButton {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.label
                            onClicked: root.schedule([root.planAction, String(modelData.min)])
                        }
                    }
                }

                // Durée libre en minutes
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 8
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: custom.activeFocus ? Theme.subtext : Theme.pillBorder
                        TextInput {
                            id: custom
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 12
                            validator: IntValidator { bottom: 1; top: 1440 }
                            onAccepted: okBtn.clicked()
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: custom.text === ""
                                text: "Autre durée (min)"
                                color: Theme.muted
                                font: custom.font
                            }
                        }
                    }
                    ActionButton {
                        id: okBtn
                        icon: Theme.ic(0xf012c)
                        accent: Theme.green
                        onClicked: {
                            if (!custom.acceptableInput) return;
                            root.schedule([root.planAction, custom.text]);
                            custom.text = "";
                        }
                    }
                }
            }
        }
    }
}
