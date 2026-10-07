import QtQuick

// Texte des menus (version du launcher) : Inter comme le contenu des menus de la barre ;
// les icônes Nerd Font (zone privée Unicode) restent en JetBrains Mono
Text {
    color: Theme.text
    readonly property int cp: text.length > 0 ? text.codePointAt(0) : 0
    font.family: (cp >= 0xe000 && cp <= 0xf8ff) || cp >= 0xf0000 ? Theme.font : Theme.labelFont
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
}
