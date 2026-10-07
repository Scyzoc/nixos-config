import QtQuick
import QtQuick.Layouts
import Quickshell

// Minuteurs et chronomètre (TimerState) : pastille masquée tant que rien ne tourne.
// Minuteur le plus proche en compte à rebours (rouge les 10 dernières secondes),
// chronomètre à côté. Terminé : cloche qui sonne, clic = acquitter. Clic : menu.
Pill {
    id: root

    readonly property var next: TimerState.running[0] ?? null
    readonly property int secsLeft: next ? TimerState.remaining(next) : 0
    readonly property bool ringing: TimerState.finished.length > 0
    readonly property bool urgent: next !== null && secsLeft <= 10
    readonly property color tint: ringing ? Theme.red : urgent ? Theme.red : Theme.peach

    alert: ringing
    tooltip: TimerState.active ? TimerState.describe() : ""

    // Apparition : la pastille s'ouvre en largeur ; masquée : retirée de la barre
    readonly property bool shown: TimerState.active
    Layout.preferredWidth: shown ? implicitWidth : 0
    Behavior on Layout.preferredWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }
    visible: opacity > 0
    clip: true

    // --- Minuteur ----------------------------------------------------------------------
    BarText {
        id: bell
        visible: root.ringing || root.next !== null
        text: Theme.ic(root.ringing ? 0xf009e : 0xf051b)    // md-bell_ring / md-timer_outline
        color: root.tint
        Behavior on color { ColorAnimation { duration: 300 } }
        // Cloche qui s'agite pendant la sonnerie
        transformOrigin: Item.Top
        SequentialAnimation on rotation {
            running: root.ringing
            loops: Animation.Infinite
            NumberAnimation { to: 18; duration: 90 }
            NumberAnimation { to: -18; duration: 180 }
            NumberAnimation { to: 0; duration: 90 }
            PauseAnimation { duration: 400 }
            onRunningChanged: if (!running) bell.rotation = 0
        }
    }
    BarText {
        visible: root.ringing || root.next !== null
        text: root.ringing ? "Terminé" : TimerState.fmt(root.secsLeft)
        color: root.tint
        font.family: Theme.labelFont
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
        // Battement les 10 dernières secondes
        scale: 1
        SequentialAnimation on scale {
            running: root.urgent && !root.ringing
            loops: Animation.Infinite
            NumberAnimation { to: 1.12; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { to: 1; duration: 380; easing.type: Easing.InOutQuad }
            PauseAnimation { duration: 500 }
        }
    }
    BarText {
        readonly property string name: root.ringing ? TimerState.title(TimerState.finished[0])
                                                    : (root.next?.label ?? "")
        visible: !root.compact && name !== ""
        text: name
        color: Theme.subtext
        font.family: Theme.labelFont
        Layout.maximumWidth: 110
        elide: Text.ElideRight
    }
    // Jauge du minuteur le plus proche (se vide)
    Rectangle {
        visible: root.next !== null && !root.ringing && !root.compact
        implicitWidth: 34
        implicitHeight: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.12)
        Rectangle {
            width: parent.width * (root.next ? TimerState.progress(root.next) : 0)
            height: parent.height
            radius: parent.radius
            color: root.tint
        }
    }
    BarText {
        visible: TimerState.running.length > (root.ringing ? 0 : 1)
        text: "+" + (TimerState.running.length - (root.ringing ? 0 : 1))
        color: Theme.muted
        font.pixelSize: 11
    }

    // --- Chronomètre -------------------------------------------------------------------
    Rectangle {
        visible: TimerState.swActive && (root.ringing || root.next !== null)
        implicitWidth: 1
        implicitHeight: 14
        color: Theme.pillBorder
    }
    BarText {
        visible: TimerState.swActive
        text: Theme.ic(0xf13ab)    // md-timer
        color: TimerState.swRunning ? Theme.teal : Theme.muted
    }
    BarText {
        visible: TimerState.swActive
        text: TimerState.fmt(TimerState.swElapsed / 1000)
        color: TimerState.swRunning ? Theme.teal : Theme.muted
        font.family: Theme.labelFont
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }

    onClicked: event => {
        if (root.ringing && event.button !== Qt.RightButton) TimerState.dismiss();
        else popup.toggle();
    }

    // --- Menu ------------------------------------------------------------------------------
    BarPopup {
        id: popup
        target: root
        contentWidth: 300

        PopupHeader { title: "Minuteurs" }

        BarText {
            font.family: Theme.labelFont
            visible: TimerState.timers.length === 0
            text: "Aucun minuteur. Demande à l'assistant (Super+K) :\n« mets un minuteur de 10 minutes »"
            color: Theme.muted
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Repeater {
            model: TimerState.timers
            ColumnLayout {
                id: row
                required property var modelData
                readonly property var t: modelData
                readonly property color accent: t.done ? Theme.red : TimerState.remaining(t) <= 10 ? Theme.red : Theme.peach
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    BarText { text: Theme.ic(row.t.done ? 0xf009e : 0xf051b); font.pixelSize: 20; color: row.accent }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        BarText {
                            font.family: Theme.labelFont
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: TimerState.title(row.t)
                            color: Theme.subtext
                            font.pixelSize: 12
                        }
                        BarText {
                            text: row.t.done ? "Terminé" : TimerState.fmt(TimerState.remaining(row.t))
                            font.family: Theme.titleFont
                            font.pixelSize: 20
                            font.bold: true
                            font.features: { "tnum": 1 }
                            color: row.t.done ? Theme.red : Theme.text
                        }
                    }
                    // +1 min (relance aussi un minuteur terminé)
                    IconButton {
                        icon: "+1"
                        onClicked: TimerState.extend(row.t.id, 60)
                    }
                    IconButton {
                        icon: Theme.ic(0xf0156)    // md-close
                        accent: Theme.red
                        onClicked: TimerState.remove(row.t.id)
                    }
                }
                Slider {
                    Layout.fillWidth: true
                    visible: !row.t.done
                    interactive: false
                    value: TimerState.progress(row.t)
                    accent: row.accent
                }
            }
        }

        // Lancement rapide
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [60, 300, 600, 1500]
                ActionButton {
                    required property int modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: Theme.ic(0xf051b)
                    label: TimerState.human(modelData)
                    accent: Theme.peach
                    onClicked: TimerState.add(modelData, "")
                }
            }
        }

        Separator {}
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            BarText { text: Theme.ic(0xf13ab); font.pixelSize: 20; color: TimerState.swRunning ? Theme.teal : Theme.muted }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                BarText { text: "Chronomètre"; color: Theme.subtext; font.pixelSize: 12; font.family: Theme.labelFont }
                BarText {
                    text: TimerState.fmt(TimerState.swElapsed / 1000)
                    font.family: Theme.titleFont
                    font.pixelSize: 20
                    font.bold: true
                    font.features: { "tnum": 1 }
                    color: TimerState.swRunning ? Theme.teal : Theme.text
                }
            }
            IconButton {
                icon: Theme.ic(TimerState.swRunning ? 0xf03e4 : 0xf040a)    // md-pause / md-play
                accent: Theme.teal
                checked: TimerState.swRunning
                onClicked: TimerState.stopwatch("toggle")
            }
            IconButton {
                icon: Theme.ic(0xf0450)    // md-refresh
                onClicked: TimerState.stopwatch("reset")
            }
        }
    }
}
