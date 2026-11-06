import QtQuick
import QtQuick.Layouts
import Quickshell

// Cloche de la barre : nombre de notifications gardées ; clic = historique (menu),
// clic droit = Ne pas déranger. Cloche barrée en mode Ne pas déranger.
Pill {
    id: root

    readonly property int count: NotifState.count
    // Animation « Tout effacer » en cours (cartes qui partent en cascade)
    property bool clearing: false

    function clearAll() {
        if (clearing) return;
        clearing = true;
        trashShake.restart();
        const n = histRep.count;
        for (let i = 0; i < n; i++) {
            const it = histRep.itemAt(i);
            if (it) it.sweepOut(Math.min(i, 10) * 45);
        }
        clearDone.interval = Math.min(n - 1, 10) * 45 + 380;
        clearDone.restart();
    }
    Timer {
        id: clearDone
        onTriggered: {
            NotifState.clearAll();
            menu.visible = false;
            root.clearing = false;
        }
    }

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

            // Ne pas déranger : bouton Zzz, teinté quand actif
            IconButton {
                implicitWidth: 30
                implicitHeight: 30
                icon: Theme.ic(0xf04b2)    // md-sleep (Zzz)
                accent: Theme.mauve
                checked: NotifState.dnd
                onClicked: NotifState.dnd = !NotifState.dnd
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
                    id: histRep
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
            ClickFx { id: clearFx; color: Theme.red }
            Row {
                anchors.centerIn: parent
                spacing: 8
                BarText {
                    id: trash
                    text: Theme.ic(0xf0a7a)    // md-trash-can-outline
                    color: Theme.red
                    font.pixelSize: 14
                    transformOrigin: Item.Bottom
                    // Poubelle qui s'agite au clic
                    SequentialAnimation {
                        id: trashShake
                        NumberAnimation { target: trash; property: "rotation"; to: -18; duration: 70 }
                        NumberAnimation { target: trash; property: "rotation"; to: 14; duration: 90 }
                        NumberAnimation { target: trash; property: "rotation"; to: -8; duration: 80 }
                        NumberAnimation { target: trash; property: "rotation"; to: 0; duration: 120; easing.type: Easing.OutBack }
                    }
                }
                BarText {
                    text: "Tout effacer"
                    color: Theme.red
                    font.family: Theme.labelFont
                    font.pixelSize: 12
                }
            }
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !root.clearing
                onClicked: { clearFx.play(); root.clearAll(); }
            }
        }
    }
}
