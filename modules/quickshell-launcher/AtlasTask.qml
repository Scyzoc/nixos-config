import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Nouvelle tâche Atlas (SUPER+SHIFT+T) : formulaire envoyé au serveur MCP d'Atlas par le
// script `atlas-task` (modules/atlas-task.nix). Le bouton chapeau bascule en « Nouveau devoir »
// (évaluation de l'espace Cours, comme dans l'appli). Entrée dans le titre ou Ctrl+Entrée :
// créer ; Tab : champ suivant ; Échap : fermer le menu ouvert puis le popup.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-atlas"
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

    // --- Données Atlas (cache puis serveur) ---------------------------------------------
    property var themes: []
    property var projects: []
    property var courses: []    // matières + profs (devoirs)
    property bool metaLoaded: false

    readonly property var themeIcons: ({
        user: 0xf0013, briefcase: 0xf0814, courses: 0xf1180,
        health: 0xf05f6, home: 0xf06a1, money: 0xf0114
    })

    readonly property var themeOptions: [{ value: -1, label: "Celui du projet", icon: 0xf04fc, color: Theme.muted }]
        .concat(themes.map(t => ({ value: t.id, label: t.name, icon: themeIcons[t.icon] ?? 0xf04fc, color: Theme.subtext })))
    readonly property var projectOptions: [{ value: -1, label: "Aucun", icon: 0xf0256, color: Theme.muted }]
        .concat(projects.filter(p => p.status !== "termine" && p.status !== "archive")
            .map(p => ({ value: p.id, label: p.name, icon: 0xf0256, color: Theme.subtext, hint: p.theme })))
    readonly property var statusOptions: [
        { value: "a_faire", label: "À faire", icon: 0xf0766, color: Theme.subtext },
        { value: "en_cours", label: "En cours", icon: 0xf0aa1, color: Theme.blue },
        { value: "en_attente", label: "En attente", icon: 0xf0150, color: Theme.yellow },
        { value: "bloquee", label: "Bloquée", icon: 0xf073a, color: Theme.red },
        { value: "terminee", label: "Terminée", icon: 0xf05e0, color: Theme.green }
    ]
    readonly property var priorityOptions: [
        { value: "auto", label: "Auto", icon: 0xf0068, color: Theme.text },
        { value: "basse", label: "Basse", icon: 0xf0140, color: Theme.blue },
        { value: "normale", label: "Normale", icon: 0xf01fc, color: Theme.subtext },
        { value: "haute", label: "Haute", icon: 0xf0143, color: Theme.peach },
        { value: "urgente", label: "Urgente", icon: 0xf013f, color: Theme.red }
    ]
    readonly property var durationOptions: [{ value: 0, label: "Non estimée", icon: 0xf0377, color: Theme.muted }]
        .concat([15, 30, 45, 60, 90, 120, 180, 240].map(m => ({
            value: m, icon: 0xf051b, color: Theme.subtext,
            label: m < 60 ? m + " min" : Math.floor(m / 60) + " h" + (m % 60 ? " " + (m % 60) : "")
        })))

    readonly property var kindOptions: [
        { value: "tp", label: "TP", icon: 0xf0096, color: Theme.teal },
        { value: "devoir", label: "Devoir", icon: 0xf0cb6, color: Theme.subtext },
        { value: "controle", label: "Contrôle", icon: 0xf0dc9, color: Theme.yellow },
        { value: "epreuve", label: "Épreuve", icon: 0xf002a, color: Theme.red }
    ]
    // Couleur de matière : « var(--accent) » (CSS de l'appli) → blanc
    function courseColor(c) { return /^#[0-9a-f]{3,8}$/i.test(c ?? "") ? c : Theme.text; }
    readonly property var courseOptions: courses.map(c => ({
        value: c.id, label: c.name, icon: 0xf0b64, color: courseColor(c.color)
    }))
    readonly property var hwTeachers: courses.find(c => c.id === hwCourse)?.teachers ?? []
    readonly property var teacherOptions: hwTeachers.map(t => ({
        value: t.id, label: t.name, icon: 0xf0013, color: courseColor(t.color)
    }))

    function opt(list, v) { return list.find(o => o.value === v) ?? list[0]; }

    // --- Formulaire -------------------------------------------------------------------
    property int themeId: -1
    property int projectId: -1
    property string status: "a_faire"
    property string priority: "normale"
    property string plannedDate: ""
    property string dueDate: ""
    property int duration: 0
    property bool busy: false
    property string error: ""

    // Mode « Nouveau devoir »
    property bool homework: false
    property string hwKind: "devoir"
    property int hwCourse: -1
    property int hwTeacher: -1
    property string hwDate: ""
    property bool hwHandIn: true
    property bool hwHandInTouched: false    // réglé à la main : le type ne le change plus
    // Matière à plusieurs profs (Informatique…) : prof obligatoire
    readonly property bool hwNeedsProf: hwTeachers.length > 1
    readonly property bool hwReady: hwCourse >= 0 && (!hwNeedsProf || hwTeacher >= 0) && hwDate !== ""

    function setHomework(on) {
        closeMenu(false);
        error = "";
        homework = on;
        (on ? hwTitleBox : titleBox).input.forceActiveFocus();
    }

    function reset() {
        titleBox.input.text = "";
        linkBox.input.text = "";
        hwTitleBox.input.text = "";
        hwLinkBox.input.text = "";
        notesEdit.text = "";
        homework = false;
        hwKind = "devoir";
        hwCourse = -1;
        hwTeacher = -1;
        hwDate = "";
        hwHandIn = true;
        hwHandInTouched = false;
        themeId = -1;
        projectId = -1;
        status = "a_faire";
        priority = "normale";
        plannedDate = "";
        dueDate = "";
        duration = 0;
        busy = false;
        error = "";
    }

    // --- Ouverture / fermeture -------------------------------------------------
    property bool open: false
    visible: false

    function show() {
        const m = Hyprland.focusedMonitor;
        win.screen = Quickshell.screens.find(s => s.name === m?.name) ?? Quickshell.screens[0];
        closeMenu(false);
        reset();
        closeTimer.stop();
        visible = true;
        open = true;
        titleBox.input.forceActiveFocus();
        metaLoaded = false;
        cachedProc.running = true;
        metaProc.running = true;
    }
    function hide() {
        closeMenu(false);
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    Process {
        id: cachedProc
        command: [Paths.userBin + "/atlas-task", "cached"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (win.metaLoaded) return;
                try {
                    const r = JSON.parse(text);
                    win.themes = r.themes ?? [];
                    win.projects = r.projects ?? [];
                    win.courses = r.courses ?? [];
                } catch (e) {}
            }
        }
    }
    Process {
        id: metaProc
        command: [Paths.userBin + "/atlas-task", "meta"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: "Réponse illisible d'Atlas" }; }
                if (r.error) {
                    if (win.themes.length === 0) win.error = r.error;
                    return;
                }
                win.metaLoaded = true;
                win.themes = r.themes ?? [];
                win.projects = r.projects ?? [];
                win.courses = r.courses ?? [];
            }
        }
    }

    // --- Création ------------------------------------------------------------------
    function fullLink(box) {
        const l = box.input.text.trim();
        return l === "" || /^[a-z][a-z0-9+.-]*:\/\//i.test(l) ? l : "https://" + l;
    }

    function submit() {
        if (busy) return;
        closeMenu(false);
        if (homework) return submitHomework();
        const title = titleBox.input.text.trim();
        if (title === "") {
            error = "Le titre est obligatoire";
            titleBox.input.forceActiveFocus();
            return;
        }
        if (plannedDate && dueDate && plannedDate > dueDate) {
            error = "La date prévue doit précéder l'échéance";
            return;
        }
        const args = { title: title, status: status, priority: priority };
        if (projectId >= 0) args.projectId = projectId;
        if (themeId >= 0) args.themeId = themeId;
        // Atlas exige un thème ou un projet : à défaut, le premier thème (Perso)
        if (projectId < 0 && themeId < 0) {
            if (themes.length === 0) {
                error = "Choisis un thème ou un projet";
                return;
            }
            args.themeId = themes[0].id;
        }
        if (plannedDate) args.plannedDate = plannedDate;
        if (dueDate) args.dueDate = dueDate;
        if (duration > 0) args.durationMin = duration;
        const link = fullLink(linkBox);
        if (link !== "") args.link = link;
        const notes = notesEdit.text.trim();
        if (notes !== "") args.notes = notes;

        error = "";
        busy = true;
        createProc.command = [Paths.userBin + "/atlas-task", "create", JSON.stringify(args)];
        createProc.running = true;
    }
    function submitHomework() {
        if (hwCourse < 0) { error = "Choisis une matière"; return; }
        if (hwNeedsProf && hwTeacher < 0) { error = "Choisis le prof"; return; }
        if (hwDate === "") { error = "Date obligatoire"; return; }
        const args = {
            kind: hwKind,
            kindLabel: opt(kindOptions, hwKind).label,
            courseId: hwCourse,
            title: hwTitleBox.input.text.trim(),
            date: hwDate,
            link: fullLink(hwLinkBox),
            notes: notesEdit.text.trim(),
            toHandIn: hwHandIn
        };
        if (hwTeachers.length === 1) args.teacherId = hwTeachers[0].id;
        else if (hwTeacher >= 0) args.teacherId = hwTeacher;
        error = "";
        busy = true;
        createProc.command = [Paths.userBin + "/atlas-task", "create-exam", JSON.stringify(args)];
        createProc.running = true;
    }
    Process {
        id: createProc
        stdout: StdioCollector {
            onStreamFinished: {
                win.busy = false;
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: "Réponse illisible d'Atlas" }; }
                if (r.error) win.error = r.error;
                else win.hide();
            }
        }
    }

    // Entrée dans un champ une ligne : créer
    Connections { target: titleBox.input; function onAccepted() { win.submit(); } }
    Connections { target: linkBox.input; function onAccepted() { win.submit(); } }
    Connections { target: hwTitleBox.input; function onAccepted() { win.submit(); } }
    Connections { target: hwLinkBox.input; function onAccepted() { win.submit(); } }

    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: win.open
        onActivated: win.submit()
    }
    Shortcut {
        sequence: "Escape"
        enabled: win.open
        onActivated: win.menuAnchor ? win.closeMenu(true) : win.hide()
    }

    // --- Dates ---------------------------------------------------------------------
    readonly property var dayNames: ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    readonly property var monthNames: ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
        "août", "septembre", "octobre", "novembre", "décembre"]
    readonly property var monthShort: ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.",
        "août", "sept.", "oct.", "nov.", "déc."]

    function iso(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }
    function parseIso(s) {
        const p = s.split("-").map(Number);
        return new Date(p[0], p[1] - 1, p[2]);
    }
    function fromToday(n) {
        const d = new Date();
        d.setHours(0, 0, 0, 0);
        d.setDate(d.getDate() + n);
        return d;
    }
    function nextMonday() { return fromToday((8 - new Date().getDay()) % 7 || 7); }
    function dateLabel(s, empty) {
        if (!s) return empty;
        if (s === iso(fromToday(0))) return "Aujourd'hui";
        if (s === iso(fromToday(1))) return "Demain";
        const d = parseIso(s);
        return dayNames[d.getDay()] + " " + d.getDate() + " " + monthShort[d.getMonth()]
            + (d.getFullYear() !== new Date().getFullYear() ? " " + d.getFullYear() : "");
    }

    // --- Menu déroulant / calendrier (un seul ouvert, au-dessus du panneau) ---------------
    property Item menuAnchor: null
    property string menuKind: "list"    // « list » ou « date »
    property var menuOptions: []
    property var menuValue: null
    property var menuPick: null
    property int menuIndex: 0
    property real menuX: 0
    property real menuY: 0
    property real menuW: 0
    property real menuAnchorH: 0
    property int calYear: 2026
    property int calMonth: 0
    property string calSel: ""

    function openList(anchor, options, value, pick) {
        menuKind = "list";
        menuOptions = options;
        menuIndex = Math.max(0, options.findIndex(o => o.value === value));
        placeMenu(anchor, anchor.width);
        menuValue = value;
        menuPick = pick;
    }
    function openDate(anchor, value, pick) {
        menuKind = "date";
        menuValue = value;
        menuPick = pick;
        calSel = value || iso(fromToday(0));
        const d = parseIso(calSel);
        calYear = d.getFullYear();
        calMonth = d.getMonth();
        placeMenu(anchor, Math.max(anchor.width, 310));
    }
    function placeMenu(anchor, w) {
        const p = anchor.mapToItem(overlay, 0, 0);
        menuX = p.x;
        menuY = p.y;
        menuW = w;
        menuAnchorH = anchor.height;
        menuAnchor = anchor;
        menuKeys.forceActiveFocus();
    }
    function closeMenu(refocus) {
        const a = menuAnchor;
        menuAnchor = null;
        if (refocus && a) a.forceActiveFocus();
    }
    function pickMenu(v) {
        const f = menuPick;
        closeMenu(true);
        if (f) f(v);
    }
    function moveCal(days) {
        const d = parseIso(calSel);
        d.setDate(d.getDate() + days);
        calSel = iso(d);
        calYear = d.getFullYear();
        calMonth = d.getMonth();
    }
    function shiftMonth(n) {
        const d = new Date(calYear, calMonth + n, 1);
        calYear = d.getFullYear();
        calMonth = d.getMonth();
    }

    // --- Éléments réutilisés -----------------------------------------------------------
    readonly property color focusBorder: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.6)

    component FormLabel: Text {
        color: Theme.subtext
        font.family: Theme.labelFont
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    // Colonne « libellé + champ » (deux par ligne, largeurs égales)
    component FormField: ColumnLayout {
        id: ff
        property string title
        Layout.fillWidth: true
        Layout.preferredWidth: 100
        Layout.alignment: Qt.AlignTop
        spacing: 7
        FormLabel { text: ff.title; visible: ff.title !== "" }
    }

    // Champ cliquable qui ouvre un menu (icône, valeur, chevron)
    component SelectButton: Rectangle {
        id: sb
        property int icon: 0
        property color iconColor: Theme.subtext
        property string label: ""
        property bool placeholder: false
        property bool menuOpen: false
        signal activated()
        Layout.fillWidth: true
        implicitHeight: 42
        radius: 9
        color: sbMa.containsMouse ? Theme.rowHover : Theme.pill
        border.width: 1
        border.color: activeFocus || sb.menuOpen ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.6) : Theme.pillBorder
        activeFocusOnTab: true
        Behavior on color { ColorAnimation { duration: 120 } }
        Keys.onPressed: event => {
            if ([Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Down].includes(event.key)
                && !(event.modifiers & Qt.ControlModifier)) {
                event.accepted = true;
                sb.activated();
            }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10
            BarText {
                visible: sb.icon !== 0
                text: sb.icon ? Theme.ic(sb.icon) : ""
                font.pixelSize: 17
                color: sb.iconColor
            }
            Text {
                Layout.fillWidth: true
                text: sb.label
                elide: Text.ElideRight
                color: sb.placeholder ? Theme.muted : Theme.text
                font.family: Theme.labelFont
                font.pixelSize: 14
            }
            BarText {
                text: Theme.ic(0xf0140)    // md-chevron-down
                font.pixelSize: 16
                color: Theme.muted
                rotation: sb.menuOpen ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 160 } }
            }
        }
        MouseArea {
            id: sbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                sb.forceActiveFocus();
                sb.activated();
            }
        }
    }

    // Champ texte une ligne avec texte indicatif
    component TextBox: Rectangle {
        id: tb
        property alias input: ti
        property string placeholder: ""
        property int icon: 0
        Layout.fillWidth: true
        implicitHeight: 42
        radius: 9
        color: Theme.pill
        border.width: 1
        border.color: ti.activeFocus ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.6) : Theme.pillBorder
        Behavior on border.color { ColorAnimation { duration: 150 } }
        BarText {
            visible: tb.icon !== 0
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: tb.icon ? Theme.ic(tb.icon) : ""
            font.pixelSize: 16
            color: Theme.muted
        }
        TextInput {
            id: ti
            anchors.fill: parent
            anchors.leftMargin: tb.icon ? 40 : 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            selectionColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4)
            font.family: Theme.labelFont
            font.pixelSize: 14
            clip: true
            selectByMouse: true
            activeFocusOnTab: true
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                elide: Text.ElideRight
                visible: ti.text === ""
                text: tb.placeholder
                color: Theme.muted
                font: ti.font
            }
        }
    }

    // Bouton carré de l'en-tête
    component HeaderButton: Rectangle {
        id: hb
        property int icon: 0
        property bool active: false
        signal clicked()
        implicitWidth: 38
        implicitHeight: 38
        radius: 10
        color: hb.active ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.18)
             : hbMa.containsMouse ? Theme.pillHover : Theme.pill
        border.width: 1
        border.color: hb.active ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.6) : Theme.pillBorder
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: hbMa.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        BarText {
            anchors.centerIn: parent
            text: Theme.ic(hb.icon)
            font.pixelSize: 18
            color: hb.active ? Theme.text : hbMa.containsMouse ? Theme.text : Theme.subtext
        }
        MouseArea {
            id: hbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
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
        width: Math.min(700, parent.width - 60)
        height: Math.min(content.implicitHeight, parent.height - 40)
        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        radius: 16
        color: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.88)
        border.color: Theme.border
        border.width: 1
        clip: true

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.95
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent; onClicked: win.closeMenu(false) }    // ne ferme pas le popup

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            // En-tête
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                Layout.bottomMargin: 14
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: win.homework ? "Nouveau devoir" : "Nouvelle tâche"
                    color: Theme.text
                    font.family: Theme.labelFont
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                }
                // Bascule tâche ↔ devoir
                HeaderButton {
                    icon: win.homework ? 0xf0756 : 0xf1180    // md-format-list-checks / md-school-outline
                    active: win.homework
                    onClicked: win.setHomework(!win.homework)
                }
                HeaderButton {
                    icon: 0xf0156    // md-close
                    onClicked: win.hide()
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                Layout.topMargin: 16
                spacing: 16

                // --- Mode tâche ---
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !win.homework
                    spacing: 16

                FormField {
                    title: "Titre"
                    TextBox { id: titleBox }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    FormField {
                        title: "Thème"
                        SelectButton {
                            id: themeSel
                            menuOpen: win.menuAnchor === themeSel
                            readonly property var o: win.opt(win.themeOptions, win.themeId)
                            icon: win.themeId >= 0 ? o.icon : 0
                            label: o.label
                            placeholder: win.themeId < 0
                            onActivated: win.openList(themeSel, win.themeOptions, win.themeId, v => win.themeId = v)
                        }
                    }
                    FormField {
                        title: "Projet"
                        SelectButton {
                            id: projectSel
                            menuOpen: win.menuAnchor === projectSel
                            readonly property var o: win.opt(win.projectOptions, win.projectId)
                            icon: win.projectId >= 0 ? o.icon : 0
                            label: o.label
                            placeholder: win.projectId < 0
                            onActivated: win.openList(projectSel, win.projectOptions, win.projectId, v => win.projectId = v)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    FormField {
                        title: "Statut"
                        SelectButton {
                            id: statusSel
                            menuOpen: win.menuAnchor === statusSel
                            readonly property var o: win.opt(win.statusOptions, win.status)
                            icon: o.icon
                            iconColor: o.color
                            label: o.label
                            onActivated: win.openList(statusSel, win.statusOptions, win.status, v => win.status = v)
                        }
                    }
                    FormField {
                        title: "Priorité"
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 42
                            Rectangle {
                                id: prioChip
                                readonly property var o: win.opt(win.priorityOptions, win.priority)
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: prioRow.implicitWidth + 22
                                implicitHeight: 32
                                radius: 8
                                color: prioMa.containsMouse || activeFocus || win.menuAnchor === prioChip
                                    ? Theme.pillHover : Qt.rgba(1, 1, 1, 0.1)
                                activeFocusOnTab: true
                                Behavior on color { ColorAnimation { duration: 120 } }
                                function activate() {
                                    win.openList(prioChip, win.priorityOptions, win.priority, v => win.priority = v);
                                    win.menuW = 200;
                                }
                                Keys.onPressed: event => {
                                    if ([Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Down].includes(event.key)
                                        && !(event.modifiers & Qt.ControlModifier)) {
                                        event.accepted = true;
                                        prioChip.activate();
                                    }
                                }
                                RowLayout {
                                    id: prioRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    BarText { text: Theme.ic(prioChip.o.icon); font.pixelSize: 15; color: prioChip.o.color }
                                    Text {
                                        text: prioChip.o.label
                                        color: Theme.text
                                        font.family: Theme.labelFont
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }
                                }
                                MouseArea {
                                    id: prioMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        prioChip.forceActiveFocus();
                                        prioChip.activate();
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    FormField {
                        title: "Prévue le"
                        SelectButton {
                            id: plannedSel
                            menuOpen: win.menuAnchor === plannedSel
                            icon: 0xf0b66    // md-calendar-blank-outline
                            iconColor: win.plannedDate ? Theme.blue : Theme.muted
                            label: win.dateLabel(win.plannedDate, "Pas encore prévue")
                            placeholder: !win.plannedDate
                            onActivated: win.openDate(plannedSel, win.plannedDate, v => win.plannedDate = v)
                        }
                    }
                    FormField {
                        title: "Échéance"
                        SelectButton {
                            id: dueSel
                            menuOpen: win.menuAnchor === dueSel
                            icon: 0xf0b66
                            iconColor: win.dueDate ? Theme.peach : Theme.muted
                            label: win.dateLabel(win.dueDate, "Aucune date")
                            placeholder: !win.dueDate
                            onActivated: win.openDate(dueSel, win.dueDate, v => win.dueDate = v)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    FormField {
                        title: "Durée estimée"
                        SelectButton {
                            id: durationSel
                            menuOpen: win.menuAnchor === durationSel
                            readonly property var o: win.opt(win.durationOptions, win.duration)
                            icon: o.icon
                            iconColor: win.duration > 0 ? Theme.teal : Theme.subtext
                            label: o.label
                            onActivated: win.openList(durationSel, win.durationOptions, win.duration, v => win.duration = v)
                        }
                    }
                    Item { Layout.fillWidth: true; Layout.preferredWidth: 100 }
                }

                FormField {
                    title: "Lien"
                    TextBox { id: linkBox; placeholder: "https://..." }
                }
                }

                // --- Mode devoir : type, matière (+ prof), intitulé + « À rendre », date + lien ---
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: win.homework
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        SelectButton {
                            id: kindSel
                            Layout.preferredWidth: 100
                            menuOpen: win.menuAnchor === kindSel
                            readonly property var o: win.opt(win.kindOptions, win.hwKind)
                            icon: o.icon
                            iconColor: o.color
                            label: o.label
                            onActivated: win.openList(kindSel, win.kindOptions, win.hwKind, v => {
                                win.hwKind = v;
                                if (!win.hwHandInTouched) win.hwHandIn = v === "devoir";
                            })
                        }
                        SelectButton {
                            id: courseSel
                            Layout.preferredWidth: 100
                            menuOpen: win.menuAnchor === courseSel
                            readonly property var o: win.courseOptions.find(c => c.value === win.hwCourse)
                            icon: o ? o.icon : 0
                            iconColor: o ? o.color : Theme.muted
                            label: o ? o.label : (win.courses.length ? "Matière" : "Aucune matière")
                            placeholder: !o
                            onActivated: if (win.courseOptions.length)
                                win.openList(courseSel, win.courseOptions, win.hwCourse, v => {
                                    win.hwCourse = v;
                                    win.hwTeacher = -1;
                                })
                        }
                        SelectButton {
                            id: teacherSel
                            visible: win.hwNeedsProf
                            Layout.preferredWidth: 100
                            menuOpen: win.menuAnchor === teacherSel
                            readonly property var o: win.teacherOptions.find(t => t.value === win.hwTeacher)
                            icon: o ? o.icon : 0
                            iconColor: o ? o.color : Theme.muted
                            label: o ? o.label : "Prof"
                            placeholder: !o
                            onActivated: win.openList(teacherSel, win.teacherOptions, win.hwTeacher, v => win.hwTeacher = v)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        TextBox {
                            id: hwTitleBox
                            icon: 0xf05f4    // md-format-title
                            placeholder: "Intitulé (par défaut : le type)"
                        }
                        // « À rendre » : bouton carré, orangé quand actif
                        Rectangle {
                            id: handIn
                            implicitWidth: 46
                            implicitHeight: 42
                            radius: 9
                            color: win.hwHandIn ? Qt.rgba(Theme.peach.r, Theme.peach.g, Theme.peach.b, 0.18)
                                 : handInMa.containsMouse ? Theme.rowHover : Theme.pill
                            border.width: 1
                            border.color: win.hwHandIn || activeFocus
                                ? Qt.rgba(Theme.peach.r, Theme.peach.g, Theme.peach.b, activeFocus ? 0.9 : 0.6) : Theme.pillBorder
                            activeFocusOnTab: true
                            Behavior on color { ColorAnimation { duration: 140 } }
                            scale: handInMa.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                            function flip() {
                                win.hwHandIn = !win.hwHandIn;
                                win.hwHandInTouched = true;
                            }
                            Keys.onPressed: event => {
                                if ([Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter].includes(event.key)
                                    && !(event.modifiers & Qt.ControlModifier)) {
                                    event.accepted = true;
                                    handIn.flip();
                                }
                            }
                            BarText {
                                anchors.centerIn: parent
                                text: Theme.ic(0xf011d)    // md-tray-arrow-up
                                font.pixelSize: 18
                                color: win.hwHandIn ? Theme.peach : Theme.muted
                            }
                            MouseArea {
                                id: handInMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: handIn.flip()
                            }
                            // Infobulle
                            Rectangle {
                                visible: handInMa.containsMouse
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                implicitWidth: tipText.implicitWidth + 16
                                implicitHeight: 24
                                radius: 6
                                color: Theme.popupBg
                                border.color: Theme.border
                                border.width: 1
                                Text {
                                    id: tipText
                                    anchors.centerIn: parent
                                    text: win.hwHandIn ? "À rendre" : "Pas à rendre"
                                    color: Theme.text
                                    font.family: Theme.labelFont
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        SelectButton {
                            id: hwDateSel
                            Layout.preferredWidth: 100
                            menuOpen: win.menuAnchor === hwDateSel
                            icon: 0xf0b66    // md-calendar-blank-outline
                            iconColor: win.hwDate ? Theme.peach : Theme.muted
                            label: win.dateLabel(win.hwDate, "Date")
                            placeholder: !win.hwDate
                            onActivated: win.openDate(hwDateSel, win.hwDate, v => win.hwDate = v)
                        }
                        TextBox {
                            id: hwLinkBox
                            Layout.preferredWidth: 100
                            icon: 0xf0339    // md-link-variant
                            placeholder: "Lien"
                        }
                    }
                }

                FormField {
                    title: win.homework ? "" : "Notes"
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: win.homework ? 104 : 140
                        radius: 9
                        color: Theme.pill
                        border.width: 1
                        border.color: notesEdit.activeFocus ? win.focusBorder : Theme.pillBorder
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        BarText {
                            visible: win.homework
                            x: 13
                            y: 12
                            text: Theme.ic(0xf09aa)    // md-text-long
                            font.pixelSize: 16
                            color: Theme.muted
                        }
                        Flickable {
                            id: notesFlick
                            anchors.fill: parent
                            anchors.margins: 12
                            anchors.leftMargin: win.homework ? 40 : 12
                            contentHeight: notesEdit.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: notesEdit
                                width: notesFlick.width
                                color: Theme.text
                                selectionColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4)
                                font.family: Theme.labelFont
                                font.pixelSize: 14
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                activeFocusOnTab: true
                                Text {
                                    visible: win.homework && notesEdit.text === ""
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: "Consignes, pages à lire, remarques du prof…"
                                    color: Theme.muted
                                    font: notesEdit.font
                                }
                                Keys.onTabPressed: nextItemInFocusChain().forceActiveFocus()
                                Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus()
                                onCursorRectangleChanged: {
                                    const r = cursorRectangle;
                                    if (r.y < notesFlick.contentY) notesFlick.contentY = r.y;
                                    else if (r.y + r.height > notesFlick.contentY + notesFlick.height)
                                        notesFlick.contentY = r.y + r.height - notesFlick.height;
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            cursorShape: Qt.IBeamCursor
                            onClicked: notesEdit.forceActiveFocus()
                        }
                    }
                }

                // Pied : erreur, raccourcis, boutons
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 10
                    BarText {
                        visible: win.error !== ""
                        text: Theme.ic(0xf05d6)    // md-alert-circle-outline
                        font.pixelSize: 16
                        color: Theme.red
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.error !== "" ? win.error : "Ctrl+Entrée pour créer · Échap pour fermer"
                        color: win.error !== "" ? Theme.red : Theme.muted
                        elide: Text.ElideRight
                        font.family: Theme.labelFont
                        font.pixelSize: 12
                    }
                    Rectangle {
                        implicitWidth: cancelText.implicitWidth + 28
                        implicitHeight: 38
                        radius: 9
                        color: cancelMa.containsMouse ? Theme.pillHover : Theme.pill
                        border.width: 1
                        border.color: Theme.pillBorder
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: cancelText
                            anchors.centerIn: parent
                            text: "Annuler"
                            color: Theme.subtext
                            font.family: Theme.labelFont
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: cancelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.hide()
                        }
                    }
                    Rectangle {
                        implicitWidth: createRow.implicitWidth + 28
                        implicitHeight: 38
                        radius: 9
                        // Devoir incomplet (matière, prof, date) : bouton estompé, comme dans l'appli
                        opacity: win.homework && !win.hwReady ? 0.45 : 1
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        color: win.busy ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.5)
                             : createMa.containsMouse ? Qt.lighter(Theme.text, 1.08) : Theme.text
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: createMa.pressed ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        RowLayout {
                            id: createRow
                            anchors.centerIn: parent
                            spacing: 8
                            BarText {
                                text: Theme.ic(win.busy ? 0xf0150 : 0xf0415)    // md-clock-outline / md-plus
                                font.pixelSize: 16
                                color: "#1e1e2e"
                            }
                            Text {
                                text: win.busy ? "Création…" : win.homework ? "Ajouter le devoir" : "Créer la tâche"
                                color: "#1e1e2e"
                                font.family: Theme.labelFont
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            id: createMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: win.busy ? Qt.BusyCursor : Qt.PointingHandCursor
                            onClicked: win.submit()
                        }
                    }
                }
            }
        }
    }

    // --- Menu ouvert (liste ou calendrier) ------------------------------------------
    Item {
        id: overlay
        anchors.fill: parent
        visible: win.menuAnchor !== null
        z: 10

        // Clic hors du menu : le ferme
        MouseArea { anchors.fill: parent; onClicked: win.closeMenu(true) }

        Item {
            id: menuKeys
            Keys.onPressed: event => {
                if (event.modifiers & Qt.ControlModifier) return;
                event.accepted = true;
                if (win.menuKind === "list") {
                    switch (event.key) {
                    case Qt.Key_Up: win.menuIndex = Math.max(0, win.menuIndex - 1); break;
                    case Qt.Key_Down: win.menuIndex = Math.min(win.menuOptions.length - 1, win.menuIndex + 1); break;
                    case Qt.Key_Home: win.menuIndex = 0; break;
                    case Qt.Key_End: win.menuIndex = win.menuOptions.length - 1; break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space: win.pickMenu(win.menuOptions[win.menuIndex].value); break;
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab: win.closeMenu(true); break;
                    default: event.accepted = false;
                    }
                    listView.positionViewAtIndex(win.menuIndex, ListView.Contain);
                } else {
                    switch (event.key) {
                    case Qt.Key_Left: win.moveCal(-1); break;
                    case Qt.Key_Right: win.moveCal(1); break;
                    case Qt.Key_Up: win.moveCal(-7); break;
                    case Qt.Key_Down: win.moveCal(7); break;
                    case Qt.Key_PageUp: win.shiftMonth(-1); break;
                    case Qt.Key_PageDown: win.shiftMonth(1); break;
                    case Qt.Key_Delete:
                    case Qt.Key_Backspace: win.pickMenu(""); break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space: win.pickMenu(win.calSel); break;
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab: win.closeMenu(true); break;
                    default: event.accepted = false;
                    }
                }
            }
        }

        Rectangle {
            id: menuBox
            readonly property bool below: win.menuY + win.menuAnchorH + 6 + height < overlay.height - 16
            x: Math.min(win.menuX, overlay.width - width - 16)
            y: below ? win.menuY + win.menuAnchorH + 6 : win.menuY - height - 6
            width: win.menuW
            height: (win.menuKind === "list" ? listView.height : cal.implicitHeight) + 12
            radius: 11
            color: Theme.popupBg
            border.color: Theme.border
            border.width: 1

            opacity: overlay.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            MouseArea { anchors.fill: parent }    // le clic dans le menu ne le ferme pas

            // Liste d'options
            ListView {
                id: listView
                visible: win.menuKind === "list"
                x: 6
                y: 6
                width: parent.width - 12
                height: Math.min(contentHeight, 320)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.menuKind === "list" ? win.menuOptions : []
                currentIndex: win.menuIndex
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: listView.width
                    height: 36
                    radius: 7
                    color: index === win.menuIndex ? Theme.rowHover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        BarText {
                            visible: !!row.modelData.icon
                            text: row.modelData.icon ? Theme.ic(row.modelData.icon) : ""
                            font.pixelSize: 16
                            color: row.modelData.color ?? Theme.subtext
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            elide: Text.ElideRight
                            color: row.modelData.value === win.menuValue ? Theme.text : Theme.subtext
                            font.family: Theme.labelFont
                            font.pixelSize: 14
                            font.weight: row.modelData.value === win.menuValue ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            visible: !!row.modelData.hint
                            text: row.modelData.hint ?? ""
                            color: Theme.muted
                            font.family: Theme.labelFont
                            font.pixelSize: 12
                        }
                        BarText {
                            visible: row.modelData.value === win.menuValue
                            text: Theme.ic(0xf012c)    // md-check
                            font.pixelSize: 15
                            color: Theme.text
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.menuIndex = row.index
                        onClicked: win.pickMenu(row.modelData.value)
                    }
                }
            }

            // Calendrier
            ColumnLayout {
                id: cal
                visible: win.menuKind === "date"
                x: 10
                y: 10
                width: parent.width - 20
                spacing: 8

                // Choix rapides
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            ["Aujourd'hui", () => win.iso(win.fromToday(0))],
                            ["Demain", () => win.iso(win.fromToday(1))],
                            ["Lundi prochain", () => win.iso(win.nextMonday())],
                            ["Aucune", () => ""]
                        ]
                        Rectangle {
                            required property var modelData
                            implicitWidth: quickText.implicitWidth + 18
                            implicitHeight: 26
                            radius: 13
                            color: quickMa.containsMouse ? Theme.rowHover : "transparent"
                            border.color: Theme.pillBorder
                            border.width: 1
                            Text {
                                id: quickText
                                anchors.centerIn: parent
                                text: modelData[0]
                                color: quickMa.containsMouse ? Theme.text : Theme.subtext
                                font.family: Theme.labelFont
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: quickMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.pickMenu(modelData[1]())
                            }
                        }
                    }
                }

                // Mois
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    Text {
                        Layout.fillWidth: true
                        leftPadding: 4
                        text: win.monthNames[win.calMonth].charAt(0).toUpperCase() + win.monthNames[win.calMonth].slice(1) + " " + win.calYear
                        color: Theme.text
                        font.family: Theme.labelFont
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: [[0xf0141, -1], [0xf0142, 1]]    // md-chevron-left / right
                        Rectangle {
                            required property var modelData
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 7
                            color: navMa.containsMouse ? Theme.rowHover : "transparent"
                            BarText { anchors.centerIn: parent; text: Theme.ic(modelData[0]); font.pixelSize: 17; color: Theme.subtext }
                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.shiftMonth(modelData[1])
                            }
                        }
                    }
                }

                // Grille des jours (lundi en premier)
                Grid {
                    id: grid
                    Layout.fillWidth: true
                    columns: 7
                    readonly property real cell: Math.floor(width / 7)
                    readonly property date first: {
                        const d = new Date(win.calYear, win.calMonth, 1);
                        return new Date(win.calYear, win.calMonth, 1 - (d.getDay() + 6) % 7);
                    }
                    Repeater {
                        model: ["lu", "ma", "me", "je", "ve", "sa", "di"]
                        Text {
                            required property string modelData
                            width: grid.cell
                            height: 22
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: Theme.muted
                            font.family: Theme.labelFont
                            font.pixelSize: 11
                        }
                    }
                    Repeater {
                        model: 42
                        Rectangle {
                            id: day
                            required property int index
                            readonly property var d: new Date(grid.first.getFullYear(), grid.first.getMonth(), grid.first.getDate() + index)
                            readonly property string s: win.iso(d)
                            readonly property bool inMonth: d.getMonth() === win.calMonth
                            readonly property bool chosen: s === win.menuValue
                            readonly property bool cursor: s === win.calSel
                            readonly property bool today: s === win.iso(win.fromToday(0))
                            width: grid.cell
                            height: 32
                            radius: 8
                            color: chosen ? Theme.text : cursor || dayMa.containsMouse ? Theme.rowHover : "transparent"
                            border.width: today && !chosen ? 1 : 0
                            border.color: Theme.text
                            Text {
                                anchors.centerIn: parent
                                text: day.d.getDate()
                                color: day.chosen ? "#1e1e2e" : day.inMonth ? Theme.text : Theme.muted
                                font.family: Theme.labelFont
                                font.pixelSize: 13
                                font.weight: day.chosen ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                id: dayMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.pickMenu(day.s)
                            }
                        }
                    }
                }
            }
        }
    }
}
