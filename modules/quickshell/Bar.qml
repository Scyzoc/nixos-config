import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Une barre par écran (même contenu partout, workspaces propres à l'écran)
PanelWindow {
    id: bar

    required property ShellScreen modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Top

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 5
        left: 10
        right: 10
    }
    implicitHeight: 36
    // Écran étroit (ex. écran vertical) : pastilles en icônes seules
    readonly property bool compact: width < 1400
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
    }

    RowLayout {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Workspaces { monitorName: bar.modelData.name }
        CompactHint { monitorName: bar.modelData.name; compact: bar.compact }
    }

    // Horloge centrée, sauf si le groupe de droite déborde jusqu'au centre
    // (écran étroit, titre long) : elle glisse alors vers la gauche, sans
    // jamais passer sur les workspaces
    Clock {
        id: clock
        readonly property real centered: (bar.width - width) / 2
        readonly property real maxX: rightRow.x - width - 12
        readonly property real minX: leftRow.x + leftRow.width + 12
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(minX, Math.min(centered, maxX))
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    RowLayout {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        TimerPill { compact: bar.compact }
        Media { compact: bar.compact }
        Brightness { compact: bar.compact }
        Volume { compact: bar.compact }
        SysRes { compact: bar.compact }
        BluetoothPill { compact: bar.compact }
        Ethernet { compact: bar.compact }
        Wifi { compact: bar.compact }
        Battery { compact: bar.compact }
        Power { compact: bar.compact }
    }
}
