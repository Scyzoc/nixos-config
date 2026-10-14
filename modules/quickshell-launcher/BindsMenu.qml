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
        schemeGet.running = true;
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

    // --- Thème : suit le mode clair / sombre de l'OS (color-scheme, theme-automation.nix) --
    property bool dark: true
    Process {
        id: schemeGet
        command: [Paths.dconf, "read", "/org/gnome/desktop/interface/color-scheme"]
        stdout: StdioCollector { onStreamFinished: win.dark = text.indexOf("prefer-dark") >= 0 }
    }
    // `dconf watch` : une ligne chemin, puis une ligne valeur à chaque changement
    Process {
        id: schemeWatch
        running: true
        command: [Paths.dconf, "watch", "/org/gnome/desktop/interface/color-scheme"]
        stdout: SplitParser {
            onRead: line => { if (line.indexOf("'") >= 0) win.dark = line.indexOf("prefer-dark") >= 0; }
        }
    }
    Component.onCompleted: schemeGet.running = true

    readonly property var p: dark ? {
        panel: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.82), scrim: Qt.rgba(0, 0, 0, 0.35),
        border: Qt.rgba(1, 1, 1, 0.2), text: "#ffffff", sub: "#b4b4b4", muted: "#737373",
        pill: Qt.rgba(1, 1, 1, 0.05), pillBorder: Qt.rgba(1, 1, 1, 0.1), hover: Qt.rgba(1, 1, 1, 0.08),
        cursor: Qt.rgba(1, 1, 1, 0.16), tip: "#2e2e2e",
        mauve: Theme.mauve, green: Theme.green, red: Theme.red, blue: Theme.blue, yellow: Theme.yellow, teal: Theme.teal
    } : {
        panel: Qt.rgba(248 / 255, 248 / 255, 250 / 255, 0.88), scrim: Qt.rgba(0, 0, 0, 0.18),
        border: Qt.rgba(0, 0, 0, 0.14), text: "#1c1c1f", sub: "#55555c", muted: "#8a8a92",
        pill: Qt.rgba(0, 0, 0, 0.045), pillBorder: Qt.rgba(0, 0, 0, 0.1), hover: Qt.rgba(0, 0, 0, 0.06),
        cursor: Qt.rgba(0, 0, 0, 0.09), tip: "#2a2a2e",
        mauve: "#7c4dcc", green: "#1a7f37", red: "#cf222e", blue: "#0969da", yellow: "#9a6700", teal: "#0f766e"
    }
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

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

    // Onglets du switch : icônes seules, le nom est dans l'infobulle
    readonly property var tabs: [
        { id: "all", label: "Tous", icon: 0xf0279 },        // md-format-list-bulleted
        { id: "perso", label: "Mes raccourcis", icon: 0xf04ce },   // md-star
        { id: "apps", label: "Applications", icon: 0xf003b },      // md-apps
        { id: "fenetres", label: "Fenêtres", icon: 0xf0293 },      // md-window-maximize
        { id: "workspaces", label: "Workspaces et souris", icon: 0xf056e },   // md-view-dashboard
        { id: "media", label: "Média et système", icon: 0xf0387 },  // md-music-note
        { id: "conflit", label: "Conflits", icon: 0xf0026 },        // md-alert
        { id: "off", label: "Désactivés", icon: 0xf0209 }           // md-eye-off
    ]
    readonly property var shownTabs: tabs.filter(t => t.id !== "conflit" || conflicts > 0)
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
        { id: "exec", label: "Lancer une commande", icon: 0xf018d },    // md-console
        { id: "lua", label: "Action Hyprland (Lua)", icon: 0xf08b1 }    // md-language-lua
    ]
    readonly property var flagOpts: [
        { id: "locked", label: "Actif écran verrouillé", icon: 0xf033e },        // md-lock
        { id: "repeating", label: "Répétition tant que la touche est tenue", icon: 0xf0456 },   // md-repeat
        { id: "release", label: "Déclenché au relâchement", icon: 0xf01da }      // md-eject
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
        color: win.p.scrim
        opacity: win.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: win.hide() }
    }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.1)
        width: Math.min(860, parent.width - 80)
        // Hauteur du contenu (plafonnée) : pas de vide sous une liste courte
        height: Math.min(parent.height * 0.8, Math.max(180, body.implicitHeight + 28))
        radius: 18
        color: win.p.panel
        border.color: win.p.border
        border.width: 1
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 200 } }

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }    // le clic dans le panneau ne ferme pas

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // ===== En-tête : titre, switch des sections (icônes), recherche, actions =====
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                z: 5

                Txt { text: Theme.ic(0xf030c); font.pixelSize: 22; color: win.p.mauve }    // md-keyboard
                Txt {
                    text: win.mode === "edit" ? (win.editing ? "Modifier le raccourci" : "Nouveau raccourci") : "Raccourcis"
                    font.family: Theme.titleFont
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                // Switch : le curseur glisse d'une section à l'autre
                Rectangle {
                    id: seg
                    visible: win.mode === "list"
                    readonly property int cell: 34
                    readonly property int idx: Math.max(0, win.shownTabs.findIndex(t => t.id === win.tab))
                    implicitWidth: cell * win.shownTabs.length + 6
                    implicitHeight: 34
                    radius: 11
                    color: win.p.pill
                    border.color: win.p.pillBorder
                    border.width: 1
                    z: 5

                    Rectangle {
                        x: 3 + seg.idx * seg.cell
                        y: 3
                        width: seg.cell
                        height: parent.height - 6
                        radius: 8
                        color: win.p.cursor
                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        x: 3
                        y: 3
                        Repeater {
                            model: win.shownTabs
                            Item {
                                id: cellItem
                                required property var modelData
                                readonly property bool current: win.tab === modelData.id
                                readonly property color tone: modelData.id === "conflit" ? win.p.yellow
                                                              : (modelData.id === "off" ? win.p.red : win.p.mauve)
                                width: seg.cell
                                height: seg.height - 6
                                z: cellMa.containsMouse ? 10 : 0
                                Txt {
                                    anchors.centerIn: parent
                                    text: Theme.ic(cellItem.modelData.icon)
                                    font.pixelSize: 17
                                    color: cellItem.current || cellMa.containsMouse ? cellItem.tone
                                           : (cellItem.modelData.id === "conflit" ? win.p.yellow : win.p.muted)
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                                MouseArea {
                                    id: cellMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { win.tab = cellItem.modelData.id; search.forceActiveFocus(); }
                                }
                                Tip {
                                    text: cellItem.modelData.label + (cellItem.modelData.id === "all" ? " · " + win.all.length
                                          : (cellItem.modelData.id === "conflit" ? " · " + win.conflicts : ""))
                                    shown: cellMa.containsMouse
                                }
                            }
                        }
                    }
                }

                // Recherche
                Rectangle {
                    Layout.fillWidth: true
                    visible: win.mode === "list"
                    implicitHeight: 34
                    radius: 11
                    color: win.p.pill
                    border.color: search.text !== "" ? win.tint(win.p.mauve, 0.55) : win.p.pillBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        Txt { text: Theme.ic(0xf0349); font.pixelSize: 16; color: win.p.sub }    // md-magnify
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: win.p.text
                            font.family: Theme.labelFont
                            font.pixelSize: 13
                            clip: true
                            selectByMouse: true
                            selectionColor: win.tint(win.p.mauve, 0.4)
                            selectedTextColor: win.p.text
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
                                text: "Touche, action, commande…"
                                color: win.p.muted
                                font: search.font
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true; visible: win.mode === "edit" }

                Btn {
                    visible: win.mode === "list"
                    icon: 0xf0415    // md-plus
                    tip: "Nouveau raccourci (Ctrl+N)"
                    accent: win.p.mauve
                    onClicked: win.openEdit(null)
                }
                Btn {
                    icon: 0xf0156    // md-close
                    tip: win.mode === "edit" ? "Retour" : "Fermer"
                    onClicked: win.mode === "edit" ? win.closeEdit() : win.hide()
                }
            }

            // Erreur
            Rectangle {
                Layout.fillWidth: true
                visible: win.error !== ""
                implicitHeight: errText.implicitHeight + 14
                radius: 10
                color: win.tint(win.p.red, 0.13)
                border.color: win.tint(win.p.red, 0.4)
                border.width: 1
                Txt {
                    id: errText
                    anchors.fill: parent
                    anchors.margins: 7
                    text: Theme.ic(0xf0026) + "  " + win.error    // md-alert
                    color: win.p.red
                    font.pixelSize: 12
                    font.family: Theme.labelFont
                    wrapMode: Text.Wrap
                }
            }

            // ===== Liste =====
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(60, contentHeight)
                Layout.fillHeight: true
                visible: win.mode === "list"
                clip: true
                spacing: 1
                model: win.rows
                boundsBehavior: Flickable.StopAtBounds

                Txt {
                    anchors.centerIn: parent
                    visible: win.rows.length === 0
                    text: "Aucun raccourci"
                    color: win.p.muted
                    font.family: Theme.labelFont
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var b: modelData.bind ?? null
                    readonly property bool isSel: index === win.sel
                    width: list.width
                    height: b ? 38 : 24

                    // Titre de section
                    Txt {
                        visible: !row.b
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        text: (modelData.header ?? "").toUpperCase()
                        font.pixelSize: 10
                        font.letterSpacing: 1.2
                        font.family: Theme.labelFont
                        color: win.p.muted
                    }

                    Rectangle {
                        visible: !!row.b
                        anchors.fill: parent
                        radius: 9
                        color: row.isSel ? win.p.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: win.sel = row.index
                            onDoubleClicked: win.openEdit(row.b)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            KeyCaps {
                                Layout.preferredWidth: 196
                                keys: row.b?.pretty ?? ""
                                opacity: row.b?.enabled ? 1 : 0.45
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                opacity: row.b?.enabled ? 1 : 0.45
                                Txt {
                                    Layout.fillWidth: true
                                    text: row.b?.label ?? ""
                                    elide: Text.ElideRight
                                    font.family: Theme.labelFont
                                    font.pixelSize: 13
                                    font.strikeout: !row.b?.enabled
                                }
                                Txt {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: row.b?.desc && row.b?.kind === "exec" ? row.b.cmd
                                          : (row.b?.source === "custom" && row.b?.kind === "lua" ? row.b.lua : "")
                                    elide: Text.ElideRight
                                    font.pixelSize: 10
                                    color: win.p.muted
                                }
                            }

                            // Étiquettes
                            Txt {    // actif écran verrouillé
                                visible: (row.b?.flags ?? []).includes("locked")
                                text: Theme.ic(0xf033e)
                                font.pixelSize: 13
                                color: win.p.teal
                            }
                            Badge {
                                visible: row.b?.conflict ?? false
                                text: "Conflit"
                                tone: win.p.yellow
                            }
                            Badge {
                                visible: (row.b?.replaces ?? "") !== ""
                                text: "Remplace " + (row.b?.replacesPretty ?? "")
                                tone: win.p.blue
                            }
                            Badge {
                                visible: row.b?.source === "custom" && !row.b?.replaces
                                text: "Perso"
                                tone: win.p.mauve
                            }
                            Badge {
                                visible: !(row.b?.enabled ?? true)
                                text: "Désactivé"
                                tone: win.p.muted
                            }

                            // Actions (ligne choisie)
                            RowLayout {
                                spacing: 3
                                opacity: row.isSel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                Btn {
                                    icon: 0xf03eb    // md-pencil
                                    tip: "Modifier"
                                    small: true
                                    onClicked: win.openEdit(row.b)
                                }
                                Btn {    // désactiver / réactiver (défauts)
                                    visible: row.b?.source === "default"
                                    icon: row.b?.enabled ? 0xf0209 : 0xf054c    // md-eye-off / md-undo
                                    tip: row.b?.enabled ? "Désactiver" : "Réactiver"
                                    small: true
                                    accent: row.b?.enabled ? win.p.red : win.p.green
                                    onClicked: win.flip(row.b)
                                }
                                Btn {    // supprimer (perso) ; si remplacement, restaure l'original
                                    visible: row.b?.source === "custom"
                                    icon: row.b?.replaces ? 0xf054c : 0xf01b4    // md-undo / md-delete
                                    tip: row.b?.replaces ? "Restaurer l'original" : "Supprimer"
                                    small: true
                                    accent: row.b?.replaces ? win.p.green : win.p.red
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
                visible: win.mode === "list"
                spacing: 12
                Repeater {
                    model: [["↑ ↓", "choisir"], ["Entrée", "modifier"], ["Espace", "(dés)activer"], ["Suppr", "supprimer"], ["Échap", "fermer"]]
                    RowLayout {
                        required property var modelData
                        spacing: 5
                        Rectangle {
                            implicitWidth: hintKey.implicitWidth + 10
                            implicitHeight: 17
                            radius: 5
                            color: win.p.pill
                            border.color: win.p.pillBorder
                            border.width: 1
                            Txt { id: hintKey; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 10; color: win.p.sub }
                        }
                        Txt { text: modelData[1]; font.pixelSize: 11; color: win.p.muted }
                    }
                }
                Item { Layout.fillWidth: true }
                Txt {
                    visible: win.all.some(b => b.source === "custom" || !b.enabled)
                    text: "Tout réinitialiser"
                    font.pixelSize: 11
                    font.family: Theme.labelFont
                    color: resetMa.containsMouse ? win.p.red : win.p.muted
                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.call(["reset"])
                    }
                }
            }

            // ===== Formulaire =====
            // Bind de la config Nix : l'enregistrer le remplace
            Rectangle {
                Layout.fillWidth: true
                visible: win.mode === "edit" && win.editing?.source === "default"
                implicitHeight: noteText.implicitHeight + 14
                radius: 10
                color: win.tint(win.p.blue, 0.11)
                border.color: win.tint(win.p.blue, 0.35)
                border.width: 1
                Txt {
                    id: noteText
                    anchors.fill: parent
                    anchors.margins: 7
                    text: "Raccourci de la config Nix : l'enregistrer le remplace par ta version (restaurable depuis la liste)."
                    color: win.p.blue
                    font.pixelSize: 12
                    font.family: Theme.labelFont
                    wrapMode: Text.Wrap
                }
            }

            // Combinaison : aperçu en touches, saisie manuelle, bouton de capture
            Rectangle {
                Layout.fillWidth: true
                visible: win.mode === "edit"
                implicitHeight: 46
                radius: 11
                color: win.capturing ? win.tint(win.p.mauve, 0.1) : win.p.pill
                border.color: win.capturing ? win.p.mauve : (fKeys.activeFocus ? win.p.sub : win.p.pillBorder)
                border.width: win.capturing ? 2 : 1
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 10

                    KeyCaps {
                        visible: !win.capturing && fKeys.text.trim() !== ""
                        keys: win.fKeysPretty
                    }
                    Txt {
                        visible: win.capturing
                        text: "Appuie sur la combinaison…  (Échap : annuler)"
                        color: win.p.mauve
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
                        color: win.p.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        selectionColor: win.tint(win.p.mauve, 0.4)
                        selectedTextColor: win.p.text
                        Keys.onTabPressed: fValue.focusInput()
                        Keys.onEscapePressed: win.closeEdit()
                        Keys.onReturnPressed: fValue.focusInput()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: fKeys.text === ""
                            text: "Saisie manuelle : SUPER + SHIFT + K"
                            color: win.p.muted
                            font: fKeys.font
                        }
                    }
                    Item { Layout.fillWidth: true; visible: win.capturing }
                    Btn {
                        icon: 0xf030c    // md-keyboard
                        text: win.capturing ? "" : "Capturer"
                        tip: win.capturing ? "Annuler la capture" : ""
                        accent: win.p.mauve
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
            Txt {
                visible: win.mode === "edit" && win.clash !== null
                text: Theme.ic(0xf0026) + "  Déjà utilisé par « " + (win.clash?.label ?? "") + " » : les deux s'exécuteraient"    // md-alert
                color: win.p.yellow
                font.pixelSize: 11
                font.family: Theme.labelFont
            }

            // Action : type (icônes) + commande
            RowLayout {
                Layout.fillWidth: true
                visible: win.mode === "edit"
                spacing: 8
                Rectangle {
                    implicitWidth: 34 * win.kindOpts.length + 6
                    implicitHeight: 36
                    radius: 11
                    color: win.p.pill
                    border.color: win.p.pillBorder
                    border.width: 1
                    z: 5
                    Rectangle {
                        x: 3 + Math.max(0, win.kindOpts.findIndex(k => k.id === win.fKind)) * 34
                        y: 3
                        width: 34
                        height: parent.height - 6
                        radius: 8
                        color: win.p.cursor
                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        x: 3
                        y: 3
                        Repeater {
                            model: win.kindOpts
                            Item {
                                id: kindItem
                                required property var modelData
                                width: 34
                                height: 30
                                z: kindMa.containsMouse ? 10 : 0
                                Txt {
                                    anchors.centerIn: parent
                                    text: Theme.ic(kindItem.modelData.icon)
                                    font.pixelSize: 17
                                    color: win.fKind === kindItem.modelData.id || kindMa.containsMouse ? win.p.mauve : win.p.muted
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                                MouseArea {
                                    id: kindMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.fKind = kindItem.modelData.id
                                }
                                Tip { text: kindItem.modelData.label; shown: kindMa.containsMouse }
                            }
                        }
                    }
                }
                Field {
                    id: fValue
                    placeholder: win.fKind === "exec" ? "Commande : kitty --class btop -e btop" : "Expression Lua : hl.dsp.window.close()"
                    mono: true
                    next: fDesc
                    onAccepted: win.save()
                }
            }

            // Description + options (icônes)
            RowLayout {
                Layout.fillWidth: true
                visible: win.mode === "edit"
                spacing: 8
                Field {
                    id: fDesc
                    placeholder: "Description (facultatif) : Moniteur système"
                    next: fKeys
                    onAccepted: win.save()
                }
                Repeater {
                    model: win.flagOpts
                    Rectangle {
                        id: flagBtn
                        required property var modelData
                        readonly property bool on: win.fFlags.includes(modelData.id)
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 11
                        z: flagMa.containsMouse ? 10 : 0
                        color: on ? win.tint(win.p.teal, 0.18) : (flagMa.containsMouse ? win.p.hover : win.p.pill)
                        border.color: on ? win.tint(win.p.teal, 0.55) : win.p.pillBorder
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Txt {
                            anchors.centerIn: parent
                            text: Theme.ic(flagBtn.modelData.icon)
                            font.pixelSize: 17
                            color: flagBtn.on ? win.p.teal : win.p.muted
                        }
                        MouseArea {
                            id: flagMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.toggleFlag(flagBtn.modelData.id)
                        }
                        Tip { text: flagBtn.modelData.label; shown: flagMa.containsMouse }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: win.mode === "edit"
                spacing: 8
                Item { Layout.fillWidth: true }
                Btn { text: "Annuler"; onClicked: win.closeEdit() }
                Btn {
                    icon: 0xf012c    // md-check
                    text: win.saving ? "Application…" : "Enregistrer"
                    accent: win.p.green
                    enabled: !win.saving && fKeys.text.trim() !== "" && fValue.text.trim() !== ""
                    onClicked: win.save()
                }
            }
        }
    }

    readonly property string fKeysPretty: {
        const s = fKeys.text.trim();
        if (s === "") return "";
        const mods = ["SUPER", "CTRL", "ALT", "SHIFT"];
        return s.split(/\s*\+\s*/).map(k => mods.includes(k.toUpperCase()) ? k.toUpperCase() : k).join(" + ");
    }

    // --- Composants ---------------------------------------------------------------------
    component Txt: Text {
        color: win.p.text
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        verticalAlignment: Text.AlignVCenter
    }

    // Infobulle sous le composant parent
    component Tip: Rectangle {
        property string text: ""
        property bool shown: false
        visible: shown && text !== ""
        z: 100
        anchors.top: parent.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: tipText.implicitWidth + 14
        implicitHeight: 22
        radius: 7
        color: win.p.tip
        Txt { id: tipText; anchors.centerIn: parent; text: parent.text; font.pixelSize: 11; font.family: Theme.labelFont; color: "#ffffff" }
    }

    // Combinaison dessinée en touches
    component KeyCaps: Row {
        property string keys: ""
        spacing: 3
        Repeater {
            model: parent.keys === "" ? [] : parent.keys.split(" + ")
            Rectangle {
                required property string modelData
                readonly property bool isMod: ["SUPER", "CTRL", "ALT", "SHIFT"].includes(modelData)
                implicitWidth: Math.max(24, capText.implicitWidth + 12)
                implicitHeight: 24
                radius: 6
                color: isMod ? win.tint(win.p.mauve, 0.16) : win.p.pill
                border.color: isMod ? win.tint(win.p.mauve, 0.4) : win.p.border
                border.width: 1
                Txt {
                    id: capText
                    anchors.centerIn: parent
                    text: win.dispNames[modelData] ?? modelData.replace(/^XF86/, "")
                    font.pixelSize: 11
                    font.family: Theme.labelFont
                    color: parent.isMod ? win.p.mauve : win.p.text
                }
            }
        }
    }

    component Badge: Rectangle {
        property string text: ""
        property color tone: win.p.sub
        implicitWidth: badgeText.implicitWidth + 12
        implicitHeight: 18
        radius: 9
        color: win.tint(tone, 0.14)
        border.color: win.tint(tone, 0.4)
        border.width: 1
        Txt {
            id: badgeText
            anchors.centerIn: parent
            text: parent.text
            font.pixelSize: 10
            font.family: Theme.labelFont
            color: parent.tone
        }
    }

    // Bouton : icône et / ou texte, infobulle facultative
    component Btn: Rectangle {
        id: btn
        property int icon: 0
        property string text: ""
        property string tip: ""
        property color accent: win.p.sub
        property bool small: false
        signal clicked()
        implicitWidth: btnRow.implicitWidth + (text !== "" ? 22 : (small ? 14 : 18))
        implicitHeight: small ? 26 : 34
        radius: small ? 8 : 11
        opacity: enabled ? 1 : 0.4
        z: btnMa.containsMouse ? 10 : 0
        color: btnMa.containsMouse ? win.tint(accent, 0.2) : win.p.pill
        border.color: btnMa.containsMouse ? win.tint(accent, 0.5) : win.p.pillBorder
        border.width: 1
        scale: btnMa.pressed ? 0.93 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            Txt {
                visible: btn.icon !== 0
                text: btn.icon ? Theme.ic(btn.icon) : ""
                font.pixelSize: btn.small ? 14 : 17
                color: btnMa.containsMouse ? btn.accent : win.p.sub
            }
            Txt {
                visible: btn.text !== ""
                text: btn.text
                font.pixelSize: 12
                font.family: Theme.labelFont
                color: btnMa.containsMouse ? win.p.text : win.p.sub
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
        Tip { text: btn.tip; shown: btnMa.containsMouse }
    }

    // Champ de texte du formulaire
    component Field: Rectangle {
        id: fld
        property string placeholder: ""
        property bool mono: false
        property var next: null
        property alias text: inp.text
        signal accepted()
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 11
        color: win.p.pill
        border.color: inp.activeFocus ? win.p.sub : win.p.pillBorder
        border.width: 1
        function focusInput() { inp.forceActiveFocus(); }
        TextInput {
            id: inp
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: win.p.text
            font.family: fld.mono ? Theme.font : Theme.labelFont
            font.pixelSize: 13
            clip: true
            selectByMouse: true
            selectionColor: win.tint(win.p.mauve, 0.4)
            selectedTextColor: win.p.text
            onAccepted: fld.accepted()
            Keys.onEscapePressed: win.closeEdit()
            Keys.onTabPressed: if (fld.next) fld.next.focusInput()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                elide: Text.ElideRight
                visible: inp.text === ""
                text: fld.placeholder
                color: win.p.muted
                font: inp.font
            }
        }
    }
}
