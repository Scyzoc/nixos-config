import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// Workspaces de l'écran courant uniquement (attribués par workspace-bind)
// Glisser un workspace sur un autre y déplace toutes ses fenêtres (ws-move)
Rectangle {
    id: root
    required property string monitorName

    // Glisser-déposer en cours : id source / cible (-1 = aucun)
    property int dragFrom: -1
    property int dragOver: -1
    property string dragLabel: ""
    property real dragX: 0

    implicitWidth: row.implicitWidth + 8
    implicitHeight: 28
    radius: 8
    color: Theme.pill
    border.color: Theme.pillBorder
    border.width: 1

    MouseArea {
        anchors.fill: parent
        onWheel: event => Hyprland.dispatch(event.angleDelta.y > 0 ? "workspace m-1" : "workspace m+1")
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: ScriptModel {
                values: Hyprland.workspaces.values
                    .filter(w => w.id > 0 && w.monitor && w.monitor.name === root.monitorName)
                    .sort((a, b) => a.id - b.id)
            }

            Rectangle {
                id: ws
                required property HyprlandWorkspace modelData
                readonly property bool isEmpty: modelData.toplevels.values.length === 0
                readonly property bool isActive: modelData.active
                readonly property bool small: isEmpty && !isActive

                Layout.preferredHeight: 22
                Layout.preferredWidth: small ? 14 : Math.max(24, label.implicitWidth + 16)
                radius: 6
                readonly property bool isDragSource: root.dragFrom === modelData.id
                readonly property bool isDropTarget: root.dragFrom >= 0 && root.dragOver === modelData.id && !isDragSource

                opacity: isDragSource ? 0.35 : 1
                color: isDropTarget ? Qt.rgba(1, 1, 1, 0.25)
                     : isActive ? Qt.rgba(1, 1, 1, 0.2)
                     : (ma.containsMouse && root.dragFrom < 0 ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                border.color: isDropTarget ? Theme.blue : (isActive ? Qt.rgba(1, 1, 1, 0.3) : "transparent")
                border.width: 1

                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }

                BarText {
                    id: label
                    anchors.centerIn: parent
                    text: ws.modelData.name
                    color: ws.isEmpty ? Qt.rgba(1, 1, 1, 0.25) : Theme.text
                    font.family: Theme.labelFont
                    font.features: { "tnum": 1 }
                    font.pixelSize: ws.small ? 8 : Theme.fontSize
                    font.weight: ws.isActive ? Font.Bold : Font.Medium
                }

                MouseArea {
                    id: ma
                    property real pressX: 0
                    property bool dragged: false

                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: root.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    onPressed: mouse => { pressX = mouse.x; dragged = false; }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        // Seuil de 6 px avant de démarrer ; un workspace vide n'a rien à déplacer
                        if (!dragged && Math.abs(mouse.x - pressX) > 6 && !ws.isEmpty) {
                            dragged = true;
                            root.dragFrom = ws.modelData.id;
                            root.dragLabel = ws.modelData.name;
                        }
                        if (!dragged) return;
                        const p = mapToItem(row, mouse.x, mouse.y);
                        const over = row.childAt(p.x, row.height / 2);
                        root.dragOver = over && over.modelData ? over.modelData.id : -1;
                        root.dragX = mapToItem(root, mouse.x, 0).x;
                    }
                    onReleased: {
                        if (dragged && root.dragOver > 0 && root.dragOver !== root.dragFrom)
                            Quickshell.execDetached([Paths.userBin + "/ws-move", String(root.dragFrom), String(root.dragOver)]);
                        root.dragFrom = -1;
                        root.dragOver = -1;
                    }
                    onCanceled: { root.dragFrom = -1; root.dragOver = -1; }
                    onClicked: if (!dragged) ws.modelData.activate()
                }
            }
        }
    }

    // Étiquette du workspace glissé, suit le curseur
    Rectangle {
        visible: root.dragFrom >= 0
        x: Math.max(0, Math.min(root.width - width, root.dragX - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(24, ghost.implicitWidth + 16)
        height: 22
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.3)
        border.color: Theme.blue
        border.width: 1
        z: 10

        BarText {
            id: ghost
            anchors.centerIn: parent
            text: root.dragLabel
            color: Theme.text
            font.family: Theme.labelFont
            font.pixelSize: Theme.fontSize
            font.weight: Font.Bold
        }
    }
}
