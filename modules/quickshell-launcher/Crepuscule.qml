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
// Touches : Échap fermer (ou annuler la recherche de ville).
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

    // --- Données -----------------------------------------------------------------
    property var st: null
    readonly property var flt: st ? st.filter : ({ mode: "sun", start: "21:00", end: "07:00", offset: 0, temp: 3500, brightness: 90 })
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
    function offsetLabel(o) {
        if (o === 0) return "au coucher du soleil";
        const a = Math.abs(o), t = a >= 60 ? Math.floor(a / 60) + " h" + (a % 60 ? " " + (a % 60) : "") : a + " min";
        return t + (o > 0 ? " avant le coucher" : " après le coucher");
    }

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
                    BarText {
                        text: "Filtre lumière bleue et mode sombre"
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                }
                Item { Layout.fillWidth: true }
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
                            Layout.fillWidth: true
                            text: win.st ? win.st.city.name : "…"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                        BarText {
                            Layout.fillWidth: true
                            text: win.st ? win.st.city.region : ""
                            font.pixelSize: 10
                            color: Theme.muted
                            elide: Text.ElideRight
                        }
                    }
                    BarText { text: Theme.ic(0xf059c) + " " + win.sunRise; font.pixelSize: 13; color: Theme.yellow }
                    BarText { text: Theme.ic(0xf059b) + " " + win.sunSet; font.pixelSize: 13; color: win.warm }
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
                                font.family: Theme.font
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
                                BarText { text: cityRow.modelData.name; font.pixelSize: 13 }
                                BarText {
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

            // --- Filtre lumière bleue ---
            Card {
                Layout.fillWidth: true
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

                // Détail du mode
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.flt.mode === "sun"
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        BarText {
                            text: win.st && win.st.window ? "Aujourd'hui : " + win.st.window.start + " → " + win.st.window.end : ""
                            font.pixelSize: 13
                        }
                        BarText {
                            text: "Début " + win.offsetLabel(win.flt.offset) + ", fin au lever"
                            font.pixelSize: 11
                            color: Theme.muted
                        }
                    }
                    IconBtn {
                        glyph: 0xf0374    // md-minus : plus tôt
                        enabled: win.flt.offset < 120
                        onClicked: win.setFilter("offset", win.flt.offset + 15)
                    }
                    BarText {
                        Layout.preferredWidth: 64
                        horizontalAlignment: Text.AlignHCenter
                        text: (win.flt.offset > 0 ? "−" : win.flt.offset < 0 ? "+" : "") + Math.abs(win.flt.offset) + " min"
                        font.pixelSize: 13
                        color: Theme.subtext
                    }
                    IconBtn {
                        glyph: 0xf0415    // md-plus : plus tard
                        enabled: win.flt.offset > -120
                        onClicked: win.setFilter("offset", win.flt.offset - 15)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: win.flt.mode === "hours"
                    spacing: 14
                    BarText { text: "De"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.flt.start)
                        accent: win.warm
                        onEdited: m => win.setFilter("start", win.fmt(m))
                    }
                    BarText { text: "à"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.flt.end)
                        accent: win.warm
                        onEdited: m => win.setFilter("end", win.fmt(m))
                    }
                    Item { Layout.fillWidth: true }
                }
                BarText {
                    visible: win.flt.mode === "always" || win.flt.mode === "off"
                    text: win.flt.mode === "always" ? "Filtre appliqué en permanence" : "Écran à sa couleur normale, jour et nuit"
                    font.pixelSize: 12
                    color: Theme.muted
                }
                BarText {
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
                            Layout.fillWidth: true
                            from: 6500
                            to: 1500
                            step: 100
                            value: win.flt.temp
                            colorFrom: "#fff3e6"
                            colorTo: "#ff7a1a"
                            onCommitted: v => win.setFilter("temp", v, true)
                        }
                        BarText { Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight; text: win.flt.temp + " K"; font.pixelSize: 12; color: Theme.subtext }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        BarText { Layout.preferredWidth: 22; text: Theme.ic(0xf00df); font.pixelSize: 16; color: Theme.subtext }
                        Slider {
                            Layout.fillWidth: true
                            from: 100
                            to: 40
                            step: 5
                            value: win.flt.brightness
                            colorFrom: "#ffffff"
                            colorTo: "#5a5a5a"
                            onCommitted: v => win.setFilter("brightness", v, true)
                        }
                        BarText { Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight; text: win.flt.brightness + " %"; font.pixelSize: 12; color: Theme.subtext }
                    }
                }
            }

            // --- Mode sombre ---
            Card {
                Layout.fillWidth: true
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
                    BarText { text: Theme.ic(0xf0594) + "  Sombre à"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.th.dark)
                        accent: Theme.mauve
                        onEdited: m => win.setThemeHours(win.fmt(m), win.th.light)
                    }
                    Item { implicitWidth: 6 }
                    BarText { text: Theme.ic(0xf0599) + "  Clair à"; font.pixelSize: 13; color: Theme.subtext }
                    TimeBox {
                        minutes: win.toMin(win.th.light)
                        accent: Theme.mauve
                        onEdited: m => win.setThemeHours(win.th.dark, win.fmt(m))
                    }
                    Item { Layout.fillWidth: true }
                }
                BarText {
                    visible: win.th.mode === "sun"
                    text: "Sombre au coucher (" + win.sunSet + "), clair au lever (" + win.sunRise + ")"
                    font.pixelSize: 12
                    color: Theme.muted
                }

                // Choix immédiat clair / sombre
                RowLayout {
                    Layout.fillWidth: true
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
                        Layout.fillWidth: true
                        text: win.th.mode === "manual" ? "Le thème ne change plus tout seul"
                                                       : "Jusqu'au prochain changement automatique"
                        wrapMode: Text.Wrap
                        font.pixelSize: 11
                        color: Theme.muted
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
            BarText { text: ":"; font.pixelSize: 22; color: Theme.muted }
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

    // Curseur : piste en dégradé (from → to), appliqué au relâchement
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
            onPressed: ev => sl.dragValue = sl.at(ev.x)
            onPositionChanged: ev => { if (pressed) sl.dragValue = sl.at(ev.x); }
            onReleased: if (sl.dragValue !== sl.value) sl.committed(sl.dragValue)
            onWheel: ev => {
                const v = Math.max(Math.min(sl.from, sl.to), Math.min(Math.max(sl.from, sl.to),
                          sl.value + (ev.angleDelta.y > 0 ? 1 : -1) * sl.step * (sl.to > sl.from ? 1 : -1)));
                if (v !== sl.value) sl.committed(v);
            }
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
        signal clicked()
        implicitWidth: chipRow.implicitWidth + 20
        implicitHeight: 28
        radius: 14
        color: cma.containsMouse ? Theme.pillHover : "transparent"
        border.color: Theme.pillBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: cma.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            BarText { text: Theme.ic(chip.glyph); font.pixelSize: 13; color: Theme.subtext }
            BarText { text: chip.label; font.pixelSize: 11; color: cma.containsMouse ? Theme.text : Theme.subtext }
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
