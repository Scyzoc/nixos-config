import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Menu contextuel d'un workspace (clic droit dans la barre) :
//  - déplacer tout le workspace vers un autre (ws-move : tailles et positions conservées,
//    point = cible déjà occupée, ses fenêtres partagent alors la place)
//  - lier à un workspace d'un autre écran (workspace-link : affichés ensemble)
//  - le vider (ws-clear : ferme ses fenêtres), confirmé par un 2e clic
BarPopup {
    id: menu

    required property HyprlandWorkspace workspace
    readonly property int count: workspace.toplevels.values.length
    property bool armed: false
    property int tab: 0    // 0 déplacer, 1 lier

    contentWidth: 230

    // Écrans et leurs workspaces (celui du workspace d'abord), calculés seulement menu ouvert
    readonly property var screens: {
        if (!shown) return [];
        const own = workspace.monitor?.name ?? "";
        const names = {};
        for (const w of Hyprland.workspaces.values) {
            if (w.id <= 0 || !w.monitor) continue;
            if (!names[w.monitor.name]) names[w.monitor.name] = [];
            names[w.monitor.name].push(w);
        }
        return Object.keys(names)
            .sort((a, b) => (b === own) - (a === own) || a.localeCompare(b))
            .map(n => ({ name: n, workspaces: names[n].sort((a, b) => a.id - b.id) }));
    }

    // Liaisons : { pairs: [[1, 6], …] } lu dans workspace-link ; partners = jumeaux de ce workspace
    property var pairs: []
    readonly property var partners: pairs
        .filter(p => p[0] === workspace.id || p[1] === workspace.id)
        .map(p => p[0] === workspace.id ? p[1] : p[0])

    Process {
        id: linkState
        command: [Paths.userBin + "/workspace-link", "state"]
        stdout: StdioCollector {
            onStreamFinished: { try { menu.pairs = JSON.parse(text).pairs; } catch (e) {} }
        }
    }
    Process {
        id: linkEdit
        onExited: linkState.running = true
    }
    function toggleLink(id) {
        linkEdit.command = [Paths.userBin + "/workspace-link", partners.indexOf(id) >= 0 ? "del" : "add",
                            String(workspace.id), String(id)];
        linkEdit.running = true;
    }

    onVisibleChanged: { armed = false; tab = 0; if (visible) linkState.running = true; }
    onCountChanged: if (count === 0) visible = false

    // Désarme la confirmation si le 2e clic ne vient pas
    Timer { id: disarm; interval: 3000; onTriggered: menu.armed = false }

    function moveTo(id) {
        visible = false;
        Quickshell.execDetached([Paths.userBin + "/ws-move", String(workspace.id), String(id)]);
    }
    function clear() {
        if (!armed) { armed = true; disarm.restart(); return; }
        visible = false;
        Quickshell.execDetached([Paths.userBin + "/ws-clear", String(workspace.id)]);
    }

    // Un seul onglet affiché à la fois : le menu reste petit

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        BarText {
            text: "Workspace " + menu.workspace.name
            font.family: Theme.titleFont
            font.bold: true
            font.pixelSize: 14
            Layout.fillWidth: true
        }
        ActionButton {
            implicitHeight: 26
            implicitWidth: 34
            icon: Theme.ic(0xf0a3c)    // md-arrow_right_bold
            accent: Theme.blue
            highlighted: menu.tab === 0
            onClicked: menu.tab = 0
        }
        ActionButton {
            implicitHeight: 26
            implicitWidth: 34
            icon: Theme.ic(0xf0337)    // md-link
            accent: Theme.green
            highlighted: menu.tab === 1
            onClicked: menu.tab = 1
        }
    }

    WorkspaceGrid {
        visible: menu.tab === 0
        Layout.preferredHeight: visible ? implicitHeight : 0
        screens: menu.screens
        current: menu.workspace.id
        onPicked: id => menu.moveTo(id)
    }

    // Liaisons : un workspace du même écran est grisé (workspace-link l'ignore)
    WorkspaceGrid {
        visible: menu.tab === 1
        Layout.preferredHeight: visible ? implicitHeight : 0
        screens: menu.screens
        current: menu.workspace.id
        dimScreen: menu.workspace.monitor?.name ?? ""
        markColor: Theme.green
        marked: menu.partners
        onPicked: id => menu.toggleLink(id)
    }

    ActionButton {
        Layout.fillWidth: true
        implicitHeight: 28
        icon: Theme.ic(0xf0a7a)    // md-trash_can_outline
        label: menu.armed ? "Recliquer pour tout fermer"
                          : "Vider (" + menu.count + ")"
        accent: Theme.red
        glowing: menu.armed
        glowColor: Theme.red
        onClicked: menu.clear()
    }
}
