import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Popups de notification : pile en haut à droite, sous la barre, sur l'écran actif.
PanelWindow {
    id: win

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
    visible: NotifState.popups.length > 0

    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; right: true }
    // Sous la barre (5 de marge + 36 de haut) + 8
    margins { top: 49; right: 10 }
    implicitWidth: 380
    implicitHeight: Math.max(1, stack.implicitHeight)
    color: "transparent"

    Column {
        id: stack
        width: parent.width
        spacing: 8

        // Les cartes restantes glissent à leur nouvelle place quand une autre part
        move: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }

        Repeater {
            // ScriptModel : garde les cartes existantes (et leur animation / délai) quand la liste change
            model: ScriptModel { values: NotifState.popups }
            NotifCard {
                required property var modelData
                notif: modelData
                width: stack.width
            }
        }
    }
}
