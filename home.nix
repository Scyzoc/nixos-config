{ config, pkgs, lib, ... }:
let
  notionTodo = ./modules/notion-todo.nix;
  tesseractFra = pkgs.tesseract.override { enableLanguages = [ "fra" "eng" ]; };

  # hyprlock-safe : relance hyprlock s'il plante. Le verrou Wayland reste posé
  # quand hyprlock meurt (Hyprland affiche alors l'écran rouge « lockscreen app
  # died » et rien ne débloque la session). Avec misc.allow_session_lock_restore
  # (modules/hyprland.nix), un nouveau hyprlock reprend le verrou. Cas réel :
  # réveil après retrait du dock → sortie FALLBACK détruite sous hyprlock 0.9.6
  # → « Disconnected from pollfd id 0 » → SIGABRT.
  # Sortie 0 = déverrouillage normal ; tout autre code = plantage → relance.
  hyprlockSafe = pkgs.writeShellScriptBin "hyprlock-safe" ''
    # Une seule instance : un 2e appel (hypridle pendant une relance) sort.
    exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/hyprlock-safe.lock"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0

    fails=0
    while :; do
      start=$(date +%s)
      # Mode bureau (écran externe seul) : batterie masquée → champ mot de passe
      # remonté juste sous la date (config dérivée, position -120 → -75).
      cfg="$HOME/.config/hypr/hyprlock.conf"
      args=("$@")
      case $(cat "$HOME/.local/state/display-mode" 2>/dev/null) in
        lid-closed|external-only)
          alt="''${XDG_RUNTIME_DIR:-/tmp}/hyprlock-desktop.conf"
          if ${pkgs.gnused}/bin/sed 's/^\(\s*position\s*=\s*0,\s*\)-120\s*$/\1-75/' "$cfg" > "$alt" 2>/dev/null; then
            args=(-c "$alt" "$@")
          fi
          ;;
      esac
      ${pkgs.hyprlock}/bin/hyprlock "''${args[@]}" 9>&- && exit 0
      rc=$?
      # Compteur remis à zéro si hyprlock a tenu un moment (plantage isolé)
      [ $(( $(date +%s) - start )) -gt 30 ] && fails=0
      fails=$(( fails + 1 ))
      echo "hyprlock-safe: hyprlock sorti avec $rc, relance n°$fails" >&2
      if [ "$fails" -ge 15 ]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Verrouillage" \
          "hyprlock plante en boucle ($rc) — SUPER+L ou TTY pour relancer"
        exit "$rc"
      fi
      # Filet si l'option a été perdue (reload partiel de la config)
      ${pkgs.hyprland}/bin/hyprctl eval \
        'hl.config({ misc = { allow_session_lock_restore = true } })' >/dev/null 2>&1
      sleep 1
    done
  '';
in

