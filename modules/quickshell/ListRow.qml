import QtQuick
import QtQuick.Layouts

// Ligne cliquable pour les listes des popups (appareils, réseaux, sorties audio...)
Rectangle {
    id: row

    property string icon: ""
    property string iconFont: Theme.font   // ex. "DeviceIcons" pour les icônes maison
    property url iconImage: ""             // image à la place de l'icône (ex. logo AirPods)
    property color iconColor: Theme.text
    property string label: ""
    property string labelFont: Theme.font
    property string detail: ""
    property bool active: false
    property bool busy: false
    property bool dot: false             // point vert (ex. appareil connecté)
    property string actionIcon: ""       // bouton secondaire à droite (ex. réglages)
    property bool actionActive: false
    signal clicked()
    signal actionClicked()

    Layout.fillWidth: true
    implicitHeight: 34
    radius: 8
    color: active ? Qt.rgba(1, 1, 1, 0.12) : (ma.containsMouse ? Theme.rowHover : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }

    ClickFx { id: fx }

    // Fin d'une opération (busy) qui a changé l'état de la ligne : lueur qui s'estompe,
    // verte si elle est devenue active (connexion), rouge si elle ne l'est plus (déconnexion).
    // Délai de grâce : busy et active ne changent pas toujours dans le même ordre.
    property bool wasBusy: false
    property bool wasActive: false      // état au début de l'opération
    property real glow: 0
    property color glowColor: Theme.green
    onBusyChanged: {
        if (busy) {
            if (!wasBusy) wasActive = active;
            wasBusy = true;
            failGrace.stop();
        }
        checkDone();
    }
    onActiveChanged: checkDone()
    function checkDone() {
        if (!wasBusy || busy) return;
        if (active !== wasActive) {
            wasBusy = false;
            failGrace.stop();
            glowColor = active ? Theme.green : Theme.red;
            glowAnim.restart();
        } else failGrace.restart();
    }
    Timer { id: failGrace; interval: 1500; onTriggered: row.wasBusy = false }
    SequentialAnimation {
        id: glowAnim
        NumberAnimation { target: row; property: "glow"; from: 0; to: 1; duration: 220; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 250 }
        NumberAnimation { target: row; property: "glow"; to: 0; duration: 1100; easing.type: Easing.InOutSine }
    }
    Rectangle {
        anchors.fill: parent
        radius: row.radius
        visible: row.glow > 0
        color: Qt.rgba(row.glowColor.r, row.glowColor.g, row.glowColor.b, 0.22 * row.glow)
        border.width: 1
        border.color: Qt.rgba(row.glowColor.r, row.glowColor.g, row.glowColor.b, 0.8 * row.glow)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Image {
            visible: row.iconImage.toString() !== ""
            source: row.iconImage
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        BarText {
            visible: row.iconImage.toString() === ""
            text: row.icon
            font.family: row.iconFont
            color: row.iconColor
            font.pixelSize: 16
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
        }
        BarText {
            text: row.label
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.family: row.labelFont
            font.bold: row.active
        }
        Rectangle {
            visible: row.dot && !row.busy
            implicitWidth: 7
            implicitHeight: 7
            radius: 3.5
            color: Theme.green
        }
        BarText {
            visible: !row.busy && row.detail !== ""
            text: row.detail
            color: Theme.subtext
            font.pixelSize: 12
            font.family: Theme.labelFont
        }
        // Connexion en cours : icône de chargement qui tourne en boucle
        Spinner {
            visible: row.busy
            color: Theme.blue
        }
        // Réserve la place du bouton secondaire
        Item { visible: row.actionIcon !== ""; Layout.preferredWidth: 26 }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { fx.play(); row.clicked(); }
    }

    Rectangle {
        visible: row.actionIcon !== ""
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: 6
        color: row.actionActive ? Qt.rgba(1, 1, 1, 0.2) : (actionMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent")
        scale: actionMa.pressed ? 0.85 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        ClickFx { id: actionFx }
        BarText {
            anchors.centerIn: parent
            text: row.actionIcon
            color: row.actionActive ? Theme.text : Theme.subtext
            font.pixelSize: 15
        }
        MouseArea {
            id: actionMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { actionFx.play(); row.actionClicked(); }
        }
    }
}
