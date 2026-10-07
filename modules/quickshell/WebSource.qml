pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Site web d'où vient le son de Brave (mélangeur audio) : nom + favicon (script web-source,
// quickshell.nix). Brave ne joue que depuis un sous-processus audio commun à tous ses
// onglets : on part du morceau annoncé par son lecteur MPRIS.
//   info(titre) → { host, name, icon, win } ou null (recherche lancée, résultat en cache)
Singleton {
    id: ws

    property var cache: ({})      // clé → résultat (ou {} : rien trouvé)
    property var queue: []        // [clé, args]

    // Fenêtres Brave : PWA (appId « brave-soundcloud.com__-Default ») ou fenêtre classique
    function braveWindows() {
        return ToplevelManager.toplevels.values.filter(w => /^brave/.test((w.appId || "").toLowerCase()));
    }
    function pwaHost(w) {
        const m = (w?.appId || "").match(/^brave-(.+?)__/);
        return m ? m[1] : "";
    }

    function info(title) {
        if (!title) return null;
        const wins = braveWindows();
        // Fenêtre dont le titre contient le morceau : PWA → site direct
        const win = wins.find(w => (w.title || "").indexOf(title) >= 0) ?? null;
        const host = pwaHost(win);
        const pwas = wins.map(pwaHost).filter(h => h !== "");
        const key = host ? "host:" + host : "title:" + title + "|" + pwas.join(",");
        const args = host ? ["--host", host] : ["--title", title, "--pwa", pwas.join(",")];
        // Hors de l'évaluation du binding (request modifie queue) ; une fonction par appel
        // (Qt.callLater fusionne les appels d'une même fonction)
        const ask = () => ws.request(key, args);
        const r = cache[key];
        if (r === undefined) {
            Qt.callLater(ask);
            return null;
        }
        // Rien trouvé (historique pas encore écrit par Brave…) : nouvel essai après 20 s
        if (!r.host) {
            if (Date.now() - (r.t ?? 0) > 20000) Qt.callLater(ask);
            return null;
        }
        // Fenêtre à afficher au clic : celle du morceau, sinon la PWA du site
        return Object.assign({ win: win ?? wins.find(w => pwaHost(w) === r.host) ?? null }, r);
    }

    function request(key, args) {
        if (queue.some(q => q[0] === key) || (proc.running && proc.key === key)) return;
        queue = queue.concat([[key, args]]);
        next();
    }
    function next() {
        if (proc.running || queue.length === 0) return;
        const q = queue[0];
        queue = queue.slice(1);
        proc.key = q[0];
        proc.command = [Paths.webSource].concat(q[1]);
        proc.running = true;
    }

    Process {
        id: proc
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                r.t = Date.now();
                const c = Object.assign({}, ws.cache);
                c[proc.key] = r;
                ws.cache = c;
            }
        }
        onExited: ws.next()
    }
}
