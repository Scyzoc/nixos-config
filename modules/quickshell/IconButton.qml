import QtQuick

// Bouton carré arrondi avec une seule icône ; teinté de la couleur d'accent quand actif
Rectangle {
    id: root
    property string icon: ""
    property color accent: Theme.text
    property bool checked: false
    property bool busy: false
    signal clicked()

    implicitWidth: 34
    implicitHeight: 34
    radius: 10
    color: checked ? Qt.rgba(accent.r, accent.g, accent.b, ma.containsMouse ? 0.35 : 0.22)
                   : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
    border.color: checked ? accent : Theme.pillBorder
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }
    // Clic : léger enfoncement (rebond au relâchement) + flash
    scale: ma.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    ClickFx { id: fx; color: root.accent }

    BarText {
        anchors.centerIn: parent
        text: root.icon
        color: root.checked ? root.accent : Theme.subtext
        font.pixelSize: 17
        Behavior on color { ColorAnimation { duration: 150 } }

        // Pulsation pendant une action en cours (ex. VPN qui se connecte)
        SequentialAnimation on opacity {
            running: root.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 450 }
            NumberAnimation { to: 1; duration: 450 }
            onStopped: parent.opacity = 1
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
