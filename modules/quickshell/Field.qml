import QtQuick
import QtQuick.Layouts

// Champ de saisie des popups (libellé + zone de texte)
ColumnLayout {
    id: root
    property string label: ""
    property string placeholder: ""
    property alias text: input.text
    property alias validator: input.validator
    property bool valid: true
    signal accepted()

    Layout.fillWidth: true
    spacing: 3

    BarText { text: root.label; color: Theme.subtext; font.pixelSize: 11; visible: root.label !== ""; font.family: Theme.labelFont }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: !root.valid && input.text !== "" ? Theme.red : (input.activeFocus ? Theme.subtext : Theme.pillBorder)

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.labelFont
            font.pixelSize: 12
            clip: true
            selectByMouse: true
            onAccepted: root.accepted()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: root.placeholder
                color: Theme.muted
                font: input.font
            }
        }
    }
}
