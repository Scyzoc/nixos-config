import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// « Dynamic Island » : une pilule noire née de l'horloge (Clock.qml) qui s'étire pour afficher
// un message, puis se rétracte. Deux contenus : le bonjour du jour (GreetingState) et les bulles
// « va dormir » (SleepState.bubble, avec « J'y vais ») et « Enregistrement terminé » / « Capture copiée » (ScreenState,
// fond gris des menus de la barre, pas noir, lisible sur n'importe quel fond). Fenêtre superposée à la barre, mêmes
// marges → coordonnées identiques à celles de `clock`.
PanelWindow {
    id: win

    required property ShellScreen modelData
    required property var clock
    required property int barHeight
    screen: modelData

    readonly property bool here: Hyprland.focusedMonitor?.name === modelData.name

    WlrLayershell.namespace: "quickshell-island"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true; right: true }
    margins { top: 5; left: 10; right: 10 }
    implicitHeight: 230
    color: "transparent"
    visible: open
    // Cliquable seulement pour une bulle de sommeil (bouton « J'y vais »), sinon transparente aux clics
    mask: Region {
        x: island.x - 4
        y: island.y - 4
        width: win.mode === "sleep" || win.mode === "record" ? island.width + 8 : 0
        height: win.mode === "sleep" || win.mode === "record" ? island.height + 8 : 0
    }

    // --- Contenu voulu ---------------------------------------------------------------------
    readonly property var sleepWanted: here && !SleepState.detailsOpen ? SleepState.bubble : null
    readonly property bool greetingWanted: here && GreetingState.active
    readonly property bool recordWanted: here && ScreenState.doneFile !== ""
    onSleepWantedChanged: refresh()
    onGreetingWantedChanged: refresh()
    onRecordWantedChanged: refresh()

    // L'île « pastille » est translucide : l'heure en dessous est masquée tant qu'elle est là
    Binding { target: win.clock; property: "opacity"; value: 0; when: win.open && win.mode === "record" }

    property bool open: false          // fenêtre affichée
    property string mode: ""           // contenu affiché : "greeting" | "sleep" | "record"
    property var cur: null             // bulle de sommeil affichée
    property bool closing: false

    readonly property bool alarm: mode === "sleep" && cur !== null && !cur.farewell && cur.level >= 3
    readonly property color accent: mode === "sleep" && cur
        ? (cur.farewell ? Theme.mauve : SleepState.levelColorFor(cur.level)) : Qt.rgba(1, 1, 1, 1)

    function refresh() {
        const want = sleepWanted ? "sleep" : (greetingWanted ? "greeting" : (recordWanted ? "record" : ""));
        if (want === "") {
            if (open && !closing) close();
            return;
        }
        if (!open || closing) {
            closeAnim.stop();
            closing = false;
            mode = want;
            cur = sleepWanted;
            open = true;
            openAnim.restart();
        } else if (mode !== want || (want === "sleep" && cur && cur.id !== sleepWanted.id)) {
            swapAnim.restart();     // change de contenu sans refermer l'île
        }
    }
    function close() {
        closing = true;
        openAnim.stop();
        swapAnim.stop();
        holdGreeting.stop();
        countdown.stop();
        closeAnim.restart();
    }
    // Contenu affiché : démarre ses minuteries (frappe du texte, durée du bonjour, jauge d'au revoir)
    function shown() {
        typing.stop();
        msg.typed = 0;
        countdown.stop();
        gauge.remain = 1;
        holdGreeting.stop();
        if (mode === "greeting" || mode === "record") holdGreeting.restart();
        else if (mode === "sleep") {
            if (alarm) island.hit();
            typing.restart();
            if (cur && !cur.sticky) countdown.restart();
        }
    }

    // --- Géométrie : départ = pastille de l'horloge, arrivée = grande pilule centrée dessus ---
    readonly property real startW: clock.width
    readonly property real startH: clock.height
    readonly property real startX: clock.x
    readonly property real startY: (barHeight - clock.height) / 2
    // Largeur : celle du contenu (bonjour) ou fixe (bulle de sommeil, texte à la ligne)
    readonly property Item contentRow: mode === "record" ? recRow : greetRow
    readonly property bool shotMenu: mode === "record" && ScreenState.menuOpen
    property real endW: Math.min(mode === "sleep" ? 400 : Math.max(contentRow.implicitWidth + 52, shotMenu ? shotActions.implicitWidth + 28 : 0), width - 20)
    Behavior on endW { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    property real endH: mode === "sleep" ? sleepBox.implicitHeight + 28 : mode === "record" ? (shotMenu ? 84 : 36) : 68
    Behavior on endH { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    readonly property real endX: Math.max(0, Math.min(width - endW, startX + startW / 2 - endW / 2))

    property real grow: 0           // 0 = pastille de l'horloge, 1 = pilule ouverte
    property real pillOpacity: 0
    property real textOpacity: 0

    Rectangle {
        id: ring
        // Onde de choc des alarmes
        property real wave: 1
        anchors.centerIn: island
        width: island.width + wave * 36
        height: island.height + wave * 24
        radius: island.radius + wave * 10
        color: "transparent"
        border.width: 3
        border.color: SleepState.vivid
        opacity: win.alarm ? (1 - wave) * 0.85 * win.pillOpacity : 0
    }

    Rectangle {
        id: island
        x: win.startX + (win.endX - win.startX) * win.grow + shakeX
        y: win.startY
        width: win.startW + (win.endW - win.startW) * win.grow
        height: win.startH + (win.endH - win.startH) * win.grow
        radius: Math.min(height / 2, 10 + 26 * win.grow)
        clip: true
        // Alarme : fond rouge sombre, flash rouge vif à chaque « coup »
        color: win.alarm ? SleepState.mix(Qt.rgba(0.17, 0.02, 0.04, 1), SleepState.vivid, 0.7 * flash)
            : win.mode === "record" ? (hover.hovered ? Qt.rgba(48 / 255, 48 / 255, 48 / 255, 0.96) : Theme.popupBg) : "#000000"
        border.color: win.alarm ? SleepState.mix(Qt.rgba(0.55, 0.05, 0.1, 1), SleepState.vivid, glow)
            : win.mode === "sleep" ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.35 + 0.45 * glow)
            : win.mode === "record" ? Theme.pillBorder : Qt.rgba(1, 1, 1, 0.14)
        border.width: win.alarm ? 2 : 1
        opacity: win.pillOpacity

        property real flash: 0
        property real shakeX: 0
        property real glow: 0
        // Coup : flash + secousse + onde de choc
        function hit() { shake.restart(); flashAnim.restart(); waveAnim.restart(); }
        NumberAnimation { id: flashAnim; target: island; property: "flash"; from: 1; to: 0; duration: 550; easing.type: Easing.OutCubic }
        NumberAnimation { id: waveAnim; target: ring; property: "wave"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
        SequentialAnimation {
            id: shake
            loops: 3
            NumberAnimation { target: island; property: "shakeX"; to: 10; duration: 45 }
            NumberAnimation { target: island; property: "shakeX"; to: -10; duration: 90 }
            NumberAnimation { target: island; property: "shakeX"; to: 0; duration: 45 }
        }
        // Tant qu'elle est là, elle insiste : un coup toutes les 3,5 s (1,8 s sous 6 h)
        Timer {
            running: win.alarm && win.textOpacity === 1 && !win.closing
            interval: win.cur && win.cur.level >= 4 ? 1800 : 3500
            repeat: true
            onTriggered: island.hit()
        }
        // Bordure qui respire (niveaux 3-4)
        SequentialAnimation on glow {
            running: win.open && win.mode === "sleep" && win.cur !== null && win.cur.level >= 3
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 400; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 400; easing.type: Easing.InOutSine }
        }

        HoverHandler { id: hover }

        // --- Bonjour : icône météo à gauche, texte à droite ---
        Row {
            id: greetRow
            visible: win.mode === "greeting"
            anchors.centerIn: parent
            spacing: 14
            opacity: win.textOpacity
            Column {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.clock.weatherSym !== ""
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.clock.weatherGlyph(win.clock.weatherSym)
                    color: "#ffffff"
                    font.family: Theme.font
                    font.pixelSize: 30
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.clock.weatherTemp
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.family: Theme.labelFont
                    font.pixelSize: 11
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.clock.weatherSym !== ""
                width: 1
                height: 36
                color: Qt.rgba(1, 1, 1, 0.16)
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: GreetingState.title
                    color: "#ffffff"
                    font.family: Theme.titleFont
                    font.pixelSize: 22
                    font.bold: true
                }
                Text {
                    text: GreetingState.subtitle
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.family: Theme.labelFont
                    font.pixelSize: 12
                }
            }
        }

        // --- Enregistrement terminé / capture d'écran (style pastille) : clic = ouvrir le dossier de la vidéo ---
        Row {
            id: recRow
            visible: win.mode === "record"
            anchors.horizontalCenter: parent.horizontalCenter
            y: (36 - height) / 2
            spacing: 8
            opacity: win.textOpacity
            // Enregistrement : écran (contour blanc + pied) avec une coche verte, qui rebondit
            Item {
                id: badge
                visible: ScreenState.doneKind !== "shot"
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                Rectangle {
                    x: 1
                    y: 2
                    width: 20
                    height: 14
                    radius: 3
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.text
                }
                Rectangle {    // pied
                    x: 7
                    y: 19
                    width: 8
                    height: 2
                    radius: 1
                    color: Theme.text
                }
                Text {
                    id: badgeCheck
                    x: (parent.width - width) / 2
                    y: 9 - height / 2
                    text: Theme.ic(0xf012c)    // md-check
                    color: Theme.green
                    font.family: Theme.font
                    font.pixelSize: 14
                }
                SequentialAnimation {
                    running: win.mode === "record" && win.textOpacity > 0 && badge.visible
                    PropertyAction { target: badgeCheck; property: "scale"; value: 0.3 }
                    PauseAnimation { duration: 80 }
                    NumberAnimation { target: badgeCheck; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                }
            }
            // Capture d'écran : cadre de visée (quatre coins) avec une coche verte au centre
            Item {
                id: frame
                visible: ScreenState.doneKind === "shot"
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                readonly property int arm: 7
                readonly property int th: 2
                Repeater {
                    model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                    Item {
                        required property var modelData
                        x: modelData[0] * (frame.width - frame.arm)
                        y: modelData[1] * (frame.height - frame.arm)
                        width: frame.arm
                        height: frame.arm
                        Rectangle {    // branche horizontale
                            width: frame.arm
                            height: frame.th
                            radius: 1
                            color: Theme.text
                            y: modelData[1] ? frame.arm - frame.th : 0
                        }
                        Rectangle {    // branche verticale
                            width: frame.th
                            height: frame.arm
                            radius: 1
                            color: Theme.text
                            x: modelData[0] ? frame.arm - frame.th : 0
                        }
                    }
                }
                Text {
                    id: frameCheck
                    anchors.centerIn: parent
                    text: Theme.ic(0xf012c)    // md-check
                    color: Theme.green
                    font.family: Theme.font
                    font.pixelSize: 14
                }
                SequentialAnimation {
                    running: win.mode === "record" && win.textOpacity > 0 && frame.visible
                    PropertyAction { target: frameCheck; property: "scale"; value: 0.3 }
                    PauseAnimation { duration: 80 }
                    NumberAnimation { target: frameCheck; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ScreenState.doneLabel
                color: Theme.text
                font.family: Theme.labelFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            // Capture : bouton qui déroule le menu d'actions
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.ic(0xf0140)    // md-chevron_down
                color: Theme.subtext
                font.family: Theme.font
                font.pixelSize: 16
                rotation: win.shotMenu ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }
        }
        // Menu déroulant : enregistrer sous / dessiner (la capture est déjà copiée)
        Row {
            id: shotActions
            anchors.horizontalCenter: parent.horizontalCenter
            y: 42
            spacing: 6
            opacity: win.shotMenu ? win.textOpacity : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            ActionButton {
                icon: Theme.ic(0xf0193)    // md-content_save (enregistrer sous)
                iconSize: 17
                implicitWidth: 40
                implicitHeight: 30
                enabled: win.shotMenu
                onClicked: ScreenState.shotAction("save")
            }
            ActionButton {
                visible: ScreenState.doneKind === "record"
                icon: Theme.ic(0xf018f)    // md-content_copy (copier la vidéo)
                iconSize: 17
                implicitWidth: 40
                implicitHeight: 30
                enabled: win.shotMenu
                onClicked: ScreenState.shotAction("copy")
            }
            ActionButton {
                visible: ScreenState.doneKind === "record"
                icon: Theme.ic(0xf0770)    // md-folder_open (ouvrir le dossier)
                iconSize: 17
                implicitWidth: 40
                implicitHeight: 30
                enabled: win.shotMenu
                onClicked: ScreenState.shotAction("folder")
            }
            ActionButton {
                visible: ScreenState.doneKind === "shot"
                icon: Theme.ic(0xf03eb)    // md-pencil (dessiner)
                iconSize: 17
                implicitWidth: 40
                implicitHeight: 30
                enabled: win.shotMenu
                onClicked: ScreenState.shotAction("draw")
            }
            ActionButton {
                visible: ScreenState.doneKind === "shot"
                icon: Theme.ic(0xf113d)    // md-text_recognition (extraire le texte)
                iconSize: 17
                implicitWidth: 40
                implicitHeight: 30
                enabled: win.shotMenu
                onClicked: ScreenState.shotAction("ocr")
            }
        }
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 36
            enabled: win.mode === "record" && win.textOpacity === 1
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                ScreenState.menuOpen = !ScreenState.menuOpen;
                if (ScreenState.menuOpen) holdGreeting.stop();
                else holdGreeting.restart();
            }
        }

        // --- Bulle « va dormir » ---
        RowLayout {
            id: sleepBox
            visible: win.mode === "sleep"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12
            opacity: win.textOpacity

            // Lune + « z » qui s'envolent
            Item {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 38
                implicitHeight: 38
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16)
                }
                BarText {
                    anchors.centerIn: parent
                    text: Theme.ic(0xf0594)    // md-weather_night
                    font.pixelSize: 20
                    color: win.accent
                }
                Repeater {
                    model: 3
                    BarText {
                        id: zz
                        required property int index
                        property real p: 0
                        text: "z"
                        font.family: Theme.labelFont
                        font.bold: true
                        font.pixelSize: 8 + index * 2
                        color: win.accent
                        x: 26 + p * 10 + index * 2
                        y: 8 - p * 22
                        opacity: p < 0.2 ? p * 5 : 1 - (p - 0.2) / 0.8
                        SequentialAnimation on p {
                            running: win.open && win.mode === "sleep"
                            loops: Animation.Infinite
                            PauseAnimation { duration: zz.index * 600 }
                            NumberAnimation { from: 0; to: 1; duration: 1800; easing.type: Easing.OutSine }
                            PauseAnimation { duration: (2 - zz.index) * 600 }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    BarText {
                        Layout.fillWidth: true
                        text: win.cur?.title ?? ""
                        font.family: Theme.titleFont
                        font.bold: true
                        font.pixelSize: win.alarm ? 19 : 16
                        font.capitalization: win.alarm ? Font.AllUppercase : Font.MixedCase
                        color: win.alarm ? "#ffffff" : win.accent
                    }
                    BarText {
                        visible: !(win.cur?.farewell ?? false)
                        text: SleepState.label
                        font.family: Theme.labelFont
                        font.features: { "tnum": 1 }
                        font.weight: win.alarm ? Font.Black : Font.DemiBold
                        color: win.alarm ? "#ffffff" : SleepState.tint
                    }
                }
                // Texte qui s'écrit
                BarText {
                    id: msg
                    Layout.fillWidth: true
                    readonly property string full: win.cur?.body ?? ""
                    property real typed: 0
                    text: full.slice(0, Math.round(typed))
                    wrapMode: Text.WordWrap
                    font.family: Theme.labelFont
                    font.pixelSize: 12
                    lineHeight: 1.15
                    color: win.alarm ? "#ffd9df" : Theme.subtext
                    // Hauteur réservée dès le départ : l'île ne grandit pas en écrivant
                    Layout.preferredHeight: ghost.implicitHeight
                    Text {
                        id: ghost
                        visible: false
                        width: msg.width
                        text: msg.full
                        wrapMode: Text.WordWrap
                        font: msg.font
                        lineHeight: 1.15
                    }
                    NumberAnimation on typed {
                        id: typing
                        running: false
                        from: 0
                        to: msg.full.length
                        duration: msg.full.length * 22
                    }
                }
                RowLayout {
                    visible: !(win.cur?.farewell ?? false)
                    Layout.topMargin: 6
                    spacing: 6
                    ActionButton {
                        icon: Theme.ic(0xf04b2)
                        label: "J'y vais"
                        accent: win.accent
                        highlighted: true
                        implicitHeight: 28
                        onClicked: SleepState.goodnight()
                    }
                }
            }
        }

        // Fermeture auto (bulle d'au revoir seulement) : jauge qui se vide
        Rectangle {
            id: gauge
            visible: win.mode === "sleep" && win.cur !== null && !win.cur.sticky
            anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 6; leftMargin: 18 }
            height: 2
            radius: 1
            color: win.accent
            opacity: 0.6 * win.textOpacity
            property real remain: 1
            width: (island.width - 36) * remain
            NumberAnimation on remain {
                id: countdown
                running: false
                paused: running && hover.hovered
                from: 1
                to: 0
                duration: 4000
                onFinished: if (win.mode === "sleep" && !win.closing) SleepState.dismiss()
            }
        }
    }

    // Durée du bonjour
    Timer {
        id: holdGreeting
        interval: 4800
        onTriggered: {
            if (win.mode === "record") ScreenState.doneFile = "";
            else GreetingState.active = false;
        }
    }

    // --- Séquences -------------------------------------------------------------------------
    // Ouverture : la pilule noire recouvre l'horloge, s'étire (rebond doux, comme iOS), puis le texte
    SequentialAnimation {
        id: openAnim
        NumberAnimation { target: win; property: "pillOpacity"; to: 1; duration: 180 }
        NumberAnimation { target: win; property: "grow"; to: 1; duration: 650; easing.type: Easing.OutBack; easing.overshoot: win.alarm ? 2.6 : 1.1 }
        NumberAnimation { target: win; property: "textOpacity"; to: 1; duration: 260 }
        ScriptAction { script: win.shown() }
    }
    // Changement de contenu : le texte s'efface, l'île s'ajuste, le nouveau texte arrive
    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: win; property: "textOpacity"; to: 0; duration: 140 }
        ScriptAction { script: { win.mode = win.sleepWanted ? "sleep" : (win.greetingWanted ? "greeting" : "record"); win.cur = win.sleepWanted; } }
        PauseAnimation { duration: 200 }
        NumberAnimation { target: win; property: "textOpacity"; to: 1; duration: 220 }
        ScriptAction { script: win.shown() }
    }
    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: win; property: "textOpacity"; to: 0; duration: 200 }
        NumberAnimation { target: win; property: "grow"; to: 0; duration: 520; easing.type: Easing.InOutCubic }
        NumberAnimation { target: win; property: "pillOpacity"; to: 0; duration: 180 }
        ScriptAction { script: { win.open = false; win.closing = false; win.mode = ""; win.cur = null; win.refresh(); } }
    }

    Component.onCompleted: refresh()
}
