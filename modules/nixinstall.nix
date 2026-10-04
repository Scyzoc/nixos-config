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

  # Commande `uninstall` : liste les paquets simples (une ligne) de home.packages,
  # sélection fzf (filtre optionnel en argument), retire la ligne + son commentaire
  # juste au-dessus, puis rebuild. Rebuild raté → home.nix restauré.
  nixuninstall = pkgs.writeShellScriptBin "uninstall" ''
    set -u
    HOME_NIX=/etc/nixos/home.nix
    FZF=${pkgs.fzf}/bin/fzf
    AWK=${pkgs.gawk}/bin/awk
    G=$'\e[32m'; C=$'\e[36m'; Y=$'\e[33m'; R=$'\e[0m'

    # Catégories dont les paquets servent au bureau (barre, captures, verrouillage…)
    SENSIBLES="|Lanceurs d'applications|Barre de statut et fond d'ecran|Capture d'ecran|Presse-papiers|Verrouillage|Emoji picker|Audio et luminosite|"

    # numéro de ligne, attribut, marque, catégorie, commentaire en fin de ligne
    LISTE=$($AWK -v sens="$SENSIBLES" '
      /home\.packages = with pkgs; \[/ { p = 1; next }
      p && /^  \];/ { exit }
      p && /^    # --- .* ---$/ { c = $0; sub(/^    # --- /, "", c); sub(/ ---$/, "", c) }
      p && /^    [A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*(#.*)?$/ {
        com = ""
        if (match($0, /#.*/)) com = substr($0, RSTART)
        cat = (c == "") ? "Autres" : c
        m = (index(sens, "|" c "|") || $1 == "polkit_gnome") ? "⚠" : " "
        printf "%d\t%s\t%s\t%s\t%s\n", NR, $1, m, cat, com
      }
    ' "$HOME_NIX")

    # Sélection + confirmation ; « non » → retour à la liste, Échap → quitter
    while true; do
      CHOIX=$(printf '%s\n' "$LISTE" \
        | ${pkgs.util-linux}/bin/column -t -s $'\t' -o '  ' \
        | $FZF --multi --reverse --height=80% --query="$*" \
            --with-nth=2.. --prompt="retirer > " \
            --header="TAB = sélection multiple · Entrée = valider · Échap = quitter · ⚠ = utilisé par le bureau" \
            --preview="nix eval --raw nixpkgs#{2}.meta.description 2>/dev/null" \
            --preview-window=down,3,wrap)
      [ -z "$CHOIX" ] && { echo "Annulé."; exit 0; }

      LIGNES=$(printf '%s\n' "$CHOIX" | $AWK '{print $1}')
      NOMS=$(printf '%s\n' "$CHOIX" | $AWK '{print $2}' | tr '\n' ' ')

      if printf '%s\n' "$CHOIX" | grep -q "⚠"; then
        echo "''${Y}⚠''${R} Certains paquets choisis servent au bureau (Hyprland, barre, captures…)."
      fi
      read -r -p "Retirer : $NOMS? [o/N] " rep
      [[ "$rep" =~ ^[oOyY]$ ]] && break
    done

    SAUVEGARDE=$(mktemp)
    cp "$HOME_NIX" "$SAUVEGARDE"

    # Supprime les lignes choisies + les lignes de commentaire collées juste au-dessus
    $AWK -v cibles="$(printf '%s\n' "$LIGNES" | tr '\n' ',')" '
      BEGIN { n = split(cibles, t, ","); for (i = 1; i <= n; i++) if (t[i] != "") del[t[i]] = 1 }
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
      rm -f "$SAUVEGARDE"
      echo "''${G}󰄬''${R} Désinstallé : $NOMS"
      ${pkgs.libnotify}/bin/notify-send "Désinstallation" "Retiré : $NOMS"
    else
      cat "$SAUVEGARDE" > "$HOME_NIX"
      rm -f "$SAUVEGARDE"
      echo "''${Y}󰅚''${R} Rebuild échoué — home.nix restauré, rien n'a été retiré." >&2
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
