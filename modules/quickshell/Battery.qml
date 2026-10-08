import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Batterie (police BatteryIcons) ; clic : détails, profil d'énergie, limite de charge
Pill {
    id: root

    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property real pct: {
        const p = dev?.percentage ?? 0;
        return p <= 1 ? p * 100 : p;
    }
    readonly property int cap: Math.round(pct)
    // Secteur branché mais limite de charge atteinte = pas en charge
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
                                     || (!UPower.onBattery && dev?.state !== UPowerDeviceState.FullyCharged
                                         && dev?.state !== UPowerDeviceState.PendingCharge && cap < limit)
    property string mode: "normal"

    // Limite de charge (seuil de fin thinkpad_acpi), réglée par battery-limit (battery-limit.nix)
    property int limit: 100
    FileView {
        id: limitFile
        path: "/sys/class/power_supply/BAT0/charge_control_end_threshold"
        printErrors: false
        onLoaded: root.limit = parseInt(text()) || 100
    }
    Process {
        id: limitSet
        onExited: { root.pendingLimit = 0; limitFile.reload(); }
    }
    function setLimit(l) {
        limitSet.command = [Paths.sudo, "-n", Paths.batteryLimit, String(l)];
        limitSet.running = true;
    }

    // Interrupteur coché = limite active (< 100 %). Recocher reprend la dernière valeur.
    readonly property bool limitOn: limit < 100
    property int lastLimit: 80
    onLimitChanged: if (limit < 100) lastLimit = limit

    // Glissière 50..100 % par pas de 5 : valeur affichée en direct, appliquée
    // 0,6 s après le dernier geste (100 % = limite désactivée)
    property int pendingLimit: 0
    readonly property int shownLimit: pendingLimit > 0 ? pendingLimit : (limitOn ? limit : lastLimit)
    Timer {
        id: limitApply
        interval: 600
        onTriggered: if (root.pendingLimit > 0) root.setLimit(root.pendingLimit)
    }
    function slideLimit(v) {
        pendingLimit = 50 + Math.round(v * 10) * 5;
        limitApply.restart();
    }

    // Mode énergie courant, écrit par apply-power-mode (power-saving.nix)
    FileView {
        path: "/tmp/waybar_power_mode"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.mode = text().trim() || "normal"
    }

    readonly property bool critical: !charging && cap < 20

    // Mode bureau : écrans Xiaomi + MSI branchés, sur secteur, limite de charge
    // atteinte (plus en charge) → icône « écrans » à la place de la batterie
    readonly property bool deskSetup: {
        let xiaomi = false, msi = false;
        for (const sc of Quickshell.screens) {
            const m = (sc.model || "").toLowerCase();
            if (m.indexOf("mi monitor") >= 0) xiaomi = true;
            if (m.indexOf("msi") >= 0) msi = true;
        }
        return xiaomi && msi;
    }
    readonly property bool desktopMode: deskSetup && !UPower.onBattery && !charging
    // Priorité : charge > batterie faible > mode éco/perf > niveau (> 70 % vert, sinon blanc)
    readonly property color tint: {
        if (charging) return Theme.blue;
        if (critical) return Theme.red;
        if (mode === "eco") return Theme.peach;
        if (mode === "performance") return Theme.red;
        if (cap > 70) return Theme.green;
        return Theme.text;
    }

    // U+E000..U+E00A = 0..100 % par pas de 10, U+E00C..U+E016 = idem + éclair (en charge)
    readonly property string glyph: String.fromCharCode((charging ? 0xe00c : 0xe000) + Math.floor((cap + 5) / 10))

    // Batterie faible : l'icône (rouge) clignote
    property real blink: 1
    SequentialAnimation on blink {
        running: root.critical
        loops: Animation.Infinite
        NumberAnimation { to: 0.15; duration: 500; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutQuad }
        onRunningChanged: if (!running) root.blink = 1
    }

    BarText {
        text: root.desktopMode ? Theme.ic(0xf037a) : root.glyph     // md-monitor_multiple
        font.family: root.desktopMode ? Theme.font : "BatteryIcons"
        font.pixelSize: root.desktopMode ? 17 : 19
        color: root.tint
        opacity: root.blink
    }

    onClicked: popup.toggle()

    function fmtDuration(s) {
        if (!s || s <= 0) return "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return h > 0 ? h + " h " + (m < 10 ? "0" : "") + m : m + " min";
    }
    // Temps avant d'atteindre la limite de charge (UPower ne donne que le temps jusqu'à 100 %) :
    // énergie manquante jusqu'au seuil / puissance de charge ; sinon timeToFull au prorata
    readonly property real timeToLimit: {
        const rate = dev?.changeRate ?? 0, cap_ = dev?.energyCapacity ?? 0;
        if (rate > 0 && cap_ > 0) return Math.max(0, (limit / 100 * cap_ - (dev?.energy ?? 0)) / rate * 3600);
        const full = dev?.timeToFull ?? 0;
        return pct < 100 ? full * Math.max(0, limit - pct) / (100 - pct) : 0;
    }
    // État de charge (sous-titre du menu, infobulle)
    readonly property string statusText: {
        if (dev?.state === UPowerDeviceState.FullyCharged) return "Chargée";
        if (charging) {
            const t = fmtDuration(limitOn ? timeToLimit : dev?.timeToFull);
            return "En charge" + (t ? "  ·  " + (limitOn ? limit + " % dans " : "pleine dans ") + t : "");
        }
        // Secteur : indiqué par l'icône prise à côté du pourcentage (plugIcon)
        // (limite : effet sur l'icône prise ; valeur rappelée dans la section « Limite de charge »)
        if (!UPower.onBattery) return desktopMode ? "Mode bureau" : "";
        const t = fmtDuration(dev?.timeToEmpty);
        return "Sur batterie" + (t ? "  ·  " + t + " restantes" : "");
    }
    // Infobulle : pile verticale (proportions de la police BatteryIcons, borne en haut,
    // jauge continue) + pourcentage en dessous
    tooltipContent: Component {
        ColumnLayout {
            spacing: 6
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 24
                implicitHeight: 54
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 8
                    height: 4
                    topLeftRadius: 2
                    topRightRadius: 2
                    color: root.tint
                }
                Rectangle {
                    id: shell
                    y: 6
                    width: 24
                    height: 48
                    radius: 5
                    color: "transparent"
                    border.color: root.tint
                    border.width: 2
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        height: (shell.height - 8) * Math.min(100, root.pct) / 100
                        radius: 2
                        color: root.tint
                    }
                    BarText {
                        anchors.centerIn: parent
                        visible: root.charging
                        text: Theme.ic(0xf140b)     // md-lightning_bolt
                        font.pixelSize: 18
                        color: Theme.text
                        style: Text.Outline
                        styleColor: "#1e1e1e"
                    }
                }
            }
            BarText {
                Layout.alignment: Qt.AlignHCenter
                text: root.cap + " %"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    function setMode(m) {
        Quickshell.execDetached([Paths.userBin + "/apply-power-mode", m]);
    }

    BarPopup {
        id: popup
        target: root
        contentWidth: 300

        RowLayout {
            spacing: 12
            BarText { text: root.glyph; font.family: "BatteryIcons"; font.pixelSize: 40; color: root.tint }
            ColumnLayout {
                spacing: 2
                RowLayout {
                    spacing: 8
                    BarText { text: root.cap + " %"; font.family: Theme.titleFont; font.pixelSize: 22; font.bold: true }
                    // Prise : PC branché. Bleue en charge ; verte + pastille pause qui
                    // « respire » quand la limite de charge retient la batterie
                    Item {
                        id: plugIcon
                        readonly property bool held: !root.charging && root.limitOn
                        property real breath: 1
                        visible: !UPower.onBattery
                        implicitWidth: 22
                        implicitHeight: 22
                        SequentialAnimation on breath {
                            running: plugIcon.visible && plugIcon.held && popup.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 1400; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
                            onRunningChanged: if (!running) plugIcon.breath = 1
                        }
                        BarText {
                            anchors.centerIn: parent
                            text: Theme.ic(0xf06a5)    // md-power-plug
                            font.pixelSize: 18
                            color: plugIcon.held ? Theme.green : root.charging ? Theme.blue : Theme.text
                            opacity: plugIcon.breath
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                        Rectangle {
                            visible: plugIcon.held
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -3
                            anchors.bottomMargin: -2
                            width: 12
                            height: 12
                            radius: 6
                            color: Theme.popupBg
                            BarText {
                                anchors.centerIn: parent
                                text: Theme.ic(0xf03e4)    // md-pause
                                font.pixelSize: 9
                                color: Theme.green
                            }
                        }
                    }
                }
                BarText {
                    visible: text !== ""
                    color: Theme.subtext
                    font.pixelSize: 12
                    font.family: Theme.labelFont
                    text: root.statusText
                }
                BarText {
                    visible: (root.dev?.changeRate ?? 0) > 0
                    text: (root.dev?.changeRate ?? 0).toFixed(1) + " W"
                    color: Theme.muted
                    font.pixelSize: 11
                    font.family: Theme.labelFont
                }
            }
        }

        Slider { Layout.fillWidth: true; interactive: false; value: root.pct / 100; accent: root.tint; flowing: root.charging }

        Separator {}
        // Boutons en icônes seules : le profil actif est rappelé ici
        BarText {
            text: "Profil d'énergie : " + ({ eco: "Éco", normal: "Normal", performance: "Performance" }[root.mode] ?? root.mode)
            color: Theme.subtext
            font.pixelSize: 12
            font.family: Theme.labelFont
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "eco", label: "Éco", icon: 0xf032a, color: Theme.peach },
                    { id: "normal", label: "Normal", icon: 0xf0f85, color: Theme.text },
                    { id: "performance", label: "Perf", icon: 0xf04c5, color: Theme.red }
                ]
                // Icône seule, 3 boutons de même largeur
                ActionButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: Theme.ic(modelData.icon)
                    accent: modelData.color
                    highlighted: root.mode === modelData.id
                    onClicked: root.setMode(modelData.id)
                }
            }
        }

        Separator {}
        RowLayout {
            Layout.fillWidth: true
            BarText { text: "Limite de charge"; color: Theme.subtext; font.pixelSize: 12; font.family: Theme.labelFont; Layout.fillWidth: true }
            BarText {
                visible: limitPanel.open
                text: root.shownLimit >= 100 ? "sans limite" : root.shownLimit + " %"
                color: root.shownLimit >= 100 ? Theme.yellow : Theme.green
                font.pixelSize: 12
                font.family: Theme.labelFont
                font.bold: true
            }
            Toggle {
                checked: root.limitOn
                accent: Theme.green
                onToggled: root.setLimit(root.limitOn ? 100 : root.lastLimit)
            }
        }

        // Glissière : dépliage animé (même animation que les réglages Bluetooth / Wi-Fi)
        Item {
            id: limitPanel
            readonly property bool open: root.limitOn
            Layout.fillWidth: true
            Layout.preferredHeight: open ? limitBody.implicitHeight : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            visible: Layout.preferredHeight > 0
            clip: true
            opacity: open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            ColumnLayout {
                id: limitBody
                width: parent.width
                y: limitPanel.open ? 0 : -14
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                spacing: 2

                Slider {
                    Layout.fillWidth: true
                    value: (root.shownLimit - 50) / 50
                    accent: root.shownLimit >= 100 ? Theme.yellow : Theme.green
                    onMoved: v => root.slideLimit(v)
                }
            }
        }
    }
}
