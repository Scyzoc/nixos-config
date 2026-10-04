import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// Popup déroulé sous un élément de la barre. Se ferme avec Échap, au clic en dehors
// (le clic atteint quand même la fenêtre visée : pas besoin de cliquer deux fois),
// à la première touche frappée hors champ de saisie ou à l'ouverture d'un autre menu.
PopupWindow {
    id: popup

    required property Item target
    property int padding: 14
    property int contentWidth: 300
    default property alias content: body.data

    anchor.item: target
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.rect.width: target.width
    anchor.rect.height: target.height + 12
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    grabFocus: false
    color: "transparent"
    visible: false
    implicitWidth: contentWidth + padding * 2
    implicitHeight: body.implicitHeight + padding * 2

    function toggle() { visible = !visible; }

    onVisibleChanged: {
        if (visible) {
            if (PopupState.current && PopupState.current !== popup) PopupState.current.visible = false;
            PopupState.current = popup;
        } else if (PopupState.current === popup) {
            PopupState.current = null;
        }
    }

    // Clavier pour le menu (Échap, champs de saisie) ; clic en dehors → fermeture
    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible
        onCleared: popup.visible = false
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: popup.visible = false
    }

    // Pas de fermeture sur les événements Hyprland : « activewindowv2 » est aussi émis
    // à chaque changement de titre de la fenêtre active (terminal, onglet qui travaille).

    // Frappe clavier : ferme le menu, sauf pendant la saisie dans un champ
    // (les touches que le champ ignore — Maj, flèches — remontent jusqu'ici)
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const f = keys.Window.activeFocusItem;
            if (f && f !== keys && f.cursorPosition !== undefined) return;
            popup.visible = false;
        }

        Rectangle {
            id: frame
            anchors.fill: parent
            radius: 14
            color: Theme.popupBg
            border.color: Theme.border
            border.width: 1

            opacity: popup.visible ? 1 : 0
            transform: Translate { y: popup.visible ? 0 : -8; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: popup.padding
                spacing: 10
            }
        }
    }
}
