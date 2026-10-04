{ pkgs, ... }:

let
  # Commande `nixinstall` (alias interactif `install`) : cherche un paquet dans
  # nixpkgs, laisse choisir le(s) bon(s) résultat(s) avec fzf, l'ajoute à
  # home.nix sous la catégorie choisie, puis rebuild. Rebuild raté → home.nix restauré.
  # Usage : install <terme> [terme...]   (plusieurs termes = ET)
  nixinstall = pkgs.writeShellScriptBin "nixinstall" ''
    set -u
    HOME_NIX=/etc/nixos/home.nix
    SYS_NIX=/etc/nixos/configuration.nix
    JQ=${pkgs.jq}/bin/jq
    FZF=${pkgs.fzf}/bin/fzf
    B=$'\e[1m'; C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; D=$'\e[2m'; R=$'\e[0m'

    if [ $# -eq 0 ]; then
      echo "Usage : install <terme> [terme...]" >&2
      exit 1
    fi
    TERME="$*"
    PREMIER="''${1,,}"

    deja_installe() {
      grep -qE "^[[:space:]]*\(?(pkgs\.)?$1([[:space:]]|$|\))" "$HOME_NIX" "$SYS_NIX" 2>/dev/null
    }

    echo "''${C}󰍉''${R} Recherche de « $TERME » dans nixpkgs..."
    # nixpkgs du registre système = celui verrouillé par le flake
    # Sortie TSV : attr, version, catégories (",nav,cli,"), description.
    # Catégories devinées depuis le nom d'attribut et des mots-clés de la description.
    RESULTATS=$(nix search nixpkgs --json -- "$@" 2>/dev/null \
      | $JQ -r '
          def kw: [
            ["nav",    "web browser|internet browser|browser (for|built|based)|^(an? )?browser\\b|(privacy|security)[- ][a-z]+ browser|chromium|firefox|gecko|webkit|navigateur"],
            ["edit",   "\\beditor\\b|\\bide\\b|integrated development|text editing"],
            ["cli",    "command[- ]line|\\bcli\\b|terminal|\\btui\\b|\\bshell\\b"],
            ["ia",     "\\bai\\b|\\bllm|\\bgpt|claude|anthropic|openai|machine learning|neural|\\bagents?\\b"],
            ["comm",   "\\bchat|messag|e-?mail|\\birc\\b|matrix|voip|discord|telegram|signal"],
            ["media",  "audio|video|music|player|media|image|photo|stream|podcast"],
            ["jeu",    "\\bgames?\\b|emulator|minecraft|steam"],
            ["office", "office|\\bpdf\\b|document|\\bnotes?\\b|spreadsheet|calendar|productivity"],
            ["dev",    "compiler|language server|\\blsp\\b|\\bsdk\\b|debugger|build (tool|system)|programming|\\bapi\\b|framework|\\bgit\\b"],
            ["sys",    "system|monitor|\\bdisk|driver|kernel|hardware|network|\\bvpn\\b|backup|wayland|hyprland"],
            ["theme",  "\\bfonts?\\b|theme|icon|cursor|wallpaper"]
          ];
          to_entries[]
          | (.key | sub("^legacyPackages\\.[^.]+\\."; "")) as $a
          | select($a | test("-unwrapped$") | not)
          | ((.value.description // "") | ascii_downcase) as $d
          | ($a | test("^(vimPlugins|gnomeExtensions|vscode-extensions|tmuxPlugins|obs-studio-plugins|firefox-addons|kodiPackages|hyprlandPlugins|ankiAddons|mpvScripts|home-assistant-custom-components|home-assistant-custom-lovelace-modules|rofi-plugins|xfce4-panel-plugins)\\."))     as $ext
          | ($a | test("^(rPackages|(python[0-9]*|perl[0-9]*|lua[0-9_]*|ruby|node|ocaml|haskell|emacs|coq|chicken|akku|beam[0-9]*|elm|idris|julia|rust|go|php[0-9]*|texlive|dotnet|sbcl|lisp|cuda)[A-Za-z0-9_]*)\\.")) as $lib
          | [ (if $lib or $ext then empty
               else (kw[] | select(.[1] as $re | $d | test($re)) | .[0]) end),
              (if $ext then "ext" else empty end),
              (if $lib or ($d | test("\\blibrary\\b|\\bbindings?\\b|\\bmodule for\\b")) then "lib" else empty end),
              (if ($a | contains(".") | not) and ($lib | not) then "app" else empty end)
            ] as $c
          | [$a, (.value.version // "" | if . == "" then "-" else . end),
             ("," + ($c | join(",")) + ","), .value.description // ""]
          | @tsv')

    if [ -z "$RESULTATS" ]; then
      echo "''${Y}󰅚''${R} Aucun paquet trouvé pour « $TERME »."
      exit 1
    fi

    # Trop de résultats → demander le type de logiciel pour cibler
    SEUIL=15
    NB=$(printf '%s\n' "$RESULTATS" | wc -l)
    if [ "$NB" -gt "$SEUIL" ]; then
      declare -A LABEL=(
        [app]="Applications (paquets principaux, hors librairies)"
        [nav]="Navigateurs web"
        [edit]="Éditeurs / IDE"
        [cli]="Outils en ligne de commande / terminal"
        [ia]="IA / assistants / LLM"
        [comm]="Communication (chat, mail, visio)"
        [media]="Multimédia (audio, vidéo, image)"
        [jeu]="Jeux / émulateurs"
        [office]="Bureautique (PDF, notes, documents)"
        [dev]="Développement (compilateurs, LSP, SDK)"
        [sys]="Système / réseau / matériel"
        [theme]="Polices / thèmes / icônes"
        [ext]="Extensions / plugins (vim, gnome, vscode…)"
        [lib]="Librairies (python, haskell, node…)"
      )
      MENU=""
      for k in app nav edit cli ia comm media jeu office dev sys theme ext lib; do
        n=$(printf '%s\n' "$RESULTATS" | cut -f3 | grep -c ",$k,")
        [ "$n" -gt 0 ] && MENU+="$k"$'\t'"''${LABEL[$k]}  ($n)"$'\n'
      done
      MENU+="tout"$'\t'"Tout afficher  ($NB)"

      TYPE=$(printf '%s\n' "$MENU" | $FZF --reverse --height=50% \
        --delimiter=$'\t' --with-nth=2 \
        --prompt="type > " \
        --header="$NB résultats pour « $TERME » — quel type de logiciel cherches-tu ?" \
        | cut -f1)
      [ -z "$TYPE" ] && { echo "Annulé."; exit 0; }
      if [ "$TYPE" != "tout" ]; then
        RESULTATS=$(printf '%s\n' "$RESULTATS" | ${pkgs.gawk}/bin/awk -F'\t' -v k=",$TYPE," 'index($3, k)')
      fi
    fi

    # Tri : nom exact, puis nom qui commence par le terme, puis le reste (alphabétique)
    LIGNES=$(printf '%s\n' "$RESULTATS" | while IFS=$'\t' read -r attr ver _cats desc; do
      nom="''${attr##*.}"; nom="''${nom,,}"
      if [ "$nom" = "$PREMIER" ]; then rang=0
      elif [[ "$nom" == "$PREMIER"* ]]; then rang=1
      else rang=2; fi
      marque=" "
      deja_installe "$attr" && marque="✔"
      printf '%s\t%s\t%s\t%s\t%s\n' "$rang" "$attr" "$marque" "$ver" "$desc"
    done | sort -t$'\t' -k1,1n -k2,2 | cut -f2-)

    NB=$(printf '%s\n' "$LIGNES" | wc -l)
    CHOIX=$(printf '%s\n' "$LIGNES" \
      | ${pkgs.util-linux}/bin/column -t -s $'\t' -o '  ' \
      | $FZF --multi --ansi --reverse --height=80% \
          --prompt="paquet > " \
          --header="$NB résultat(s) · TAB = sélection multiple · Entrée = valider · ✔ = déjà installé" \
          --preview="nix eval --raw nixpkgs#{1}.meta.longDescription 2>/dev/null || nix eval --raw nixpkgs#{1}.meta.description 2>/dev/null; echo; echo; nix eval --raw nixpkgs#{1}.meta.homepage 2>/dev/null" \
          --preview-window=down,30%,wrap \
      | ${pkgs.gawk}/bin/awk '{print $1}')

    [ -z "$CHOIX" ] && { echo "Annulé."; exit 0; }

    A_AJOUTER=()
    for p in $CHOIX; do
      if deja_installe "$p"; then
        echo "''${Y}󰄬''${R} $p est déjà dans la config, ignoré."
      else
        A_AJOUTER+=("$p")
      fi
    done
    [ ''${#A_AJOUTER[@]} -eq 0 ] && exit 0

    # Catégories de la section « 4. APPLICATIONS ET OUTILS » de home.nix
    CATEGORIES=$(${pkgs.gawk}/bin/awk '
      /# 4\. APPLICATIONS ET OUTILS/ { in4 = 1; next }
      in4 && /^  \];/ { exit }
      in4 && /^    # --- .* ---$/ { sub(/^    # --- /, ""); sub(/ ---$/, ""); print }
    ' "$HOME_NIX")

    CAT=$(printf '%s\n' "$CATEGORIES" | $FZF --reverse --height=40% \
      --prompt="catégorie > " --header="Où ranger : ''${A_AJOUTER[*]}")
    [ -z "$CAT" ] && { echo "Annulé."; exit 0; }

    SAUVEGARDE=$(mktemp)
    cp "$HOME_NIX" "$SAUVEGARDE"

    # Insère chaque paquet sur sa ligne, juste sous l'en-tête de catégorie
    for p in "''${A_AJOUTER[@]}"; do
      ${pkgs.gawk}/bin/awk -v cat="    # --- $CAT ---" -v pkg="    $p" '
        { print }
        !fait && $0 == cat { print pkg; fait = 1 }
      ' "$HOME_NIX" > "$HOME_NIX.tmp" && cat "$HOME_NIX.tmp" > "$HOME_NIX" && rm -f "$HOME_NIX.tmp"
      echo "''${G}󰐕''${R} $p ajouté dans home.nix (''${B}$CAT''${R})"
    done

    echo "''${C}󰑓''${R} Rebuild en cours..."
    if sudo /run/current-system/sw/bin/nixos-rebuild switch --flake /etc/nixos#pc1; then
      rm -f "$SAUVEGARDE"
      echo "''${G}󰄬''${R} Installé : ''${A_AJOUTER[*]}"
      ${pkgs.libnotify}/bin/notify-send "Installation" "Installé : ''${A_AJOUTER[*]}"
    else
      cat "$SAUVEGARDE" > "$HOME_NIX"
      rm -f "$SAUVEGARDE"
      echo "''${Y}󰅚''${R} Rebuild échoué — home.nix restauré, rien n'a été installé." >&2
      exit 1
    fi
  '';

  # Commande `uninstall` : liste les paquets de home.packages (lignes simples et
  # blocs enveloppés type override/symlinkJoin ; scripts maison exclus) et les
  # applis web de modules/webapps/apps.json,
  # sélection fzf (filtre optionnel en argument), retire la ligne + son commentaire
  # juste au-dessus, puis rebuild. Rebuild raté → home.nix restauré.
  # `uninstall --app <id .desktop>` (clic droit du menu d'applications) : paquet
  # deviné depuis le .desktop, pas de liste fzf, juste la confirmation.
  nixuninstall = pkgs.writeShellScriptBin "uninstall" ''
    set -u
    APP_ID=""
    if [ "''${1:-}" = "--app" ]; then
      APP_ID="''${2:-}"
      set --
    fi
    HOME_NIX=/etc/nixos/home.nix
    SYS_NIX=/etc/nixos/configuration.nix
    FZF=${pkgs.fzf}/bin/fzf
    AWK=${pkgs.gawk}/bin/awk
    JQ=${pkgs.jq}/bin/jq
    WEB_DIR=/etc/nixos/modules/webapps
    WEB_JSON=$WEB_DIR/apps.json
    G=$'\e[32m'; C=$'\e[36m'; Y=$'\e[33m'; R=$'\e[0m'

    # Catégories dont les paquets servent au bureau (barre, captures, verrouillage…)
    SENSIBLES="|Lanceurs d'applications|Barre de statut et fond d'ecran|Capture d'ecran|Presse-papiers|Verrouillage|Emoji picker|Audio et luminosite|"

    # ligne (ou plage début-fin pour un bloc), attribut, marque, catégorie, commentaire
    LISTE=$($AWK -v sens="$SENSIBLES" '
      function emit(pos, nom, com,   cat, m) {
        cat = (c == "") ? "Autres" : c
        m = (index(sens, "|" c "|") || nom == "polkit_gnome") ? "⚠" : " "
        printf "%s\t%s\t%s\t%s\t%s\n", pos, nom, m, cat, com
      }
      # Paquet enveloppé : attribut en tête (pkgs.discord.override → discord), sinon
      # premier pkgs.X hors outils de construction (symlinkJoin rustdesk → rustdesk).
      # Scripts maison (writeShellScriptBin…) → "" = ignorés.
      function nom_bloc(texte,   t, x) {
        t = texte; sub(/^[[:space:]]*\(/, "", t); sub(/^pkgs\./, "", t)
        match(t, /^[A-Za-z_][A-Za-z0-9_-]*/); x = substr(t, 1, RLENGTH)
        if (x ~ /^write(Shell)?Script(Bin)?$/) return ""
        if (x !~ /^(symlinkJoin|buildEnv|runCommand)$/) return x
        t = texte
        while (match(t, /pkgs\.[A-Za-z_][A-Za-z0-9_-]*/)) {
          x = substr(t, RSTART + 5, RLENGTH - 5); t = substr(t, RSTART + RLENGTH)
          if (x !~ /^(symlinkJoin|buildEnv|runCommand|makeWrapper|lib|stdenv)$/) return x
        }
        return ""
      }
      /home\.packages = with pkgs; \[/ { p = 1; next }
      !p { next }
      # Dans un bloc multi-lignes : il se ferme sur la première ligne indentée de 4
      debut && /^    [^ ]/ {
        bloc = bloc "\n" $0; nom = nom_bloc(bloc)
        if (nom != "") emit(debut "-" NR, nom, "(bloc de " (NR - debut + 1) " lignes)")
        debut = 0; next
      }
      debut { bloc = bloc "\n" $0; next }
      /^  \];/ { exit }
      /^    # --- .* ---$/ { c = $0; sub(/^    # --- /, "", c); sub(/ ---$/, "", c) }
      /^    [A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*(#.*)?$/ {
        com = ""
        if (match($0, /#.*/)) com = substr($0, RSTART)
        emit(NR, $1, com)
      }
      # Expression entre parenthèses : sur une ligne si équilibrée, sinon début de bloc
      /^    \(/ {
        s = $0; o = gsub(/\(/, "(", s); f = gsub(/\)/, ")", s)
        if (o == f) { nom = nom_bloc($0); if (nom != "") emit(NR, nom, "(enveloppé)") }
        else { debut = NR; bloc = $0 }
      }
    ' "$HOME_NIX")

    # Applis web (modules/webapps.nix, commande `webapp`) : position = web:<id>
    LISTE+=$'\n'$($JQ -r '.[] | "web:\(.id)\t\(.id)\t \tApplis web\t\(.name) — \(.url)"' "$WEB_JSON")

    # Applis de base GNOME (Cartes, Calculatrice…) installées par services.desktopManager.gnome :
    # candidats = paquets exclusibles du module GNOME, gardés s'ils ont une appli visible
    # dans le menu ; position = gnome:<attribut>, retrait via environment.gnome.excludePackages
    GNOME_ATTRS=$($AWK '
      /removeExcluded \[|optionalPackages = \[/ { l = 1 }
      l || /notExcluded pkgs\./ {
        s = $0
        while (match(s, /pkgs\.[A-Za-z0-9_-]+/)) { print substr(s, RSTART + 5, RLENGTH - 5); s = substr(s, RSTART + RLENGTH) }
      }
      l && /\]/ { l = 0 }
    ' ${pkgs.path}/nixos/modules/services/desktop-managers/gnome.nix | sort -u)
    LISTE+=$'\n'$(for f in /run/current-system/sw/share/applications/*.desktop; do
      grep -q '^NoDisplay=true' "$f" && continue
      s=$(readlink -f "$f"); s=''${s#/nix/store/*-}; s=''${s%%/*}
      nom=$(sed -n 's/^Name\[fr\]=//p' "$f" | head -1)
      [ -z "$nom" ] && nom=$(sed -n 's/^Name=//p' "$f" | head -1)
      printf '%s\t%s\n' "$s" "$nom"
    done | $AWK -F'\t' -v attrs="$GNOME_ATTRS" '
      BEGIN { n = split(attrs, a, "\n") }
      # Dossier du store « gnome-maps-50.3 » ↔ attribut gnome-maps (ou tecla ↔ gnome-tecla)
      function va(s, x) { return s == x || (index(s, x "-") == 1 && substr(s, length(x) + 2, 1) ~ /[0-9]/) }
      {
        for (i = 1; i <= n; i++) {
          x = a[i]; y = x; sub(/^gnome-/, "", y)
          if (va($1, x) || va($1, y)) {
            if (!(x in noms)) ordre[++k] = x
            noms[x] = (x in noms) ? noms[x] ", " $2 : $2
            break
          }
        }
      }
      END {
        for (i = 1; i <= k; i++) {
          x = ordre[i]; m = (x == "nautilus") ? "⚠" : " "
          printf "gnome:%s\t%s\t%s\tApplis GNOME (de base)\t%s\n", x, x, m, noms[x]
        }
      }')

    # --app : retrouve la ligne de LISTE du paquet qui fournit le .desktop
    #   webapp-<id>       → web:<id>
    #   fichier du store  → dossier « discord-0.0.90 » ↔ attribut discord (ou kdePackages.kate ↔ kate)
    #   fichier local     → .desktop hors Nix (wine, appli maison) : simple suppression
    # Introuvable → liste fzf filtrée sur le nom de l'appli
    APP_CHOIX=""
    if [ -n "$APP_ID" ]; then
      FICHIER=""
      for d in "''${XDG_DATA_HOME:-$HOME/.local/share}" $(printf '%s' "''${XDG_DATA_DIRS:-}" | tr ':' ' '); do
        [ -e "$d/applications/$APP_ID.desktop" ] && { FICHIER="$d/applications/$APP_ID.desktop"; break; }
      done
      APP_NOM=$APP_ID
      if [ -n "$FICHIER" ]; then
        # Section principale seulement (pas les actions « Nouvelle fenêtre »…)
        n=$(sed -n '/^\[Desktop Entry\]/,/^\[/{s/^Name\[fr\]=//p}' "$FICHIER" | head -1)
        [ -z "$n" ] && n=$(sed -n '/^\[Desktop Entry\]/,/^\[/{s/^Name=//p}' "$FICHIER" | head -1)
        [ -n "$n" ] && APP_NOM=$n
      fi

      if [ -n "$FICHIER" ] && [[ "$(readlink -f "$FICHIER")" != /nix/store/* ]]; then
        echo "« $APP_NOM » ne vient pas de la config Nix : $FICHIER"
        read -r -p "Supprimer ce raccourci ? [o/N] " rep
        [[ "$rep" =~ ^[oOyY]$ ]] || { echo "Annulé."; exit 0; }
        rm -f "$FICHIER"
        echo "''${G}󰄬''${R} Raccourci supprimé : $APP_NOM"
        ${pkgs.libnotify}/bin/notify-send "Désinstallation" "Raccourci supprimé : $APP_NOM"
        exit 0
      fi

      if [[ "$APP_ID" == webapp-* ]]; then
        POS="web:''${APP_ID#webapp-}"
      else
        STORE=""
        if [ -n "$FICHIER" ]; then
          STORE=$(readlink -f "$FICHIER"); STORE=''${STORE#/nix/store/*-}; STORE=''${STORE%%/*}
        fi
        # « discord-0.0.90 », « prismlauncher-unwrapped-11.0.3 » ou « rustdesk » ↔ attribut ;
        # sinon id ou nom de l'appli = attribut (.desktop maison : Parabolic ↔ parabolic)
        POS=$(printf '%s\n' "$LISTE" | $AWK -F'\t' -v s="$STORE" -v id="$APP_ID" -v nom="$APP_NOM" '
          function va(s, x) { return s == x || (index(s, x "-") == 1 && substr(s, length(x) + 2, 1) ~ /[0-9]/) }
          BEGIN { sub(/-unwrapped/, "", s); id = tolower(id); nom = tolower(nom) }
          $1 ~ /^web:/ { next }
          {
            x = $2; sub(/.*\./, "", x); y = x; sub(/^gnome-/, "", y)
            if ((s != "" && (va(s, x) || va(s, y))) || id == tolower(x) || nom == tolower(x)) { print $1; exit }
          }')
      fi
      if [ -n "$POS" ]; then
        APP_CHOIX=$(printf '%s\n' "$LISTE" | $AWK -F'\t' -v p="$POS" '$1 == p' \
          | ${pkgs.util-linux}/bin/column -t -s $'\t' -o '  ')
      fi
      if [ -z "$APP_CHOIX" ]; then
        echo "''${Y}󰅚''${R} Paquet de « $APP_NOM » introuvable dans home.packages."
        # Piste : paquet système, ou activé par une option programs.X / services.X
        RACINE=''${STORE%%-[0-9]*}
        [ -n "$RACINE" ] && grep -n -F -- "$RACINE" "$SYS_NIX" "$HOME_NIX" | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | head -3 \
          | sed 's|^/etc/nixos/||; s/^/   déclaré ici ? /'
        echo "Choisis-le dans la liste si tu le vois, sinon Échap (à retirer à la main)."
        read -r -p "Entrée pour ouvrir la liste… " _ || exit 0
        set -- "$APP_NOM"
      fi
    fi

    # Sélection + confirmation ; « non » → retour à la liste, Échap → quitter
    while true; do
      if [ -n "$APP_CHOIX" ]; then
        CHOIX=$APP_CHOIX
        echo "Appli : $APP_NOM  →  paquet $(printf '%s\n' "$CHOIX" | $AWK '{print $2}')"
      else
        CHOIX=$(printf '%s\n' "$LISTE" \
          | ${pkgs.util-linux}/bin/column -t -s $'\t' -o '  ' \
          | $FZF --multi --reverse --height=80% --query="$*" \
              --with-nth=2.. --prompt="retirer > " \
              --header="TAB = sélection multiple · Entrée = valider · Échap = quitter · ⚠ = utilisé par le bureau" \
              --preview="case {1} in web:*) echo 'Appli web (brave --app)' ;; gnome:*) echo 'Appli GNOME de base (environment.gnome.excludePackages)' ;; *) nix eval --raw nixpkgs#{2}.meta.description 2>/dev/null ;; esac" \
              --preview-window=down,3,wrap)
        [ -z "$CHOIX" ] && { echo "Annulé."; exit 0; }
      fi

      LIGNES=$(printf '%s\n' "$CHOIX" | $AWK '{print $1}')
      NOMS=$(printf '%s\n' "$CHOIX" | $AWK '{print $2}' | tr '\n' ' ')

      if printf '%s\n' "$CHOIX" | grep -q "⚠"; then
        echo "''${Y}⚠''${R} Certains paquets choisis servent au bureau (Hyprland, barre, captures…)."
      fi
      read -r -p "Retirer : $NOMS? [o/N] " rep
      [[ "$rep" =~ ^[oOyY]$ ]] && break
      [ -n "$APP_CHOIX" ] && { echo "Annulé."; exit 0; }
    done

    SAUVEGARDE=$(mktemp)
    cp "$HOME_NIX" "$SAUVEGARDE"
    SYS_SAUVEGARDE=$(mktemp)
    cp "$SYS_NIX" "$SYS_SAUVEGARDE"
    WEB_SAUVEGARDE=$(mktemp -d)
    cp -a "$WEB_DIR/." "$WEB_SAUVEGARDE/"

    # Applis web : retirées de apps.json + icône supprimée
    for id in $(printf '%s\n' "$LIGNES" | sed -n 's/^web://p'); do
      rm -f "$WEB_DIR/icons/$($JQ -r --arg id "$id" '.[] | select(.id == $id) | .icon' "$WEB_JSON")"
      $JQ --arg id "$id" 'map(select(.id != $id))' "$WEB_JSON" > "$WEB_JSON.tmp" && mv "$WEB_JSON.tmp" "$WEB_JSON"
    done
    # Flake : suppressions à refléter dans l'index git
    git -C /etc/nixos add -A "$WEB_DIR"

    # Applis GNOME : ajoutées à environment.gnome.excludePackages (bloc créé au besoin
    # juste sous services.desktopManager.gnome.enable)
    EXCLUS=$(printf '%s\n' "$LIGNES" | sed -n 's/^gnome://p' | tr '\n' ' ')
    if [ -n "$EXCLUS" ]; then
      if ! grep -q '^  environment\.gnome\.excludePackages = with pkgs; \[$' "$SYS_NIX"; then
        $AWK '
          { print }
          /^  services\.desktopManager\.gnome\.enable = true;/ {
            print ""
            print "  # Applis GNOME de base retirées (commande `uninstall`)"
            print "  environment.gnome.excludePackages = with pkgs; ["
            print "  ];"
          }
        ' "$SYS_SAUVEGARDE" > "$SYS_NIX.tmp" && cat "$SYS_NIX.tmp" > "$SYS_NIX" && rm -f "$SYS_NIX.tmp"
      fi
      $AWK -v ajout="$EXCLUS" '
        BEGIN { n = split(ajout, a, " ") }
        /^  environment\.gnome\.excludePackages = with pkgs; \[$/ { dans = 1 }
        dans && /^  \];/ { for (i = 1; i <= n; i++) print "    " a[i]; dans = 0 }
        { print }
      ' "$SYS_NIX" > "$SYS_NIX.tmp" && cat "$SYS_NIX.tmp" > "$SYS_NIX" && rm -f "$SYS_NIX.tmp"
    fi

    # Supprime les lignes choisies + les lignes de commentaire collées juste au-dessus
    $AWK -v cibles="$(printf '%s\n' "$LIGNES" | grep '^[0-9]' | tr '\n' ',')" '
      BEGIN {
        n = split(cibles, t, ",")
        for (i = 1; i <= n; i++) if (t[i] != "") {
          if (split(t[i], r, "-") == 1) r[2] = r[1]
          for (k = r[1] + 0; k <= r[2] + 0; k++) del[k] = 1
        }
      }
      { l[NR] = $0 }
      END {
        for (i = NR; i >= 1; i--) if (i in del) {
          j = i - 1
          while (j >= 1 && l[j] ~ /^    # / && l[j] !~ /^    # (---|===)/) { del[j] = 1; j-- }
        }
        for (i = 1; i <= NR; i++) if (!(i in del)) print l[i]
      }
    ' "$SAUVEGARDE" > "$HOME_NIX.tmp" && cat "$HOME_NIX.tmp" > "$HOME_NIX" && rm -f "$HOME_NIX.tmp"

    echo "''${C}󰑓''${R} Rebuild en cours..."
    if sudo /run/current-system/sw/bin/nixos-rebuild switch --flake /etc/nixos#pc1; then
      rm -rf "$SAUVEGARDE" "$SYS_SAUVEGARDE" "$WEB_SAUVEGARDE"
      echo "''${G}󰄬''${R} Désinstallé : $NOMS"
      ${pkgs.libnotify}/bin/notify-send "Désinstallation" "Retiré : $NOMS"
    else
      cat "$SAUVEGARDE" > "$HOME_NIX"
      cat "$SYS_SAUVEGARDE" > "$SYS_NIX"
      rm -rf "$WEB_DIR"; mkdir -p "$WEB_DIR"; cp -a "$WEB_SAUVEGARDE/." "$WEB_DIR/"
      git -C /etc/nixos add -A "$WEB_DIR"
      rm -rf "$SAUVEGARDE" "$SYS_SAUVEGARDE" "$WEB_SAUVEGARDE"
      echo "''${Y}󰅚''${R} Rebuild échoué — home.nix, configuration.nix et applis web restaurés, rien n'a été retiré." >&2
      exit 1
    fi
  '';
in
{
  home.packages = [ nixinstall nixuninstall ];

  # `install` dans le shell interactif seulement (les scripts/Makefile gardent
  # coreutils). Option (-m, -d…) ou fichier existant en 1er argument → coreutils.
  programs.bash.initExtra = ''
    install() {
      if [ $# -eq 0 ] || [[ "$1" == -* ]] || [ -e "$1" ]; then
        command install "$@"
      else
        nixinstall "$@"
      fi
    }
  '';
}
