pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Palette et constantes partagées (reprend le style de l'ancienne waybar)
Singleton {
    id: theme

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property string titleFont: "League Spartan"    // titres des menus
    readonly property string trackFont: "Figtree"           // titre du morceau dans la barre
    readonly property string labelFont: "Inter"             // horloge, date, workspaces, Wi-Fi, Bluetooth, % son / CPU / RAM / luminosité
    readonly property int fontSize: 13

    // Fond de barre plus sombre quand le haut du fond d'écran est clair (texte
    // blanc illisible sur gris clair) : 25 % sur fond sombre → 60 % sur fond blanc
    property real wallLum: 0
    readonly property color bg: Qt.rgba(0, 0, 0, 0.25 + 0.35 * Math.max(0, Math.min(1, (wallLum - 0.4) / 0.55)))
    Behavior on wallLum { NumberAnimation { duration: 600 } }

    // Fond changé (wallpaper-apply) → luminosité moyenne de la bande haute de l'image
    FileView {
        path: Paths.wallpaperState
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const f = text().trim();
            if (!f) return;
            lumProc.command = [Paths.magick, f + "[0]", "-gravity", "north", "-crop", "100%x6%+0+0",
                               "+repage", "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"];
            lumProc.running = true;
        }
    }
    Process {
        id: lumProc
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(text);
                if (!isNaN(v)) theme.wallLum = v;
            }
        }
    }

    readonly property color border: Qt.rgba(1, 1, 1, 0.2)
    readonly property color pill: Qt.rgba(1, 1, 1, 0.05)
    readonly property color pillHover: Qt.rgba(1, 1, 1, 0.2)
    readonly property color pillBorder: Qt.rgba(1, 1, 1, 0.1)
    readonly property color popupBg: Qt.rgba(30 / 255, 30 / 255, 30 / 255, 0.94)
    readonly property color rowHover: Qt.rgba(1, 1, 1, 0.08)

    readonly property color text: "#ffffff"
    readonly property color subtext: "#b4b4b4"
    readonly property color muted: "#737373"
    readonly property color blue: "#89b4fa"
    readonly property color sky: "#89dceb"
    readonly property color green: "#a6e3a1"
    readonly property color yellow: "#f9e2af"
    readonly property color peach: "#fab387"
    readonly property color red: "#f38ba8"
    readonly property color pink: "#f5c2e7"
    readonly property color mauve: "#cba6f7"
    readonly property color teal: "#94e2d5"
    readonly property color bluetooth: "#0082fc"   // bleu Bluetooth officiel
    readonly property color spotify: "#1DB954"
    readonly property color youtube: "#ff4444"
    readonly property color soundcloud: "#ff5500"

    // Glyphe Nerd Font à partir de son codepoint (pas de glyphes littéraux dans les sources)
    function ic(cp) { return String.fromCodePoint(cp); }

    function lerpColor(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    function fmtTime(secs) {
        secs = Math.max(0, Math.floor(secs || 0));
        const m = Math.floor(secs / 60), s = secs % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }
}
