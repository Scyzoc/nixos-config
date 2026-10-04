import QtQuick

// Effet de clic : flash (couleur d'accent) qui s'estompe. À placer en premier
// enfant d'un bouton (sous le contenu) et appeler play() au clic.
Rectangle {
    id: fx
    anchors.fill: parent
    radius: parent.radius
    color: "#ffffff"
    opacity: 0

    function play() { anim.restart(); }

    NumberAnimation {
        id: anim
        target: fx
        property: "opacity"
        from: 0.35
        to: 0
        duration: 380
        easing.type: Easing.OutCubic
    }
}
