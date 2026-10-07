import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris

// Lecteur MPRIS : pochette + titre défilant ; clic : contrôles complets
Pill {
    id: root

    readonly property var players: Mpris.players.values
    // Lecteurs réels : Brave garde son MPRIS après fermeture de l'onglet vidéo (arrêté, sans
    // titre) → ignoré. L'état vide transitoire d'un changement de morceau n'est pas « arrêté ».
    readonly property var livePlayers: players.filter(p => p.playbackState !== MprisPlaybackState.Stopped || (p.trackTitle ?? "") !== "")
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? livePlayers[0] ?? players[0] ?? null
    // Métadonnées affichées, figées pendant les changements de morceau : le navigateur
    // publie ~0,5 s un état vide (pas de titre, logo Brave en pochette). On ne suit le
    // lecteur que lorsqu'il a un titre ; l'affichage n'est vidé qu'après 2 s sans titre.
    property string title: ""
    property string artist: ""
    property string album: ""
    property string art: ""
    // Source recalculée (la fenêtre Spotify change de titre après le MPRIS),
    // mais à partir du titre figé : l'état vide transitoire ne la perturbe pas
    readonly property string source: title !== "" ? sourceOf(player, title) : ""
    readonly property string sourceLabel: title !== "" ? sourceName(player, title) : ""
    function syncMeta() {
        const p = player;
        if (p && (p.trackTitle ?? "") !== "") {
            clearMeta.stop();
            title = p.trackTitle;
            artist = p.trackArtist ?? "";
            album = p.trackAlbum ?? "";
            art = p.trackArtUrl ?? "";
        } else if (!p) {
            clearMeta.stop();
            clearMeta.triggered();
        } else {
            clearMeta.restart();
        }
    }
    Timer {
        id: clearMeta
        interval: 2000
        onTriggered: {
            root.title = ""; root.artist = ""; root.album = ""; root.art = "";
        }
    }
    onPlayerChanged: syncMeta()
    Component.onCompleted: syncMeta()
    Connections {
        target: root.player
        function onTrackTitleChanged() { root.syncMeta(); }
        function onTrackArtistChanged() { root.syncMeta(); }
        function onTrackAlbumChanged() { root.syncMeta(); }
        function onTrackArtUrlChanged() { root.syncMeta(); }
    }

    // Source réelle d'un lecteur : Spotify / SoundCloud / YouTube tournent dans Brave, dont le
    // MPRIS ne donne pas l'URL. On cherche la fenêtre dont le titre contient le
    // morceau (PWA Spotify : "Titre • Artiste", PWA SoundCloud : "Titre by Artiste",
    // onglet : "Titre - YouTube").
    // Dernière source trouvée mémorisée par lecteur+morceau (en pause, le titre
    // de la fenêtre redevient générique).
    property var sourceCache: ({})
    function sourceOf(p, t) {
        if (!p) return "";
        const id = (p.identity + " " + p.desktopEntry + " " + p.dbusName).toLowerCase();
        if (id.indexOf("spotify") >= 0) return "spotify";
        const u = p.metadata["xesam:url"] ?? "";
        if (u.indexOf("youtube") >= 0 || u.indexOf("youtu.be") >= 0) return "youtube";
        if (!/brave|chrom|firefox/.test(id)) return "other";

        const key = p.dbusName + "|" + t;
        const win = t ? ToplevelManager.toplevels.values.find(w => (w.title || "").indexOf(t) >= 0) : null;
        if (win) {
            const s = ((win.appId || "") + " " + win.title).toLowerCase();
            const src = s.indexOf("spotify") >= 0 ? "spotify"
                      : s.indexOf("soundcloud") >= 0 ? "soundcloud"
                      : s.indexOf("youtube") >= 0 ? "youtube" : "web";
            sourceCache[key] = src;
            return src;
        }
        if (sourceCache[key]) return sourceCache[key];
        // Aucune fenêtre au titre du morceau (la PWA SoundCloud n'affiche pas toujours le
        // morceau, ex. « soundcloud.com/discover » ; un onglet en arrière-plan non plus) :
        // sources possibles d'après les fenêtres ouvertes (PWA par appId, onglet YouTube
        // visible par titre). Une seule → c'est elle ; sinon YouTube en arrière-plan.
        const wins = ToplevelManager.toplevels.values
            .map(w => ((w.appId || "") + " " + (w.title || "")).toLowerCase())
            .filter(w => /^(brave|chrom)/.test(w));    // pas l'appli Spotify native
        const cands = ["soundcloud", "spotify", "youtube"].filter(n => wins.some(w => w.indexOf(n) >= 0));
        return cands.length === 1 ? cands[0] : "youtube";
    }
    function sourceName(p, t) {
        const s = sourceOf(p, t);
        if (s === "spotify") return "Spotify";
        if (s === "soundcloud") return "SoundCloud";
        if (s === "youtube") return "YouTube";
        return p?.identity ?? "";
    }
    function sourceIcon(s) {
        if (s === "spotify") return Theme.ic(0xf1bc);
        if (s === "soundcloud") return Theme.ic(0xf1be);
        if (s === "youtube") return Theme.ic(0xf05c3);
        if (s === "web") return Theme.ic(0xf059f);
        return Theme.ic(0xf075a);
    }
    function sourceColor(s) {
        if (s === "spotify") return Theme.spotify;
        if (s === "soundcloud") return Theme.soundcloud;
        if (s === "youtube") return Theme.youtube;
        return Theme.yellow;
    }

    readonly property color accent: player ? sourceColor(source) : Theme.muted

    visible: player !== null && title !== ""

    // Clic sur l'en-tête du popup : affiche la fenêtre du lecteur (la lance si fermée).
    // focuswindow ouvre aussi le bureau spécial (Spotify rangé dans « magic »).
    function reEsc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
    function showPlayer() {
        popup.visible = false;
        const wins = ToplevelManager.toplevels.values;
        if (source === "spotify") {
            const w = wins.find(t => (t.appId || "").toLowerCase().indexOf("spotify") >= 0);
            if (w) Hyprland.dispatch("focuswindow class:^" + reEsc(w.appId) + "$");
            else Hyprland.dispatch("exec spotify");
            return;
        }
        if (source === "soundcloud") {
            const w = wins.find(t => (t.appId || "").toLowerCase().indexOf("soundcloud") >= 0);
            if (w) Hyprland.dispatch("focuswindow class:^" + reEsc(w.appId) + "$");
            else Hyprland.dispatch("exec brave --app=https://soundcloud.com");
            return;
        }
        const w = title ? wins.find(t => (t.title || "").indexOf(title) >= 0) : null;
        if (w) Hyprland.dispatch("focuswindow title:^" + reEsc(w.title) + "$");
        else if (player?.canRaise) player.raise();
    }

    // ColorQuantizer ne lit que des fichiers locaux : la pochette distante (Spotify natif,
    // https://i.scdn.co/…) est d'abord téléchargée en cache. Les anciennes couleurs
    // restent le temps du téléchargement.
    property string quantArt: ""
    Process {
        id: coverFetch
        property string url: ""
        property string dest: ""
        onExited: code => { if (code === 0 && url === root.art) root.quantArt = "file://" + dest; }
    }
    onArtChanged: {
        if (!/^https?:/.test(art)) { quantArt = art; return; }
        coverFetch.running = false;
        coverFetch.url = art;
        coverFetch.dest = "/tmp/quickshell-covers/" + art.replace(/[^A-Za-z0-9]/g, "_").slice(-80);
        coverFetch.command = [Paths.curl, "-sfL", "--max-time", "5", "--create-dirs", "-o", coverFetch.dest, art];
        coverFetch.running = true;
    }

    // Couleurs de l'artiste / de l'album tirées de la pochette : les 2 teintes les plus
    // vives, éclaircies pour rester lisibles sur le fond sombre (sinon bleu / mauve)
    ColorQuantizer {
        id: coverColors
        source: root.quantArt
        depth: 3            // 8 couleurs dominantes
        rescaleSize: 64
    }
    readonly property var vividColors: coverColors.colors.slice()
        .sort((a, b) => (b.hsvSaturation * b.hsvValue) - (a.hsvSaturation * a.hsvValue))
    function readable(c, minL) {
        return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, Math.max(c.hslLightness, minL), 1);
    }
    readonly property bool hasCover: art !== "" && vividColors.length > 0
    readonly property color artistColor: hasCover ? readable(vividColors[0], 0.72) : Theme.blue
    readonly property color albumColor: hasCover ? readable(vividColors[Math.min(1, vividColors.length - 1)], 0.62) : Theme.mauve
    // Titre de la barre : teinte la plus vive de la pochette (sinon couleur de la source),
    // éclaircie sur fond sombre / assombrie sur fond clair (Theme.barText noir = fond clair) ;
    // en pause : même teinte presque désaturée (Theme.muted était illisible sur la barre)
    function onBar(c) {
        const dark = Theme.barText.r < 0.5;
        return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation,
                       dark ? Math.min(c.hslLightness, 0.28) : Math.max(c.hslLightness, 0.72), 1);
    }
    readonly property color playColor: hasCover ? onBar(vividColors[0]) : accent
    readonly property color titleColor: player?.isPlaying ? playColor
        : onBar(Qt.hsla(Math.max(0, playColor.hslHue), playColor.hslSaturation * 0.25, playColor.hslLightness, 1))

    // Transition de morceau : glisse depuis la droite (suivant) ou la gauche (précédent)
    property int trackDir: 1
    onTitleChanged: {
        headerAnim.restart();
        pillAnim.restart();
        trackDir = 1;
    }
    function prevTrack() { trackDir = -1; player.previous(); }
    function nextTrack() { trackDir = 1; player.next(); }
    framed: false
    hpad: 4

    // Double tampon : l'ancienne pochette reste affichée jusqu'à ce que la nouvelle
    // soit chargée (pas de case vide entre deux morceaux) ; sert à la barre et au popup
    property string shownArt: ""
    Image {
        visible: false
        asynchronous: true
        source: root.art
        onSourceChanged: if (source == "") root.shownArt = ""
        onStatusChanged: if (status === Image.Ready) root.shownArt = source
    }

    // Pochette, arrondie comme les pastilles de la barre ; logo de la source à défaut
    ClippingRectangle {
        Layout.preferredWidth: 24
        Layout.preferredHeight: 24
        radius: 10
        color: "transparent"
        opacity: root.player?.isPlaying ? 1 : 0.5
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Image {
            anchors.fill: parent
            visible: root.shownArt !== ""
            source: root.shownArt
            fillMode: Image.PreserveAspectCrop
            mipmap: true
        }
        BarText {
            anchors.centerIn: parent
            visible: root.shownArt === ""
            text: root.sourceIcon(root.source)
            color: root.accent
            font.pixelSize: 15
        }
    }

    // Titre défilant (marquee) quand il dépasse la largeur disponible
    Item {
        visible: !root.compact
        Layout.preferredWidth: Math.min(scrollText.implicitWidth, 190)
        Layout.preferredHeight: 20
        clip: true

        BarText {
            id: scrollText
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: root.titleColor
            Behavior on color { ColorAnimation { duration: 400 } }
            font.family: Theme.trackFont
            font.bold: root.player?.isPlaying ?? false
            transform: Translate { id: pillShift }

            ParallelAnimation {
                id: pillAnim
                NumberAnimation { target: pillShift; property: "x"; from: 18 * root.trackDir; to: 0; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: scrollText; property: "opacity"; from: 0; to: 1; duration: 260 }
            }

            readonly property real overflow: implicitWidth - parent.width
            x: 0
            SequentialAnimation on x {
                running: scrollText.overflow > 0 && !root.compact
                loops: Animation.Infinite
                PauseAnimation { duration: 2000 }
                NumberAnimation { to: -scrollText.overflow; duration: Math.max(0, scrollText.overflow) * 30 }
                PauseAnimation { duration: 1500 }
                NumberAnimation { to: 0; duration: 400 }
                onStopped: scrollText.x = 0
            }
        }
    }

    onClicked: event => {
        if (!player) return;
        if (event.button === Qt.MiddleButton) player.togglePlaying();
        else if (event.button === Qt.RightButton) root.nextTrack();
        else popup.toggle();
    }

    // La position MPRIS n'est pas poussée : on la rafraîchit pendant l'affichage
    Timer {
        running: popup.visible && (root.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    BarPopup {
        id: popup
        target: root
        contentWidth: 320

        // En-tête cliquable (→ fenêtre du lecteur) ; animé à chaque changement de morceau
        Rectangle {
            id: headerBox
            Layout.fillWidth: true
            implicitHeight: header.implicitHeight + 8
            radius: 12
            color: headerMa.containsMouse ? Theme.rowHover : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            scale: headerMa.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
            ClickFx { id: headerFx }

            ParallelAnimation {
                id: headerAnim
                NumberAnimation { target: headerShift; property: "x"; from: 32 * root.trackDir; to: 0; duration: 340; easing.type: Easing.OutCubic }
                NumberAnimation { target: header; property: "opacity"; from: 0; to: 1; duration: 280 }
                NumberAnimation { target: cover; property: "scale"; from: 0.88; to: 1; duration: 380; easing.type: Easing.OutBack }
            }

        RowLayout {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 4
            spacing: 12
            transform: Translate { id: headerShift }
            ClippingRectangle {
                id: cover
                Layout.preferredWidth: 88
                Layout.preferredHeight: 88
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.08)
                Image {
                    anchors.fill: parent
                    source: root.shownArt
                    fillMode: Image.PreserveAspectCrop
                }
                BarText {
                    anchors.centerIn: parent
                    visible: root.art === ""
                    text: root.sourceIcon(root.source)
                    font.pixelSize: 36
                    color: Theme.muted
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                BarText { Layout.fillWidth: true; text: root.title; font.family: Theme.titleFont; font.bold: true; font.pixelSize: 15; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
                BarText {
                    font.family: Theme.labelFont
                    Layout.fillWidth: true; text: root.artist; elide: Text.ElideRight; visible: text !== ""
                    color: root.artistColor
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
                BarText {
                    font.family: Theme.labelFont
                    Layout.fillWidth: true; text: root.album; font.pixelSize: 12; elide: Text.ElideRight; visible: text !== ""
                    color: root.albumColor
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
                RowLayout {
                    spacing: 5
                    BarText { text: root.sourceIcon(root.source); color: root.accent; font.pixelSize: 14 }
                    BarText { text: root.sourceLabel; color: root.accent; font.pixelSize: 12; font.bold: true; font.family: Theme.labelFont }
                }
            }
        }

            MouseArea {
                id: headerMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { headerFx.play(); root.showPlayer(); }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: !!root.player && root.player.lengthSupported && root.player.length > 0
            spacing: 2
            Slider {
                Layout.fillWidth: true
                accent: root.accent
                interactive: root.player?.canSeek ?? false
                value: root.player ? root.player.position / root.player.length : 0
                onMoved: v => root.player.position = v * root.player.length
            }
            RowLayout {
                Layout.fillWidth: true
                BarText { text: Theme.fmtTime(root.player?.position); color: Theme.subtext; font.pixelSize: 11; font.family: Theme.labelFont }
                Item { Layout.fillWidth: true }
                BarText { text: Theme.fmtTime(root.player?.length); color: Theme.subtext; font.pixelSize: 11; font.family: Theme.labelFont }
            }
        }

        // Lecture au centre ; choix du lecteur (si plusieurs sont ouverts) sur la même ligne,
        // logos seuls répartis aux deux extrémités
        Item {
            Layout.fillWidth: true
            implicitHeight: transport.implicitHeight
            readonly property int half: Math.ceil(root.livePlayers.length / 2)

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: root.livePlayers.length > 1
                Repeater { model: root.livePlayers.slice(0, parent.parent.half); delegate: playerBtn }
            }

            RowLayout {
                id: transport
                anchors.centerIn: parent
                spacing: 12
                ActionButton {
                    icon: Theme.ic(0xf04ae)
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.prevTrack()
                }
                ActionButton {
                    icon: root.player?.isPlaying ? Theme.ic(0xf03e4) : Theme.ic(0xf040a)
                    accent: root.accent
                    highlighted: true
                    implicitWidth: 48
                    onClicked: root.player.togglePlaying()
                }
                ActionButton {
                    icon: Theme.ic(0xf04ad)
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.nextTrack()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: root.livePlayers.length > 1
                Repeater { model: root.livePlayers.slice(parent.parent.half); delegate: playerBtn }
            }
        }

        Component {
            id: playerBtn
            ActionButton {
                required property MprisPlayer modelData
                implicitWidth: 40
                icon: root.sourceIcon(root.sourceOf(modelData, modelData.trackTitle))
                highlighted: modelData === root.player
                accent: root.sourceColor(root.sourceOf(modelData, modelData.trackTitle))
                onClicked: {
                    if (!modelData.isPlaying) {
                        for (const p of root.players) if (p.isPlaying) p.pause();
                        modelData.play();
                    }
                }
            }
        }
    }
}
