import QtQuick
import QtQuick.Layouts
import Quickshell

// Bouton de la barre : fond translucide, survol, clignotement en alerte
Rectangle {
    id: pill

    property bool framed: true
    // Écran étroit (Bar.compact) : icônes seules, textes masqués
    property bool compact: false
    // Infobulle au survol (infos essentielles, lignes séparées par \n) ; "" = aucune
    property string tooltip: ""
    // Infobulle sur mesure (remplace le texte) ; null = texte de `tooltip`
    property Component tooltipContent: null
    property bool alert: false
    property int hpad: 10
    readonly property alias hovered: mouse.containsMouse
    // >= 0 : pastille coupée en deux à cette abscisse, seule la moitié survolée s'éclaire
    property real splitX: -1
    readonly property bool hoverLeft: mouse.mouseX < splitX
    default property alias content: row.data

    signal clicked(var event)
    signal scrolled(var event)

    implicitWidth: row.implicitWidth + hpad * 2
    implicitHeight: 24
    radius: 10
    color: framed ? (mouse.containsMouse && splitX < 0 ? Theme.pillHover : Theme.pill) : "transparent"
    border.color: framed ? Theme.pillBorder : "transparent"
    border.width: 1

    Behavior on color { ColorAnimation { duration: 200 } }
    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // Clic : léger enfoncement (rebond au relâchement) + flash
    scale: mouse.pressed ? 0.94 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
    ClickFx { id: fx }

    // Clignotement rouge (batterie/CPU/écouteurs critiques)
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.rgba(243 / 255, 139 / 255, 168 / 255, 0.7)
        visible: pill.alert
        opacity: 0
        SequentialAnimation on opacity {
            running: pill.alert
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 500 }
            NumberAnimation { to: 0; duration: 500 }
        }
    }

    // Survol d'une moitié : forme de la pastille découpée au séparateur
    // (coins arrondis côté extérieur, bord droit côté séparateur)
    Item {
        visible: pill.framed && pill.splitX >= 0
        x: pill.hoverLeft ? 0 : pill.splitX
        width: pill.hoverLeft ? pill.splitX : pill.width - pill.splitX
        height: pill.height
        clip: true
        opacity: mouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Rectangle {
            x: pill.hoverLeft ? 0 : -pill.splitX
            width: pill.width
            height: pill.height
            radius: pill.radius
            color: Qt.rgba(1, 1, 1, 0.15)
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => { fx.play(); tip.suppressed = true; pill.clicked(event); }
        onContainsMouseChanged: {
            if (containsMouse) tipDelay.restart();
            else { tipDelay.stop(); tip.suppressed = false; tip.visible = false; }
        }
        onWheel: event => pill.scrolled(event)
    }

    // Infobulle : apparaît après 600 ms de survol, masquée au clic (le menu prend le relais)
    Timer {
        id: tipDelay
        interval: 600
        onTriggered: if (mouse.containsMouse && !tip.suppressed && (pill.tooltip !== "" || pill.tooltipContent)) tip.visible = true
    }
    PopupWindow {
        id: tip
        property bool suppressed: false
        onSuppressedChanged: if (suppressed) visible = false
        anchor.item: pill
        anchor.rect.x: 0
        anchor.rect.y: 0
        anchor.rect.width: pill.width
        anchor.rect.height: pill.height + 8
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        visible: false
        color: "transparent"
        mask: Region {}    // ne capte pas la souris
        implicitWidth: (tipCustom.item ? tipCustom.implicitWidth : tipText.implicitWidth) + 20
        implicitHeight: tipCustom.item ? tipCustom.implicitHeight + 20 : tipText.implicitHeight + 12

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.popupBg
            border.color: Theme.border
            border.width: 1
            opacity: tip.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            BarText {
                id: tipText
                anchors.centerIn: parent
                visible: !tipCustom.item
                text: pill.tooltip
                font.pixelSize: 12
                lineHeight: 1.15
                horizontalAlignment: Text.AlignHCenter
            }
            Loader {
                id: tipCustom
                anchors.centerIn: parent
                sourceComponent: pill.tooltipContent
            }
        }
    }
}
