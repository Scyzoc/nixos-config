import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Raccourcis Hyprland (SUPER+F1) : tous les binds (config Nix + les tiens), recherche,
// filtres, ajout / modification / désactivation / suppression. Backend `binds`
// (modules/binds.nix, assets/binds.py) : les changements sont appliqués à chaud et
// gardés dans ~/.local/state/binds/user.json, sans toucher aux .nix.
// Liste : ↑ ↓ choisir, Entrée modifier, Espace activer / désactiver, Suppr supprimer,
// Ctrl+N nouveau, Échap fermer. Formulaire : le bouton clavier capture une combinaison
// (submap vide le temps de la capture, sinon Hyprland exécuterait le bind).
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-binds"
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
        search.text = "";
        tab = "all";
        mode = "list";
        error = "";
        sel = 0;
        reload();
        closeTimer.stop();
        visible = true;
        open = true;
        search.forceActiveFocus();
    }
    function hide() {
        stopCapture();
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Données -----------------------------------------------------------------
    property var all: []
    property string error: ""
    property string tab: "all"
    property string mode: "list"    // "list" | "edit"
    property bool saving: false

    readonly property string bin: Paths.userBin + "/binds"
    function call(args) {
        if (proc.running) return;
        proc.command = [bin].concat(args);
        proc.running = true;
    }
    function reload() { call(["list"]); }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.all = d.binds;
                    win.error = d.error ?? "";
                    if (win.saving && !d.error) win.closeEdit();
                } catch (e) {
                    win.error = "Réponse de `binds` illisible";
                }
                win.saving = false;
            }
        }
    }
    Process { id: capProc }
    function startCapture() {
        capProc.command = [bin, "capture", "start"];
        capProc.running = true;
        capturing = true;
        capture.forceActiveFocus();
    }
    function stopCapture() {
        if (!capturing) return;
        capturing = false;
        Quickshell.execDetached([bin, "capture", "stop"]);
    }

    readonly property var tabs: [
        { id: "all", label: "Tous" },
        { id: "perso", label: "Perso" },
        { id: "apps", label: "Applications" },
        { id: "fenetres", label: "Fenêtres" },
        { id: "workspaces", label: "Workspaces" },
        { id: "media", label: "Média" },
        { id: "conflit", label: "Conflits" },
        { id: "off", label: "Désactivés" }
    ]
    readonly property var catOrder: ["perso", "apps", "fenetres", "workspaces", "media"]
    readonly property var catNames: ({
        perso: "Mes raccourcis", apps: "Applications", fenetres: "Fenêtres",
        workspaces: "Workspaces et souris", media: "Média et système"
    })
    readonly property int conflicts: all.filter(b => b.conflict).length

    function plain(s) { return (s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }

    // Liste affichée : titres de section intercalés ({ header }), binds filtrés
    readonly property var rows: {
        const q = plain(search.text).trim();
        const hits = all.filter(b => {
            if (tab === "conflit") { if (!b.conflict) return false; }
            else if (tab === "off") { if (b.enabled) return false; }
            else if (tab !== "all" && b.cat !== tab) return false;
            if (q === "") return true;
            return plain(b.pretty + " " + b.label + " " + b.cmd + " " + b.desc + " " + keyDisp(b.pretty)).includes(q);
        });
        hits.sort((a, b) => catOrder.indexOf(a.cat) - catOrder.indexOf(b.cat) || a.label.localeCompare(b.label, "fr", { numeric: true }));
        const out = [];
        let last = "";
        for (const b of hits) {
            if (b.cat !== last) {
                out.push({ header: catNames[b.cat] ?? b.cat });
                last = b.cat;
            }
            out.push({ bind: b });
        }
        return out;
    }
    property int sel: 0
    onRowsChanged: {
        if (sel >= rows.length || rows[sel]?.header !== undefined) sel = firstBind(0, 1);
    }
    function firstBind(from, d) {
        for (let i = from; i >= 0 && i < rows.length; i += d)
            if (rows[i].bind) return i;
        return Math.max(0, Math.min(from, rows.length - 1));
    }
    function move(d) {
        const i = firstBind(sel + d, d);
        if (rows[i]?.bind) sel = i;
        list.positionViewAtIndex(sel, ListView.Contain);
    }
    readonly property var current: rows[sel]?.bind ?? null

    // --- Noms de touches ----------------------------------------------------------------
    readonly property var dispNames: ({
        SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Maj", left: "←", right: "→", up: "↑", down: "↓",
        semicolon: ";", comma: ",", period: ".", colon: ":", slash: "/", backslash: "\\", Space: "Espace",
        Return: "Entrée", Escape: "Échap", BackSpace: "⌫", Delete: "Suppr", Prior: "Page ↑", Next: "Page ↓",
        mouse_down: "Molette ↓", mouse_up: "Molette ↑", "mouse:272": "Clic gauche", "mouse:273": "Clic droit",
        ampersand: "&", eacute: "é", quotedbl: "\"", apostrophe: "'", parenleft: "(", parenright: ")",
        minus: "-", egrave: "è", underscore: "_", ccedilla: "ç", agrave: "à", equal: "=", plus: "+",
        asterisk: "*", dollar: "$", ugrave: "ù", exclam: "!", less: "<", greater: ">", question: "?",
        twosuperior: "²", asciicircum: "^", numbersign: "#", at: "@", percent: "%",
        XF86AudioRaiseVolume: "Vol +", XF86AudioLowerVolume: "Vol −", XF86AudioMute: "Muet",
        XF86AudioMicMute: "Micro", XF86MonBrightnessUp: "Lum +", XF86MonBrightnessDown: "Lum −",
        XF86AudioNext: "Suivant", XF86AudioPrev: "Précédent", XF86AudioPlay: "Lecture", XF86AudioPause: "Pause"
    })
    function keyDisp(keys) {
        return keys.split(" + ").map(k => dispNames[k] ?? k.replace(/^XF86/, "")).join(" ");
    }
    function normKeys(s) {
        const order = ["SUPER", "CTRL", "ALT", "SHIFT"];
        const alias = { WIN: "SUPER", MOD4: "SUPER", META: "SUPER", CONTROL: "CTRL", MOD1: "ALT" };
        const parts = s.split(/[+,]/).map(p => p.trim()).filter(p => p !== "");
        const mods = [];
        let key = "";
        parts.forEach((p, i) => {
            const m = alias[p.toUpperCase()] ?? p.toUpperCase();
            if (order.includes(m) && i < parts.length - 1) { if (!mods.includes(m)) mods.push(m); }
            else key = p.toLowerCase();
        });
        mods.sort((a, b) => order.indexOf(a) - order.indexOf(b));
        return mods.concat([key]).join(" + ");
    }

    // Capture : touche pressée → nom Hyprland
    readonly property var specials: ({
        [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab",
        [Qt.Key_Space]: "Space", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete",
        [Qt.Key_Insert]: "Insert", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End",
        [Qt.Key_PageUp]: "Prior", [Qt.Key_PageDown]: "Next", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right",
        [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Print]: "Print", [Qt.Key_Pause]: "Pause",
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute", [Qt.Key_MicMute]: "XF86AudioMicMute",
        [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp", [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown",
        [Qt.Key_MediaPlay]: "XF86AudioPlay", [Qt.Key_MediaPause]: "XF86AudioPause",
        [Qt.Key_MediaNext]: "XF86AudioNext", [Qt.Key_MediaPrevious]: "XF86AudioPrev"
    })
    readonly property var charNames: ({
        "&": "ampersand", "é": "eacute", "\"": "quotedbl", "'": "apostrophe", "(": "parenleft", ")": "parenright",
        "-": "minus", "è": "egrave", "_": "underscore", "ç": "ccedilla", "à": "agrave", "=": "equal",
        ";": "semicolon", ":": "colon", "!": "exclam", ",": "comma", ".": "period", "$": "dollar",
        "ù": "ugrave", "*": "asterisk", "^": "asciicircum", "<": "less", ">": "greater", "²": "twosuperior",
        "/": "slash", "?": "question", "#": "numbersign", "@": "at", "%": "percent", "+": "plus",
        "\\": "backslash", "[": "bracketleft", "]": "bracketright", "{": "braceleft", "}": "braceright",
        "~": "asciitilde", "`": "grave", "|": "bar"
    })
    // Rangée des chiffres en AZERTY (codes xkb 10 à 19) : avec Maj, Qt donne le chiffre,
    // Hyprland veut la touche sans Maj
    readonly property var numRow: ["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft", "minus", "egrave", "underscore", "ccedilla", "agrave"]
    function keyName(ev) {
        const k = ev.key;
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35) return "F" + (k - Qt.Key_F1 + 1);
        if (specials[k]) return specials[k];
        const code = ev.nativeScanCode;
        if (ev.modifiers & Qt.ShiftModifier)
            return code >= 10 && code <= 19 ? numRow[code - 10] : "code:" + code;
        if (k > 0x1f && k < 0x01000000) {
            const c = String.fromCodePoint(k).toLowerCase();
            return charNames[c] ?? c;
        }
        return "";
    }
    readonly property var modKeys: [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Shift,
                                    Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Hyper_L, Qt.Key_Hyper_R, Qt.Key_CapsLock]

    // --- Formulaire -----------------------------------------------------------------------
    property var editing: null      // bind modifié (null : nouveau)
    property string fKind: "exec"
    property var fFlags: []
    property bool capturing: false
    readonly property var kindOpts: [
        { id: "exec", label: "Lancer une commande" },
        { id: "lua", label: "Action Hyprland (Lua)" }
    ]
    readonly property var flagOpts: [
        { id: "locked", label: "Écran verrouillé", tip: "marche aussi quand la session est verrouillée" },
        { id: "repeating", label: "Répétition", tip: "se répète tant que la touche est tenue" },
        { id: "release", label: "Au relâchement", tip: "se déclenche quand on lâche la touche" }
    ]
    readonly property var clash: {
        const n = normKeys(fKeys.text);
        if (n === "" || n.endsWith(" + ") ) return null;
        return all.find(b => b.enabled && b.norm.toLowerCase() === n.toLowerCase() && b.id !== editing?.id
                             && b.id !== editing?.replaces && b.replaces !== editing?.id) ?? null;
    }

    function openEdit(b) {
        editing = b;
        mode = "edit";
        error = "";
        fKeys.text = b ? b.keys : "";
        fKind = b ? b.kind : "exec";
        fValue.text = b ? (b.source === "custom" ? b.value : (b.kind === "exec" ? b.cmd : b.lua)) : "";
        fDesc.text = b ? b.desc : "";
        fFlags = b ? b.flags.slice() : [];
        if (b) fValue.focusInput();
        else {
            fKeys.forceActiveFocus();
            startCapture();
        }
    }
    function closeEdit() {
        stopCapture();
        mode = "list";
        search.forceActiveFocus();
    }
    function toggleFlag(f) {
        fFlags = fFlags.includes(f) ? fFlags.filter(x => x !== f) : fFlags.concat([f]);
    }
    function save() {
        if (saving) return;
        const data = JSON.stringify({
            keys: fKeys.text.trim(), kind: fKind, value: fValue.text.trim(),
            desc: fDesc.text.trim(), flags: fFlags
        });
        saving = true;
        stopCapture();
        call(editing ? ["update", editing.id, data] : ["add", data]);
    }
    function remove(b) { call(["delete", b.id]); }
    function flip(b) { call(["toggle", b.id]); }

    // --- Interface -----------------------------------------------------------------------
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
        width: Math.min(900, parent.width - 80)
        height: Math.min(700, parent.height - 100)
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
            anchors.margins: 18
            spacing: 12

            // En-tête
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                BarText { text: Theme.ic(0xf030c); font.pixelSize: 24; color: Theme.mauve }    // md-keyboard
                BarText {
                    text: win.mode === "edit" ? (win.editing ? "Modifier le raccourci" : "Nouveau raccourci") : "Raccourcis"
                    font.family: Theme.titleFont
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                BarText {
                    visible: win.mode === "list"
                    text: win.all.length + " binds"
                    color: Theme.muted
                    font.pixelSize: 12
                    font.family: Theme.labelFont
                }
                Item { Layout.fillWidth: true }
                Btn {
                    visible: win.mode === "list"
                    icon: 0xf0415    // md-plus
                    text: "Nouveau"
                    accent: Theme.mauve
                    onClicked: win.openEdit(null)
                }
                Btn {
                    icon: 0xf0156    // md-close
                    onClicked: win.mode === "edit" ? win.closeEdit() : win.hide()
                }
            }

            // Erreur
            Rectangle {
                Layout.fillWidth: true
                visible: win.error !== ""
                implicitHeight: errText.implicitHeight + 16
                radius: 10
                color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.14)
                border.color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.4)
                border.width: 1
                BarText {
                    id: errText
                    anchors.fill: parent
                    anchors.margins: 8
                    text: Theme.ic(0xf0026) + "  " + win.error    // md-alert
                    color: Theme.red
                    font.pixelSize: 12
                    font.family: Theme.labelFont
                    wrapMode: Text.Wrap
                }
            }

            // ===== Liste =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.mode === "list"
                spacing: 10

                // Recherche
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 12
                    color: Theme.pill
                    border.color: search.text !== "" ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.5) : Theme.pillBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10
                        BarText { text: Theme.ic(0xf0349); font.pixelSize: 17; color: Theme.subtext }    // md-magnify
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            font.family: Theme.labelFont
                            font.pixelSize: 14
                            clip: true
                            selectByMouse: true
                            Keys.onPressed: event => {
                                event.accepted = true;
                                const ctrl = event.modifiers & Qt.ControlModifier;
                                switch (event.key) {
                                case Qt.Key_Escape: win.hide(); break;
                                case Qt.Key_Down: win.move(1); break;
                                case Qt.Key_Up: win.move(-1); break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter: if (win.current) win.openEdit(win.current); break;
                                case Qt.Key_Delete:
                                    if (win.current?.source === "custom") win.remove(win.current);
                                    else event.accepted = false;
                                    break;
                                case Qt.Key_N:
                                    if (ctrl) win.openEdit(null);
                                    else event.accepted = false;
                                    break;
                                case Qt.Key_Space:
                                    if (search.text === "" && win.current && win.current.source === "default") win.flip(win.current);
                                    else event.accepted = false;
                                    break;
                                default: event.accepted = false;
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: search.text === ""
                                text: "Chercher une touche, une action, une commande…"
                                color: Theme.muted
                                font: search.font
                            }
                        }
                    }
                }

                // Filtres
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: win.tabs.filter(t => (t.id !== "conflit" || win.conflicts > 0))
                        Rectangle {
                            required property var modelData
                            readonly property bool on: win.tab === modelData.id
                            implicitWidth: chipText.implicitWidth + 22
                            implicitHeight: 28
                            radius: 14
                            color: on ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.22)
                                      : (chipMa.containsMouse ? Theme.rowHover : "transparent")
                            border.color: on ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.6) : Theme.pillBorder
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            BarText {
                                id: chipText
                                anchors.centerIn: parent
                                text: modelData.label + (modelData.id === "conflit" ? " (" + win.conflicts + ")" : "")
                                font.pixelSize: 12
                                font.family: Theme.labelFont
                                color: parent.on ? Theme.text : (modelData.id === "conflit" ? Theme.yellow : Theme.subtext)
                            }
                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { win.tab = modelData.id; search.forceActiveFocus(); }
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: win.rows
                    boundsBehavior: Flickable.StopAtBounds

                    BarText {
                        anchors.centerIn: parent
                        visible: win.rows.length === 0
                        text: "Aucun raccourci"
                        color: Theme.muted
                        font.family: Theme.labelFont
                    }

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property var b: modelData.bind ?? null
                        readonly property bool isSel: index === win.sel
                        width: list.width
                        height: b ? 46 : 30

                        // Titre de section
                        BarText {
                            visible: !row.b
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: (modelData.header ?? "").toUpperCase()
                            font.pixelSize: 10
                            font.letterSpacing: 1.2
                            font.family: Theme.labelFont
                            color: Theme.muted
                        }

                        Rectangle {
                            visible: !!row.b
                            anchors.fill: parent
                            radius: 10
                            color: row.isSel ? Theme.rowHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: win.sel = row.index
                                onDoubleClicked: win.openEdit(row.b)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12
                                opacity: row.b?.enabled ? 1 : 0.45

                                KeyCaps {
                                    Layout.preferredWidth: 270
                                    keys: row.b?.pretty ?? ""
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    BarText {
                                        Layout.fillWidth: true
                                        text: row.b?.label ?? ""
                                        elide: Text.ElideRight
                                        font.family: Theme.labelFont
                                        font.pixelSize: 13
                                        font.strikeout: !row.b?.enabled
                                    }
                                    BarText {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: row.b?.desc && row.b?.kind === "exec" ? row.b.cmd
                                              : (row.b?.source === "custom" && row.b?.kind === "lua" ? row.b.lua : "")
                                        elide: Text.ElideRight
                                        font.pixelSize: 10
                                        color: Theme.muted
                                    }
                                }

                                // Étiquettes
                                Badge {
                                    visible: row.b?.conflict ?? false
                                    text: "Conflit"
                                    tint: Theme.yellow
                                }
                                Badge {
                                    visible: (row.b?.replaces ?? "") !== ""
                                    text: "Remplace " + (row.b?.replacesPretty ?? "")
                                    tint: Theme.blue
                                }
                                Badge {
                                    visible: row.b?.source === "custom" && !row.b?.replaces
                                    text: "Perso"
                                    tint: Theme.mauve
                                }
                                Badge {
                                    visible: !(row.b?.enabled ?? true)
                                    text: "Désactivé"
                                    tint: Theme.muted
                                }
                                Badge {
                                    visible: (row.b?.flags ?? []).includes("locked")
                                    text: "Verrouillé OK"
                                    tint: Theme.teal
                                }

                                // Actions
                                RowLayout {
                                    spacing: 4
                                    opacity: row.isSel ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    Btn {
                                        icon: 0xf03eb    // md-pencil
                                        small: true
                                        onClicked: win.openEdit(row.b)
                                    }
                                    Btn {    // désactiver / réactiver (défauts)
                                        visible: row.b?.source === "default"
                                        icon: row.b?.enabled ? 0xf0156 : 0xf054c    // md-close / md-undo
                                        small: true
                                        accent: row.b?.enabled ? Theme.red : Theme.green
                                        onClicked: win.flip(row.b)
                                    }
                                    Btn {    // supprimer (perso) ; si remplacement, restaure l'original
                                        visible: row.b?.source === "custom"
                                        icon: row.b?.replaces ? 0xf054c : 0xf01b4    // md-undo / md-delete
                                        small: true
                                        accent: row.b?.replaces ? Theme.green : Theme.red
                                        onClicked: win.remove(row.b)
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
                        model: [["↑ ↓", "choisir"], ["Entrée", "modifier"], ["Espace", "(dés)activer"], ["Suppr", "supprimer"], ["Ctrl+N", "nouveau"], ["Échap", "fermer"]]
                        RowLayout {
                            required property var modelData
                            spacing: 6
                            Rectangle {
                                implicitWidth: hintKey.implicitWidth + 10
                                implicitHeight: 18
                                radius: 5
                                color: Theme.pill
                                border.color: Theme.pillBorder
                                border.width: 1
                                BarText { id: hintKey; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 10; color: Theme.subtext }
                            }
                            BarText { text: modelData[1]; font.pixelSize: 11; color: Theme.muted }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    BarText {
                        visible: win.all.some(b => b.source === "custom" || !b.enabled)
                        text: "Tout réinitialiser"
                        font.pixelSize: 11
                        font.family: Theme.labelFont
                        color: resetMa.containsMouse ? Theme.red : Theme.muted
                        MouseArea {
                            id: resetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.call(["reset"])
                        }
                    }
                }
            }

            // ===== Formulaire =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.mode === "edit"
                spacing: 14

                // Bind de la config Nix : l'enregistrer le remplace
                Rectangle {
                    Layout.fillWidth: true
                    visible: win.editing?.source === "default"
                    implicitHeight: noteText.implicitHeight + 16
                    radius: 10
                    color: Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.12)
                    border.color: Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.35)
                    border.width: 1
                    BarText {
                        id: noteText
                        anchors.fill: parent
                        anchors.margins: 8
                        text: "Ce raccourci vient de la config Nix : l'enregistrer le remplace par ta version (restaurable depuis la liste)."
                        color: Theme.blue
                        font.pixelSize: 12
                        font.family: Theme.labelFont
                        wrapMode: Text.Wrap
                    }
                }

                // Combinaison
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    BarText { text: "Combinaison"; color: Theme.subtext; font.pixelSize: 11; font.family: Theme.labelFont }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 12
                        color: win.capturing ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.1) : Theme.pill
                        border.color: win.capturing ? Theme.mauve : (fKeys.activeFocus ? Theme.subtext : Theme.pillBorder)
                        border.width: win.capturing ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 12

                            // Aperçu en touches
                            KeyCaps {
                                Layout.preferredWidth: 270
                                visible: !win.capturing && fKeys.text.trim() !== ""
                                keys: win.fKeysPretty
                            }
                            BarText {
                                visible: win.capturing
                                text: "Appuie sur la combinaison…  (Échap : annuler)"
                                color: Theme.mauve
                                font.family: Theme.labelFont
                                font.pixelSize: 13
                                SequentialAnimation on opacity {
                                    running: win.capturing
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.45; duration: 700 }
                                    NumberAnimation { to: 1; duration: 700 }
                                }
                            }
                            // Saisie manuelle (« SUPER + SHIFT + K ») et recours si la capture ne passe pas
                            TextInput {
                                id: fKeys
                                Layout.fillWidth: true
                                visible: !win.capturing
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 12
                                clip: true
                                selectByMouse: true
                                Keys.onTabPressed: fValue.focusInput()
                                Keys.onEscapePressed: win.closeEdit()
                                Keys.onReturnPressed: fValue.focusInput()
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: fKeys.text === ""
                                    text: "ou saisie manuelle : SUPER + SHIFT + K"
                                    color: Theme.muted
                                    font: fKeys.font
                                }
                            }
                            Item { Layout.fillWidth: true; visible: win.capturing }
                            Btn {
                                icon: 0xf030c    // md-keyboard
                                text: win.capturing ? "" : "Capturer"
                                accent: Theme.mauve
                                onClicked: win.capturing ? win.stopCapture() : win.startCapture()
                            }
                        }

                        // Récepteur de touches pendant la capture
                        FocusScope {
                            id: capture
                            anchors.fill: parent
                            focus: true
                            Keys.onPressed: event => {
                                event.accepted = true;
                                if (!win.capturing) return;
                                if (win.modKeys.includes(event.key)) return;
                                const mods = event.modifiers;
                                if (event.key === Qt.Key_Escape && !(mods & ~Qt.KeypadModifier)) {
                                    win.stopCapture();
                                    fKeys.forceActiveFocus();
                                    return;
                                }
                                const name = win.keyName(event);
                                if (name === "") return;
                                const parts = [];
                                if (mods & Qt.MetaModifier) parts.push("SUPER");
                                if (mods & Qt.ControlModifier) parts.push("CTRL");
                                if (mods & Qt.AltModifier) parts.push("ALT");
                                if (mods & Qt.ShiftModifier) parts.push("SHIFT");
                                fKeys.text = parts.concat([name]).join(" + ");
                                win.stopCapture();
                                fValue.focusInput();
                            }
                        }
                    }
                    BarText {
                        visible: win.clash !== null
                        text: Theme.ic(0xf0026) + "  Déjà utilisé par « " + (win.clash?.label ?? "") + " » : les deux s'exécuteraient"    // md-alert
                        color: Theme.yellow
                        font.pixelSize: 11
                        font.family: Theme.labelFont
                    }
                }

                // Type d'action
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: win.kindOpts
                        Rectangle {
                            required property var modelData
                            readonly property bool on: win.fKind === modelData.id
                            implicitWidth: kindText.implicitWidth + 28
                            implicitHeight: 32
                            radius: 16
                            color: on ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.22) : (kindMa.containsMouse ? Theme.rowHover : "transparent")
                            border.color: on ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.6) : Theme.pillBorder
                            border.width: 1
                            BarText {
                                id: kindText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 12
                                font.family: Theme.labelFont
                                color: parent.on ? Theme.text : Theme.subtext
                            }
                            MouseArea {
                                id: kindMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.fKind = modelData.id
                            }
                        }
                    }
                }

                Field2 {
                    id: fValue
                    label: win.fKind === "exec" ? "Commande" : "Expression Lua"
                    placeholder: win.fKind === "exec" ? "ex : kitty --class btop -e btop" : "ex : hl.dsp.window.close()"
                    mono: true
                    next: fDesc
                    onAccepted: win.save()
                }
                Field2 {
                    id: fDesc
                    label: "Description (facultatif)"
                    placeholder: "ex : Moniteur système"
                    next: fKeys
                    onAccepted: win.save()
                }

                // Options
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: win.flagOpts
                        Rectangle {
                            required property var modelData
                            readonly property bool on: win.fFlags.includes(modelData.id)
                            implicitWidth: flagText.implicitWidth + 32
                            implicitHeight: 30
                            radius: 15
                            color: on ? Qt.rgba(Theme.teal.r, Theme.teal.g, Theme.teal.b, 0.18) : (flagMa.containsMouse ? Theme.rowHover : "transparent")
                            border.color: on ? Qt.rgba(Theme.teal.r, Theme.teal.g, Theme.teal.b, 0.55) : Theme.pillBorder
                            border.width: 1
                            BarText {
                                id: flagText
                                anchors.centerIn: parent
                                text: (parent.on ? Theme.ic(0xf012c) + "  " : "") + modelData.label    // md-check
                                font.pixelSize: 12
                                font.family: Theme.labelFont
                                color: parent.on ? Theme.teal : Theme.subtext
                            }
                            MouseArea {
                                id: flagMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.toggleFlag(modelData.id)
                            }
                        }
                    }
                    BarText {
                        text: "Options du bind"
                        color: Theme.muted
                        font.pixelSize: 11
                        font.family: Theme.labelFont
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    Btn { text: "Annuler"; onClicked: win.closeEdit() }
                    Btn {
                        icon: 0xf012c    // md-check
                        text: win.saving ? "Application…" : "Enregistrer"
                        accent: Theme.green
                        enabled: !win.saving && fKeys.text.trim() !== "" && fValue.text.trim() !== ""
                        onClicked: win.save()
                    }
                }
            }
        }
    }

    readonly property string fKeysPretty: {
        const s = fKeys.text.trim();
        if (s === "") return "";
        return s.split(/\s*\+\s*/).map(k => (k.toUpperCase() === "SUPER" || k.toUpperCase() === "CTRL" || k.toUpperCase() === "ALT" || k.toUpperCase() === "SHIFT") ? k.toUpperCase() : k).join(" + ");
    }

    // --- Composants ---------------------------------------------------------------------
    // Combinaison dessinée en touches
    component KeyCaps: Row {
        property string keys: ""
        spacing: 4
        Repeater {
            model: parent.keys === "" ? [] : parent.keys.split(" + ")
            Rectangle {
                required property string modelData
                readonly property bool isMod: ["SUPER", "CTRL", "ALT", "SHIFT"].includes(modelData)
                implicitWidth: Math.max(26, capText.implicitWidth + 14)
                implicitHeight: 26
                radius: 7
                color: isMod ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.16) : Theme.pill
                border.color: isMod ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.4) : Theme.border
                border.width: 1
                BarText {
                    id: capText
                    anchors.centerIn: parent
                    text: win.dispNames[modelData] ?? modelData.replace(/^XF86/, "")
                    font.pixelSize: 11
                    font.family: Theme.labelFont
                    color: parent.isMod ? Theme.mauve : Theme.text
                }
            }
        }
    }

    component Badge: Rectangle {
        property string text: ""
        property color tint: Theme.subtext
        implicitWidth: badgeText.implicitWidth + 14
        implicitHeight: 20
        radius: 10
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.14)
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.4)
        border.width: 1
        BarText {
            id: badgeText
            anchors.centerIn: parent
            text: parent.text
            font.pixelSize: 10
            font.family: Theme.labelFont
            color: parent.tint
        }
    }

    // Bouton : icône et / ou texte
    component Btn: Rectangle {
        id: btn
        property int icon: 0
        property string text: ""
        property color accent: Theme.subtext
        property bool small: false
        signal clicked()
        implicitWidth: btnRow.implicitWidth + (small ? 14 : 22)
        implicitHeight: small ? 28 : 34
        radius: 10
        opacity: enabled ? 1 : 0.4
        color: btnMa.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.22) : Theme.pill
        border.color: btnMa.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.5) : Theme.pillBorder
        border.width: 1
        scale: btnMa.pressed ? 0.93 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            BarText {
                visible: btn.icon !== 0
                text: btn.icon ? Theme.ic(btn.icon) : ""
                font.pixelSize: btn.small ? 15 : 17
                color: btnMa.containsMouse ? btn.accent : Theme.subtext
            }
            BarText {
                visible: btn.text !== ""
                text: btn.text
                font.pixelSize: 12
                font.family: Theme.labelFont
                color: btnMa.containsMouse ? Theme.text : Theme.subtext
            }
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // Champ de texte du formulaire
    component Field2: ColumnLayout {
        id: fld
        property string label: ""
        property string placeholder: ""
        property bool mono: false
        property var next: null
        property alias text: inp.text
        signal accepted()
        Layout.fillWidth: true
        spacing: 5
        function focusInput() { inp.forceActiveFocus(); }
        BarText { text: fld.label; color: Theme.subtext; font.pixelSize: 11; font.family: Theme.labelFont }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: 10
            color: Theme.pill
            border.color: inp.activeFocus ? Theme.subtext : Theme.pillBorder
            border.width: 1
            TextInput {
                id: inp
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: fld.mono ? Theme.font : Theme.labelFont
                font.pixelSize: 13
                clip: true
                selectByMouse: true
                onAccepted: fld.accepted()
                Keys.onEscapePressed: win.closeEdit()
                Keys.onTabPressed: if (fld.next) fld.next.focusInput()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: inp.text === ""
                    text: fld.placeholder
                    color: Theme.muted
                    font: inp.font
                }
            }
        }
    }
}
