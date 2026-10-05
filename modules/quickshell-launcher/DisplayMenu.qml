import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Menu des écrans (SUPER+P) : carte live des écrans, modes (PC / externe / miroir /
// étendu), réglages de l'écran sélectionné (résolution, fréquence, échelle, on/off) et
// dispositions enregistrées. Les données viennent de `display-state` (JSON), les actions
// passent par `display-apply` (modules/display-switch.nix) qui pose le verrou anti-boucle.
// Touches : 1-4 modes, Tab écran suivant, Échap fermer.
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
        width: Math.min(780, parent.width - 80)
        height: content.implicitHeight + 40
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
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 16

            // --- En-tête ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                BarText { text: Theme.ic(0xf0379); font.pixelSize: 22; color: Theme.mauve }    // md-monitor
                BarText { text: "Affichage"; font.family: Theme.titleFont; font.pixelSize: 20; color: Theme.text }
                BarText {
                    text: win.liveMons.length + (win.liveMons.length > 1 ? " écrans actifs" : " écran actif")
                    font.pixelSize: 12
                    color: Theme.muted
                    Layout.leftMargin: 6
                }
                Item { Layout.fillWidth: true }
                Chip {
                    label: "Avancé"
                    glyph: 0xf0493    // md-cog
                    onClicked: { win.hide(); Quickshell.execDetached([Paths.nwgDisplays]); }
                }
            }

            // --- Carte des écrans ---
            Rectangle {
                id: map
                Layout.fillWidth: true
                implicitHeight: 190
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
                        implicitHeight: 92
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
                                font.pixelSize: 24
                                color: modelData.color
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                font.pixelSize: 13
                                color: Theme.text
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.sub
                                font.pixelSize: 10
                                color: Theme.muted
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

            // --- Réglages de l'écran sélectionné ---
            Rectangle {
                Layout.fillWidth: true
                visible: win.sel !== null
                implicitHeight: detail.implicitHeight + 24
                radius: 14
                color: Theme.pill
                border.color: Theme.pillBorder
                border.width: 1

                ColumnLayout {
                    id: detail
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        BarText {
                            text: win.sel ? win.sel.name + " — " + win.shortDesc(win.sel.description) : ""
                            font.pixelSize: 13
                            color: Theme.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        // Activer / désactiver un écran externe
                        Chip {
                            visible: win.sel !== null && win.sel.name !== "eDP-1"
                            label: win.sel && win.sel.disabled ? "Activer" : "Désactiver"
                            glyph: 0xf0425    // md-power
                            accent: win.sel && win.sel.disabled ? Theme.green : Theme.red
                            onClicked: win.apply("set-mon", win.sel.name,
                                                 win.sel.disabled ? "preferred,auto,1" : "disable")
                        }
                    }

                    // Résolution
                    RowLayout {
                        Layout.fillWidth: true
                        visible: win.sel !== null && !win.sel.disabled
                        spacing: 8
                        BarText { text: "Résolution"; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 80 }
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
                        spacing: 8
                        BarText { text: "Fréquence"; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 80 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: win.sel && !win.sel.disabled ? win.rates(win.sel, win.sel.width + "x" + win.sel.height) : []
                                Chip {
                                    required property var modelData
                                    label: modelData.n + " Hz"
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
                        spacing: 8
                        BarText { text: "Échelle"; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 80 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [1, 1.25, 1.5, 1.75, 2]
                                Chip {
                                    required property real modelData
                                    label: Math.round(modelData * 100) + " %"
                                    active: win.sel && Math.abs(win.sel.scale - modelData) < 0.01
                                    onClicked: win.setRule(win.sel, win.sel.width + "x" + win.sel.height, Math.round(win.sel.refreshRate), modelData)
                                }
                            }
                        }
                    }

                    // Sélecteur d'écran (si plusieurs, y compris désactivés)
                    RowLayout {
                        Layout.fillWidth: true
                        visible: win.monitors.length > 1
                        spacing: 8
                        BarText { text: "Écran"; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 80 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: win.monitors
                                Chip {
                                    required property var modelData
                                    label: modelData.name + (modelData.disabled ? " (off)" : "")
                                    glyph: modelData.name === "eDP-1" ? 0xf0322 : 0xf0379
                                    active: modelData.name === win.selected
                                    onClicked: win.selected = modelData.name
                                }
                            }
                        }
                    }
                }
            }

            // --- Dispositions enregistrées ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                BarText { text: "Dispositions"; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 80 }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: win.layouts
                        Chip {
                            required property var modelData
                            label: modelData.name
                            glyph: 0xf056e    // md-view-dashboard
                            active: modelData.current
                            enabled: modelData.current
                            onClicked: win.apply("restore-layout")
                        }
                    }
                    BarText {
                        visible: win.layouts.length === 0
                        text: "Aucune enregistrée"
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                }
                Chip {
                    visible: win.hasExternal
                    label: "Enregistrer"
                    glyph: 0xf0193    // md-content-save
                    onClicked: win.apply("save-layout")
                }
                Chip {
                    label: "Gérer"
                    glyph: 0xf0493
                    onClicked: { win.hide(); Quickshell.execDetached([Paths.userBin + "/display-layouts"]); }
                }
            }

            // --- Rappel des touches ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [["1-4", "mode"], ["Tab", "écran suivant"], ["Échap", "fermer"]]
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

    // Bouton compact réutilisé par les rangées de réglages
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property int glyph: 0
        property bool active: false
        property color accent: Theme.mauve
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