{
  # ==========================================================================
  # 1. INFORMATIONS UTILISATEUR
  # ==========================================================================
  home.username = "user";
  home.homeDirectory = "/home/user";
  home.stateVersion = "23.11";

  home.pointerCursor = lib.mkForce {
    gtk.enable = true;
    x11.enable = true;
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
  };

  imports = lib.optional (builtins.pathExists notionTodo) notionTodo ++ [
    ./modules/hyprland.nix
    ./modules/quickshell.nix
    ./modules/cours.nix
    ./modules/emoji.nix
    ./modules/voice-transcription.nix
    ./modules/screen-record.nix
    ./modules/assistant.nix
    ./modules/atlas-task.nix
    ./modules/atlas-workspace.nix
    ./modules/app-launcher.nix
    ./modules/wallpaper-picker.nix
    ./modules/workspace-cycle.nix
    ./modules/workspace-compact.nix
    ./modules/special-zoom.nix
    ./modules/clipboard.nix
    ./modules/airpods-monitor.nix
    ./modules/airpods-ear.nix
    ./modules/media-tap.nix
    ./modules/power-saving.nix
    ./modules/theme-automation.nix
    ./modules/internet-check.nix
    ./modules/netfix.nix
    ./modules/display-switch.nix
    ./modules/workspace-link.nix
    ./modules/crepuscule.nix
    ./modules/update-check.nix
    ./modules/nixfix.nix
    ./modules/archive-extract.nix
    ./modules/ipinfo.nix
    ./modules/driver-update.nix
    ./modules/cli-list.nix
    ./modules/nixinstall.nix
    ./modules/webapps.nix
    ./modules/binds.nix
    ./modules/espace.nix
  ];

  # ==========================================================================
  # VARIABLES D'ENVIRONNEMENT
  # ==========================================================================

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    PATH = "/etc/profiles/per-user/user/bin:$HOME/.npm-global/bin:$PATH";
    AQ_NO_ATOMIC = "1";
  };

  # ==========================================================================
  # 2. CONFIGURATION SSH
  # ==========================================================================
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*" = {
        AddKeysToAgent = "no";
        Compression = "no";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
        ForwardAgent = "no";
        HashKnownHosts = "no";
        ServerAliveCountMax = 3;
        ServerAliveInterval = 0;
        UserKnownHostsFile = "~/.ssh/known_hosts";
      };
      "vps" = {
        HostName = "VPS_IP_REDACTED";
        User = "user";
      };
      "pc" = {
        HostName = "HOMELAB_IP_REDACTED";
        User = "user";
      };
      "homelab" = {
        HostName = "HOMELAB_IP_REDACTED";
        User = "homelab";
        # Forward X11 : xclip côté serveur lit le presse-papiers local
        # (coller des images dans Claude Code avec Ctrl+V)
        ForwardX11 = true;
        ForwardX11Trusted = true;
      };
      "192.168.99.*" = {
        KexAlgorithms = "+diffie-hellman-group1-sha1";
        HostKeyAlgorithms = "+ssh-rsa";
        Ciphers = "+aes256-cbc";
      };
    };
  };

  # ==========================================================================
  # 3. CONFIGURATION ROFI (THEMES)
  # ==========================================================================



  # ==========================================================================
  # 3. SCRIPTS PERSONNALISES
  # ==========================================================================
  home.packages = with pkgs; [
    # Icônes stock GTK legacy (gtk-cut, gtk-copy...) : sans elles la barre
    # d'outils de VMware Workstation s'affiche vide
    adwaita-icon-theme-legacy

    # Simulateur réseau Cisco (9.0.1, via overlays/cisco-packet-tracer-901.nix)
    cisco-packet-tracer_9

    (writeShellScriptBin "homelab" ''
      # Connexion SSH au homelab, en montant le VPN maison si besoin
      if ! ${netcat-gnu}/bin/nc -z -w2 HOMELAB_IP_REDACTED 22 2>/dev/null; then
        echo "󰖂 Connexion au VPN maison..."
        sudo /run/current-system/sw/bin/systemctl start openvpn-maison || {
          echo "󰅚 Impossible de démarrer le VPN"; exit 1;
        }
        for i in $(seq 1 30); do
          ${netcat-gnu}/bin/nc -z -w2 HOMELAB_IP_REDACTED 22 2>/dev/null && break
          sleep 1
        done
        if ! ${netcat-gnu}/bin/nc -z -w2 HOMELAB_IP_REDACTED 22 2>/dev/null; then
          echo "󰅚 VPN monté mais homelab injoignable (HOMELAB_IP_REDACTED:22)"
          exit 1
        fi
        echo "󰄬 VPN connecté"
      fi
      exec ssh homelab "$@"
    '')
    (writeShellScriptBin "wakepc" ''
      if ${netcat-gnu}/bin/nc -z -w2 HOMELAB_IP_REDACTED 22 2>/dev/null; then
        ssh homelab@HOMELAB_IP_REDACTED wakeonlan AA:BB:CC:DD:EE:FF
      else
        ${libnotify}/bin/notify-send -u critical 'Wake-on-LAN' 'Homelab injoignable — VPN pas activé ?'
      fi
    '')
    (writeShellScriptBin "pcoff" ''
      if ${netcat-gnu}/bin/nc -z -w2 HOMELAB_IP_REDACTED 22 2>/dev/null; then
        ssh pc 'shutdown /s /t 0'
      else
        ${libnotify}/bin/notify-send -u critical 'Extinction' 'PC injoignable — allumé ? VPN activé ?'
      fi
    '')
    onlyoffice-desktopeditors
    github-cli
    dnsutils
    (python3.withPackages (ps: [ ps.requests ]))
    signal-desktop
    telegram-desktop
    parabolic
    stirling-pdf-desktop
    lmstudio
    # Electron 43 : fenêtre noire (webFrame cassé) → épinglé sur 42
    (obsidian.override { electron = electron_42; })




    # --- audio-switch ---
    (pkgs.writeShellScriptBin "audio-switch" ''
      SINKS=$(wpctl status | grep -A 10 "Sinks" | grep -oP '\d+(?=\.)' | head -n 2)
      CURRENT=$(wpctl status | grep "*" | grep -oP '\d+(?=\.)' | head -n 1)
      NEXT=$(echo "$SINKS" | grep -v "$CURRENT" | head -n 1)
      if [ -n "$NEXT" ]; then
          wpctl set-default "$NEXT"
      fi
    '')

    # ==========================================================================
    # 4. APPLICATIONS ET OUTILS
    # ==========================================================================

    # --- Navigateurs et communication ---
    ffmpegthumbnailer
    brave
    google-chrome
    (pkgs.discord.override { withOpenASAR = true; })
    remmina
    localsend

    # --- Diagrammes ---
    drawio

    # --- Éditeurs ---

    # --- Musique et divertissement ---
    spotify
    prismlauncher
    vlc
    stremio-linux-shell
    # Recopie écran iPhone (AirPlay) : commande `airplay` (ports fixés pour le pare-feu)
    (writeShellScriptBin "airplay" ''exec ${uxplay}/bin/uxplay -n PC_du_I -nh -p "$@"'')

    # --- Developpement ---
    cryptsetup
    nodejs
    pnpm
    vscode
    opencode
    claude-code
    openssl


    # --- Utilitaires systeme ---
    rsync
    nmap
    (pkgs.writeShellScriptBin "nixsave" ''
      TARGET="/etc/nixos/Sauvegarde"
      echo "📦 Sauvegarde de la configuration NixOS vers $TARGET..."
      sudo mkdir -p "$TARGET"
      sudo rsync -av --exclude="Sauvegarde" /etc/nixos/ "$TARGET/"
      echo "✅ Sauvegarde terminée !"
    '')
    polkit_gnome
    cmatrix
    tree
    htop
    btop
    gdu
    baobab
    lazydocker
    nwg-displays
    unrar
    fsearch            # Recherche de fichiers instantanee (equivalent Everything)
    trash-cli          # Corbeille en CLI (trash-put, trash-list, trash-restore, trash-empty)

    # --- Fond d'ecran ---
    awww
    imagemagick

    # --- Capture d'ecran ---
    grim
    slurp
    wayfreeze
    swappy

    # --- Presse-papiers ---
    cliphist
    wl-clipboard

    # --- Verrouillage ---
    hyprlock
    hyprlockSafe
    hypridle

    # --- Emoji picker ---
    wtype

    # --- Audio et luminosite ---
    playerctl
    brightnessctl
    pwvucontrol

    # --- Divers ---
    screen
    xhost
    wlogout
    _1password-cli

    # --- wlogout config ---
    (pkgs.writeShellScriptBin "portail" ''
      # Ouvre la page de détection de portail captif dans Brave
      exec brave http://detectportal.brave-http-only.com/
    '')

    (pkgs.writeShellScriptBin "power-menu" ''
      pkill wlogout || wlogout
    '')

    (pkgs.writeShellScriptBin "console" ''
      port=$(ls /dev/ttyUSB* 2>/dev/null | head -1)
      if [ -z "$port" ]; then
        echo "Aucun port /dev/ttyUSB* détecté."
        exit 1
      fi
      echo "Connexion sur $port..."
      sudo screen "$port"
    '')

    (pkgs.writeShellScriptBin "veille" ''
      delai="''${1:-3}"
      if ! [[ "$delai" =~ ^[0-9]+$ ]]; then
        echo "Usage : veille [secondes]" >&2
        exit 1
      fi
      echo "Mise en veille dans $delai secondes (Ctrl+C pour annuler)"
      sleep "$delai"
      systemctl suspend
    '')

    # Capture : gèle l'écran (curseur figé inclus), puis sélection de zone
    (pkgs.writeShellScriptBin "screenshot" ''
      mode="''${1:-copy}"

      # Clic sur l'île « Capture … » de la barre (ScreenState.open) : ouvre l'éditeur
      if [ "$1" = "--edit" ]; then
        exec ${pkgs.swappy}/bin/swappy -f "$2"
      fi

      # Actions du menu déroulant de l'île : copier / enregistrer sous (le fichier est déplacé)
      if [ "$1" = "--copy" ]; then
        ${pkgs.wl-clipboard}/bin/wl-copy < "$2"
        exit 0
      fi
      # OCR : extrait le texte de la capture, le copie dans le presse-papiers
      if [ "$1" = "--ocr" ]; then
        txt=$(${tesseractFra}/bin/tesseract "$2" - -l fra+eng 2>/dev/null)
        if [ -n "$(echo "$txt" | ${pkgs.coreutils}/bin/tr -d '[:space:]')" ]; then
          printf '%s' "$txt" | ${pkgs.wl-clipboard}/bin/wl-copy
          ${pkgs.libnotify}/bin/notify-send -a screenshot -i edit-copy "Texte extrait" "Copié dans le presse-papiers"
        else
          ${pkgs.libnotify}/bin/notify-send -a screenshot -i dialog-warning "Aucun texte détecté" "La capture ne contient pas de texte"
        fi
        exit 0
      fi
      if [ "$1" = "--save-as" ]; then
        file="$2"
        dir="$HOME/Pictures/Screenshots"
        ${pkgs.coreutils}/bin/mkdir -p "$dir"
        dest=$(${pkgs.zenity}/bin/zenity --file-selection --save --confirm-overwrite \
          --title="Enregistrer la capture" \
          --file-filter="Images PNG | *.png" \
          --filename="$dir/screenshot_$(${pkgs.coreutils}/bin/date +%Y%m%d_%H%M%S).png") || exit 0
        [ -z "$dest" ] && exit 0
        case "$dest" in *.png|*.PNG) ;; *) dest="$dest.png" ;; esac
        ${pkgs.coreutils}/bin/cp -f "$file" "$dest"
        exit 0
      fi

      if [ "$1" = "--internal-finish" ]; then
        mode="$2"
        file="$3"
        # Écran déjà gelé (menu inclus dans l'image) : les vrais menus de la barre sont fermés,
        # sinon ils se superposent à la copie gelée (deux menus sur la capture)
        if ${pkgs.quickshell}/bin/quickshell ipc -c bar call popup close >/dev/null 2>&1; then
          ${pkgs.coreutils}/bin/sleep 0.15
        fi
        geom=$(${pkgs.slurp}/bin/slurp)
        ${pkgs.procps}/bin/pkill wayfreeze
        if [ -n "$geom" ]; then
          # Le screen_shader de Crépuscule (filtre lumière bleue) est inclus dans la
          # capture : coupé le temps de grim (~150 ms), puis remis.
          shader=$(${pkgs.hyprland}/bin/hyprctl getoption decoration:screen_shader | ${pkgs.gnused}/bin/sed -n 's/^str: //p')
          case "$shader" in ""|"[[EMPTY]]") shader="" ;; esac
          [ -n "$shader" ] && ${pkgs.hyprland}/bin/hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })' >/dev/null
          ${pkgs.grim}/bin/grim -g "$geom" "$file"
          [ -n "$shader" ] && ${pkgs.hyprland}/bin/hyprctl eval "hl.config({ decoration = { screen_shader = \"$shader\" } })" >/dev/null
          if [ "$mode" = "save" ]; then
            # Demande l'emplacement ; défaut ~/Pictures/Screenshots/
            dir="$HOME/Pictures/Screenshots"
            ${pkgs.coreutils}/bin/mkdir -p "$dir"
            dest=$(${pkgs.zenity}/bin/zenity --file-selection --save --confirm-overwrite \
              --title="Enregistrer la capture" \
              --file-filter="Images PNG | *.png" \
              --filename="$dir/screenshot_$(${pkgs.coreutils}/bin/date +%Y%m%d_%H%M%S).png")
            if [ -z "$dest" ]; then
              ${pkgs.coreutils}/bin/rm -f "$file"
              exit 0
            fi
            case "$dest" in *.png|*.PNG) ;; *) dest="$dest.png" ;; esac
            ${pkgs.coreutils}/bin/mv -f "$file" "$dest"
            file="$dest"
            msg="Sauvegardé : $(${pkgs.coreutils}/bin/basename "$file")"
          else
            ${pkgs.wl-clipboard}/bin/wl-copy < "$file"
            msg="Zone copiée dans le presse-papiers"
          fi
          # Annonce par l'île de la barre (ScreenState.qml lit ce fichier, « copy|save <fichier> »)
          echo "$mode $file" > /tmp/screenshot.state
          ( ${pkgs.coreutils}/bin/sleep 2.5; ${pkgs.coreutils}/bin/rm -f /tmp/screenshot.state ) >/dev/null 2>&1 &
        fi
        exit 0
      fi

      # Toggle : annule une capture déjà en cours
      ${pkgs.procps}/bin/pkill slurp 2>/dev/null && exit 0
      ${pkgs.procps}/bin/pkill wayfreeze 2>/dev/null && exit 0

      file="$(${pkgs.coreutils}/bin/mktemp --suffix=.png)"

      # --inverse-transform : sans lui l'overlay gelé s'affiche retourné sur
      # les moniteurs pivotés (MSI en transform 3).
      ${pkgs.wayfreeze}/bin/wayfreeze --inverse-transform \
        --after-freeze-cmd "screenshot --internal-finish $mode $file"
    '')

    (pkgs.writeShellScriptBin "discord-launcher" ''
      MSI_DESC="Microstep MSI MAG241C 0x00000010"
      MSI_CONNECTED=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
        ${pkgs.jq}/bin/jq -r '.[] | select(.description == "'"$MSI_DESC"'") | .name')
      if [ -n "$MSI_CONNECTED" ]; then
        ${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.exec_cmd("discord", { workspace = "11" })' 
      else
        discord
      fi
    '')
  ];

  # Requis : sans ça home-manager n'écrit aucun xdg.desktopEntries
  xdg.enable = true;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "thunar.desktop";
      "x-scheme-handler/mailto" = "gmail-mailto.desktop";
    };
  };
  # Défauts Nix gardés dans ~/.local/share/applications/mimeapps.list (fallback
  # lu par GIO). ~/.config/mimeapps.list reste un vrai fichier modifiable, sinon
  # "Définir l'application par défaut" de Thunar échoue (symlink /nix/store).
  xdg.configFile."mimeapps.list".enable = false;

  # Le nom D-Bus org.freedesktop.FileManager1 (utilisé par les navigateurs pour
  # "ouvrir le dossier") est sinon capté par nautilus, démarré à froid à chaque
  # clic. On le redirige vers Thunar, déjà lancé en --daemon.
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${pkgs.xfce.thunar}/bin/Thunar --gapplication-service
  '';

  # mailto: → nouvel onglet de composition Gmail dans Brave
  xdg.desktopEntries.gmail-mailto = {
    name = "Gmail (mailto)";
    exec = "${pkgs.writeShellScript "gmail-mailto" ''
      exec ${pkgs.brave}/bin/brave "https://mail.google.com/mail/?extsrc=mailto&url=$1"
    ''} %u";
    mimeType = [ "x-scheme-handler/mailto" ];
    noDisplay = true;
  };

  xdg.desktopEntries."org.nickvision.tubeconverter" = {
    name = "Parabolic";
    comment = "Download web video and audio";
    exec = "org.nickvision.tubeconverter %u";
    icon = "org.nickvision.tubeconverter";
    terminal = false;
    type = "Application";
    categories = [ "AudioVideo" "Network" ];
    settings = {
      DBusActivatable = "false";
      Keywords = "YouTube;Downloader;ytdlp;audio;video;media;download;";
      StartupNotify = "true";
    };
  };

  # vim (sans GUI) installe gvim.desktop alors que gvim n'existe pas : on masque
  xdg.desktopEntries.gvim = {
    name = "GVim";
    exec = "gvim";
    noDisplay = true;
  };

  xdg.desktopEntries."Claude Code" = {
    name = "Claude Code";
    exec = "claude %U";
    icon = "claude-code";
    terminal = true;
    type = "Application";
    noDisplay = true;
  };

  xdg.dataFile."icons/hicolor/256x256/apps/vscode.png".source = "${pkgs.vscode}/share/icons/hicolor/256x256/apps/vscode.png";
  xdg.dataFile."icons/hicolor/scalable/apps/claude-code.svg".source = ./assets/claude-code-icon.svg;
  # Index du thème hicolor utilisateur : on reprend l'index officiel complet
  # (toutes tailles/contextes). Un index tronqué ici masque celui du système
  # pour toutes les apps GTK : seuls les dossiers listés sont parcourus, dans
  # TOUS les répertoires de XDG_DATA_DIRS — d'où les barres d'outils vides de
  # VMware (ses icônes vivent dans 16x16/actions, devices/, status/...).
  xdg.dataFile."icons/hicolor/index.theme".source =
    "${pkgs.hicolor-icon-theme}/share/icons/hicolor/index.theme";

  # ==========================================================================
  # 5. ALIAS SHELL
  # ==========================================================================
  home.shellAliases = {
    nixgemini = "cd /etc/nixos/ && gemini";
    nixclaude = "cd /etc/nixos/ && claude";
    obsiclaude = "cd ~/Documents/Obsidian/ && claude";
    nixedit = "EDITOR='code --wait' sudoedit /etc/nixos/configuration.nix";
    homedit = "cd /etc/nixos/ && code home.nix";
    nixrebuild = "cd /etc/nixos && sudo git add . && sudo nixos-rebuild switch --flake .#pc1";
    nixupdate = "driver-update update";
    vpnon = "sudo wg-quick up proton && notify-send 'VPN' 'ProtonVPN connecté'";
    vpnoff = "sudo wg-quick down proton && notify-send 'VPN' 'ProtonVPN déconnecté'";
    stream-on = "sudo cpupower frequency-set -g performance && notify-send 'Stream mode' 'CPU en mode performance'";
    stream-off = "sudo cpupower frequency-set -g schedutil && notify-send 'Stream mode' 'CPU revenu en schedutil'";
    shutpc = "ssh user@HOMELAB_IP_REDACTED 'shutdown /s /t 0' && notify-send 'shutpc' 'PC Windows HOMELAB_IP_REDACTED éteint'";
    ls = "eza --icons=always";
    ll = "eza -l --icons=always --git";
    la = "eza -a --icons=always";
    lt = "eza --tree --icons=always";
    # gitpush = "git add -A && git commit -m 'Fix' && git push"
  };

  # ==========================================================================
  # 6. PROGRAMMES
  # ==========================================================================
  programs.home-manager.enable = true;

  # nm-applet : pas de notif "Connexion établie" (Quickshell gère le réseau)
  dconf.settings."org/gnome/nm-applet".disable-connected-notifications = true;
  # nm-applet : pas de notif "Message d'identification VPN" à la connexion VPN
  dconf.settings."org/gnome/nm-applet".disable-vpn-notifications = true;
  programs.bash = {
    enable = true;
    enableCompletion = true;
    initExtra = ''
      export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

      restart() {
        local name="$1"
        if [ -z "$name" ]; then
          echo "Usage: restart <process>"
          return 1
        fi
        if systemctl --user list-unit-files --type=service 2>/dev/null | grep -q "^''${name}\.service"; then
          systemctl --user restart "''${name}.service"
          return
        fi
        local bin
        bin=$(command -v "$name")
        if [ -z "$bin" ]; then
          echo "restart: $name introuvable (ni service systemd, ni binaire dans PATH)"
          return 1
        fi
        pkill -x "$name"
        sleep 0.3
        setsid -f "$bin" >/dev/null 2>&1 &
        disown
      }
    '';
  };

  # --- Interface fastfetch : logo NixOS + infos clean, accents cyan/violet ---
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "nixos";
        padding = { top = 1; left = 2; right = 3; };
        color = { "1" = "36"; "2" = "35"; };  # cyan + violet
      };
      display = {
        separator = "  ";
        color = { keys = "36"; title = "35"; };
      };
      modules = [
        { type = "title"; format = "{user-name}@{host-name}"; }
        "separator"
        { type = "os";       key = " OS"; keyColor = "magenta"; }
        { type = "kernel";   key = " Kernel"; }
        { type = "uptime";   key = " Uptime"; }
        { type = "packages"; key = " Packages"; }
        { type = "shell";    key = " Shell"; }
        "separator"
        { type = "wm";       key = " WM"; keyColor = "magenta"; }
        { type = "terminal"; key = " Term"; }
        { type = "cpu";      key = " CPU"; }
        { type = "gpu";      key = "󰢮 GPU"; }
        { type = "memory";   key = " RAM"; }
        { type = "disk";     key = " Disk"; }
        "separator"
        { type = "colors"; symbol = "circle"; }
      ];
    };
  };

  programs.eza = { enable = true; icons = "auto"; git = true; extraOptions = [ "--group-directories-first" "--header" ]; };
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$character";
      character = { success_symbol = "[>](bold white)"; error_symbol = "[>](bold red)"; };
      directory = { style = "bold purple"; };
    };
  };
  programs.kitty = {
    enable = true;
    font.name = "JetBrainsMono Nerd Font";
    font.size = 11;
    settings = {
      background_opacity = "0.50";
      dynamic_background_opacity = "yes";
      window_padding_width = 10;
      hide_window_decorations = "yes";
      enable_audio_bell = "no";
      confirm_os_window_close = 0;
      cursor_shape = "beam";
    };
  };

  # ==========================================================================
  # 7. HYPRLAND → modules/hyprland.nix (config Lua)
  # ==========================================================================
  # ==========================================================================
  # 8. HYPRLOCK & HYPRIDLE
  # ==========================================================================
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading = true;
        hide_cursor = true;
        grace = 0;
        ignore_empty_input = true;
      };

      # Fondu à l'apparition/disparition (no_fade_in/out retirés depuis hyprlock 0.9)
      animations = {
        enabled = true;
        bezier = [ "easeOut, 0.25, 1, 0.5, 1" ];
        animation = [
          "fadeIn, 1, 6, easeOut"
          "fadeOut, 1, 5, easeOut"
          "inputFieldDots, 1, 2, easeOut"
          "inputFieldColors, 1, 3, easeOut"
          "inputFieldWidth, 1, 3, easeOut"
        ];
      };

      background = [
        {
          path = "screenshot";
          color = "rgba(25, 20, 20, 1.0)";
          blur_passes = 4;
          blur_size = 10;
          brightness = 0.75;
          zoomfactor = 1.05;
        }
      ];

      input-field = [
        {
          size = "250, 60";
          outline_thickness = 2;
          rounding = 24;
          dots_size = 0.2;
          dots_spacing = 0.2;
          dots_center = true;
          outer_color = "rgba(255, 255, 255, 0.1)";
          inner_color = "rgba(255, 255, 255, 0.1)";
          check_color = "rgba(220, 50, 50, 0.9)";
          fail_color = "rgba(220, 50, 50, 0.9)";
          font_color = "rgb(200, 200, 200)";
          fail_text = "";
          fail_timeout = 600;
          fade_on_empty = true;
          placeholder_text = "";
          hide_input = false;
          position = "0, -120";
          halign = "center";
          valign = "center";
        }
      ];

      # Barre séparatrice entre l'heure et la date
      shape = [
        {
          size = "260, 2";
          color = "rgba(255, 255, 255, 0.6)";
          rounding = -1;
          border_size = 0;
          position = "0, 20";
          halign = "center";
          valign = "center";
          shadow_passes = 2;
          shadow_size = 6;
          shadow_color = "rgba(0, 0, 0, 0.8)";
        }
      ];

      label = [
        # Heure
        {
          text = "$TIME";
          color = "rgba(255, 255, 255, 0.9)";
          font_size = 120;
          font_family = "League Spartan Bold";
          position = "0, 95";
          halign = "center";
          valign = "center";
          shadow_passes = 3;
          shadow_size = 20;
          shadow_color = "rgba(0, 0, 0, 0.9)";
          shadow_boost = 1.6;
        }
        # Date
        {
          text = "cmd[update:1000] date +'%A %d %B' | sed 's/./\\u&/'";
          color = "rgba(255, 255, 255, 0.8)";
          font_size = 24;
          font_family = "League Spartan";
          position = "0, -10";
          halign = "center";
          valign = "center";
        }
        # Batterie (icone seule, sans pourcentage, police BatteryIcons) ; masquée en mode bureau
        # (écran externe seul : capot fermé ou écran interne éteint, cf. display-switch.nix)
        {
          # Police "BatteryIcons" : U+E000..U+E00A = 0..100 % (pas de 10), U+E00C..U+E016 = idem en charge
          text = "cmd[update:1000] case $(cat $HOME/.local/state/display-mode 2>/dev/null) in lid-closed|external-only) exit 0;; esac; CAP=$(cat /sys/class/power_supply/BAT*/capacity | head -n 1); STATUS=$(cat /sys/class/power_supply/BAT*/status | head -n 1); AC=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0); B=128; if [ \"$AC\" = \"1\" ] && [ \"$STATUS\" != \"Full\" ]; then B=140; fi; printf \"\\xee\\x80\\x$(printf '%x' $(( B + (CAP + 5) / 10 )))\"";
          # Couleur dynamique : Bleu (en charge), sinon Vert (>70), Jaune (>25), Rouge (<=25)
          color = "cmd[update:1000] CAP=$(cat /sys/class/power_supply/BAT*/capacity | head -n 1); STATUS=$(cat /sys/class/power_supply/BAT*/status | head -n 1); AC=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0); if [ \"$AC\" = \"1\" ] && [ \"$STATUS\" != \"Full\" ]; then STATUS=\"Charging\"; fi; if [ \"$STATUS\" = \"Charging\" ]; then echo \"rgba(137, 180, 250, 0.9)\"; elif [ $CAP -gt 70 ]; then echo \"rgba(166, 227, 161, 0.8)\"; elif [ $CAP -gt 25 ]; then echo \"rgba(249, 226, 175, 0.8)\"; else echo \"rgba(243, 139, 168, 0.8)\"; fi";
          font_size = 26;
          font_family = "BatteryIcons";
          position = "0, -50";
          halign = "center";
          valign = "center";
        }
        # Météo
        {
          text = "cmd[update:1800000] ${pkgs.curl}/bin/curl -s 'wttr.in/?format=%c' 2>/dev/null | tr -d '[:space:]' || echo ''";
          color = "rgba(255, 255, 255, 0.5)";
          font_size = 16;
          font_family = "Inter";
          position = "0, 40";
          halign = "center";
          valign = "bottom";
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || ${hyprlockSafe}/bin/hyprlock-safe";
        # display-sleep (modules/display-switch.nix) rallume eDP-1 avant la veille
        # s'il est éteint (capot fermé sur le dock) : si le dock est retiré pendant
        # la veille, Hyprland se réveille sinon avec zéro écran → sortie FALLBACK
        # → hyprlock éjecté. Au réveil, `post` remet le mode capot fermé si besoin.
        before_sleep_cmd = "${config.home.profileDirectory}/bin/display-sleep pre; loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'; ${config.home.profileDirectory}/bin/display-sleep post";
        # 3 : la veille attend que le verrou soit posé (donc display-sleep pre fini)
        inhibit_sleep = 3;
      };

      listener = [
        {
          timeout = 300; # 5 minutes
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 330; # 5.5 minutes
          on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'";
          on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
        }
      ];
    };
  };

  gtk = {
    enable = true;
    iconTheme = {
      # Thème parapluie : look Papirus + fallback icônes stock GTK (adwaita-icon-theme-legacy)
      # pour les vieilles apps comme VMware (barres d'outils vides sinon)
      name = "Papirus-Stock";
      package = pkgs.papirus-icon-theme;
    };
    # Signets de la barre latérale Thunar/GTK (déclaratifs : le fichier
    # ~/.config/gtk-3.0/bookmarks devient un lien lecture seule vers /nix/store)
    gtk3.bookmarks = [
      "sftp://homelab@HOMELAB_IP_REDACTED/home/homelab Homelab"
    ];
  };

  # Thème d'icônes agrégateur : hérite Papirus-Dark puis AdwaitaLegacy (stock GTK) puis hicolor
  xdg.dataFile."icons/Papirus-Stock/index.theme".text = ''
    [Icon Theme]
    Name=Papirus-Stock
    Comment=Papirus-Dark avec fallback icônes stock GTK
    Inherits=Papirus-Dark,AdwaitaLegacy,Adwaita,hicolor
    Directories=
  '';

  # ==========================================================================
  # BTS SIO — Correctifs applications
  # ==========================================================================

  # Applis web (Drive, WhatsApp, SoundCloud, Atlas…) → modules/webapps.nix + commande `webapp`
  # Icône "atlas-homelab" gardée ici : utilisée par les notifications d'atlas-task
  xdg.dataFile."icons/hicolor/scalable/apps/atlas-homelab.svg".source = ./assets/atlas-icon.svg;

  # VMware : forcer XWayland + exposer le thème hicolor embarqué du paquet
  # (vm-power-on, view-fullscreen... sinon la barre d'outils est vide)
  xdg.desktopEntries.vmware-workstation = {
    name = "VMware Workstation";
    comment = "Run and manage virtual machines";
    exec = "env GDK_BACKEND=x11 GTK_THEME=Adwaita vmware %U";
    terminal = false;
    type = "Application";
    icon = "${pkgs.vmware-workstation}/share/icons/hicolor/256x256/apps/vmware-workstation.png";  # chemin absolu : le thème d'icônes en impose une version stylisée
    startupNotify = true;
    categories = [ "System" ];
    mimeType = [
      "application/x-vmware-vm"
      "application/x-vmware-team"
      "application/x-vmware-enc-vm"
      "x-scheme-handler/vmrc"
    ];
  };

  # Ventoy : ventoy-web nécessite root (pkexec) et sert une UI web locale ; on ouvre le navigateur dessus
  xdg.desktopEntries.ventoy = {
    name = "Ventoy";
    comment = "Créer une clé USB bootable multiboot (alternative Rufus)";
    exec = ''sh -c "pkexec ventoy-web & sleep 2 && xdg-open http://127.0.0.1:24680"'';
    terminal = false;
    type = "Application";
    icon = "drive-removable-media-usb";
    startupNotify = true;
    categories = [ "System" "Utility" ];
  };

}
