{ config, pkgs, lib, ... }:

let
  HYPR   = "${pkgs.hyprland}/bin/hyprctl";
  # Script de wallpaper-picker.nix (réaffiche le dernier fond sur tous les écrans)
  WALLPAPER_RESTORE = "${config.home.profileDirectory}/bin/wallpaper-restore";
  JQ     = "${pkgs.jq}/bin/jq";
  NOTIFY = "${pkgs.libnotify}/bin/notify-send";
  ROFI   = "${pkgs.rofi}/bin/rofi";
  SOCAT  = "${pkgs.socat}/bin/socat";
  MD5SUM = "${pkgs.coreutils}/bin/md5sum";
  NWG    = "${pkgs.nwg-displays}/bin/nwg-displays";

  # Dossier des dispositions sauvegardées (une par signature d'écrans externes)
  LAYOUT_DIR = "$HOME/.local/state/display-layouts";

  # Format d'une disposition :
  #   { name, internal: { workspaces }, monitors: [ { description, x, y,
  #     width, height, refreshRate, scale, workspaces } ] }
  # `workspaces` = "11-20" ou "1,3,5-7" ; absent/null = bloc de 10 auto.
  # Les anciens fichiers (simple tableau d'écrans) sont normalisés à la volée.
  NORM = ''if type == "array" then {monitors: .} else . end'';

  # Dernier mode appliqué : relu après un `hyprctl reload` (rebuild NixOS) pour
  # réappliquer le mode courant, sinon les lignes monitor= de home.nix
  # réactivent eDP-1 et on retombe en étendu.
  MODE_FILE = "$HOME/.local/state/display-mode";

  # Verrou anti-boucle : display-apply pose des dizaines de `hyprctl keyword`,
  # et chaque keyword fait émettre un `configreloaded` par Hyprland. Sans ce
  # verrou, monitor-watcher réapplique le mode courant → boucle infinie
  # (notif "Capot fermé" en rafale). Le verrou est levé 3 s après la fin, le
  # temps que les événements en retard soient consommés.
  LOCK_FILE = "\${XDG_RUNTIME_DIR:-/tmp}/display-apply.lock";

  # Signature des écrans externes branchés (hash des descriptions triées).
  # Code retour 1 si aucun externe : pas de disposition à chercher.
  layout-sig = pkgs.writeShellScript "display-layout-sig" ''
    DESCS=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "eDP-1") | .description' | sort)
    [ -z "$DESCS" ] && exit 1
    printf '%s\n' "$DESCS" | ${MD5SUM} | cut -d' ' -f1
  '';

  # Thème rofi commun ; `input = true` affiche un champ de saisie sans liste.
  rofiTheme = { width, input ? false }: ''
    configuration {
      show-icons: false;
      font: "JetBrainsMono Nerd Font 13";
      disable-history: true;
      kb-mode-next: "";
      kb-mode-previous: "";
      me-select-entry: "";
      me-accept-entry: "MousePrimary";
    }
    * {
      background-color: transparent;
      text-color: #ffffff;
    }
    window {
      location: center;
      anchor: center;
      x-offset: 0px;
      y-offset: 0px;
      width: ${width};
      border: 2px;
      border-color: rgba(255, 255, 255, 0.2);
      border-radius: 14px;
      background-color: rgba(0, 0, 0, 0.25);
      padding: 4px;
    }
    mainbox {
      spacing: 4px;
      children: [${if input then "inputbar" else "inputbar, listview"}];
    }
    inputbar {
      children: [${if input then "prompt, entry" else "prompt"}];
      spacing: 8px;
      padding: 8px 12px;
      border-radius: 10px;
      background-color: rgba(255, 255, 255, 0.08);
      margin: 0 0 2px 0;
    }
    prompt { text-color: rgba(255, 255, 255, 0.7); }
    textbox-prompt-colon { enabled: false; }
    entry { enabled: ${if input then "true" else "false"}; }
    listview {
      lines: 8;
      spacing: 4px;
      scrollbar: false;
      padding: 2px;
      fixed-height: false;
    }
    element {
      padding: 8px 12px;
      border-radius: 10px;
      orientation: horizontal;
    }
    element-text {
      background-color: transparent;
      text-color: #ffffff;
      font: "JetBrainsMono Nerd Font 13";
      vertical-align: 0.5;
    }
    element selected {
      background-color: rgba(255, 255, 255, 0.1);
      border: 2px;
      border-color: rgba(255, 255, 255, 0.9);
    }
    element-text selected { text-color: #ffffff; }
  '';

  # ==========================================================================
  # WORKSPACE-BIND : attribue un groupe de workspaces à chaque écran actif
  #
  #   Auto (défaut)  : bloc de 10 par écran, dans l'ordre eDP-1 puis externes
  #                    de gauche à droite → eDP-1 = 1-10, externe 1 = 11-20…
  #   eDP-1 éteint   : externe 1 = 1-10, externe 2 = 11-20…
  #   Disposition    : groupes définis via display-layouts pour ces écrans ;
  #                    un écran sans groupe prend le premier bloc de 10 libre.
  #
  # Les écrans en miroir sont ignorés (pas de workspaces propres). Les règles
  # sont en `persistent:true` et les workspaces déjà ouverts sont rapatriés.
  # ==========================================================================
  workspace-bind = pkgs.writeShellScriptBin "workspace-bind" ''
    INTERNAL="eDP-1"
    CONF="$HOME/.config/hypr/workspaces.conf"
    BLOCK=10

    MONS=$(${HYPR} monitors -j)

    # eDP-1 n'apparaît dans `monitors` (sans `all`) que s'il est actif.
    INT_ON=$(printf '%s' "$MONS" | ${JQ} --arg n "$INTERNAL" \
      '[.[] | select(.name == $n and .mirrorOf == "none")] | length')

    # Écrans externes actifs hors miroir, triés gauche → droite.
    mapfile -t EXTS < <(printf '%s' "$MONS" | ${JQ} -r --arg n "$INTERNAL" \
      '[.[] | select(.name != $n and .mirrorOf == "none")] | sort_by(.x, .y) | .[].name')

    ORDER=()
    [ "$INT_ON" -gt 0 ] && ORDER+=("$INTERNAL")
    ORDER+=("''${EXTS[@]}")
    [ "''${#ORDER[@]}" -eq 0 ] && exit 0

    # Groupes personnalisés de la disposition sauvegardée pour ces écrans.
    declare -A SPEC
    EXTRA_AUTO=""
    LAYOUT=""
    if SIG=$(${layout-sig}) && [ -f "${LAYOUT_DIR}/$SIG.json" ]; then
      LAYOUT=$(${JQ} -c '${NORM}' "${LAYOUT_DIR}/$SIG.json")
    fi
    if [ -n "$LAYOUT" ]; then
      INT_SPEC=$(printf '%s' "$LAYOUT" | ${JQ} -r '.internal.workspaces // empty')
      for m in "''${EXTS[@]}"; do
        d=$(printf '%s' "$MONS" | ${JQ} -r --arg n "$m" '.[] | select(.name == $n) | .description')
        SPEC[$m]=$(printf '%s' "$LAYOUT" | ${JQ} -r --arg d "$d" \
          '.monitors[] | select(.description == $d) | .workspaces // empty' | head -1)
      done
      if [ "$INT_ON" -gt 0 ]; then
        SPEC[$INTERNAL]="$INT_SPEC"
      elif [ "''${#EXTS[@]}" -gt 0 ]; then
        # eDP-1 éteint : le premier externe récupère aussi le groupe de l'écran
        # interne, pour ne perdre aucun workspace.
        first="''${EXTS[0]}"
        if [ -n "$INT_SPEC" ]; then
          SPEC[$first]="$INT_SPEC''${SPEC[$first]:+,''${SPEC[$first]}}"
        elif [ -n "''${SPEC[$first]}" ]; then
          EXTRA_AUTO="$first"
        fi
      fi
    fi

    # "1,3,5-7" → une ligne par workspace
    expand() {
      local part IFS=,
      for part in $1; do
        case "$part" in
          *-*) seq "''${part%-*}" "''${part#*-}" ;;
          *)   echo "$part" ;;
        esac
      done
    }

    declare -A OWNER

    # Premier bloc de 10 entièrement libre → attribué à l'écran $1.
    claim_block() {
      local b=1 ws free
      while :; do
        free=1
        for ws in $(seq "$b" $((b + BLOCK - 1))); do
          [ -n "''${OWNER[$ws]:-}" ] && { free=0; break; }
        done
        [ "$free" -eq 1 ] && break
        b=$((b + BLOCK))
      done
      for ws in $(seq "$b" $((b + BLOCK - 1))); do OWNER[$ws]="$1"; done
    }

    # 1) Groupes explicites (premier écran servi en cas de chevauchement)
    for m in "''${ORDER[@]}"; do
      for ws in $(expand "''${SPEC[$m]:-}"); do
        [ -z "''${OWNER[$ws]:-}" ] && OWNER[$ws]="$m"
      done
    done
    # 2) Écrans en auto
    [ -n "$EXTRA_AUTO" ] && claim_block "$EXTRA_AUTO"
    for m in "''${ORDER[@]}"; do
      [ -z "''${SPEC[$m]:-}" ] && claim_block "$m"
    done

    # Tout workspace hors groupe (jusqu'à 30, ou plus si un existe) est épinglé
    # au dernier écran, sinon il s'ouvrirait sur l'écran focus → mélange.
    LAST="''${ORDER[-1]}"
    MAXWS=30
    for ws in "''${!OWNER[@]}"; do [ "$ws" -gt "$MAXWS" ] && MAXWS=$ws; done
    HIGHEST=$(${HYPR} workspaces -j | ${JQ} '[.[] | select(.id > 0) | .id] | max // 0')
    [ "$HIGHEST" -gt "$MAXWS" ] && MAXWS=$HIGHEST
    EXISTING=" $(${HYPR} workspaces -j | ${JQ} -r '[.[] | select(.id > 0) | .id] | join(" ")') "

    declare -A SEEN
    KW=""
    MV=""
    mkdir -p "$(dirname "$CONF")"
    : > "$CONF.tmp"
    for ws in $(seq 1 "$MAXWS"); do
      m="''${OWNER[$ws]:-}"
      if [ -n "$m" ]; then
        RULE="$ws, monitor:$m, persistent:true"
        # Premier workspace du groupe = workspace par défaut de l'écran
        if [ -z "''${SEEN[$m]:-}" ]; then
          RULE="$RULE, default:true"
          SEEN[$m]=1
        else
          RULE="$RULE, default:false"
        fi
      else
        m="$LAST"
        # `keyword workspace` fusionne avec la règle existante : sans false
        # explicite, un persistent/default hérité d'un ancien écran reste.
        RULE="$ws, monitor:$m, persistent:false, default:false"
      fi
      echo "workspace = $RULE" >> "$CONF.tmp"
      KW+="keyword workspace $RULE ; "
      # Un workspace déjà ouvert ailleurs ne suit pas la règle tout seul.
      case "$EXISTING" in
        *" $ws "*) MV+="dispatch moveworkspacetomonitor $ws $m ; " ;;
      esac
    done
    # Réécrit seulement si le contenu change : un fichier sourcé modifié peut
    # recharger la config Hyprland et annuler les règles posées à chaud.
    if cmp -s "$CONF.tmp" "$CONF"; then
      rm -f "$CONF.tmp"
    else
      mv "$CONF.tmp" "$CONF"
    fi

    ${HYPR} --batch "$KW" >/dev/null
    [ -n "$MV" ] && ${HYPR} --batch "$MV" >/dev/null
    exit 0
  '';

  # ==========================================================================
  # SCRIPT CENTRAL : applique un mode d'affichage
  # Usage : display-apply <pc-only|external-only|lid-closed|mirror|extend|
  #                        save-layout|restore-layout|restore-layout-external>
  # ==========================================================================
  display-apply = pkgs.writeShellScriptBin "display-apply" ''
    MODE="$1"
    INTERNAL="eDP-1"

    # Voir LOCK_FILE : ignore les événements Hyprland que ce script provoque.
    touch "${LOCK_FILE}"
    trap '( sleep 5; rm -f "${LOCK_FILE}" ) >/dev/null 2>&1 &' EXIT

    PREV_MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "")
    STAMP_FILE="${LOCK_FILE}.stamp"
    NOW_TS=$(date +%s)
    LAST_TS=$(cat "$STAMP_FILE" 2>/dev/null || echo 0)

    # Anti-rafale : même mode redemandé moins de 10 s après la dernière
    # application → on ne refait rien (donc aucune notif en boucle), même si
    # un event Hyprland a échappé au verrou.
    if [ "$MODE" != "set-mon" ] && [ "$MODE" = "$PREV_MODE" ] && [ $(( NOW_TS - LAST_TS )) -lt 10 ]; then
      exit 0
    fi
    echo "$NOW_TS" > "$STAMP_FILE"

    # Notif d'affichage : silencieuse si le mode ne change pas, et remplacée
    # en place (hint synchronous) donc jamais empilée.
    notify_display() {
      [ "$MODE" = "$PREV_MODE" ] && return 0
      ${NOTIFY} -h string:x-canonical-private-synchronous:display-switch \
        "Affichage" "$1" -i video-display -t 2000
    }

    INT_RES="1920x1080@60"
    INT_SCALE="1"
    # Position de l'écran interne dans la disposition étendue (définie dans home.nix)
    INT_EXT_POS="1520x1440"

    ext_monitors() {
      ${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "eDP-1") | .name'
    }

    mon_desc() {
      ${HYPR} monitors all -j | ${JQ} -r --arg n "$1" '.[] | select(.name == $n) | .description'
    }

    desc_name() {
      ${HYPR} monitors all -j | ${JQ} -r --arg d "$1" '.[] | select(.description == $d) | .name' | head -1
    }

    # Pose une règle écran par nom de connecteur ET par description :
    # monitors.conf (nwg-displays) cible les noms, home.nix les descriptions.
    # Sans les deux, la règle restante peut l'emporter (cause du miroir cassé).
    set_mon() {
      local desc
      desc=$(mon_desc "$1")
      ${HYPR} keyword monitor "$1,$2" >/dev/null
      [ -n "$desc" ] && ${HYPR} keyword monitor "desc:$desc,$2" >/dev/null
    }

    layout_file() {
      local sig
      sig=$(${layout-sig}) || return 1
      [ -f "${LAYOUT_DIR}/$sig.json" ] && echo "${LAYOUT_DIR}/$sig.json"
    }

    # Règle "WxH@RR,XxY,scale" sauvegardée pour une description (vide sinon)
    saved_rule() {
      local file
      file=$(layout_file) || return 0
      ${JQ} -r --arg d "$1" '${NORM} | .monitors[] | select(.description == $d)
        | "\(.width)x\(.height)@\(.refreshRate),\(.x)x\(.y),\(.scale)"' "$file" | head -1
    }

    # Remet un externe en affichage normal : disposition sauvegardée si elle
    # existe, sinon résolution préférée placée automatiquement.
    reset_ext() {
      local rule
      rule=$(saved_rule "$(mon_desc "$1")")
      set_mon "$1" "''${rule:-preferred,auto,1}"
    }

    # Externes désactivés (pc-only) ou en miroir : à réactiver hors miroir.
    unmirror_all() {
      ${HYPR} monitors all -j | ${JQ} -r \
        '.[] | select(.name != "eDP-1" and (.disabled or .mirrorOf != "none")) | .name' | \
        while read -r m; do reset_ext "$m"; done
    }

    # Écrans sans disposition sauvegardée (hors Xiaomi/MSI, placés par
    # home.nix) : collés à droite d'eDP-1, bords bas alignés, enchaînés de
    # gauche à droite. Évite les écrans éloignés inatteignables à la souris
    # (ex : vieille règle nwg-displays par nom de port, pour un autre écran).
    place_unknown() {
      local right bottom name desc w h rr scale lw lh
      right=$(( ''${INT_EXT_POS%x*} + ''${INT_RES%%x*} ))
      bottom=$(( ''${INT_EXT_POS#*x} + $(echo "$INT_RES" | cut -dx -f2 | cut -d@ -f1) ))
      ${HYPR} monitors all -j | ${JQ} -r '
        [.[] | select(.name != "eDP-1" and (.disabled | not) and .mirrorOf == "none")]
        | sort_by(.x) | .[]
        | ((.transform % 2) == 1) as $rot
        | [ .name, .description, .width, .height, .refreshRate, .scale,
            ((if $rot then .height else .width end) / .scale | floor),
            ((if $rot then .width else .height end) / .scale | floor) ]
        | @tsv' | \
      while IFS=$'\t' read -r name desc w h rr scale lw lh; do
        echo "$desc" | grep -qiE "Xiaomi|MSI|Microstep" && continue
        [ -n "$(saved_rule "$desc")" ] && continue
        set_mon "$name" "''${w}x''${h}@''${rr},''${right}x$(( bottom - lh )),$scale"
        right=$(( right + lw ))
      done
    }

    restore_saved() {
      local file row desc name
      file=$(layout_file) || return 1
      ${JQ} -c '${NORM} | .monitors[]' "$file" | while read -r row; do
        desc=$(echo "$row" | ${JQ} -r '.description')
        name=$(desc_name "$desc")
        [ -z "$name" ] && continue
        # Disable/re-enable plutôt qu'un simple repositionnement : sinon les
        # workspaces déjà actifs gardent un layout figé à l'ancienne position
        # (fenêtres invisibles bien que présentes).
        set_mon "$name" disable
        set_mon "$name" "$(echo "$row" | ${JQ} -r '"\(.width)x\(.height)@\(.refreshRate),\(.x)x\(.y),\(.scale)"')"
      done
    }

    case "$MODE" in

      pc-only)
        # Désactive les externes, eDP-1 reste à INT_EXT_POS pour éviter
        # le chevauchement avec les externes (0x0) lors d'un re-branchement
        for m in $(ext_monitors); do
          set_mon "$m" disable
        done
        ${HYPR} keyword monitor "$INTERNAL,$INT_RES,$INT_EXT_POS,$INT_SCALE"
        notify_display "PC uniquement"
        ;;

      external-only)
        unmirror_all
        ${HYPR} keyword monitor "$INTERNAL,disable"
        notify_display "Externe uniquement"
        ;;

      lid-closed)
        unmirror_all
        ${HYPR} keyword monitor "$INTERNAL,disable"
        notify_display "Capot fermé"
        ;;

      mirror)
        # eDP-1 = source ; chaque externe le recopie dans sa résolution
        # préférée (Hyprland met à l'échelle).
        ${HYPR} keyword monitor "$INTERNAL,$INT_RES,0x0,$INT_SCALE"
        for m in $(ext_monitors); do
          set_mon "$m" "preferred,auto,1,mirror,$INTERNAL"
        done
        notify_display "Mode miroir"
        ;;

      extend)
        unmirror_all
        LID_FILE=$(ls /proc/acpi/button/lid/*/state 2>/dev/null | head -1)
        LID_STATE=$([ -n "$LID_FILE" ] && awk '{print $2}' "$LID_FILE" || echo "open")

        if [ "$LID_STATE" = "closed" ]; then
          # Capot fermé : eDP-1 inaccessible, le premier externe devient principal
          ${HYPR} keyword monitor "$INTERNAL,disable"
        else
          ${HYPR} keyword monitor "$INTERNAL,$INT_RES,$INT_EXT_POS,$INT_SCALE"
        fi
        sleep 1
        place_unknown
        notify_display "Mode étendu"
        ;;

      set-mon)
        # Réglage d'un écran depuis le menu Quickshell : display-apply set-mon <nom> <règle>
        # (règle = "WxH@RR,XxY,scale" ou "disable"). Le mode courant n'est pas modifié.
        set_mon "$2" "$3"
        sleep 1
        ;;

      save-layout)
        # Sauvegarde position/résolution des externes, indexée par signature.
        # Le nom et les groupes de workspaces déjà définis sont conservés.
        if ! SIG=$(${layout-sig}); then
          notify_display "Aucun écran externe à enregistrer"
          exit 0
        fi
        if ${HYPR} monitors -j | ${JQ} -e 'any(.[]; .mirrorOf != "none")' >/dev/null; then
          notify_display "Quitte le mode miroir avant d'enregistrer"
          exit 0
        fi
        mkdir -p "${LAYOUT_DIR}"
        FILE="${LAYOUT_DIR}/$SIG.json"
        OLD=$([ -f "$FILE" ] && ${JQ} -c '${NORM}' "$FILE" || echo '{}')
        ${HYPR} monitors all -j | ${JQ} --argjson old "$OLD" '
          [.[] | select(.name != "eDP-1") | {description, x, y, width, height, refreshRate, scale}] as $m
          | {
              name: ($old.name // ($m | map(.description) | join(" + "))),
              internal: ($old.internal // {}),
              monitors: ($m | map(. as $x | . + {
                workspaces: ([($old.monitors // [])[] | select(.description == $x.description) | .workspaces] | first)
              }))
            }' > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
        notify_display "Disposition enregistrée"
        exit 0
        ;;

      restore-layout)
        # Réapplique la disposition sauvegardée pour les externes connectés
        # (eDP-1 reste actif).
        if restore_saved; then
          ${HYPR} keyword monitor "$INTERNAL,$INT_RES,$INT_EXT_POS,$INT_SCALE"
          notify_display "Disposition restaurée"
        fi
        ;;

      restore-layout-external)
        # Idem, puis désactive eDP-1 (capot fermé).
        if restore_saved; then
          ${HYPR} keyword monitor "$INTERNAL,disable"
          notify_display "Disposition restaurée (externe uniquement)"
        fi
        ;;

    esac

    # Mémorise le mode pour pouvoir le réappliquer après un hyprctl reload
    case "$MODE" in
      pc-only|external-only|lid-closed|mirror|extend|restore-layout|restore-layout-external)
        mkdir -p "$(dirname "${MODE_FILE}")"
        echo "$MODE" > "${MODE_FILE}"
        ;;
    esac

    # Laisse Hyprland finir d'appliquer les écrans avant de lire leur état.
    sleep 1
    ${workspace-bind}/bin/workspace-bind
    # Écrans renommés / reconfigurés : sans ça, un écran branché peut rester sans fond
    ${WALLPAPER_RESTORE}

    # Horodatage de fin : la fenêtre anti-rafale part de la fin réelle.
    date +%s > "$STAMP_FILE"
  '';

  # ==========================================================================
  # DISPLAY-LAYOUTS : gestion des dispositions sauvegardées (rofi)
  # Liste → Appliquer / Groupes de workspaces / Renommer / Supprimer
  # ==========================================================================
  display-layouts = pkgs.writeShellScriptBin "display-layouts" ''
    DIR="${LAYOUT_DIR}"
    mkdir -p "$DIR"

    # Menu à choix : entrées sur stdin, renvoie l'index choisi (vide si Échap)
    pick() {
      ${ROFI} -dmenu -i -no-custom -format i -p "$1" \
        -theme ~/.config/rofi/display-layouts.rasi
    }

    # Saisie libre pré-remplie avec $2
    ask() {
      printf "" | ${ROFI} -dmenu -p "$1" -filter "$2" \
        -theme ~/.config/rofi/display-input.rasi
    }

    notify() {
      ${NOTIFY} -h string:x-canonical-private-synchronous:display-layouts \
        "Dispositions" "$1" -i video-display -t 2500
    }

    # write_json <fichier> <filtre jq> [--arg…]
    write_json() {
      local file="$1" filter="$2"; shift 2
      ${JQ} "$@" '${NORM} | '"$filter" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    }

    # Si la disposition modifiée est celle des écrans branchés, on l'applique.
    rebind_if_current() {
      if [ "$(${layout-sig})" = "$(basename "$1" .json)" ]; then
        workspace-bind
      fi
    }

    layout_name() {
      ${JQ} -r '${NORM} | .name // (.monitors | map(.description) | join(" + "))' "$1"
    }

    edit_groups() {
      local file="$1" choice idx cur new
      while :; do
        mapfile -t DESCS < <(${JQ} -r '${NORM} | .monitors[].description' "$file")
        {
          printf '󰌢  Écran du PC (eDP-1)  →  %s\n' \
            "$(${JQ} -r '${NORM} | .internal.workspaces // "auto"' "$file")"
          for d in "''${DESCS[@]}"; do
            printf '󰍹  %s  →  %s\n' "''${d:0:32}" \
              "$(${JQ} -r --arg d "$d" '${NORM} | [.monitors[] | select(.description == $d) | .workspaces // "auto"] | first' "$file")"
          done
          printf '󰑓  Tout remettre en auto\n'
        } > "$TMP"
        idx=$(pick "󰕰  Groupes" < "$TMP")
        [ -z "$idx" ] && return

        if [ "$idx" -eq $(( ''${#DESCS[@]} + 1 )) ]; then
          write_json "$file" '.internal.workspaces = null | .monitors |= map(.workspaces = null)'
          rebind_if_current "$file"
          continue
        fi

        if [ "$idx" -eq 0 ]; then
          cur=$(${JQ} -r '${NORM} | .internal.workspaces // ""' "$file")
        else
          cur=$(${JQ} -r --arg d "''${DESCS[$((idx - 1))]}" \
            '${NORM} | [.monitors[] | select(.description == $d) | .workspaces // ""] | first' "$file")
        fi

        new=$(ask "Workspaces (ex : 11-20 ou 1,3,5-7 ; vide = auto)" "$cur") || continue
        new=$(printf '%s' "$new" | tr -d ' ')
        [ "$new" = "auto" ] && new=""
        if [ -n "$new" ] && ! printf '%s' "$new" | grep -qE '^[1-9][0-9]*(-[1-9][0-9]*)?(,[1-9][0-9]*(-[1-9][0-9]*)?)*$'; then
          notify "Format invalide : « $new »"
          continue
        fi
        [ -z "$new" ] && new=null || new="\"$new\""

        if [ "$idx" -eq 0 ]; then
          write_json "$file" '.internal.workspaces = $v' --argjson v "$new"
        else
          write_json "$file" '.monitors |= map(if .description == $d then .workspaces = $v else . end)' \
            --argjson v "$new" --arg d "''${DESCS[$((idx - 1))]}"
        fi
        rebind_if_current "$file"
      done
    }

    TMP=$(mktemp)
    trap 'rm -f "$TMP"' EXIT
    CUR_SIG=$(${layout-sig} || true)

    while :; do
      FILES=()
      : > "$TMP"
      [ -n "$CUR_SIG" ] && printf '󰆓  Enregistrer la disposition actuelle\n' >> "$TMP"
      for f in "$DIR"/*.json; do
        [ -f "$f" ] || continue
        # Fichiers vides (sauvegarde sans externe) : ignorés
        [ "$(${JQ} '${NORM} | .monitors | length' "$f" 2>/dev/null || echo 0)" -gt 0 ] || continue
        FILES+=("$f")
        mark="   "
        [ "$(basename "$f" .json)" = "$CUR_SIG" ] && mark="󰄬  "
        printf '%s%s\n' "$mark" "$(layout_name "$f")" >> "$TMP"
      done

      idx=$(pick "󰕮  Dispositions" < "$TMP")
      [ -z "$idx" ] && exit 0

      if [ -n "$CUR_SIG" ]; then
        if [ "$idx" -eq 0 ]; then
          display-apply save-layout
          continue
        fi
        idx=$((idx - 1))
      fi
      FILE="''${FILES[$idx]}"
      IS_CUR=0
      [ "$(basename "$FILE" .json)" = "$CUR_SIG" ] && IS_CUR=1

      while [ -f "$FILE" ]; do
        : > "$TMP"
        ACTIONS=()
        if [ "$IS_CUR" -eq 1 ]; then
          printf '󰁨  Appliquer\n' >> "$TMP"; ACTIONS+=(apply)
        fi
        printf '󰕰  Groupes de workspaces\n󰑕  Renommer\n󰆴  Supprimer\n' >> "$TMP"
        ACTIONS+=(groups rename delete)

        a=$(pick "$(layout_name "$FILE")" < "$TMP")
        [ -z "$a" ] && break

        case "''${ACTIONS[$a]}" in
          apply)
            display-apply restore-layout
            exit 0
            ;;
          groups)
            edit_groups "$FILE"
            ;;
          rename)
            name=$(ask "Nom" "$(layout_name "$FILE")") || continue
            [ -n "$name" ] && write_json "$FILE" '.name = $n' --arg n "$name"
            ;;
          delete)
            printf '󰜺  Annuler\n󰆴  Supprimer « %s »\n' "$(layout_name "$FILE")" > "$TMP"
            if [ "$(pick "Confirmer" < "$TMP")" = "1" ]; then
              rm -f "$FILE"
              notify "Disposition supprimée"
              [ "$IS_CUR" -eq 1 ] && workspace-bind
            fi
            ;;
        esac
      done
    done
  '';

  # ==========================================================================
  # DISPLAY-STATE : état complet en une ligne JSON pour le menu Quickshell
  # (SUPER+P) : { mode, sig, monitors (hyprctl), layouts [{file,name,count,current}] }
  # ==========================================================================
  display-state = pkgs.writeShellScriptBin "display-state" ''
    DIR="${LAYOUT_DIR}"
    SIG=$(${layout-sig} 2>/dev/null || true)
    MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "")
    LAYOUTS="[]"
    if ls "$DIR"/*.json >/dev/null 2>&1; then
      # Fichiers avec leur signature (nom de fichier) pour marquer l'actuelle
      LAYOUTS=$(for f in "$DIR"/*.json; do
        ${JQ} -c --arg f "$(basename "$f" .json)" --arg sig "$SIG" '${NORM}
          | select((.monitors | length) > 0)
          | {file: $f, current: ($f == $sig), count: (.monitors | length),
             name: (.name // (.monitors | map(.description) | join(" + "))),
             internal: (.internal.workspaces // ""),
             monitors: (.monitors | map({description, workspaces: (.workspaces // "")}))}' "$f" 2>/dev/null
      done | ${JQ} -cs '.')
    fi
    ${HYPR} monitors all -j | ${JQ} -c --arg mode "$MODE" --arg sig "$SIG" --argjson layouts "$LAYOUTS" '
      {mode: $mode, sig: $sig, layouts: $layouts,
       monitors: map({name, description, x, y, width, height, refreshRate, scale,
                      mirrorOf, disabled, availableModes})}'
  '';

  # ==========================================================================
  # DISPLAY-LAYOUT-EDIT : gestion non interactive d'une disposition (menu Quickshell)
  #   display-layout-edit rename <sig> <nom>
  #   display-layout-edit groups <sig> <internal|description> <spec>   (vide = auto)
  #   display-layout-edit reset-groups <sig>
  #   display-layout-edit delete <sig>
  # ==========================================================================
  display-layout-edit = pkgs.writeShellScriptBin "display-layout-edit" ''
    ACTION="$1"; SIG="$2"
    case "$SIG" in *[!0-9a-f]*|"") exit 1 ;; esac
    FILE="${LAYOUT_DIR}/$SIG.json"
    [ -f "$FILE" ] || exit 1

    notify() {
      ${NOTIFY} -h string:x-canonical-private-synchronous:display-layouts \
        "Dispositions" "$1" -i video-display -t 2500
    }
    write_json() {
      local filter="$1"; shift
      ${JQ} "$@" '${NORM} | '"$filter" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    }
    # Disposition des écrans branchés : on réapplique les groupes de workspaces
    rebind_if_current() {
      if [ "$(${layout-sig})" = "$SIG" ]; then
        ${workspace-bind}/bin/workspace-bind
      fi
    }

    case "$ACTION" in
      rename)
        [ -n "$3" ] && write_json '.name = $n' --arg n "$3"
        ;;
      groups)
        spec=$(printf '%s' "$4" | tr -d ' ')
        [ "$spec" = "auto" ] && spec=""
        if [ -n "$spec" ] && ! printf '%s' "$spec" | grep -qE '^[1-9][0-9]*(-[1-9][0-9]*)?(,[1-9][0-9]*(-[1-9][0-9]*)?)*$'; then
          notify "Format invalide : « $spec »"
          exit 1
        fi
        if [ -z "$spec" ]; then v=null; else v="\"$spec\""; fi
        if [ "$3" = "internal" ]; then
          write_json '.internal.workspaces = $v' --argjson v "$v"
        else
          write_json '.monitors |= map(if .description == $d then .workspaces = $v else . end)' \
            --argjson v "$v" --arg d "$3"
        fi
        rebind_if_current
        ;;
      reset-groups)
        write_json '.internal.workspaces = null | .monitors |= map(.workspaces = null)'
        rebind_if_current
        notify "Groupes remis en auto"
        ;;
      delete)
        rm -f "$FILE"
        notify "Disposition supprimée"
        rebind_if_current
        ;;
    esac
  '';

  # SUPER+P : affiche / masque le menu Quickshell des écrans (modules/quickshell-launcher/DisplayMenu.qml)
  display-menu = pkgs.writeShellScriptBin "display-menu" ''
    ${config.programs.quickshell.package}/bin/quickshell ipc -c launcher call display toggle >/dev/null 2>&1
  '';

  # ==========================================================================
  # MONITOR-WATCHER : service systemd, écoute socket Hyprland
  # monitoradded  → extend (capot ouvert) ou external-only (capot fermé)
  # monitorremoved → pc-only (0 externe) ou réapplique mode correct (≥1 externe)
  # ==========================================================================
  monitor-watcher = pkgs.writeShellScriptBin "monitor-watcher" ''
    INTERNAL="eDP-1"

    SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    until [ -S "$SOCKET" ]; do sleep 1; done

    ${SOCAT} -u "UNIX-CONNECT:$SOCKET" - | while IFS= read -r event; do

      ETYPE="''${event%%>>*}"
      EDATA="''${event#*>>}"

      case "$ETYPE" in

        monitoradded)
          # Fond d'écran réappliqué dans tous les cas, même quand display-apply
          # n'est pas lancé (verrou, nwg-displays, anti-rafale)
          ( sleep 4; ${WALLPAPER_RESTORE} ) >/dev/null 2>&1 &
          [ -f "${LOCK_FILE}" ] && continue
          # nwg-displays déclenche lui-même des events monitoradded/removed
          # en interne quand on applique un changement (sans débranchement
          # réel). Si l'appli tourne, on n'intervient pas — l'utilisateur
          # est en train d'arranger manuellement, il faut pas écraser ça.
          if pgrep -f nwg-displays >/dev/null 2>&1; then continue; fi

          MONITOR="$EDATA"
          [ "$MONITOR" = "$INTERNAL" ] && continue

          LOCK="$XDG_RUNTIME_DIR/disp-added-$(echo "$MONITOR" | tr '/' '-')"
          NOW=$(date +%s)
          if [ -f "$LOCK" ]; then
            LAST=$(cat "$LOCK" 2>/dev/null || echo 0)
            [ $(( NOW - LAST )) -lt 10 ] && continue
          fi
          echo "$NOW" > "$LOCK"

          sleep 2
          # Le verrou a pu être posé pendant l'attente : on revérifie.
          [ -f "${LOCK_FILE}" ] && continue
          LID_FILE=$(ls /proc/acpi/button/lid/*/state 2>/dev/null | head -1)
          LID_STATE=$([ -n "$LID_FILE" ] && awk '{print $2}' "$LID_FILE" || echo "open")

          # Écrans connus (MSI/Xiaomi, maison) → logique dédiée existante.
          # Sinon (ex : écrans du boulot) → restaure la disposition
          # sauvegardée pour cette signature d'écrans, si elle existe.
          KNOWN=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "eDP-1") | .description' | grep -icE "Xiaomi|MSI|Microstep")

          if [ "$KNOWN" -gt 0 ]; then
            if [ "$LID_STATE" = "closed" ]; then
              ${display-apply}/bin/display-apply lid-closed
            else
              ${display-apply}/bin/display-apply extend
            fi
          else
            SIG=$(${layout-sig})
            if [ -n "$SIG" ] && [ -f "${LAYOUT_DIR}/$SIG.json" ]; then
              if [ "$LID_STATE" = "closed" ]; then
                ${display-apply}/bin/display-apply restore-layout-external
              else
                ${display-apply}/bin/display-apply restore-layout
              fi
            else
              # Écran inconnu : étendu, eDP-1 = 1-10, externe = 11-20.
              ${display-apply}/bin/display-apply extend
              # Notif persistante avec bouton d'action → ouvre nwg-displays.
              # Une fois arrangé (position/résolution), Super+Maj+P enregistre
              # la disposition pour ces noms d'écrans.
              (
                ACTION=$(${NOTIFY} -A "open=Ouvrir nwg-displays" "Affichage" "Écrans inconnus — configure puis Super+Maj+P pour enregistrer" -i video-display -t 0)
                [ "$ACTION" = "open" ] && ${NWG} &
              ) &
            fi
          fi
          ;;

        configreloaded)
          [ -f "${LOCK_FILE}" ] && continue
          # Un rebuild NixOS réécrit hyprland.conf → hyprctl reload → les
          # lignes monitor= de home.nix/monitors.conf reprennent la main
          # (eDP-1 réactivé, écran inconnu replacé loin). On réapplique le
          # dernier mode choisi.
          if pgrep -f nwg-displays >/dev/null 2>&1; then continue; fi
          LAST=$(cat "${MODE_FILE}" 2>/dev/null || echo "")
          case "$LAST" in
            external-only|lid-closed|mirror|extend|restore-layout|restore-layout-external)
              sleep 2
              [ -f "${LOCK_FILE}" ] && continue
              EXT=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | head -1)
              [ -n "$EXT" ] && ${display-apply}/bin/display-apply "$LAST"
              ;;
          esac
          ;;

        monitorremoved)
          [ -f "${LOCK_FILE}" ] && continue
          if pgrep -f nwg-displays >/dev/null 2>&1; then continue; fi

          MONITOR="$EDATA"
          [ "$MONITOR" = "$INTERNAL" ] && continue

          sleep 1
          [ -f "${LOCK_FILE}" ] && continue
          EXT=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
          if [ -z "$EXT" ]; then
            ${display-apply}/bin/display-apply pc-only
          else
            ${display-apply}/bin/display-apply extend
          fi
          ;;

      esac

    done
  '';

  # ==========================================================================
  # LID-WATCHER : service systemd, poll /proc/acpi lid state
  # closed + externe présent → lid-closed (workspaces migrés)
  # open après triggered    → extend
  # ==========================================================================
  lid-watcher = pkgs.writeShellScriptBin "lid-watcher" ''
    INTERNAL="eDP-1"
    LID_FILE=$(ls /proc/acpi/button/lid/*/state 2>/dev/null | head -1)
    [ -z "$LID_FILE" ] && exit 0

    until ${HYPR} monitors -j >/dev/null 2>&1; do sleep 1; done

    prev_state=$(awk '{print $2}' "$LID_FILE")

    while true; do
      sleep 2
      state=$(awk '{print $2}' "$LID_FILE")

      if [ "$state" != "$prev_state" ]; then
        prev_state="$state"
        EXT=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | head -1)

        case "$state" in
          closed)
            [ -n "$EXT" ] && ${display-apply}/bin/display-apply lid-closed
            ;;
          open)
            [ -n "$EXT" ] && ${display-apply}/bin/display-apply extend
            ;;
        esac
      fi
    done
  '';

in
{
  # --------------------------------------------------------------------------
  # Thèmes Rofi
  # --------------------------------------------------------------------------
  xdg.configFile."rofi/display-layouts.rasi".text = rofiTheme { width = "520px"; };
  xdg.configFile."rofi/display-input.rasi".text   = rofiTheme { width = "520px"; input = true; };

  # --------------------------------------------------------------------------
  # ~/.config/hypr/monitors.conf doit exister pour que `source` (dans
  # hyprland.conf) ne plante pas avant le premier "Apply" de nwg-displays.
  # Juste un touch : le contenu est géré par nwg-displays, pas par nous.
  # --------------------------------------------------------------------------
  home.activation.ensureMonitorsConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    [ -f "$HOME/.config/hypr/monitors.conf" ] || touch "$HOME/.config/hypr/monitors.conf"
    [ -f "$HOME/.config/hypr/workspaces.conf" ] || touch "$HOME/.config/hypr/workspaces.conf"
  '';

  # --------------------------------------------------------------------------
  # Packages
  # --------------------------------------------------------------------------
  home.packages = [ display-apply display-state display-layout-edit display-menu display-layouts monitor-watcher lid-watcher workspace-bind ];

  # --------------------------------------------------------------------------
  # Services systemd user
  # --------------------------------------------------------------------------
  systemd.user.services.lid-watcher = {
    Unit = {
      Description = "Lid state watcher → migrate workspaces eDP-1";
      After       = [ "hyprland-session.target" ];
      PartOf      = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${lid-watcher}/bin/lid-watcher";
      Restart    = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  systemd.user.services.monitor-watcher = {
    Unit = {
      Description = "Hyprland monitor hotplug → mode automatique";
      After       = [ "hyprland-session.target" ];
      PartOf      = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${monitor-watcher}/bin/monitor-watcher";
      Restart    = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  # --------------------------------------------------------------------------
  # Keybindings : Super+P menu Quickshell, Super+Maj+P enregistrer, Super+Ctrl+P dispositions
  # --------------------------------------------------------------------------
  wayland.windowManager.hyprland.settings.bind = [
    "$mainMod, P, exec, display-menu"
    "$mainMod SHIFT, P, exec, display-apply save-layout"
    "$mainMod CTRL, P, exec, display-layouts"
  ];
}
