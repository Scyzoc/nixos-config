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
    // Coupé seulement pendant l'ouverture : battement et onde débordent ensuite
    clip: Layout.preferredWidth < implicitWidth - 0.5

    BarText { text: "·"; color: Theme.muted; font.family: Theme.labelFont }
    Item {
        id: badge
        // Sous 7 h : capsule rouge vif pleine qui bat comme un cœur, onde autour à chaque
        // battement ; sous 6 h : battement plus rapide + secousse
        readonly property bool alarm: SleepState.alarm
        // 7 h 30 → 7 h : capsule rouge translucide cerclée de rouge vif (avant la capsule pleine)
        readonly property bool warn: SleepState.blinking && !alarm
        property real pad: alarm || warn ? 8 : 0
        Behavior on pad { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
        implicitWidth: inner.implicitWidth + pad * 2
        implicitHeight: 20
        property real beat: 0      // 0 → 1 : battement
        property real ring: 1      // 0 → 1 : onde qui s'élargit (1 = éteinte)
        property real shakeX: 0
        scale: 1 + 0.14 * beat

        Rectangle {
            id: halo
            visible: badge.alarm
            anchors.centerIn: parent
            width: parent.width + badge.ring * 18
            height: parent.height + badge.ring * 10
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: SleepState.vivid
            opacity: (1 - badge.ring) * 0.9
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: badge.alarm ? SleepState.mix(Qt.rgba(0.43, 0, 0.07, 1), SleepState.vivid, 0.45 + 0.55 * badge.beat)
                               : Qt.rgba(SleepState.vivid.r, SleepState.vivid.g, SleepState.vivid.b, 0.22)
            border.width: badge.warn ? 1.5 : 0
            border.color: SleepState.vivid
            opacity: badge.alarm || badge.warn ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
        RowLayout {
            id: inner
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: badge.shakeX
            spacing: 4
            BarText {
                text: Theme.ic(0xf04b2)    // md-sleep
                color: badge.alarm ? "#ffffff" : SleepState.tint
                Behavior on color { ColorAnimation { duration: 400 } }
            }
            BarText {
                text: SleepState.label
                color: badge.alarm ? "#ffffff" : SleepState.tint
                Behavior on color { ColorAnimation { duration: 400 } }
                font.family: Theme.labelFont
                font.weight: badge.alarm || badge.warn ? Font.Black : Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }

        // 7 h 30 → 7 h : clignotement de plus en plus rapide (1,2 s → 0,5 s)
        readonly property int period: Math.round(500 + 700 * Math.max(0, Math.min(1, (SleepState.minutesLeft - 420) / 30)))
        SequentialAnimation on opacity {
            running: SleepState.blinking && !badge.alarm && !SleepState.bubble
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: badge.period / 2; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: badge.period / 2; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) badge.opacity = 1
        }
        // Sous 7 h : double battement (boum-boum) + onde ; sous 6 h plus rapide et secoué
        SequentialAnimation {
            running: badge.alarm
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: badge; property: "beat"; to: 1; duration: 90; easing.type: Easing.OutQuad }
                NumberAnimation { target: badge; property: "ring"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    NumberAnimation { target: badge; property: "shakeX"; to: SleepState.panic ? 3 : 0; duration: 40 }
                    NumberAnimation { target: badge; property: "shakeX"; to: SleepState.panic ? -3 : 0; duration: 80 }
                    NumberAnimation { target: badge; property: "shakeX"; to: SleepState.panic ? 2 : 0; duration: 60 }
                    NumberAnimation { target: badge; property: "shakeX"; to: 0; duration: 40 }
                }
            }
            NumberAnimation { target: badge; property: "beat"; to: 0.35; duration: 110 }
            NumberAnimation { target: badge; property: "beat"; to: 0.9; duration: 80; easing.type: Easing.OutQuad }
            NumberAnimation { target: badge; property: "beat"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            PauseAnimation { duration: SleepState.panic ? 100 : 500 }
            onRunningChanged: if (!running) { badge.beat = 0; badge.ring = 1; badge.shakeX = 0; }
        }
    }

    // --- Détail de la nuit (clic sur le compteur) --------------------------------------------
    BarPopup {
        id: details
        onVisibleChanged: SleepState.detailsOpen = visible
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
        }
    }
}
