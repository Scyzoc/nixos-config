import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Emojis (SUPER+;) : grille par catégorie, récents, recherche en français (noms et
// mots-clés CLDR, sans accents) et couleur de peau mémorisée.
// Entrée / clic : colle dans la fenêtre active ; Maj+Entrée / clic droit : copie seulement.
// Données générées au build (assets/emoji-data.py, emoji.nix).
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-emoji"
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

    readonly property int cols: 10
    // Tailles des planches d'images (emoji.nix) : repos et survol
    readonly property int small: 28
    readonly property int big: 33

    // --- Ouverture / fermeture -------------------------------------------------
    property bool open: false
    visible: false

    function show() {
        const m = Hyprland.focusedMonitor;
        win.screen = Quickshell.screens.find(s => s.name === m?.name) ?? Quickshell.screens[0];
        search.text = "";
        tab = recent.length > 0 ? "recent" : 0;
        closeTimer.stop();
        visible = true;
        open = true;
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
        search.forceActiveFocus();
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Données -----------------------------------------------------------------
    // emojis[i] = [emoji, groupe, nom, recherche, teintes (5 variantes ou 0),
    //              case dans les planches, cases des teintes (ou 0)]
    property var emojis: []
    property var names: []      // nom normalisé (début du champ recherche)
    property var byChar: ({})   // emoji → indice
    property var byGroup: []    // groupe → indices (onglets calculés une seule fois)
    property int atlasCols: 64
    FileView {
        id: dataFile
        path: Paths.emojiDir + "/emoji.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                const idx = {}, groups = d.groups.map(() => []);
                d.emojis.forEach((e, i) => {
                    idx[e[0]] = i;
                    groups[e[1]].push(i);
                });
                win.names = d.emojis.map(e => e[3].split(" · ")[0]);
                win.byChar = idx;
                win.byGroup = groups;
                win.atlasCols = d.cols;
                win.emojis = d.emojis;
            } catch (e) {
                console.warn("emoji.json illisible : " + e);
            }
        }
    }

    // Récents (emojis de base, le plus récent d'abord) et couleur de peau (0 : jaune)
    property var recent: []
    property int tone: 0
    FileView {
        id: stateFile
        path: Paths.emojiState
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                win.recent = s.recent ?? [];
                win.tone = s.tone ?? 0;
            } catch (e) {}
        }
    }
    function save() { stateFile.setText(JSON.stringify({ recent: recent, tone: tone })); }
    function setTone(t) {
        tone = t;
        save();
    }
    function remember(e) {
        recent = [e].concat(recent.filter(x => x !== e)).slice(0, 50);
        save();
    }

    // Emoji affiché : variante de la couleur de peau choisie si elle existe
    function glyph(i) {
        const e = emojis[i];
        if (!e) return "";
        return tone > 0 && e[4] && e[4][tone - 1] ? e[4][tone - 1] : e[0];
    }
    // Sa case dans les planches d'images (-1 : aucune)
    function slot(i) {
        const e = emojis[i];
        if (!e) return -1;
        return tone > 0 && e[6] && e[6][tone - 1] >= 0 ? e[6][tone - 1] : e[5];
    }

    // Emoji dessiné : morceau d'une planche d'images (une seule image décodée et envoyée
    // au GPU pour tous les emojis) au lieu d'un rendu de police par emoji
    function atlas(size) { return "file://" + Paths.emojiDir + "/atlas-" + size + ".png"; }
    component Sprite: Item {
        property int slot: -1
        property int size: win.small
        width: size
        height: size
        clip: true
        visible: slot >= 0
        Image {
            source: win.atlas(parent.size)
            x: -(parent.slot % win.atlasCols) * parent.size
            y: -Math.floor(parent.slot / win.atlasCols) * parent.size
            smooth: false    // affichée à sa taille exacte, pixel pour pixel
        }
    }
    // Planches chargées dès le démarrage (et gardées en cache) : pas d'attente à l'ouverture
    Image { visible: false; asynchronous: true; source: win.atlas(win.small) }
    Image { visible: false; asynchronous: true; source: win.atlas(win.big) }

    // --- Catégories et recherche --------------------------------------------------
    readonly property var tabs: [
        { id: "recent", label: "Récents", icon: 0xf02da, color: Theme.text },
        { id: 0, label: "Smileys et émotions", icon: 0xf01f5, color: Theme.yellow },
        { id: 1, label: "Personnes et corps", icon: 0xf1822, color: Theme.peach },
        { id: 2, label: "Animaux et nature", icon: 0xf03e9, color: Theme.green },
        { id: 3, label: "Nourriture et boissons", icon: 0xf0c84, color: Theme.red },
        { id: 4, label: "Voyages et lieux", icon: 0xf001d, color: Theme.sky },
        { id: 5, label: "Activités", icon: 0xf04b8, color: Theme.teal },
        { id: 6, label: "Objets", icon: 0xf0336, color: Theme.mauve },
        { id: 7, label: "Symboles", icon: 0xf02d5, color: Theme.pink },
        { id: 8, label: "Drapeaux", icon: 0xf023d, color: Theme.blue }
    ]
    property var tab: "recent"
    readonly property var currentTab: tabs.find(t => t.id === tab) ?? tabs[0]

    function setTab(id) {
        search.text = "";
        tab = id;
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
    }
    function cycleTab(d) {
        const i = tabs.findIndex(t => t.id === tab);
        setTab(tabs[(i + d + tabs.length) % tabs.length].id);
    }

    function norm(s) {
        return (s ?? "").toLowerCase().replace(/’/g, "'").replace(/œ/g, "oe").replace(/æ/g, "ae")
                        .normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }
    property string query: ""
    readonly property string q: norm(query.trim()).replace(/\s+/g, " ")
    readonly property bool searching: q !== ""

    // Recherche : tous les mots tapés doivent apparaître. Rang : nom exact, mot entier
    // du nom, mot-clé exact, début du nom, début d'un mot du nom, le reste
    function find(q) {
        const toks = q.split(" ");
        const hits = [];
        for (let i = 0; i < emojis.length; i++) {
            const s = emojis[i][3];
            if (!toks.every(t => s.indexOf(t) >= 0)) continue;
            const n = names[i];
            const score = n === q ? 0
                        : (" " + n + " ").indexOf(" " + q + " ") >= 0 ? 1
                        : (s + " · ").indexOf(" · " + q + " · ") >= 0 ? 2
                        : n.startsWith(q) ? 3
                        : (" " + n).indexOf(" " + toks[0]) >= 0 ? 4 : 5;
            hits.push([score, i]);
        }
        hits.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
        return hits.map(h => h[1]);
    }

    // Indices affichés dans la grille
    readonly property var shown: {
        if (searching) return find(q);
        if (tab === "recent") return recent.map(e => byChar[e]).filter(i => i !== undefined);
        return byGroup[tab] ?? [];
    }
    readonly property int selected: shown[grid.currentIndex] ?? -1
    // Couleur de peau réglable seulement dans « Personnes et corps » (onglet de la main)
    readonly property bool toneTab: !searching && tab === 1

    // --- Actions ---------------------------------------------------------------------
    // Par Hyprland (« exec ») : wl-copy reste propriétaire du presse-papiers même si le
    // service des menus redémarre. Emoji passé en codepoints hexa.
    function paste(i, copyOnly) {
        if (i < 0 || !emojis[i]) return;
        const g = glyph(i);
        // Points de code un par un : Array.from(g) de QML coupe les paires UTF-16
        const cps = [];
        for (let k = 0; k < g.length; k++) {
            const c = g.codePointAt(k);
            cps.push(c.toString(16));
            if (c > 0xffff) k++;
        }
        const hex = cps.join("-");
        remember(emojis[i][0]);
        // Collage : fermeture sans fondu, la fenêtre récupère le clavier tout de suite
        if (copyOnly) hide();
        else { open = false; visible = false; }
        Hyprland.dispatch("exec " + Paths.userBin + "/emoji-paste " + hex + (copyOnly ? " copy" : ""));
    }

    // Couleurs de peau : jaune par défaut puis les 5 teintes Fitzpatrick
    readonly property var toneColors: ["#ffc83d", "#f7d7c4", "#e6b88e", "#c68d5c", "#9a6440", "#5d3b2a"]
    readonly property var toneNames: ["Par défaut", "Peau claire", "Peau moyennement claire",
                                      "Peau légèrement mate", "Peau mate", "Peau foncée"]

    // --- Interface -------------------------------------------------------------------
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
        width: Math.min(540, parent.width - 80)
        height: Math.min(560, parent.height - 120)
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

            // Recherche
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
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
                        font.pixelSize: 14
                        clip: true
                        selectByMouse: true
                        focus: true
                        onTextChanged: {
                            win.query = text;
                            grid.currentIndex = 0;
                            grid.positionViewAtBeginning();
                        }
                        // Flèches : grille ; Tab : catégorie ; Ctrl+T : couleur de peau (onglet main) ; le reste : saisie
                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            const shift = event.modifiers & Qt.ShiftModifier;
                            event.accepted = true;
                            switch (event.key) {
                            case Qt.Key_Escape: win.hide(); break;
                            case Qt.Key_Down: grid.moveCurrentIndexDown(); break;
                            case Qt.Key_Up: grid.moveCurrentIndexUp(); break;
                            case Qt.Key_Left: grid.moveCurrentIndexLeft(); break;
                            case Qt.Key_Right: grid.moveCurrentIndexRight(); break;
                            case Qt.Key_PageDown: grid.currentIndex = Math.min(grid.count - 1, grid.currentIndex + win.cols * 4); break;
                            case Qt.Key_PageUp: grid.currentIndex = Math.max(0, grid.currentIndex - win.cols * 4); break;
                            case Qt.Key_Tab: win.cycleTab(shift ? -1 : 1); break;
                            case Qt.Key_Backtab: win.cycleTab(-1); break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter: win.paste(win.selected, shift); break;
                            case Qt.Key_T:
                                if (ctrl && win.toneTab) win.setTone((win.tone + 1) % 6);
                                else event.accepted = false;
                                break;
                            default: event.accepted = false;
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            elide: Text.ElideRight
                            visible: search.text === ""
                            text: "Rechercher un emoji…"
                            color: Theme.muted
                            font: search.font
                        }
                    }
                    BarText {
                        visible: win.searching
                        text: win.shown.length + (win.shown.length > 1 ? " résultats" : " résultat")
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }

            // Catégories (icônes seules) ; le curseur glisse de l'une à l'autre
            Rectangle {
                id: seg
                readonly property int current: Math.max(0, win.tabs.findIndex(t => t.id === win.tab))
                readonly property real segW: (width - 6) / win.tabs.length
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 12
                color: Theme.pill
                border.color: Theme.pillBorder
                border.width: 1

                Rectangle {
                    x: 3 + seg.current * seg.segW
                    y: 3
                    width: seg.segW
                    height: parent.height - 6
                    radius: 9
                    color: Qt.rgba(1, 1, 1, 0.16)
                    opacity: win.searching ? 0 : 1
                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                Row {
                    x: 3
                    y: 3
                    Repeater {
                        model: win.tabs
                        Item {
                            id: segItem
                            required property var modelData
                            readonly property bool current: !win.searching && win.tab === modelData.id
                            width: seg.segW
                            height: seg.height - 6
                            BarText {
                                anchors.centerIn: parent
                                text: Theme.ic(segItem.modelData.icon)
                                font.pixelSize: 17
                                color: segItem.current ? segItem.modelData.color
                                     : segMa.containsMouse ? Theme.subtext : Theme.muted
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            MouseArea {
                                id: segMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { win.setTab(segItem.modelData.id); search.forceActiveFocus(); }
                            }
                        }
                    }
                }
            }

            // Titre de la section
            BarText {
                Layout.leftMargin: 4
                text: win.searching ? "Résultats" : win.currentTab.label
                font.pixelSize: 12
                font.bold: true
                color: Theme.subtext
            }

            // Grille
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: grid
                    anchors.fill: parent
                    clip: true
                    cellWidth: Math.floor(width / win.cols)
                    cellHeight: cellWidth
                    keyNavigationWraps: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: cellHeight * 6    // lignes prêtes avant d'apparaître au défilement
                    model: ScriptModel { values: win.shown }

                    highlightMoveDuration: 100
                    highlight: Rectangle {
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.12)
                        border.color: Theme.pillBorder
                        border.width: 1
                    }

                    delegate: Item {
                        id: cell
                        required property int modelData
                        required property int index
                        readonly property bool current: GridView.isCurrentItem
                        width: grid.cellWidth
                        height: grid.cellHeight

                        // Deux planches : 28 px au repos, 33 px au survol, chacune affichée à sa
                        // taille exacte (nette). Seul le zoom d'entrée du survol est étiré.
                        readonly property int slot: win.slot(modelData)
                        Sprite {
                            x: Math.round((cell.width - size) / 2)
                            y: Math.round((cell.height - size) / 2)
                            size: win.small
                            slot: cell.current ? -1 : cell.slot
                        }
                        Sprite {
                            x: Math.round((cell.width - size) / 2)
                            y: Math.round((cell.height - size) / 2)
                            size: win.big
                            slot: cell.current ? cell.slot : -1
                            scale: cell.current ? 1 : win.small / win.big
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            // Souris bougée seulement : le défilement au clavier ne vole pas la sélection
                            onPositionChanged: grid.currentIndex = cell.index
                            onClicked: mouse => win.paste(cell.modelData, mouse.button === Qt.RightButton)
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: -7
                    width: 3
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.25)
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
                        text: Theme.ic(win.searching ? 0xf0349 : 0xf02da)
                        font.pixelSize: 44
                        color: Theme.muted
                    }
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: win.emojis.length === 0 ? "Données d'emojis introuvables"
                            : win.searching ? "Aucun emoji" : "Aucun emoji récent"
                        color: Theme.subtext
                    }
                }
            }

            // Emoji sélectionné + couleur de peau
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 58
                radius: 12
                color: Theme.pill
                border.color: Theme.pillBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Item {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Sprite {
                            x: Math.round((36 - size) / 2)
                            y: Math.round((36 - size) / 2)
                            size: win.big
                            slot: win.slot(win.selected)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        BarText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.bold: true
                            text: {
                                const n = win.emojis[win.selected]?.[2] ?? "";
                                return n.charAt(0).toUpperCase() + n.slice(1);
                            }
                        }
                        BarText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 11
                            color: Theme.muted
                            text: {
                                const e = win.emojis[win.selected];
                                if (!e) return "";
                                return win.tabs[e[1] + 1].label + (e[4] ? "  ·  " + win.toneNames[win.tone].toLowerCase() : "");
                            }
                        }
                    }

                    // Couleur de peau (Ctrl+T), onglet « Personnes et corps » seulement
                    Row {
                        visible: win.toneTab
                        spacing: 4
                        Repeater {
                            model: 6
                            Item {
                                id: toneItem
                                required property int index
                                readonly property bool current: win.tone === index
                                width: 22
                                height: 22
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: toneItem.current ? 20 : 14
                                    height: width
                                    radius: width / 2
                                    color: win.toneColors[toneItem.index]
                                    border.color: toneItem.current ? Theme.text : Qt.rgba(1, 1, 1, 0.2)
                                    border.width: toneItem.current ? 2 : 1
                                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { win.setTone(toneItem.index); search.forceActiveFocus(); }
                                }
                            }
                        }
                    }
                }
            }

            // Rappel des touches
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [["Entrée", "coller"], ["Maj+Entrée", "copier"], ["Tab", "catégorie"]]
                           .concat(win.toneTab ? [["Ctrl+T", "peau"]] : [])
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
    }
}
