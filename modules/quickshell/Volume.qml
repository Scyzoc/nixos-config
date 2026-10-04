import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// Volume : molette = ±5 % ; clic : sortie, volume, volume par application
Pill {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio
                                                                && n.properties["media.class"] === "Stream/Output/Audio")

    PwObjectTracker { objects: [root.sink].concat(root.sinks).concat(root.streams) }

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
        onVisibleChanged: if (!visible) root.editSinks = false

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
            BarText { text: Math.round(root.vol * 100) + "%"; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
        }

        Separator {}
        RowLayout {
            Layout.fillWidth: true
            BarText { text: "Sortie"; color: Theme.subtext; font.pixelSize: 12; Layout.fillWidth: true }
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

        Separator { visible: root.streams.length > 0 }
        BarText { visible: root.streams.length > 0; text: "Applications"; color: Theme.subtext; font.pixelSize: 12 }

        Repeater {
            model: root.streams
            ColumnLayout {
                required property PwNode modelData
                Layout.fillWidth: true
                spacing: 2
                BarText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    text: (modelData.properties["application.name"] ?? modelData.name)
                          + (modelData.properties["media.name"] ? "  ·  " + modelData.properties["media.name"] : "")
                }
                RowLayout {
                    Layout.fillWidth: true
                    Slider {
                        Layout.fillWidth: true
                        accent: Theme.mauve
                        value: modelData.audio?.volume ?? 0
                        onMoved: v => modelData.audio.volume = v
                    }
                    BarText { text: Math.round((modelData.audio?.volume ?? 0) * 100) + "%"; font.pixelSize: 11; color: Theme.subtext; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
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
