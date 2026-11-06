import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Popup déroulé sous un élément de la barre. Se ferme avec Échap, au clic en dehors
// (le clic atteint quand même la fenêtre visée : pas besoin de cliquer deux fois),
// à la première touche frappée hors champ de saisie ou à l'ouverture d'un autre menu.
// `visible` est l'état voulu : la fenêtre (`win`) reste affichée le temps de l'animation de fermeture,
// qui rejoue le morphing à l'envers (le menu se rétracte dans la pastille).
Item {
    id: popup

    required property Item target
    property int padding: 14
    property int contentWidth: 300
    default property alias content: body.data
    // Morphing : le menu naît de la pastille (même position, même taille) puis s'agrandit
    property bool morph: true
    property real grow: morph ? 0 : 1
    property real frameOp: morph ? 0 : 1     // opacité du cadre
    property real textOp: morph ? 0 : 1      // opacité du contenu
    property bool closing: false
    readonly property bool shown: visible || closing
    // Animation d'ouverture terminée : les menus y reportent leur travail lourd (scan, processus)
    readonly property bool settled: visible && grow >= 1

    // Déclaré dans une pastille : rattaché à la cible elle-même (pas à son RowLayout, où il prendrait de la place)
    parent: target
    width: 0
    height: 0

    function toggle() { visible = !visible; }

    // Position du menu décidée ici (pas par le compositeur) pour que le cadre parte exactement
    // de la pastille et y revienne : fenêtre centrée sur la pastille, ramenée dans l'écran si besoin.
    property real tx: 0       // abscisse de la pastille dans la fenêtre de la barre
    property real shift: 0    // décalage horizontal de la fenêtre par rapport au centrage sur la pastille
    function place() {
        const tw = popup.target.QsWindow.window;
        if (!tw) return;
        tx = popup.target.mapToItem(null, 0, 0).x;
        const w = contentWidth + padding * 2;
        const left = Math.max(10, Math.min(tw.width - w - 10, tx + target.width / 2 - w / 2));
        shift = left - (tx + target.width / 2 - w / 2);
    }

    onVisibleChanged: {
        if (visible) {
            place();
            closeAnim.stop();
            if (morph) {
                if (!closing) { grow = 0; frameOp = 0; textOp = 0; }
                openAnim.restart();
            }
            closing = false;
            if (PopupState.current && PopupState.current !== popup) PopupState.current.visible = false;
            PopupState.current = popup;
        } else {
            if (morph && frameOp > 0) {
                openAnim.stop();
                closing = true;
                closeAnim.restart();
            }
            if (PopupState.current === popup) PopupState.current = null;
        }
    }

    // Mêmes séquences que l'île (Island.qml) : ouverture = le cadre recouvre la pastille, s'étire, puis le
    // contenu apparaît ; fermeture = le contenu s'efface, le cadre se rétracte dans la pastille, puis s'efface.
    SequentialAnimation {
        id: openAnim
        NumberAnimation { target: popup; property: "frameOp"; to: 1; duration: 70 }
        NumberAnimation { target: popup; property: "grow"; to: 1; duration: 280; easing.type: Easing.OutCubic }
        NumberAnimation { target: popup; property: "textOp"; to: 1; duration: 110 }
    }
    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: popup; property: "textOp"; to: 0; duration: 130 }
        NumberAnimation { target: popup; property: "grow"; to: 0; duration: 340; easing.type: Easing.InOutCubic }
        NumberAnimation { target: popup; property: "frameOp"; to: 0; duration: 110 }
        ScriptAction { script: popup.closing = false }
    }

    // Morphing : le menu recouvre la pastille et la grab ne capte plus toujours le clic en dehors →
    // fenêtre transparente plein écran qui ferme le menu au moindre clic
    LazyLoader {
        active: popup.morph && popup.visible
        PanelWindow {
            screen: popup.target.QsWindow.window?.screen ?? null
            WlrLayershell.namespace: "quickshell-popup-catcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: popup.visible = false
            }
        }
    }
    // La pastille s'efface une fois recouverte par le menu (et revient quand il se rétracte)
    Binding { target: popup.target; property: "opacity"; value: 0; when: popup.morph && popup.shown && popup.frameOp > 0.5 }

    // Clavier pour le menu (Échap, champs de saisie) ; clic en dehors → fermeture
    HyprlandFocusGrab {
        windows: [win]
        active: popup.visible
        onCleared: popup.visible = false
    }

    PopupWindow {
        id: win

        anchor.item: popup.target
        anchor.rect.x: popup.shift
        anchor.adjustment: PopupAdjustment.None
        anchor.rect.y: 0
        anchor.rect.width: popup.target.width
        anchor.rect.height: popup.morph ? 0 : popup.target.height + 12
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom

        grabFocus: false
        color: "transparent"
        visible: popup.shown
        implicitWidth: popup.contentWidth + popup.padding * 2
        implicitHeight: body.implicitHeight + popup.padding * 2

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
                readonly property real w0: popup.morph ? popup.target.width : win.width
                readonly property real h0: popup.morph ? popup.target.height : win.height
                width: w0 + (win.width - w0) * popup.grow
                height: h0 + (win.height - h0) * popup.grow
                // Centre du cadre : celui de la pastille au départ, celui du menu à l'arrivée
                readonly property real c0: win.width / 2 - popup.shift
                x: (c0 + (win.width / 2 - c0) * popup.grow) - width / 2
                y: 0
                clip: true
                radius: popup.morph ? Math.min(height / 2, 10 + 4 * popup.grow) : 14
                color: Theme.popupBg
                border.color: Theme.border
                border.width: 1

                opacity: popup.morph ? popup.frameOp : (popup.visible ? 1 : 0)
                transform: Translate { y: popup.visible || popup.morph ? 0 : -8; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                Behavior on opacity { enabled: !popup.morph; NumberAnimation { duration: 160 } }

                ColumnLayout {
                    id: body
                    anchors.top: parent.top
                    anchors.topMargin: popup.padding
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: popup.contentWidth
                    opacity: popup.textOp
                    spacing: 10
                }
            }
        }
    }
}
