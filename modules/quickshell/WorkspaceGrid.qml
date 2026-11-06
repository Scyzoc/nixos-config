import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

// Grille de boutons de workspaces, une ligne par écran (menu clic droit des workspaces)
ColumnLayout {
    id: grid

    property var screens: []              // [{ name, workspaces: [HyprlandWorkspace] }]
    property int current: -1              // workspace grisé (le workspace du menu lui-même)
    property var marked: []               // ids en surbrillance (déjà liés)
    property string dimScreen: ""         // écran dont les workspaces sont grisés
    property color markColor: Theme.blue
    signal picked(int id)

    Layout.fillWidth: true
    spacing: 2

    Repeater {
        model: grid.screens

        RowLayout {
            id: screenRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 8

            BarText {
                visible: grid.screens.length > 1
                text: screenRow.modelData.name
                color: Theme.subtext
                font.family: Theme.labelFont
                font.pixelSize: 11
                Layout.preferredWidth: 36
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 5
            }

            Flow {
                Layout.fillWidth: true
                spacing: 3

                Repeater {
                    model: screenRow.modelData.workspaces

                    ActionButton {
                        required property HyprlandWorkspace modelData
                        readonly property bool isSelf: modelData.id === grid.current || screenRow.modelData.name === grid.dimScreen
                        width: 30
                        height: 26
                        label: modelData.name
                        enabled: !isSelf
                        opacity: isSelf ? 0.3 : 1
                        accent: grid.markColor
                        highlighted: grid.marked.indexOf(modelData.id) >= 0
                        onClicked: grid.picked(modelData.id)

                        // Workspace occupé
                        Rectangle {
                            visible: !parent.isSelf && parent.modelData.toplevels.values.length > 0
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 4
                            width: 5; height: 5; radius: 2.5
                            color: Theme.yellow
                        }
                    }
                }
            }
        }
    }
}
