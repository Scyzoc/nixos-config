import QtQuick
import QtQuick.Layouts

// Bouton texte/icône des popups
Rectangle {
    id: root
    property string icon: ""
    property string iconFont: Theme.font   // ex. "DeviceIcons" pour les icônes maison
    property string label: ""
    property color accent: Theme.text
    property bool highlighted: false
    property bool busy: false            // pulsation de l'icône pendant une action en cours
    property bool glowing: false         // lueur pulsée autour du bouton (ex. connexion VPN)
    property color glowColor: Theme.peach
    signal clicked()

    implicitHeight: 32
    implicitWidth: content.implicitWidth + 20
    radius: 8
    color: highlighted ? Qt.rgba(accent.r, accent.g, accent.b, 0.25)
                       : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
    border.color: glowing ? glowColor : highlighted ? accent : Theme.pillBorder
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }
    // Clic : léger enfoncement (rebond au relâchement) + flash
    scale: ma.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    ClickFx { id: fx; color: root.accent }

    // Lueur : halo qui respire autour du bouton + fond teinté
    property real glow: 0
    SequentialAnimation on glow {
        running: root.glowing
        loops: Animation.Infinite
        NumberAnimation { from: 0.25; to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) glowFade.start()
    }
    NumberAnimation { id: glowFade; target: root; property: "glow"; to: 0; duration: 400; easing.type: Easing.OutQuad }
    Repeater {
        // 3 anneaux de plus en plus larges et transparents = halo doux
        model: 3
        Rectangle {
            required property int index
            z: -1
            anchors.fill: parent
            anchors.margins: -(index + 1) * 2
            radius: root.radius + (index + 1) * 2
            color: "transparent"
            border.width: 2
            border.color: root.glowColor
            opacity: root.glow * (0.28 - index * 0.08)
            visible: root.glow > 0
        }
    }
    // Réussite (lueur terminée, bouton désormais actif) : petit rebond,
    // onde qui s'élargit et flash de la couleur d'accent
    onGlowingChanged: if (!glowing && highlighted) success.restart()
    property real bump: 1
    property real wave: 0
    transform: Scale { origin.x: root.width / 2; origin.y: root.height / 2; xScale: root.bump; yScale: root.bump }
    ParallelAnimation {
        id: success
        SequentialAnimation {
            NumberAnimation { target: root; property: "bump"; to: 1.08; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "bump"; to: 1; duration: 420; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: root; property: "wave"; from: 0; to: 1; duration: 750; easing.type: Easing.OutCubic }
    }
    Rectangle {
        z: -1
        anchors.centerIn: parent
        width: parent.width + root.wave * 14
        height: parent.height + root.wave * 14
        radius: root.radius + root.wave * 7
        color: "transparent"
        border.width: 2
        border.color: root.accent
        opacity: (1 - root.wave) * 0.7
        visible: root.wave > 0 && root.wave < 1
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.accent
        opacity: (1 - root.wave) * 0.3
        visible: root.wave > 0 && root.wave < 1
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.glowColor
        opacity: root.glow * 0.1
        visible: root.glow > 0
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 6
        BarText {
            visible: root.icon !== ""
            text: root.icon
            font.family: root.iconFont
            color: root.glowing ? root.glowColor : root.accent
            Behavior on color { ColorAnimation { duration: 200 } }
            font.pixelSize: 15
            SequentialAnimation on opacity {
                running: root.busy
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 450 }
                NumberAnimation { to: 1; duration: 450 }
                onStopped: parent.opacity = 1
            }
        }
        BarText { visible: root.label !== ""; text: root.label; font.pixelSize: 12 }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { fx.play(); root.clicked(); }
    }
}
