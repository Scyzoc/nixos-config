import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth

// Bluetooth ; clic : activer, scanner, (dé)connecter les appareils ;
// roue dentée d'un appareil connu : nom, MAC, type (icône), oublier
Pill {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var devices: Bluetooth.devices.values
    readonly property var connected: devices.filter(d => d.connected)
    readonly property BluetoothDevice main: connected[0] ?? null
    readonly property bool isAirpods: main !== null && main.name.toLowerCase().indexOf("airpod") >= 0

    // Batteries G/D/boîtier des AirPods : au pourcent près par la connexion du contrôle du
    // bruit (AncState), sinon par dizaines via le scan Bluetooth d'airpods-monitor
    property var airpodsBle: ({})
    FileView {
        id: airpodsFile
        path: "/tmp/airpods_battery.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.airpodsBle = JSON.parse(text()); } catch (e) { root.airpodsBle = {}; }
        }
    }
    readonly property var airpods: AncState.battery.left !== undefined ? AncState.battery : airpodsBle
    readonly property var airpodsCharging: AncState.battery.left !== undefined ? AncState.charging : ({})

    readonly property var budLevels: [airpods.left, airpods.right].filter(v => v !== null && v !== undefined)
    readonly property bool critical: isAirpods && budLevels.length > 0 && Math.min(...budLevels) <= 15
                                     || (main !== null && main.batteryAvailable && !isAirpods && main.battery <= 0.15)

    alert: critical

    // Menu Bluetooth / AirPods ouvert, sur n'importe quel écran (btPill : marqueur pour PopupState)
    readonly property bool btPill: true
    readonly property bool btMenuOpen: PopupState.current?.target?.btPill ?? false

    // (Dé)connexion, menu fermé : annonce « <nom> connecté ● » (vert) / « déconnecté ● » (rouge)
    // qui sort de la pastille. Pas d'annonce pour les appareils déjà connectés au lancement.
    // wasConnected : adresse → { name, airpods, icon, iconFont } (l'appareil peut disparaître
    // à la déconnexion, d'où la copie)
    property var wasConnected: ({})
    property bool announceArmed: false
    Timer { interval: 3000; running: true; onTriggered: root.announceArmed = true }
    onConnectedChanged: {
        const now = {};
        let fresh = null, gone = null;
        for (const d of connected) {
            now[d.address] = {
                name: d.name || d.address,
                airpods: d.name.toLowerCase().indexOf("airpod") >= 0,
                icon: devIcon(d),
                iconFont: devIconFont(d)
            };
            if (!wasConnected[d.address]) fresh = now[d.address];
        }
        for (const a in wasConnected) if (!now[a]) gone = wasConnected[a];
        wasConnected = now;
        if (!announceArmed || btMenuOpen) return;
        if (fresh) toast.show(fresh, true);
        else if (gone) toast.show(gone, false);
    }
    onBtMenuOpenChanged: if (btMenuOpen) toast.hide()

    // AirPods : survol et clic séparés au milieu du trait (icône | nom)
    splitX: isAirpods && !compact ? divider.parent.x + divider.x + 0.5 : -1

    // Un adaptateur bloqué par rfkill (ex. après le mode avion) ne peut pas être
    // allumé directement : on le débloque d'abord, puis on l'allume.
    readonly property bool blocked: adapter?.state === BluetoothAdapterState.Blocked
    Process {
        id: unblock
        command: [Paths.rfkill, "unblock", "bluetooth"]
        onExited: powerOn.restart()
    }
    Timer {
        id: powerOn
        interval: 700
        onTriggered: if (root.adapter && !root.blocked) root.adapter.enabled = true
    }
    function setPower(on) {
        if (!adapter) return;
        if (on && blocked) unblock.running = true;
        else adapter.enabled = on;
    }

    // Types d'appareil (icônes) : partagés avec le menu son (DevTypes.qml)
    readonly property var typeDefs: DevTypes.defs
    readonly property var types: DevTypes.types
    function setType(addr, t) { DevTypes.set(addr, t); }

    // Connus d'abord (connectés en tête), inconnus seulement pendant une recherche
    readonly property var knownDevices: powered
        ? devices.filter(d => d.paired || d.connected)
                 .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
        : []
    readonly property var otherDevices: powered && (adapter?.discovering ?? false)
        ? devices.filter(d => !d.paired && !d.connected).sort((a, b) => a.name.localeCompare(b.name))
        : []

    // Ligne d'appareil (+ réglages dépliables), partagée par les deux listes
    Component {
        id: deviceRow

            ColumnLayout {
                id: entry
                required property BluetoothDevice modelData
                Layout.fillWidth: true
                spacing: 4

                ListRow {
                    icon: root.devIcon(entry.modelData)
                    iconFont: root.devIconFont(entry.modelData)
                    iconColor: entry.modelData.connected ? Theme.bluetooth : Theme.subtext
                    label: entry.modelData.name || entry.modelData.address
                    detail: root.devDetail(entry.modelData)
                    active: entry.modelData.connected
                    // (Dé)connexion / appairage en cours : icône de chargement (ListRow.busy)
                    busy: entry.modelData.state === BluetoothDeviceState.Connecting
                          || entry.modelData.state === BluetoothDeviceState.Disconnecting
                          || entry.modelData.pairing
                    dot: entry.modelData.connected && root.devDetail(entry.modelData) === ""
                    // Réglages : appareils connus seulement
                    actionIcon: entry.modelData.paired ? Theme.ic(0xf0493) : ""
                    actionActive: root.settingsFor === entry.modelData.address
                    onActionClicked: root.settingsFor = root.settingsFor === entry.modelData.address ? "" : entry.modelData.address
                    onClicked: {
                        if (entry.modelData.connected) entry.modelData.disconnect();
                        else if (entry.modelData.paired) entry.modelData.connect();
                        else { entry.modelData.trusted = true; entry.modelData.pair(); }
                    }
                }

                // Réglages : dépliage animé (hauteur + fondu + glissement), repli
                // inverse puis déchargement une fois la hauteur revenue à 0
                Item {
                    id: panel
                    readonly property bool open: entry.modelData.paired && root.settingsFor === entry.modelData.address
                    Layout.fillWidth: true
                    Layout.preferredHeight: open ? (settings.item?.implicitHeight ?? 0) : 0
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    visible: Layout.preferredHeight > 0
                    clip: true
                    opacity: open ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Loader {
                        id: settings
                        width: parent.width
                        y: panel.open ? 0 : -14
                        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        active: panel.open || panel.Layout.preferredHeight > 0
                        sourceComponent: BtSettings {
                            device: entry.modelData
                            typeDefs: root.typeDefs
                            type: root.types[entry.modelData.address] ?? "auto"
                            onTypeChosen: t => root.setType(entry.modelData.address, t)
                            onForgotten: {
                                root.setType(entry.modelData.address, "auto");
                                root.settingsFor = "";
                            }
                        }
                    }
                }
            }
    }

    // Appareil dont les réglages sont ouverts (adresse MAC)
    property string settingsFor: ""

    // Type effectif : choix de l'utilisateur, sinon AirPods → écouteurs
    function devType(d) { return DevTypes.typeOf(d.address, d.name); }
    function devIconFont(d) { return devType(d)?.font ?? Theme.font; }
    function devIcon(d) {
        const t = devType(d);
        if (t) return Theme.ic(t.icon);
        const i = (d.icon || "").toLowerCase();
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return Theme.ic(0xf02cb);
        if (i.indexOf("mouse") >= 0) return Theme.ic(0xf037d);
        if (i.indexOf("keyboard") >= 0) return Theme.ic(0xf030c);
        if (i.indexOf("phone") >= 0) return Theme.ic(0xf011c);
        return Theme.ic(0xf00af);
    }
    function devDetail(d) {
        // AirPods : batteries G / D / boîtier déjà dans l'en-tête du menu → rien dans la liste
        if (d.connected && d.name.toLowerCase().indexOf("airpod") >= 0) return "";
        if (d.connected && d.batteryAvailable) return Math.round(d.battery * 100) + "%";
        if (d.connected) return "";    // point vert (ListRow.dot)
        return d.paired ? "" : "nouveau";
    }

    // AirPods : même logo que leur menu (rouge si batterie faible)
    Image {
        visible: root.isAirpods
        source: Qt.resolvedUrl("airpods.png")
        Layout.preferredHeight: 15
        Layout.preferredWidth: 15 * 218 / 126
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: root.powered ? 1 : 0.4
        layer.enabled: root.critical
        layer.effect: MultiEffect {
            colorization: 1
            colorizationColor: Theme.red
        }
    }
    BarText {
        id: btIcon
        visible: !root.isAirpods
        // Appareil connecté : son icône (type choisi / détecté), sinon logo Bluetooth
        text: !root.powered ? Theme.ic(0xf00b2) : (root.main ? root.devIcon(root.main) : Theme.ic(0xf00af))
        font.family: root.main ? root.devIconFont(root.main) : Theme.font
        color: root.critical ? Theme.red : Theme.bluetooth
        opacity: root.powered ? 1 : 0.4
        SequentialAnimation on color {
            running: root.adapter?.discovering ?? false
            loops: Animation.Infinite
            ColorAnimation { to: Theme.muted; duration: 500 }
            ColorAnimation { to: Theme.bluetooth; duration: 500 }
            onStopped: btIcon.color = Qt.binding(() => root.critical ? Theme.red : Theme.bluetooth)
        }
    }
    // AirPods : pastille coupée en deux (icône → menu AirPods, nom → menu Bluetooth)
    Rectangle {
        id: divider
        visible: root.isAirpods && !root.compact
        implicitWidth: 1
        implicitHeight: 14
        color: Qt.rgba(1, 1, 1, 0.2)
    }
    // Nom de l'appareil : défile en aller-retour s'il dépasse 140 px
    Item {
        id: marquee
        visible: root.main !== null && !root.compact
        readonly property int maxWidth: 140
        readonly property bool overflow: nameText.implicitWidth > maxWidth
        implicitWidth: Math.min(nameText.implicitWidth, maxWidth)
        implicitHeight: nameText.implicitHeight
        clip: true

        BarText {
            id: nameText
            text: root.main?.name ?? ""
            font.family: Theme.labelFont
            font.weight: Font.Medium
            // AirPods : nom en blanc (comme leur logo) ; rouge si batterie faible
            color: root.critical ? Theme.red : root.isAirpods ? Theme.text : Theme.bluetooth
            // Retour au début ; animation relancée par sa liaison (un restart() la casserait
            // et ferait défiler un nom qui tient dans la pastille)
            onTextChanged: {
                scroll.stop();
                x = 0;
                scroll.running = Qt.binding(() => marquee.overflow && marquee.visible);
            }
        }

        SequentialAnimation {
            id: scroll
            running: marquee.overflow && marquee.visible
            loops: Animation.Infinite
            PauseAnimation { duration: 1500 }
            NumberAnimation {
                target: nameText; property: "x"
                to: Math.min(0, marquee.maxWidth - nameText.implicitWidth)
                duration: Math.max(1, nameText.implicitWidth - marquee.maxWidth) * 30
                easing.type: Easing.InOutSine
            }
            PauseAnimation { duration: 1500 }
            NumberAnimation {
                target: nameText; property: "x"
                to: 0
                duration: Math.max(1, nameText.implicitWidth - marquee.maxWidth) * 30
                easing.type: Easing.InOutSine
            }
            onStopped: nameText.x = 0
        }
    }

    // Annonce de connexion : glisse hors de la pastille (rebond), reste ~3 s, puis y rentre
    PopupWindow {
        id: toast
        property string name: ""
        // Logo AirPods, sinon icône de l'appareil (type choisi / détecté)
        property bool airpods: false
        property string icon: ""
        property string iconFont: Theme.font
        property bool on: true      // connexion (point vert) / déconnexion (point rouge)
        readonly property color dotColor: on ? Theme.green : Theme.red
        readonly property int gap: 8
        function show(info, connected) {
            name = info.name;
            airpods = info.airpods;
            icon = info.icon;
            iconFont = info.iconFont;
            on = connected;
            visible = true;
            toastAnim.restart();
        }
        function hide() { toastAnim.stop(); visible = false; }

        anchor.item: root
        anchor.rect.x: 0
        anchor.rect.y: 0
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        visible: false
        color: "transparent"
        mask: Region {}    // ne capte pas la souris
        implicitWidth: toastBox.width
        implicitHeight: toastBox.height + gap + 6    // + marge du rebond

        Rectangle {
            id: toastBox
            width: toastRow.implicitWidth + 24
            height: 30
            y: -height
            radius: 10
            color: Theme.popupBg
            border.color: Theme.border
            border.width: 1

            RowLayout {
                id: toastRow
                anchors.centerIn: parent
                spacing: 6
                Image {
                    visible: toast.airpods
                    source: Qt.resolvedUrl("airpods.png")
                    Layout.preferredHeight: 15
                    Layout.preferredWidth: 15 * 218 / 126
                    Layout.rightMargin: 2
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
                BarText {
                    visible: !toast.airpods
                    text: toast.icon
                    font.family: toast.iconFont
                    color: toast.on ? Theme.bluetooth : Theme.subtext
                }
                BarText { text: toast.name; font.bold: true; elide: Text.ElideRight; Layout.maximumWidth: 220; font.family: Theme.labelFont }
                BarText { text: toast.on ? "connecté" : "déconnecté"; color: Theme.subtext; font.family: Theme.labelFont }
                // Point vert / rouge + halo qui pulse
                Item {
                    Layout.leftMargin: 2
                    implicitWidth: 8
                    implicitHeight: 8
                    Rectangle {
                        id: halo
                        anchors.fill: parent
                        radius: 4
                        color: toast.dotColor
                        ParallelAnimation {
                            running: toast.visible
                            loops: Animation.Infinite
                            NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.6; duration: 1100; easing.type: Easing.OutCubic }
                            NumberAnimation { target: halo; property: "opacity"; from: 0.6; to: 0; duration: 1100 }
                        }
                    }
                    Rectangle { anchors.fill: parent; radius: 4; color: toast.dotColor }
                }
            }
        }

        SequentialAnimation {
            id: toastAnim
            ParallelAnimation {
                NumberAnimation { target: toastBox; property: "y"; from: -toastBox.height; to: toast.gap; duration: 420; easing.type: Easing.OutBack }
                NumberAnimation { target: toastBox; property: "opacity"; from: 0; to: 1; duration: 220 }
            }
            PauseAnimation { duration: 2800 }
            ParallelAnimation {
                NumberAnimation { target: toastBox; property: "y"; to: -toastBox.height; duration: 280; easing.type: Easing.InCubic }
                NumberAnimation { target: toastBox; property: "opacity"; to: 0; duration: 260 }
            }
            ScriptAction { script: toast.visible = false }
        }
    }

    onClicked: event => {
        // Compact (pas de nom à cliquer) : clic droit → menu Bluetooth
        if (event.button === Qt.RightButton) {
            if (root.compact && root.isAirpods) popup.toggle();
            else Hyprland.dispatch("exec blueman-manager");
        }
        // AirPods : clic à gauche du séparateur (icône) → menu AirPods, sinon menu Bluetooth
        // (compact : icône seule → menu AirPods, qui donne accès au Bluetooth)
        else if (root.isAirpods && (root.compact || event.x < root.splitX)) airpodsPopup.toggle();
        else popup.toggle();
    }

    // Menu AirPods (clic sur l'icône quand ils sont connectés) : batteries + contrôle du bruit.
    // Menu Bluetooth : clic sur le nom (clic droit en mode compact).
    BarPopup {
        id: airpodsPopup
        target: root
        contentWidth: 300

        // En-tête (style menu batterie) : grosse icône, nom, mode actuel
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            // Logo AirPods (~/Pictures/icons/airpods.png, fond nettoyé) ;
            // teinté en rouge si batterie faible
            Image {
                source: Qt.resolvedUrl("airpods.png")
                Layout.preferredHeight: 38
                Layout.preferredWidth: 38 * 218 / 126
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                layer.enabled: root.critical
                layer.effect: MultiEffect {
                    colorization: 1
                    colorizationColor: Theme.red
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                BarText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: AncState.device?.name ?? root.main?.name ?? ""
                    font.family: Theme.titleFont
                    font.pixelSize: 18
                    font.bold: true
                }
                BarText {
                    font.family: Theme.labelFont
                    text: AncState.mode > 0 ? AncState.label : "Connexion aux AirPods…"
                    color: AncState.modes.find(x => x.id === AncState.mode)?.color ?? Theme.muted
                    font.pixelSize: 12
                }
            }
        }

        // Batteries G / D / boîtier
        RowLayout {
            visible: root.airpods.left !== undefined
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                // [nom, niveau, en charge, icône : moitié du logo (left / right) ou boîtier (case)]
                // Ordre : gauche, boîtier (s'il est détecté), droite
                model: [["Gauche", root.airpods.left, root.airpodsCharging.left, "left"],
                        ["Boîtier", root.airpods.case, root.airpodsCharging.case, "case"],
                        ["Droite", root.airpods.right, root.airpodsCharging.right, "right"]]
                ColumnLayout {
                    required property var modelData
                    readonly property bool known: modelData[1] !== null && modelData[1] !== undefined
                    // Niveau inconnu (écouteur absent, boîtier fermé loin…) : élément masqué
                    visible: known
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1    // colonnes de même largeur
                    spacing: 2
                    readonly property bool charging: modelData[2] === true
                    // Orange en charge, rouge si faible, vert sinon
                    readonly property color accent: charging ? Theme.peach : (modelData[1] ?? 100) <= 15 ? Theme.red : Theme.green
                    // Survol : le pourcentage glisse à droite du nom (masqué sinon)
                    HoverHandler { id: gaugeHover }
                    // Icônes aux extrémités et boîtier au milieu : écouteur droit en miroir (icône
                    // au bord droit, jauge remplie depuis la droite), boîtier centré (jauge
                    // remplie depuis le centre)
                    readonly property bool mirrored: modelData[3] === "right"
                    readonly property bool centered: modelData[3] === "case"
                    // Icône (+ éclair en charge), pourcentage au survol, puis jauge
                    RowLayout {
                        Layout.fillWidth: true
                        layoutDirection: parent.mirrored ? Qt.RightToLeft : Qt.LeftToRight
                        spacing: 3
                        // Boîtier : cale de la largeur du pourcentage + ressort → icône au centre
                        Item { visible: parent.parent.centered; implicitWidth: pctText.implicitWidth }
                        Item { visible: parent.parent.centered; Layout.fillWidth: true }
                        // Écouteur : sa moitié du logo AirPods (gauche = moitié gauche) ;
                        // boîtier : airpods-case.png (même style)
                        Item {
                            readonly property bool isCase: modelData[3] === "case"
                            implicitHeight: isCase ? 12 : 16
                            implicitWidth: Math.round(isCase ? implicitHeight * 136 / 100 : implicitHeight * 109 / 126)
                            Layout.preferredHeight: 16
                            clip: true
                            opacity: gaugeHover.hovered ? 1 : 0.7
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Image {
                                source: Qt.resolvedUrl(parent.isCase ? "airpods-case.png" : "airpods.png")
                                anchors.verticalCenter: parent.verticalCenter
                                height: parent.implicitHeight
                                width: parent.isCase ? parent.implicitWidth : height * 218 / 126
                                x: modelData[3] === "right" ? parent.width - width : 0
                                smooth: true
                                mipmap: true
                            }
                        }
                        BarText { visible: parent.parent.charging; text: Theme.ic(0xf140b); font.pixelSize: 11; color: Theme.peach }
                        Item { Layout.fillWidth: true }
                        BarText {
                            id: pctText
                            text: modelData[1] + "%"
                            color: parent.parent.accent
                            font.family: Theme.labelFont
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            font.pixelSize: 11
                            opacity: gaugeHover.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            transform: Translate {
                                x: gaugeHover.hovered ? 0 : (gauge.parent.mirrored ? -6 : 6)
                                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                    // Jauge ; en charge : reflet lumineux qui balaie la partie remplie
                    Item {
                        id: gauge
                        readonly property bool charging: parent.charging
                        Layout.fillWidth: true
                        implicitHeight: 18
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Rectangle {
                                id: fill
                                x: gauge.parent.mirrored ? parent.width - width
                                 : gauge.parent.centered ? Math.round((parent.width - width) / 2) : 0
                                width: parent.width * Math.max(0, Math.min(1, (modelData[1] ?? 0) / 100))
                                height: parent.height
                                radius: 3
                                color: gauge.parent.accent
                                clip: true
                                Behavior on color { ColorAnimation { duration: 300 } }
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                Rectangle {
                                    id: shine
                                    visible: gauge.charging
                                    width: 28
                                    height: parent.height
                                    x: -width
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: "transparent" }
                                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.75) }
                                        GradientStop { position: 1; color: "transparent" }
                                    }
                                    SequentialAnimation on x {
                                        running: gauge.charging && gauge.visible
                                        loops: Animation.Infinite
                                        // Balaye vers l'extrémité pleine (sens inversé en miroir)
                                        NumberAnimation {
                                            from: gauge.parent.mirrored ? fill.width : -shine.width
                                            to: gauge.parent.mirrored ? -shine.width : fill.width
                                            duration: 1100
                                            easing.type: Easing.InOutSine
                                        }
                                        PauseAnimation { duration: 700 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Separator {}
        BarText { text: "Contrôle du bruit"; color: Theme.subtext; font.pixelSize: 12; font.family: Theme.labelFont }
        // 4 boutons icône seule, de même largeur (comme les profils d'énergie)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            opacity: AncState.mode > 0 ? 1 : 0.4
            enabled: AncState.mode > 0
            Repeater {
                model: AncState.modes
                ActionButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: Theme.ic(modelData.icon)
                    accent: modelData.color
                    highlighted: AncState.mode === modelData.id
                    onClicked: AncState.set(modelData.id)
                }
            }
        }
    }

    BarPopup {
        id: popup
        target: root
        contentWidth: 320

        // Arrête le scan et referme les réglages à la fermeture du popup
        onVisibleChanged: if (!visible) {
            if (root.adapter?.discovering) root.adapter.discovering = false;
            root.settingsFor = "";
        }

        // En-tête (style menu Wi-Fi) : grosse icône de l'appareil, nom et état à côté
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Item {
                Layout.preferredWidth: root.isAirpods ? 38 * 218 / 126 : heroIcon.implicitWidth
                Layout.preferredHeight: 40
                // AirPods : même logo que leur menu
                Image {
                    visible: root.isAirpods
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("airpods.png")
                    width: parent.width
                    height: 38
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
                BarText {
                    id: heroIcon
                    visible: !root.isAirpods
                    anchors.centerIn: parent
                    text: !root.powered ? Theme.ic(0xf00b2)                  // md-bluetooth_off
                        : root.main ? root.devIcon(root.main) : Theme.ic(0xf00af)
                    font.family: root.powered && root.main ? root.devIconFont(root.main) : Theme.font
                    font.pixelSize: 40
                    color: !root.powered ? Theme.muted : root.main ? Theme.bluetooth : Theme.subtext
                }
            }
            ColumnLayout {
                id: headCol
                Layout.fillWidth: true
                spacing: 2
                // Nom + icône « connecté » juste après
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    BarText {
                        Layout.fillWidth: false
                        Layout.maximumWidth: headCol.width - 26    // place de l'icône (pas de lien au RowLayout : boucle de layout)
                        elide: Text.ElideRight
                        text: !root.powered ? (root.blocked ? "Bluetooth bloqué" : "Bluetooth")
                            : root.main?.name ?? "Bluetooth"
                        font.family: Theme.titleFont
                        font.pixelSize: 22
                        font.bold: true
                    }
                    BarText {
                        id: check
                        visible: root.powered && root.main !== null
                        text: Theme.ic(0xf05e0)    // md-check-circle
                        color: Theme.bluetooth
                        font.pixelSize: 16
                    }
                    Item { Layout.fillWidth: true }
                }
                BarText {
                    font.family: Theme.labelFont
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Theme.subtext
                    font.pixelSize: 12
                    text: {
                        if (!root.powered) return root.blocked ? "Mode avion ou rfkill : l'interrupteur le débloque" : "";
                        if (!root.main) return "";
                        if (root.isAirpods && root.airpods.left !== undefined)
                            return "G " + (root.airpods.left ?? "?") + " %  ·  D " + (root.airpods.right ?? "?")
                                   + " %  ·  Boîtier " + (root.airpods.case ?? "?") + " %";
                        if (root.main.batteryAvailable) return "Batterie " + Math.round(root.main.battery * 100) + " %";
                        return "";
                    }
                    visible: text !== ""
                }
                BarText {
                    font.family: Theme.labelFont
                    visible: root.powered && root.connected.length > 1
                    text: "+ " + (root.connected.length - 1) + " autre" + (root.connected.length > 2 ? "s appareils connectés" : " appareil connecté")
                    color: Theme.muted
                    font.pixelSize: 11
                }
            }
            // Recherche d'appareils en cours : icône de chargement qui tourne
            Spinner {
                visible: root.adapter?.discovering ?? false
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
            }
            // Interrupteur Bluetooth, à droite du nom
            Toggle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                checked: root.powered
                accent: Theme.bluetooth
                onToggled: root.setPower(!root.powered)
            }
        }

        Separator {}
        // Recherche / réglages avancés : 2 boutons icône seule de même largeur (comme le menu Wi-Fi)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ActionButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                enabled: root.powered
                opacity: root.powered ? 1 : 0.4
                icon: Theme.ic(0xf0450)
                accent: Theme.bluetooth
                highlighted: root.adapter?.discovering ?? false
                onClicked: root.adapter.discovering = !root.adapter.discovering
            }
            ActionButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Theme.ic(0xf0493)
                onClicked: {
                    popup.visible = false;
                    Hyprland.dispatch("exec blueman-manager");
                }
            }
        }

        Separator { visible: root.powered && root.knownDevices.length > 0 }

        // Appareils connus (appairés / connectés), puis ceux trouvés par la recherche.
        // ScriptModel : lignes conservées quand la liste se retrie (lueur de
        // (dé)connexion et panneau de réglages ne sont pas perdus)
        Repeater {
            model: ScriptModel { values: root.knownDevices }
            delegate: deviceRow
        }

        Separator { visible: root.otherDevices.length > 0 }
        BarText {
            font.family: Theme.labelFont
            visible: root.otherDevices.length > 0
            text: "Autres appareils"
            color: Theme.subtext
            font.pixelSize: 12
        }
        Repeater { model: root.otherDevices; delegate: deviceRow }
    }
}
