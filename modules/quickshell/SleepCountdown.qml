import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Compte à rebours de sommeil, à droite de l'heure (Clock.qml). Réveil calculé par Atlas
// (/api/sleep : premier événement du lendemain − trajet − préparation), 09:00 sans
// événement. Apparaît à 8 h du réveil, rougit à mesure, clignote sous 7 h 30.
RowLayout {
    id: root

    required property date now
    property string wake: "09:00"   // "HH:mm" ; "" = rappel désactivé dans Atlas
    property var first: null        // { title, start, leave } ou null

    readonly property int fullMin: 8 * 60      // nuit idéale : apparition
    readonly property int blinkMin: 7 * 60 + 30
    readonly property int redMin: 6 * 60       // rouge franc à partir d'ici

    readonly property int minutesLeft: {
        if (wake === "") return -1;
        const w = new Date(now);
        w.setHours(Number(wake.slice(0, 2)), Number(wake.slice(3, 5)), 0, 0);
        if (w <= now) w.setDate(w.getDate() + 1);
        return Math.ceil((w - now) / 60000);
    }
    readonly property bool shown: minutesLeft > 0 && minutesLeft <= fullMin
    readonly property bool blinking: shown && minutesLeft < blinkMin
    // 0 à 8 h → 1 à 6 h : du gris clair au rouge
    readonly property real heat: Math.max(0, Math.min(1, (fullMin - minutesLeft) / (fullMin - redMin)))
    readonly property color tint: Qt.rgba(Theme.subtext.r + (Theme.red.r - Theme.subtext.r) * heat,
                                          Theme.subtext.g + (Theme.red.g - Theme.subtext.g) * heat,
                                          Theme.subtext.b + (Theme.red.b - Theme.subtext.b) * heat, 1)
    // Clignotement de plus en plus rapide : 1,6 s à 7 h 30 → 0,5 s à 5 h 30
    readonly property int blinkPeriod: Math.round(500 + 1100 * Math.max(0, Math.min(1, (minutesLeft - 330) / 120)))

    readonly property string label: {
        const h = Math.floor(minutesLeft / 60), m = minutesLeft % 60;
        return h > 0 ? h + "h" + String(m).padStart(2, "0") : m + " min";
    }
    // Ligne ajoutée à l'infobulle de l'horloge
    readonly property string summary: !shown ? ""
        : "Réveil à " + wake + (first ? "  ·  " + first.title + " à " + first.start
                                      + (first.leave ? ", départ " + first.leave : "") : "")

    spacing: 6

    // Apparition : s'ouvre en largeur depuis l'heure ; masqué : retiré de la pastille
    Layout.preferredWidth: shown ? implicitWidth : 0
    Behavior on Layout.preferredWidth { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 420 } }
    visible: opacity > 0
    clip: true

    BarText { text: "·"; color: Theme.muted; font.family: Theme.labelFont }
    RowLayout {
        id: badge
        spacing: 4
        BarText {
            text: Theme.ic(0xf04b2)    // md-sleep
            color: root.tint
            Behavior on color { ColorAnimation { duration: 600 } }
        }
        BarText {
            text: root.label
            color: root.tint
            Behavior on color { ColorAnimation { duration: 600 } }
            font.family: Theme.labelFont
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
        SequentialAnimation on opacity {
            running: root.blinking
            loops: Animation.Infinite
            NumberAnimation { to: 0.2; duration: root.blinkPeriod / 2; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: root.blinkPeriod / 2; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) badge.opacity = 1
        }
    }

    Process {
        id: fetch
        command: [Paths.curl, "-sf", "--max-time", "8", "https://atlas.homelab.lan/api/sleep"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }    // Atlas injoignable : on garde l'ancien réveil
                if (d === null) { root.wake = ""; root.first = null; return; }
                root.first = d.first ?? null;
                root.wake = d.first ? d.wake : "09:00";
            }
        }
    }
    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetch.running = true
    }
}
