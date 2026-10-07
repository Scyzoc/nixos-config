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
    readonly property int alarmMin: 7 * 60      // sous 7 h : alarme (rouge vif, capsule pleine)
    readonly property bool alarm: shown && minutesLeft < alarmMin
    readonly property bool panic: shown && minutesLeft < redMin
    // Rouge d'alarme, plus saturé que Theme.red (pastel) : il doit sauter aux yeux
    readonly property color vivid: "#ff2a45"
    // 0 à 8 h → 1 à 7 h : du gris clair au rouge vif (courbe accélérée : ça vire vite)
    readonly property real heat: Math.max(0, Math.min(1, (fullMin - minutesLeft) / (fullMin - alarmMin)))
    readonly property color tint: alarm ? vivid : mix(Theme.subtext, vivid, Math.pow(heat, 0.7))
    // 1 : 8 h–7 h 30 · 2 : 7 h 30–7 h · 3 : 7 h–6 h · 4 : moins de 6 h
    readonly property int level: !shown ? 0 : minutesLeft >= blinkMin ? 1 : minutesLeft >= 420 ? 2
                                 : minutesLeft >= redMin ? 3 : 4
    readonly property color levelColor: levelColorFor(level)
    function levelColorFor(l) { return [Theme.subtext, Theme.mauve, "#ff6a3d", vivid, vivid][l]; }
    // Cycles complets si couché maintenant
    readonly property int cycles: Math.max(0, Math.floor((minutesLeft - fallAsleep) / cycle))
    readonly property int secondsLeft: wake === "" ? -1 : Math.max(0, Math.floor((wakeDate - now) / 1000))
    // Compteur à la seconde (7:18:42) : la pression monte
    readonly property string label: {
        const t = secondsLeft, h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, sec = t % 60;
        const p = n => String(n).padStart(2, "0");
        return (h > 0 ? h + ":" + p(m) : m) + ":" + p(sec);
    }

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

    // Écart entre deux bulles selon le niveau (min)
    readonly property var gaps: [0, 20, 15, 10, 5]

    onShownChanged: if (!shown) { nextNudge = 0; bubble = null; }
    // Bulle ignorée qui change de palier : remplacée par une plus insistante
    onLevelChanged: if (bubble && !bubble.farewell && level > bubble.level) nudge()

    Timer {
        interval: 15000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const t = Date.now();
            if (root.bubble || t < root.nextNudge) return;
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
        return { title: pick(titles), body: pick(bodies) };
    }

    function nudge() {
        const m = compose();
        bubbleId++;
        // Ne part qu'avec « J'y vais » : ni croix, ni délai, ni report
        bubble = { id: bubbleId, level: Math.max(1, level), title: m.title, body: m.body, sticky: true };
        if (level >= 3) Quickshell.execDetached([Paths.pwPlay, Paths.bubbleSound]);
    }
    // Fin de la bulle d'au revoir (délai écoulé)
    function dismiss() { bubble = null; }
    // « J'y vais » : bulle d'au revoir ; si l'écran est encore allumé au prochain
    // créneau (20/15/10/5 min selon le niveau), une nouvelle bulle revient
    function goodnight() {
        bubbleId++;
        bubble = { id: bubbleId, level: 0, title: "Bonne nuit", body: `Réveil à ${hm(wakeDate)}. Dors bien.`, sticky: false, farewell: true };
        nextNudge = Date.now() + gaps[Math.max(1, level)] * 60000;
    }

    IpcHandler {
        target: "sleep"
        function nudge(): string { root.nudge(); return root.bubble.title + " — " + root.bubble.body; }
        function status(): string {
            return root.wake === "" ? "désactivé"
                : `réveil ${root.hm(root.wakeDate)}, reste ${root.fmt(root.minutesLeft)}, niveau ${root.level}, bulle ${root.bubble ? root.bubble.title : "aucune"}`;
        }
    }
}
