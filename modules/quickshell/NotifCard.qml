import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Carte de notification, style des menus de la barre. La couleur de l'appli (marque connue,
// sinon teinte dominante de son icône) colore le nom de l'appli et la jauge du délai, en bas.
//   popup: true  → carte flottante (glisse depuis la droite, délai, survol = pause)
//   popup: false → ligne de l'historique (menu de la cloche)
Rectangle {
    id: card

    required property Notification notif
    property bool popup: true

    readonly property string appIcon: NotifState.appIconOf(notif)
    // Vraie image (avatar, pochette…) ; une icône de thème passée en image compte comme icône
    readonly property string photo: notif.image && !notif.image.startsWith("image://icon/") && notif.image !== appIcon ? notif.image : ""
    readonly property string iconSrc: appIcon || (notif.image.startsWith("image://icon/") && Quickshell.hasThemeIcon(notif.image.slice(13)) ? notif.image : "")
    readonly property string brand: NotifState.brandColor(notif)
    readonly property color accent: brand !== "" ? brand : tint.color
    readonly property bool critical: notif.urgency === NotificationUrgency.Critical
    readonly property real timeout: NotifState.timeoutFor(notif)
    readonly property bool hovered: mouse.containsMouse || closeMouse.containsMouse

    // Couleurs du texte : popups = fond de la barre (Theme.notif*, noir plus ou moins opaque selon
    // le fond d'écran derrière), texte noir si ce fond reste trop clair ; historique = thème du menu
    readonly property bool darkText: popup && Theme.notifDarkText
    readonly property color fg: popup ? Theme.notifText : Theme.text
    readonly property color fgSub: Qt.rgba(fg.r, fg.g, fg.b, darkText ? 0.78 : 0.72)
    readonly property color fgMuted: Qt.rgba(fg.r, fg.g, fg.b, darkText ? 0.6 : 0.45)
    readonly property color fill: darkText ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.06)
    // Couleur de l'appli ajustée pour rester lisible (bleu Discord trop sombre, jaune sur fond clair…)
    readonly property color accentText: Theme.readable(accent, darkText)

    // Jauge du délai (1 → 0), en pause au survol
    property real progress: 1
    // Glissement d'entrée / sortie (0 = en place, 1 = hors champ à droite)
    property real slide: popup ? 1 : 0
    property bool leaving: false

    implicitHeight: content.implicitHeight + 24 + (popup && timeout > 0 ? 4 : 0)
    radius: 14
    color: hovered && !popup ? Qt.rgba(1, 1, 1, 0.08) : (popup ? Theme.notifBg : Qt.rgba(1, 1, 1, 0.04))
    border.color: critical ? Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.7) : (popup ? Theme.border : Theme.pillBorder)
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }

    opacity: 1 - slide
    transform: Translate { x: card.slide * (card.width + 20) }

    IconColor { id: tint; source: card.iconSrc; fallback: NotifState.hashColor(card.notif) }

    Component.onCompleted: if (popup) enterAnim.start()
    NumberAnimation { id: enterAnim; target: card; property: "slide"; to: 0; duration: 320; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: leaveAnim
        NumberAnimation { target: card; property: "slide"; to: 1; duration: 240; easing.type: Easing.InCubic }
        ScriptAction { script: NotifState.hidePopup(card.notif) }
    }
    // « Tout effacer » (historique) : la carte file à droite en accélérant, après `delay` ms
    function sweepOut(delay) {
        timer.stop();
        sweepAnim.delay = delay;
        sweepAnim.start();
    }
    SequentialAnimation {
        id: sweepAnim
        property int delay: 0
        PauseAnimation { duration: sweepAnim.delay }
        NumberAnimation { target: card; property: "slide"; to: 1; duration: 280; easing.type: Easing.InCubic }
    }

    // Fin du délai : la carte glisse hors de l'écran (la notif reste dans l'historique)
    function leave() {
        if (leaving) return;
        leaving = true;
        timer.stop();
        leaveAnim.start();
    }

    NumberAnimation {
        id: timer
        target: card
        property: "progress"
        from: 1
        to: 0
        duration: card.timeout * 1000
        running: card.popup && card.timeout > 0
        paused: running && card.hovered
        onFinished: card.leave()
    }
    // Notif remplacée (même id, nouveau contenu) : délai relancé
    Connections {
        target: card.notif
        function onSummaryChanged() { if (card.popup && card.timeout > 0 && !card.leaving) timer.restart(); }
        function onBodyChanged() { if (card.popup && card.timeout > 0 && !card.leaving) timer.restart(); }
    }

    // Gauche : action par défaut / focus de l'appli ; droit : fermer ; milieu : masquer toutes les popups
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.RightButton) card.notif.dismiss();
            else if (event.button === Qt.MiddleButton) NotifState.hideAllPopups();
            else { fx.play(); NotifState.activate(card.notif); }
        }
    }
    ClickFx { id: fx; color: card.accent }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Image (avatar, pochette…) avec l'icône de l'appli en pastille, sinon l'icône seule
            Item {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                Layout.alignment: Qt.AlignTop

                ClippingRectangle {
                    id: pic
                    anchors.fill: parent
                    radius: 12
                    color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.16)

                    Image {
                        id: photoImg
                        anchors.fill: parent
                        visible: card.photo !== ""
                        source: card.photo
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(88, 88)
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }
                    IconImage {
                        id: iconImg
                        anchors.centerIn: parent
                        visible: card.photo === "" && card.iconSrc !== ""
                        implicitSize: 30
                        source: visible ? card.iconSrc : ""
                        asynchronous: true
                    }
                    BarText {
                        anchors.centerIn: parent
                        visible: card.photo !== "" ? photoImg.status === Image.Error
                                                   : (card.iconSrc === "" || iconImg.status === Image.Error)
                        text: Theme.ic(0xf009a)    // md-bell
                        color: card.accent
                        font.pixelSize: 22
                    }
                }
                // Pastille de l'appli sur la photo (avatar, pochette)
                Rectangle {
                    visible: card.photo !== "" && card.appIcon !== ""
                    width: 20
                    height: 20
                    radius: 10
                    x: parent.width - width + 4
                    y: parent.height - height + 4
                    color: Theme.popupBg
                    border.color: card.accent
                    border.width: 1
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 14
                        source: parent.visible ? card.appIcon : ""
                        asynchronous: true
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                // En-tête : Appli · il y a 2 min                  ✕
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    BarText {
                        text: card.notif.appName || card.notif.desktopEntry || "Notification"
                        color: card.accentText
                        font.family: Theme.labelFont
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.maximumWidth: 170
                    }
                    BarText {
                        text: "·  " + NotifState.ago(card.notif)
                        visible: NotifState.ago(card.notif) !== ""
                        color: card.fgMuted
                        font.family: Theme.labelFont
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 10
                        opacity: card.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        color: closeMouse.containsMouse ? Theme.red : card.fill
                        Behavior on color { ColorAnimation { duration: 150 } }
                        BarText {
                            anchors.centerIn: parent
                            text: Theme.ic(0xf0156)    // md-close
                            font.pixelSize: 12
                            color: closeMouse.containsMouse ? "#000000" : card.fgSub
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.notif.dismiss()
                        }
                    }
                }

                BarText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.notif.summary
                    color: card.fg
                    font.family: Theme.labelFont
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                BarText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.notif.body
                    color: card.fgSub
                    font.family: Theme.labelFont
                    font.pixelSize: 12
                    lineHeight: 1.1
                    wrapMode: Text.Wrap
                    maximumLineCount: card.popup ? 4 : 3
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    linkColor: card.accentText
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
        }

        // Boutons d'action (hors action par défaut, déclenchée par le clic sur la carte)
        Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: actRep.count > 0
            Repeater {
                id: actRep
                model: NotifState.actionsOf(card.notif)
                Rectangle {
                    required property NotificationAction modelData
                    implicitWidth: actText.implicitWidth + 20
                    implicitHeight: 26
                    radius: 8
                    color: actMouse.containsMouse ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.25) : card.fill
                    border.color: actMouse.containsMouse ? card.accent : Theme.pillBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    BarText {
                        id: actText
                        anchors.centerIn: parent
                        text: modelData.text
                        color: card.fg
                        font.family: Theme.labelFont
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: actMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { modelData.invoke(); card.notif.dismiss(); }
                    }
                }
            }
        }
    }

    // Jauge du délai, couleur de l'appli, centrée en bas
    Rectangle {
        visible: card.popup && card.timeout > 0
        x: 14
        y: card.height - 6
        width: (card.width - 28) * card.progress
        height: 2
        radius: 1
        color: card.accent
        opacity: 0.85
    }
}
