import QtQuick

// Interrupteur on/off
Rectangle {
    id: root
    property bool checked: false
    property color accent: Theme.blue
    signal toggled()

    implicitWidth: 38
    implicitHeight: 20
    radius: 10
    color: checked ? accent : Qt.rgba(1, 1, 1, 0.15)
    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
