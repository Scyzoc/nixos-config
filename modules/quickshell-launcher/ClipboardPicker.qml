import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// Presse-papiers (SUPER+V) : historique cliphist avec recherche, onglets par type
// (texte, liens, images) et aperçu complet de l'entrée sélectionnée.
// Entrée : copie puis colle dans la fenêtre active ; Maj+Entrée : copie seulement.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-clipboard"
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
        tab = "all";
        showPreview = false;
        closeTimer.stop();
        visible = true;
        open = true;
        list.currentIndex = 0;
        list.positionViewAtBeginning();
        search.forceActiveFocus();
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Historique --------------------------------------------------------------
    // clipboard-index (clipboard.nix) : lignes « id <aperçu> » de cliphist, la plus récente
    // d'abord ; pour une image, un 3e champ donne le fichier décodé (cache). Tabulations.
    property var items: []      // [{ id, text, kind, file, ext, dims, size }]
    readonly property var byId: {
        const m = {};
        for (const it of items) m[it.id] = it;
        return m;
    }

    function parse(line) {
        const p = line.split("\t");
        if (p.length < 2 || p[0] === "") return null;
        const text = p[1];
        const bin = text.match(/^\[\[ binary data (.+) (\w+) (\d+)x(\d+) \]\]$/);
        if (bin) return { id: p[0], text: "Image " + bin[2].toUpperCase(), kind: "image", file: p[2] ?? "",
                          ext: bin[2].toUpperCase(), dims: bin[3] + " × " + bin[4], size: bin[1] };
        let kind = "text";
        if (/^(https?:\/\/|www\.)\S+$/i.test(text)) kind = "link";
        else if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(text)) kind = "color";
        else if (isSecret(text)) kind = "secret";
        return { id: p[0], text: text, kind: kind };
    }

    // Code / mot de passe / clé : un seul « mot » qui ressemble à un secret
    // (« 9385495840 », « fed73kdof* », « Dife7zlsef »), sans chemins, mails, fichiers, versions
    function isSecret(t) {
        if (/^\d{4,20}$/.test(t)) return true;                       // code PIN, OTP, numéro
        if (t.length < 6 || t.length > 128 || /\s/.test(t)) return false;
        if (/[\/\\]/.test(t) || /^~/.test(t)) return false;           // chemin
        if (/^[^@]+@[^@]+\.[a-z]{2,}$/i.test(t)) return false;        // adresse mail
        if (/^[\w-]+\.[a-z]{2,4}$/i.test(t)) return false;             // nom de fichier
        if (/^v?\d+([.:-]\d+)+$/i.test(t)) return false;               // version, heure, date
        // Ponctuation collée au mot (« bonjour! », « (test) ») : pas un secret
        const core = t.replace(/^[!?.,;:()"'«»…\[\]{}]+|[!?.,;:()"'«»…\[\]{}]+$/g, "");
        // Lettres mêlées à des chiffres ou symboles
        const random = s => /[A-Za-zÀ-ÿ]/.test(s) && /[^A-Za-zÀ-ÿ]/.test(s);
        // Mot composé (« x86_64-linux ») : secret seulement si un morceau est aléatoire
        if (/[._-]/.test(core))
            return core.split(/[._-]+/).some(s => s.length >= 6 && random(s));
        return core.length >= 6 && random(core);
    }

    Process {
        id: indexer
        command: [Paths.userBin + "/clipboard-index"]
        property var lines: []
        stdout: SplitParser { onRead: line => indexer.lines.push(line) }
        onExited: {
            win.items = indexer.lines.map(win.parse).filter(it => it !== null);
            // Liste mise à jour sous la sélection : on reste en haut
            if (win.open && list.currentIndex < 0) list.currentIndex = 0;
        }
    }
    function refresh() {
        if (indexer.running) return;
        indexer.lines = [];
        indexer.running = true;
    }
    Component.onCompleted: refresh()

    // --- Onglets et recherche ----------------------------------------------------
    readonly property var tabs: [
        { id: "all", label: "Tout", icon: 0xf014c, color: Theme.text },
        { id: "text", label: "Texte", icon: 0xf09a8, color: Theme.green },
        { id: "link", label: "Liens", icon: 0xf0339, color: Theme.blue },
        { id: "secret", label: "Codes", icon: 0xf0306, color: Theme.yellow },
        { id: "image", label: "Images", icon: 0xf02e9, color: Theme.pink }
    ]
    property string tab: "all"
    // Les couleurs (#rrggbb) sont rangées avec le texte
    function tabOf(it) { return it.kind === "color" ? "text" : it.kind; }
    readonly property var counts: {
        const n = { all: items.length, text: 0, link: 0, secret: 0, image: 0 };
        for (const it of items) n[tabOf(it)]++;
        return n;
    }

    function norm(s) {
        return (s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }
    property string query: ""
    readonly property string q: norm(query.trim())
    // Identifiants affichés : onglet + texte tapé (cherché dans l'aperçu de cliphist)
    readonly property var shown: items.filter(it => (tab === "all" || tabOf(it) === tab)
                                                     && (q === "" || norm(it.text).indexOf(q) >= 0))
                                      .map(it => it.id)
    readonly property var selected: byId[shown[list.currentIndex] ?? ""] ?? null

    function setTab(id) {
        tab = id;
        list.currentIndex = 0;
        list.positionViewAtBeginning();
    }
    function cycleTab(d) {
        const i = tabs.findIndex(t => t.id === tab);
        setTab(tabs[(i + d + tabs.length) % tabs.length].id);
    }

    // --- Aperçu : contenu complet de l'entrée sélectionnée (texte) ------------------
    property string previewText: ""
    property string previewFor: ""
    onSelectedChanged: {
        if (!selected || selected.kind === "image") { previewText = ""; previewFor = ""; return; }
        if (showPreview && selected.id !== previewFor) previewDelay.restart();
    }

    // Volet d'aperçu (bouton œil sous les onglets, Ctrl+P), masqué à chaque ouverture.
    // Masqué : menu étroit, liste seule.
    property bool showPreview: false
    function setPreview(on) {
        showPreview = on;
        if (on && selected && selected.kind !== "image" && selected.id !== previewFor) previewDelay.restart();
    }
    Timer {
        id: previewDelay
        interval: 60
        onTriggered: {
            if (!win.selected || win.selected.kind === "image") return;
            if (shower.running) { restart(); return; }
            shower.forId = win.selected.id;
            shower.command = [Paths.userBin + "/clipboard-show", shower.forId];
            shower.running = true;
        }
    }
    Process {
        id: shower
        property string forId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (shower.forId !== win.selected?.id) return;
                win.previewText = text;
                win.previewFor = shower.forId;
            }
        }
    }

    // --- Actions ---------------------------------------------------------------------
    // Par Hyprland (« exec ») : wl-copy reste propriétaire du presse-papiers même si le
    // service des menus redémarre
    function paste(id, copyOnly) {
        if (!id) return;
        hide();
        Hyprland.dispatch("exec " + Paths.userBin + "/clipboard-paste " + id + (copyOnly ? " copy" : ""));
    }
    function remove(id) {
        if (!id) return;
        const i = list.currentIndex;
        items = items.filter(it => it.id !== id);
        list.currentIndex = Math.min(i, shown.length - 1);
        Quickshell.execDetached([Paths.userBin + "/clipboard-delete", id]);
    }

    function wipe() {
        items = [];
        previewText = "";
        previewFor = "";
        Quickshell.execDetached([Paths.userBin + "/clipboard-wipe"]);
    }

    function kindIcon(k) {
        if (k === "link") return Theme.ic(0xf0339);
        if (k === "image") return Theme.ic(0xf02e9);
        if (k === "secret") return Theme.ic(0xf0306);
        return Theme.ic(0xf09a8);
    }
    function kindColor(k) {
        if (k === "link") return Theme.blue;
        if (k === "image") return Theme.pink;
        if (k === "secret") return Theme.yellow;
        return Theme.subtext;
    }

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
        width: Math.min(win.showPreview ? 760 : 470, parent.width - 80)
        height: Math.min(470, parent.height - 120)
        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
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
                            list.currentIndex = 0;
                            list.positionViewAtBeginning();
                        }
                        // Haut / bas : liste ; Tab : onglet ; le reste : saisie
                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            const shift = event.modifiers & Qt.ShiftModifier;
                            event.accepted = true;
                            switch (event.key) {
                            case Qt.Key_Escape: win.hide(); break;
                            case Qt.Key_Down: list.incrementCurrentIndex(); break;
                            case Qt.Key_Up: list.decrementCurrentIndex(); break;
                            case Qt.Key_PageDown: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 8); break;
                            case Qt.Key_PageUp: list.currentIndex = Math.max(0, list.currentIndex - 8); break;
                            case Qt.Key_Tab: win.cycleTab(shift ? -1 : 1); break;
                            case Qt.Key_Backtab: win.cycleTab(-1); break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter: win.paste(win.selected?.id, shift); break;
                            case Qt.Key_P:
                                if (ctrl) win.setPreview(!win.showPreview);
                                else event.accepted = false;
                                break;
                            case Qt.Key_Delete:
                                if (ctrl) win.remove(win.selected?.id);
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
                            text: "Rechercher dans le presse-papiers…"
                            color: Theme.muted
                            font: search.font
                        }
                    }
                    BarText {
                        text: win.shown.length + (win.shown.length > 1 ? " entrées" : " entrée")
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // Colonne de gauche : onglets en haut, « tout effacer » en bas
                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 8

                // Onglets verticaux (icônes seules) ; le curseur glisse de l'un à l'autre
                Rectangle {
                    id: seg
                    readonly property int segH: 40
                    readonly property int current: Math.max(0, win.tabs.findIndex(t => t.id === win.tab))
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 46
                    implicitHeight: segH * win.tabs.length + 6
                    radius: 12
                    color: Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1

                    Rectangle {
                        x: 3
                        y: 3 + seg.current * seg.segH
                        width: parent.width - 6
                        height: seg.segH
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.16)
                        Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }
                    Column {
                        x: 3
                        y: 3
                        Repeater {
                            model: win.tabs
                            Item {
                                id: segItem
                                required property var modelData
                                readonly property bool current: win.tab === modelData.id
                                width: seg.width - 6
                                height: seg.segH
                                BarText {
                                    anchors.centerIn: parent
                                    text: Theme.ic(segItem.modelData.icon)
                                    font.pixelSize: 17
                                    color: segItem.current ? segItem.modelData.color : Theme.muted
                                    Behavior on color { ColorAnimation { duration: 200 } }
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

                // Volet d'aperçu : œil (affiché) / œil barré (masqué)
                Rectangle {
                    implicitWidth: 46
                    implicitHeight: 40
                    radius: 12
                    color: prevMa.containsMouse ? Theme.rowHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: prevMa.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                    BarText {
                        anchors.centerIn: parent
                        text: Theme.ic(win.showPreview ? 0xf06d0 : 0xf06d1)    // md-eye_outline / md-eye_off_outline
                        font.pixelSize: 18
                        color: win.showPreview ? Theme.text : Theme.muted
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { win.setPreview(!win.showPreview); search.forceActiveFocus(); }
                    }
                }

                Item { Layout.fillHeight: true }

                // Tout effacer (historique + presse-papiers courant) : 1er clic arme le
                // bouton (rouge, coche), 2e clic dans les 3 s confirme
                Rectangle {
                    id: wipeBtn
                    property bool armed: false
                    implicitWidth: 46
                    implicitHeight: 40
                    radius: 12
                    opacity: win.items.length > 0 ? 1 : 0.4
                    color: armed ? Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.25)
                         : wipeMa.containsMouse ? Theme.pillHover : Theme.pill
                    border.color: armed ? Theme.red : Theme.pillBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: wipeMa.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                    ClickFx { id: wipeFx; color: Theme.red }

                    BarText {
                        anchors.centerIn: parent
                        text: Theme.ic(wipeBtn.armed ? 0xf012c : 0xf0a7a)
                        font.pixelSize: 17
                        color: wipeBtn.armed || wipeMa.containsMouse ? Theme.red : Theme.muted
                    }
                    Timer { id: disarm; interval: 3000; onTriggered: wipeBtn.armed = false }
                    Connections {
                        target: win
                        function onOpenChanged() { wipeBtn.armed = false; }
                    }
                    MouseArea {
                        id: wipeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: win.items.length > 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wipeFx.play();
                            if (wipeBtn.armed) { wipeBtn.armed = false; win.wipe(); }
                            else { wipeBtn.armed = true; disarm.restart(); }
                            search.forceActiveFocus();
                        }
                    }
                }
                }

                // Liste des entrées
                Item {
                    Layout.preferredWidth: win.showPreview ? Math.round(panel.width * 0.42) : -1
                    Layout.fillWidth: !win.showPreview
                    Layout.fillHeight: true

                    ListView {
                        id: list
                        anchors.fill: parent
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        // ScriptModel : lignes conservées d'une frappe à l'autre (elles glissent)
                        model: ScriptModel { values: win.shown }

                        highlightMoveDuration: 140
                        highlightResizeDuration: 140
                        highlight: Rectangle {
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.12)
                            border.color: Theme.pillBorder
                            border.width: 1
                        }

                        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
                        remove: Transition {
                            NumberAnimation { property: "opacity"; to: 0; duration: 140 }
                            NumberAnimation { property: "x"; to: -30; duration: 140 }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "y"; duration: 180; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "opacity"; to: 1; duration: 100 }
                        }

                        delegate: Item {
                            id: row
                            required property string modelData
                            required property int index
                            readonly property var it: win.byId[modelData] ?? ({ text: "", kind: "text" })
                            readonly property bool current: ListView.isCurrentItem
                            width: list.width
                            height: it.kind === "image" ? 62 : 38

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 10

                                // Image : vignette ; couleur : pastille ; sinon icône du type
                                ClippingRectangle {
                                    visible: row.it.kind === "image"
                                    Layout.preferredWidth: 74
                                    Layout.preferredHeight: 48
                                    radius: 7
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    Image {
                                        anchors.fill: parent
                                        source: row.it.kind === "image" && row.it.file ? "file://" + row.it.file : ""
                                        sourceSize.width: 148
                                        sourceSize.height: 96
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                                Rectangle {
                                    visible: row.it.kind === "color"
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    radius: 5
                                    color: row.it.kind === "color" ? row.it.text : "transparent"
                                    border.color: Qt.rgba(1, 1, 1, 0.3)
                                    border.width: 1
                                }
                                BarText {
                                    visible: row.it.kind !== "image" && row.it.kind !== "color"
                                    text: win.kindIcon(row.it.kind)
                                    font.pixelSize: 15
                                    color: win.kindColor(row.it.kind)
                                    Layout.preferredWidth: 18
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    BarText {
                                        Layout.fillWidth: true
                                        text: row.it.text
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        font.pixelSize: 12
                                        color: row.current ? Theme.text : row.it.kind === "link" ? Theme.blue : Theme.subtext
                                    }
                                    BarText {
                                        visible: row.it.kind === "image"
                                        text: (row.it.dims ?? "") + "  ·  " + (row.it.size ?? "")
                                        font.pixelSize: 11
                                        color: Theme.muted
                                    }
                                }

                                // Supprimer l'entrée (sur la ligne sélectionnée)
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 7
                                    opacity: row.current ? 1 : 0
                                    color: delMa.containsMouse ? Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.25) : "transparent"
                                    BarText {
                                        anchors.centerIn: parent
                                        text: Theme.ic(0xf0a7a)
                                        font.pixelSize: 15
                                        color: delMa.containsMouse ? Theme.red : Theme.muted
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Souris bougée seulement : le défilement au clavier ne vole pas la sélection
                                onPositionChanged: list.currentIndex = row.index
                                onClicked: win.paste(row.modelData, false)
                            }
                            // Par-dessus la zone de clic de la ligne
                            MouseArea {
                                id: delMa
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 26
                                enabled: row.current
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.remove(row.modelData)
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: -7
                        width: 3
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.25)
                        visible: list.visibleArea.heightRatio < 1
                        y: list.visibleArea.yPosition * list.height
                        height: list.visibleArea.heightRatio * list.height
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: win.shown.length === 0
                        spacing: 8
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Theme.ic(0xf014c)
                            font.pixelSize: 44
                            color: Theme.muted
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: win.items.length === 0 ? "Presse-papiers vide" : "Aucune entrée"
                            color: Theme.subtext
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.pillBorder; visible: win.showPreview }

                // Aperçu de l'entrée sélectionnée
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    visible: win.showPreview && win.selected !== null

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        BarText {
                            text: win.kindIcon(win.selected?.kind ?? "text")
                            font.pixelSize: 16
                            color: win.kindColor(win.selected?.kind ?? "text")
                        }
                        BarText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.bold: true
                            text: {
                                const s = win.selected;
                                if (!s) return "";
                                if (s.kind === "image") return "Image " + s.ext;
                                if (s.kind === "link") return "Lien";
                                if (s.kind === "color") return "Couleur";
                                if (s.kind === "secret") return "Code / mot de passe";
                                return "Texte";
                            }
                        }
                        BarText {
                            color: Theme.muted
                            font.pixelSize: 11
                            text: {
                                const s = win.selected;
                                if (!s) return "";
                                if (s.kind === "image") return s.dims + "  ·  " + s.size;
                                if (win.previewFor !== s.id) return "";
                                const n = win.previewText.length, l = win.previewText.split("\n").length;
                                return n + (n > 1 ? " caractères" : " caractère") + (l > 1 ? "  ·  " + l + " lignes" : "");
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Theme.pillBorder
                        border.width: 1
                        clip: true

                        // Image entière
                        Image {
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: win.selected?.kind === "image"
                            source: win.selected?.kind === "image" && win.selected.file ? "file://" + win.selected.file : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }

                        // Couleur : grande pastille au-dessus du code
                        Rectangle {
                            visible: win.selected?.kind === "color"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 28
                            width: 120
                            height: 120
                            radius: 24
                            color: win.selected?.kind === "color" ? win.selected.text : "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.3)
                            border.width: 1
                        }

                        // Texte complet, défilable à la molette
                        Flickable {
                            id: textView
                            anchors.fill: parent
                            anchors.margins: 12
                            anchors.topMargin: win.selected?.kind === "color" ? 170 : 12
                            visible: win.selected !== null && win.selected.kind !== "image"
                            clip: true
                            contentHeight: fullText.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            BarText {
                                id: fullText
                                width: textView.width
                                // Aperçu court de cliphist en attendant le contenu complet
                                text: win.previewFor === win.selected?.id ? win.previewText : (win.selected?.text ?? "")
                                onTextChanged: textView.contentY = 0
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAnywhere
                                verticalAlignment: Text.AlignTop
                                horizontalAlignment: win.selected?.kind === "color" ? Text.AlignHCenter : Text.AlignLeft
                                font.pixelSize: 12
                                lineHeight: 1.25
                                color: win.selected?.kind === "link" ? Theme.blue : Theme.text
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
                    // Menu étroit (aperçu masqué) : l'essentiel seulement
                    model: win.showPreview
                        ? [["Entrée", "coller"], ["Maj+Entrée", "copier"], ["Tab", "type"], ["Ctrl+P", "aperçu"], ["Échap", "fermer"]]
                        : [["Entrée", "coller"], ["Tab", "type"], ["Ctrl+P", "aperçu"]]
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
