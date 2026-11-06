import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    // Popups de notification (serveur : NotifState, remplace swaync)
    NotifPopups {}

    // Notifications :
    //   quickshell ipc -c bar call notif dnd       bascule Ne pas déranger (renvoie on/off)
    //   quickshell ipc -c bar call notif clear     efface tout
    IpcHandler {
        target: "notif"
        function dnd(): string { NotifState.dnd = !NotifState.dnd; return NotifState.dnd ? "on" : "off"; }
        function clear(): string { NotifState.clearAll(); return "ok"; }
    }

    // Minuteurs / chronomètre (TimerState), utilisés par l'assistant :
    //   quickshell ipc -c bar call timer add 600 "pâtes"
    //   quickshell ipc -c bar call timer cancel ""        ("" : tous)
    //   quickshell ipc -c bar call timer stopwatch start  (start / pause / reset / toggle)
    IpcHandler {
        target: "timer"
        function add(seconds: int, label: string): string { return TimerState.add(seconds, label); }
        function cancel(label: string): string { return TimerState.cancel(label); }
        function stopwatch(cmd: string): string { return TimerState.stopwatch(cmd); }
        function list(): string { return TimerState.describe(); }
    }

    // Message de bienvenue : `quickshell ipc -c bar call greeting hello` (test, ignore la date)
    IpcHandler {
        target: "greeting"
        function hello(): string { GreetingState.check(true); return "ok"; }
    }

    // Ferme le menu de barre ouvert (appelé par `screenshot` avant de geler l'écran)
    IpcHandler {
        target: "popup"
        function close(): string {
            if (PopupState.current) PopupState.current.visible = false;
            return "ok";
        }
    }
}
