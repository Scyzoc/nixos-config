import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// Menu d'applications : recherche, catégories, grille d'icônes. Même palette que la
// barre (Theme.qml partagé). Plein écran transparent pour capter le clic en dehors.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-launcher"
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
    // open : état voulu (pilote les animations) ; visible : retombe après le fondu
    property bool open: false
    visible: false

    function show() {
        const m = Hyprland.focusedMonitor;
        win.screen = Quickshell.screens.find(s => s.name === m?.name) ?? Quickshell.screens[0];
        search.text = "";
        category = "all";
        menuEntry = null;
        closeTimer.stop();
        visible = true;
        open = true;
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
        search.forceActiveFocus();
    }
    function hide() {
        menuEntry = null;
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Catégories --------------------------------------------------------------
    // keys : catégories freedesktop (clé Categories des .desktop) rangées dedans
    readonly property var cats: [
        { id: "all", label: "Toutes", icon: 0xf003b, color: Theme.text },
        { id: "freq", label: "Fréquentes", icon: 0xf04ce, color: Theme.yellow },
        { id: "net", label: "Internet", icon: 0xf059f, color: Theme.blue, keys: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
        { id: "media", label: "Multimédia", icon: 0xf0387, color: Theme.green, keys: ["AudioVideo", "Audio", "Video", "Player", "Music"] },
        { id: "dev", label: "Développement", icon: 0xf0174, color: Theme.mauve, keys: ["Development", "IDE"] },
        { id: "office", label: "Bureautique", icon: 0xf0219, color: Theme.peach, keys: ["Office"] },
        { id: "gfx", label: "Graphisme", icon: 0xf03d8, color: Theme.pink, keys: ["Graphics"] },
        { id: "game", label: "Jeux", icon: 0xf0297, color: Theme.red, keys: ["Game"] },
        { id: "edu", label: "Éducation", icon: 0xf0474, color: Theme.teal, keys: ["Education", "Science"] },
        { id: "sys", label: "Système", icon: 0xf0493, color: Theme.sky, keys: ["System", "Settings"] },
        { id: "util", label: "Utilitaires", icon: 0xf1064, color: Theme.yellow, keys: ["Utility", "Accessibility"] },
        { id: "other", label: "Autres", icon: 0xf01d8, color: Theme.subtext }
    ]
    // Une seule catégorie par application : la première qui correspond, dans cet ordre
    // (Steam = Network + Game → Jeux ; VS Code = Utility + Development → Développement)
    readonly property var catPriority: ["game", "dev", "gfx", "media", "office", "net", "edu", "sys", "util"]
    function catOf(e) {
        const c = e.categories ?? [];
        for (const id of catPriority) {
            const keys = cats.find(x => x.id === id).keys;
            if (c.some(k => keys.indexOf(k) >= 0)) return id;
        }
        return "other";
    }

    // --- Applications ------------------------------------------------------------
    // Minuscules sans accents, pour la recherche et le tri
    function norm(s) {
        return (s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }
    // Une entrée par application, triée par nom
    readonly property var appIndex: {
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            out.push({
                entry: e,
                name: norm(e.name),
                extra: norm([e.genericName, e.comment, (e.keywords ?? []).join(" "), e.id].join(" ")),
                cat: catOf(e)
            });
        }
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }
    readonly property var catCount: {
        const n = { all: appIndex.length, freq: 0 };
        for (const it of appIndex) {
            n[it.cat] = (n[it.cat] ?? 0) + 1;
            if ((usage[it.entry.id] ?? 0) > 0) n.freq++;
        }
        n.freq = Math.min(n.freq, freqMax);
        return n;
    }
    readonly property var visibleCats: cats.filter(c => c.id === "all" || (catCount[c.id] ?? 0) > 0)

    // Nombre de lancements par application (identifiant .desktop → compteur)
    readonly property int freqMax: 18
    property var usage: ({})
    FileView {
        id: usageFile
        path: Paths.usageFile
        printErrors: false
        onLoaded: {
            try { win.usage = JSON.parse(text()); } catch (e) { win.usage = {}; }
        }
    }
    function bump(id) {
        const u = Object.assign({}, usage);
        u[id] = (u[id] ?? 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
    }

    // --- Recherche ---------------------------------------------------------------
    property string query: ""
    property string category: "all"
    readonly property string q: norm(query.trim())

    function score(it, q) {
        const n = it.name;
        if (n === q) return 1000;
        if (n.startsWith(q)) return 800;
        if (n.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 600;
        if (n.indexOf(q) >= 0) return 400;
        if (it.extra.indexOf(q) >= 0) return 200;
        // Lettres dans l'ordre (« frfx » → Firefox), à partir de 3 lettres
        if (q.length < 3) return 0;
        let i = 0;
        for (const ch of n) if (ch === q[i]) i++;
        return i === q.length ? 100 : 0;
    }

    // Recherche : toutes catégories, meilleures correspondances d'abord, avec un bonus
    // aux applications souvent lancées (« term » → kitty avant XTerm). Sinon la catégorie
    // choisie, par ordre alphabétique.
    readonly property var results: {
        if (q !== "") {
            const scored = [];
            for (const it of appIndex) {
                const s = score(it, q);
                if (s > 0) scored.push([s + Math.min((usage[it.entry.id] ?? 0) * 20, 300), it]);
            }
            scored.sort((a, b) => (b[0] - a[0]) || a[1].name.localeCompare(b[1].name));
            return scored.map(x => x[1].entry);
        }
        if (category === "freq")
            return appIndex.filter(it => (usage[it.entry.id] ?? 0) > 0)
                           .sort((a, b) => (usage[b.entry.id] - usage[a.entry.id]) || a.name.localeCompare(b.name))
                           .slice(0, freqMax).map(it => it.entry);
        return appIndex.filter(it => category === "all" || it.cat === category).map(it => it.entry);
    }

    function setCategory(id) {
        search.text = "";
        category = id;
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
    }
    function cycleCategory(d) {
        const v = visibleCats;
        const i = Math.max(0, v.findIndex(c => c.id === category));
        setCategory(v[(i + d + v.length) % v.length].id);
    }

    // --- Lancement -----------------------------------------------------------------
    // Par Hyprland (« exec ») : l'application ne dépend pas du service du menu
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function launch(e) {
        if (!e) return;
        bump(e.id);
        hide();
        let cmd = e.command.map(shq).join(" ");
        if (e.runInTerminal) cmd = Paths.kitty + " -e " + cmd;
        if (e.workingDirectory) cmd = "cd " + shq(e.workingDirectory) + " && " + cmd;
        console.info("Lancement :", cmd);
        Hyprland.dispatch("exec " + cmd);
    }
    // Recherche web sur le texte tapé (Ctrl+B, ou Entrée quand aucune application ne correspond)
    function webSearch() {
        const t = query.trim();
        if (t === "") return;
        hide();
        Hyprland.dispatch("exec " + Paths.brave + " " + shq("https://search.brave.com/search?q=" + encodeURIComponent(t)));
    }
    function activate() {
        if (results.length > 0 && grid.currentIndex >= 0) launch(results[grid.currentIndex]);
        else webSearch();
    }

    // --- Menu contextuel (clic droit / touche Menu) ------------------------------------
    property var menuEntry: null
    property point menuPos: Qt.point(0, 0)
    function openMenu(e, item, x, y) {
        menuPos = item.mapToItem(panel, x, y);
        menuEntry = e;
    }
    // Désinstallation : commande `uninstall --app` (modules/nixinstall.nix) dans un kitty
    // flottant, qui confirme puis rebuild ; reste ouvert pour lire le résultat
    function uninstall(e) {
        if (!e) return;
        hide();
        const sh = Paths.userBin + "/uninstall --app " + shq(e.id)
                 + "; echo; read -r -p 'Entrée pour fermer… ' _";
        Hyprland.dispatch("exec " + Paths.kitty + " --class app-uninstall -e sh -c " + shq(sh));
    }

    function iconSource(e) {
        const i = e.icon ?? "";
        if (i.startsWith("/")) return "file://" + i;
        return Quickshell.iconPath(i || "application-x-executable", "application-x-executable");
    }

    // --- Interface -------------------------------------------------------------------
    // Fond assombri ; clic en dehors du panneau → fermeture
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: win.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: win.hide() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(880, parent.width - 80)
        height: Math.min(590, parent.height - 120)
        radius: 18
        color: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.8)
        border.color: Theme.border
        border.width: 1

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }    // le clic dans le panneau ne ferme pas

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Champ de recherche
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                radius: 12
                color: Theme.pill
                border.color: Theme.pillBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    BarText { text: Theme.ic(0xf0349); font.pixelSize: 18; color: Theme.subtext }
                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 15
                        clip: true
                        selectByMouse: true
                        focus: true
                        onTextChanged: {
                            win.query = text;
                            if (text !== "") win.category = "all";
                            grid.currentIndex = 0;
                            grid.positionViewAtBeginning();
                        }
                        // Flèches : grille ; Tab : catégorie ; le reste : saisie
                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            event.accepted = true;
                            switch (event.key) {
                            case Qt.Key_Escape:
                                if (win.menuEntry) win.menuEntry = null;
                                else win.hide();
                                break;
                            case Qt.Key_Menu:
                                if (grid.currentItem) win.openMenu(win.results[grid.currentIndex], grid.currentItem, grid.currentItem.width / 2, grid.currentItem.height / 2);
                                break;
                            case Qt.Key_Down: grid.moveCurrentIndexDown(); break;
                            case Qt.Key_Up: grid.moveCurrentIndexUp(); break;
                            case Qt.Key_Left: grid.moveCurrentIndexLeft(); break;
                            case Qt.Key_Right: grid.moveCurrentIndexRight(); break;
                            case Qt.Key_Tab: win.cycleCategory(event.modifiers & Qt.ShiftModifier ? -1 : 1); break;
                            case Qt.Key_Backtab: win.cycleCategory(-1); break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter: win.activate(); break;
                            case Qt.Key_B:
                                if (ctrl) win.webSearch();
                                else event.accepted = false;
                                break;
                            default: event.accepted = false;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: "Rechercher une application…"
                            color: Theme.muted
                            font: search.font
                        }
                    }
                    BarText {
                        text: win.results.length + (win.results.length > 1 ? " applications" : " application")
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // Catégories ; le fond de la sélection glisse d'une ligne à l'autre
                Item {
                    id: sidebar
                    Layout.preferredWidth: 196
                    Layout.fillHeight: true
                    clip: true
                    readonly property int rowH: 34
                    readonly property int gap: 2
                    readonly property int selected: win.visibleCats.findIndex(c => c.id === win.category)

                    Rectangle {
                        width: parent.width
                        height: sidebar.rowH
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.12)
                        visible: sidebar.selected >= 0
                        y: Math.max(0, sidebar.selected) * (sidebar.rowH + sidebar.gap)
                        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    Column {
                        width: parent.width
                        spacing: sidebar.gap
                        Repeater {
                            model: win.visibleCats
                            Rectangle {
                                id: catRow
                                required property var modelData
                                readonly property bool current: win.category === modelData.id
                                width: sidebar.width
                                height: sidebar.rowH
                                radius: 10
                                color: catMa.containsMouse && !current ? Theme.rowHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                scale: catMa.pressed ? 0.97 : 1
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                ClickFx { id: catFx }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10
                                    BarText {
                                        text: Theme.ic(catRow.modelData.icon)
                                        font.pixelSize: 16
                                        color: catRow.modelData.color
                                        Layout.preferredWidth: 20
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    BarText {
                                        Layout.fillWidth: true
                                        text: catRow.modelData.label
                                        elide: Text.ElideRight
                                        font.bold: catRow.current
                                        color: catRow.current ? Theme.text : Theme.subtext
                                    }
                                    BarText {
                                        text: win.catCount[catRow.modelData.id] ?? 0
                                        color: Theme.muted
                                        font.pixelSize: 11
                                    }
                                }
                                MouseArea {
                                    id: catMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { catFx.play(); win.setCategory(catRow.modelData.id); search.forceActiveFocus(); }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.pillBorder }

                // Grille des applications
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    GridView {
                        id: grid
                        anchors.fill: parent
                        clip: true
                        readonly property int cols: Math.max(3, Math.floor(width / 124))
                        cellWidth: Math.floor(width / cols)
                        cellHeight: 106
                        boundsBehavior: Flickable.StopAtBounds
                        // ScriptModel : cases conservées d'une frappe à l'autre (elles glissent
                        // vers leur nouvelle place au lieu d'être recréées)
                        model: ScriptModel { values: win.results }

                        highlightMoveDuration: 150
                        highlight: Item {
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 12
                                color: Qt.rgba(1, 1, 1, 0.12)
                                border.color: Theme.pillBorder
                                border.width: 1
                            }
                        }

                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
                            NumberAnimation { property: "scale"; from: 0.8; to: 1; duration: 200; easing.type: Easing.OutBack }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "opacity"; to: 1; duration: 100 }
                            NumberAnimation { property: "scale"; to: 1; duration: 100 }
                        }

                        delegate: Item {
                            id: cell
                            required property var modelData
                            required property int index
                            width: grid.cellWidth
                            height: grid.cellHeight

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6
                                scale: cellMa.pressed ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                IconImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 48
                                    asynchronous: true
                                    source: win.iconSource(cell.modelData)
                                    scale: cell.GridView.isCurrentItem ? 1.1 : 1
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                }
                                BarText {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    text: cell.modelData.name
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignTop
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: cell.GridView.isCurrentItem ? Theme.text : Theme.subtext
                                }
                            }
                            MouseArea {
                                id: cellMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Souris bougée seulement : le défilement au clavier ne vole pas la sélection
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPositionChanged: if (!win.menuEntry) grid.currentIndex = cell.index
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        grid.currentIndex = cell.index;
                                        win.openMenu(cell.modelData, cell, mouse.x, mouse.y);
                                    } else win.launch(cell.modelData);
                                }
                            }
                        }
                    }

                    // Barre de défilement (indicateur)
                    Rectangle {
                        anchors.right: parent.right
                        width: 3
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.25)
                        visible: grid.visibleArea.heightRatio < 1
                        y: grid.visibleArea.yPosition * grid.height
                        height: grid.visibleArea.heightRatio * grid.height
                    }

                    // Rien trouvé : propose la recherche web
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: win.results.length === 0
                        spacing: 8
                        IconImage {
                            Layout.alignment: Qt.AlignHCenter
                            visible: win.q !== ""
                            implicitSize: 48
                            source: Quickshell.iconPath("brave-browser", "web-browser")
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            visible: win.q === ""
                            text: Theme.ic(0xf003b)
                            font.pixelSize: 44
                            color: Theme.muted
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Aucune application"
                            color: Theme.subtext
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 420
                            visible: win.q !== ""
                            elide: Text.ElideMiddle
                            text: "Entrée : rechercher « " + win.query.trim() + " » sur Brave"
                            color: Theme.blue
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // Rappel des touches
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [["Entrée", "lancer"], ["Tab", "catégorie"], ["Ctrl+B", "recherche web"], ["Clic droit", "désinstaller"], ["Échap", "fermer"]]
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
                        BarText { text: modelData[1]; font.pixelSize: 11; color: Theme.muted }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        // Menu contextuel ; clic en dehors (dans le panneau) → fermeture
        MouseArea {
            anchors.fill: parent
            visible: win.menuEntry !== null
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: win.menuEntry = null
        }
        Rectangle {
            id: ctxMenu
            visible: win.menuEntry !== null
            width: 200
            height: ctxCol.implicitHeight + 12
            x: Math.min(win.menuPos.x, panel.width - width - 8)
            y: Math.min(win.menuPos.y, panel.height - height - 8)
            radius: 12
            color: Qt.rgba(30 / 255, 30 / 255, 30 / 255, 0.97)
            border.color: Theme.border
            border.width: 1

            opacity: visible ? 1 : 0
            scale: visible ? 1 : 0.9
            transformOrigin: Item.TopLeft
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

            Column {
                id: ctxCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                BarText {
                    width: parent.width
                    leftPadding: 8
                    rightPadding: 8
                    topPadding: 4
                    bottomPadding: 4
                    text: win.menuEntry?.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    color: Theme.muted
                }

                Repeater {
                    model: [
                        { label: "Lancer", icon: 0xf040a, color: Theme.text, act: "launch" },
                        { label: "Désinstaller", icon: 0xf0a7a, color: Theme.red, act: "uninstall" }
                    ]
                    Rectangle {
                        id: ctxRow
                        required property var modelData
                        width: ctxCol.width
                        height: 32
                        radius: 8
                        color: ctxMa.containsMouse ? Theme.rowHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10
                            BarText {
                                text: Theme.ic(ctxRow.modelData.icon)
                                font.pixelSize: 15
                                color: ctxRow.modelData.color
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter
                            }
                            BarText {
                                Layout.fillWidth: true
                                text: ctxRow.modelData.label
                                color: ctxRow.modelData.color
                            }
                        }
                        MouseArea {
                            id: ctxMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const e = win.menuEntry;
                                win.menuEntry = null;
                                if (ctxRow.modelData.act === "launch") win.launch(e);
                                else win.uninstall(e);
                            }
                        }
                    }
                }
            }
        }
    }
}
