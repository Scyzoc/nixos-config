import QtQuick

// Interrupteur on/off, d'après le « switch » Uiverse de namecho, réduit à 40 × 22 px :
// la bille s'allonge pendant l'appui. Couleurs : celles du thème de la barre.
Rectangle {
    id: root
    property bool checked: false
    property color accent: Theme.blue
    signal toggled()

    readonly property real diameter: 16
    readonly property real wider: 22
    readonly property real offset: (height - diameter) / 2

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? accent : Qt.rgba(1, 1, 1, 0.15)
    Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    Rectangle {
        width: mouse.pressed ? root.wider : root.diameter
        height: root.diameter
        radius: root.diameter / 2
        y: root.offset
        // Position = progression (0 gauche, 1 droite) × course restante : suit la largeur animée,
        // la bille ne dépasse donc jamais du rail
        property real pos: root.checked ? 1 : 0
        x: root.offset + pos * (root.width - width - 2 * root.offset)
        color: "#ffffff"
        Behavior on pos { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
