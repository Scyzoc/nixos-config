pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Minuteurs et chronomètre (assistant : « mets un minuteur de 10 secondes », « lance le
// chrono »), partagés par les barres de tous les écrans. Commandes par IPC (shell.qml) ;
// état gardé dans un fichier pour survivre à un redémarrage de la barre.
Singleton {
    id: root

    // Minuteurs : [{ id, label, duration (s), end (ms epoch), done, doneAt }]
    property var timers: []
    property int nextId: 1
    // Chronomètre : temps cumulé (ms) + départ du tour en cours (ms epoch, 0 = en pause)
    property real swAcc: 0
    property real swStart: 0
    readonly property bool swRunning: swStart > 0
    readonly property bool swActive: swRunning || swAcc > 0

    property real now: Date.now()
    readonly property var running: timers.filter(t => !t.done).sort((a, b) => a.end - b.end)
    readonly property var finished: timers.filter(t => t.done)
    readonly property bool active: timers.length > 0 || swActive
    readonly property real swElapsed: swAcc + (swRunning ? now - swStart : 0)

    function remaining(t) { return Math.max(0, Math.ceil((t.end - now) / 1000)); }
    function progress(t) { return t.duration > 0 ? Math.max(0, Math.min(1, (t.end - now) / (t.duration * 1000))) : 0; }
    // 75 → « 1:15 », 3725 → « 1:02:05 »
    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
        const p = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + p(m) + ":" + p(sec) : m + ":" + p(sec);
    }
    // Durée lisible pour les notifications : « 10 s », « 5 min », « 1 h 30 »
    function human(s) {
        if (s < 60) return s + " s";
        if (s < 3600) return Math.floor(s / 60) + " min" + (s % 60 ? " " + (s % 60) + " s" : "");
        return Math.floor(s / 3600) + " h" + (s % 3600 >= 60 ? " " + Math.floor(s % 3600 / 60) : "");
    }
    function title(t) { return t.label !== "" ? t.label : "Minuteur " + human(t.duration); }

    Timer {
        // 1 s suffit au chrono affiché à la seconde ; 200 ms : la fin tombe pile
        interval: 200
        repeat: true
        running: root.active
        onTriggered: root.tick()
    }
    function tick() {
        now = Date.now();
        let changed = false;
        const list = timers.map(t => {
            if (t.done || t.end > now) return t;
            changed = true;
            ring(t);
            return Object.assign({}, t, { done: true, doneAt: now });
        });
        // Minuteur terminé non acquitté : retiré au bout de 2 min
        const kept = list.filter(t => !t.done || now - t.doneAt < 120000);
        if (changed || kept.length !== list.length) {
            timers = kept;
            save();
        }
    }

    // --- Commandes ---------------------------------------------------------------------
    function add(seconds, label) {
        seconds = Math.round(seconds);
        if (!(seconds > 0) || seconds > 7 * 86400) return "Durée invalide";
        now = Date.now();
        const t = { id: nextId++, label: (label ?? "").trim(), duration: seconds, end: now + seconds * 1000, done: false };
        timers = timers.concat([t]);
        save();
        return "Minuteur " + human(seconds) + " lancé";
    }
    function extend(id, seconds) {
        now = Date.now();
        timers = timers.map(t => t.id !== id ? t : Object.assign({}, t, {
            end: Math.max(t.end, now) + seconds * 1000,
            duration: t.duration + seconds,
            done: false
        }));
        stopRing();
        save();
    }
    // Annule les minuteurs dont le nom contient `query` ("" : tous)
    function cancel(query) {
        const q = (query ?? "").trim().toLowerCase();
        const n = timers.length;
        timers = q === "" ? [] : timers.filter(t => t.label.toLowerCase().indexOf(q) < 0);
        stopRing();
        save();
        return (n - timers.length) + " minuteur(s) annulé(s)";
    }
    function remove(id) {
        timers = timers.filter(t => t.id !== id);
        if (finished.length === 0) stopRing();
        save();
    }
    function dismiss() {
        timers = timers.filter(t => !t.done);
        stopRing();
        save();
    }

    // Chronomètre : start (reprend si en pause), pause, reset
    function stopwatch(cmd) {
        now = Date.now();
        if (cmd === "start" && !swRunning) swStart = now;
        else if (cmd === "pause" && swRunning) { swAcc += now - swStart; swStart = 0; }
        else if (cmd === "reset") { swAcc = 0; swStart = 0; }
        else if (cmd === "toggle") return stopwatch(swRunning ? "pause" : "start");
        save();
        return "Chronomètre " + (swRunning ? "en marche" : swAcc > 0 ? "en pause à " + fmt(swAcc / 1000) : "remis à zéro");
    }

    function describe() {
        const lines = running.map(t => title(t) + " : " + fmt(remaining(t)) + " restant");
        for (const t of finished) lines.push(title(t) + " : terminé");
        if (swActive) lines.push("Chronomètre : " + fmt(swElapsed / 1000) + (swRunning ? "" : " (pause)"));
        return lines.length ? lines.join("\n") : "Aucun minuteur";
    }

    // --- Sonnerie -------------------------------------------------------------------------
    function ring(t) {
        Quickshell.execDetached([Paths.notifySend, "-a", "Minuteur", "-u", "critical", "-i", "alarm-clock",
                                 "Minuteur terminé", title(t)]);
        if (!ringer.running) ringer.running = true;
    }
    function stopRing() { ringer.running = false; }
    Process {
        id: ringer
        command: ["/bin/sh", "-c", "for i in 1 2 3 4 5; do '" + Paths.pwPlay + "' '" + Paths.alarmSound + "' || exit; done"]
    }

    // --- Sauvegarde -----------------------------------------------------------------------
    property bool restored: false
    function save() {
        if (!restored) return;
        store.setText(JSON.stringify({ timers: timers, nextId: nextId, swAcc: swAcc, swStart: swStart }));
    }
    Process {
        running: true
        command: [Paths.mkdir, "-p", Paths.stateDir]
        onExited: store.path = Paths.stateDir + "/timers.json"
    }
    FileView {
        id: store
        printErrors: false
        onLoaded: root.restore(text())
        onLoadFailed: root.restored = true    // pas encore de fichier
    }
    function restore(raw) {
        if (restored) return;
        restored = true;
        let s;
        try { s = JSON.parse(raw); } catch (e) { return; }
        now = Date.now();
        // Fini pendant que la barre était arrêtée : sonne s'il y a moins de 2 min, sinon oublié
        timers = (s.timers ?? []).filter(t => t.done ? now - t.doneAt < 120000 : t.end > now - 120000);
        nextId = s.nextId ?? 1;
        swAcc = s.swAcc ?? 0;
        swStart = s.swStart ?? 0;
        tick();
    }
}
