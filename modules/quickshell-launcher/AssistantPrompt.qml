import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Assistant (SUPER+K) : champ de demande en français, envoyé au script `assistant`
// (modules/assistant.nix) qui répond par notification. Entrée : envoyer ; haut / bas :
// demandes précédentes ; micro : passer à la voix (voice-to-text --assistant).
PanelWindow {
    id: win

    WlrLayershell.namespace: "quickshell-assistant"
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
        input.text = "";
        histPos = -1;
        closeTimer.stop();
        visible = true;
        open = true;
        input.forceActiveFocus();
    }
    function hide() {
        open = false;
        closeTimer.restart();
    }
    function toggle() { open ? hide() : show(); }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!win.open) win.visible = false }

    // --- Envoi -------------------------------------------------------------------------
    // Demandes de la session, la plus récente d'abord (flèche haut pour les rappeler)
    property var history: []
    property int histPos: -1

    function send(text) {
        const t = text.trim();
        if (t === "") return;
        history = [t].concat(history.filter(h => h !== t)).slice(0, 30);
        hide();
        Quickshell.execDetached([Paths.userBin + "/assistant", t]);
    }
    function voice() {
        hide();
        Quickshell.execDetached([Paths.userBin + "/voice-to-text", "--assistant"]);
    }
    function recall(d) {
        if (history.length === 0) return;
        histPos = Math.max(-1, Math.min(history.length - 1, histPos + d));
        input.text = histPos < 0 ? "" : history[histPos];
        input.cursorPosition = input.text.length;
    }

    readonly property var examples: [
        "Mets Ciao de Werenoi sur Spotify",
        "Minuteur de 10 minutes",
        "Ouvre Discord",
        "youtube.com"
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
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.28)
        width: Math.min(620, parent.width - 80)
        height: content.implicitHeight + 32
        radius: 18
        color: Qt.rgba(22 / 255, 22 / 255, 22 / 255, 0.8)
        border.color: Theme.border
        border.width: 1

        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }    // le clic dans le panneau ne ferme pas

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Champ de demande
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    color: Theme.pill
                    border.color: input.text !== "" ? Qt.rgba(Theme.mauve.r, Theme.mauve.g, Theme.mauve.b, 0.5) : Theme.pillBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10
                        BarText { text: Theme.ic(0xf06a9); font.pixelSize: 20; color: Theme.mauve }    // md-robot
                        TextInput {
                            id: input
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            font.family: Theme.labelFont
                            font.pixelSize: 15
                            clip: true
                            selectByMouse: true
                            focus: true
                            Keys.onPressed: event => {
                                event.accepted = true;
                                switch (event.key) {
                                case Qt.Key_Escape: win.hide(); break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter: win.send(input.text); break;
                                case Qt.Key_Up: win.recall(1); break;
                                case Qt.Key_Down: win.recall(-1); break;
                                default: event.accepted = false;
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                elide: Text.ElideRight
                                visible: input.text === ""
                                text: "Demande à l'assistant…"
                                color: Theme.muted
                                font: input.font
                            }
                        }
                    }
                }

                // Passer à la voix
                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 12
                    color: micMa.containsMouse ? Theme.pillHover : Theme.pill
                    border.color: Theme.pillBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: micMa.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                    BarText {
                        anchors.centerIn: parent
                        text: Theme.ic(0xf036c)    // md-microphone
                        font.pixelSize: 20
                        color: micMa.containsMouse ? Theme.red : Theme.subtext
                    }
                    MouseArea {
                        id: micMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.voice()
                    }
                }
            }

            // Exemples cliquables (champ vide)
            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: input.text === ""
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
                        BarText {
                            id: exText
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 11
                            color: exMa.containsMouse ? Theme.text : Theme.subtext
                        }
                        MouseArea {
                            id: exMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { input.text = modelData; input.forceActiveFocus(); }
                        }
                    }
                }
            }

            // Rappel des touches
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: [["Entrée", "envoyer"], ["↑", "précédente"], ["Maj+Super+K", "voix"], ["Échap", "fermer"]]
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
