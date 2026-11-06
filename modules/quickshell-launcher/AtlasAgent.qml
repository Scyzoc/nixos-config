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
    readonly property color cChip: dark ? "#2b2b2b" : "#efedea"
    readonly property color cText: dark ? "#ededed" : "#37342e"
    readonly property color cMuted: dark ? "#9a9a9a" : "#8a847c"
    readonly property color cLine: dark ? "#2e2e2e" : "#e6e3de"
    readonly property color cErr: dark ? "#e08a8a" : "#b3392f"
    readonly property var aiStops: dark ? ["#3987e5", "#a08ce8", "#68c191", "#d9a45c"] : ["#2a78d6", "#6b4fc7", "#2b7d52", "#a2691a"]
    readonly property var aiPalette: aiStops.concat([aiStops[0]])
    readonly property string sans: Theme.trackFont

    // --- Discussion ----------------------------------------------------------------
    property int conversation: 0
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
        msgs.clear();
        input.forceActiveFocus();
    }

    function onEvent(e) {
        const i = msgs.count - 1;
        if (i < 0) return;
        if (e.t === "start") conversation = e.conversationId;
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
        width: Math.min(520, parent.width - 80)
        height: Math.min(760, parent.height - 100)
        radius: 20
        color: win.cPanel
        border.color: win.cLine
        border.width: 1
        clip: true

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // En-tête
            Item {
                Layout.fillWidth: true
                implicitHeight: 64
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 12
                    Rectangle {
                        implicitWidth: 36; implicitHeight: 36; radius: 10
                        color: win.cChip
                        BarText { anchors.centerIn: parent; text: Theme.ic(0xf06a9); font.pixelSize: 19; color: win.cText }
                    }
                    Text { text: "Agent"; font.family: win.sans; font.pixelSize: 17; font.weight: Font.DemiBold; color: win.cText; Layout.fillWidth: true }
                    Repeater {
                        model: [
                            { icon: 0xf0415, tip: "new" },
                            { icon: 0xf03cc, tip: "open" },
                            { icon: 0xf0156, tip: "close" }
                        ]
                        Rectangle {
                            required property var modelData
                            implicitWidth: 36; implicitHeight: 36; radius: 10
                            color: hMa.containsMouse ? win.cChip : "transparent"
                            opacity: modelData.tip === "new" && win.busy ? 0.4 : 1
                            BarText { anchors.centerIn: parent; text: Theme.ic(modelData.icon); font.pixelSize: 19; color: win.cMuted }
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
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    topMargin: 16
                    bottomMargin: 12
                    clip: true
                    spacing: 16
                    model: msgs
                    visible: msgs.count > 0
                    boundsBehavior: Flickable.StopAtBounds

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

                        Rectangle {
                            id: bubble
                            visible: row.mine
                            anchors.right: parent.right
                            width: Math.min(parent.width * 0.85, userText.implicitWidth + 28)
                            height: userText.implicitHeight + 20
                            radius: 16
                            color: win.cChip
                            Text {
                                id: userText
                                x: 14; y: 10
                                width: Math.min(parent.parent.width * 0.85 - 28, implicitWidth)
                                wrapMode: Text.Wrap
                                text: row.text
                                color: win.cText
                                font.family: win.sans
                                font.pixelSize: 14
                            }
                        }

                        Column {
                            id: reply
                            visible: !row.mine
                            width: parent.width
                            spacing: 8
                            Flow {
                                width: parent.width
                                spacing: 6
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
                                        Text { id: toolT; anchors.centerIn: parent; text: modelData; color: win.cMuted; font.family: win.sans; font.pixelSize: 11 }
                                    }
                                }
                            }
                            // Réflexion : orbe + « Thinking… » (dégradé animé)
                            Row {
                                visible: row.waiting
                                spacing: 10
                                ThinkingOrb { id: orb; orbSize: 22; running: row.waiting && win.open; palette: win.aiPalette; anchors.verticalCenter: parent.verticalCenter }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        id: thinkText
                                        text: "Thinking"
                                        font.family: win.sans
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        color: win.aiStops[0]
                                        SequentialAnimation on color {
                                            running: row.waiting && win.open
                                            loops: Animation.Infinite
                                            ColorAnimation { to: win.aiStops[1]; duration: 1400 }
                                            ColorAnimation { to: win.aiStops[2]; duration: 1400 }
                                            ColorAnimation { to: win.aiStops[3]; duration: 1400 }
                                            ColorAnimation { to: win.aiStops[0]; duration: 1400 }
                                        }
                                    }
                                    Repeater {
                                        model: 3
                                        Text {
                                            required property int index
                                            text: "."
                                            font: thinkText.font
                                            color: thinkText.color
                                            SequentialAnimation on opacity {
                                                running: row.waiting && win.open
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: index * 200 }
                                                NumberAnimation { from: 0.2; to: 1; duration: 350 }
                                                NumberAnimation { from: 1; to: 0.2; duration: 350 }
                                                PauseAnimation { duration: (2 - index) * 200 }
                                            }
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: row.text !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                textFormat: Text.MarkdownText
                                text: row.text
                                color: row.failed ? win.cErr : win.cText
                                linkColor: win.aiStops[1]
                                font.family: win.sans
                                font.pixelSize: 14
                                lineHeight: 1.25
                                onLinkActivated: link => Qt.openUrlExternally(link.startsWith("/") ? "https://atlas.homelab.lan" + link : link)
                            }
                        }
                    }
                }

                // Accueil
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 36
                    spacing: 12
                    visible: msgs.count === 0

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 70; implicitHeight: 70; radius: 20
                        color: win.cChip
                        BarText { anchors.centerIn: parent; text: Theme.ic(0xf06a9); font.pixelSize: 32; color: win.cText }
                    }
                    Item { width: 1; height: 4 }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Que veux-tu faire ?"
                        font.family: win.sans; font.pixelSize: 19; font.weight: Font.DemiBold
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
                    Item { width: 1; height: 8 }
                    Repeater {
                        model: win.examples
                        GradBorder {
                            required property string modelData
                            width: parent.width
                            implicitHeight: exText.implicitHeight + 26
                            radius: 10
                            bw: 1.5
                            fill: exMa.containsMouse ? win.cChip : win.cPanel
                            stops: win.aiStops
                            strength: exMa.containsMouse ? 0.8 : 0.55
                            Text {
                                id: exText
                                anchors.verticalCenter: parent.verticalCenter
                                x: 14
                                width: parent.width - 28
                                wrapMode: Text.Wrap
                                text: modelData
                                color: win.cText
                                font.family: win.sans
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: exMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.send(modelData)
                            }
                        }
                    }
                }
            }

            // Saisie
            Item {
                Layout.fillWidth: true
                implicitHeight: 84
                GradBorder {
                    anchors.fill: parent
                    anchors.margins: 14
                    radius: 24
                    bw: 2
                    fill: win.cPanel
                    stops: win.aiStops
                    strength: input.activeFocus ? 0.9 : 0.65

                    TextInput {
                        id: input
                        anchors.left: parent.left
                        anchors.right: sendBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
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
                            color: win.cMuted
                            font: input.font
                        }
                    }

                    Rectangle {
                        id: sendBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 9
                        width: 38; height: 38; radius: 19
                        color: sendMa.containsMouse ? Qt.darker(win.cChip, 1.08) : win.cChip
                        scale: sendMa.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        BarText {
                            anchors.centerIn: parent
                            text: win.busy ? Theme.ic(0xf04db) : Theme.ic(0xf005d)    // md-stop / md-arrow-up
                            font.pixelSize: 19
                            color: win.busy ? win.cErr : win.cMuted
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
