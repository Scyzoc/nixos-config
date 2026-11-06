import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Agent IA d'Atlas (SUPER+SHIFT+T) : fenêtre de discussion avec l'agent Hermes d'Atlas
// (même discussion que la page /agent du site, voir assets/atlas-agent.py).
// Entrée : envoyer ; Échap : fermer (une réponse en cours continue) ; Ctrl+N : nouvelle discussion.
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
        if (!loaded) { loaded = true; lastProc.running = true; }
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

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
        "Qu'est-ce que j'ai à faire aujourd'hui ?",
        "Tâches en retard",
        "Où en est mon projet NixOS ?",
        "Crée une tâche : …"
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
        width: Math.min(760, parent.width - 80)
        height: Math.min(680, parent.height - 120)
        radius: 18
        color: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.88)
        border.color: Theme.border
        border.width: 1

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // En-tête
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                BarText { text: Theme.ic(0xf06a9); font.pixelSize: 20; color: Theme.mauve }
                BarText { text: "Agent Atlas"; font.pixelSize: 15; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 30; implicitHeight: 30; radius: 9
                    color: newMa.containsMouse ? Theme.pillHover : "transparent"
                    opacity: win.busy ? 0.4 : 1
                    BarText { anchors.centerIn: parent; text: Theme.ic(0xf0415); font.pixelSize: 17; color: Theme.subtext }    // md-plus
                    MouseArea { id: newMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.newChat() }
                }
            }

            // Fil des messages
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 10
                model: msgs
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row
                    required property string role
                    required property string text
                    required property string tools
                    required property bool failed
                    readonly property bool mine: role === "user"
                    width: list.width
                    implicitHeight: bubble.height

                    Rectangle {
                        id: bubble
                        anchors.right: row.mine ? parent.right : undefined
                        anchors.left: row.mine ? undefined : parent.left
                        width: Math.min(parent.width * 0.88, Math.max(body.implicitWidth, toolsText.implicitWidth) + 28)
                        height: col.implicitHeight + 20
                        radius: 14
                        color: row.mine ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.22) : Theme.pill
                        border.color: row.failed ? Theme.red : (row.mine ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.4) : Theme.pillBorder)
                        border.width: 1

                        Column {
                            id: col
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 6
                            Text {
                                id: toolsText
                                visible: row.tools !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: "⚙ " + row.tools
                                color: Theme.muted
                                font.family: Theme.labelFont
                                font.pixelSize: 11
                            }
                            Text {
                                id: body
                                width: parent.width
                                wrapMode: Text.Wrap
                                textFormat: row.mine ? Text.PlainText : Text.MarkdownText
                                text: row.text === "" && win.busy ? "…" : row.text
                                color: row.failed ? Theme.red : Theme.text
                                linkColor: Theme.mauve
                                font.family: Theme.labelFont
                                font.pixelSize: 14
                                onLinkActivated: link => Qt.openUrlExternally(link.startsWith("/") ? "https://atlas.homelab.lan" + link : link)
                            }
                        }
                    }
                }

                // Accueil
                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    visible: msgs.count === 0
                    BarText { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.ic(0xf06a9); font.pixelSize: 44; color: Theme.mauve }
                    BarText { anchors.horizontalCenter: parent.horizontalCenter; text: "Que veux-tu demander à Atlas ?"; font.pixelSize: 15; color: Theme.subtext }
                    Flow {
                        width: 520
                        spacing: 8
                        Repeater {
                            model: win.examples
                            Rectangle {
                                required property string modelData
                                implicitWidth: exText.implicitWidth + 20
                                implicitHeight: 26
                                radius: 13
                                color: exMa.containsMouse ? Theme.rowHover : "transparent"
                                border.color: Theme.pillBorder
                                border.width: 1
                                BarText { id: exText; anchors.centerIn: parent; text: modelData; font.pixelSize: 11; color: exMa.containsMouse ? Theme.text : Theme.subtext }
                                MouseArea {
                                    id: exMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { input.text = modelData; input.forceActiveFocus(); input.cursorPosition = input.text.length; }
                                }
                            }
                        }
                    }
                }
            }

            // Saisie
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    color: Theme.pill
                    border.color: input.text !== "" ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.5) : Theme.pillBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    TextInput {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.labelFont
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
                            width: parent.width
                            elide: Text.ElideRight
                            visible: input.text === ""
                            text: win.busy ? "L'agent réfléchit…" : "Demande à l'agent d'Atlas…"
                            color: Theme.muted
                            font: input.font
                        }
                    }
                }

                // Envoyer / arrêter
                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 12
                    color: sendMa.containsMouse ? Theme.pillHover : Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1
                    scale: sendMa.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                    BarText {
                        anchors.centerIn: parent
                        text: win.busy ? Theme.ic(0xf04db) : Theme.ic(0xf048a)    // md-stop / md-send
                        font.pixelSize: 20
                        color: win.busy ? Theme.red : Theme.mauve
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

            // Rappel des touches
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [["Entrée", "envoyer"], ["Ctrl+N", "nouvelle discussion"], ["Échap", "fermer"]]
                    RowLayout {
                        required property var modelData
                        spacing: 6
                        Rectangle {
                            implicitWidth: keyText.implicitWidth + 10
                            implicitHeight: 18
                            radius: 5
                            color: Theme.pill
                            border.color: Theme.pillBorder
                            border.width: 1
                            BarText { id: keyText; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 10; color: Theme.subtext }
                        }
                        BarText { text: modelData[1]; font.pixelSize: 11; color: Theme.muted }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
