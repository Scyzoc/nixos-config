pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Serveur de notifications (remplace swaync) : popups en haut à droite (NotifPopups),
// historique dans le menu de la cloche (NotifCenter).
//   popups   : notifications affichées en ce moment, la plus récente en tête
//   history  : toutes les notifications gardées (server.trackedNotifications), plus récente en tête
// Une notif qui expire quitte les popups mais reste dans l'historique ; fermer (croix, clic droit)
// ou cliquer dessus la supprime partout.
Singleton {
    id: root

    property bool dnd: false
    // Heure d'arrivée par id (ms) ; `tick` avance toutes les 30 s pour rafraîchir « il y a 5 min »
    property var times: ({})
    property int tick: 0
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.tick++ }

    function ago(n) {
        root.tick;
        const t = times[n.id];
        if (!t) return "";
        const m = Math.floor((Date.now() - t) / 60000);
        if (m < 1) return "";    // moins d'une minute : rien
        if (m < 60) return "il y a " + m + " min";
        const d = new Date(t);
        return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes();
    }
    property var popups: []
    readonly property var history: server.trackedNotifications.values.slice().reverse()
    readonly property int count: server.trackedNotifications.values.length
    readonly property int maxPopups: 5
    readonly property int maxHistory: 50

    // Délais par défaut (s) quand l'appli n'en impose pas ; critique : reste affichée
    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical) return 0;
        if (n.expireTimeout > 0) return Math.max(3, n.expireTimeout);
        return n.urgency === NotificationUrgency.Low ? 4 : 8;
    }

    function hidePopup(n) {
        if (popups.indexOf(n) < 0) return;
        popups = popups.filter(p => p !== n);
        // Transitoire : pas d'historique
        if (n.transient) n.expire();
    }
    function hideAllPopups() { for (const n of popups.slice()) hidePopup(n); }
    function clearAll() {
        popups = [];
        for (const n of server.trackedNotifications.values.slice()) n.dismiss();
    }

    // Boutons d'action affichés (l'action « default » est déclenchée par le clic sur la carte)
    function actionsOf(n) {
        const out = [];
        for (let i = 0; i < n.actions.length; i++)
            if (n.actions[i].identifier !== "default" && n.actions[i].text) out.push(n.actions[i]);
        return out;
    }

    // Clic sur une notif : action par défaut si l'appli en propose une, sinon focus de sa fenêtre
    function activate(n) {
        let def = null;
        for (let i = 0; i < n.actions.length; i++)
            if (n.actions[i].identifier === "default") def = n.actions[i];
        if (def) def.invoke();
        else Quickshell.execDetached([Paths.notifFocus, n.appName ?? "", n.desktopEntry ?? ""]);
        n.dismiss();
    }

    // ── Couleur de l'appli ─────────────────────────────────────────────────────
    // Couleurs de marque connues (clé : app-name ou desktop-entry en minuscules, non alphanumérique → « - »).
    // Sinon : teinte dominante de l'icône (IconColor dans la carte), puis une couleur du thème tirée du nom.
    readonly property var brandColors: ({
        "discord": "#5865f2", "vesktop": "#5865f2", "webcord": "#5865f2",
        "signal": "#3a76ef", "signal-desktop": "#3a76ef",
        "telegram-desktop": "#2aabee", "telegram": "#2aabee",
        "spotify": "#1db954",
        "brave": "#fb542b", "brave-browser": "#fb542b",
        "firefox": "#ff7139",
        "thunderbird": "#0a84ff",
        "steam": "#66c0f4",
        "claude-code": "#da7756", "claude": "#da7756", "kitty": "#da7756",
        "bluetooth": "#0082fc",
        "screenshot": "#ffffff", "capture-d-écran": "#ffffff",
        "minuteur": "#f9e2af",
        "alimentation": "#f38ba8",
        "réseau": "#89dceb", "wi-fi": "#89dceb",
        "cours": "#cba6f7",
        "mises-à-jour": "#a6e3a1",
        "notify-send": "#b4b4b4"
    })
    readonly property var palette: ["#89b4fa", "#cba6f7", "#a6e3a1", "#f9e2af", "#fab387",
                                    "#f5c2e7", "#94e2d5", "#89dceb", "#f38ba8"]

    function slug(s) {
        return String(s ?? "").toLowerCase().replace(/[^a-z0-9à-öø-ÿ]+/g, "-").replace(/^-|-$/g, "");
    }
    function brandColor(n) {
        for (const k of [slug(n.appName), slug(n.desktopEntry)])
            if (k && brandColors[k]) return brandColors[k];
        return "";
    }
    function hashColor(n) {
        const s = slug(n.appName || n.desktopEntry || "notif");
        let h = 0;
        for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
        return palette[h % palette.length];
    }

    // Icône de l'appli (URL utilisable par Image / IconColor), "" si introuvable
    function appIconOf(n) {
        DesktopEntries.applications.values.length;   // ré-évalue une fois les .desktop chargés
        const entry = (n.desktopEntry && DesktopEntries.byId(n.desktopEntry))
                   || DesktopEntries.heuristicLookup(n.appName || "");
        for (const i of [n.appIcon, entry?.icon, slug(n.appName)]) {
            if (!i) continue;
            if (i.startsWith("image://icon/")) { if (Quickshell.hasThemeIcon(i.slice(13))) return i; continue; }
            if (i.startsWith("file://") || i.startsWith("image://")) return i;
            if (i.startsWith("/")) return "file://" + i;
            // iconPath(…, true) renvoie un chemin même pour une icône absente (damier) → hasThemeIcon
            if (Quickshell.hasThemeIcon(i)) return Quickshell.iconPath(i);
        }
        return "";
    }

    // ── Serveur ────────────────────────────────────────────────────────────────
    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true;
            const ts = Object.assign({}, root.times);
            ts[n.id] = Date.now();
            root.times = ts;

            // Remplacement « synchrone » (x-canonical-private-synchronous, ex. mode Cours) :
            // l'ancienne notif du même groupe disparaît
            const sync = n.hints["x-canonical-private-synchronous"];
            if (sync)
                for (const o of trackedNotifications.values)
                    if (o !== n && o.hints["x-canonical-private-synchronous"] === sync) o.dismiss();

            // Historique borné
            const all = trackedNotifications.values;
            for (let i = 0; i < all.length - root.maxHistory; i++) all[i].dismiss();

            n.closed.connect(() => { root.popups = root.popups.filter(p => p !== n); });

            const critical = n.urgency === NotificationUrgency.Critical;
            if (root.dnd && !critical) return;
            root.popups = [n].concat(root.popups.filter(p => p !== n)).slice(0, root.maxPopups);
            // Son (muet en mode Cours hors AirPods : script notif-sound, cours.nix)
            if (!n.hints["suppress-sound"])
                Quickshell.execDetached([Paths.userBin + "/notif-sound"]);
        }
    }
}
