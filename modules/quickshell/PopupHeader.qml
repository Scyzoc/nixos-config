import QtQuick
import QtQuick.Layouts

// En-tête de popup : titre + boutons optionnels (enfants) + interrupteur optionnel
RowLayout {
    id: root
    property string title: ""
    property bool showToggle: false
    property bool checked: false
    property color toggleAccent: Theme.blue
    default property alias actions: actionRow.data
    signal toggled()

    Layout.fillWidth: true

    BarText {
        text: root.title
        font.family: Theme.titleFont
        font.bold: true
        font.pixelSize: 15
        Layout.fillWidth: true
    }
    // Boutons d'action placés à gauche de l'interrupteur
    RowLayout {
        id: actionRow
        spacing: 4
    }
    Toggle {
        visible: root.showToggle
        checked: root.checked
        accent: root.toggleAccent
        onToggled: root.toggled()
    }
}
