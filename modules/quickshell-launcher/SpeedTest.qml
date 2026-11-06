import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Test de débit (SUPER+I) : détection instantanée de l'absence d'internet, puis latence,
// débit descendant et montant avec jauge animée et courbe en direct. Les mesures viennent
// du script `speedtest-stream` (modules/internet-check.nix), une ligne par évènement.
// R / Entrée : relancer ; F / Entrée (sans internet) : netfix ; Échap : fermer.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-speedtest"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    // --- Ouverture / fermeture -------------------------------------------------
    property bool open: false
    visible: false

    function show() {
        const m = Hyprland.focusedMonitor;
        win.screen = Quickshell.screens.find(s => s.name === m?.name) ?? Quickshell.screens[0];
        closeTimer.stop();
        visible = true;
        open = true;
        keys.forceActiveFocus();
        start();
    }
    function hide() {
        open = false;
        stop();
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- État de la mesure ---------------------------------------------------------------
    // phase : idle | detect | ping | dl | ul | done | offline
    property string phase: "idle"
    property string offReason: ""
    property real pingAvg: -1
    property real jitter: 0
    property real loss: 0
    property real dlFinal: -1
    property real ulFinal: -1
    property real live: 0          // débit instantané affiché par la jauge
    property var samples: []       // courbe de l'étape en cours

    readonly property bool running: phase === "detect" || phase === "ping" || phase === "dl" || phase === "ul"
    readonly property bool measuring: phase === "dl" || phase === "ul"
    readonly property color accent: phase === "ul" ? Theme.mauve : phase === "offline" ? Theme.red : Theme.blue
    readonly property color accent2: phase === "ul" ? Theme.pink : phase === "offline" ? Theme.red : Theme.teal
    readonly property real gaugeTarget: measuring ? live : phase === "done" ? Math.max(dlFinal, 0) : 0
    property real shown: 0
    Behavior on shown { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    onGaugeTargetChanged: shown = gaugeTarget

    function start() {
        stop();
        phase = "detect";
        offReason = "";
        pingAvg = -1; jitter = 0; loss = 0;
        dlFinal = -1; ulFinal = -1;
        live = 0; samples = [];
        proc.running = true;
    }
    function stop() { proc.running = false; }

    // Pas d'internet : ouvre netfix (diagnostic + réparation) et ferme le test
    function repair() {
        hide();
        Quickshell.execDetached([Paths.userBin + "/netfix-window"]);
    }

    function handle(line) {
        const p = line.trim().split(" ");
        switch (p[0]) {
        case "phase":
            phase = p[1];
            live = 0;
            samples = [];
            break;
        case "offline":
            offReason = p[1];
            phase = "offline";
            break;
        case "ping":
            pingAvg = parseFloat(p[1]);
            jitter = parseFloat(p[2]);
            loss = parseFloat(p[3]);
            break;
        case "dl":
        case "ul":
            live = parseFloat(p[1]);
            samples = samples.concat([live]);
            break;
        case "dl_done":
            dlFinal = parseFloat(p[1]);
            break;
        case "ul_done":
            ulFinal = parseFloat(p[1]);
            break;
        case "done":
            phase = "done";
            live = 0;
            shown = dlFinal;
            break;
        }
    }

    Process {
        id: proc
        command: [Paths.userBin + "/speedtest-stream"]
        stdout: SplitParser { onRead: data => win.handle(data) }
        onExited: if (win.running) win.phase = "offline", win.offReason = "error"
    }

    function fmt(v) { return v < 0 ? "—" : v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2); }

    readonly property var phaseLabel: ({
        idle: "", detect: "Détection de la connexion…", ping: "Mesure de la latence…",
        dl: "Téléchargement", ul: "Envoi", done: "Test terminé", offline: "Pas d'internet"
    })

    // Verdict en fin de test
    readonly property string verdict: {
        if (phase !== "done") return "";
        if (dlFinal < 1) return "Connexion très faible";
        if (dlFinal < 10) return "Connexion lente";
        if (dlFinal < 50) return "Connexion correcte";
        if (dlFinal < 200) return "Bonne connexion";
        return "Excellente connexion";
    }
    readonly property color verdictColor: dlFinal < 1 ? Theme.red : dlFinal < 10 ? Theme.peach : dlFinal < 50 ? Theme.yellow : Theme.green

    // --- Interface -------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: win.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: win.hide() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 600
        height: content.implicitHeight + 40
        radius: 20
        color: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.8)
        border.color: Theme.border
        border.width: 1

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }    // le clic dans le panneau ne ferme pas

        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                event.accepted = true;
                switch (event.key) {
                case Qt.Key_Escape: win.hide(); break;
                case Qt.Key_F:
                    if (win.phase === "offline") win.repair();
                    else event.accepted = false;
                    break;
                case Qt.Key_R: win.start(); break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (win.phase === "offline") win.repair();
                    else win.start();
                    break;
                default: event.accepted = false;
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 14

            // En-tête
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                BarText {
                    text: win.phase === "offline" ? Theme.ic(0xf05aa) : Theme.ic(0xf04c5)    // md-wifi-off / md-speedometer
                    font.pixelSize: 22
                    color: win.accent
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
                BarText {
                    text: "Test de débit"
                    font.family: Theme.titleFont
                    font.pixelSize: 20
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                BarText {
                    text: "Cloudflare  ·  1.1.1.1"
                    font.pixelSize: 11
                    color: Theme.muted
                }
            }

            // Progression par étapes (latence, descendant, montant)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        { k: "ping", on: win.pingAvg >= 0 },
                        { k: "dl", on: win.dlFinal >= 0 },
                        { k: "ul", on: win.ulFinal >= 0 }
                    ]
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Theme.pill
                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: win.phase === "offline" ? Theme.red : (modelData.k === "ul" ? Theme.mauve : Theme.blue)
                            width: modelData.on ? parent.width : win.phase === modelData.k ? parent.width * 0.5 : 0
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            SequentialAnimation on opacity {
                                running: win.phase === modelData.k
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                                onRunningChanged: if (!running) parent.opacity = 1
                            }
                        }
                    }
                }
            }

            // Jauge ou écran « pas d'internet »
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 238

                // -- Jauge --
                Item {
                    id: gaugeBox
                    anchors.fill: parent
                    visible: win.phase !== "offline"

                    Canvas {
                        id: gauge
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 280
                        height: 280
                        antialiasing: true

                        // Échelle logarithmique : 0 → 1000 Mbit/s
                        function frac(v) { return Math.max(0, Math.min(1, Math.log(1 + v) / Math.log(1001))); }
                        readonly property real a0: Math.PI * 0.75
                        readonly property real sweep: Math.PI * 1.5

                        property real value: win.shown
                        property color c1: win.accent
                        property color c2: win.accent2
                        onValueChanged: requestPaint()
                        onC1Changed: requestPaint()
                        onC2Changed: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const cx = width / 2, cy = height / 2, r = 118;
                            ctx.lineCap = "round";
                            ctx.lineWidth = 14;
                            // piste
                            ctx.strokeStyle = "rgba(255,255,255,0.08)";
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, a0, a0 + sweep);
                            ctx.stroke();
                            // valeur
                            const f = frac(value);
                            if (f > 0.002) {
                                const g = ctx.createLinearGradient(cx - r, cy + r, cx + r, cy - r);
                                g.addColorStop(0, c1.toString());
                                g.addColorStop(1, c2.toString());
                                ctx.strokeStyle = g;
                                ctx.beginPath();
                                ctx.arc(cx, cy, r, a0, a0 + sweep * f);
                                ctx.stroke();
                                // pointe lumineuse
                                const ea = a0 + sweep * f;
                                ctx.fillStyle = "#ffffff";
                                ctx.beginPath();
                                ctx.arc(cx + r * Math.cos(ea), cy + r * Math.sin(ea), 4, 0, Math.PI * 2);
                                ctx.fill();
                            }
                        }
                    }

                    // Graduations
                    Repeater {
                        model: [0, 5, 10, 50, 100, 250, 500, 1000]
                        BarText {
                            required property int modelData
                            readonly property real ang: gauge.a0 + gauge.sweep * gauge.frac(modelData)
                            x: gauge.x + gauge.width / 2 + 90 * Math.cos(ang) - width / 2
                            y: gauge.y + gauge.height / 2 + 90 * Math.sin(ang) - height / 2
                            text: modelData
                            font.pixelSize: 10
                            color: Theme.muted
                        }
                    }

                    // Valeur au centre
                    ColumnLayout {
                        anchors.horizontalCenter: gauge.horizontalCenter
                        y: gauge.y + 78
                        spacing: 0
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: win.phase === "dl" ? Theme.ic(0xf01da) + "  Descendant"
                                : win.phase === "ul" ? Theme.ic(0xf0552) + "  Montant"
                                : win.phase === "done" ? Theme.ic(0xf01da) + "  Descendant" : ""
                            font.pixelSize: 12
                            color: win.accent
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: win.measuring || win.phase === "done" ? win.fmt(win.shown) : "—"
                            font.family: Theme.titleFont
                            font.pixelSize: 56
                            font.bold: true
                            color: win.running && !win.measuring ? Theme.muted : Theme.text
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: win.measuring || win.phase === "done" ? "Mbit/s" : win.phaseLabel[win.phase]
                            font.pixelSize: win.measuring || win.phase === "done" ? 14 : 12
                            color: Theme.subtext
                        }
                    }
                }

                // -- Pas d'internet --
                Item {
                    id: offBox
                    anchors.fill: parent
                    visible: win.phase === "offline"

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 110
                            implicitHeight: 110
                            radius: 55
                            color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.12)
                            border.color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.5)
                            border.width: 2
                            BarText {
                                anchors.centerIn: parent
                                text: Theme.ic(0xf05aa)    // md-wifi-off
                                font.pixelSize: 54
                                color: Theme.red
                            }
                            SequentialAnimation on scale {
                                running: offBox.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.06; duration: 800; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
                            }
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Pas d'internet"
                            font.family: Theme.titleFont
                            font.pixelSize: 28
                            font.bold: true
                            color: Theme.red
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: win.offReason === "noroute" ? "Aucune connexion réseau : Wi-Fi coupé ou câble débranché"
                                : win.offReason === "noreply" ? "Connecté au réseau, mais aucune réponse d'internet"
                                : "Le test a été interrompu"
                            font.pixelSize: 12
                            color: Theme.subtext
                        }
                    }
                }
            }

            // Courbe en direct de l'étape en cours
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 12
                color: Theme.pill
                border.color: Theme.pillBorder
                border.width: 1
                clip: true
                visible: win.phase !== "offline"

                Canvas {
                    id: graph
                    anchors.fill: parent
                    anchors.margins: 1
                    property var pts: win.samples
                    property color c1: win.accent
                    onPtsChanged: requestPaint()
                    onC1Changed: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const n = pts.length;
                        if (n < 2) return;
                        let mx = 1;
                        for (const v of pts) mx = Math.max(mx, v);
                        mx *= 1.15;
                        const w = width, h = height, step = w / Math.max(n - 1, 31);
                        const y = v => h - 4 - (v / mx) * (h - 10);
                        ctx.beginPath();
                        ctx.moveTo(0, y(pts[0]));
                        for (let i = 1; i < n; i++) ctx.lineTo(i * step, y(pts[i]));
                        ctx.strokeStyle = c1.toString();
                        ctx.lineWidth = 2.5;
                        ctx.lineJoin = "round";
                        ctx.stroke();
                        ctx.lineTo((n - 1) * step, h);
                        ctx.lineTo(0, h);
                        ctx.closePath();
                        const g = ctx.createLinearGradient(0, 0, 0, h);
                        g.addColorStop(0, Qt.rgba(c1.r, c1.g, c1.b, 0.35).toString());
                        g.addColorStop(1, Qt.rgba(c1.r, c1.g, c1.b, 0).toString());
                        ctx.fillStyle = g;
                        ctx.fill();
                    }
                }
                BarText {
                    anchors.centerIn: parent
                    visible: win.samples.length < 2
                    text: win.running ? win.phaseLabel[win.phase] : "Appuie sur R pour lancer un test"
                    font.pixelSize: 11
                    color: Theme.muted
                }
            }

            // Cartes de résultats
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: win.phase !== "offline"

                Repeater {
                    model: [
                        { k: "ping", icon: 0xf051b, name: "Latence", col: "blue" },
                        { k: "dl", icon: 0xf01da, name: "Descendant", col: "teal" },
                        { k: "ul", icon: 0xf0552, name: "Montant", col: "mauve" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool active: win.phase === modelData.k
                        readonly property color col: Theme[modelData.col]
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 82
                        radius: 14
                        color: active ? Qt.rgba(col.r, col.g, col.b, 0.1) : Theme.pill
                        border.color: active ? Qt.rgba(col.r, col.g, col.b, 0.6) : Theme.pillBorder
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 2
                            RowLayout {
                                spacing: 6
                                BarText { text: Theme.ic(modelData.icon); font.pixelSize: 14; color: col }
                                BarText { text: modelData.name; font.pixelSize: 11; color: Theme.subtext }
                            }
                            RowLayout {
                                spacing: 5
                                BarText {
                                    text: modelData.k === "ping" ? (win.pingAvg < 0 ? "—" : win.pingAvg.toFixed(0))
                                        : modelData.k === "dl" ? win.fmt(win.dlFinal) : win.fmt(win.ulFinal)
                                    font.family: Theme.titleFont
                                    font.pixelSize: 24
                                    font.bold: true
                                }
                                BarText {
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 4
                                    text: modelData.k === "ping" ? "ms" : "Mbit/s"
                                    font.pixelSize: 11
                                    color: Theme.muted
                                }
                            }
                            BarText {
                                visible: modelData.k === "ping"
                                text: win.pingAvg < 0 ? " " : "gigue " + win.jitter.toFixed(1) + " ms  ·  perte " + win.loss.toFixed(0) + " %"
                                font.pixelSize: 10
                                color: win.loss > 0 ? Theme.peach : Theme.muted
                            }
                        }
                    }
                }
            }

            // Verdict + boutons
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                BarText {
                    Layout.fillWidth: true
                    text: win.phase === "done" ? Theme.ic(0xf012c) + "  " + win.verdict    // md-check
                        : ""
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    font.pixelSize: 13
                    font.bold: true
                    color: win.phase === "done" ? win.verdictColor : Theme.subtext
                }

                Repeater {
                    model: (win.phase === "offline"
                            ? [{ label: "Réparer (netfix)", icon: 0xf0be0, key: "F", act: "repair", accent: true }]
                            : []).concat([
                        { label: "Relancer", icon: 0xf0450, key: "R", act: "start" },
                        { label: "Fermer", icon: 0xf0156, key: "Échap", act: "hide" }
                    ])
                    Rectangle {
                        required property var modelData
                        implicitWidth: btnRow.implicitWidth + 24
                        implicitHeight: 34
                        radius: 10
                        color: modelData.accent ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, btnMa.containsMouse ? 0.3 : 0.18)
                                                : btnMa.containsMouse ? Theme.pillHover : Theme.pill
                        border.color: modelData.accent ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.6) : Theme.pillBorder
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: btnMa.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        RowLayout {
                            id: btnRow
                            anchors.centerIn: parent
                            spacing: 7
                            BarText { text: Theme.ic(modelData.icon); font.pixelSize: 14; color: modelData.accent ? Theme.red : Theme.subtext }
                            BarText { text: modelData.label; font.pixelSize: 12 }
                            BarText { text: modelData.key; font.pixelSize: 10; color: Theme.muted }
                        }
                        MouseArea {
                            id: btnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.act === "start" ? win.start() : modelData.act === "repair" ? win.repair() : win.hide()
                        }
                    }
                }
            }
        }
    }
}
