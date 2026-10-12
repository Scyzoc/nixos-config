import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// « Dynamic Island » : une pilule noire née de l'horloge (Clock.qml) qui s'étire pour afficher
// un message, puis se rétracte. Deux contenus : le bonjour du jour (GreetingState) et les bulles
// « va dormir » (SleepState.bubble, avec « J'y vais »). Fenêtre superposée à la barre, mêmes
// marges → coordonnées identiques à celles de `clock`.
PanelWindow {
    id: win

    required property ShellScreen modelData
    required property Item clock
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
        width: win.mode === "sleep" ? island.width + 8 : 0
        height: win.mode === "sleep" ? island.height + 8 : 0
    }

    // --- Contenu voulu ---------------------------------------------------------------------
    readonly property var sleepWanted: here && !SleepState.detailsOpen ? SleepState.bubble : null
    readonly property bool greetingWanted: here && GreetingState.active
    onSleepWantedChanged: refresh()
    onGreetingWantedChanged: refresh()

    property bool open: false          // fenêtre affichée
    property string mode: ""           // contenu affiché : "greeting" | "sleep"
    property var cur: null             // bulle de sommeil affichée
    property bool closing: false

    readonly property bool alarm: mode === "sleep" && cur !== null && !cur.farewell && cur.level >= 3
    readonly property color accent: mode === "sleep" && cur
        ? (cur.farewell ? Theme.mauve : SleepState.levelColorFor(cur.level)) : Qt.rgba(1, 1, 1, 1)

    function refresh() {
        const want = sleepWanted ? "sleep" : (greetingWanted ? "greeting" : "");
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
        if (mode === "greeting") holdGreeting.restart();
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
    readonly property real endW: Math.min(mode === "sleep" ? 400 : 380, width - 20)
    property real endH: mode === "sleep" ? sleepBox.implicitHeight + 28 : 72
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
        color: win.alarm ? SleepState.mix(Qt.rgba(0.17, 0.02, 0.04, 1), SleepState.vivid, 0.7 * flash) : "#000000"
        border.color: win.alarm ? SleepState.mix(Qt.rgba(0.55, 0.05, 0.1, 1), SleepState.vivid, glow)
            : win.mode === "sleep" ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.35 + 0.45 * glow)
            : Qt.rgba(1, 1, 1, 0.14)
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

        // --- Bonjour ---
        Column {
            visible: win.mode === "greeting"
            anchors.centerIn: parent
            spacing: 3
            opacity: win.textOpacity
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: GreetingState.title
                color: "#ffffff"
                font.family: Theme.titleFont
                font.pixelSize: 22
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: GreetingState.subtitle
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: Theme.labelFont
                font.pixelSize: 12
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
        onTriggered: GreetingState.active = false
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
        ScriptAction { script: { win.mode = win.sleepWanted ? "sleep" : "greeting"; win.cur = win.sleepWanted; } }
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
