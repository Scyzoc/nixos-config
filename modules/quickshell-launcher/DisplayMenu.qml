import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Menu des écrans (SUPER+P), en trois onglets : affichage (carte live des écrans et modes
// PC / externe / miroir / étendu), réglages de l'écran sélectionné (résolution, fréquence,
// échelle, on/off) et dispositions enregistrées (nom, groupes de workspaces). Les données viennent de `display-state` (JSON), les actions
// passent par `display-apply` (modules/display-switch.nix) qui pose le verrou anti-boucle.
// Touches : ← → onglets, 1-4 modes, Tab écran suivant, Échap fermer.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-display"
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
        closeTimer.stop();
        visible = true;
        open = true;
        tab = 0;
        pos = 0;
        confirmDel = false;
        refresh();
        keys.forceActiveFocus();
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Données -----------------------------------------------------------------
    property var monitors: []
    property var layouts: []
    property string mode: ""
    property string selected: ""    // nom du connecteur sélectionné
    property int tab: 0             // 0 affichage, 1 réglages, 2 dispositions
    property real pos: tab          // position animée (transitions entre onglets)
    Behavior on pos { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
    property string selLayout: ""   // signature (nom de fichier) de la disposition éditée
    property bool confirmDel: false
    readonly property var layout: layouts.find(l => l.file === selLayout) ?? null

    readonly property var externals: monitors.filter(m => m.name !== "eDP-1")
    readonly property bool hasExternal: externals.length > 0
    readonly property var liveMons: monitors.filter(m => !m.disabled)
    readonly property var sel: monitors.find(m => m.name === selected) ?? null
    // Mode effectif : les restaurations de disposition comptent comme étendu / externe
    readonly property string curMode: {
        if (mode === "restore-layout") return "extend";
        if (mode === "restore-layout-external" || mode === "lid-closed") return "external-only";
        return mode;
    }

    Process {
        id: stateProc
        command: [Paths.userBin + "/display-state"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.monitors = d.monitors;
                    win.layouts = d.layouts;
                    win.mode = d.mode;
                    if (!d.layouts.some(l => l.file === win.selLayout))
                        win.selLayout = (d.layouts.find(l => l.current) ?? d.layouts[0])?.file ?? "";
                    if (!d.monitors.some(m => m.name === win.selected))
                        win.selected = (d.monitors.find(m => !m.disabled) ?? d.monitors[0])?.name ?? "";
                } catch (e) {}
            }
        }
    }
    function refresh() { if (!stateProc.running) stateProc.running = true; }

    // Les actions déclenchent un `sleep 1` côté script : on relit l'état après
    Timer { id: later; interval: 1700; onTriggered: win.refresh() }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (win.open && (ev.name === "monitoraddedv2" || ev.name === "monitorremoved"))
                later.restart();
        }
    }

    // Édition d'une disposition (display-layout-edit) puis relecture rapide
    Timer { id: quick; interval: 500; onTriggered: win.refresh() }
    function edit(...args) {
        Quickshell.execDetached([Paths.userBin + "/display-layout-edit", ...args]);
        quick.restart();
    }
    Timer { id: confirmTimer; interval: 3000; onTriggered: win.confirmDel = false }

    function apply(...args) {
        Quickshell.execDetached([Paths.userBin + "/display-apply", ...args]);
        later.restart();
    }
    function setMode(m) {
        if (m !== "pc-only" && !hasExternal) return;
        apply(m);
    }
    function nextMonitor() {
        if (monitors.length === 0) return;
        const i = monitors.findIndex(m => m.name === selected);
        selected = monitors[(i + 1) % monitors.length].name;
    }

    // Règle "WxH@RR,XxY,scale" pour l'écran sélectionné avec des valeurs modifiées
    function setRule(m, res, hz, scale) {
        apply("set-mon", m.name, res + "@" + hz + "," + m.x + "x" + m.y + "," + scale);
    }
    function modeRes(s) { return s.split("@")[0]; }
    function modeHz(s) { return s.split("@")[1].replace("Hz", ""); }
    // Résolutions distinctes (ordre d'Hyprland = décroissant) / fréquences d'une résolution
    function resolutions(m) {
        const out = [];
        for (const s of m.availableModes) {
            const r = modeRes(s);
            if (!out.includes(r)) out.push(r);
        }
        return out.slice(0, 8);
    }
    function rates(m, res) {
        const out = [];
        for (const s of m.availableModes)
            if (modeRes(s) === res) {
                const h = Math.round(parseFloat(modeHz(s)));
                if (!out.some(o => o.n === h)) out.push({ n: h, raw: modeHz(s) });
            }
        return out;
    }
    function shortDesc(d) {
        // "Vendor Model 0x1234" → on retire le suffixe hexadécimal
        return (d ?? "").replace(/\s+0x[0-9A-Fa-f]+$/, "");
    }

    readonly property var modes: [
        { id: "pc-only", label: "PC uniquement", sub: "Écran interne seul", icon: 0xf0322, color: Theme.blue, ext: false },
        { id: "external-only", label: "Externe uniquement", sub: "Écrans externes seuls", icon: 0xf037a, color: Theme.teal, ext: true },
        { id: "mirror", label: "Miroir", sub: "Même image partout", icon: 0xf0191, color: Theme.peach, ext: true },
        { id: "extend", label: "Étendu", sub: "Bureau sur tous les écrans", icon: 0xf0293, color: Theme.mauve, ext: true }
    ]

    // --- Interface -------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: win.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: win.hide() }
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            event.accepted = true;
            switch (event.key) {
            case Qt.Key_Escape: win.hide(); break;
            case Qt.Key_Left: win.tab = Math.max(0, win.tab - 1); break;
            case Qt.Key_Right: win.tab = Math.min(2, win.tab + 1); break;
            case Qt.Key_Tab: win.nextMonitor(); break;
            case Qt.Key_1: win.setMode("pc-only"); break;
            case Qt.Key_2: win.setMode("external-only"); break;
            case Qt.Key_3: win.setMode("mirror"); break;
            case Qt.Key_4: win.setMode("extend"); break;
            default: event.accepted = false;
            }
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(760, parent.width - 80)
        height: 500
        radius: 20
        color: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.88)
        border.color: Theme.border
        border.width: 1

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }    // le clic dans le panneau ne ferme pas

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // --- Barre d'onglets : icônes, pastille qui glisse sous l'onglet actif ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    id: tabBar
                    implicitWidth: 3 * 56 + 8
                    implicitHeight: 44
                    radius: 22
                    color: Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1

                    // Pastille mobile, suit `pos` (donc fluide, même si on change vite d'onglet)
                    Rectangle {
                        x: 4 + win.pos * 56
                        y: 4
                        width: 56
                        height: 36
                        radius: 18
                        color: Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.25)
                        border.color: Theme.mauve
                        border.width: 1
                    }
                    Repeater {
                        model: [0xf0379, 0xf0493, 0xf056e]    // moniteur, réglages, dispositions
                        Item {
                            required property int modelData
                            required property int index
                            x: 4 + index * 56
                            y: 4
                            width: 56
                            height: 36
                            readonly property real near: Math.max(0, 1 - Math.abs(win.pos - index))
                            BarText {
                                anchors.centerIn: parent
                                text: Theme.ic(modelData)
                                font.pixelSize: 19
                                color: Theme.lerpColor(Theme.subtext, Theme.mauve, near)
                                scale: 1 + 0.15 * near
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.tab = index
                            }
                        }
                    }
                }

                BarText {
                    text: win.liveMons.length + "  " + Theme.ic(0xf0379)
                    font.pixelSize: 13
                    color: Theme.muted
                }
                Item { Layout.fillWidth: true }
                Chip {
                    glyph: 0xf0493    // md-cog : nwg-displays
                    label: ""
                    onClicked: { win.hide(); Quickshell.execDetached([Paths.nwgDisplays]); }
                }
            }

            // --- Pages : fondu + glissement selon `pos` ---
            Item {
                id: host
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Page 0 : affichage
                Item {
                    id: page0
                    readonly property real d: 0 - win.pos
                    width: host.width
                    height: host.height
                    x: d * 70
                    opacity: Math.max(0, 1 - Math.abs(d) * 1.6)
                    visible: opacity > 0.01
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 16
            // --- Carte des écrans ---
            Rectangle {
                id: map
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: Theme.pill
                border.color: Theme.pillBorder
                border.width: 1
                clip: true

                // Boîte englobante des écrans actifs (taille logique = pixels / échelle)
                readonly property var bbox: {
                    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
                    for (const m of win.liveMons) {
                        const w = m.width / m.scale, h = m.height / m.scale;
                        x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y);
                        x1 = Math.max(x1, m.x + w); y1 = Math.max(y1, m.y + h);
                    }
                    return win.liveMons.length ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : { x: 0, y: 0, w: 1, h: 1 };
                }
                readonly property real k: Math.min((width - 60) / bbox.w, (height - 44) / bbox.h)
                readonly property real offX: (width - bbox.w * k) / 2
                readonly property real offY: (height - bbox.h * k) / 2

                BarText {
                    anchors.centerIn: parent
                    visible: win.liveMons.length === 0
                    text: "Aucun écran actif"
                    color: Theme.muted
                }

                Repeater {
                    model: win.liveMons
                    Rectangle {
                        required property var modelData
                        readonly property bool isSel: modelData.name === win.selected
                        readonly property bool mirrored: modelData.mirrorOf !== "none"
                        // Un écran en miroir est décalé pour rester visible sous sa source
                        x: map.offX + (modelData.x - map.bbox.x) * map.k + (mirrored ? 10 : 0)
                        y: map.offY + (modelData.y - map.bbox.y) * map.k + (mirrored ? 10 : 0)
                        width: modelData.width / modelData.scale * map.k
                        height: modelData.height / modelData.scale * map.k
                        radius: 8
                        color: isSel ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.22) : Qt.rgba(1, 1, 1, 0.07)
                        border.color: isSel ? Theme.mauve : Theme.border
                        border.width: isSel ? 2 : 1
                        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Theme.ic(modelData.name === "eDP-1" ? 0xf0322 : 0xf0379)
                                font.pixelSize: 18
                                color: isSel ? Theme.mauve : Theme.subtext
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.name === "eDP-1" ? "PC" : modelData.name
                                font.pixelSize: 12
                                color: Theme.text
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.width + "×" + modelData.height + " · " + Math.round(modelData.refreshRate) + " Hz"
                                font.pixelSize: 10
                                color: Theme.subtext
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: mirrored
                                text: "miroir de " + modelData.mirrorOf
                                font.pixelSize: 10
                                color: Theme.peach
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.selected = modelData.name
                        }
                    }
                }
            }

            // --- Modes ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Repeater {
                    model: win.modes
                    Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool enabled: !modelData.ext || win.hasExternal
                        readonly property bool current: win.curMode === modelData.id
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 84
                        radius: 14
                        opacity: enabled ? 1 : 0.35
                        color: current ? Qt.rgba(modelData.color.r, modelData.color.g, modelData.color.b, 0.18)
                                       : (ma.containsMouse && enabled ? Theme.pillHover : Theme.pill)
                        border.color: current ? modelData.color : Theme.pillBorder
                        border.width: current ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: ma.pressed && enabled ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Theme.ic(modelData.icon)
                                font.pixelSize: 28
                                color: modelData.color
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                font.pixelSize: 13
                                color: Theme.text
                            }
                        }
                        // Raccourci clavier
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            implicitWidth: 18
                            implicitHeight: 18
                            radius: 5
                            color: Theme.pill
                            border.color: Theme.pillBorder
                            border.width: 1
                            BarText { anchors.centerIn: parent; text: card.index + 1; font.pixelSize: 10; color: Theme.subtext }
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: card.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: win.setMode(modelData.id)
                        }
                    }
                }
            }

                    }
                }

                // Page 1 : réglages
                Item {
                    id: page1
                    readonly property real d: 1 - win.pos
                    width: host.width
                    height: host.height
                    x: d * 70
                    opacity: Math.max(0, 1 - Math.abs(d) * 1.6)
                    visible: opacity > 0.01
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 14
                        // Écran à régler
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: win.monitors
                                Chip {
                                    required property var modelData
                                    label: modelData.name === "eDP-1" ? "PC" : modelData.name
                                    glyph: modelData.name === "eDP-1" ? 0xf0322 : 0xf0379
                                    active: modelData.name === win.selected
                                    opacity: modelData.disabled ? 0.5 : 1
                                    onClicked: win.selected = modelData.name
                                }
                            }
                        }

                        // Activer / désactiver (écrans externes)
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.sel !== null && win.sel.name !== "eDP-1"
                            Chip {
                                glyph: 0xf0425    // md-power
                                label: win.sel && win.sel.disabled ? "On" : "Off"
                                accent: win.sel && win.sel.disabled ? Theme.green : Theme.red
                                active: true
                                onClicked: win.apply("set-mon", win.sel.name,
                                                     win.sel.disabled ? "preferred,auto,1" : "disable")
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // Résolution
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.sel !== null && !win.sel.disabled
                            spacing: 10
                            BarText { text: Theme.ic(0xf0293); font.pixelSize: 20; color: Theme.mauve; Layout.preferredWidth: 28 }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: win.sel && !win.sel.disabled ? win.resolutions(win.sel) : []
                                    Chip {
                                        required property string modelData
                                        readonly property string curRes: win.sel.width + "x" + win.sel.height
                                        label: modelData
                                        active: modelData === curRes
                                        onClicked: {
                                            const r = win.rates(win.sel, modelData);
                                            win.setRule(win.sel, modelData, r.length ? r[0].raw : Math.round(win.sel.refreshRate), win.sel.scale);
                                        }
                                    }
                                }
                            }
                        }

                        // Fréquence
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.sel !== null && !win.sel.disabled
                            spacing: 10
                            BarText { text: Theme.ic(0xf04c5); font.pixelSize: 20; color: Theme.teal; Layout.preferredWidth: 28 }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: win.sel && !win.sel.disabled ? win.rates(win.sel, win.sel.width + "x" + win.sel.height) : []
                                    Chip {
                                        required property var modelData
                                        label: modelData.n + " Hz"
                                        accent: Theme.teal
                                        active: Math.round(win.sel.refreshRate) === modelData.n
                                        onClicked: win.setRule(win.sel, win.sel.width + "x" + win.sel.height, modelData.raw, win.sel.scale)
                                    }
                                }
                            }
                        }

                        // Échelle
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.sel !== null && !win.sel.disabled
                            spacing: 10
                            BarText { text: Theme.ic(0xf0349); font.pixelSize: 20; color: Theme.peach; Layout.preferredWidth: 28 }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [1, 1.25, 1.5, 1.75, 2]
                                    Chip {
                                        required property real modelData
                                        label: Math.round(modelData * 100) + " %"
                                        accent: Theme.peach
                                        active: win.sel && Math.abs(win.sel.scale - modelData) < 0.01
                                        onClicked: win.setRule(win.sel, win.sel.width + "x" + win.sel.height, Math.round(win.sel.refreshRate), modelData)
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // Page 2 : dispositions
                Item {
                    id: page2
                    readonly property real d: 2 - win.pos
                    width: host.width
                    height: host.height
                    x: d * 70
                    opacity: Math.max(0, 1 - Math.abs(d) * 1.6)
                    visible: opacity > 0.01
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 14
                        // Barre d'actions : enregistrer l'état actuel, appliquer, supprimer
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            Chip {
                                visible: win.hasExternal
                                glyph: 0xf0193    // md-content-save
                                label: ""
                                accent: Theme.blue
                                onClicked: win.apply("save-layout")
                            }
                            Chip {
                                visible: win.layout !== null && win.layout.current
                                glyph: 0xf0e1e    // md-check
                                label: ""
                                accent: Theme.green
                                onClicked: win.apply("restore-layout")
                            }
                            Chip {
                                visible: win.layout !== null
                                glyph: win.confirmDel ? 0xf0e1e : 0xf01b4    // md-check / md-delete
                                label: ""
                                accent: Theme.red
                                active: win.confirmDel
                                onClicked: {
                                    if (!win.confirmDel) { win.confirmDel = true; confirmTimer.restart(); return; }
                                    win.confirmDel = false;
                                    win.edit("delete", win.layout.file);
                                }
                            }
                        }

                        // Dispositions enregistrées
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: win.layouts
                                Chip {
                                    required property var modelData
                                    label: modelData.name
                                    maxLabel: 300
                                    glyph: modelData.current ? 0xf0e1e : 0xf056e
                                    active: modelData.file === win.selLayout
                                    onClicked: { win.selLayout = modelData.file; win.confirmDel = false; }
                                }
                            }
                        }
                        BarText {
                            visible: win.layouts.length === 0
                            Layout.alignment: Qt.AlignHCenter
                            text: Theme.ic(0xf056e)
                            font.pixelSize: 40
                            color: Theme.muted
                        }

                        // Nom
                        Field {
                            Layout.fillWidth: true
                            visible: win.layout !== null
                            glyph: 0xf0455    // md-pencil
                            placeholder: "…"
                            value: win.layout ? win.layout.name : ""
                            onSubmitted: t => win.edit("rename", win.layout.file, t)
                        }

                        // Groupes de workspaces (vide = auto)
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.layout !== null
                            BarText { text: Theme.ic(0xf056e); font.pixelSize: 16; color: Theme.mauve }
                            Item { Layout.fillWidth: true }
                            Chip {
                                glyph: 0xf0450    // md-refresh : tout en auto
                                label: "auto"
                                onClicked: win.edit("reset-groups", win.layout.file)
                            }
                        }
                        Field {
                            Layout.fillWidth: true
                            visible: win.layout !== null
                            glyph: 0xf0322
                            placeholder: "auto"
                            value: win.layout ? win.layout.internal : ""
                            onSubmitted: t => win.edit("groups", win.layout.file, "internal", t)
                        }
                        Repeater {
                            model: win.layout ? win.layout.monitors : []
                            Field {
                                required property var modelData
                                Layout.fillWidth: true
                                glyph: 0xf0379
                                prefix: win.shortDesc(modelData.description)
                                placeholder: "auto"
                                value: modelData.workspaces
                                onSubmitted: t => win.edit("groups", win.layout.file, modelData.description, t)
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // Champ de saisie : Entrée ou perte du focus enregistre ; Échap rend le focus aux raccourcis
    component Field: Rectangle {
        id: fld
        property string value: ""
        property string placeholder: ""
        property string prefix: ""
        property int glyph: 0
        signal submitted(string text)
        implicitHeight: 34
        radius: 10
        color: Theme.pill
        border.color: inp.activeFocus ? Theme.mauve : Theme.pillBorder
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 150 } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8
            BarText {
                visible: fld.glyph !== 0
                text: Theme.ic(fld.glyph)
                font.pixelSize: 14
                color: Theme.subtext
            }
            BarText {
                visible: fld.prefix !== ""
                text: fld.prefix
                font.pixelSize: 11
                color: Theme.subtext
                elide: Text.ElideRight
                Layout.preferredWidth: 300
            }
            TextInput {
                id: inp
                Layout.fillWidth: true
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 12
                clip: true
                selectByMouse: true
                text: fld.value
                onAccepted: { fld.submitted(text); keys.forceActiveFocus(); }
                onActiveFocusChanged: if (!activeFocus && text !== fld.value) fld.submitted(text)
                Keys.onEscapePressed: { text = fld.value; keys.forceActiveFocus(); }
                BarText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: inp.text === ""
                    text: fld.placeholder
                    font.pixelSize: 12
                    color: Theme.muted
                }
            }
        }
    }

    // Bouton compact réutilisé par les rangées de réglages
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property int glyph: 0
        property bool active: false
        property color accent: Theme.mauve
        property int maxLabel: 9999
        signal clicked()
        implicitWidth: chipRow.implicitWidth + 20
        implicitHeight: 28
        radius: 14
        opacity: enabled ? 1 : 0.55
        color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.22) : (cma.containsMouse ? Theme.pillHover : "transparent")
        border.color: active ? accent : Theme.pillBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: cma.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            BarText {
                visible: chip.glyph !== 0
                text: Theme.ic(chip.glyph)
                font.pixelSize: 13
                color: chip.active ? chip.accent : Theme.subtext
            }
            BarText {
                text: chip.label
                elide: Text.ElideRight
                Layout.maximumWidth: chip.maxLabel
                font.pixelSize: 11
                color: chip.active || cma.containsMouse ? Theme.text : Theme.subtext
            }
        }
        MouseArea {
            id: cma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
}
