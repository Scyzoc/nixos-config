import QtQuick
import Quickshell.Widgets

// Logo d'un projet Atlas (menu Projets) : image (téléchargée en cache par atlas-workspace),
// emoji ou icône Atlas ; à défaut, un dossier
Item {
    id: root
    property var logo: null     // { kind: "image" | "emoji" | "icon", value }
    property int size: 26
    implicitWidth: size
    implicitHeight: size

    // Icônes d'Atlas (src/lib/icons.ts) → Material Design (Nerd Font)
    readonly property var icons: ({
        user: 0xf0004, briefcase: 0xf00d6, home: 0xf02dc, money: 0xf0114,
        health: 0xf02d1, courses: 0xf1180, code: 0xf0169, music: 0xf075a
    })
    readonly property string kind: logo?.kind ?? ""

    ClippingRectangle {
        anchors.fill: parent
        radius: root.size * 0.25
        color: Theme.pill
        visible: root.kind === "image"
        Image {
            anchors.fill: parent
            source: root.kind === "image" ? "file://" + root.logo.value : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            asynchronous: true
            smooth: true
        }
    }
    Text {
        anchors.centerIn: parent
        visible: root.kind === "emoji"
        text: root.kind === "emoji" ? root.logo.value : ""
        font.family: "Noto Color Emoji"
        font.pixelSize: root.size * 0.8
    }
    Rectangle {
        anchors.fill: parent
        radius: root.size * 0.25
        color: Theme.pill
        visible: root.kind !== "image" && root.kind !== "emoji"
        BarText {
            anchors.centerIn: parent
            text: Theme.ic(root.kind === "icon" ? (root.icons[root.logo.value] ?? 0xf0256) : 0xf0256)
            font.pixelSize: root.size * 0.6
            color: Theme.mauve
        }
    }
}
