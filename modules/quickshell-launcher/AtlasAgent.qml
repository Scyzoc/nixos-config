import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Agent IA d'Atlas (SUPER+SHIFT+T) : fenêtre de discussion avec l'agent Hermes d'Atlas
// (même discussion que la page /agent du site, voir assets/atlas-agent.py).
// Entrée : envoyer ; Échap : fermer (une réponse en cours continue) ; Ctrl+N : nouvelle discussion.
// Look du widget « Agent » du site (clair ou sombre selon le thème GTK), orbe de réflexion ThinkingOrb.
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-atlas-agent"
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
        input.forceActiveFocus();
        schemeProc.running = true;
        if (!loaded) { loaded = true; lastProc.running = true; }
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Palette (clair par défaut, sombre si color-scheme = prefer-dark) ---------------
    property bool dark: false
    Process {
        id: schemeProc
        command: [Paths.dconf, "read", "/org/gnome/desktop/interface/color-scheme"]
        stdout: StdioCollector { onStreamFinished: win.dark = text.indexOf("dark") >= 0 }
    }
    readonly property color cPanel: dark ? "#1a1a1a" : "#ffffff"
    readonly property color cHover: dark ? "#242424" : "#f6f5f2"
    readonly property color cChip: dark ? "#2b2b2b" : "#efedea"
    readonly property color cSoft: dark ? "#2b2b2b" : "#eceae5"
    readonly property color cAccent: dark ? "#ededed" : "#2c2723"
    readonly property color cText: dark ? "#ededed" : "#37342e"
    readonly property color cMuted: dark ? "#9a9a9a" : "#625d56"
    readonly property color cFaint: dark ? "#8a8a8a" : "#7b756d"
    readonly property color cLine: dark ? "#2e2e2e" : "#e8e5e0"
    readonly property color cLineStrong: dark ? "#3c3c3c" : "#d3cfc8"
    readonly property color cErr: dark ? "#e08a8a" : "#b3392f"
    readonly property var aiStops: dark ? ["#3987e5", "#a08ce8", "#68c191", "#d9a45c"] : ["#2a78d6", "#6b4fc7", "#2b7d52", "#a2691a"]
    readonly property var aiPalette: aiStops.concat([aiStops[0]])
    readonly property string sans: Theme.trackFont

    // --- Discussion ----------------------------------------------------------------
    property int conversation: 0
    property string title: ""
    property bool busy: false
    property bool loaded: false
    ListModel { id: msgs }

    function scrollEnd() { list.positionViewAtEnd(); }

    function send(text) {
        const t = text.trim();
        if (t === "" || busy) return;
        msgs.append({ role: "user", text: t, tools: "", failed: false });
        msgs.append({ role: "assistant", text: "", tools: "", failed: false });
        busy = true;
        input.text = "";
        sendProc.command = [Paths.userBin + "/atlas-agent", "send", String(conversation), t];
        sendProc.running = true;
        Qt.callLater(scrollEnd);
    }
    function stop() {
        if (busy && conversation > 0)
            Quickshell.execDetached([Paths.userBin + "/atlas-agent", "stop", String(conversation)]);
    }
    function newChat() {
        if (busy) return;
        conversation = 0;
        title = "";
        msgs.clear();
        input.forceActiveFocus();
    }

    function onEvent(e) {
        const i = msgs.count - 1;
        if (i < 0) return;
        if (e.t === "start") { conversation = e.conversationId; if (e.title) title = e.title; }
        else if (e.t === "delta") msgs.setProperty(i, "text", msgs.get(i).text + e.text);
        else if (e.t === "tool") {
            const cur = msgs.get(i).tools;
            msgs.setProperty(i, "tools", cur === "" ? e.label : cur + " · " + e.label);
        } else if (e.t === "error") {
            msgs.setProperty(i, "text", msgs.get(i).text === "" ? e.message : msgs.get(i).text);
            msgs.setProperty(i, "failed", true);
        } else if (e.t === "stopped" && msgs.get(i).text === "") {
            msgs.setProperty(i, "text", "Réponse arrêtée.");
            msgs.setProperty(i, "failed", true);
        }
        Qt.callLater(scrollEnd);
    }

    Process {
        id: sendProc
        stdout: SplitParser {
            onRead: line => {
                try { win.onEvent(JSON.parse(line)); } catch (e) { }
            }
        }
        onExited: {
            win.busy = false;
            const i = msgs.count - 1;
            if (i >= 0 && msgs.get(i).role === "assistant" && msgs.get(i).text === "") {
                msgs.setProperty(i, "text", "Pas de réponse d'Atlas (VPN coupé ?).");
                msgs.setProperty(i, "failed", true);
            }
        }
    }
    // Reprend la dernière discussion à la première ouverture
    Process {
        id: lastProc
        command: [Paths.userBin + "/atlas-agent", "last"]
        stdout: StdioCollector {
            onStreamFinished: {
                const id = parseInt(text);
                if (id > 0 && msgs.count === 0) { win.conversation = id; loadProc.command = [Paths.userBin + "/atlas-agent", "load", String(id)]; loadProc.running = true; }
            }
        }
    }
    Process {
        id: loadProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (msgs.count > 0) return;
                    win.title = d.title || "";
                    for (const m of d.messages)
                        msgs.append({ role: m.role, text: m.content, tools: "", failed: m.error });
                    Qt.callLater(win.scrollEnd);
                } catch (e) { }
            }
        }
    }

    readonly property var examples: [
        "Qu’est-ce que j’ai à faire aujourd’hui ?",
        "Quelles tâches sont en retard ? Propose-moi un plan pour les rattraper.",
        "Résume l’avancement de mes projets actifs.",
        "Quelles évaluations arrivent dans les deux prochaines semaines ?"
    ]

    // --- Interface (reprend .agent-dock / .agent-pop d'Atlas) ----------------------------
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
        width: Math.min(420, parent.width - 32)
        height: Math.min(640, parent.height - 112)
        radius: 14
        color: win.cPanel
        border.color: win.cLine
        border.width: 1
        clip: true

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // En-tête (.agent-pop-head)
            Item {
                Layout.fillWidth: true
                implicitHeight: 52
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 6
                    Rectangle {
                        implicitWidth: 26; implicitHeight: 26; radius: 8
                        color: win.cSoft
                        Layout.rightMargin: 4
                        BarText { anchors.centerIn: parent; text: Theme.ic(0xf069a); font.pixelSize: 15; color: win.cAccent }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.title !== "" ? win.title : "Agent"
                        elide: Text.ElideRight
                        font.family: win.sans; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: win.cText
                    }
                    Repeater {
                        model: [
                            { icon: 0xf0415, tip: "new" },
                            { icon: 0xf0293, tip: "open" },
                            { icon: 0xf0156, tip: "close" }
                        ]
                        Rectangle {
                            required property var modelData
                            implicitWidth: 34; implicitHeight: 34; radius: 8
                            color: hMa.containsMouse ? win.cHover : "transparent"
                            opacity: modelData.tip === "new" && win.busy ? 0.4 : 1
                            BarText { anchors.centerIn: parent; text: Theme.ic(modelData.icon); font.pixelSize: 17; color: hMa.containsMouse ? win.cText : win.cMuted }
                            MouseArea {
                                id: hMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.tip === "new") win.newChat();
                                    else if (modelData.tip === "open") { Qt.openUrlExternally("https://atlas.homelab.lan/agent" + (win.conversation > 0 ? "?c=" + win.conversation : "")); win.hide(); }
                                    else win.hide();
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.cLine }

            // Fil des messages + accueil
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    topMargin: 14
                    bottomMargin: 10
                    clip: true
                    spacing: 14
                    model: msgs
                    visible: msgs.count > 0
                    boundsBehavior: Flickable.StopAtBounds

                    // Séparateur de jour (.agent-day)
                    header: Item {
                        width: list.width
                        height: 26
                        RowLayout {
                            anchors.fill: parent
                            spacing: 12
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.cLine }
                            Text { text: "Aujourd’hui"; font.family: win.sans; font.pixelSize: 12; color: win.cFaint }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.cLine }
                        }
                    }

                    delegate: Item {
                        id: row
                        required property int index
                        required property string role
                        required property string text
                        required property string tools
                        required property bool failed
                        readonly property bool mine: role === "user"
                        readonly property bool waiting: !mine && text === "" && win.busy && index === msgs.count - 1
                        width: list.width
                        implicitHeight: mine ? bubble.height : reply.implicitHeight

                        // .agent-bubble : 14 14 4 14, fond panel-3
                        Rectangle {
                            id: bubble
                            visible: row.mine
                            anchors.right: parent.right
                            width: Math.min(parent.width * 0.88, userText.implicitWidth + 26)
                            height: userText.implicitHeight + 18
                            radius: 14
                            color: win.cChip
                            Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 14; height: 14; radius: 4; color: win.cChip }
                            Text {
                                id: userText
                                x: 13; y: 9
                                width: Math.min(row.width * 0.88 - 26, implicitWidth)
                                wrapMode: Text.Wrap
                                text: row.text
                                color: win.cText
                                font.family: win.sans
                                font.pixelSize: 15
                                lineHeight: 1.3
                            }
                        }

                        Column {
                            id: reply
                            visible: !row.mine
                            width: parent.width
                            spacing: 8
                            // .agent-tools
                            Flow {
                                width: parent.width
                                spacing: 5
                                visible: row.tools !== ""
                                Repeater {
                                    model: row.tools === "" ? [] : row.tools.split(" · ")
                                    Rectangle {
                                        required property string modelData
                                        implicitWidth: toolT.implicitWidth + 18
                                        implicitHeight: 22
                                        radius: 11
                                        color: "transparent"
                                        border.color: win.cLine
                                        border.width: 1
                                        Text { id: toolT; anchors.centerIn: parent; text: modelData; color: win.cMuted; font.family: win.sans; font.pixelSize: 12 }
                                    }
                                }
                            }
                            // .agent-thinking : orbe + texte en dégradé qui glisse + points qui rebondissent
                            Row {
                                visible: row.waiting
                                spacing: 6
                                topPadding: 3
                                bottomPadding: 3
                                ThinkingOrb { orbSize: 22; running: row.waiting && win.open; palette: win.aiPalette; anchors.verticalCenter: parent.verticalCenter }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        id: thinkText
                                        text: "Thinking"
                                        font.family: win.sans
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        color: win.aiStops[0]
                                        SequentialAnimation on color {
                                            running: row.waiting && win.open
                                            loops: Animation.Infinite
                                            ColorAnimation { to: win.aiStops[1]; duration: 600 }
                                            ColorAnimation { to: win.aiStops[2]; duration: 600 }
                                            ColorAnimation { to: win.aiStops[3]; duration: 600 }
                                            ColorAnimation { to: win.aiStops[0]; duration: 600 }
                                        }
                                    }
                                    Repeater {
                                        model: 3
                                        Text {
                                            id: dot
                                            required property int index
                                            text: "."
                                            font: thinkText.font
                                            color: thinkText.color
                                            transform: Translate { id: tr; y: 0 }
                                            SequentialAnimation {
                                                running: row.waiting && win.open
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: dot.index * 150 }
                                                NumberAnimation { target: tr; property: "y"; to: -3; duration: 360; easing.type: Easing.InOutQuad }
                                                NumberAnimation { target: tr; property: "y"; to: 0; duration: 360; easing.type: Easing.InOutQuad }
                                                PauseAnimation { duration: 480 - dot.index * 150 }
                                            }
                                        }
                                    }
                                }
                            }
                            // .agent-answer
                            Text {
                                visible: row.text !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                textFormat: Text.MarkdownText
                                text: row.text
                                color: row.failed ? win.cErr : win.cText
                                linkColor: win.aiStops[1]
                                font.family: win.sans
                                font.pixelSize: 15
                                lineHeight: 1.35
                                onLinkActivated: link => Qt.openUrlExternally(link.startsWith("/") ? "https://atlas.homelab.lan" + link : link)
                            }
                        }
                    }
                }

                // Accueil (.agent-empty, version compacte)
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 6
                    visible: msgs.count === 0

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 52; implicitHeight: 52; radius: 14
                        color: win.cSoft
                        BarText { anchors.centerIn: parent; text: Theme.ic(0xf069a); font.pixelSize: 24; color: win.cAccent }
                    }
                    Item { width: 1; height: 2 }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Que veux-tu faire ?"
                        font.family: win.sans; font.pixelSize: 16; font.weight: Font.Bold
                        color: win.cText
                    }
                    Text {
                        width: parent.width - 20
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "L’agent lit et modifie tes tâches, projets et évaluations, et consulte ton agenda."
                        font.family: win.sans; font.pixelSize: 15
                        color: win.cMuted
                    }
                    Item { width: 1; height: 4 }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: win.examples
                            // .agent-suggest : fond panel, anneau shimmer 1,5 px (0,6 → 1 au survol)
                            Rectangle {
                                id: sg
                                required property string modelData
                                width: parent.width
                                height: sgText.implicitHeight + 22
                                radius: 10
                                color: win.cPanel
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1.5
                                    radius: 8.5
                                    color: Qt.rgba(Qt.color(win.aiStops[1]).r, Qt.color(win.aiStops[1]).g, Qt.color(win.aiStops[1]).b, 0.08)
                                    opacity: sgMa.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }
                                GradRing {
                                    anchors.fill: parent
                                    radius: 10
                                    lineWidth: 1.5
                                    stops: win.aiStops
                                    opacity: sgMa.containsMouse ? 1 : 0.6
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }
                                Text {
                                    id: sgText
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 13
                                    width: parent.width - 26
                                    wrapMode: Text.Wrap
                                    text: sg.modelData
                                    color: win.cText
                                    font.family: win.sans
                                    font.pixelSize: 14
                                    lineHeight: 1.25
                                }
                                MouseArea {
                                    id: sgMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.send(sg.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // Saisie (.agent-composer)
            Item {
                Layout.fillWidth: true
                implicitHeight: 70
                Rectangle {
                    id: composer
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 10
                    anchors.topMargin: 6
                    radius: 18
                    color: win.cPanel
                    border.width: 1.5
                    border.color: input.activeFocus ? "transparent" : win.cLineStrong

                    GradRing {
                        anchors.fill: parent
                        radius: 18
                        lineWidth: 1.5
                        stops: win.aiStops
                        opacity: input.activeFocus ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                    }

                    TextInput {
                        id: input
                        anchors.left: parent.left
                        anchors.right: sendBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        color: win.cText
                        font.family: win.sans
                        font.pixelSize: 15
                        clip: true
                        selectByMouse: true
                        focus: true
                        Keys.onPressed: event => {
                            event.accepted = true;
                            if (event.key === Qt.Key_Escape) win.hide();
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.send(input.text);
                            else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) win.newChat();
                            else event.accepted = false;
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: input.text === ""
                            text: "Écris à l’agent…"
                            color: win.cFaint
                            font: input.font
                        }
                    }

                    // .btn.agent-send : éteint (panel-3, réduit) sans texte, plein (accent) sinon
                    Rectangle {
                        id: sendBtn
                        readonly property bool ready: input.text.trim() !== "" || win.busy
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 7.5
                        width: 36; height: 36; radius: 18
                        color: ready ? win.cAccent : win.cChip
                        scale: !ready ? 0.86 : (sendMa.pressed ? 0.92 : 1)
                        Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        BarText {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: sendBtn.ready && sendMa.containsMouse && !win.busy ? -2 : 0
                            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            text: win.busy ? Theme.ic(0xf04db) : Theme.ic(0xf005d)    // md-stop / md-arrow-up
                            font.pixelSize: 18
                            color: sendBtn.ready ? win.cPanel : win.cFaint
                        }
                        MouseArea {
                            id: sendMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.busy ? win.stop() : win.send(input.text)
                        }
                    }
                }
            }
        }
    }
}
