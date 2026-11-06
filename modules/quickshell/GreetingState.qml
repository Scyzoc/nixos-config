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

    // Heure courante, rafraîchie chaque minute : sans ça, le bonjour reste figé à l'heure de démarrage
    property date now: new Date()
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    readonly property int hour: now.getHours()
    readonly property string title: (hour < 5 ? "Bonne nuit" : hour < 12 ? "Bonjour" : hour < 18 ? "Bon après-midi" : hour < 22 ? "Bonsoir" : "Bonne nuit") + " user"
    readonly property string subtitle: (hour < 5 ? "Pense à dormir" : hour < 12 ? "Bonne journée" : hour < 14 ? "Bon appétit" : hour < 18 ? taskText : hour < 22 ? "Bonne soirée" : "Pense à dormir")
        + "  ·  " + now.toLocaleDateString(Qt.locale("fr_FR"), "dddd d MMMM")

    // Tâches Atlas du jour (atlas-task today), affichées à la place du vœu de l'après-midi
    property int taskCount: -1
    readonly property string taskText: taskCount < 0 ? "Belle après-midi"
        : taskCount === 0 ? "Aucune tâche aujourd'hui"
        : taskCount + (taskCount === 1 ? " tâche" : " tâches") + " aujourd'hui"

    function show() { taskProbe.running = true; root.active = true; }

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
        id: taskProbe
        command: [Paths.userBin + "/atlas-task", "today"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.taskCount = JSON.parse(text).count; } catch (e) {}
            }
        }
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
