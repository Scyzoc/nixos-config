import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// Sélecteur de fonds d'écran (SUPER+W) : deux catégories, clair / sombre, classées
// d'après la luminosité moyenne de l'image (clic droit : changer de catégorie).
// Le fond du panneau reprend, flouté, le fond d'écran survolé.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    // --- Ouverture / fermeture -------------------------------------------------
    property bool open: false
    visible: false

    function show() {
        const m = Hyprland.focusedMonitor;
        win.screen = Quickshell.screens.find(s => s.name === m?.name) ?? Quickshell.screens[0];
        refresh();
        search.text = "";
        // Onglet du fond actuel, fond actuel sélectionné
        const cur = byPath[current];
        if (cur) tab = catOf(cur);
        closeTimer.stop();
        visible = true;
        open = true;
        Qt.callLater(selectCurrent);    // après la mise à jour de la grille
        search.forceActiveFocus();
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    function selectCurrent() {
        if (grid.height <= 0) return;    // pas encore affichée : rappelée par onHeightChanged
        const i = shown.indexOf(current);
        grid.currentIndex = Math.max(0, i);
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
    }

    // --- Fonds d'écran -----------------------------------------------------------
    // wallpaper-index (wallpaper-picker.nix) : une ligne « current <chemin> », puis une
    // ligne « luminosité <miniature> <chemin> » par image (tabulations). Les miniatures
    // manquantes sont créées au passage : la grille se remplit au fil de l'eau.
    property var items: []          // [{ path, name, thumb, lum }], triés par nom
    property string current: ""     // chemin du fond affiché
    readonly property var byPath: {
        const m = {};
        for (const it of items) m[it.path] = it;
        return m;
    }

    Process {
        id: indexer
        command: [Paths.userBin + "/wallpaper-index"]
        environment: ({ LC_ALL: "C" })
        property var seen: ({})
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t");
                if (p[0] === "current") { win.current = p[1] ?? ""; return; }
                if (p.length < 3) return;
                indexer.seen[p[2]] = true;
                win.upsert({ path: p[2], thumb: p[1], lum: parseFloat(p[0]) || 0, name: p[2].split("/").pop() });
            }
        }
        // Images supprimées du dossier
        onExited: win.items = win.items.filter(it => indexer.seen[it.path])
    }
    function refresh() {
        if (indexer.running) return;
        indexer.seen = {};
        indexer.running = true;
    }
    function upsert(it) {
        const i = items.findIndex(x => x.path === it.path);
        if (i >= 0 && items[i].thumb === it.thumb && items[i].lum === it.lum) return;
        const copy = items.slice();
        if (i >= 0) copy[i] = it;
        else copy.push(it);
        copy.sort((a, b) => norm(a.name).localeCompare(norm(b.name)));
        items = copy;
    }
    // Miniatures prêtes avant la première ouverture
    Component.onCompleted: refresh()

    // --- Catégories --------------------------------------------------------------
    // Luminosité moyenne (0 = noir, 1 = blanc) à partir de laquelle une image est « claire »
    readonly property real threshold: 0.4
    // Choix de l'utilisateur (nom de fichier → "light" | "dark"), prioritaire sur le calcul
    property var overrides: ({})
    FileView {
        id: overridesFile
        path: Paths.stateDir + "/wallpaper-categories.json"
        printErrors: false
        onLoaded: {
            try { win.overrides = JSON.parse(text()); } catch (e) { win.overrides = {}; }
        }
    }
    function autoCat(it) { return it.lum >= threshold ? "light" : "dark"; }
    function catOf(it) { return overrides[it.name] ?? autoCat(it); }
    function moveToOther(path) {
        const it = byPath[path];
        if (!it) return;
        const target = catOf(it) === "light" ? "dark" : "light";
        const o = Object.assign({}, overrides);
        if (target === autoCat(it)) delete o[it.name];
        else o[it.name] = target;
        overrides = o;
        overridesFile.setText(JSON.stringify(o));
    }

    readonly property var tabs: [
        { id: "light", label: "Clair", icon: 0xf05a8, color: Theme.yellow },
        { id: "dark", label: "Sombre", icon: 0xf0594, color: Theme.mauve }
    ]
    property string tab: "dark"
    readonly property var counts: {
        const n = { light: 0, dark: 0 };
        for (const it of items) n[catOf(it)]++;
        return n;
    }

    // --- Recherche ---------------------------------------------------------------
    function norm(s) {
        return (s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }
    property string query: ""
    readonly property string q: norm(query.trim())
    // Chemins affichés : catégorie de l'onglet, filtrée par le texte tapé
    readonly property var shown: items.filter(it => catOf(it) === tab && (q === "" || norm(it.name).indexOf(q) >= 0))
                                      .map(it => it.path)

    function setTab(id) {
        if (tab === id) return;
        tab = id;
        Qt.callLater(selectCurrent);
    }

    // --- Application ---------------------------------------------------------------
    function apply(path) {
        if (!path) return;
        current = path;
        hide();
        Quickshell.execDetached([Paths.userBin + "/wallpaper-apply", path]);
    }

    function title(name) { return name.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " "); }

    // --- Interface -------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: win.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: win.hide() }
    }

    Item {
        id: panel
        anchors.centerIn: parent
        width: Math.min(1120, parent.width - 80)
        height: Math.min(720, parent.height - 100)

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }    // le clic dans le panneau ne ferme pas

        // Fond : miniature du fond sélectionné, floutée et assombrie, en fondu enchaîné
        ClippingRectangle {
            anchors.fill: parent
            radius: 20
            color: "#161616"

            Item {
                id: backdrop
                anchors.fill: parent
                readonly property string src: win.byPath[win.shown[grid.currentIndex] ?? ""]?.thumb ?? ""
                onSrcChanged: {
                    bgBack.source = bgFront.source;
                    bgFront.source = src !== "" ? "file://" + src : "";
                    bgFade.restart();
                }
                layer.enabled: true
                layer.textureSize: Qt.size(280, 180)    // petit : flou moins coûteux
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    saturation: 0.25
                }
                Image { id: bgBack; anchors.fill: parent; fillMode: Image.PreserveAspectCrop }
                Image {
                    id: bgFront
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    NumberAnimation { id: bgFade; target: bgFront; property: "opacity"; from: 0; to: 1; duration: 320 }
                }
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(14 / 255, 14 / 255, 14 / 255, 0.68) }
        }
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: "transparent"
            border.color: Theme.border
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // En-tête : titre, onglets clair / sombre, recherche
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                BarText { text: Theme.ic(0xf0e09); font.pixelSize: 24; color: Theme.text }
                ColumnLayout {
                    spacing: 0
                    BarText { text: "Fonds d'écran"; font.family: Theme.trackFont; font.pixelSize: 20; font.bold: true }
                    BarText {
                        text: win.shown.length + (win.shown.length > 1 ? " images" : " image")
                              + (indexer.running && win.items.length === 0 ? "  ·  préparation des miniatures…" : "")
                        color: Theme.subtext
                        font.pixelSize: 11
                    }
                }
                Item { Layout.fillWidth: true }

                // Onglets ; le curseur glisse de l'un à l'autre
                Rectangle {
                    id: seg
                    readonly property int segW: 132
                    implicitWidth: segW * 2 + 6
                    implicitHeight: 38
                    radius: 12
                    color: Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1

                    Rectangle {
                        x: 3 + (win.tab === "light" ? 0 : seg.segW)
                        y: 3
                        width: seg.segW
                        height: parent.height - 6
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.16)
                        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        x: 3
                        y: 3
                        Repeater {
                            model: win.tabs
                            Item {
                                id: segItem
                                required property var modelData
                                readonly property bool current: win.tab === modelData.id
                                width: seg.segW
                                height: seg.height - 6
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7
                                    BarText {
                                        text: Theme.ic(segItem.modelData.icon)
                                        font.pixelSize: 16
                                        color: segItem.current ? segItem.modelData.color : Theme.muted
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    BarText {
                                        text: segItem.modelData.label
                                        font.bold: segItem.current
                                        color: segItem.current ? Theme.text : Theme.subtext
                                    }
                                    BarText {
                                        text: win.counts[segItem.modelData.id]
                                        font.pixelSize: 11
                                        color: Theme.muted
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { win.setTab(segItem.modelData.id); search.forceActiveFocus(); }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: 230
                    implicitHeight: 38
                    radius: 12
                    color: Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        BarText { text: Theme.ic(0xf0349); font.pixelSize: 16; color: Theme.subtext }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            font.family: Theme.labelFont
                            font.pixelSize: 13
                            clip: true
                            selectByMouse: true
                            focus: true
                            onTextChanged: {
                                win.query = text;
                                grid.currentIndex = 0;
                                grid.positionViewAtBeginning();
                            }
                            // Flèches : grille ; Tab : clair / sombre ; le reste : saisie
                            Keys.onPressed: event => {
                                event.accepted = true;
                                switch (event.key) {
                                case Qt.Key_Escape: win.hide(); break;
                                case Qt.Key_Down: grid.moveCurrentIndexDown(); break;
                                case Qt.Key_Up: grid.moveCurrentIndexUp(); break;
                                case Qt.Key_Left: grid.moveCurrentIndexLeft(); break;
                                case Qt.Key_Right: grid.moveCurrentIndexRight(); break;
                                case Qt.Key_Tab:
                                case Qt.Key_Backtab: win.setTab(win.tab === "light" ? "dark" : "light"); break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter: win.apply(win.shown[grid.currentIndex]); break;
                                default: event.accepted = false;
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: search.text === ""
                                text: "Rechercher…"
                                color: Theme.muted
                                font: search.font
                            }
                        }
                    }
                }
            }

            // Grille des miniatures
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: grid
                    anchors.fill: parent
                    clip: true
                    readonly property int cols: Math.max(2, Math.round(width / 270))
                    cellWidth: Math.floor(width / cols)
                    cellHeight: Math.round(cellWidth * 9 / 16)
                    boundsBehavior: Flickable.StopAtBounds
                    highlightFollowsCurrentItem: false
                    // Marge : la case sélectionnée, agrandie, n'est pas rognée en haut / en bas
                    topMargin: 4
                    bottomMargin: 4
                    // Première ouverture : la grille n'a sa hauteur qu'après l'affichage
                    onHeightChanged: if (win.open) Qt.callLater(win.selectCurrent)
                    model: ScriptModel { values: win.shown }

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 240; easing.type: Easing.OutCubic }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: 140 }
                        NumberAnimation { property: "scale"; to: 0.9; duration: 140 }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "opacity"; to: 1; duration: 100 }
                        NumberAnimation { property: "scale"; to: 1; duration: 100 }
                    }

                    delegate: Item {
                        id: cell
                        required property string modelData
                        required property int index
                        readonly property var it: win.byPath[modelData] ?? ({ thumb: "", name: "" })
                        readonly property bool selected: GridView.isCurrentItem
                        readonly property bool active: modelData === win.current
                        width: grid.cellWidth
                        height: grid.cellHeight
                        z: selected ? 1 : 0

                        Item {
                            id: card
                            anchors.fill: parent
                            anchors.margins: 8
                            scale: cellMa.pressed ? 0.97 : cell.selected ? 1.05 : 1
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 12
                                color: Qt.rgba(1, 1, 1, 0.06)

                                Image {
                                    anchors.fill: parent
                                    source: cell.it.thumb !== "" ? "file://" + cell.it.thumb : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                // Nom sur dégradé, pour l'image sélectionnée
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 46
                                    opacity: cell.selected ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 160 } }
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "transparent" }
                                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.75) }
                                    }
                                    BarText {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 9
                                        text: win.title(cell.it.name)
                                        font.family: Theme.labelFont
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            // Contour (blanc sur la sélection)
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: "transparent"
                                border.width: cell.selected ? 2 : 1
                                border.color: cell.selected ? Theme.text : Qt.rgba(1, 1, 1, 0.14)
                                Behavior on border.color { ColorAnimation { duration: 140 } }
                            }
                            // Fond d'écran en place
                            Rectangle {
                                visible: cell.active
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 8
                                implicitWidth: badge.implicitWidth + 14
                                implicitHeight: 22
                                radius: 11
                                color: Qt.rgba(0, 0, 0, 0.6)
                                border.color: Qt.rgba(1, 1, 1, 0.2)
                                border.width: 1
                                RowLayout {
                                    id: badge
                                    anchors.centerIn: parent
                                    spacing: 5
                                    BarText { text: Theme.ic(0xf012c); color: Theme.green; font.pixelSize: 12 }
                                    BarText { text: "actuel"; font.pixelSize: 11 }
                                }
                            }
                        }

                        MouseArea {
                            id: cellMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            // Souris bougée seulement : le défilement au clavier ne vole pas la sélection
                            onPositionChanged: grid.currentIndex = cell.index
                            onClicked: event => {
                                if (event.button === Qt.RightButton) win.moveToOther(cell.modelData);
                                else win.apply(cell.modelData);
                            }
                        }
                    }
                }

                // Barre de défilement (indicateur)
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: -8
                    width: 3
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.3)
                    visible: grid.visibleArea.heightRatio < 1
                    y: grid.visibleArea.yPosition * grid.height
                    height: grid.visibleArea.heightRatio * grid.height
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: win.shown.length === 0
                    spacing: 8
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Theme.ic(0xf0976)
                        font.pixelSize: 44
                        color: Theme.muted
                    }
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: indexer.running && win.items.length === 0 ? "Préparation des miniatures…"
                            : win.items.length === 0 ? "Aucune image dans ~/Pictures/Wallpapers"
                            : win.q !== "" ? "Aucun fond d'écran ne correspond"
                            : "Aucun fond d'écran " + (win.tab === "light" ? "clair" : "sombre")
                        color: Theme.subtext
                    }
                }
            }

            // Rappel des touches
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [["Entrée", "appliquer"], ["Tab", "clair / sombre"], ["Clic droit", "changer de catégorie"], ["Échap", "fermer"]]
                    RowLayout {
                        required property var modelData
                        spacing: 6
                        Rectangle {
                            implicitWidth: keyText.implicitWidth + 10
                            implicitHeight: 18
                            radius: 5
                            color: Theme.pill
                            border.color: Theme.pillBorder
                            border.width: 1
                            BarText { id: keyText; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 10; color: Theme.subtext }
                        }
                        BarText { text: modelData[1]; font.pixelSize: 11; color: Theme.subtext }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
