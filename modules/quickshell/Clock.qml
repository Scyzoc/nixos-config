import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Heure + météo + compte à rebours de sommeil ; clic : calendrier ; clic droit : calendrier Notion
Pill {
    id: root

    property string weatherIcon: ""      // emoji (pastille de la barre)
    property string weatherSym: ""       // symbole texte wttr (%x) → icône monochrome du menu
    property string weatherCond: ""
    property string weatherTemp: ""
    property string weatherFeels: ""
    property string weatherWind: ""
    property string weatherHum: ""

    // Symbole wttr (%x) → icône Nerd Font md-weather-*
    function weatherGlyph(sym) {
        if (sym === "o") return Theme.ic(0xf0599);                          // soleil
        if (sym === "m") return Theme.ic(0xf0595);                          // éclaircies
        if (sym === "mm" || sym === "mmm") return Theme.ic(0xf0590);        // nuageux
        if (sym === "=") return Theme.ic(0xf0591);                          // brouillard
        if (sym.indexOf("!") >= 0) return Theme.ic(0xf067e);                // orage
        if (sym.indexOf("x") >= 0) return Theme.ic(0xf067f);                // neige fondue
        if (sym.indexOf("*") >= 0) return Theme.ic(sym === "**" ? 0xf0f36 : 0xf0598); // neige
        if (sym === "///" || sym === "//") return Theme.ic(0xf0596);        // forte pluie
        if (sym === "/" || sym === ".") return Theme.ic(0xf0597);           // pluie
        return Theme.ic(0xf0590);
    }
    // "+29°C" → "29°C" ; "↑17km/h" → "17 km/h"
    function cleanTemp(t) { return t.replace(/^\+/, ""); }
    function cleanWind(w) { return w.replace(/^[^0-9]+/, "").replace("km/h", " km/h"); }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    tooltip: {
        const d = clock.date.toLocaleDateString(Qt.locale("fr_FR"), "dddd d MMMM yyyy");
        const w = root.weatherCond ? root.weatherCond + "  ·  " + root.cleanTemp(root.weatherTemp) : "";
        return d.charAt(0).toUpperCase() + d.slice(1) + (w ? "\n" + w : "")
             + (sleep.summary ? "\n" + sleep.summary : "");
    }

    Process {
        id: weatherProc
        command: [Paths.curl, "-s", "--max-time", "6", "wttr.in/Paris?lang=fr&format=%c|%C|%t|%f|%w|%h|%x"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("|");
                if (p.length < 7 || p[0] === "" || text.indexOf("Unknown") >= 0) return;
                root.weatherIcon = p[0].trim();
                root.weatherCond = p[1].trim();
                root.weatherTemp = root.cleanTemp(p[2].trim());
                root.weatherFeels = root.cleanTemp(p[3].trim());
                root.weatherWind = root.cleanWind(p[4].trim());
                root.weatherHum = p[5].trim();
                root.weatherSym = p[6].trim();
            }
        }
    }
    Timer {
        // 15 min, ou 1 min tant que la météo n'a pas pu être chargée
        interval: root.weatherIcon === "" ? 60000 : 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }

    BarText { visible: root.weatherIcon !== ""; text: root.weatherIcon }
    // Chiffres à chasse fixe (tnum) : la pastille ne bouge pas quand l'heure change
    BarText { text: Qt.formatDateTime(clock.date, "dd/MM"); color: Theme.subtext; font.family: Theme.labelFont; font.features: { "tnum": 1 } }
    BarText { text: "·"; color: Theme.muted; font.family: Theme.labelFont }
    BarText { text: Qt.formatDateTime(clock.date, "HH:mm"); font.family: Theme.labelFont; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
    SleepCountdown { id: sleep; now: clock.date }

    onClicked: event => {
        if (event.button === Qt.RightButton)
            Hyprland.dispatch("exec brave --app=https://calendar.notion.so/");
        else
            popup.toggle();
    }

    BarPopup {
        id: popup
        target: root
        contentWidth: 300

        property date view: new Date()
        onVisibleChanged: if (visible) view = new Date()

        // Date + heure centrées, police League Spartan
        BarText {
            Layout.alignment: Qt.AlignHCenter
            text: clock.date.toLocaleDateString(Qt.locale("fr_FR"), "dddd d MMMM")
            font.family: Theme.titleFont
            font.bold: true
            font.pixelSize: 16
            font.capitalization: Font.Capitalize
        }
        BarText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "HH:mm:ss")
            font.family: Theme.titleFont
            font.pixelSize: 34
            font.bold: true
            color: Theme.text
        }

        Separator {}

        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                icon: Theme.ic(0xf0141)
                onClicked: popup.view = new Date(popup.view.getFullYear(), popup.view.getMonth() - 1, 1)
            }
            BarText {
                font.family: Theme.labelFont
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: popup.view.toLocaleDateString(Qt.locale("fr_FR"), "MMMM yyyy")
                font.capitalization: Font.Capitalize
                font.bold: true
            }
            ActionButton {
                icon: Theme.ic(0xf0142)
                onClicked: popup.view = new Date(popup.view.getFullYear(), popup.view.getMonth() + 1, 1)
            }
        }

        Grid {
            id: grid
            Layout.alignment: Qt.AlignHCenter
            columns: 7
            columnSpacing: 2
            rowSpacing: 2

            readonly property int year: popup.view.getFullYear()
            readonly property int month: popup.view.getMonth()
            readonly property int offset: (new Date(year, month, 1).getDay() + 6) % 7

            Repeater {
                model: ["L", "M", "M", "J", "V", "S", "D"]
                BarText {
                    font.family: Theme.labelFont
                    required property string modelData
                    width: 38
                    height: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.muted
                    font.pixelSize: 11
                }
            }

            Repeater {
                model: 42
                Rectangle {
                    required property int index
                    readonly property date day: new Date(grid.year, grid.month, 1 - grid.offset + index)
                    readonly property bool inMonth: day.getMonth() === grid.month
                    readonly property bool today: day.toDateString() === clock.date.toDateString()
                    width: 38
                    height: 28
                    radius: 8
                    color: today ? Theme.text : "transparent"
                    BarText {
                        font.family: Theme.labelFont
                        anchors.centerIn: parent
                        text: parent.day.getDate()
                        font.pixelSize: 12
                        font.bold: parent.today
                        color: parent.today ? "#11111b" : (parent.inMonth ? Theme.text : Qt.rgba(1, 1, 1, 0.2))
                    }
                }
            }
        }

        Separator {}

        // Météo : icône + température centrées, condition, puis 3 colonnes égales
        BarText {
            font.family: Theme.labelFont
            visible: root.weatherTemp === ""
            Layout.alignment: Qt.AlignHCenter
            text: "Météo en cours de chargement…"
            color: Theme.muted
            font.pixelSize: 11
        }
        ColumnLayout {
            visible: root.weatherTemp !== ""
            Layout.fillWidth: true
            // Largeur forcée : un layout caché au chargement ne s'étire pas toujours ensuite
            Layout.preferredWidth: popup.contentWidth
            spacing: 8

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                BarText { text: root.weatherGlyph(root.weatherSym); font.pixelSize: 26; color: Theme.text }
                BarText { text: root.weatherTemp; font.family: Theme.titleFont; font.bold: true; font.pixelSize: 26 }
            }
            BarText {
                font.family: Theme.labelFont
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.weatherCond + "  ·  Paris"
                color: Theme.subtext
                font.pixelSize: 12
            }
            // 3 colonnes de largeur fixe (1/3 du menu chacune), texte centré dedans
            Row {
                Layout.preferredWidth: popup.contentWidth
                Repeater {
                    model: [["Ressenti", root.weatherFeels], ["Vent", root.weatherWind], ["Humidité", root.weatherHum]]
                    Column {
                        required property var modelData
                        width: popup.contentWidth / 3
                        spacing: 1
                        BarText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData[0]; color: Theme.muted; font.pixelSize: 10; font.family: Theme.labelFont }
                        BarText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData[1]; font.pixelSize: 12; font.bold: true; font.family: Theme.labelFont }
                    }
                }
            }
        }
    }
}
