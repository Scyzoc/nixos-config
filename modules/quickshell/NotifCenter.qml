import QtQuick
import QtQuick.Layouts
import Quickshell

// Cloche de la barre : nombre de notifications gardées ; clic = historique (menu),
// clic droit = Ne pas déranger. Cloche barrée en mode Ne pas déranger.
Pill {
    id: root

    readonly property int count: NotifState.count

    tooltip: (NotifState.dnd ? "Ne pas déranger activé\n" : "")
             + (count === 0 ? "Aucune notification" : count + " notification" + (count > 1 ? "s" : ""))
             + "\nClic droit : ne pas déranger"

    BarText {
        text: Theme.ic(NotifState.dnd ? 0xf009b : (root.count > 0 ? 0xf116b : 0xf009a))    // md-bell-off / bell-badge / bell
        color: NotifState.dnd ? Theme.muted : Theme.text
        font.pixelSize: 15
    }
    BarText {
        visible: root.count > 0 && !root.compact
        text: root.count
        font.family: Theme.labelFont
    }

    onClicked: event => {
        if (event.button === Qt.RightButton) NotifState.dnd = !NotifState.dnd;
        else menu.toggle();
    }

    BarPopup {
        id: menu
        target: root
        contentWidth: 380

        PopupHeader {
            title: "Notifications"
            showToggle: true
            checked: NotifState.dnd
            toggleAccent: Theme.mauve
            onToggled: NotifState.dnd = !NotifState.dnd

            BarText {
                text: "Ne pas déranger"
                color: Theme.subtext
                font.family: Theme.labelFont
                font.pixelSize: 11
            }
        }

        BarText {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            visible: root.count === 0
            text: "Aucune notification"
            color: Theme.muted
            font.family: Theme.labelFont
            horizontalAlignment: Text.AlignHCenter
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, 480)
            visible: root.count > 0
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: parent.width
                spacing: 6
                move: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }
                Repeater {
                    model: ScriptModel { values: menu.visible ? NotifState.history : [] }
                    NotifCard {
                        required property var modelData
                        notif: modelData
                        popup: false
                        width: list.width
                    }
                }
            }
        }

        // Tout effacer
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            visible: root.count > 0
            implicitHeight: 30
            radius: 10
            color: clearMouse.containsMouse ? Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.25) : Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.12)
            Behavior on color { ColorAnimation { duration: 150 } }
            BarText {
                anchors.centerIn: parent
                text: Theme.ic(0xf0a7a) + "  Tout effacer"    // md-trash-can-outline
                color: Theme.red
                font.family: Theme.labelFont
                font.pixelSize: 12
            }
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { NotifState.clearAll(); menu.visible = false; }
            }
        }
    }
}
