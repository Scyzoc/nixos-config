import QtQuick

// Anneau « IA » du site Atlas : contour en dégradé (viz-1 → info → pos → warn → viz-1) qui glisse
// en boucle (équivalent de `--shimmer` + `weekend-slide`). Se pose par-dessus un cadre arrondi.
Canvas {
    id: ring
    property real radius: 10
    property real lineWidth: 1.5
    property var stops: ["#2a78d6", "#6b4fc7", "#2b7d52", "#a2691a"]
    property real period: 6000
    property bool running: visible && opacity > 0.01
    property real phase: 0
    onPhaseChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onStopsChanged: requestPaint()

    NumberAnimation on phase {
        from: 0; to: 1
        duration: ring.period
        loops: Animation.Infinite
        running: ring.running
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        if (width < 4 || height < 4) return;
        const W = width, s = phase * 3 * W;
        // dégradé de période 3·W, répété pour que le glissement boucle sans saut
        const g = ctx.createLinearGradient(-3 * W + s, 0, 6 * W + s, 0);
        const cols = stops.concat([stops[0]]);
        const per = cols.length - 1;
        for (let rep = 0; rep < 3; rep++)
            for (let i = 0; i <= per; i++) {
                if (rep > 0 && i === 0) continue;
                g.addColorStop((rep * per + i) / (3 * per), cols[i]);
            }
        ctx.strokeStyle = g;
        ctx.lineWidth = lineWidth;
        const h = lineWidth / 2;
        ctx.beginPath();
        ctx.roundedRect(h, h, width - lineWidth, height - lineWidth, radius - h, radius - h);
        ctx.stroke();
    }
}
