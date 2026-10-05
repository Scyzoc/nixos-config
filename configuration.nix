# Configuration système NixOS - ThinkPad L14 Gen 4 (iGPU Intel/AMD)

{ config, pkgs, lib, ... }:

{
  # ==========================================================================
  # 1. IMPORTS ET MATÉRIEL (HARDWARE)
  # ==========================================================================

  # Import de la configuration matérielle auto-générée
  imports = [
    # hardware-configuration.nix et networking.nix sont importés par hosts/pcX/default.nix
  ];

  # --- Bootloader (UEFI avec systemd-boot) ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # r8168 remplace r8169 pour corriger le hotplug câble Ethernet (bug r8169 sur RTL8111/8168)
  boot.extraModulePackages = [ config.boot.kernelPackages.vmware config.boot.kernelPackages.r8168 ];
  boot.blacklistedKernelModules = [ "r8169" ];
  boot.kernelModules = [ "vmmon" "vmnet" "r8168" ];
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelParams = [ "amdgpu.freesync_video=1" "amd_pstate=active" ];

  boot.kernel.sysctl = {
    # zram est rapide (RAM) → on swappe agressivement pour libérer le cache et gagner en fluidité
    "vm.swappiness" = 150;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_ratio" = 15;
    # zram = accès aléatoire : pas de readahead au swapin (réduit la latence)
    "vm.page-cluster" = 0;
  };



  # 3. AUCUNE passerelle par défaut (defaultGateway) 
  # car internet passe toujours par le Wi-Fi.

  services.ollama = {
    enable = true;
    package = pkgs.ollama;
  };
  systemd.services.ollama.wantedBy = lib.mkForce [];

  # Service RustDesk Server (désactivé — utilise le serveur public par défaut)
  # Pour réactiver : services.rustdesk-server = { enable = true; openFirewall = true; signal.enable = true; relay.enable = true; };
  services.rustdesk-server.enable = false;

  services.earlyoom.enable = true;

  # Mise à jour firmware (dock Lenovo, etc.) via LVFS
  services.fwupd.enable = true;

  # Index de fichiers pour la commande `locate` (plocate, mis à jour par timer)
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # Désactiver les monitors GVFS inutiles (Apple, appareils photo, Android/MTP)
  systemd.user.services.gvfs-afc-volume-monitor.wantedBy = lib.mkForce [];
  systemd.user.services.gvfs-gphoto2-volume-monitor.wantedBy = lib.mkForce [];
  systemd.user.services.gvfs-mtp-volume-monitor.wantedBy = lib.mkForce [];

  # TLP gère les gouverneurs CPU (performance sur secteur, powersave sur batterie)

  # ZRAM swap (8 GB compressé en RAM) — filet de sécurité contre les OOM kills
  zramSwap = {
    enable = true;
    algorithm = "zstd";  # bon ratio compression/vitesse
    memoryPercent = 50;  # 50% de 30 GB = ~15 GB swap compressé (zstd ~3:1 → réel élevé)
  };

  # earlyoom suffit (réactif, léger) — systemd-oomd ferait doublon
  systemd.oomd.enable = false;

  # ==========================================================================
  # 3. LOCALISATION (LANGUE, HEURE, CLAVIER)
  # ==========================================================================

  # Fuseau horaire
  time.timeZone = "Europe/Paris";

  # Locale par défaut (français)
  i18n.defaultLocale = "fr_FR.UTF-8";

  # Locales spécifiques (formats français pour dates, monnaie, etc.)
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };

  # Clavier AZERTY français (X11 + console)
  services.xserver.xkb = {
    layout = "fr";
    variant = "azerty";
  };
  console.keyMap = "fr";

  # ==========================================================================
  # 4. INTERFACE GRAPHIQUE (DISPLAY MANAGER + DESKTOP)
  # ==========================================================================

  # Xserver (base graphique)
  services.xserver.enable = true;

  # SDDM Display Manager (Screen Saver Display Manager) - écran de connexion
  services.displayManager.sddm.enable = false;

  # GDM Display Manager (GNOME Display Manager) - écran de connexion
  services.displayManager.gdm.enable = true;

  # Hyprland window manager (enabled at system level)
  programs.hyprland.enable = true;

  # GNOME Desktop Environment
  services.desktopManager.gnome.enable = true; # Re-enabled as Nautilus requires GNOME components

  # IBus (méthode de saisie CJK) activé d'office par GNOME : inutile ici
  i18n.inputMethod.enable = lib.mkForce false;

  # Applis GNOME de base retirées (commande `uninstall`)
  environment.gnome.excludePackages = with pkgs; [
    gnome-calculator
    gnome-contacts
    gnome-characters
    yelp
    gnome-calendar
    gnome-disk-utility
    gnome-characters
    gnome-clocks
    gnome-weather
    gnome-maps
    gnome-font-viewer
    simple-scan
    seahorse
    gnome-music
    gnome-tour
    epiphany
  ];

  # GNOME services that might have been removed
  services.gvfs.enable = true;
  programs.dconf.enable = true;

  # Thunar (gestionnaire de fichiers) : programs.thunar tire xfconf, sans quoi
  # les réglages de Thunar ne sont jamais persistés.
  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.tumbler.enable = true; # miniatures

  # Portail XDG pour Hyprland et GTK
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
    config.common = {
      default = [ "hyprland" "gtk" ];
      # Le portail GTK implémente Settings (color-scheme) — hyprland ne le fait pas
      "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
      # Boîtes Ouvrir/Enregistrer : dialogue KDE (style Dolphin) au lieu du GTK
      "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
    };
  };

  # ==========================================================================
  # 5. SON ET AUDIO (PipeWire)
  # ==========================================================================

  # Désactive PulseAudio (remplacé par PipeWire)
  services.pulseaudio.enable = false;

  # RTKit (gestion des priorités temps réel pour l'audio)
  security.rtkit.enable = true;

  # PipeWire (serveur audio moderne)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true; # Priorité temps réel pour réduire les drops du screen capture
    extraConfig.pipewire."92-low-latency" = {
      context.properties = {
        default.clock.rate = 48000;
        default.clock.quantum = 512;
        default.clock.min-quantum = 512;
        default.clock.max-quantum = 512;
      };
    };
    # Les applis suivent toujours la sortie par défaut : sans ça, WirePlumber
    # réapplique la sortie mémorisée par appli et changer de sortie (barre) ou
    # couper la sortie par défaut n'a aucun effet sur elles
    wireplumber.extraConfig."51-follow-default" = {
      "wireplumber.settings" = {
        "node.stream.restore-target" = false;
      };
    };
  };

  # ==========================================================================
  # Bluetooth
  # ==========================================================================

  hardware.bluetooth.enable = true; # Active le démon système Bluetooth
  hardware.bluetooth.powerOnBoot = true; # Allume la puce au démarrage

  # Firmware redistribuable (inclut les firmwares Realtek r8169 pour la carte Ethernet)
  hardware.enableRedistributableFirmware = true;
  
  # Gestionnaire graphique/applet (fournit la commande blueman-manager)
  services.blueman.enable = true;


  # ==========================================================================
  # 6. GRAPHISMES (GPU)
  # ==========================================================================

  # Support OpenGL + VAAPI (iGPU AMD du ThinkPad L14 Gen 4)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa                # drivers AMD (radeonsi) + VAAPI out-of-the-box
      libva-utils         # vainfo — diagnostic accélération vidéo
      libva-vdpau-driver  # pont VAAPI→VDPAU (compatibilité applications)
      libvdpau-va-gl      # pont VDPAU→VAAPI→OpenGL
    ];
  };

  # NOTE : Pas de pilotes NVIDIA car le L14 Gen 4 utilise un iGPU AMD

  # ==========================================================================
  # 7. IMPRESSION
  # ==========================================================================

  services.printing.enable = false;
  services.avahi.enable = false;
  systemd.services.ModemManager.enable = false;

  # ==========================================================================
  # 8. GESTION DE L'ALIMENTATION (BATTERIE LAPTOP)
  # ==========================================================================

  # Désactive power-profiles-daemon (conflit avec TLP)
  services.power-profiles-daemon.enable = false;

  # Fermeture du capot : suspendre (hypridle verrouille avant le suspend)
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  # TLP (gestion avancée de l'alimentation)
  services.tlp = {
    enable = true;
    settings = {
      # Gouverneur CPU
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      # Politique d'énergie CPU
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      # Seuils de charge : gérés par battery-limit.nix (réglables depuis la barre)
    };
  };

  # ==========================================================================
  # 9. POLICES (FONTS)
  # ==========================================================================

  fonts.packages = with pkgs; [
    # Apple Color Emoji (fichier local)
    (runCommand "apple-color-emoji" { } ''
      mkdir -p $out/share/fonts/truetype
      cp ${./fonts/AppleColorEmoji.ttf} $out/share/fonts/truetype/AppleColorEmoji.ttf
    '')

    # JetBrainsMono Nerd Font (icônes + terminal)
    nerd-fonts.jetbrains-mono

    # Figtree : titre du morceau (barre Quickshell)
    figtree

    # Inter : horloge et date (barre Quickshell)
    inter

    # BatteryIcons : icônes batterie custom (barre Quickshell + hyprlock)
    (runCommand "battery-icons-font" {
      nativeBuildInputs = [ (python3.withPackages (p: [ p.fonttools p.skia-pathops ])) ];
    } ''
      mkdir -p $out/share/fonts/opentype
      python3 ${./assets/battery-icons-font.py} $out/share/fonts/opentype/BatteryIcons.otf
    '')

    # DeviceIcons : icônes d'appareils Bluetooth maison (barre Quickshell)
    (runCommand "device-icons-font" {
      nativeBuildInputs = [ (python3.withPackages (p: [ p.fonttools ])) ];
    } ''
      mkdir -p $out/share/fonts/opentype
      python3 ${./assets/device-icons-font.py} ${./assets/earbuds.svg} $out/share/fonts/opentype/DeviceIcons.otf
    '')
  ];

  # Police emoji par défaut
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      emoji = [ "Apple Color Emoji" ];
    };
  };

  # ==========================================================================
  # 10. UTILISATEURS
  # ==========================================================================
  
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    # Claviers Keychron (VID 3434) : accès hidraw pour les configurateurs web
    # (Keychron Launcher / VIA) qui utilisent WebHID depuis le navigateur
    KERNEL=="hidraw*", ATTRS{idVendor}=="3434", MODE="0660", GROUP="input", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", MODE="0660", GROUP="input", TAG+="uaccess"
  '';

  users.groups.uinput = {};
  users.groups.vmware = {};

  users.users.user = {
    isNormalUser = true;
    uid = 1000;
    group = "users";
    home = "/home/user";
    shell = pkgs.bash;
    description = "user";
    extraGroups = [
      "networkmanager"  # Gestion du réseau
      "wheel"           # Accès sudo
      "video"           # Accès matériel vidéo
      "audio"           # Accès matériel audio
      "input"
      "render"
      "vmware"
      "wireshark"       # Capture réseau sans root
      "dialout"         # Accès ports série (câble console switch/routeur)
      "docker"
    ];
  };

  # ==========================================================================
  # BTS SIO — Outils professionnels
  # ==========================================================================

  # --- Cisco Packet Tracer (nécessite le .deb téléchargé manuellement) ---
  nixpkgs.config.permittedInsecurePackages = [
  #  "cisco-packet-tracer-9.0.0"
    "ventoy-1.1.17"  # Ventoy : composants tiers avec CVE connues, autorisé pour flashage USB
  ];

  # --- VMware Workstation ---
  virtualisation.vmware.host = {
    enable = true;
    extraConfig = "";
  };

  # VMware livre les icônes de sa barre d'outils dans son propre thème hicolor,
  # hors des chemins XDG standard. Variable système : héritée par la session
  # graphique (home.sessionVariables ne l'est pas depuis greetd/Hyprland).
  environment.sessionVariables.XDG_DATA_DIRS = [
    "${pkgs.vmware-workstation}/lib/vmware/share"
  ];

  # --- Docker ---
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers.portainer = {
      image = "portainer/portainer-ce:latest";
      autoStart = true;
      ports = [ "9000:9000" "9443:9443" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "portainer_data:/data"
      ];
    };
  };

  # --- Wireshark (capture réseau) ---
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  # ==========================================================================
  # 11. PROGRAMMES GLOBAUX (SYSTÈME)
  # ==========================================================================

  # Git au niveau système
  programs.git.enable = true;

  # nix-ld : exécuter binaires dynamiques génériques (ex: installeur natif claude)
  programs.nix-ld.enable = true;

  # KDE Connect (transferts fichiers iPhone/PC)
  programs.kdeconnect.enable = true;

  # Hyprland (activé au niveau système)
  # programs.hyprland.enable = true; # Already enabled

  # Autoriser les paquets non-libres (Spotify, Discord, etc.)
  nixpkgs.config.allowUnfree = true;

  # --- Paquets système disponibles pour tous les utilisateurs ---
  environment.systemPackages = with pkgs; [
    # --- Éditeurs et utilitaires de base ---
    vim
    wget
    ncurses
    unzip
    ethtool
    gparted

    # --- Création clé USB bootable (alternative Rufus) ---
    ventoy-full  # GUI multiboot : copie plusieurs ISO (Windows, Debian, Tails…)

    # --- Notifications ---
    libnotify
    swaynotificationcenter

    # --- Capture d'écran ---

    # --- Réseau ---
    networkmanagerapplet
    networkmanager-openvpn

    # --- Processus (pkill, pgrep) ---
    procps

    # --- Gestion alimentation manuelle ---
    linuxPackages.cpupower
    iw
    jq

    # --- Lanceur d'applications ---
    rofi
    league-spartan

    # --- Cyber ---
    dirb  # Brute-force de répertoires web

    # --- Développement web ---
    playwright-test  # CLI playwright (ex : playwright open --device="iPhone 15" http://localhost:5173)

    # --- BTS SIO ---
    #ciscoPacketTracer9  # Cisco Packet Tracer (VMware et Wireshark → section BTS SIO)
    gnome-themes-extra  # Thème Adwaita avec icônes GTK stock pour VMware
  ];

  # ==========================================================================
  # 12. CONFIGURATION NIX (FLAKES ET OPTIMISATIONS)
  # ==========================================================================

  # Autoriser nixos-rebuild sans mot de passe pour user
  security.sudo.extraConfig = ''
    user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/nixos-rebuild
    user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/git
    user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/cpupower
    user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/wg-quick up proton
    user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/wg-quick down proton
    user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/systemctl start openvpn-maison
    user ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/systemctl stop openvpn-maison
  '';
  # ==========================================================================

  # Activer les fonctionnalités expérimentales (flakes + nouvelle CLI)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Optimisation du stockage (déduplication des paquets)
  nix.settings.auto-optimise-store = true;

  # Garbage collection automatique : on ne garde que les 5 dernières générations.
  # `nix-collect-garbage` ne sait pas compter les générations, donc on supprime
  # d'abord les anciennes avec `nix-env --delete-generations +5` (système et
  # home-manager), puis le GC nettoie les chemins devenus inutilisés.
  # Limiter la taille du journal systemd
  services.journald.settings.Journal.SystemMaxUse = "200M";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    # Vide : le tri des générations est fait par ExecStartPre ("0d" est refusé par nix-collect-garbage)
    options = "";
  };

  # home-manager est un module NixOS : ses générations sont incluses dans celles du système
  systemd.services.nix-gc.serviceConfig.ExecStartPre = [
    "-${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5"
  ];

  # Ne garder que 5 entrées dans le menu de démarrage
  boot.loader.systemd-boot.configurationLimit = 5;

  # WireGuard — config ProtonVPN dans /etc/wireguard/proton.conf (hors git)
  networking.wg-quick.interfaces.proton = {
    configFile = "/etc/wireguard/proton.conf";
    autostart = false;
  };

  # Brave : Shields coupés sur SoundCloud, sinon l'anti-bot DataDome bloque
  # la connexion ("Accès temporairement restreint")
  # environment.etc."brave/policies/managed/shields.json".text = builtins.toJSON {
  #   BraveShieldsDisabledForUrls = [ "[*.]soundcloud.com" ];
  # };

  # Dispatcher NM : set MAC fixe sur tap0 après connexion VPN maison
  environment.etc."NetworkManager/dispatcher.d/99-maison-mac" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      ACTION="$2"
      if [ "$ACTION" = "vpn-up" ] && [ -n "$VPN_IP_IFACE" ]; then
        ${pkgs.iproute2}/bin/ip link set "$VPN_IP_IFACE" address 02:00:00:00:00:01
        ${pkgs.iproute2}/bin/ip link set "$VPN_IP_IFACE" up
        ${pkgs.dhcpcd}/bin/dhcpcd -k "$VPN_IP_IFACE" 2>/dev/null || true
        ${pkgs.dhcpcd}/bin/dhcpcd --nobackground --oneshot -4 --noipv4ll -t 30 "$VPN_IP_IFACE"
        # Route par defaut via le tunnel : metric bas pour battre le Wi-Fi (600)
        GW=$(${pkgs.iproute2}/bin/ip -4 route show default dev "$VPN_IP_IFACE" | ${pkgs.gawk}/bin/awk '$2=="via"{print $3; exit}')
        if [ -n "$GW" ]; then
          ${pkgs.iproute2}/bin/ip -4 route show default dev "$VPN_IP_IFACE" | while read -r R; do
            ${pkgs.iproute2}/bin/ip -4 route del $R || true
          done
          ${pkgs.iproute2}/bin/ip -4 route add default via "$GW" dev "$VPN_IP_IFACE" metric 50
        fi
        # DNS = AdGuard exclusif -> .lan + adblock via VPN
        printf 'nameserver HOMELAB_IP_REDACTED\n' | ${pkgs.openresolv}/bin/resolvconf -a "$VPN_IP_IFACE.ovpn" -x
      fi
      if [ "$ACTION" = "vpn-down" ]; then
        # Balayage : l'iface peut deja avoir disparu, on retire toute entree tapN.ovpn
        # openresolv range les entrees -x dans /run/resolvconf/exclusive, pas
        # dans interfaces/ : on liste les interfaces connues plutot que globber
        for IF in $(${pkgs.openresolv}/bin/resolvconf -i 2>/dev/null); do
          case "$IF" in
            tap*.ovpn) ${pkgs.openresolv}/bin/resolvconf -d "$IF" || true ;;
          esac
        done
      fi
    '';
  };

  # Dispatcher NM : coupe les VPN (proton + maison) quand le Wi-Fi tombe
  environment.etc."NetworkManager/dispatcher.d/98-vpn-wifi-down" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      IFACE="$1"
      ACTION="$2"
      case "$IFACE" in
        wl*)
          if [ "$ACTION" = "down" ]; then
            ${pkgs.systemd}/bin/systemctl stop wg-quick-proton.service openvpn-maison.service || true
          fi
          ;;
      esac
    '';
  };

  # OpenVPN — VPN maison (routeur, IP fixe)
  services.openvpn.servers.maison = {
    config = ''
      client
      dev tap
      proto udp
      remote VPN_HOST_REDACTED VPN_PORT_REDACTED
      resolv-retry infinite
      nobind
      persist-key
      persist-tun
      ca /etc/nixos/vpn/ca.crt
      cert /etc/nixos/vpn/client.crt
      key /etc/nixos/vpn/client.key
      cipher AES-128-CBC
      data-ciphers AES-128-CBC
      comp-lzo
      allow-compression yes
      route-nopull
      script-security 2
      verb 0
      sndbuf 393216
      rcvbuf 393216
    '';
    autoStart = false;
    up = ''
      ${pkgs.iproute2}/bin/ip link set $dev address 02:00:00:00:00:01
      ${pkgs.iproute2}/bin/ip link set $dev up
      # Route hote vers le serveur VPN via la passerelle actuelle : sans elle,
      # la route par defaut metric 50 renverrait le trafic chiffre dans le tunnel
      ${pkgs.iproute2}/bin/ip -4 route del "$trusted_ip/32" 2>/dev/null || true
      SRV=$(${pkgs.iproute2}/bin/ip -4 route get "$trusted_ip" | ${pkgs.gawk}/bin/awk '{for(i=1;i<NF;i++){if($i=="via")v=$(i+1);if($i=="dev")d=$(i+1)}} END{print v, d}')
      set -- $SRV
      [ -n "$1" ] && [ -n "$2" ] && ${pkgs.iproute2}/bin/ip -4 route replace "$trusted_ip/32" via "$1" dev "$2"
      # Pas d'IPv6 hors tunnel (le Wi-Fi fuiterait l'IP publique) : route
      # « unreachable » prioritaire -> les applis retombent tout de suite sur l'IPv4
      ${pkgs.iproute2}/bin/ip -6 route replace unreachable default metric 1
      # En arriere-plan : openvpn est bloque tant que ce script tourne, la
      # reponse DHCP ne traverserait jamais le tunnel si on l'attendait ici
      (
        ${pkgs.dhcpcd}/bin/dhcpcd -k $dev 2>/dev/null || true
        ${pkgs.dhcpcd}/bin/dhcpcd --nobackground --oneshot -4 --noipv4ll -t 30 $dev
        # Route par defaut via le tunnel : metric bas pour battre le Wi-Fi (600)
        GW=$(${pkgs.iproute2}/bin/ip -4 route show default dev $dev | ${pkgs.gawk}/bin/awk '$2=="via"{print $3; exit}')
        if [ -n "$GW" ]; then
          ${pkgs.iproute2}/bin/ip -4 route show default dev $dev | while read -r R; do
            ${pkgs.iproute2}/bin/ip -4 route del $R || true
          done
          ${pkgs.iproute2}/bin/ip -4 route add default via "$GW" dev $dev metric 50
        fi
        # DNS = AdGuard homelab exclusif -> resout *.lan + ad-blocking via VPN
        printf 'nameserver HOMELAB_IP_REDACTED\n' | ${pkgs.openresolv}/bin/resolvconf -a "$dev.ovpn" -x
      ) </dev/null &
    '';
    down = ''
      ${pkgs.iproute2}/bin/ip -4 route del "$trusted_ip/32" 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 route del unreachable default metric 1 2>/dev/null || true
      # openresolv range les entrees -x dans /run/resolvconf/exclusive, pas
      # dans interfaces/ : on liste les interfaces connues plutot que globber
      for IF in $(${pkgs.openresolv}/bin/resolvconf -i 2>/dev/null); do
        case "$IF" in
          tap*.ovpn) ${pkgs.openresolv}/bin/resolvconf -d "$IF" || true ;;
        esac
      done
    '';
  };

  # Filet securite : si openvpn-maison s'arrete (stop/crash/kill/shutdown),
  # retire le DNS exclusif AdGuard -> resolv.conf revient au DNS local automatiquement
  systemd.services.openvpn-maison.serviceConfig.ExecStopPost =
    pkgs.writeShellScript "maison-dns-cleanup" ''
      ${pkgs.iproute2}/bin/ip -6 route del unreachable default metric 1 2>/dev/null || true
      # openresolv range les entrees -x dans /run/resolvconf/exclusive, pas
      # dans interfaces/ : on liste les interfaces connues plutot que globber
      for IF in $(${pkgs.openresolv}/bin/resolvconf -i 2>/dev/null); do
        case "$IF" in
          tap*.ovpn) ${pkgs.openresolv}/bin/resolvconf -d "$IF" || true ;;
        esac
      done
    '';

  # CA racine de Caddy (homelab) -> HTTPS *.lan de confiance (trust systeme)
  security.pki.certificateFiles = [ ./caddy-root.crt ];

  # Version de l'état du système (ne pas modifier après génération)
  system.stateVersion = "25.11";
}
