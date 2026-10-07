import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Crépuscule (menu d'applications, ou `crepuscule`) : filtre anti-lumière bleue et mode sombre.
// Filtre : selon le soleil d'une ville (avance réglable), horaires fixes, toujours ou désactivé ;
// température et luminosité. Mode sombre : horaires, soleil ou manuel (clair / sombre à la main).
// Données et actions via `crepuscule-ctl` (assets/crepuscule.py, modules/crepuscule.nix).
// Deux sections (lumière bleue / mode sombre), changées par le switch à icônes de l'en-tête.
// Touches : Tab changer de section, Échap fermer (ou annuler la recherche de ville).
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-crepuscule"
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
        searching = false;
        refresh();
        keys.forceActiveFocus();
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Section ----------------------------------------------------------------
    property int tab: 0             // 0 lumière bleue, 1 mode sombre (gardée d'une ouverture à l'autre)
    property real pos: tab          // position animée (glissement entre sections)
    Behavior on pos { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }

    // --- Données -----------------------------------------------------------------
    property var st: null
    readonly property var flt: st ? st.filter : ({ mode: "sun", start: "21:00", end: "07:00", full_start: null, full_end: null, ramp_in: 30, ramp_out: 30, temp: 3500, brightness: 90 })
    readonly property var th: st ? st.theme : ({ mode: "hours", dark: "20:00", light: "08:00", current: "light" })
    readonly property string sunRise: st && st.sun ? st.sun.rise : "--:--"
    readonly property string sunSet: st && st.sun ? st.sun.set : "--:--"
    readonly property string ctlPath: Paths.userBin + "/crepuscule-ctl"

    Process {
        id: stateProc
        command: [win.ctlPath, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Réglage en attente (anti-rebond) : on garde l'affichage local
                if (debounce.running || actProc.running || win.queue.length) return;
                try { win.st = JSON.parse(text); } catch (e) {}
            }
        }
    }
    function refresh() { if (!stateProc.running) stateProc.running = true; }
    // Statut actif / inactif à jour tant que la fenêtre est ouverte
    Timer { interval: 30000; repeat: true; running: win.open; onTriggered: win.refresh() }

    // Actions exécutées une par une (chacune peut relancer gammastep), puis relecture
    property var queue: []
    Process {
        id: actProc
        onExited: win.queue.length ? win.next() : win.refresh()
    }
    function next() {
        actProc.command = [ctlPath, ...queue.shift()];
        actProc.running = true;
    }
    function ctl(...args) {
        queue.push(args);
        if (!actProc.running) next();
    }
    // Aperçu pendant le glissement d'un curseur : seul le dernier aperçu en attente est gardé
    function preview(temp, bright) {
        const args = ["preview", String(temp), String(bright)];
        if (queue.length && queue[queue.length - 1][0] === "preview") queue[queue.length - 1] = args;
        else ctl(...args);
    }

    // Copie locale modifiée tout de suite (affichage réactif), envoi groupé après 700 ms
    property var pending: ({})
    Timer {
        id: debounce
        interval: 700
        onTriggered: {
            for (const k in win.pending) {
                const v = win.pending[k];
                if (k === "theme.hours") win.ctl("theme", "hours", v[0], v[1]);
                else win.ctl("set", k, String(v));
            }
            win.pending = {};
        }
    }
    function patch(section, key, value) {
        if (!st) return;
        const s = JSON.parse(JSON.stringify(st));
        s[section][key] = value;
        st = s;
    }
    function setFilter(key, value, now) {
        patch("filter", key, value);
        pending["filter." + key] = value;
        if (now) { debounce.stop(); debounce.triggered(); }
        else debounce.restart();
    }
    function setThemeHours(dark, light) {
        patch("theme", "dark", dark);
        patch("theme", "light", light);
        pending["theme.hours"] = [dark, light];
        debounce.restart();
    }
    function setThemeMode(m) {
        patch("theme", "mode", m);
        ctl("theme", "mode", m);
    }
    function setScheme(s) {
        patch("theme", "current", s);
        ctl("theme", s);
    }

    // --- Ville (géocodage Open-Meteo) ---
    property bool searching: false
    property var cities: []
    property string searchMsg: ""
    function startSearch() {
        searching = true;
        cities = [];
        searchMsg = "";
        cityInput.text = "";
        cityInput.forceActiveFocus();
    }
    function stopSearch() {
        searching = false;
        keys.forceActiveFocus();
    }
    Process {
        id: geoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    win.cities = d.results;
                    win.searchMsg = d.error ?? "";
                } catch (e) { win.searchMsg = "Recherche impossible"; }
            }
        }
    }
    function search() {
        const q = cityInput.text.trim();
        if (q.length < 2 || geoProc.running) return;
        searchMsg = "Recherche…";
        cities = [];
        geoProc.command = [ctlPath, "geocode", q];
        geoProc.running = true;
    }
    function pickCity(c) {
        if (st) {
            const s = JSON.parse(JSON.stringify(st));
            s.city = c;
            st = s;
        }
        ctl("set-city", c.name, c.region, String(c.lat), String(c.lon));
        stopSearch();
    }

    // --- Heures ---
    function toMin(s) { const p = String(s).split(":"); return (parseInt(p[0]) || 0) * 60 + (parseInt(p[1]) || 0); }
    function fmt(m) {
        m = ((Math.round(m) % 1440) + 1440) % 1440;
        const h = Math.floor(m / 60), mm = m % 60;
        return (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm;
    }
    readonly property var rampChoices: [0, 15, 30, 60, 120]
    function durLabel(m) { return m === 0 ? "Aucune" : m < 60 ? m + " min" : (m / 60) + " h"; }
    // Minutes actuelles (rafraîchies avec l'état, pour le repère « maintenant » de la frise)
    property int nowMin: 0
    onStChanged: { const d = new Date(); nowMin = d.getHours() * 60 + d.getMinutes(); }

    readonly property var filterModes: [
        { id: "sun", label: "Soleil", icon: 0xf059b },
        { id: "hours", label: "Horaires", icon: 0xf0150 },
        { id: "always", label: "Toujours", icon: 0xf06e4 },
        { id: "off", label: "Désactivé", icon: 0xf0425 }
    ]
    readonly property var themeModes: [
        { id: "hours", label: "Horaires", icon: 0xf0150 },
        { id: "sun", label: "Soleil", icon: 0xf059b },
        { id: "manual", label: "Manuel", icon: 0xf0741 }
    ]
    readonly property color warm: "#ff9a4d"

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
        Keys.onEscapePressed: win.hide()
        Keys.onTabPressed: win.tab = 1 - win.tab
        Keys.onBacktabPressed: win.tab = 1 - win.tab
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(620, parent.width - 80)
        height: col.implicitHeight + 40
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        radius: 20
        color: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.9)
        border.color: Theme.border
        border.width: 1
        clip: true

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }    // le clic dans le panneau ne ferme pas

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 14

            // --- En-tête ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 22
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 0.6, 0.3, 0.30) }
                        GradientStop { position: 1; color: Qt.rgba(0.8, 0.65, 0.97, 0.22) }
                    }
                    border.color: Qt.rgba(1, 0.6, 0.3, 0.5)
                    border.width: 1
                    BarText {
                        anchors.centerIn: parent
                        text: Theme.ic(0xf059a)    // md-weather_sunset
                        font.pixelSize: 22
                        color: win.warm
                    }
                }
                ColumnLayout {
                    spacing: 0
                    BarText {
                        text: "Crépuscule"
                        font.family: Theme.titleFont
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                }
                Item { Layout.fillWidth: true }

                // Switch des sections : pastille qui glisse sous l'icône active
                Rectangle {
                    id: sw
                    readonly property color accent: Theme.lerpColor(win.warm, Theme.mauve, Math.max(0, Math.min(1, win.pos)))
                    implicitWidth: 2 * 54 + 8
                    implicitHeight: 42
                    radius: 21
                    color: Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1
                    Rectangle {
                        x: 4 + win.pos * 54
                        y: 4
                        width: 54
                        height: 34
                        radius: 17
                        color: Qt.rgba(sw.accent.r, sw.accent.g, sw.accent.b, 0.25)
                        border.color: sw.accent
                        border.width: 1
                    }
                    Repeater {
                        model: [
                            { icon: 0xf06e8, color: win.warm },       // md-lightbulb_on
                            { icon: 0xf050e, color: Theme.mauve }     // md-theme_light_dark
                        ]
                        Item {
                            required property var modelData
                            required property int index
                            readonly property real near: Math.max(0, 1 - Math.abs(win.pos - index))
                            x: 4 + index * 54
                            y: 4
                            width: 54
                            height: 34
                            BarText {
                                anchors.centerIn: parent
                                text: Theme.ic(modelData.icon)
                                font.pixelSize: 18
                                color: Theme.lerpColor(Theme.subtext, modelData.color, near)
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
                IconBtn { glyph: 0xf0156; onClicked: win.hide() }    // md-close
            }

            // --- Ville et soleil du jour ---
            Card {
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    visible: !win.searching
                    spacing: 10
                    BarText { text: Theme.ic(0xf034e); font.pixelSize: 18; color: Theme.red }    // md-map_marker
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        BarText {
                            font.family: Theme.labelFont
                            Layout.fillWidth: true
                            text: win.st ? win.st.city.name : "…"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                        BarText {
                            font.family: Theme.labelFont
                            Layout.fillWidth: true
                            text: win.st ? win.st.city.region : ""
                            font.pixelSize: 10
                            color: Theme.muted
                            elide: Text.ElideRight
                        }
                    }
                    BarText { text: Theme.ic(0xf059c); font.pixelSize: 14; color: Theme.yellow }
                    BarText { font.family: Theme.labelFont; text: win.sunRise; font.pixelSize: 13; color: Theme.yellow }
                    BarText { text: Theme.ic(0xf059b); font.pixelSize: 14; color: win.warm }
                    BarText { font.family: Theme.labelFont; text: win.sunSet; font.pixelSize: 13; color: win.warm }
                    Chip { glyph: 0xf0349; label: "Changer"; onClicked: win.startSearch() }    // md-magnify
                }

                // Recherche de ville
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: win.searching
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        BarText { text: Theme.ic(0xf0349); font.pixelSize: 16; color: Theme.subtext }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            BarText {
                                font.family: Theme.labelFont
                                anchors.fill: parent
                                visible: cityInput.text === ""
                                text: "Nom de la ville, puis Entrée"
                                font.pixelSize: 13
                                color: Theme.muted
                            }
                            TextInput {
                                id: cityInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text
                                font.family: Theme.labelFont
                                font.pixelSize: 13
                                clip: true
                                selectByMouse: true
                                onAccepted: win.search()
                                Keys.onEscapePressed: win.stopSearch()
                            }
                        }
                        IconBtn { glyph: 0xf0156; onClicked: win.stopSearch() }
                    }
                    BarText {
                        font.family: Theme.labelFont
                        visible: win.searchMsg !== ""
                        text: win.searchMsg
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                    Repeater {
                        model: win.cities
                        Rectangle {
                            id: cityRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 8
                            color: cityMa.containsMouse ? Theme.rowHover : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                BarText { font.family: Theme.labelFont; text: cityRow.modelData.name; font.pixelSize: 13 }
                                BarText {
                                    font.family: Theme.labelFont
                                    Layout.fillWidth: true
                                    text: cityRow.modelData.region
                                    font.pixelSize: 11
                                    color: Theme.muted
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: cityMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.pickCity(cityRow.modelData)
                            }
                        }
                    }
                }
            }

            // --- Sections : glissement + fondu selon `pos`, hauteur interpolée ---
            Item {
                id: host
                Layout.fillWidth: true
                implicitHeight: filterCard.implicitHeight
                                + (themeCard.implicitHeight - filterCard.implicitHeight) * Math.max(0, Math.min(1, win.pos))
                clip: true

            // Section 0 : filtre lumière bleue
            Card {
                id: filterCard
                width: host.width
                x: -win.pos * 70
                opacity: Math.max(0, 1 - win.pos * 1.6)
                visible: opacity > 0.01
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    BarText { text: Theme.ic(0xf06e8); font.pixelSize: 18; color: win.warm }    // md-lightbulb_on
                    BarText { text: "Filtre lumière bleue"; font.family: Theme.labelFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    Badge {
                        lit: win.st ? win.st.active : false
                        accent: win.warm
                        label: lit ? "Actif · " + win.st.now.temp + " K" : "Inactif"
                    }
                }
                Segmented {
                    Layout.fillWidth: true
                    items: win.filterModes
                    current: win.flt.mode
                    accent: win.warm
                    onPicked: key => win.setFilter("mode", key, true)
                }

                // Détail du mode : plage (horaires), frise de la nuit, montée / descente
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.flt.mode === "hours"
                    spacing: 14
                    BarText { font.family: Theme.labelFont; text: "De"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.flt.start)
                        accent: win.warm
                        onEdited: m => win.setFilter("start", win.fmt(m))
                    }
                    BarText { font.family: Theme.labelFont; text: "à"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.flt.end)
                        accent: win.warm
                        onEdited: m => win.setFilter("end", win.fmt(m))
                    }
                    Item { Layout.fillWidth: true }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: (win.flt.mode === "sun" || win.flt.mode === "hours") && win.st !== null && win.st.slice !== null
                    spacing: 8
                    BarText {
                        font.family: Theme.labelFont
                        text: "Pleine valeur de " + (win.st && win.st.slice ? win.st.slice.start + " à " + win.st.slice.end : "")
                              + "  ·  glisse les poignées"
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                    Timeline {
                        Layout.fillWidth: true
                        sunMode: win.flt.mode === "sun"
                        winStart: win.st && win.st.window ? win.toMin(win.st.window.start) : 0
                        winEnd: win.st && win.st.window ? win.toMin(win.st.window.end) : 0
                        sliceStart: win.st && win.st.slice ? win.toMin(win.st.slice.start) : 0
                        sliceEnd: win.st && win.st.slice ? win.toMin(win.st.slice.end) : 0
                        rampIn: win.flt.ramp_in
                        rampOut: win.flt.ramp_out
                        now: win.nowMin
                        onSliceEdited: (a, b) => {
                            // Copie locale : la frise suit tout de suite, le backend recalcule ensuite
                            if (win.st) {
                                const s = JSON.parse(JSON.stringify(win.st));
                                s.slice = { start: a === "edge" ? s.window.start : a, end: b === "edge" ? s.window.end : b };
                                win.st = s;
                            }
                            win.setFilter("full_start", a);
                            win.setFilter("full_end", b, true);
                        }
                    }
                    RampRow {
                        Layout.fillWidth: true
                        glyph: 0xf059b    // md-weather_sunset_down
                        label: "Montée"
                        value: win.flt.ramp_in
                        hint: value > 0 && win.st && win.st.slice
                              ? "dès " + win.fmt(win.toMin(win.st.slice.start) - value) : "d'un coup"
                        onPicked: m => win.setFilter("ramp_in", m, true)
                    }
                    RampRow {
                        Layout.fillWidth: true
                        glyph: 0xf059c    // md-weather_sunset_up
                        label: "Descente"
                        value: win.flt.ramp_out
                        hint: value > 0 && win.st && win.st.slice
                              ? "jusqu'à " + win.fmt(win.toMin(win.st.slice.end) + value) : "d'un coup"
                        onPicked: m => win.setFilter("ramp_out", m, true)
                    }
                }
                BarText {
                    font.family: Theme.labelFont
                    visible: win.flt.mode === "always" || win.flt.mode === "off"
                    text: win.flt.mode === "always" ? "Filtre appliqué en permanence" : "Écran à sa couleur normale, jour et nuit"
                    font.pixelSize: 12
                    color: Theme.muted
                }
                BarText {
                    font.family: Theme.labelFont
                    Layout.fillWidth: true
                    visible: win.st !== null && win.st.error !== null
                    text: win.st && win.st.error ? win.st.error : ""
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                    color: Theme.red
                }

                // Intensité
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: win.flt.mode !== "off"
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        BarText { Layout.preferredWidth: 22; text: Theme.ic(0xf050f); font.pixelSize: 16; color: Theme.subtext }
                        Slider {
                            id: tempSlider
                            Layout.fillWidth: true
                            from: 6500
                            to: 1500
                            step: 100
                            value: win.flt.temp
                            colorFrom: "#fff3e6"
                            colorTo: "#ff7a1a"
                            onCommitted: v => win.setFilter("temp", v, true)
                            onPreviewed: v => win.preview(v, win.flt.brightness)
                            onPreviewEnded: win.ctl("preview-end")
                        }
                        BarText { font.family: Theme.labelFont; Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight; text: tempSlider.dragValue + " K"; font.pixelSize: 12; color: Theme.subtext }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        BarText { Layout.preferredWidth: 22; text: Theme.ic(0xf00df); font.pixelSize: 16; color: Theme.subtext }
                        Slider {
                            id: brightSlider
                            Layout.fillWidth: true
                            from: 100
                            to: 40
                            step: 5
                            value: win.flt.brightness
                            colorFrom: "#ffffff"
                            colorTo: "#5a5a5a"
                            onCommitted: v => win.setFilter("brightness", v, true)
                            onPreviewed: v => win.preview(win.flt.temp, v)
                            onPreviewEnded: win.ctl("preview-end")
                        }
                        BarText { font.family: Theme.labelFont; Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight; text: brightSlider.dragValue + " %"; font.pixelSize: 12; color: Theme.subtext }
                    }
                }
            }

            // Section 1 : mode sombre
            Card {
                id: themeCard
                width: host.width
                x: (1 - win.pos) * 70
                opacity: Math.max(0, 1 - (1 - win.pos) * 1.6)
                visible: opacity > 0.01
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    BarText { text: Theme.ic(0xf050e); font.pixelSize: 18; color: Theme.mauve }    // md-theme_light_dark
                    BarText { text: "Mode sombre"; font.family: Theme.labelFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    Badge {
                        lit: win.th.current === "dark"
                        accent: Theme.mauve
                        label: lit ? "Sombre" : "Clair"
                    }
                }
                Segmented {
                    Layout.fillWidth: true
                    items: win.themeModes
                    current: win.th.mode
                    accent: Theme.mauve
                    onPicked: key => win.setThemeMode(key)
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.th.mode === "hours"
                    spacing: 14
                    BarText { text: Theme.ic(0xf0594); font.pixelSize: 14; color: Theme.subtext }
                    BarText { font.family: Theme.labelFont; text: "Sombre à"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.th.dark)
                        accent: Theme.mauve
                        onEdited: m => win.setThemeHours(win.fmt(m), win.th.light)
                    }
                    Item { implicitWidth: 6 }
                    BarText { text: Theme.ic(0xf0599); font.pixelSize: 14; color: Theme.subtext }
                    BarText { font.family: Theme.labelFont; text: "Clair à"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.th.light)
                        accent: Theme.mauve
                        onEdited: m => win.setThemeHours(win.th.dark, win.fmt(m))
                    }
                    Item { Layout.fillWidth: true }
                }
                BarText {
                    font.family: Theme.labelFont
                    visible: win.th.mode === "sun"
                    text: "Sombre au coucher (" + win.sunSet + "), clair au lever (" + win.sunRise + ")"
                    font.pixelSize: 12
                    color: Theme.muted
                }

                // Mode manuel : choix clair / sombre
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.th.mode === "manual"
                    spacing: 10
                    Segmented {
                        Layout.preferredWidth: 240
                        items: [
                            { id: "light", label: "Clair", icon: 0xf0599 },
                            { id: "dark", label: "Sombre", icon: 0xf0594 }
                        ]
                        current: win.th.current
                        accent: Theme.mauve
                        onPicked: key => win.setScheme(key)
                    }
                    BarText {
                        font.family: Theme.labelFont
                        Layout.fillWidth: true
                        text: "Le thème ne change plus tout seul"
                        wrapMode: Text.Wrap
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                }
            }
            }
        }
    }

    // --- Composants ---------------------------------------------------------------------

    // Bloc à fond léger ; les enfants s'empilent en colonne
    component Card: Rectangle {
        default property alias content: inner.data
        implicitHeight: inner.implicitHeight + 28
        radius: 14
        color: Theme.pill
        border.color: Theme.pillBorder
        border.width: 1
        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12
        }
    }

    // Pastille d'état (actif / inactif)
    component Badge: Rectangle {
        id: badge
        property bool lit: false
        property color accent: Theme.mauve
        property string label: ""
        implicitWidth: badgeText.implicitWidth + 22
        implicitHeight: 24
        radius: 12
        color: lit ? Qt.rgba(accent.r, accent.g, accent.b, 0.18) : "transparent"
        border.color: lit ? accent : Theme.pillBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: 160 } }
        BarText {
            id: badgeText
            font.family: Theme.labelFont
            anchors.centerIn: parent
            text: badge.label
            font.pixelSize: 11
            color: badge.lit ? badge.accent : Theme.muted
        }
    }

    // Boutons de choix exclusifs de même largeur ({ id, label, icon })
    component Segmented: RowLayout {
        id: seg
        property var items: []
        property string current: ""
        property color accent: Theme.mauve
        signal picked(string key)
        spacing: 6
        Repeater {
            model: seg.items
            Rectangle {
                id: segBtn
                required property var modelData
                readonly property bool active: seg.current === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 36
                radius: 10
                color: active ? Qt.rgba(seg.accent.r, seg.accent.g, seg.accent.b, 0.2)
                              : (segMa.containsMouse ? Theme.pillHover : Theme.pill)
                border.color: active ? seg.accent : Theme.pillBorder
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                scale: segMa.pressed ? 0.95 : 1
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                ClickFx { id: segFx }
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7
                    BarText {
                        text: Theme.ic(segBtn.modelData.icon)
                        font.pixelSize: 15
                        color: segBtn.active ? seg.accent : Theme.subtext
                    }
                    BarText {
                        font.family: Theme.labelFont
                        text: segBtn.modelData.label
                        font.pixelSize: 12
                        color: segBtn.active || segMa.containsMouse ? Theme.text : Theme.subtext
                    }
                }
                MouseArea {
                    id: segMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        segFx.play();
                        if (!segBtn.active) seg.picked(segBtn.modelData.id);
                    }
                }
            }
        }
    }

    // Heure HH:MM : flèches ou molette sur les heures (±1 h) et les minutes (±5 min)
    component TimeBox: Rectangle {
        id: tb
        property int minutes: 0
        property color accent: Theme.mauve
        signal edited(int minutes)
        implicitWidth: 112
        implicitHeight: 64
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.25)
        border.color: tbHover.hovered ? Qt.rgba(accent.r, accent.g, accent.b, 0.6) : Theme.pillBorder
        border.width: 1
        readonly property bool hovered: tbHover.hovered
        HoverHandler { id: tbHover }

        function bump(d) { tb.edited(((tb.minutes + d) % 1440 + 1440) % 1440); }

        RowLayout {
            anchors.centerIn: parent
            spacing: 2
            TimePart { box: tb; value: Math.floor(tb.minutes / 60); step: 60 }
            BarText { font.family: Theme.labelFont; text: ":"; font.pixelSize: 22; color: Theme.muted }
            TimePart { box: tb; value: tb.minutes % 60; step: 5 }
        }
    }

    // Chiffres d'une TimeBox (heures ou minutes)
    component TimePart: Item {
        id: tp
        property var box
        property int value: 0
        property int step: 1
        implicitWidth: 40
        implicitHeight: 60
        BarText {
            font.family: Theme.labelFont
            anchors.centerIn: parent
            text: (tp.value < 10 ? "0" : "") + tp.value
            font.pixelSize: 22
            font.weight: Font.DemiBold
            color: tpWheel.hovered ? tp.box.accent : Theme.text
        }
        HoverHandler { id: tpWheel }
        WheelHandler {
            onWheel: ev => tp.box.bump(ev.angleDelta.y > 0 ? tp.step : -tp.step)
        }
        BarText {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.ic(0xf0143)    // md-chevron_up
            font.pixelSize: 12
            color: upMa.containsMouse ? tp.box.accent : Theme.muted
            opacity: tp.box.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            MouseArea {
                id: upMa
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tp.box.bump(tp.step)
            }
        }
        BarText {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.ic(0xf0140)    // md-chevron_down
            font.pixelSize: 12
            color: downMa.containsMouse ? tp.box.accent : Theme.muted
            opacity: tp.box.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            MouseArea {
                id: downMa
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tp.box.bump(-tp.step)
            }
        }
    }

    // Curseur : piste en dégradé (from → to), aperçu à l'écran pendant le glissement, appliqué au relâchement
    component Slider: Item {
        id: sl
        property real from: 0
        property real to: 100
        property real step: 1
        property real value: 0
        property color colorFrom: "#ffffff"
        property color colorTo: "#000000"
        property real dragValue: value
        readonly property real frac: Math.max(0, Math.min(1, (dragValue - from) / (to - from)))
        signal committed(int value)
        signal previewed(int value)     // pendant le glissement
        signal previewEnded()           // au relâchement, après committed
        implicitHeight: 24
        onValueChanged: if (!slMa.pressed) dragValue = value

        function at(x) {
            const f = Math.max(0, Math.min(1, x / width));
            return Math.round((from + f * (to - from)) / step) * step;
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 8
            radius: 4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: sl.colorFrom }
                GradientStop { position: 1; color: sl.colorTo }
            }
            opacity: 0.85
        }
        Rectangle {
            x: sl.frac * (sl.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: Theme.lerpColor(sl.colorFrom, sl.colorTo, sl.frac)
            border.color: "#ffffff"
            border.width: 2
            scale: slMa.pressed ? 1.2 : (slMa.containsMouse ? 1.1 : 1)
            Behavior on scale { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            id: slMa
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: ev => { sl.dragValue = sl.at(ev.x); sl.previewed(sl.dragValue); }
            onPositionChanged: ev => {
                if (!pressed) return;
                const v = sl.at(ev.x);
                if (v !== sl.dragValue) { sl.dragValue = v; sl.previewed(v); }
            }
            onReleased: {
                if (sl.dragValue !== sl.value) sl.committed(sl.dragValue);
                sl.previewEnded();
            }
            onWheel: ev => {
                const v = Math.max(Math.min(sl.from, sl.to), Math.min(Math.max(sl.from, sl.to),
                          sl.value + (ev.angleDelta.y > 0 ? 1 : -1) * sl.step * (sl.to > sl.from ? 1 : -1)));
                if (v !== sl.value) sl.committed(v);
            }
        }
    }

    // Frise de la nuit : de la borne de début (coucher / début) à celle de fin (lever / fin).
    // Courbe = intensité du filtre ; montée avant la tranche pleine, descente après (dessinées
    // hors de la frise si elles débordent). Deux poignées règlent la tranche ; près d'une borne,
    // elles s'y accrochent (« edge » : la tranche suit alors le soleil jour après jour).
    component Timeline: Item {
        id: tl
        property bool sunMode: true
        property int winStart: 0
        property int winEnd: 0
        property int sliceStart: 0
        property int sliceEnd: 0
        property int rampIn: 0
        property int rampOut: 0
        property int now: 0
        signal sliceEdited(string a, string b)

        // Tout en minutes relatives au début de plage
        readonly property int wl: ((winEnd - winStart) % 1440 + 1440) % 1440 || 1440
        property real dragA: -1
        property real dragB: -1
        readonly property real a: dragA >= 0 ? dragA : ((sliceStart - winStart) % 1440 + 1440) % 1440
        readonly property real b: dragB >= 0 ? dragB : Math.max(a, (((sliceEnd - winStart) % 1440 + 1440) % 1440) || (sliceEnd === winEnd ? wl : 0))
        readonly property real lo: Math.min(0, a - rampIn)
        readonly property real hi: Math.max(wl, b + rampOut)
        readonly property real pad: 12
        readonly property real yTop: 30
        readonly property real base: 84
        function px(m) { return pad + (m - lo) / (hi - lo) * (width - 2 * pad); }
        function rel(p) { return lo + (p - pad) / (width - 2 * pad) * (hi - lo); }
        function abs(rel) { return win.fmt(winStart + rel); }
        readonly property real nowRel: {
            let r = ((now - winStart) % 1440 + 1440) % 1440;
            if (r > hi && r - 1440 >= lo) r -= 1440;
            return r;
        }

        implicitHeight: 108
        onAChanged: cv.requestPaint()
        onBChanged: cv.requestPaint()
        onLoChanged: cv.requestPaint()
        onHiChanged: cv.requestPaint()
        onWidthChanged: cv.requestPaint()

        // Fond de la plage (coucher → lever)
        Rectangle {
            x: tl.px(0)
            y: tl.yTop - 8
            width: tl.px(tl.wl) - tl.px(0)
            height: tl.base - tl.yTop + 8
            radius: 8
            color: Qt.rgba(0.35, 0.4, 0.75, 0.10)
            border.color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
        }

        Canvas {
            id: cv
            anchors.fill: parent
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const x0 = tl.px(tl.a - tl.rampIn), xa = tl.px(tl.a), xb = tl.px(tl.b), x1 = tl.px(tl.b + tl.rampOut);
                // Ligne de base (pointillés hors de la plage)
                c.strokeStyle = Qt.rgba(1, 1, 1, 0.18);
                c.lineWidth = 1;
                c.beginPath(); c.moveTo(tl.px(0), tl.base); c.lineTo(tl.px(tl.wl), tl.base); c.stroke();
                // Aire de la courbe
                const g = c.createLinearGradient(0, tl.yTop, 0, tl.base);
                g.addColorStop(0, Qt.rgba(1, 0.6, 0.3, 0.55));
                g.addColorStop(1, Qt.rgba(1, 0.6, 0.3, 0.04));
                c.fillStyle = g;
                c.beginPath();
                c.moveTo(x0, tl.base); c.lineTo(xa, tl.yTop); c.lineTo(xb, tl.yTop); c.lineTo(x1, tl.base);
                c.closePath(); c.fill();
                c.strokeStyle = "#ff9a4d";
                c.lineWidth = 2;
                c.beginPath();
                c.moveTo(x0, tl.base); c.lineTo(xa, tl.yTop); c.lineTo(xb, tl.yTop); c.lineTo(x1, tl.base);
                c.stroke();
            }
        }

        // Repère « maintenant »
        Rectangle {
            visible: tl.nowRel >= tl.lo && tl.nowRel <= tl.hi
            x: tl.px(tl.nowRel) - 1
            y: tl.yTop - 12
            width: 2
            height: tl.base - tl.yTop + 12
            radius: 1
            color: Theme.text
            opacity: 0.7
        }

        // Bornes : coucher / lever (ou début / fin)
        Repeater {
            model: [
                { rel: 0, glyph: tl.sunMode ? 0xf059b : 0xf0150, color: win.warm, align: Text.AlignLeft },
                { rel: tl.wl, glyph: tl.sunMode ? 0xf059c : 0xf0150, color: Theme.yellow, align: Text.AlignRight }
            ]
            Row {
                required property var modelData
                x: modelData.align === Text.AlignLeft ? Math.max(0, tl.px(modelData.rel) - 4)
                                                      : Math.min(tl.width - implicitWidth, tl.px(modelData.rel) - implicitWidth + 4)
                y: tl.base + 6
                spacing: 4
                BarText { text: Theme.ic(parent.modelData.glyph); font.pixelSize: 12; color: parent.modelData.color }
                BarText { text: tl.abs(parent.modelData.rel); font.pixelSize: 11; font.family: Theme.labelFont; color: parent.modelData.color }
            }
        }

        // Poignées de la tranche pleine
        Repeater {
            model: [0, 1]
            Item {
                id: hd
                required property int modelData
                readonly property real pos: modelData === 0 ? tl.a : tl.b
                x: tl.px(pos) - 12
                y: tl.yTop - 12
                width: 24
                height: 24
                z: 2
                BarText {
                    font.family: Theme.labelFont
                    anchors.bottom: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: -2
                    text: tl.abs(hd.pos)
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: hma.containsMouse || hma.pressed ? win.warm : Theme.subtext
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: win.warm
                    border.color: "#ffffff"
                    border.width: 2
                    scale: hma.pressed ? 1.3 : (hma.containsMouse ? 1.15 : 1)
                    Behavior on scale { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    id: hma
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor
                    preventStealing: true
                    onPositionChanged: ev => {
                        if (!pressed) return;
                        const p = mapToItem(tl, ev.x, ev.y);
                        let v = Math.round(tl.rel(p.x) / 5) * 5;
                        v = Math.max(0, Math.min(tl.wl, v));
                        if (v < 10) v = 0;                      // accroche aux bornes
                        if (v > tl.wl - 10) v = tl.wl;
                        if (hd.modelData === 0) { tl.dragB = tl.b; tl.dragA = Math.min(v, tl.b); }
                        else { tl.dragA = tl.a; tl.dragB = Math.max(v, tl.a); }
                    }
                    onReleased: {
                        if (tl.dragA < 0 && tl.dragB < 0) return;
                        const a = tl.a, b = tl.b;
                        tl.dragA = -1;
                        tl.dragB = -1;
                        tl.sliceEdited(a <= 0 ? "edge" : tl.abs(a), b >= tl.wl ? "edge" : tl.abs(b));
                    }
                }
            }
        }
    }

    // Durée de montée / descente : Aucune, 15 min… 2 h
    component RampRow: RowLayout {
        id: rr
        property int glyph: 0
        property string label: ""
        property int value: 0
        property string hint: ""
        signal picked(int minutes)
        spacing: 6
        BarText { Layout.preferredWidth: 20; text: Theme.ic(rr.glyph); font.pixelSize: 14; color: win.warm }
        BarText { font.family: Theme.labelFont; Layout.preferredWidth: 70; text: rr.label; font.pixelSize: 12; color: Theme.subtext }
        Repeater {
            model: win.rampChoices
            Chip {
                required property int modelData
                label: win.durLabel(modelData)
                active: rr.value === modelData
                accent: win.warm
                onClicked: rr.picked(modelData)
            }
        }
        BarText {
            font.family: Theme.labelFont
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: rr.hint
            font.pixelSize: 11
            color: Theme.muted
            elide: Text.ElideRight
        }
    }

    // Bouton rond à icône seule
    component IconBtn: Rectangle {
        id: ib
        property int glyph: 0
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        opacity: enabled ? 1 : 0.35
        color: ibMa.containsMouse && enabled ? Theme.pillHover : "transparent"
        border.color: Theme.pillBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: ibMa.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        BarText {
            anchors.centerIn: parent
            text: Theme.ic(ib.glyph)
            font.pixelSize: 14
            color: Theme.subtext
        }
        MouseArea {
            id: ibMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: ib.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (ib.enabled) ib.clicked()
        }
    }

    // Bouton compact icône + texte
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
            BarText { visible: chip.glyph !== 0; text: Theme.ic(chip.glyph); font.pixelSize: 13; color: chip.active ? chip.accent : Theme.subtext }
            BarText { font.family: Theme.labelFont; text: chip.label; font.pixelSize: 11; color: chip.active || cma.containsMouse ? Theme.text : Theme.subtext }
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
