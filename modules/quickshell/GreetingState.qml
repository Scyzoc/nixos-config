pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Message de bienvenue « Dynamic Island » (Greeting.qml) : une fois par jour, au premier
// déverrouillage (fin de hyprlock) ou, sans verrou, au démarrage de la barre.
Singleton {
    id: root

    property bool active: false
    property bool locked: false
    readonly property string stateFile: Paths.stateDir + "/greeting-last"

    readonly property int hour: new Date().getHours()
    readonly property string title: (hour < 5 ? "Bonne nuit" : hour < 18 ? (hour < 12 ? "Bonjour" : "Bon après-midi") : "Bonsoir") + " Lei"
    readonly property string subtitle: (hour < 5 ? "Pense à dormir" : hour < 18 ? "Bonne journée" : "Bonne soirée")
        + "  ·  " + Qt.formatDate(new Date(), "dddd d MMMM")

    function show() { root.active = true; }

    // Nouveau jour ? marque aujourd'hui et affiche (force : ignore la date, pour les tests)
    function check(force: bool) {
        checker.command = [Paths.sh, "-c",
            force ? "echo go"
                  : "f=\"$1\"; d=$(" + Paths.date + " +%F); [ \"$(" + Paths.cat + " \"$f\" 2>/dev/null)\" = \"$d\" ] "
                    + "|| { " + Paths.mkdir + " -p \"$(dirname \"$f\")\"; echo \"$d\" > \"$f\"; echo go; }",
            "sh", root.stateFile];
        checker.running = true;
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: if (text.indexOf("go") >= 0) root.show()
        }
    }

    // Surveille hyprlock : verrouillé → déverrouillé = « je viens de me connecter »
    Process {
        id: lockProbe
        command: [Paths.pidof, "hyprlock"]
        onExited: code => {
            const now = code === 0;
            if (root.locked && !now) root.check(false);
            root.locked = now;
        }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: if (!lockProbe.running) lockProbe.running = true
    }
    // Connexion (barre qui démarre) : attend que l'écran soit prêt
    Timer {
        interval: 4000
        running: true
        onTriggered: if (!root.locked) root.check(false)
    }
}
