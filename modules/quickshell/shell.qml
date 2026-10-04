import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Variants {
        model: Quickshell.screens
        Bar {}
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
}
