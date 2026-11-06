# screen-record.nix — Enregistrement de l'écran (SUPER+SHIFT+Impr, bascule démarrer/arrêter)
# Zone choisie à la souris (slurp), sans audio, dans ~/Videos/. La barre affiche un point REC
# + durée à droite de l'heure (quickshell/ScreenRec.qml, état dans ScreenState.qml) ; à l'arrêt,
# « Enregistrement terminé » apparaît dans l'île de l'heure (Island.qml). Clic sur l'île : ouvre le
# dossier avec la vidéo sélectionnée (`screen-record open <fichier>`) ; menu : enregistrer sous,
# copier, ouvrir le dossier, supprimer (`screen-record delete <fichier>` → corbeille).
# États : /tmp/screen_rec.lock (pid + fichier, mtime = début) ; /tmp/screen_rec.state (done <fichier> | error).
{ pkgs, ... }:

let
  screen-record = pkgs.writeShellScriptBin "screen-record" ''
    LOCK_FILE="/tmp/screen_rec.lock"
    STATE_FILE="/tmp/screen_rec.state"
    DIR="$HOME/Videos"
    finish() { echo "$1" > "$STATE_FILE"; ( ${pkgs.coreutils}/bin/sleep 2.5; ${pkgs.coreutils}/bin/rm -f "$STATE_FILE" ) >/dev/null 2>&1 & }

    # Ouvre le dossier de la vidéo, fichier sélectionné
    if [ "''${1:-}" = open ]; then
        ${pkgs.glib}/bin/gdbus call --session --dest org.freedesktop.FileManager1 \
            --object-path /org/freedesktop/FileManager1 --method org.freedesktop.FileManager1.ShowItems \
            "['file://$2']" "" >/dev/null 2>&1 \
            || ${pkgs.xdg-utils}/bin/xdg-open "$(${pkgs.coreutils}/bin/dirname "$2")"
        exit 0
    fi

    # Menu de l'île : copie le fichier (presse-papiers, collable dans un gestionnaire de fichiers)
    if [ "''${1:-}" = copy ]; then
        printf 'file://%s\n' "$2" | ${pkgs.wl-clipboard}/bin/wl-copy -t text/uri-list
        exit 0
    fi

    # Menu de l'île : supprimer (vers la corbeille, récupérable)
    if [ "''${1:-}" = delete ]; then
        if ${pkgs.glib}/bin/gio trash "$2"; then
            ${pkgs.libnotify}/bin/notify-send -a "Enregistrement" -i user-trash "Vidéo mise à la corbeille" "$(${pkgs.coreutils}/bin/basename "$2")"
        else
            ${pkgs.libnotify}/bin/notify-send -a "Enregistrement" -u critical "Suppression impossible" "$2"
        fi
        exit 0
    fi

    # Menu de l'île : enregistrer sous (déplace la vidéo)
    if [ "''${1:-}" = save-as ]; then
        dest=$(${pkgs.zenity}/bin/zenity --file-selection --save --confirm-overwrite \
            --title="Enregistrer la vidéo" --file-filter="Vidéos MP4 | *.mp4" \
            --filename="$2") || exit 0
        [ -z "$dest" ] && exit 0
        case "$dest" in *.mp4|*.MP4) ;; *) dest="$dest.mp4" ;; esac
        ${pkgs.coreutils}/bin/mv -f "$2" "$dest"
        exit 0
    fi

    if [ -f "$LOCK_FILE" ]; then
        # Arrêt : SIGINT laisse wf-recorder finaliser proprement le fichier
        read -r PID FILE < "$LOCK_FILE"
        kill -INT "$PID" 2>/dev/null
        for _ in $(${pkgs.coreutils}/bin/seq 50); do kill -0 "$PID" 2>/dev/null || break; ${pkgs.coreutils}/bin/sleep 0.1; done
        ${pkgs.coreutils}/bin/rm -f "$LOCK_FILE"
        if [ -s "$FILE" ]; then
            finish "done $FILE"
        else
            finish error
        fi
        exit 0
    fi

    # Démarrage : sélection de la zone à filmer (Échap ou 2e appui = annule)
    ${pkgs.procps}/bin/pkill -x slurp && exit 0
    GEOM=$(${pkgs.slurp}/bin/slurp) || exit 0
    [ -z "$GEOM" ] && exit 0

    ${pkgs.coreutils}/bin/mkdir -p "$DIR"
    FILE="$DIR/ecran_$(${pkgs.coreutils}/bin/date +%Y%m%d_%H%M%S).mp4"
    ${pkgs.coreutils}/bin/rm -f "$STATE_FILE"
    ${pkgs.wf-recorder}/bin/wf-recorder -g "$GEOM" -f "$FILE" >/tmp/screen_rec.log 2>&1 &
    PID=$!
    ${pkgs.coreutils}/bin/sleep 0.4
    if kill -0 "$PID" 2>/dev/null; then
        echo "$PID $FILE" > "$LOCK_FILE"
    else
        finish error
        ${pkgs.libnotify}/bin/notify-send -a "Enregistrement" -u critical "Enregistrement impossible" "Voir /tmp/screen_rec.log"
    fi
  '';
in
{
  home.packages = [ screen-record pkgs.wf-recorder ];
}
