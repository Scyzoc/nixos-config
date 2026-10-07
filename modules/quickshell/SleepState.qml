pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Sommeil : réveil calculé par Atlas (/api/sleep : premier événement du lendemain − trajet
// − préparation ; 09:00 sans événement), temps restant, et bulles « va dormir » qui sortent
// du compteur (SleepCountdown.qml), partagés par les barres de tous les écrans.
//   quickshell ipc -c bar call sleep nudge     bulle immédiate (test)
//   quickshell ipc -c bar call sleep status
Singleton {
    id: root

    property string wake: "09:00"   // "HH:mm" ; "" = rappel désactivé dans Atlas
    property var first: null        // { title, start, leave } ou null

    readonly property int fullMin: 8 * 60       // nuit idéale : apparition du compteur
    readonly property int blinkMin: 7 * 60 + 30 // clignotement
    readonly property int redMin: 6 * 60        // rouge franc
    readonly property int fallAsleep: 15        // temps d'endormissement (min)
    readonly property int cycle: 90             // cycle de sommeil (min)

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    readonly property date wakeDate: {
        const w = new Date(now);
        if (wake === "") return w;
        w.setHours(Number(wake.slice(0, 2)), Number(wake.slice(3, 5)), 0, 0);
        if (w <= now) w.setDate(w.getDate() + 1);
        return w;
    }
    readonly property int minutesLeft: wake === "" ? -1 : Math.ceil((wakeDate - now) / 60000)
    readonly property bool shown: minutesLeft > 0 && minutesLeft <= fullMin
    readonly property bool blinking: shown && minutesLeft < blinkMin
    // 0 à 8 h → 1 à 6 h : du gris clair au rouge
    readonly property real heat: Math.max(0, Math.min(1, (fullMin - minutesLeft) / (fullMin - redMin)))
    readonly property color tint: mix(Theme.subtext, Theme.red, heat)
    // 1 : 8 h–7 h 30 · 2 : 7 h 30–7 h · 3 : 7 h–6 h · 4 : moins de 6 h
    readonly property int level: !shown ? 0 : minutesLeft >= blinkMin ? 1 : minutesLeft >= 420 ? 2
                                 : minutesLeft >= redMin ? 3 : 4
    readonly property color levelColor: [Theme.subtext, Theme.mauve, Theme.peach, Theme.red, Theme.red][level]
    // Cycles complets si couché maintenant
    readonly property int cycles: Math.max(0, Math.floor((minutesLeft - fallAsleep) / cycle))
    readonly property string label: fmt(minutesLeft)

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    // 449 → « 7h29 », 45 → « 45 min »
    function fmt(m) {
        m = Math.max(0, m);
        const h = Math.floor(m / 60), r = m % 60;
        return h > 0 ? h + "h" + String(r).padStart(2, "0") : r + " min";
    }
    function hm(d) { return Qt.formatDateTime(d, "HH:mm"); }
    // Heure limite de coucher pour n cycles complets avant le réveil
    function bedFor(n) { return new Date(wakeDate.getTime() - (fallAsleep + n * cycle) * 60000); }

    // --- Réveil (Atlas) ------------------------------------------------------------------
    Process {
        id: fetch
        command: [Paths.curl, "-sf", "--max-time", "8", "https://atlas.homelab.lan/api/sleep"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }    // Atlas injoignable : on garde l'ancien réveil
                if (d === null) { root.wake = ""; root.first = null; return; }
                root.first = d.first ?? null;
                root.wake = d.first ? d.wake : "09:00";
            }
        }
    }
    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetch.running = true
    }

    // --- Bulles ----------------------------------------------------------------------------
    // Bulle affichée : { id, level, title, body, sticky } ou null
    property var bubble: null
    property int bubbleId: 0
    property real nextNudge: 0      // ms epoch
    property int snoozes: 0         // « encore 10 min » de la nuit
    property real goodnightUntil: 0 // « J'y vais » : bulles suspendues

    // Écart entre deux bulles selon le niveau (min)
    readonly property var gaps: [0, 20, 15, 10, 5]

    onShownChanged: if (!shown) { snoozes = 0; nextNudge = 0; goodnightUntil = 0; bubble = null; }

    Timer {
        interval: 15000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const t = Date.now();
            if (root.bubble || t < root.nextNudge || t < root.goodnightUntil) return;
            root.nudge();
        }
    }

    function pick(list) { return list[Math.floor(Math.random() * list.length)]; }

    function compose() {
        const l = Math.max(1, level), w = hm(wakeDate);
        const ev = first ? first.title + " à " + first.start + (first.leave ? ", départ " + first.leave : "") : "";
        const lost = fullMin - minutesLeft;
        const nextBed = bedFor(cycles);
        const titles = [
            null,
            ["Ta nuit commence", "C'est l'heure", "On range ?"],
            ["Il est temps", "Au lit", "Allez, on y va"],
            ["Tu grignotes ta nuit", "Sérieusement", "Ça devient juste"],
            ["Mode survie", "Va dormir.", "Stop."]
        ][l];
        const bodies = [
            `Couché maintenant : ${cycles} cycle${cycles > 1 ? "s" : ""} complet${cycles > 1 ? "s" : ""} avant ${w}.`,
            `Dans 20 min, il ne te restera que ${fmt(minutesLeft - 20)}.`,
            `Pour ${cycles} cycles, il faut dormir avant ${hm(nextBed)}. Pas après.`
        ];
        if (ev) bodies.push(`Demain : ${ev}. Ton toi de demain compte sur toi.`);
        if (lost > 0) bodies.push(`Déjà ${fmt(lost)} de perdues sur ta nuit idéale.`);
        if (l >= 3) bodies.push("Chaque minute ici, c'est une minute de sommeil en moins.");
        if (l >= 4) bodies.push(`Moins de 6 h de sommeil. Demain va piquer : ferme tout, maintenant.`);
        let body = pick(bodies);
        if (snoozes >= 2) body = `${snoozes}e « encore 10 min ». On sait tous les deux comment ça finit.`;
        return { title: pick(titles), body: body };
    }

    function nudge() {
        const m = compose();
        bubbleId++;
        bubble = { id: bubbleId, level: Math.max(1, level), title: m.title, body: m.body, sticky: level >= 3 };
        nextNudge = Date.now() + gaps[Math.max(1, level)] * 60000;
        if (level >= 3) Quickshell.execDetached([Paths.pwPlay, Paths.bubbleSound]);
    }
    // Fermée sans répondre (croix, délai écoulé)
    function dismiss() { bubble = null; }
    // « Encore 10 min »
    function snooze() {
        snoozes++;
        nextNudge = Date.now() + 10 * 60000;
        bubble = null;
    }
    // « J'y vais » : bulle d'au revoir, puis silence 30 min
    function goodnight() {
        bubbleId++;
        bubble = { id: bubbleId, level: 0, title: "Bonne nuit", body: `Réveil à ${hm(wakeDate)}. Dors bien.`, sticky: false, farewell: true };
        goodnightUntil = Date.now() + 30 * 60000;
    }

    IpcHandler {
        target: "sleep"
        function nudge(): string { root.nudge(); return root.bubble.title + " — " + root.bubble.body; }
        function status(): string {
            return root.wake === "" ? "désactivé"
                : `réveil ${root.hm(root.wakeDate)}, reste ${root.fmt(root.minutesLeft)}, niveau ${root.level}, reports ${root.snoozes}`;
        }
    }
}
