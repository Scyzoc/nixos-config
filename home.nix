{ config, pkgs, lib, ... }:
let notionTodo = ./modules/notion-todo.nix; in

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
    ./modules/quickshell.nix
    ./modules/swaync.nix
    ./modules/networkmenu.nix
    ./modules/emoji.nix
    ./modules/voice-transcription.nix
    ./modules/assistant.nix
    ./modules/atlas-task.nix
    ./modules/app-launcher.nix
    ./modules/wallpaper-picker.nix
    ./modules/workspace-cycle.nix
    ./modules/workspace-compact.nix
    ./modules/special-zoom.nix
    ./modules/clipboard.nix
    ./modules/bluetooth-menu.nix
    ./modules/airpods-monitor.nix
    ./modules/airpods-ear.nix
    ./modules/power-saving.nix
    ./modules/theme-automation.nix
    ./modules/internet-check.nix
    ./modules/netfix.nix
    ./modules/ethernet-menu.nix
    ./modules/display-switch.nix
    ./modules/gammastep.nix
    ./modules/update-check.nix
    ./modules/nixfix.nix
    ./modules/bedtime.nix
    ./modules/archive-extract.nix
    ./modules/ipinfo.nix
    ./modules/driver-update.nix
    ./modules/cli-list.nix
    ./modules/nixinstall.nix
    ./modules/webapps.nix
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
        ssh homelab@HOMELAB_IP_REDACTED wakeonlan AA:BB:CC:DD:EE:FF \
          && ${libnotify}/bin/notify-send 'Wake-on-LAN' 'PC réveillé (HOMELAB_IP_REDACTED)'
      else
        ${libnotify}/bin/notify-send -u critical 'Wake-on-LAN' 'Homelab injoignable — VPN pas activé ?'
      fi
    '')
    (writeShellScriptBin "pcoff" ''
      if ${netcat-gnu}/bin/nc -z -w2 HOMELAB_IP_REDACTED 22 2>/dev/null; then
        ssh pc 'shutdown /s /t 0' \
          && ${libnotify}/bin/notify-send 'Extinction' 'PC Windows éteint (HOMELAB_IP_REDACTED)'
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
    obsidian




    # --- audio-switch ---
    (pkgs.writeShellScriptBin "audio-switch" ''
      SINKS=$(wpctl status | grep -A 10 "Sinks" | grep -oP '\d+(?=\.)' | head -n 2)
      CURRENT=$(wpctl status | grep "*" | grep -oP '\d+(?=\.)' | head -n 1)
      NEXT=$(echo "$SINKS" | grep -v "$CURRENT" | head -n 1)
      if [ -n "$NEXT" ]; then
          wpctl set-default "$NEXT"
          notify-send "Audio" "Sortie basculee vers l'appareil ID: $NEXT" -i audio-speakers
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

    # --- Developpement ---
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
      ${pkgs.libnotify}/bin/notify-send "Veille" "Mise en veille dans $delai secondes…" -t 2500
      echo "Mise en veille dans $delai secondes (Ctrl+C pour annuler)"
      sleep "$delai"
      systemctl suspend
    '')

    # Capture : gèle l'écran (curseur figé inclus), puis sélection de zone
    (pkgs.writeShellScriptBin "screenshot" ''
      mode="''${1:-copy}"

      if [ "$1" = "--internal-finish" ]; then
        mode="$2"
        file="$3"
        geom=$(${pkgs.slurp}/bin/slurp)
        ${pkgs.procps}/bin/pkill wayfreeze
        if [ -n "$geom" ]; then
          ${pkgs.grim}/bin/grim -g "$geom" "$file"
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
              ${pkgs.libnotify}/bin/notify-send -a Screenshot -u low Screenshot 'Capture annulée'
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
          action=$(${pkgs.libnotify}/bin/notify-send -a Screenshot -i "$file" -A "editer=Éditer" -w Screenshot "$msg")
          if [ "$action" = "editer" ]; then
            ${pkgs.swappy}/bin/swappy -f "$file"
          fi
        else
          ${pkgs.libnotify}/bin/notify-send -a Screenshot -u low Screenshot 'Capture annulée'
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
        ${pkgs.hyprland}/bin/hyprctl dispatch exec "[workspace 11] discord"
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

  # nm-applet : pas de notif "Connexion établie" (garde celle de networkmenu)
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
          systemctl --user restart "''${name}.service" && notify-send "restart" "''${name} relancé (systemd)"
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
        notify-send "restart" "''${name} relancé"
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
  # 7. HYPRLAND
  # ==========================================================================
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    settings = {
      "$mainMod" = "SUPER";
      "$terminal" = "kitty";
      "$fileManager" = "thunar";
      "$menu" = "app-launcher";

      env = [
        "XDG_SESSION_TYPE,wayland"
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "XCURSOR_THEME,Bibata-Modern-Ice"
        # Contourne un crash Aquamarine/AMD (SDRMConnector::releaseCommitBuffers, SIGABRT)
        # au branchement d'un écran externe : désactive l'atomic modesetting DRM.
        "AQ_NO_ATOMIC,1"
      ];

      monitor = [
        "eDP-1, 1920x1080@60, 1520x1440, 1"
        "desc:Xiaomi Corporation Mi monitor 5505610117971, 3440x1440@120.00, 0x0, 1"
        "desc:Microstep MSI MAG241C 0x00000010, 1920x1080@144, 3440x0, 1, transform, 3"
        ", preferred, auto, 1"
      ];

      # Sourcé après les règles ci-dessus : nwg-displays écrit ici quand on
      # clique "Apply" (mode Hyprland de nwg-displays, écrit un fichier +
      # hyprctl reload plutôt que d'appliquer en live). Placé en dernier
      # pour que ses lignes monitor= aient priorité sur les défauts au-dessus.
      source = [ "~/.config/hypr/monitors.conf" "~/.config/hypr/workspaces.conf" ];

      # Répartition des workspaces : plus de règles en dur ici. Elles sont
      # générées dynamiquement par workspace-bind (modules/display-switch.nix)
      # dans ~/.config/hypr/workspaces.conf, un bloc de 10 par écran actif
      # (eDP-1 : 1-10, externe 1 : 11-20, ...) ou les groupes définis par
      # disposition via display-layouts (Super+Ctrl+P).

      exec-once = [
        "dbus-update-activation-environment --systemd --all"
        "systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland"
        "hyprctl setcursor Bibata-Modern-Ice 24"
        "xhost +si:localuser:root"
        "swaync"
        "awww-daemon"
        "awww restore || true"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        # --no-agent : la barre Quickshell gère les mots de passe Wi-Fi ; sinon NM
        # attend la fenêtre de nm-applet avant d'abandonner (demande de mdp très lente)
        "nm-applet --indicator --no-agent"
        "workspace-bind"
      ];

      input = {
        kb_layout = "fr";
        kb_variant = "azerty";
        numlock_by_default = true;
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
          drag_lock = true;
        };
      };

      gesture = [
        "3, horizontal, workspace"
      ];

      cursor = {
        inactive_timeout = 2;
        no_hardware_cursors = true;
      };

      general = {
        gaps_in = 5;
        # = marges gauche/droite de la barre Quickshell (Bar.qml) → bords alignés
        gaps_out = 10;
        border_size = 1;
        "col.active_border" = "rgba(ffffffff)";
        "col.inactive_border" = "rgba(595959aa)";
        resize_on_border = false;
        allow_tearing = false;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
        active_opacity = 1.0;
        inactive_opacity = 1.0;
        shadow = { enabled = true; range = 4; render_power = 3; color = "rgba(1a1a1aee)"; };
        blur = { enabled = true; size = 4; passes = 1; ignore_opacity = false; new_optimizations = true; };
      };

      animations = {
        enabled = true;
        bezier = [
          "easeOutQuint, 0.23, 1, 0.32, 1"
          "linear, 0, 0, 1, 1"
          "snap, 0.19, 1, 0.22, 1"
          "smoothOut, 0.36, 0, 0.66, -0.56"
          "smoothIn, 0.25, 1, 0.5, 1"
        ];
        animation = [
          "global, 1, 3, snap"
          "border, 1, 3, easeOutQuint"
          "windows, 1, 2, snap"
          "windowsIn, 1, 2, snap, popin 87%"
          "windowsOut, 1, 2, easeOutQuint, popin 87%"
          "fadeIn, 1, 2, linear"
          "fadeOut, 1, 2, linear"
          "fade, 1, 2, linear"
          "layers, 1, 2, snap"
          "layersIn, 1, 2, snap, fade"
          "layersOut, 1, 2, easeOutQuint, fade"
          "fadeLayersIn, 1, 2, linear"
          "fadeLayersOut, 1, 2, linear"
          "workspaces, 1, 3, smoothIn, slide"
          "workspacesIn, 1, 3, smoothIn, slide"
          "workspacesOut, 1, 3, smoothOut, slide"
          # Scratchpad : fondu seul, le zoom des fenêtres est fait par special-zoom
          "specialWorkspace, 1, 2, snap, fade"
          "specialWorkspaceOut, 1, 2, linear, fade"
        ];
      };

      # disable_autoreload : workspace-bind réécrit workspaces.conf (sourcé) ;
      # l'autoreload rechargeait alors toute la config et effaçait les règles
      # posées à chaud (mode miroir annulé au bout de 2 s). Le rebuild
      # home-manager fait déjà `hyprctl reload` lui-même.
      misc = { force_default_wallpaper = 0; disable_hyprland_logo = true; vrr = 2; disable_autoreload = true; };

      render = {
        direct_scanout = false;
      };
      dwindle = { preserve_split = true; };


      bind = [
        "$mainMod, C, exec, $terminal"
        "$mainMod, B, exec, brave"
        "$mainMod, G, exec, brave --app=https://gemini.google.com"
        "$mainMod, A, exec, brave --app=https://claude.ai/new"
        "$mainMod, N, exec, brave --app=https://www.notion.so/ID_CENSURE"
        "$mainMod ALT, P, exec, brave --app=https://calendar.notion.so/"
        
        "$mainMod, Y, exec, brave --app=https://www.youtube.com/"
        "$mainMod, S, exec, spotify"
        "$mainMod, T, exec, brave --app=https://atlas.homelab.lan"
        "$mainMod, D, exec, discord-launcher"
        "$mainMod, R, exec, $menu"
        "$mainMod, E, exec, thunar"
        "$mainMod, W, exec, wallpaper-picker"
        "$mainMod, V, exec, clipboard-manager"
        "$mainMod, L, exec, hyprlock"
        "$mainMod, semicolon, exec, emoji-picker"
        "$mainMod, I, exec, kitty --class internet-check -e internet-check"
        "$mainMod, U, exec, $terminal --class nmtui -e nmtui"
        "$mainMod ALT, S, exec, audio-switch"
        "$mainMod, O, exec, obsidian 'obsidian://open?vault=Obsidian'"
        "$mainMod SHIFT, O, exec, pwvucontrol"
        "$mainMod, Q, killactive,"
        "$mainMod SHIFT, M, exit,"
        "$mainMod SHIFT, V, exec, voice-to-text"
        "$mainMod SHIFT, N, exec, notion-todo"
        "$mainMod, Space, togglefloating,"
        "$mainMod, J, layoutmsg, togglesplit" # J'ai enlevé le doublon de P (pseudo) qui était utilisé par Notion
        
        # Mouvements Focus
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        
        # Déplacements de fenêtres (flèches)
        "$mainMod SHIFT, left, movewindow, l"
        "$mainMod SHIFT, right, movewindow, r"
        "$mainMod SHIFT, up, movewindow, u"
        "$mainMod SHIFT, down, movewindow, d"
        
        
        "$mainMod, F, fullscreen, 1"
        "$mainMod SHIFT, F, fullscreen,"
        # Special Workspace (Scratchpad)
        "$mainMod, X, exec, special-zoom magic" # Scratchpad : fondu + zoom depuis le centre (modules/special-zoom.nix) — X car S est pris par Spotify
        "$mainMod SHIFT, X, movetoworkspace, special:magic"

        # Switch bureaux avec Super+Tab (par moniteur)
        "$mainMod, Tab, exec, ws-cycle next"
        "$mainMod SHIFT, Tab, exec, ws-cycle prev"
        "$mainMod CTRL, Tab, exec, ws-compact"

        # Souris
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"

        # Screenshots
        ", Print, exec, screenshot copy"
        "SHIFT, Print, exec, screenshot save"
        ] ++ (        # --- ADAPTATION SPÉCIFIQUE AZERTY ---
        let
          # Liste des touches physiques sous les chiffres 1 à 0 en AZERTY
          azertyKeys = [ "ampersand" "eacute" "quotedbl" "apostrophe" "parenleft" "minus" "egrave" "underscore" "ccedilla" "agrave" ];
        in
        builtins.concatLists (builtins.genList (i:
          let
            ws = i + 1;
            key = builtins.elemAt azertyKeys i;
          in [
            "$mainMod, ${key}, workspace, ${toString ws}"
            "$mainMod SHIFT, ${key}, movetoworkspace, ${toString ws}"
            # Workspaces 11 à 20 : même touche + CTRL
            "$mainMod CTRL, ${key}, workspace, ${toString (ws + 10)}"
            "$mainMod CTRL SHIFT, ${key}, movetoworkspace, ${toString (ws + 10)}"
          ]
        ) 10)
      );

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      bindel = [
        ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && [ \"$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')\" = \"0.00\" ] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1"
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
      ];

      bindl = [
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

      bindr = [];

      windowrule = [
        "match:class .*, suppress_event maximize"
        "match:class ^$, match:title ^$, match:xwayland 1, match:float 1, match:fullscreen 0, match:pin 0, no_focus 1"
        "match:class nmtui, float 1"
        "match:class nmtui, size 700 500"
        "match:class nmtui, center 1"
        "match:class com.saivert.pwvucontrol, float 1"
        "match:class com.saivert.pwvucontrol, size 700 500"
        "match:class com.saivert.pwvucontrol, center 1"
        "match:class com.saivert.pwvucontrol, animation popin"
        "match:title wlogout, float 1"
        "match:title wlogout, center 1"

        # Vérification internet : terminal flottant centré
        "match:class internet-check, float 1"
        "match:class internet-check, size 560 340"
        "match:class internet-check, center 1"
        "match:class internet-check, animation popin"

        # netfix (menu applications) : terminal flottant centré
        "match:class netfix, float 1"
        "match:class netfix, size 720 560"
        "match:class netfix, center 1"
        "match:class netfix, animation popin"

        # Désinstallation (clic droit du menu d'applications) : terminal flottant centré
        "match:class app-uninstall, float 1"
        "match:class app-uninstall, size 760 480"
        "match:class app-uninstall, center 1"
        "match:class app-uninstall, animation popin"

        # Menu Notion TO DO
        "match:class notion-todo, float 1"
        "match:class notion-todo, center 1"
        "match:class notion-todo, animation popin"
      ];
      layerrule = [
        "blur on, match:namespace bedtime"
        "ignore_alpha 0.0, match:namespace bedtime"
        "blur on, match:namespace quickshell-bar"
        "ignore_alpha 0.1, match:namespace quickshell-bar"
        # Menus d'applications / presse-papiers : flou derrière le panneau seulement
        # (pas derrière le fond assombri)
        "blur on, match:namespace quickshell-launcher"
        "ignore_alpha 0.4, match:namespace quickshell-launcher"
        "blur on, match:namespace quickshell-clipboard"
        "ignore_alpha 0.4, match:namespace quickshell-clipboard"
        "blur on, match:namespace quickshell-emoji"
        "ignore_alpha 0.4, match:namespace quickshell-emoji"
        "blur on, match:namespace swaync"
        "ignore_alpha 0.1, match:namespace swaync"
        "blur on, match:namespace swaync-notification-window"
        "ignore_alpha 0.1, match:namespace swaync-notification-window"
        "blur on, match:namespace swaync-control-center"
        "ignore_alpha 0.1, match:namespace swaync-control-center"
        "blur on, match:namespace launcher"
        "blur on, match:namespace rofi"
        "ignore_alpha 0.1, match:namespace rofi"
        "animation fade, match:namespace rofi"
      ];
    };
  };
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
          dots_size = 0.2;
          dots_spacing = 0.2;
          dots_center = true;
          outer_color = "rgba(255, 255, 255, 0.1)";
          inner_color = "rgba(255, 255, 255, 0.1)";
          check_color = "rgba(220, 50, 50, 0.9)";
          fail_color = "rgba(220, 50, 50, 0.9)";
          font_color = "rgb(200, 200, 200)";
          fail_text = "";
          fail_timeout = 300;
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
        # Batterie (icone seule, sans pourcentage, police BatteryIcons)
        {
          # Police "BatteryIcons" : U+E000..U+E00A = 0..100 % (pas de 10), U+E00C..U+E016 = idem en charge
          text = "cmd[update:1000] CAP=$(cat /sys/class/power_supply/BAT*/capacity | head -n 1); STATUS=$(cat /sys/class/power_supply/BAT*/status | head -n 1); AC=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0); B=128; if [ \"$AC\" = \"1\" ] && [ \"$STATUS\" != \"Full\" ]; then B=140; fi; printf \"\\xee\\x80\\x$(printf '%x' $(( B + (CAP + 5) / 10 )))\"";
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
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 300; # 5 minutes
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 330; # 5.5 minutes
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
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
    icon = "vmware-workstation";
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
