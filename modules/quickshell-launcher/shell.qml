//@ pragma IconTheme Papirus-Stock
import QtQuick
import Quickshell
import Quickshell.Io

// Menus plein écran : applications (SUPER+R), fonds d'écran (SUPER+W), presse-papiers
// (SUPER+V), emojis (SUPER+;), assistant (SUPER+K) tâche Atlas (SUPER+SHIFT+T), écrans (SUPER+P)
// et Crépuscule (filtre lumière bleue / mode sombre, depuis le menu d'applications). Config Quickshell séparée de la barre : un bug ici ne la fait pas tomber.
// Reste chargée en arrière-plan, menus affichés par IPC (un seul à la fois) :
//   quickshell ipc -c launcher call launcher toggle
//   quickshell ipc -c launcher call wallpaper toggle
//   quickshell ipc -c launcher call clipboard toggle
//   quickshell ipc -c launcher call emoji toggle
//   quickshell ipc -c launcher call assistant toggle
//   quickshell ipc -c launcher call atlas toggle
//   quickshell ipc -c launcher call display toggle
//   quickshell ipc -c launcher call crepuscule toggle
ShellRoot {
    id: root

    Launcher { id: launcher }
    WallpaperPicker { id: wallpaper }
    ClipboardPicker { id: clipboard }
    EmojiPicker { id: emoji }
    AssistantPrompt { id: assistant }
    AtlasTask { id: atlas }
    DisplayMenu { id: display }
    Crepuscule { id: crepuscule }

    function toggleOnly(menu) {
        for (const m of [launcher, wallpaper, clipboard, emoji, assistant, atlas, display, crepuscule])
            if (m !== menu && m.open) m.hide();
        menu.toggle();
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleOnly(launcher); }
    }
    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.toggleOnly(wallpaper); }
    }
    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggleOnly(clipboard); }
    }
    IpcHandler {
        target: "emoji"
        function toggle(): void { root.toggleOnly(emoji); }
    }
    IpcHandler {
        target: "assistant"
        function toggle(): void { root.toggleOnly(assistant); }
    }
    IpcHandler {
        target: "atlas"
        function toggle(): void { root.toggleOnly(atlas); }
    }
    IpcHandler {
        target: "display"
        function toggle(): void { root.toggleOnly(display); }
    }
    IpcHandler {
        target: "crepuscule"
        function toggle(): void { root.toggleOnly(crepuscule); }
    }
}
