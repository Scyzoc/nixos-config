import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Projets (SUPER+H) : liste des projets Atlas ; un clic ouvre les fenêtres de travail du
// projet (terminaux, Claude Code, navigateur…) sur le workspace vide le plus proche.
// La roue dentée (ou Ctrl+E) ouvre l'éditeur de recette. Backend : `atlas-workspace`
// (modules/atlas-workspace.nix), recettes dans ~/.config/atlas/workspaces.json.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-projects"
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

    property bool open: false
    visible: false

    function show() {
        const m = Hyprland.focusedMonitor;
        win.screen = Quickshell.screens.find(s => s.name === m?.name) ?? Quickshell.screens[0];
        search.text = "";
        editing = null;
        error = "";
        closeTimer.stop();
        visible = true;
        open = true;
        grid.currentIndex = 0;
        search.forceActiveFocus();
        listProc.command = [Paths.userBin + "/atlas-workspace", "list"];
        listProc.running = true;
        refreshProc.running = true;
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Données ---------------------------------------------------------------------
    property var projects: []
    property bool refreshing: false
    property string error: ""

    function parseList(text) {
        try {
            const r = JSON.parse(text);
            if (r.error) { error = r.error; return; }
            projects = r.projects;
            error = "";
        } catch (e) {}
    }
    // Cache d'abord (instantané), puis Atlas
    Process {
        id: listProc
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: win.parseList(text) }
    }
    Process {
        id: refreshProc
        command: [Paths.userBin + "/atlas-workspace", "list", "--refresh"]
        environment: ({ LC_ALL: "C" })
        onRunningChanged: win.refreshing = running
        stdout: StdioCollector { onStreamFinished: win.parseList(text) }
    }
    function reload() {
        listProc.command = [Paths.userBin + "/atlas-workspace", "list"];
        listProc.running = true;
    }

    readonly property var statusInfo: ({
        actif: { label: "Actif", color: Theme.green },
        continu: { label: "Continu", color: Theme.blue },
        a_commencer: { label: "À commencer", color: Theme.subtext },
        en_pause: { label: "En pause", color: Theme.yellow }
    })
    readonly property var statusOrder: ["actif", "continu", "a_commencer", "en_pause"]

    function norm(s) {
        return (s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    }
    // Configurés d'abord, puis par statut, puis par nom
    readonly property var results: {
        const q = norm(search.text.trim());
        return projects.filter(p => q === "" || norm(p.name).indexOf(q) >= 0)
            .sort((a, b) => (b.configured - a.configured)
                || (statusOrder.indexOf(a.status) - statusOrder.indexOf(b.status))
                || a.name.localeCompare(b.name));
    }
    function shortDir(d) { return (d ?? "").replace(/^\/home\/[^/]+/, "~"); }

    // --- Lancement --------------------------------------------------------------------
    function launch(p) {
        if (!p) return;
        if (!p.configured) { edit(p); return; }
        hide();
        Quickshell.execDetached([Paths.userBin + "/atlas-workspace", "launch", String(p.id)]);
    }

    // --- Éditeur de recette ------------------------------------------------------------
    property var editing: null      // projet en cours d'édition
    property var draft: []          // fenêtres (copie modifiable)
    readonly property var types: [
        { id: "terminal", label: "Terminal", icon: 0xf018d, color: Theme.green, field: "Commande (vide = shell)" },
        { id: "claude", label: "Claude Code", icon: 0xf06a9, color: Theme.peach, field: "Arguments (ex : --continue)" },
        { id: "browser", label: "Navigateur", icon: 0xf059f, color: Theme.blue, field: "Adresse (ex : http://localhost:3000)" },
        { id: "atlas", label: "Page Atlas", icon: 0xf0256, color: Theme.mauve, field: "" },
        { id: "app", label: "Application", icon: 0xf03d6, color: Theme.teal, field: "Commande (ex : code .)" },
        { id: "pause", label: "Pause", icon: 0xf051f, color: Theme.yellow, field: "Secondes avant la suite (ex : 3)" }
    ]
    function typeOf(id) { return types.find(t => t.id === id) ?? types[0]; }

    function edit(p) {
        editing = p;
        dirInput.text = shortDir(p.dir);
        draft = p.windows.length ? p.windows.map(w => Object.assign({}, w))
                                 : [{ type: "terminal", cmd: "" }, { type: "claude", cmd: "" }];
        dirInput.forceActiveFocus();
    }
    function closeEditor() {
        editing = null;
        search.forceActiveFocus();
    }
    function setDraft(i, key, value) {
        const d = draft.slice();
        d[i] = Object.assign({}, d[i]);
        d[i][key] = value;
        draft = d;
    }
    function addWindow(type) {
        draft = draft.concat([{ type: type, cmd: "", url: "", seconds: type === "pause" ? 3 : "" }]);
    }
    function removeWindow(i) {
        const d = draft.slice();
        d.splice(i, 1);
        draft = d;
    }
    function moveWindow(i, delta) {
        const j = i + delta;
        if (j < 0 || j >= draft.length) return;
        const d = draft.slice();
        [d[i], d[j]] = [d[j], d[i]];
        draft = d;
    }
    property bool launchAfterSave: false
    function save(andLaunch) {
        if (!editing) return;
        const windows = draft.map(w => {
            const o = { type: w.type };
            if (w.type === "browser") o.url = (w.url ?? "").trim();
            else if (w.type === "pause") o.seconds = Math.max(0, parseFloat(String(w.seconds ?? "").replace(",", ".")) || 1);
            else if (w.type !== "atlas" && (w.cmd ?? "").trim() !== "") o.cmd = w.cmd.trim();
            return o;
        }).filter(w => w.type !== "browser" || w.url);
        launchAfterSave = andLaunch;
        saveProc.command = [Paths.userBin + "/atlas-workspace", "save", String(editing.id),
                            JSON.stringify({ dir: dirInput.text.trim().replace(/^~/, Paths.home), windows: windows })];
        saveProc.running = true;
    }
    Process {
        id: saveProc
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (r.error) { win.error = r.error; return; }
                } catch (e) { win.error = "Échec de l'enregistrement"; return; }
                const p = win.editing;
                win.closeEditor();
                if (win.launchAfterSave) {
                    win.hide();
                    Quickshell.execDetached([Paths.userBin + "/atlas-workspace", "launch", String(p.id)]);
                } else win.reload();
            }
        }
    }

    // --- Interface ----------------------------------------------------------------------
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

        MouseArea { anchors.fill: parent }

        // ===== Liste des projets =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            visible: win.editing === null

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

                    BarText { text: Theme.ic(0xf0256); font.pixelSize: 18; color: Theme.mauve }
                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.labelFont
                        font.pixelSize: 15
                        clip: true
                        selectByMouse: true
                        onTextChanged: grid.currentIndex = 0
                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            event.accepted = true;
                            switch (event.key) {
                            case Qt.Key_Escape: win.hide(); break;
                            case Qt.Key_Down: grid.moveCurrentIndexDown(); break;
                            case Qt.Key_Up: grid.moveCurrentIndexUp(); break;
                            case Qt.Key_Left: grid.moveCurrentIndexLeft(); break;
                            case Qt.Key_Right: grid.moveCurrentIndexRight(); break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter: win.launch(win.results[grid.currentIndex]); break;
                            case Qt.Key_E:
                                if (ctrl && win.results[grid.currentIndex]) win.edit(win.results[grid.currentIndex]);
                                else event.accepted = false;
                                break;
                            default: event.accepted = false;
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: "Sur quel projet travailler ?"
                            color: Theme.muted
                            font: search.font
                        }
                    }
                    BarText {
                        visible: win.refreshing
                        text: Theme.ic(0xf0450)
                        color: Theme.muted
                        RotationAnimation on rotation { running: win.refreshing; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                    }
                    BarText {
                        text: win.results.length + (win.results.length > 1 ? " projets" : " projet")
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: grid
                    anchors.fill: parent
                    clip: true
                    readonly property int cols: Math.max(2, Math.floor(width / 270))
                    cellWidth: Math.floor(width / cols)
                    cellHeight: 112
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: win.results }
                    highlightMoveDuration: 150
                    highlight: Item {
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 14
                            color: Qt.rgba(1, 1, 1, 0.1)
                            border.color: Theme.border
                            border.width: 1
                        }
                    }

                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property var st: win.statusInfo[modelData.status] ?? { label: modelData.status, color: Theme.muted }
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 14
                            color: Theme.pill
                            border.color: Theme.pillBorder
                            border.width: 1
                            opacity: card.modelData.configured ? 1 : 0.6
                            scale: cardMa.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                            ClickFx { id: cardFx }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ProjectLogo { logo: card.modelData.logo; size: 26 }
                                    BarText {
                                        Layout.fillWidth: true
                                        text: card.modelData.name
                                        font.pixelSize: 14
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    // Roue dentée : éditeur de recette
                                    Rectangle {
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        radius: 8
                                        color: gearMa.containsMouse ? Theme.pillHover : "transparent"
                                        z: 2
                                        BarText { anchors.centerIn: parent; text: Theme.ic(0xf0493); color: gearMa.containsMouse ? Theme.text : Theme.muted; font.pixelSize: 15 }
                                        MouseArea {
                                            id: gearMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.edit(card.modelData)
                                        }
                                    }
                                }
                                BarText {
                                    Layout.fillWidth: true
                                    text: card.modelData.configured
                                        ? card.modelData.windows.map(w => Theme.ic(win.typeOf(w.type).icon)).join("  ")
                                          + "   " + win.shortDir(card.modelData.dir)
                                        : "Non configuré · clic pour configurer"
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                    elide: Text.ElideMiddle
                                }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: card.st.color }
                                    BarText { text: card.st.label; font.pixelSize: 11; color: card.st.color }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 4
                                        radius: 2
                                        color: Qt.rgba(1, 1, 1, 0.1)
                                        visible: card.modelData.total > 0
                                        Rectangle {
                                            width: parent.width * card.modelData.done / Math.max(1, card.modelData.total)
                                            height: parent.height
                                            radius: 2
                                            color: card.st.color
                                        }
                                    }
                                    Item { Layout.fillWidth: true; visible: card.modelData.total === 0 }
                                    BarText {
                                        visible: card.modelData.total > 0
                                        text: card.modelData.done + "/" + card.modelData.total
                                        font.pixelSize: 11
                                        color: Theme.muted
                                    }
                                }
                            }
                        }
                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            anchors.rightMargin: 44     // laisse la roue dentée
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: grid.currentIndex = card.index
                            onClicked: { cardFx.play(); win.launch(card.modelData); }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: win.results.length === 0
                    spacing: 8
                    BarText { Layout.alignment: Qt.AlignHCenter; text: Theme.ic(0xf0256); font.pixelSize: 44; color: Theme.muted }
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: win.error !== "" ? win.error : (win.refreshing ? "Chargement des projets…" : "Aucun projet")
                        color: win.error !== "" ? Theme.red : Theme.subtext
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [["Entrée", "ouvrir l'espace de travail"], ["Ctrl+E", "configurer"], ["Échap", "fermer"]]
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
                BarText { visible: win.error !== "" && win.results.length > 0; text: win.error; color: Theme.red; font.pixelSize: 11 }
            }
        }

        // ===== Éditeur de recette =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            visible: win.editing !== null

            Keys.onEscapePressed: win.closeEditor()

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 10
                    color: backMa.containsMouse ? Theme.pillHover : Theme.pill
                    BarText { anchors.centerIn: parent; text: Theme.ic(0xf004d); font.pixelSize: 16 }
                    MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.closeEditor() }
                }
                ProjectLogo { logo: win.editing?.logo ?? null; size: 32 }
                BarText {
                    Layout.fillWidth: true
                    text: win.editing?.name ?? ""
                    font.family: Theme.titleFont
                    font.pixelSize: 22
                    font.bold: true
                    elide: Text.ElideRight
                }
                BarText { text: "Espace de travail"; color: Theme.muted; font.pixelSize: 12 }
            }

            // Dossier du projet
            BarText { text: "Dossier"; color: Theme.subtext; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 10
                color: Theme.pill
                border.color: dirInput.activeFocus ? Theme.border : Theme.pillBorder
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    BarText { text: Theme.ic(0xf024b); color: Theme.yellow; font.pixelSize: 16 }
                    TextInput {
                        id: dirInput
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        clip: true
                        selectByMouse: true
                        Keys.onEscapePressed: win.closeEditor()
                        Keys.onReturnPressed: event => { if (event.modifiers & Qt.ControlModifier) win.save(true); }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: dirInput.text === ""
                            text: "~/Documents/PROJETS/…"
                            color: Theme.muted
                            font: dirInput.font
                        }
                    }
                }
            }

            BarText { text: "Étapes (dans cet ordre ; « Pause » attend avant la suivante)"; color: Theme.subtext; font.pixelSize: 12 }

            ListView {
                id: winList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: win.draft.length

                delegate: Rectangle {
                    id: row
                    required property int index
                    readonly property var w: win.draft[index] ?? {}
                    readonly property var t: win.typeOf(w.type)
                    width: winList.width
                    height: 44
                    radius: 10
                    color: Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6

                        // Type : clic pour passer au suivant (clic droit : précédent)
                        Rectangle {
                            implicitWidth: 140
                            implicitHeight: 32
                            radius: 8
                            color: typeMa.containsMouse ? Theme.pillHover : Qt.rgba(1, 1, 1, 0.06)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8
                                BarText { text: Theme.ic(row.t.icon); color: row.t.color; font.pixelSize: 15 }
                                BarText { Layout.fillWidth: true; text: row.t.label; elide: Text.ElideRight }
                                BarText { text: Theme.ic(0xf0140); color: Theme.muted; font.pixelSize: 10 }
                            }
                            MouseArea {
                                id: typeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    const i = win.types.findIndex(x => x.id === row.w.type);
                                    const d = mouse.button === Qt.RightButton ? -1 : 1;
                                    win.setDraft(row.index, "type", win.types[(i + d + win.types.length) % win.types.length].id);
                                }
                            }
                        }

                        // Commande / adresse
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.04)
                            visible: row.t.field !== ""
                            TextInput {
                                id: field
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 12
                                clip: true
                                selectByMouse: true
                                readonly property string key: row.w.type === "browser" ? "url" : row.w.type === "pause" ? "seconds" : "cmd"
                                text: String(row.w[key] ?? "")
                                onTextEdited: win.setDraft(row.index, key, text)
                                Keys.onEscapePressed: win.closeEditor()
                                Keys.onReturnPressed: event => { if (event.modifiers & Qt.ControlModifier) win.save(true); }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: field.text === ""
                                    text: row.t.field
                                    color: Theme.muted
                                    font: field.font
                                }
                            }
                        }
                        BarText {
                            Layout.fillWidth: true
                            visible: row.t.field === ""
                            text: "atlas.homelab.lan/projects/" + (win.editing?.id ?? "")
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: 12
                        }

                        Repeater {
                            model: [
                                { icon: 0xf005d, act: -1, color: Theme.subtext },
                                { icon: 0xf0045, act: 1, color: Theme.subtext },
                                { icon: 0xf0a7a, act: 0, color: Theme.red }
                            ]
                            Rectangle {
                                required property var modelData
                                implicitWidth: 30
                                implicitHeight: 30
                                radius: 8
                                color: btnMa.containsMouse ? Theme.pillHover : "transparent"
                                BarText { anchors.centerIn: parent; text: Theme.ic(modelData.icon); color: modelData.color; font.pixelSize: 15 }
                                MouseArea {
                                    id: btnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.act === 0 ? win.removeWindow(row.index) : win.moveWindow(row.index, modelData.act)
                                }
                            }
                        }
                    }
                }
            }

            // Ajout d'une fenêtre
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                BarText { text: "Ajouter :"; color: Theme.muted; font.pixelSize: 12 }
                Repeater {
                    model: win.types
                    Rectangle {
                        required property var modelData
                        implicitWidth: addRow.implicitWidth + 16
                        implicitHeight: 30
                        radius: 8
                        color: addMa.containsMouse ? Theme.pillHover : Theme.pill
                        border.color: Theme.pillBorder
                        border.width: 1
                        ClickFx { id: addFx }
                        RowLayout {
                            id: addRow
                            anchors.centerIn: parent
                            spacing: 6
                            BarText { text: Theme.ic(modelData.icon); color: modelData.color; font.pixelSize: 14 }
                            BarText { text: modelData.label; font.pixelSize: 12 }
                        }
                        MouseArea {
                            id: addMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { addFx.play(); win.addWindow(modelData.id); }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                BarText { visible: win.error !== ""; text: win.error; color: Theme.red; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: [
                        { label: "Annuler", act: "cancel", bg: Theme.pill, fg: Theme.subtext },
                        { label: "Enregistrer", act: "save", bg: Theme.pill, fg: Theme.text },
                        { label: "Enregistrer et ouvrir", act: "launch", bg: Qt.rgba(1, 1, 1, 0.9), fg: "#111111" }
                    ]
                    Rectangle {
                        required property var modelData
                        implicitWidth: actText.implicitWidth + 28
                        implicitHeight: 36
                        radius: 10
                        color: modelData.bg
                        border.color: Theme.pillBorder
                        border.width: 1
                        opacity: actMa.containsMouse ? 0.85 : 1
                        scale: actMa.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        BarText { id: actText; anchors.centerIn: parent; text: modelData.label; color: modelData.fg; font.bold: modelData.act === "launch" }
                        MouseArea {
                            id: actMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !saveProc.running
                            onClicked: {
                                if (modelData.act === "cancel") win.closeEditor();
                                else win.save(modelData.act === "launch");
                            }
                        }
                    }
                }
            }
        }
    }
}
