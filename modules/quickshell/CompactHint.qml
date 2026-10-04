import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// Suggestion de compactage, à droite des workspaces : apparaît quand l'écran a des
// trous (ex : 1, 2 et 7 occupés), seulement si la situation est stable
// depuis un moment et que le workspace affiché n'est pas vide (on s'apprête alors
// à le remplir). Clic : ws-compact sur cet écran ; clic droit : ignorer jusqu'au
// prochain changement des workspaces occupés.
Pill {
    id: root
    required property string monitorName

    // Délai de stabilité avant de proposer (évite de clignoter pendant qu'on range)
    readonly property int settleMs: 15000

    readonly property var wsList: Hyprland.workspaces.values
        .filter(w => w.id > 0 && w.monitor && w.monitor.name === root.monitorName)
        .sort((a, b) => a.id - b.id)
    readonly property var used: wsList.filter(w => w.toplevels.values.length > 0).map(w => w.id)
    // Même calcul que ws-compact : i-ème workspace occupé → i-ème workspace de l'écran
    readonly property var moves: used
        .map((id, i) => [id, wsList[i].id])
        .filter(m => m[0] !== m[1])
    readonly property string signature: used.join(",")
    readonly property var shownWs: wsList.find(w => w.active) ?? null
    readonly property bool shownEmpty: shownWs !== null && shownWs.toplevels.values.length === 0

    property bool settled: false
    property string dismissed: ""
    onSignatureChanged: { settled = false; settle.restart(); }
    Timer { id: settle; interval: root.settleMs; running: true; onTriggered: root.settled = true }

    tooltip: shown
        ? "Workspaces à trous : " + moves.map(m => m[0] + " → " + m[1]).join(", ")
          + "\nClic : compacter · clic droit : ignorer"
        : ""

    onClicked: event => {
        if (event.button === Qt.LeftButton)
            Quickshell.execDetached([Paths.userBin + "/ws-compact", root.monitorName]);
        // Masquée tout de suite ; réapparaît si les workspaces occupés changent
        if (event.button !== Qt.MiddleButton) root.dismissed = root.signature;
    }

    // Apparition : la pastille s'ouvre en largeur ; masquée : retirée de la barre
    readonly property bool shown: moves.length > 0 && settled && !shownEmpty && dismissed !== signature
    Layout.preferredWidth: shown ? implicitWidth : 0
    Behavior on Layout.preferredWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }
    visible: opacity > 0
    clip: true

    BarText {
        text: Theme.ic(0xf0793)    // md-arrow_collapse_left
        color: Theme.sky
    }
}
