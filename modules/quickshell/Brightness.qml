import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Luminosité : pastille masquée, affichée quelques secondes quand la luminosité change
// (touches, brightnessctl, économie d'énergie…) ; molette dessus = ±5 %
Pill {
    id: root

    // Rétroéclairage : premier de /sys/class/backlight (le numéro amdgpu_blN peut changer)
    property string dev: ""
    Process {
        running: true
        command: ["/bin/sh", "-c", "for d in /sys/class/backlight/*; do [ -e \"$d/brightness\" ] && echo \"$d\" && break; done"]
        stdout: StdioCollector { onStreamFinished: root.dev = text.trim() }
    }

    property int max: 0
    property int raw: -1
    // Pourcentage « perçu », comme les touches (brightnessctl -e4 : pas de 5 % réguliers)
    readonly property real level: max > 0 && raw >= 0 ? Math.pow(raw / max, 1 / 4) : 0

    FileView {
        path: root.dev ? root.dev + "/max_brightness" : ""
        printErrors: false
        onLoaded: root.max = parseInt(text())
    }
    // Écriture dans le fichier sysfs (brightnessctl) → notification inotify → relecture
    FileView {
        path: root.dev ? root.dev + "/brightness" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text());
            if (isNaN(v) || v === root.raw) return;
            const first = root.raw < 0;
            root.raw = v;
            if (!first) root.flash();    // pas d'affichage au démarrage de la barre
        }
    }

    // --- Affichage temporaire ------------------------------------------------------
    property bool shown: false
    function flash() {
        shown = true;
        hideTimer.restart();
    }
    Timer {
        id: hideTimer
        interval: 2500
        // Gardée tant que la souris est dessus
        onTriggered: root.hovered ? restart() : root.shown = false
    }

    // Apparition : la pastille s'ouvre en largeur ; masquée : retirée de la barre
    Layout.preferredWidth: shown ? implicitWidth : 0
    Behavior on Layout.preferredWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }
    visible: opacity > 0
    clip: true

    // Icône et couleur selon l'intensité : lune bleutée la nuit → soleil jaune vif
    function icon(l) {
        if (l < 0.2) return Theme.ic(0xf0594);     // md-weather_night
        if (l < 0.4) return Theme.ic(0xf00dd);     // md-brightness_4
        if (l < 0.6) return Theme.ic(0xf00de);     // md-brightness_5
        if (l < 0.8) return Theme.ic(0xf00df);     // md-brightness_6
        return Theme.ic(0xf00e0);                  // md-brightness_7
    }
    readonly property var stops: [Theme.blue, Theme.mauve, Theme.peach, Theme.yellow, "#fff6d5"]
    function colorAt(l) {
        const t = Math.max(0, Math.min(1, l)) * (stops.length - 1);
        const i = Math.min(stops.length - 2, Math.floor(t));
        return Theme.lerpColor(Qt.color(stops[i]), Qt.color(stops[i + 1]), t - i);
    }
    readonly property color tint: colorAt(level)

    BarText { text: root.icon(root.level); color: root.tint }
    // Jauge
    Rectangle {
        implicitWidth: root.compact ? 36 : 56
        implicitHeight: 5
        radius: 2.5
        color: Qt.rgba(1, 1, 1, 0.12)
        Rectangle {
            width: parent.width * root.level
            height: parent.height
            radius: parent.radius
            color: root.tint
            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }
    BarText {
        visible: !root.compact
        text: Math.round(root.level * 100) + "%"
        color: root.tint
        font.family: Theme.labelFont
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
        Layout.preferredWidth: 36    // largeur fixe : la barre ne bouge pas entre 9 % et 100 %
    }

    onScrolled: event => Quickshell.execDetached([Paths.brightnessctl, "-q", "-e4", "-n2", "set",
                                                  event.angleDelta.y > 0 ? "5%+" : "5%-"])
}
