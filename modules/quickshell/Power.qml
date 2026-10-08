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
    property string hoveredLabel: ""
    readonly property string armedLabel: ({ logout: "Déconnexion", reboot: "Redémarrer", poweroff: "Éteindre" }[armed] ?? "")
    // Désarme la confirmation si le 2e clic ne vient pas
    Timer { id: disarm; interval: 3000; onTriggered: root.armed = "" }
    property bool planMode: false            // mode programmation (bouton minuteur)
    property string planAction: ""           // action choisie (déplie le planificateur ; "" = replié)
    property int planIdx: 6                  // délai choisi : index dans planSteps
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
        planMode = false;
    }

    // Délais proposés par la glissière (minutes)
    readonly property var planSteps: [5, 10, 15, 20, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300, 360, 480]
    readonly property int planMin: planSteps[planIdx]
    function fmtMin(m) {
        const h = Math.floor(m / 60), r = m % 60;
        return h === 0 ? r + " min" : h + " h" + (r ? " " + (r < 10 ? "0" : "") + r : "");
    }
    function schedulable(id) { return id === "suspend" || id === "reboot" || id === "poweroff"; }
    function actionColor(a) { return a === "suspend" ? Theme.mauve : a === "reboot" ? Theme.peach : Theme.red; }

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
        if (action.id === "plan") {
            planMode = !planMode;
            planAction = "";
            armed = "";
            return;
        }
        // Mode programmation : le bouton choisit l'action au lieu de l'exécuter
        if (planMode) {
            if (schedulable(action.id)) planAction = planAction === action.id ? "" : action.id;
            return;
        }
        if (action.confirm && armed !== action.id) { armed = action.id; disarm.restart(); return; }
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
            root.hoveredLabel = "";
            root.planMode = false;
            root.planAction = "";
            if (visible) status.running = true;
        }

        // Icônes seules : verrouiller / veille / déconnexion, puis éteindre / redémarrer / minuteur
        Repeater {
            model: [
                [
                    { id: "lock", label: "Verrouiller", icon: 0xf033e, color: Theme.blue, confirm: false, cmd: [Paths.hyprlock] },
                    { id: "suspend", label: "Veille", icon: 0xf04b2, color: Theme.mauve, confirm: false, cmd: [Paths.systemctl, "suspend"] },
                    { id: "logout", label: "Déconnexion", icon: 0xf0343, color: Theme.yellow, confirm: true, cmd: [] }
                ],
                [
                    { id: "poweroff", label: "Éteindre", icon: 0xf0425, color: Theme.red, confirm: true, cmd: [Paths.systemctl, "poweroff"] },
                    { id: "reboot", label: "Redémarrer", icon: 0xf0709, color: Theme.peach, confirm: true, cmd: [Paths.systemctl, "reboot"] },
                    { id: "plan", label: "Programmer", icon: 0xf13ab, color: Theme.yellow, confirm: false, cmd: [] }    // md-timer
                ]
            ]
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: parent.modelData
                    // Boutons de même largeur (base identique + partage égal)
                    ActionButton {
                        id: btn
                        required property var modelData
                        readonly property bool isPlan: modelData.id === "plan"
                        readonly property bool canPlan: root.schedulable(modelData.id)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 44
                        iconSize: 20
                        icon: Theme.ic(modelData.icon)
                        accent: modelData.color
                        // Armé (1er clic d'une action à confirmer) : lueur pulsée
                        glowing: root.armed === modelData.id
                        glowColor: modelData.color
                        // Mode programmation : minuteur allumé, action choisie allumée,
                        // actions non programmables estompées
                        highlighted: isPlan ? root.planMode : root.planMode && root.planAction === modelData.id
                        opacity: root.planMode && !isPlan && !canPlan ? 0.25 : 1
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        onHoveredChanged: root.hoveredLabel = hovered ? modelData.label : (root.hoveredLabel === modelData.label ? "" : root.hoveredLabel)
                        onClicked: root.run(modelData)

                        // Badge minuteur sur les actions programmables (arrive en zoom)
                        BarText {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 3
                            anchors.rightMargin: 5
                            text: Theme.ic(0xf13ab)
                            color: Theme.yellow
                            font.pixelSize: 10
                            readonly property bool shown: root.planMode && btn.canPlan
                            opacity: shown ? 1 : 0
                            scale: shown ? 1 : 0.3
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                        }
                        // Programmation en cours sur cette action : point jaune
                        Rectangle {
                            visible: root.schedAction === btn.modelData.id && !root.planMode
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 5
                            width: 6; height: 6; radius: 3
                            color: Theme.yellow
                        }
                    }
                }
            }
        }

        // Nom de l'action survolée, consigne ou demande de confirmation (hauteur fixe : pas de saut)
        BarText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.labelFont
            font.pixelSize: 12
            text: root.armed !== "" ? "Recliquer pour confirmer : " + root.armedLabel
                : root.planMode && root.planAction === "" ? "Choisis l'action à programmer"
                : (root.hoveredLabel || " ")
            color: root.armed !== "" ? Theme.red : root.planMode ? Theme.yellow : Theme.subtext
        }

        // Planificateur : déplié une fois l'action choisie (même animation que les
        // réglages Bluetooth / Wi-Fi)
        Item {
            id: planner
            readonly property bool open: root.planMode && root.planAction !== ""
            readonly property color accent: root.actionColor(root.planAction)
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
                spacing: 8

                // Lecture en direct : délai en gros, heure d'échéance à droite
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    BarText {
                        text: "dans " + root.fmtMin(root.planMin)
                        font.family: Theme.titleFont
                        font.pixelSize: 22
                        font.bold: true
                        color: planner.accent
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Layout.fillWidth: true
                    }
                    BarText {
                        text: "à " + Qt.formatDateTime(new Date(clock.date.getTime() + root.planMin * 60000), "HH:mm")
                        font.family: Theme.labelFont
                        font.pixelSize: 13
                        color: Theme.subtext
                    }
                }

                // Glissière crantée (délais de planSteps) ; molette = cran suivant
                Slider {
                    Layout.fillWidth: true
                    accent: planner.accent
                    value: root.planIdx / (root.planSteps.length - 1)
                    onMoved: v => root.planIdx = Math.round(v * (root.planSteps.length - 1))
                }

                ActionButton {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    icon: Theme.ic(0xf13ab)
                    label: root.actionLabel(root.planAction) + " dans " + root.fmtMin(root.planMin)
                    accent: planner.accent
                    highlighted: true
                    onClicked: root.schedule([root.planAction, String(root.planMin)])
                }
            }
        }

        // Programmation en cours
        Separator { visible: root.schedAction !== "" }
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
    }
}
