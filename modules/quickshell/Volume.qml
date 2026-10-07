import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Widgets

// Volume : molette = ±5 % ; clic : sortie, volume, mélangeur dépliable (volume par application)
Pill {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    // Les properties d'un nœud restent vides tant qu'il n'est pas suivi : on suit tous les
    // flux, puis on garde les sorties audio (lecture), pas les micros
    readonly property var allStreams: Pipewire.nodes.values.filter(n => n.isStream)
    readonly property var streams: allStreams.filter(n => n.audio && n.properties["media.class"] === "Stream/Output/Audio")

    PwObjectTracker { objects: [root.sink].concat(root.sinks).concat(root.allStreams) }

    // Sorties masquées (node.name PipeWire, stable), partagées entre les barres
    property var hiddenSinks: []
    FileView {
        id: hiddenFile
        path: Quickshell.statePath("hidden-sinks.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.hiddenSinks = JSON.parse(text()); } catch (e) { root.hiddenSinks = []; }
        }
    }
    function isHidden(n) { return hiddenSinks.indexOf(n.name) >= 0; }
    function toggleHidden(n) {
        const l = isHidden(n) ? hiddenSinks.filter(x => x !== n.name) : hiddenSinks.concat([n.name]);
        hiddenSinks = l;
        hiddenFile.setText(JSON.stringify(l, null, 2));
    }
    // Noms personnalisés { node.name: "nom" } (barre uniquement), vide = nom d'origine
    property var sinkNames: ({})
    FileView {
        id: namesFile
        path: Quickshell.statePath("sink-names.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.sinkNames = JSON.parse(text()); } catch (e) { root.sinkNames = {}; }
        }
    }
    function origName(n) { return n.description || n.nickname || n.name; }
    function sinkLabel(n) { return sinkNames[n.name] || origName(n); }
    function renameSink(n, label) {
        const m = Object.assign({}, sinkNames);
        const t = label.trim();
        if (t === "" || t === origName(n)) delete m[n.name];
        else m[n.name] = t;
        sinkNames = m;
        namesFile.setText(JSON.stringify(m, null, 2));
    }

    // Mode édition (crayon) : toutes les sorties, nom modifiable + œil pour masquer/afficher.
    // Hors édition : sorties masquées retirées, sauf la sortie active.
    property bool editSinks: false
    readonly property var shownSinks: editSinks ? sinks : sinks.filter(n => !isHidden(n) || n === sink)

    // Mélangeur (replié par défaut) : un flux audio par application, relié à sa fenêtre
    // Hyprland par PID (sinon par classe : Brave/Chrome jouent depuis un sous-processus)
    property bool mixerOpen: false
    // Nouvelle appli qui joue pendant que le mélangeur est affiché → retrouver sa fenêtre
    onStreamsChanged: if (mixerOpen && popup.visible) Hyprland.refreshToplevels()
    function streamWindows(n) {
        const p = n.properties;
        const pid = Number(p["application.process.id"] ?? 0);
        const tl = Hyprland.toplevels.values;
        const byPid = pid > 0 ? tl.filter(t => t.lastIpcObject?.pid === pid) : [];
        if (byPid.length > 0) return byPid;
        const keys = [p["application.name"], p["application.process.binary"], p["application.id"]]
            .filter(k => k).map(k => String(k).toLowerCase().replace(/^\./, "").replace(/-wrapped$/, ""));
        return tl.filter(t => {
            const c = (t.lastIpcObject?.class ?? "").toLowerCase();
            return c !== "" && keys.some(k => c === k || c.startsWith(k + "-") || k.startsWith(c));
        });
    }
    function streamEntry(n, cls) {
        DesktopEntries.applications.values.length;   // ré-évalue une fois les .desktop chargés
        return DesktopEntries.heuristicLookup(cls || n.properties["application.name"] || "");
    }
    function streamIcon(n, cls, entry) {
        const p = n.properties;
        for (const i of [entry?.icon, p["application.icon_name"], cls.toLowerCase(),
                         String(p["application.name"] ?? "").toLowerCase()]) {
            if (!i) continue;
            if (i.startsWith("/")) return "file://" + i;
            const s = Quickshell.iconPath(i, true);
            if (s) return s;
        }
        return "";
    }

    function icon(v, m) {
        if (m) return Theme.ic(0xf075f);
        if (v < 0.34) return Theme.ic(0xf057f);
        if (v < 0.67) return Theme.ic(0xf0580);
        return Theme.ic(0xf057e);
    }
    // 0 % = muet ; remonter le volume retire le muet
    function setVol(v) {
        if (!sink?.audio) return;
        const nv = Math.max(0, Math.min(1, v));
        sink.audio.volume = nv;
        sink.audio.muted = nv < 0.005;
    }

    // Volume mis à 0 ailleurs (pwvucontrol, appli…) → muet aussi
    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() {
            const a = root.sink.audio;
            if (a.volume < 0.005 && !a.muted) a.muted = true;
        }
    }

    readonly property color tint: muted ? Theme.red : Theme.lerpColor(Qt.color(Theme.muted), Qt.color("#91cfe5"), Math.min(1, vol))

    BarText { text: root.icon(root.vol, root.muted); color: root.tint }
    BarText {
        visible: !root.muted && !root.compact
        text: Math.round(root.vol * 100) + "%"
        color: root.tint
        font.family: Theme.labelFont
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }

    onScrolled: event => setVol(vol + (event.angleDelta.y > 0 ? 0.05 : -0.05))
    onClicked: event => {
        if (event.button === Qt.MiddleButton) { if (sink?.audio) sink.audio.muted = !muted; }
        else popup.toggle();
    }

    BarPopup {
        id: popup
        target: root
        contentWidth: 320
        onVisibleChanged: {
            if (!visible) root.editSinks = false;
            else if (root.mixerOpen) Hyprland.refreshToplevels();
        }

        PopupHeader { title: "Son" }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ActionButton {
                icon: root.icon(root.vol, root.muted)
                accent: root.muted ? Theme.red : Theme.sky
                onClicked: if (root.sink?.audio) root.sink.audio.muted = !root.muted
            }
            Slider {
                Layout.fillWidth: true
                accent: root.muted ? Theme.muted : Theme.sky
                value: root.vol
                onMoved: v => root.setVol(v)
            }
            BarText { text: Math.round(root.vol * 100) + "%"; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight; font.family: Theme.labelFont }
        }

        Separator {}
        RowLayout {
            Layout.fillWidth: true
            BarText { text: "Sortie"; color: Theme.subtext; font.pixelSize: 12; Layout.fillWidth: true; font.family: Theme.labelFont }
            ActionButton {
                implicitWidth: 26
                implicitHeight: 22
                icon: Theme.ic(0xf0cb6)       // md-pencil_outline : renommer / masquer des sorties
                accent: Theme.sky
                highlighted: root.editSinks
                onClicked: root.editSinks = !root.editSinks
            }
        }

        Repeater {
            model: root.shownSinks
            ColumnLayout {
                id: sinkEntry
                required property PwNode modelData
                readonly property bool hidden: root.isHidden(modelData)
                Layout.fillWidth: true
                spacing: 0

                ListRow {
                    visible: !root.editSinks
                    // Bluetooth : icône du type choisi dans les réglages Bluetooth (DevTypes)
                    readonly property var devIcon: DevTypes.sinkIcon(sinkEntry.modelData)
                    icon: Theme.ic(devIcon.icon)
                    iconFont: devIcon.font || Theme.font
                    // AirPods : même logo que leur menu
                    iconImage: /airpod/i.test(sinkEntry.modelData.description) ? Qt.resolvedUrl("airpods.png") : ""
                    iconColor: active ? Theme.sky : Theme.subtext
                    label: root.sinkLabel(sinkEntry.modelData)
                    active: sinkEntry.modelData === root.sink
                    onClicked: Pipewire.preferredDefaultAudioSink = sinkEntry.modelData
                }

                // Édition : [nom] [✓ si modifié] [œil]
                RowLayout {
                    visible: root.editSinks
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    spacing: 6
                    opacity: sinkEntry.hidden ? 0.45 : 1
                    Field {
                        id: nameField
                        placeholder: root.origName(sinkEntry.modelData)
                        text: root.sinkLabel(sinkEntry.modelData)
                        onAccepted: root.renameSink(sinkEntry.modelData, text)
                    }
                    ActionButton {
                        visible: nameField.text.trim() !== root.sinkLabel(sinkEntry.modelData)
                        implicitWidth: 30
                        implicitHeight: 30
                        icon: Theme.ic(0xf012c)
                        accent: Theme.green
                        onClicked: root.renameSink(sinkEntry.modelData, nameField.text)
                    }
                    ActionButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        icon: Theme.ic(sinkEntry.hidden ? 0xf06d1 : 0xf06d0)
                        accent: Theme.sky
                        onClicked: root.toggleHidden(sinkEntry.modelData)
                    }
                }
            }
        }

        Separator {}

        // Mélangeur : en-tête cliquable qui déplie le volume de chaque application
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 8
            color: mixMa.containsMouse ? Theme.rowHover : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            ClickFx { id: mixFx }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                BarText {
                    text: Theme.ic(0xf066a)       // md-tune_vertical
                    color: root.mixerOpen ? Theme.mauve : Theme.subtext
                    font.pixelSize: 16
                    Layout.preferredWidth: 20
                    horizontalAlignment: Text.AlignHCenter
                }
                BarText { text: "Mélangeur"; Layout.fillWidth: true; font.family: Theme.labelFont; font.bold: root.mixerOpen }
                BarText {
                    text: root.streams.length === 0 ? "aucune appli"
                        : root.streams.length + (root.streams.length > 1 ? " applis" : " appli")
                    color: Theme.subtext
                    font.pixelSize: 12
                    font.family: Theme.labelFont
                }
                BarText {
                    text: Theme.ic(0xf0140)       // md-chevron_down
                    color: Theme.subtext
                    rotation: root.mixerOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
            MouseArea {
                id: mixMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    mixFx.play();
                    root.mixerOpen = !root.mixerOpen;
                    if (root.mixerOpen) Hyprland.refreshToplevels();
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.mixerOpen ? mixCol.implicitHeight : 0
            Layout.topMargin: root.mixerOpen ? 0 : -10   // replié : pas d'espace fantôme
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            clip: true
            opacity: root.mixerOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            ColumnLayout {
                id: mixCol
                width: parent.width
                spacing: 10

                BarText {
                    visible: root.streams.length === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    text: "Aucune application ne joue de son"
                    color: Theme.subtext
                    font.pixelSize: 12
                    font.family: Theme.labelFont
                }

                Repeater {
                    model: root.streams
                    ColumnLayout {
                        id: app
                        required property PwNode modelData
                        readonly property var props: modelData.properties
                        readonly property var wins: root.streamWindows(modelData)
                        readonly property string cls: wins.length > 0 ? (wins[0].lastIpcObject?.class ?? "") : ""
                        readonly property var entry: root.streamEntry(modelData, cls)
                        readonly property string iconSrc: root.streamIcon(modelData, cls, entry)
                        readonly property string appName: entry?.name ?? props["application.name"] ?? modelData.name
                        // Une seule fenêtre → son titre ; sinon le nom du flux s'il apporte quelque chose
                        readonly property string sub: wins.length === 1 ? (wins[0].title ?? "")
                            : (props["media.name"] && props["media.name"] !== appName ? props["media.name"] : "")
                        readonly property real vol: modelData.audio?.volume ?? 0
                        readonly property bool mute: modelData.audio?.muted ?? false
                        Layout.fillWidth: true
                        spacing: 4

                        // [icône] [appli · fenêtre] — clic = afficher la fenêtre
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: 6
                            color: winMa.containsMouse && app.wins.length > 0 ? Theme.rowHover : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 8
                                IconImage {
                                    visible: app.iconSrc !== ""
                                    source: app.iconSrc
                                    implicitSize: 20
                                }
                                BarText {
                                    visible: app.iconSrc === ""
                                    text: Theme.ic(0xf075a)   // md-music_note : appli sans icône
                                    color: Theme.mauve
                                    font.pixelSize: 16
                                    Layout.preferredWidth: 20
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                BarText {
                                    text: app.appName
                                    font.family: Theme.labelFont
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                BarText {
                                    visible: app.sub !== ""
                                    Layout.fillWidth: true
                                    text: app.sub
                                    elide: Text.ElideRight
                                    color: Theme.subtext
                                    font.family: Theme.labelFont
                                    font.pixelSize: 11
                                }
                                Item { visible: app.sub === ""; Layout.fillWidth: true }
                            }
                            MouseArea {
                                id: winMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: app.wins.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (app.wins.length === 0) return;
                                    popup.visible = false;
                                    Hyprland.dispatch("focuswindow address:0x" + app.wins[0].address);
                                }
                            }
                        }

                        // [muet] [glissière] [%]
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            spacing: 8
                            ActionButton {
                                implicitWidth: 26
                                implicitHeight: 22
                                icon: root.icon(app.vol, app.mute)
                                accent: app.mute ? Theme.red : Theme.mauve
                                onClicked: if (app.modelData.audio) app.modelData.audio.muted = !app.mute
                            }
                            Slider {
                                Layout.fillWidth: true
                                accent: app.mute ? Theme.muted : Theme.mauve
                                value: app.vol
                                onMoved: v => {
                                    app.modelData.audio.volume = v;
                                    if (app.mute && v > 0.005) app.modelData.audio.muted = false;
                                }
                            }
                            BarText {
                                text: Math.round(app.vol * 100) + "%"
                                font.pixelSize: 11
                                color: app.mute ? Theme.red : Theme.subtext
                                Layout.preferredWidth: 38
                                horizontalAlignment: Text.AlignRight
                                font.family: Theme.labelFont
                            }
                        }
                    }
                }
            }
        }

        ActionButton {
            Layout.alignment: Qt.AlignRight
            icon: Theme.ic(0xf0493)
            label: "Mixeur avancé"
            onClicked: {
                popup.visible = false;
                Hyprland.dispatch("exec [float; center; size 700 500; animation popin] pwvucontrol");
            }
        }
    }
}
