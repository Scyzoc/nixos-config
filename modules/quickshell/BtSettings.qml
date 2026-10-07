import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

// Réglages d'un appareil Bluetooth connu (sobre, icônes seules) :
// [icône du type] nom (alias BlueZ) + oublier ; clic sur l'icône → choix du type (mémorisé localement)
Rectangle {
    id: root

    required property BluetoothDevice device
    required property var typeDefs        // [{ id, label, icon, font? }] (BluetoothPill.qml)
    property string type: "auto"          // type choisi pour cet appareil
    property string deviceIcon: ""        // icône actuelle (BluetoothPill.devIcon)
    property string deviceIconFont: Theme.font
    property bool confirmForget: false
    property bool pickType: false         // grille des types ouverte

    signal typeChosen(string type)
    signal forgotten()

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 20
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.04)
    border.color: Theme.pillBorder

    // Nom vide = retour au nom fourni par l'appareil
    function rename() {
        const n = nameField.text.trim();
        root.device.name = n;
        if (n === "") nameField.text = root.device.deviceName;
    }

    // Désarme la corbeille si le 2e clic ne vient pas
    Timer { id: disarm; interval: 3000; onTriggered: root.confirmForget = false }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Nom · valider (si modifié) · oublier
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            // Icône actuelle : ouvre / referme la grille des types
            ActionButton {
                implicitWidth: 30
                implicitHeight: 30
                icon: root.deviceIcon
                iconFont: root.deviceIconFont
                accent: Theme.bluetooth
                highlighted: root.pickType
                onClicked: root.pickType = !root.pickType
            }
            Field {
                id: nameField
                placeholder: root.device.deviceName
                text: root.device.name
                onAccepted: root.rename()
            }
            ActionButton {
                visible: nameField.text.trim() !== root.device.name
                implicitWidth: 30
                implicitHeight: 30
                icon: Theme.ic(0xf012c)
                accent: Theme.green
                onClicked: root.rename()
            }
            ActionButton {
                implicitWidth: 30
                implicitHeight: 30
                icon: Theme.ic(0xf0a7a)
                accent: Theme.red
                highlighted: root.confirmForget
                onClicked: {
                    if (!root.confirmForget) { root.confirmForget = true; disarm.restart(); return; }
                    root.device.forget();
                    root.forgotten();
                }
            }
        }

        // Type d'appareil → icône (Auto = détection BlueZ) ; refermée après le choix
        GridLayout {
            visible: root.pickType
            Layout.fillWidth: true
            columns: 7
            columnSpacing: 4
            rowSpacing: 4
            Repeater {
                model: root.typeDefs
                ActionButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 28
                    icon: Theme.ic(modelData.id === "auto" ? 0xf0068 : modelData.icon)   // md-auto_fix
                    iconFont: modelData.font ?? Theme.font
                    accent: Theme.bluetooth
                    highlighted: root.type === modelData.id
                    onClicked: { root.typeChosen(modelData.id); root.pickType = false; }
                }
            }
        }

        BarText {
            font.family: Theme.labelFont
            visible: root.confirmForget
            text: "Recliquer pour oublier"
            color: Theme.red
            font.pixelSize: 11
        }
    }
}
