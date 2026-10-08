import QtQuick

// Glissière horizontale 0..1 ; émet moved(v) pendant le glisser
Item {
    id: root

    property real value: 0
    property color accent: Theme.blue
    property bool interactive: true
    // Reflet qui balaie la partie remplie en boucle (ex. batterie en charge)
    property bool flowing: false
    signal moved(real v)

    implicitHeight: 18
    implicitWidth: 200

    readonly property real shown: drag.pressed ? drag.local : Math.max(0, Math.min(1, value))

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
            id: fill
            width: parent.width * root.shown
            height: parent.height
            radius: 3
            color: root.accent
            clip: root.flowing

            Rectangle {
                id: shine
                visible: root.flowing && fill.width > 0
                width: Math.max(24, track.width * 0.35)
                height: parent.height
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                    GradientStop { position: 1; color: "transparent" }
                }
                // Départ hors de la barre à gauche, sortie au bout de la partie remplie
                SequentialAnimation on x {
                    running: shine.visible && root.visible
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: -shine.width
                        to: fill.width
                        duration: 900 + 900 * root.shown
                        easing.type: Easing.InOutSine
                    }
                    PauseAnimation { duration: 400 }
                }
            }
        }
    }

    Rectangle {
        visible: root.interactive
        width: drag.containsMouse || drag.pressed ? 14 : 10
        height: width
        radius: width / 2
        color: "#ffffff"
        x: root.shown * (root.width - width)
        anchors.verticalCenter: parent.verticalCenter
        Behavior on width { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        id: drag
        property real local: 0
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function update(mx) {
            local = Math.max(0, Math.min(1, mx / width));
            root.moved(local);
        }
        onPressed: event => update(event.x)
        onPositionChanged: event => { if (pressed) update(event.x); }
        onWheel: event => root.moved(Math.max(0, Math.min(1, root.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
