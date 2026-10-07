import QtQuick

// Couleur dominante d'une icône (teinte la plus vive), lue sur un Canvas 32×32.
// ColorQuantizer ne lit que des fichiers locaux, pas les URLs image://icon.
Canvas {
    id: root

    property string source: ""
    property color fallback: Theme.mauve   // icône absente ou en niveaux de gris
    property color color: fallback

    width: 32
    height: 32
    opacity: 0.01      // doit rester rendu pour que onPaint soit appelé
    enabled: false

    function load() {
        color = fallback;
        if (source === "") return;
        if (isImageLoaded(source)) requestPaint();
        else loadImage(source);
    }
    onSourceChanged: load()
    Component.onCompleted: load()
    onImageLoaded: requestPaint()

    onPaint: {
        if (source === "" || !isImageLoaded(source)) return;
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.drawImage(source, 0, 0, width, height);
        const d = ctx.getImageData(0, 0, width, height).data;

        // Histogramme des teintes (12 secteurs), pondéré par saturation × luminosité :
        // le secteur le plus lourd donne la couleur, moyennée sur ses pixels
        const bins = [];
        for (let k = 0; k < 12; k++) bins.push({ w: 0, r: 0, g: 0, b: 0 });
        for (let i = 0; i < d.length; i += 4) {
            const a = d[i + 3] / 255;
            if (a < 0.5) continue;
            const r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255;
            const max = Math.max(r, g, b), min = Math.min(r, g, b);
            const s = max > 0 ? (max - min) / max : 0;
            if (s < 0.25 || max < 0.25) continue;
            let h = max === r ? (g - b) / (max - min) : max === g ? 2 + (b - r) / (max - min) : 4 + (r - g) / (max - min);
            h = ((h / 6) % 1 + 1) % 1;
            const bin = bins[Math.floor(h * 12) % 12];
            const w = s * max * a;
            bin.w += w; bin.r += r * w; bin.g += g * w; bin.b += b * w;
        }
        const best = bins.reduce((x, y) => y.w > x.w ? y : x);
        if (best.w < 2) { color = fallback; return; }
        const c = Qt.rgba(best.r / best.w, best.g / best.w, best.b / best.w, 1);
        // Assez clair pour rester lisible sur le fond sombre du menu
        color = Qt.hsva(c.hsvHue, c.hsvSaturation, Math.max(c.hsvValue, 0.85), 1);
    }
}
