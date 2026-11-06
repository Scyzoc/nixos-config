import QtQuick

// Cadre à bordure dégradée (violet → bleu → vert → ocre, comme les blocs IA du site Atlas) :
// le contenu va dans le rectangle intérieur, de couleur `fill`.
Rectangle {
    id: r
    property color fill: "white"
    property real bw: 1.5
    property var stops: ["#2a78d6", "#6b4fc7", "#2b7d52", "#a2691a"]
    property real strength: 0.55
    default property alias content: inner.data

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(Qt.color(r.stops[1]).r, Qt.color(r.stops[1]).g, Qt.color(r.stops[1]).b, r.strength) }
        GradientStop { position: 0.45; color: Qt.rgba(Qt.color(r.stops[3]).r, Qt.color(r.stops[3]).g, Qt.color(r.stops[3]).b, r.strength * 0.8) }
        GradientStop { position: 0.75; color: Qt.rgba(Qt.color(r.stops[2]).r, Qt.color(r.stops[2]).g, Qt.color(r.stops[2]).b, r.strength) }
        GradientStop { position: 1.0; color: Qt.rgba(Qt.color(r.stops[0]).r, Qt.color(r.stops[0]).g, Qt.color(r.stops[0]).b, r.strength) }
    }
    Rectangle {
        id: inner
        anchors.fill: parent
        anchors.margins: r.bw
        radius: Math.max(0, r.radius - r.bw)
        color: r.fill
    }
}
