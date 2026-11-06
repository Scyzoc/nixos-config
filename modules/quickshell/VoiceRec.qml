import QtQuick
import QtQuick.Layouts

// Dictée vocale à droite de l'heure (comme le compteur de sommeil) : point REC qui pulse, onde
// du micro (cava) remplacée par le texte en direct dès les premiers mots, et durée ; puis orbe (ThinkingOrb) pendant la transcription ; puis les points de l'orbe forment une coche verte (collé / envoyé) ou une croix (échec).
// État dans VoiceState. Une seule animation de largeur (w) ; les pages sont superposées à
// leur largeur naturelle et se fondent l'une dans l'autre, rien n'est jamais comprimé.
Item {
    id: root

    // Dernière phase non vide : garde le contenu affiché pendant la fermeture
    property string shown: ""
    Connections {
        target: VoiceState
        function onPhaseChanged() { if (VoiceState.phase !== "") root.shown = VoiceState.phase; }
    }
    readonly property bool done: shown === "done" || shown === "sent"
    readonly property Item page: shown === "rec" ? recPage : (shown === "busy" || done) ? busyPage : shown !== "" ? resultPage : null
    readonly property real target: VoiceState.active && page ? content.x + page.implicitWidth : 0
    readonly property alias animating: widthAnim.running

    property real w: target
    Behavior on w {
        NumberAnimation {
            id: widthAnim
            duration: 320
            easing.type: Easing.OutCubic
            // Fermée : on oublie la dernière phase (la prochaine ouverture part de zéro)
            onStopped: if (!VoiceState.active) root.shown = ""
        }
    }
    // Fondus entre pages seulement quand c'est visible ; l'entrante attend que la sortante
    // ait disparu (pas de textes superposés)
    readonly property bool live: w > 0.5
    component Fade: Behavior {
        id: fade
        enabled: root.live
        SequentialAnimation {
            PauseAnimation { duration: fade.targetValue > 0.5 ? 110 : 0 }
            NumberAnimation { duration: fade.targetValue > 0.5 ? 170 : 110; easing.type: Easing.InOutQuad }
        }
    }

    // L'espacement de la pastille (6) est absorbé par la marge négative : 0 px quand fermé
    Layout.leftMargin: -6
    Layout.preferredWidth: w
    implicitHeight: 20
    clip: true
    opacity: VoiceState.active ? 1 : 0
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

        // --- Enregistrement --------------------------------------------------------------
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
            Row {
                visible: VoiceState.live === ""
                spacing: 2
                Layout.preferredHeight: 14
                Repeater {
                    model: VoiceState.bars
                    Rectangle {
                        required property int index
                        width: 2
                        height: Math.max(2, 14 * ((VoiceState.levels[index] ?? 0) / 100))
                        y: (14 - height) / 2
                        radius: 1
                        color: Theme.subtext
                    }
                }
            }
            // Texte en direct : les derniers mots (coupé à gauche)
            BarText {
                visible: VoiceState.live !== ""
                text: VoiceState.live
                color: Theme.text
                font.family: Theme.labelFont
                elide: Text.ElideLeft
                Layout.preferredWidth: Math.min(implicitWidth, 300)
            }
            BarText {
                text: VoiceState.clock
                color: Theme.subtext
                font.family: Theme.labelFont
                font.features: { "tnum": 1 }
            }
        }

        // --- Transcription ---------------------------------------------------------------
        RowLayout {
            id: busyPage
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            opacity: (root.shown === "busy" || root.done) ? 1 : 0
            Fade on opacity {}
            visible: opacity > 0

            ThinkingOrb { color: Theme.peach; running: busyPage.visible; done: root.done }
        }

        // --- Résultat : coche qui rebondit (collé / envoyé) ou croix (échec) ------------------
        RowLayout {
            id: resultPage
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            readonly property bool on: root.shown !== "" && root.shown !== "rec" && root.shown !== "busy" && !root.done
            opacity: on ? 1 : 0
            Fade on opacity {}
            visible: opacity > 0
            onOnChanged: if (on) pop.restart()

            BarText {
                id: mark
                text: Theme.ic(root.done ? 0xf012c : 0xf0156)    // md-check / md-close
                color: root.done ? Theme.green : Theme.red
                font.pixelSize: 15
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
