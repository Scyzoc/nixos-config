{ config, pkgs, ... }:

let
  # Génère la liste des applications (.desktop) au format dmenu de wofi,
  # avec résolution des icônes pour garder l'affichage de --show drun.
  gen-app-list = pkgs.writers.writePython3Bin "app-launcher-gen" { flakeIgnore = [ "E501" "E302" "E305" ]; } ''
    import os
    import configparser

    SEP = "\x1f"

    data_dirs = os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share"
    ).split(":")
    data_home = os.environ.get(
        "XDG_DATA_HOME", os.path.expanduser("~/.local/share")
    )
    dirs = [data_home] + data_dirs

    # 1. Lecture des .desktop (rapide) pour connaître les icônes réellement utiles
    seen = set()
    raw = []
    wanted = set()
    for d in dirs:
        appdir = os.path.join(d, "applications")
        for root, _, files in os.walk(appdir, followlinks=True):
            for f in files:
                if not f.endswith(".desktop"):
                    continue
                rel = os.path.relpath(os.path.join(root, f), appdir)
                if rel in seen:
                    continue
                seen.add(rel)
                cp = configparser.RawConfigParser(interpolation=None, strict=False)
                try:
                    cp.read(os.path.join(root, f), encoding="utf-8")
                    e = cp["Desktop Entry"]
                except Exception:
                    continue
                if e.get("Type") != "Application":
                    continue
                if e.get("NoDisplay", "false").lower() == "true":
                    continue
                if e.get("Hidden", "false").lower() == "true":
                    continue
                name = e.get("Name")
                exe = e.get("Exec")
                if not name or not exe:
                    continue
                for token in ("%f", "%F", "%u", "%U", "%i", "%c", "%k"):
                    exe = exe.replace(token, "")
                exe = " ".join(exe.split())
                term = e.get("Terminal", "false").lower() == "true"
                icon = e.get("Icon") or ""
                if icon and not os.path.isabs(icon):
                    wanted.add(icon)
                raw.append((name, exe, term, icon))

    # 2. Index des icônes, thème par thème dans l'ordre de priorité, en s'arrêtant
    # dès que toutes les icônes voulues sont résolues (évite de parcourir Papirus
    # et consorts : ~1M de fichiers).
    PRIORITY = ["hicolor", "Adwaita", "Papirus-Dark", "Papirus", "breeze"]
    icon_index = {}

    def scan(base):
        for root, subdirs, files in os.walk(base, followlinks=True):
            subdirs[:] = [s for s in subdirs if s != "cursors"]
            score = 0
            if "scalable" in root:
                score = 100
            else:
                for part in root.split(os.sep):
                    if "x" in part and part.split("x")[0].isdigit():
                        try:
                            score = 100 - abs(int(part.split("x")[0]) - 48)
                        except ValueError:
                            pass
            for f in files:
                name, ext = os.path.splitext(f)
                if ext not in (".png", ".svg", ".xpm"):
                    continue
                if name not in wanted:
                    continue
                prev = icon_index.get(name)
                if prev is None or prev[0] < score:
                    icon_index[name] = (score, os.path.join(root, f))

    def theme_dirs():
        for d in dirs:
            yield os.path.join(d, "pixmaps")
        for theme in PRIORITY:
            for d in dirs:
                yield os.path.join(d, "icons", theme)
        for d in dirs:
            base = os.path.join(d, "icons")
            try:
                entries = sorted(os.listdir(base))
            except OSError:
                continue
            for theme in entries:
                if theme in PRIORITY:
                    continue
                yield os.path.join(base, theme)

    for base in theme_dirs():
        if len(icon_index) >= len(wanted):
            break
        if os.path.isdir(base):
            scan(base)

    def find_icon(icon):
        if not icon:
            return None
        if os.path.isabs(icon):
            return icon if os.path.exists(icon) else None
        hit = icon_index.get(icon)
        return hit[1] if hit else None

    entries = []
    for name, exe, term, icon in raw:
        path = find_icon(icon)
        label = f"img:{path}:text:{name}" if path else name
        entries.append((name.lower(), label, exe, term))

    entries.sort()
    for _, label, exe, term in entries:
        print(f"{label}{SEP}{exe}{SEP}{'1' if term else '0'}")
  '';

  # Même config que wofi-config mais sans "show=drun" (incompatible avec --dmenu)
  dmenu-config = pkgs.runCommand "wofi-config-dmenu" { } ''
    grep -v '^show=' ${./wofi-config} > $out
  '';

  # Prompt de recherche Brave (lancé depuis l'entrée .desktop du launcher)
  brave-search = pkgs.writeShellScriptBin "brave-search" ''
    QUERY=$(: | ${pkgs.wofi}/bin/wofi --dmenu --style ${./wofi-style.css} --conf ${dmenu-config} \
      --prompt "Rechercher sur Brave...")
    [ -z "$QUERY" ] && exit 0
    exec ${pkgs.brave}/bin/brave "https://search.brave.com/search?q=$(${pkgs.jq}/bin/jq -rn --arg q "$QUERY" '$q|@uri')"
  '';

  # Ancien menu (wofi), gardé en secours si le menu Quickshell ne répond pas
  app-launcher-wofi = pkgs.writeShellScriptBin "app-launcher-wofi" ''
    export PATH=${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.findutils}/bin:$PATH
    PIDFILE="/tmp/wofi-launcher.pid"
    SEP=$'\x1f'

    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        rm -f "$PIDFILE"
        exit 0
      fi
      rm -f "$PIDFILE"
    fi

    CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/app-launcher-entries"
    mkdir -p "$(dirname "$CACHE")"

    NEWEST=$(find "''${XDG_DATA_HOME:-$HOME/.local/share}/applications" \
      "/etc/profiles/per-user/$USER/share/applications" \
      /run/current-system/sw/share/applications \
      -maxdepth 0 -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
    STALE=0
    if [ -z "$NEWEST" ] || \
       [ "$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)" -lt "''${NEWEST%%.*}" ]; then
      STALE=1
    fi

    if [ ! -s "$CACHE" ]; then
      # Premier lancement : on doit générer avant d'afficher
      ${gen-app-list}/bin/app-launcher-gen > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
    elif [ "$STALE" = "1" ]; then
      # Cache périmé (rebuild récent) : on affiche l'ancien tout de suite
      # et on régénère en arrière-plan pour le prochain lancement.
      setsid sh -c '${gen-app-list}/bin/app-launcher-gen > "'"$CACHE"'.tmp" \
        && mv "'"$CACHE"'.tmp" "'"$CACHE"'"' >/dev/null 2>&1 &
    fi

    OUT=$(mktemp)
    trap 'rm -f "$OUT"' EXIT

    cut -d"$SEP" -f1 "$CACHE" \
      | ${pkgs.wofi}/bin/wofi --dmenu --style ${./wofi-style.css} --conf ${dmenu-config} \
          --prompt "Rechercher..." --allow-images --parse-search \
          -D key_custom_0=Ctrl-b > "$OUT" &
    WOFI_PID=$!
    echo $WOFI_PID > "$PIDFILE"
    wait $WOFI_PID
    RC=$?
    rm -f "$PIDFILE"

    CHOICE=$(cat "$OUT")
    [ -z "$CHOICE" ] && exit 0

    brave_search() {
      # Retire l'échappement d'image éventuel (img:<path>:text:<nom>)
      set -- "$(printf '%s' "$1" | sed 's/^img:.*:text://')"
      exec ${pkgs.brave}/bin/brave "https://search.brave.com/search?q=$(${pkgs.jq}/bin/jq -rn --arg q "$1" '$q|@uri')"
    }

    # Ctrl+B : recherche Brave immédiate sur le texte tapé, même s'il matche une app
    if [ "$RC" = "20" ]; then
      brave_search "$CHOICE"
    fi


    LINE=$(grep -F -m1 -- "$CHOICE$SEP" "$CACHE" || true)
    # Aucune app ne correspond : recherche Brave directe sur le texte tapé
    [ -z "$LINE" ] && brave_search "$CHOICE"

    EXE=$(printf '%s' "$LINE" | cut -d"$SEP" -f2)
    TERM_FLAG=$(printf '%s' "$LINE" | cut -d"$SEP" -f3)

    if [ "$TERM_FLAG" = "1" ]; then
      setsid ${pkgs.kitty}/bin/kitty -e sh -c "$EXE" >/dev/null 2>&1 &
    else
      setsid sh -c "$EXE" >/dev/null 2>&1 &
    fi
    exit 0
  '';

  quickshell = config.programs.quickshell.package;
  launcherState = "${config.xdg.stateHome}/quickshell-launcher";

  # Chemins absolus utilisés par les menus Quickshell (PATH non garanti sous systemd).
  # userBin : scripts du profil (wallpaper-index / wallpaper-apply, wallpaper-picker.nix)
  launcher-paths = pkgs.writeText "Paths.qml" ''
    pragma Singleton
    import Quickshell

    Singleton {
        readonly property string kitty: "${pkgs.kitty}/bin/kitty"
        readonly property string brave: "${pkgs.brave}/bin/brave"
        readonly property string userBin: "${config.home.profileDirectory}/bin"
        readonly property string stateDir: "${launcherState}"
        readonly property string usageFile: "${launcherState}/usage.json"
        readonly property string emojiDir: "${config.xdg.dataHome}/emoji-picker"
        readonly property string emojiState: "${launcherState}/emoji.json"
    }
  '';

  # Config QML des menus (modules/quickshell-launcher/ : applications + fonds d'écran)
  # + thème partagé avec la barre
  launcherConfig = pkgs.runCommand "quickshell-launcher" { } ''
    mkdir $out
    cp ${./quickshell}/Theme.qml ${./quickshell}/BarText.qml ${./quickshell}/ClickFx.qml $out/
    cp ${./quickshell-launcher}/*.qml $out/
    cp ${launcher-paths} $out/Paths.qml
  '';

  # SUPER+R : affiche / masque le menu Quickshell (déjà chargé par son service)
  app-launcher = pkgs.writeShellScriptBin "app-launcher" ''
    ${quickshell}/bin/quickshell ipc -c launcher call launcher toggle >/dev/null 2>&1 \
      || exec ${app-launcher-wofi}/bin/app-launcher-wofi
  '';

in
{
  home.packages = [ app-launcher app-launcher-wofi brave-search ];

  # Menus plein écran (applications, fonds d'écran) : config Quickshell à part, service
  # à part (un bug d'un menu ne fait pas tomber la barre)
  programs.quickshell.configs.launcher = launcherConfig;

  systemd.user.services.quickshell-launcher = {
    Unit = {
      Description = "Menus d'applications et de fonds d'écran (Quickshell)";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
      X-Restart-Triggers = [ "${launcherConfig}" ];
    };
    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${launcherState}";
      ExecStart = "${quickshell}/bin/quickshell --config launcher";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  xdg.desktopEntries.brave-search = {
    name = "Rechercher sur Brave";
    comment = "Lancer une recherche web dans Brave";
    exec = "brave-search";
    icon = "brave-browser";
    terminal = false;
    type = "Application";
    categories = [ "Network" ];
  };
}
