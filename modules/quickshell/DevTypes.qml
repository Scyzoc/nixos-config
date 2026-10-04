pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Types d'appareil (icônes) : choisis dans les réglages Bluetooth, réutilisés
// par le menu son pour les sorties Bluetooth
Singleton {
    id: root

    // Icônes Nerd Font md-*, sauf font: "DeviceIcons" = police maison (assets/device-icons-font.py)
    readonly property var defs: [
        { id: "auto", label: "Auto (détecté)", icon: 0 },
        { id: "headphones", label: "Casque", icon: 0xf02cb },
        { id: "earbuds", label: "Écouteurs", icon: 0xe000, font: "DeviceIcons" },
        { id: "speaker", label: "Enceinte", icon: 0xf04c3 },
        { id: "mouse", label: "Souris", icon: 0xf037d },
        { id: "keyboard", label: "Clavier", icon: 0xf030c },
        { id: "gamepad", label: "Manette", icon: 0xf0297 },
        { id: "phone", label: "Téléphone", icon: 0xf011c },
        { id: "watch", label: "Montre", icon: 0xf0589 },
        { id: "computer", label: "Ordinateur", icon: 0xf0322 },
        { id: "tv", label: "TV", icon: 0xf0502 },
        { id: "car", label: "Voiture", icon: 0xf010b },
        { id: "other", label: "Autre", icon: 0xf00af }
    ]
    function def(id) { return defs.find(x => x.id === id) ?? null; }

    // Type choisi par appareil { "MAC": "type" }, partagé entre les barres (un fichier)
    property var types: ({})
    FileView {
        id: typesFile
        path: Quickshell.statePath("bt-types.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.types = JSON.parse(text()); } catch (e) { root.types = {}; }
        }
    }
    function set(addr, t) {
        const m = Object.assign({}, types);
        if (t === "auto") delete m[addr];
        else m[addr] = t;
        types = m;
        typesFile.setText(JSON.stringify(m, null, 2));
    }

    // Type effectif : choix de l'utilisateur, sinon AirPods → écouteurs (null = inconnu)
    function typeOf(addr, name) {
        return def(types[addr]) ?? ((name || "").toLowerCase().indexOf("airpod") >= 0 ? def("earbuds") : null);
    }

    // Icône d'une sortie PipeWire { icon, font } :
    // Bluetooth → type de l'appareil (MAC tirée du node.name), sinon devinée d'après le nom
    function sinkIcon(node) {
        const name = node?.name ?? "";
        const text = ((node?.description ?? "") + " " + name).toLowerCase();
        const bt = name.match(/^bluez_output\.([0-9A-Fa-f_]{17})/);
        if (bt) {
            const t = typeOf(bt[1].replace(/_/g, ":").toUpperCase(), node.description) ?? def("headphones");
            return { icon: t.icon, font: t.font ?? "" };
        }
        if (/hdmi|displayport/.test(text)) return { icon: 0xf0379, font: "" };                  // md-monitor
        if (/hyperx|headset|headphone|casque/.test(text)) return { icon: 0xf02ce, font: "" };   // md-headset
        if (/speaker/.test(text) && name.indexOf("pci-") >= 0) return { icon: 0xf0322, font: "" }; // md-laptop (haut-parleurs du PC)
        return { icon: 0xf04c3, font: "" };                                                    // md-speaker
    }
}
