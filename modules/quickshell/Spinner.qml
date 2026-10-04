import QtQuick

// Indicateur de chargement : arc de cercle qui tourne en boucle (centré, sans glyphe)
Item {
    id: root
    property color color: Theme.subtext
    property real lineWidth: 2
    property bool running: visible

    implicitWidth: 14
    implicitHeight: 14

    Canvas {
        id: arc
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = Math.min(width, height) / 2 - root.lineWidth / 2;
            ctx.lineWidth = root.lineWidth;
            ctx.lineCap = "round";
            // Piste discrète
            ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.2);
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI);
            ctx.stroke();
            // Arc actif : un quart de tour
            ctx.strokeStyle = root.color;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, 0, Math.PI / 2);
            ctx.stroke();
        }
        Connections {
            target: root
            function onColorChanged() { arc.requestPaint(); }
        }
    }

    RotationAnimation on rotation {
        running: root.running
        loops: Animation.Infinite
        from: 0
        to: 360
        duration: 1600
    }
}
