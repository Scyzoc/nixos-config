import QtQuick

// Bouton Ne pas déranger (menu de la cloche), même look qu'IconButton.
// Activation : l'icône Zzz s'incline en douceur et trois « z » s'envolent en diagonale.
// Désactivation : petit rebond de réveil.
Rectangle {
    id: root

    property bool checked: false
    property color accent: Theme.mauve
    signal clicked()

    implicitWidth: 30
    implicitHeight: 30
    radius: 10
    color: checked ? Qt.rgba(accent.r, accent.g, accent.b, ma.containsMouse ? 0.35 : 0.22)
                   : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
    border.color: checked ? accent : Theme.pillBorder
    border.width: 1
    Behavior on color { ColorAnimation { duration: 200 } }
    Behavior on border.color { ColorAnimation { duration: 200 } }
    scale: ma.pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    ClickFx { id: fx; color: root.accent }

    BarText {
        id: glyph
        anchors.centerIn: parent
        text: Theme.ic(0xf04b2)    // md-sleep (Zzz)
        color: root.checked ? root.accent : Theme.subtext
        font.pixelSize: 16
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    // « z » qui s'envolent (endormissement)
    Repeater {
        id: zs
        model: 3
        BarText {
            id: z
            required property int index
            text: "z"
            color: root.accent
            font.family: Theme.labelFont
            font.weight: Font.Bold
            font.pixelSize: 8 + index * 2
            opacity: 0
            x: root.width / 2 + 2
            y: root.height / 2 - 6

            function fly() { flyAnim.restart(); }
            SequentialAnimation {
                id: flyAnim
                PropertyAction { target: z; property: "opacity"; value: 0 }
                PauseAnimation { duration: z.index * 160 }
                ParallelAnimation {
                    NumberAnimation { target: z; property: "x"; from: root.width / 2 + 2; to: root.width / 2 + 8 + z.index * 5; duration: 750; easing.type: Easing.OutSine }
                    NumberAnimation { target: z; property: "y"; from: root.height / 2 - 6; to: -10 - z.index * 4; duration: 750; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        NumberAnimation { target: z; property: "opacity"; to: 1; duration: 180 }
                        PauseAnimation { duration: 280 }
                        NumberAnimation { target: z; property: "opacity"; to: 0; duration: 290 }
                    }
                }
            }
        }
    }

    // Endormissement : l'icône penche puis revient
    SequentialAnimation {
        id: sleepAnim
        NumberAnimation { target: glyph; property: "rotation"; to: -22; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: glyph; property: "rotation"; to: 0; duration: 520; easing.type: Easing.OutBack }
    }
    // Réveil : sursaut
    SequentialAnimation {
        id: wakeAnim
        NumberAnimation { target: glyph; property: "scale"; to: 1.35; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: glyph; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutElastic }
    }

    onCheckedChanged: {
        if (checked) {
            wakeAnim.stop(); glyph.scale = 1;
            sleepAnim.restart();
            for (let i = 0; i < zs.count; i++) zs.itemAt(i).fly();
        } else {
            sleepAnim.stop(); glyph.rotation = 0;
            wakeAnim.restart();
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { fx.play(); root.clicked(); }
    }
}
