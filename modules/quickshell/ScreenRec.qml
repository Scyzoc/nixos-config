import QtQuick
import QtQuick.Layouts

// Enregistrement d'écran à droite de l'heure (même principe que VoiceRec) : point REC qui pulse +
// durée pendant l'enregistrement ; croix si l'enregistrement a échoué. État dans ScreenState.
// La fin réussie est annoncée par l'île (Island.qml).
Item {
    id: root

    // Dernière phase non vide : garde le contenu affiché pendant la fermeture
    property string shown: ""
    Connections {
        target: ScreenState
        function onPhaseChanged() { if (ScreenState.phase !== "") root.shown = ScreenState.phase; }
    }
    readonly property Item page: shown === "rec" ? recPage : shown !== "" ? resultPage : null
    readonly property real target: ScreenState.active && page ? content.x + page.implicitWidth : 0
    readonly property alias animating: widthAnim.running

    property real w: target
    Behavior on w {
        NumberAnimation {
            id: widthAnim
            duration: 320
            easing.type: Easing.OutCubic
            onStopped: if (!ScreenState.active) root.shown = ""
        }
    }
    readonly property bool live: w > 0.5
    component Fade: Behavior {
        id: fade
        enabled: root.live
        SequentialAnimation {
            PauseAnimation { duration: fade.targetValue > 0.5 ? 110 : 0 }
            NumberAnimation { duration: fade.targetValue > 0.5 ? 170 : 110; easing.type: Easing.InOutQuad }
        }
    }

    Layout.leftMargin: -6
    Layout.preferredWidth: w
    implicitHeight: 20
    clip: true
    opacity: ScreenState.active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    BarText {
        id: sep
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        text: "·"
        color: Theme.muted
        font.family: Theme.labelFont
    }

    Item {
        id: content
        x: sep.x + sep.implicitWidth + 6
        height: parent.height

        RowLayout {
            id: recPage
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            opacity: root.shown === "rec" ? 1 : 0
            Fade on opacity {}
            visible: opacity > 0

            Rectangle {
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: Theme.red
                SequentialAnimation on opacity {
                    running: recPage.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            BarText {
                text: ScreenState.clock
                color: Theme.subtext
                font.family: Theme.labelFont
                font.features: { "tnum": 1 }
            }
        }

        RowLayout {
            id: resultPage
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            readonly property bool on: root.shown !== "" && root.shown !== "rec"
            opacity: on ? 1 : 0
            Fade on opacity {}
            visible: opacity > 0
            onOnChanged: if (on) pop.restart()

            BarText {
                id: mark
                text: Theme.ic(0xf0156)    // md-close
                color: Theme.red
                font.pixelSize: 15
            }
            BarText {
                text: "Échec"
                color: Theme.text
                font.family: Theme.labelFont
            }
            SequentialAnimation {
                id: pop
                PropertyAction { target: mark; property: "scale"; value: 0.3 }
                PauseAnimation { duration: 80 }
                NumberAnimation { target: mark; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
            }
        }
    }
}
