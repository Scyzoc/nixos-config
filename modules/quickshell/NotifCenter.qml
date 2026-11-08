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
    // Repli de la dernière ligne (0 → 1) : « Tout effacer » et les marges se replient avec elle
    property real lastCollapse: 0
    onCountChanged: if (count > 0) lastCollapse = 0
    // Apparition douce de « Aucune notification »
    property real emptyP: count === 0 ? 1 : 0
    Behavior on emptyP { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Chorégraphie (sans aucun saut de mise en page) : les cartes filent à droite en cascade,
    // le menu commence à se replier pendant leur départ (contenu inchangé), et les notifications
    // ne sont réellement effacées qu'une fois le menu caché (onShownChanged).
    function clearAll() {
        if (clearing) return;
        clearing = true;
        trashShake.restart();
        const n = histRep.count;
        for (let i = 0; i < n; i++) {
            const it = histRep.itemAt(i);
            if (it) it.sweepOut(Math.min(i, 8) * 35);
        }
        closeAfter.interval = Math.min(Math.max(n - 1, 0), 8) * 35 + 160;
        closeAfter.restart();
    }
    Timer {
        id: closeAfter
        onTriggered: menu.visible = false
    }
    Connections {
        target: menu
        function onShownChanged() {
            if (menu.shown || !root.clearing) return;
            NotifState.clearAll();
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

            // Ne pas déranger : bouton Zzz animé (DndButton), teinté quand actif
            DndButton {
                checked: NotifState.dnd
                onClicked: NotifState.dnd = !NotifState.dnd
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: -10 * (1 - root.emptyP)
            Layout.preferredHeight: (emptyText.implicitHeight + 12) * root.emptyP
            visible: root.emptyP > 0
            opacity: root.emptyP
            BarText {
                id: emptyText
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 6 }
                text: "Aucune notification"
                color: Theme.muted
                font.family: Theme.labelFont
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, 480)
            Layout.bottomMargin: -10 * root.lastCollapse
            visible: root.count > 0
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: parent.width
                spacing: 0
                move: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }
                Repeater {
                    id: histRep
                    // `shown` (et pas `visible`) : la liste reste en place pendant l'animation de fermeture
                    model: ScriptModel { values: menu.shown ? NotifState.history : [] }
                    // Ligne = carte + 6 px d'espace, qui se replient ensemble (hauteur continue, sans saut)
                    Item {
                        id: row
                        required property var modelData
                        width: list.width
                        height: (card.implicitHeight + 6) * (1 - card.collapse)
                        clip: card.collapse > 0
                        function sweepOut(delay) { card.sweepOut(delay); }
                        NotifCard {
                            id: card
                            notif: row.modelData
                            popup: false
                            collapseOnDismiss: true
                            width: parent.width
                            onCollapseChanged: if (histRep.count === 1) root.lastCollapse = collapse
                        }
                    }
                }
            }
        }

        // Tout effacer
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: -10 * root.lastCollapse
            Layout.bottomMargin: 4 * (1 - root.lastCollapse)
            visible: root.count > 0
            Layout.preferredHeight: 30 * (1 - root.lastCollapse)
            opacity: 1 - root.lastCollapse
            clip: true
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
