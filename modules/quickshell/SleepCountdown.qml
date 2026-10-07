import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// Compte à rebours de sommeil, à droite de l'heure (Clock.qml) ; état dans SleepState.
// Apparaît à 8 h du réveil, rougit, clignote sous 7 h 30. Des bulles « va dormir »
// en sortent (écran actif seulement) ; clic (via Clock) : détail de la nuit.
RowLayout {
    id: root

    property string monitorName: ""
    readonly property bool here: Hyprland.focusedMonitor?.name === monitorName
    readonly property string summary: !SleepState.shown ? ""
        : "Réveil à " + SleepState.hm(SleepState.wakeDate)
          + (SleepState.first ? "  ·  " + SleepState.first.title + " à " + SleepState.first.start : "")

    function toggleDetails() { details.toggle(); }

    spacing: 6

    // Apparition : s'ouvre en largeur depuis l'heure ; masqué : retiré de la pastille
    Layout.preferredWidth: SleepState.shown ? implicitWidth : 0
    Behavior on Layout.preferredWidth { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    opacity: SleepState.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 420 } }
    visible: opacity > 0
    clip: true

    BarText { text: "·"; color: Theme.muted; font.family: Theme.labelFont }
    RowLayout {
        id: badge
        spacing: 4
        BarText {
            text: Theme.ic(0xf04b2)    // md-sleep
            color: SleepState.tint
            Behavior on color { ColorAnimation { duration: 600 } }
        }
        BarText {
            text: SleepState.label
            color: SleepState.tint
            Behavior on color { ColorAnimation { duration: 600 } }
            font.family: Theme.labelFont
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
        // Clignotement de plus en plus rapide : 1,6 s à 7 h 30 → 0,5 s à 5 h 30
        readonly property int period: Math.round(500 + 1100 * Math.max(0, Math.min(1, (SleepState.minutesLeft - 330) / 120)))
        SequentialAnimation on opacity {
            running: SleepState.blinking && !bubble.current
            loops: Animation.Infinite
            NumberAnimation { to: 0.2; duration: badge.period / 2; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: badge.period / 2; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) badge.opacity = 1
        }
        // « Pouf » quand une bulle sort du compteur
        transform: Scale { id: puff; origin.x: badge.width / 2; origin.y: badge.height / 2 }
        SequentialAnimation {
            id: puffAnim
            ParallelAnimation {
                NumberAnimation { target: puff; property: "xScale"; to: 1.25; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { target: puff; property: "yScale"; to: 0.8; duration: 120; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: puff; property: "xScale"; to: 1; duration: 420; easing.type: Easing.OutElastic }
                NumberAnimation { target: puff; property: "yScale"; to: 1; duration: 420; easing.type: Easing.OutElastic }
            }
        }
    }

    // --- Bulle -----------------------------------------------------------------------------
    // Sort du compteur en « bulles de pensée » (3 points qui grossissent puis la bulle qui
    // gonfle), y est ré-aspirée à la fermeture.
    PopupWindow {
        id: bubble

        property var current: null
        // Cachée sur les autres écrans et pendant le détail de la nuit (revient à sa fermeture)
        readonly property var wanted: root.here && !details.visible ? SleepState.bubble : null
        readonly property color accent: current ? (current.farewell ? Theme.mauve : [Theme.mauve, Theme.mauve, Theme.peach, Theme.red, Theme.red][current.level]) : Theme.mauve
        property real grow: 0          // 0 → 1 : gonflement de la bulle
        property real dots: 0          // 0 → 3 : points de la traînée
        property real reveal: 0        // contenu (fondu + texte qui s'écrit)
        property bool leaving: false

        onWantedChanged: {
            if (wanted && (!current || current.id !== wanted.id)) {
                leave.stop();
                leaving = false;
                current = wanted;
                enter.restart();
                if (!wanted.farewell) puffAnim.restart();
            } else if (!wanted && current && !leaving) {
                leaving = true;
                enter.stop();
                leave.restart();
            }
        }

        anchor.item: badge
        anchor.rect.x: 0
        anchor.rect.y: 0
        anchor.rect.width: badge.width
        anchor.rect.height: badge.height + 6
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        visible: current !== null
        color: "transparent"
        implicitWidth: 340
        implicitHeight: body.y + body.height + 10
        mask: Region { item: body }

        SequentialAnimation {
            id: enter
            ScriptAction { script: { bubble.anchor.updateAnchor(); bubble.grow = 0; bubble.dots = 0; bubble.reveal = 0; typing.stop(); msg.typed = 0; countdown.stop(); gauge.remain = 1; } }
            NumberAnimation { target: bubble; property: "dots"; to: 3; duration: 240 }
            NumberAnimation { target: bubble; property: "grow"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            ScriptAction { script: if (bubble.current && bubble.current.level >= 4) shake.restart() }
            ScriptAction { script: typing.restart() }
            NumberAnimation { target: bubble; property: "reveal"; to: 1; duration: 260 }
            ScriptAction { script: if (bubble.current && !bubble.current.sticky) countdown.restart() }
        }
        SequentialAnimation {
            id: leave
            NumberAnimation { target: bubble; property: "reveal"; to: 0; duration: 120 }
            NumberAnimation { target: bubble; property: "grow"; to: 0; duration: 300; easing.type: Easing.InBack }
            NumberAnimation { target: bubble; property: "dots"; to: 0; duration: 200 }
            ScriptAction { script: { bubble.current = null; bubble.leaving = false; } }
        }

        // Traînée : 3 bulles de pensée entre le compteur et la bulle
        Repeater {
            model: [{ y: 0, s: 5 }, { y: 7, s: 8 }, { y: 17, s: 11 }]
            Rectangle {
                required property var modelData
                required property int index
                readonly property real t: Math.max(0, Math.min(1, bubble.dots - index))
                x: (bubble.width - width) / 2 + (index - 1) * 3
                y: modelData.y
                width: modelData.s
                height: width
                radius: width / 2
                color: Theme.popupBg
                border.color: Qt.rgba(bubble.accent.r, bubble.accent.g, bubble.accent.b, 0.6)
                border.width: 1
                scale: t < 1 ? t * 1.3 : 1
                opacity: t
            }
        }

        Rectangle {
            id: body
            y: 34
            x: (bubble.width - width) / 2 + shakeX
            width: bubble.width - 20
            height: content.implicitHeight + 28
            radius: 18
            color: Theme.popupBg
            border.color: Qt.rgba(bubble.accent.r, bubble.accent.g, bubble.accent.b, 0.35 + 0.45 * glow)
            border.width: 1
            transformOrigin: Item.Top
            scale: 0.08 + 0.92 * bubble.grow
            opacity: Math.min(1, bubble.grow * 2)

            property real shakeX: 0
            SequentialAnimation {
                id: shake
                loops: 2
                NumberAnimation { target: body; property: "shakeX"; to: 7; duration: 50 }
                NumberAnimation { target: body; property: "shakeX"; to: -7; duration: 100 }
                NumberAnimation { target: body; property: "shakeX"; to: 0; duration: 50 }
            }
            // Bordure qui respire (niveaux 3-4)
            property real glow: 0
            SequentialAnimation on glow {
                running: bubble.visible && bubble.current !== null && bubble.current.level >= 3
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
            }

            HoverHandler { id: hover }

            RowLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12
                opacity: bubble.reveal

                // Lune + « z » qui s'envolent
                Item {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 38
                    implicitHeight: 38
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: Qt.rgba(bubble.accent.r, bubble.accent.g, bubble.accent.b, 0.16)
                    }
                    BarText {
                        anchors.centerIn: parent
                        text: Theme.ic(0xf0594)    // md-weather_night
                        font.pixelSize: 20
                        color: bubble.accent
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
                            color: bubble.accent
                            x: 26 + p * 10 + index * 2
                            y: 8 - p * 22
                            opacity: p < 0.2 ? p * 5 : 1 - (p - 0.2) / 0.8
                            SequentialAnimation on p {
                                running: bubble.visible
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
                            text: bubble.current?.title ?? ""
                            font.family: Theme.titleFont
                            font.bold: true
                            font.pixelSize: 16
                            color: bubble.accent
                        }
                        BarText {
                            visible: !(bubble.current?.farewell ?? false)
                            text: SleepState.label
                            font.family: Theme.labelFont
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: SleepState.tint
                        }
                    }
                    // Texte qui s'écrit
                    BarText {
                        id: msg
                        Layout.fillWidth: true
                        readonly property string full: bubble.current?.body ?? ""
                        property real typed: 0
                        text: full.slice(0, Math.round(typed))
                        wrapMode: Text.WordWrap
                        font.family: Theme.labelFont
                        font.pixelSize: 12
                        lineHeight: 1.15
                        color: Theme.subtext
                        // Hauteur réservée dès le départ : la bulle ne grandit pas en écrivant
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
                        visible: !(bubble.current?.farewell ?? false)
                        Layout.topMargin: 6
                        spacing: 6
                        ActionButton {
                            icon: Theme.ic(0xf04b2)
                            label: "J'y vais"
                            accent: bubble.accent
                            highlighted: true
                            implicitHeight: 28
                            onClicked: SleepState.goodnight()
                        }
                        ActionButton {
                            icon: Theme.ic(0xf068e)    // md-alarm_snooze
                            label: "Encore 10 min"
                            implicitHeight: 28
                            onClicked: SleepState.snooze()
                        }
                    }
                }
            }

            // Croix
            BarText {
                anchors { top: parent.top; right: parent.right; margins: 10 }
                text: Theme.ic(0xf0156)    // md-close
                font.pixelSize: 12
                color: closeMa.containsMouse ? Theme.text : Theme.muted
                opacity: bubble.reveal
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SleepState.dismiss()
                }
            }

            // Fermeture auto (bulles douces) : jauge qui se vide, en pause au survol
            Rectangle {
                id: gauge
                visible: bubble.current !== null && !bubble.current.sticky
                anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 6; leftMargin: 18 }
                height: 2
                radius: 1
                color: bubble.accent
                opacity: 0.6 * bubble.reveal
                property real remain: 1
                width: (body.width - 36) * remain
                NumberAnimation on remain {
                    id: countdown
                    running: false
                    paused: running && hover.hovered
                    from: 1
                    to: 0
                    duration: bubble.current?.farewell ? 4000 : 14000
                    onFinished: if (bubble.current && !bubble.leaving) SleepState.dismiss()
                }
            }
        }
    }

    // --- Détail de la nuit (clic sur le compteur) --------------------------------------------
    BarPopup {
        id: details
        target: badge
        contentWidth: 320

        readonly property int mins: SleepState.minutesLeft
        readonly property int cycles: SleepState.cycles

        PopupHeader {
            title: "Ta nuit"
            BarText {
                text: "réveil " + SleepState.hm(SleepState.wakeDate)
                color: Theme.subtext
                font.family: Theme.labelFont
                font.pixelSize: 12
            }
        }

        // Temps restant en grand
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 0
            BarText {
                Layout.alignment: Qt.AlignHCenter
                text: SleepState.label
                font.family: Theme.titleFont
                font.bold: true
                font.pixelSize: 38
                color: SleepState.tint
            }
            BarText {
                Layout.alignment: Qt.AlignHCenter
                text: "de sommeil si tu dors maintenant"
                font.family: Theme.labelFont
                font.pixelSize: 11
                color: Theme.subtext
            }
        }

        // Frise de la nuit : endormissement puis cycles de 90 min jusqu'au réveil
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Item {
                id: frise
                Layout.fillWidth: true
                Layout.preferredWidth: details.contentWidth
                implicitHeight: 18
                readonly property var segs: {
                    const out = [], total = Math.max(1, details.mins);
                    let t = Math.min(SleepState.fallAsleep, total);
                    out.push({ start: 0, len: t, kind: "fall" });
                    while (t < total) {
                        const len = Math.min(SleepState.cycle, total - t);
                        out.push({ start: t, len: len, kind: len === SleepState.cycle ? "cycle" : "partial" });
                        t += len;
                    }
                    return out.map(s => Object.assign(s, { total: total }));
                }
                Repeater {
                    model: frise.segs
                    Rectangle {
                        required property var modelData
                        x: frise.width * modelData.start / modelData.total + 1
                        width: Math.max(2, frise.width * modelData.len / modelData.total - 2)
                        height: frise.height
                        radius: 5
                        color: modelData.kind === "cycle" ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.55)
                             : modelData.kind === "partial" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25)
                             : Qt.rgba(1, 1, 1, 0.08)
                        BarText {
                            anchors.centerIn: parent
                            visible: parent.width > 24
                            text: modelData.kind === "fall" ? Theme.ic(0xf04b2) : modelData.kind === "cycle" ? "90" : ""
                            font.family: Theme.labelFont
                            font.pixelSize: 9
                            color: Theme.text
                            opacity: 0.7
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                BarText { text: "maintenant"; font.family: Theme.labelFont; font.pixelSize: 10; color: Theme.muted }
                BarText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: details.cycles + " cycle" + (details.cycles > 1 ? "s" : "") + " complet" + (details.cycles > 1 ? "s" : "")
                    font.family: Theme.labelFont
                    font.pixelSize: 10
                    color: Theme.subtext
                }
                BarText { text: SleepState.hm(SleepState.wakeDate); font.family: Theme.labelFont; font.pixelSize: 10; color: Theme.muted }
            }
        }

        Separator {}

        // Raison du réveil
        Repeater {
            model: {
                const f = SleepState.first, w = SleepState.hm(SleepState.wakeDate);
                if (!f) return [{ icon: 0xf0020, label: "Réveil par défaut", value: w },
                                { icon: 0xf00ed, label: "Aucun événement demain matin", value: "" }];
                const rows = [{ icon: 0xf0020, label: "Réveil", value: w }];
                if (f.leave) rows.push({ icon: 0xf00e7, label: "Départ", value: f.leave });
                rows.push({ icon: 0xf00ed, label: f.title, value: f.start });
                return rows;
            }
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                BarText { text: Theme.ic(modelData.icon); color: Theme.subtext; Layout.preferredWidth: 16 }
                BarText { Layout.fillWidth: true; text: modelData.label; font.family: Theme.labelFont; font.pixelSize: 12; elide: Text.ElideRight }
                BarText { text: modelData.value; font.family: Theme.labelFont; font.pixelSize: 12; font.bold: true; font.features: { "tnum": 1 } }
            }
        }

        Separator {}

        // Heures limites de coucher pour N cycles complets
        BarText {
            text: "Se coucher avant"
            font.family: Theme.labelFont
            font.pixelSize: 11
            color: Theme.muted
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [details.cycles + 1, details.cycles, details.cycles - 1].filter(n => n >= 1)
                Rectangle {
                    id: chip
                    required property int modelData
                    readonly property bool past: modelData > details.cycles
                    readonly property bool next: modelData === details.cycles
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 10
                    color: next ? Qt.rgba(SleepState.tint.r, SleepState.tint.g, SleepState.tint.b, 0.18) : Qt.rgba(1, 1, 1, 0.05)
                    border.color: next ? SleepState.tint : Theme.pillBorder
                    border.width: 1
                    opacity: past ? 0.45 : 1
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: SleepState.hm(SleepState.bedFor(chip.modelData))
                            font.family: Theme.labelFont
                            font.bold: true
                            font.strikeout: chip.past
                            font.features: { "tnum": 1 }
                            color: chip.next ? SleepState.tint : Theme.text
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: chip.modelData + " cycles" + (chip.next ? " · prochain" : chip.past ? " · raté" : "")
                            font.family: Theme.labelFont
                            font.pixelSize: 9
                            color: Theme.subtext
                        }
                    }
                }
            }
        }

        Separator {}

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ActionButton {
                Layout.fillWidth: true
                icon: Theme.ic(0xf04b2)
                label: "Veille"
                accent: Theme.mauve
                onClicked: { details.visible = false; Quickshell.execDetached([Paths.systemctl, "suspend"]); }
            }
            ActionButton {
                Layout.fillWidth: true
                icon: Theme.ic(0xf009b)    // md-bell_off
                label: "Silence 30 min"
                onClicked: { SleepState.goodnightUntil = Date.now() + 30 * 60000; SleepState.dismiss(); details.visible = false; }
            }
        }
    }
}
