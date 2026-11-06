import QtQuick

// Orbe de réflexion (inspiré de thinking-orbs, état « searching ») : globe de points qui tourne,
// un méridien lumineux le balaie en boucle.
Item {
    id: root
    property color color: Theme.subtext
    property bool running: visible
    property int dots: 64
    // true : les points se rassemblent en coche verte
    property bool done: false
    property color doneColor: Theme.green
    property real morph: done ? 1 : 0
    Behavior on morph { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }

    implicitWidth: 20
    implicitHeight: 20

    // Points répartis sur la sphère (spirale de Fibonacci) : latitude et longitude
    readonly property var pts: {
        const out = [];
        const ga = Math.PI * (3 - Math.sqrt(5));
        for (let i = 0; i < dots; i++) {
            const y = 1 - 2 * (i + 0.5) / dots;
            out.push({ y: y, lon: ga * i, r: Math.sqrt(1 - y * y) });
        }
        return out;
    }
    property real t: 0         // horloge du balayage
    property real spinT: 0     // rotation du globe : ralentit pendant la transformation

    // Coche (repère centré, y vers le bas) : les points sont répartis le long du tracé
    readonly property var check: {
        const a = [-0.6, 0.0], b = [-0.2, 0.45], c = [0.65, -0.45];
        const l1 = Math.hypot(b[0] - a[0], b[1] - a[1]), l2 = Math.hypot(c[0] - b[0], c[1] - b[1]);
        const out = [];
        for (let i = 0; i < dots; i++) {
            const d = (i + 0.5) / dots * (l1 + l2);
            const f = d < l1 ? d / l1 : (d - l1) / l2;
            const p = d < l1 ? a : b, q = d < l1 ? b : c;
            out.push({ x: p[0] + (q[0] - p[0]) * f, y: p[1] + (q[1] - p[1]) * f });
        }
        return out;
    }

    FrameAnimation {
        running: root.running
        onTriggered: { root.t += frameTime; root.spinT += frameTime * (1 - root.morph); orb.requestPaint(); }
    }
    onColorChanged: orb.requestPaint()
    onMorphChanged: orb.requestPaint()

    Canvas {
        id: orb
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const R = Math.min(width, height) / 2 - 1.2;
            const cx = width / 2, cy = height / 2;
            const spin = root.spinT * 0.9;                       // rotation du globe
            const scan = (root.t * 2.2) % (2 * Math.PI);     // méridien de balayage
            const tilt = 0.4, ct = Math.cos(tilt), st = Math.sin(tilt);
            const m = root.morph, g = root.doneColor;
            const c = Qt.rgba(root.color.r + (g.r - root.color.r) * m, root.color.g + (g.g - root.color.g) * m,
                              root.color.b + (g.b - root.color.b) * m, 1);
            for (let i = 0; i < root.pts.length; i++) {
                const p = root.pts[i];
                const a = p.lon + spin;
                const x = p.r * Math.sin(a), z = p.r * Math.cos(a), y = p.y;
                // Inclinaison de l'axe
                const y2 = y * ct - z * st, z2 = y * st + z * ct;
                let d = Math.abs(((p.lon + spin - scan) % (2 * Math.PI) + 3 * Math.PI) % (2 * Math.PI) - Math.PI);
                const glow = Math.exp(-d * d / 0.18);
                const depth = (z2 + 1) / 2;
                const alpha = Math.min(1, 0.18 + 0.45 * depth + 0.6 * glow) * (1 - m) + m;
                const k = root.check[i];
                const px = cx + (x * R) * (1 - m) + (k.x * R) * m;
                const py = cy + (-y2 * R) * (1 - m) + (k.y * R) * m;
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, alpha);
                ctx.beginPath();
                ctx.arc(px, py, (0.5 + 0.35 * depth + 0.45 * glow) * (1 - m) + 0.95 * m, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
    }
}
