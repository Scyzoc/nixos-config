pragma Singleton
import QtQuick
import Quickshell

// Un seul menu de barre ouvert à la fois (tous écrans confondus)
Singleton {
    property var current: null
}
