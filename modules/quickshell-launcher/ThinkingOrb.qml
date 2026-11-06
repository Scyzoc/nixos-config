import QtQuick

// Orbe de réflexion « globe » : port QML de ThinkingOrb.svelte du site Atlas (moteur thinking-orbs,
// Jakub Antalik, MIT). Un méridien balaie un globe en pointillés ; les points prennent un dégradé
// qui glisse (`palette`, 5 couleurs bouclées).
Canvas {
    id: orb
    property int orbSize: 22
    property bool running: false
    property var palette: ["#2a78d6", "#6b4fc7", "#2b7d52", "#a2691a", "#2a78d6"]
    width: orbSize
    height: orbSize

    Timer {
        interval: 33
        repeat: true
        running: orb.running && orb.visible
        onTriggered: orb.requestPaint()
    }

    readonly property int latRings: 6
    readonly property int lonDensity: 14
    readonly property real speedMul: 2.665
    readonly property real scanMul: 4.335

    function angleDelta(a, b) { return Math.atan2(Math.sin(a - b), Math.cos(a - b)); }

    onPaint: {
        const ctx = getContext("2d");
        const px = orbSize;
        ctx.clearRect(0, 0, px, px);
        const nowMs = Date.now();
        const t = (nowMs / 1000) * speedMul;
        const spin = 0.5;
        const c = px / 2;
        const radius = c * 0.82;
        const tilt = 0.4 + 0.06 * Math.sin(t * 0.35);
        const sy = Math.sin(t * spin), cyw = Math.cos(t * spin), st = Math.sin(tilt), ct = Math.cos(tilt);
        const scan = t * (spin + (1.7 - spin) * scanMul);
        const rs = Math.pow(px / 300, 0.6);
        const dots = [];
        for (let li = 0; li <= latRings; li++) {
            const lat = -Math.PI / 2 + (li / latRings) * Math.PI;
            const cosLat = Math.cos(lat), sinLat = Math.sin(lat);
            const lonCount = Math.max(1, Math.round(Math.abs(cosLat) * lonDensity));
            for (let lj = 0; lj < lonCount; lj++) {
                const lon = (lj / lonCount) * 2 * Math.PI;
                const x = cosLat * Math.cos(lon);
                const z0 = cosLat * Math.sin(lon);
                const x1 = x * cyw + z0 * sy;
                const z1 = -x * sy + z0 * cyw;
                const z = sinLat * st + z1 * ct;
                const depth = (z + 1) / 2;
                const d = angleDelta(lon + t * spin, scan);
                const boost = Math.exp(-(d * d) / 0.18) * Math.max(0, z);
                dots.push({
                    x: c + x1 * radius,
                    y: c - (sinLat * ct - z1 * st) * radius,
                    z: z,
                    r: Math.max(0.3, (0.6 * 1.75 + 1.7 * 1.75 * depth + boost) * rs),
                    white: 0.62 - 0.54 * depth,
                    a: 0.45 + 0.55 * Math.min(1, boost)
                });
            }
        }
        dots.sort((a, b) => a.z - b.z);
        const n = palette.length;
        for (const d of dots) {
            const alpha = d.a * (1 - Math.min(1, Math.max(0, d.white)) * 0.8);
            const u = ((((d.x + d.y * 0.4) / px - nowMs / 2600) % 1) + 1) % 1;
            const pos = u * (n - 1);
            const i = Math.min(n - 2, Math.floor(pos));
            const f = pos - i;
            ctx.beginPath();
            ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
            ctx.globalAlpha = alpha * (1 - f);
            ctx.fillStyle = palette[i];
            ctx.fill();
            ctx.beginPath();
            ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
            ctx.globalAlpha = alpha * f;
            ctx.fillStyle = palette[i + 1];
            ctx.fill();
        }
        ctx.globalAlpha = 1;
    }
    Component.onCompleted: requestPaint()
}
