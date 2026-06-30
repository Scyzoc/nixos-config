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
    ./modules/waybar.nix
    ./modules/mpris.nix
    ./modules/swaync.nix
    ./modules/networkmenu.nix
    ./modules/emoji.nix
    ./modules/voice-transcription.nix
    ./modules/app-launcher.nix
    ./modules/wallpaper-picker.nix
    ./modules/clipboard.nix
    ./modules/bluetooth-menu.nix
    ./modules/airpods-monitor.nix
    ./modules/power-saving.nix
    ./modules/theme-automation.nix
    ./modules/internet-check.nix
    ./modules/ethernet-menu.nix
    ./modules/display-switch.nix
    ./modules/gammastep.nix
  ];

  # ==========================================================================
  # VARIABLES D'ENVIRONNEMENT
  # ==========================================================================

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    PATH = "/etc/profiles/per-user/user/bin:$HOME/.npm-global/bin:$PATH";
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
    gnome-icon-theme  # icônes "stock" GTK dépréciées (gtk-execute, gtk-media-*) pour VMware
    (writeShellScriptBin "wakepc" ''
      if ${netcat-gnu}/bin/nc -z -w2 HOMELAB_IP_REDACTED 22 2>/dev/null; then
        ssh homelab@HOMELAB_IP_REDACTED wakeonlan AA:BB:CC:DD:EE:FF \
          && ${libnotify}/bin/notify-send 'Wake-on-LAN' 'PC réveillé (HOMELAB_IP_REDACTED)'
      else
        ${libnotify}/bin/notify-send -u critical 'Wake-on-LAN' 'Homelab injoignable — VPN pas activé ?'
      fi
    '')
    onlyoffice-desktopeditors
    github-cli
    (python3.withPackages (ps: [ ps.requests ]))
    signal-cli
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
    nautilus
    brave
    google-chrome
    (pkgs.discord.override { withOpenASAR = true; })
    # rustdesk forcé en X11/XWayland (clavier mort sous Wayland natif), garde l'entrée du menu
    (pkgs.symlinkJoin {
      name = "rustdesk-x11";
      paths = [ pkgs.rustdesk ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/rustdesk \
          --set GDK_BACKEND x11 \
          --set QT_QPA_PLATFORM xcb \
          --unset WAYLAND_DISPLAY
      '';
    })
    anydesk
    remmina
    localsend

    # --- Diagrammes ---
    drawio

    # --- Éditeurs ---
    code-cursor

    # --- Musique et divertissement ---
    spotify
    prismlauncher
    vlc
    # stremio-linux-shell  # temporairement désactivé (bug de build nixpkgs)

    # --- Developpement ---
    nodejs
    vscode
    opencode
    gemini-cli
    claude-code
    claude-monitor


    # --- Utilitaires systeme ---
    rsync
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
    wine
    nwg-displays

    # --- Lanceurs d'applications ---
    wofi

    # --- Barre de statut et fond d'ecran ---
    waybar
    awww
    imagemagick

    # --- Capture d'ecran ---
    grim
    slurp
    wayfreeze

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
    pavucontrol

    # --- Divers ---
    screen
    xhost
    wlogout

    # --- wlogout config ---
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
      ${pkgs.libnotify}/bin/notify-send "Veille" "Mise en veille dans 3 secondes…" -t 2500
      sleep 3
      systemctl suspend
    '')

    # Capture : gèle l'écran (curseur figé inclus), puis sélection de zone
    (pkgs.writeShellScriptBin "screenshot" ''
      mode="''${1:-copy}"
      # Toggle : annule une capture déjà en cours
      ${pkgs.procps}/bin/pkill slurp 2>/dev/null && exit 0
      ${pkgs.procps}/bin/pkill wayfreeze 2>/dev/null && exit 0

      if [ "$mode" = "save" ]; then
        file="$HOME/Pictures/screenshot_$(${pkgs.coreutils}/bin/date +%Y%m%d_%H%M%S).png"
        ${pkgs.wayfreeze}/bin/wayfreeze --after-freeze-cmd "geom=\$(${pkgs.slurp}/bin/slurp) && [ -n \"\$geom\" ] && ${pkgs.grim}/bin/grim -g \"\$geom\" \"$file\" && ${pkgs.libnotify}/bin/notify-send Screenshot 'Sauvegardé'; ${pkgs.procps}/bin/pkill wayfreeze"
      else
        ${pkgs.wayfreeze}/bin/wayfreeze --after-freeze-cmd "geom=\$(${pkgs.slurp}/bin/slurp) && [ -n \"\$geom\" ] && ${pkgs.grim}/bin/grim -g \"\$geom\" - | ${pkgs.wl-clipboard}/bin/wl-copy && ${pkgs.libnotify}/bin/notify-send Screenshot 'Zone copiée'; ${pkgs.procps}/bin/pkill wayfreeze"
      fi
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

  xdg.dataFile."icons/hicolor/256x256/apps/vscode.png".source = "${pkgs.vscode}/share/icons/hicolor/256x256/apps/vscode.png";
  xdg.dataFile."icons/hicolor/scalable/apps/claude-code.svg".text = ''
    <svg width="691" height="691" viewBox="0 0 691 691" fill="none" xmlns="http://www.w3.org/2000/svg">
    <g clip-path="url(#clip0_5411_88528)">
    <rect width="691" height="691" rx="161.953" fill="url(#paint0_linear_5411_88528)"/>
    <rect opacity="0.35" width="691" height="691" fill="#D97757"/>
    <path d="M189.531 430.72L288.951 374.971L290.59 370.088L288.951 367.369H284.035L267.374 366.355L210.562 364.835L161.399 362.807L113.6 360.273L101.583 357.739L90.3843 342.788L91.4768 335.439L101.583 328.597L116.059 329.864L148.015 332.145L196.086 335.439L230.774 337.467L282.396 342.788H290.59L291.682 339.494L288.951 337.467L286.766 335.439L237.056 301.736L183.249 266.259L155.117 245.733L140.094 235.344L132.447 225.714L129.169 204.428L142.826 189.223L161.399 190.491L166.042 191.758L184.888 206.202L225.038 237.371L277.48 275.889L285.127 282.224L288.207 280.145L288.678 278.676L285.127 272.848L256.722 221.406L226.404 168.951L212.747 147.158L209.197 134.234C207.821 128.811 207.012 124.324 207.012 118.776L222.58 97.4901L231.32 94.7026L252.351 97.4901L261.092 105.092L274.202 134.994L295.233 181.875L328.009 245.733L337.569 264.739L342.758 282.224L344.67 287.545H347.948V284.505L350.679 248.521L355.595 204.428L360.512 147.665L362.15 131.7L370.071 112.441L385.913 102.051L398.204 107.88L408.31 122.324L406.944 131.7L400.935 170.725L389.19 231.796L381.543 272.848H385.913L391.102 267.526L411.86 240.158L446.548 196.572L461.843 179.341L479.87 160.335L491.342 151.212H513.192L529.034 175.033L521.932 199.613L499.536 227.995L480.963 252.068L454.332 287.747L437.808 316.434L439.29 318.8L443.271 318.461L503.359 305.537L535.862 299.709L574.647 293.12L592.127 301.229L594.039 309.592L587.211 326.57L545.695 336.706L497.077 346.589L424.68 363.632L423.878 364.277L424.824 365.68L457.473 368.636L471.403 369.396H505.545L569.184 374.211L585.845 385.107L595.678 398.538L594.039 408.927L568.365 421.851L533.95 413.742L453.376 394.483L425.79 387.641H421.966V389.922L444.909 412.475L487.245 450.486L539.959 499.647L542.69 511.811L535.862 521.44L528.761 520.427L482.328 485.456L464.302 469.745L423.878 435.535H421.147V439.083L430.433 452.767L479.87 527.015L482.328 549.822L478.778 557.171L465.94 561.732L452.011 559.198L422.786 518.399L393.014 472.786L368.979 431.734L366.076 433.567L351.771 586.312L345.216 594.168L329.921 599.996L317.084 590.367L310.255 574.656L317.084 543.487L325.278 502.941L331.833 470.759L337.842 430.72L341.511 417.345L341.187 416.45L338.255 416.943L308.07 458.342L262.184 520.427L225.858 559.198L217.117 562.746L202.095 554.89L203.461 540.953L211.928 528.536L262.184 464.677L292.502 424.892L312.042 402.055L311.851 398.751L310.773 398.659L177.24 485.71L153.478 488.751L143.099 479.121L144.464 463.41L149.381 458.342L189.531 430.72Z" fill="#FAF9F5"/>
    </g>
    <defs>
    <linearGradient id="paint0_linear_5411_88528" x1="283.418" y1="691" x2="283.418" y2="0" gradientUnits="userSpaceOnUse">
    <stop stop-color="#DC6038"/>
    <stop offset="1" stop-color="#D97757"/>
    </linearGradient>
    <clipPath id="clip0_5411_88528">
    <rect width="691" height="691" rx="161.953" fill="white"/>
    </clipPath>
    </defs>
    </svg>
  '';
  xdg.dataFile."icons/hicolor/index.theme".text = ''
    [Icon Theme]
    Name=hicolor
  '';

  # ==========================================================================
  # 5. ALIAS SHELL
  # ==========================================================================
  home.shellAliases = {
    nixgemini = "cd /etc/nixos/ && gemini";
    nixclaude = "cd /etc/nixos/ && claude";
    nixedit = "EDITOR='code --wait' sudoedit /etc/nixos/configuration.nix";
    homedit = "cd /etc/nixos/ && code home.nix";
    nixrebuild = "cd /etc/nixos && sudo git add . && sudo nixos-rebuild switch --flake .#pc1";
    nixupdate = "cd /etc/nixos && sudo nix flake update nixpkgs --flake /etc/nixos && nixrebuild";
    vpnon = "sudo wg-quick up proton && notify-send 'VPN' 'ProtonVPN connecté'";
    vpnoff = "sudo wg-quick down proton && notify-send 'VPN' 'ProtonVPN déconnecté'";
    stream-on = "sudo cpupower frequency-set -g performance && notify-send 'Stream mode' 'CPU en mode performance'";
    stream-off = "sudo cpupower frequency-set -g schedutil && notify-send 'Stream mode' 'CPU revenu en schedutil'";
    shutpc = "ssh user@HOMELAB_IP_REDACTED 'shutdown /s /t 0' && notify-send 'shutpc' 'PC Windows HOMELAB_IP_REDACTED éteint'";
    ls = "eza --icons=always";
    ll = "eza -l --icons=always --git";
    la = "eza -a --icons=always";
    lt = "eza --tree --icons=always";
  };

  # ==========================================================================
  # 6. PROGRAMMES
  # ==========================================================================
  programs.home-manager.enable = true;
  programs.bash = {
    enable = true;
    enableCompletion = true;
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
    # Charge la config monitors générée par nwg-displays APRÈS le bloc monitor
    # ci-dessous : la dernière règle monitor l'emporte, donc les réglages de
    # l'app prennent le dessus sur les valeurs codées en dur.
    extraConfig = ''
      source = ~/.config/hypr/monitors.conf
    '';
    settings = {
      "$mainMod" = "SUPER";
      "$terminal" = "kitty";
      "$fileManager" = "nautilus";
      "$menu" = "app-launcher";

      env = [
        "XDG_SESSION_TYPE,wayland"
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "XCURSOR_THEME,Bibata-Modern-Ice"
      ];

      monitor = [
        "eDP-1, 1920x1080@60, 1520x1440, 1"
        "desc:Xiaomi Corporation Mi monitor 5505610117971, 3440x1440@120.00, 0x0, 1"
        "desc:Microstep MSI MAG241C 0x00000010, 1920x1080@144, 3440x0, 1, transform, 3"
        ", preferred, auto, 1"
      ];

      workspace = [
        "1, monitor:eDP-1, default:true"
        "2, monitor:eDP-1"
        "3, monitor:eDP-1"
        "4, monitor:eDP-1"
        "5, monitor:eDP-1"
        "6, monitor:desc:Xiaomi Corporation Mi monitor 5505610117971, default:true"
        "7, monitor:desc:Xiaomi Corporation Mi monitor 5505610117971"
        "8, monitor:desc:Xiaomi Corporation Mi monitor 5505610117971"
        "9, monitor:desc:Xiaomi Corporation Mi monitor 5505610117971"
        "10, monitor:desc:Xiaomi Corporation Mi monitor 5505610117971"
        "11, monitor:desc:Microstep MSI MAG241C 0x00000010, default:true"
        "12, monitor:desc:Microstep MSI MAG241C 0x00000010"
        "13, monitor:desc:Microstep MSI MAG241C 0x00000010"
        "14, monitor:desc:Microstep MSI MAG241C 0x00000010"
        "15, monitor:desc:Microstep MSI MAG241C 0x00000010"
      ];

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
        "nm-applet --indicator"
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

      general = {
        gaps_in = 5;
        gaps_out = 20;
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
        ];
      };

      misc = { force_default_wallpaper = 0; disable_hyprland_logo = true; vrr = 2; };

      render = {
        direct_scanout = false;
      };
      dwindle = { preserve_split = true; };


      bind = [
        "$mainMod, C, exec, $terminal"
        "$mainMod, B, exec, brave"
        "$mainMod, G, exec, brave --app=https://gemini.google.com"
        "$mainMod, A, exec, brave --app=https://claude.ai/new"
        "$mainMod, N, exec, brave --app=https://www.notion.so/1b657c1d8c3f4c0d9d639b4996b092d0"
        "$mainMod ALT, P, exec, brave --app=https://calendar.notion.so/"
        
        "$mainMod, Y, exec, brave --app=https://www.youtube.com/"
        "$mainMod, S, exec, brave --app=https://open.spotify.com/intl-fr"
        "$mainMod, D, exec, discord-launcher"
        "$mainMod, R, exec, $menu"
        "$mainMod, E, exec, GDK_BACKEND=wayland nautilus --new-window"
        "$mainMod, W, exec, wallpaper-picker"
        "$mainMod, V, exec, clipboard-manager"
        "$mainMod, L, exec, hyprlock"
        "$mainMod, semicolon, exec, emoji-picker"
        "$mainMod, I, exec, kitty --class internet-check -e internet-check"
        "$mainMod, U, exec, $terminal --class nmtui -e nmtui"
        "$mainMod ALT, S, exec, audio-switch"
        "$mainMod, O, exec, pavucontrol"
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
        "$mainMod, X, togglespecialworkspace, magic" # J'ai changé S en X car S est pris par Spotify
        "$mainMod SHIFT, X, movetoworkspace, special:magic"

        # Switch bureaux avec Super+Tab (par moniteur)
        "$mainMod, Tab, workspace, m+1"
        "$mainMod SHIFT, Tab, workspace, m-1"

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
        "match:class waybar, match:float 1, match:title ^$, no_focus 1"
        "match:class nmtui, float 1"
        "match:class nmtui, size 700 500"
        "match:class nmtui, center 1"
        "match:class pavucontrol, float 1"
        "match:class pavucontrol, size 700 500"
        "match:class pavucontrol, center 1"
        "match:class pavucontrol, animation popin"
        "match:title wlogout, float 1"
        "match:title wlogout, center 1"

        # Menu réseau : fenêtre flottante centrée avec animation popin
        "match:class network-menu, float 1"
        "match:class network-menu, center 1"
        "match:class network-menu, animation popin"

        # Menu Ethernet : fenêtre flottante centrée avec animation popin
        "match:class ethernet-menu, float 1"
        "match:class ethernet-menu, center 1"
        "match:class ethernet-menu, animation popin"

        # Vérification internet : terminal flottant centré
        "match:class internet-check, float 1"
        "match:class internet-check, size 560 340"
        "match:class internet-check, center 1"
        "match:class internet-check, animation popin"

        # Menu Notion TO DO
        "match:class notion-todo, float 1"
        "match:class notion-todo, center 1"
        "match:class notion-todo, animation popin"
      ];
      layerrule = [
        "blur on, match:namespace waybar"
        "ignore_alpha 0.1, match:namespace waybar"
        "blur on, match:namespace swaync"
        "ignore_alpha 0.1, match:namespace swaync"
        "blur on, match:namespace swaync-notification-window"
        "ignore_alpha 0.1, match:namespace swaync-notification-window"
        "blur on, match:namespace swaync-control-center"
        "ignore_alpha 0.1, match:namespace swaync-control-center"
        "blur on, match:namespace launcher"
        "blur on, match:namespace wofi"
        "ignore_alpha 0.1, match:namespace wofi"
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
        no_fade_in = false;
        no_fade_out = false;
        grace = 0;
        ignore_empty_input = true;
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
          fade_on_empty = true;
          placeholder_text = "";
          hide_input = false;
          position = "0, -120";
          halign = "center";
          valign = "center";
        }
      ];

      label = [
        # Heure
        {
          text = "$TIME";
          color = "rgba(255, 255, 255, 0.9)";
          font_size = 120;
          font_family = "League Spartan Bold";
          position = "0, 80";
          halign = "center";
          valign = "center";
          shadow_passes = 3;
          shadow_size = 15;
          shadow_color = "rgba(255, 255, 255, 0.3)";
          shadow_boost = 1.2;
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
        # Batterie
        {
          text = "cmd[update:1000] echo \"$(cat /sys/class/power_supply/BAT*/capacity | head -n 1)% 󰁹\"";
          # Couleur dynamique : Vert (>70), Jaune (>25), Rouge (<=25)
          color = "cmd[update:1000] CAP=$(cat /sys/class/power_supply/BAT*/capacity | head -n 1); if [ $CAP -gt 70 ]; then echo \"rgba(166, 227, 161, 0.8)\"; elif [ $CAP -gt 25 ]; then echo \"rgba(249, 226, 175, 0.8)\"; else echo \"rgba(243, 139, 168, 0.8)\"; fi";
          font_size = 16;
          font_family = "Inter";
          position = "0, -45";
          halign = "center";
          valign = "center";
        }
        # Météo
        {
          text = "cmd[update:1800000] ${pkgs.curl}/bin/curl -s 'wttr.in/?format=%c+%t' 2>/dev/null | tr -d '+' || echo ''";
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
      # Thème parapluie : look Papirus + fallback icônes stock GTK (gnome-icon-theme)
      # pour les vieilles apps comme VMware (barres d'outils vides sinon)
      name = "Papirus-Stock";
      package = pkgs.papirus-icon-theme;
    };
  };

  # Thème d'icônes agrégateur : hérite Papirus-Dark puis gnome (stock) puis hicolor
  xdg.dataFile."icons/Papirus-Stock/index.theme".text = ''
    [Icon Theme]
    Name=Papirus-Stock
    Comment=Papirus-Dark avec fallback icônes stock GTK
    Inherits=Papirus-Dark,gnome,hicolor
    Directories=
  '';

  # ==========================================================================
  # BTS SIO — Correctifs applications
  # ==========================================================================

  xdg.desktopEntries.google-drive = {
    name = "Google Drive";
    comment = "Ouvrir Google Drive";
    exec = "brave --app=https://drive.google.com";
    terminal = false;
    type = "Application";
    icon = "google-drive";
    startupNotify = true;
    categories = [ "Network" "WebBrowser" ];
  };

  xdg.desktopEntries.whatsapp = {
    name = "WhatsApp";
    comment = "Ouvrir WhatsApp Web";
    exec = "brave --app=https://web.whatsapp.com";
    terminal = false;
    type = "Application";
    icon = "whatsapp";
    startupNotify = true;
    categories = [ "Network" "InstantMessaging" ];
  };

  # VMware : forcer XWayland + thème Adwaita pour les icônes GTK stock dépréciées
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
