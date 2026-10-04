import QtQuick

// Glissière horizontale 0..1 ; émet moved(v) pendant le glisser
Item {
    id: root

    property real value: 0
    property color accent: Theme.blue
    property bool interactive: true
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
            width: parent.width * root.shown
            height: parent.height
            radius: 3
            color: root.accent
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
