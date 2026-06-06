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
  boot.kernelParams = [ "amdgpu.freesync_video=1" ];



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

  # CPU Governor : schedutil pour un meilleur équilibre performance/batterie
  powerManagement.cpuFreqGovernor = "schedutil";

  # ZRAM swap (8 GB compressé en RAM) — filet de sécurité contre les OOM kills
  zramSwap = {
    enable = true;
    memoryPercent = 25; # 25% de 30 GB = ~7.5 GB de swap compressé
  };

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

  # GNOME services that might have been removed
  services.gvfs.enable = true;
  programs.dconf.enable = true;

  # Portail XDG pour Hyprland et GTK
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common = {
      default = [ "hyprland" "gtk" ];
      # Le portail GTK implémente Settings (color-scheme) — hyprland ne le fait pas
      "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
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

  # CapsLock → toggle couche numérique (comportement Windows AZERTY)
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          capslock = "toggle(numrow)";
        };
        numrow = {
          "1" = "1";
          "2" = "2";
          "3" = "3";
          "4" = "4";
          "5" = "5";
          "6" = "6";
          "7" = "7";
          "8" = "8";
          "9" = "9";
          "0" = "0";
          a = "A"; b = "B"; c = "C"; d = "D"; e = "E";
          f = "F"; g = "G"; h = "H"; i = "I"; j = "J";
          k = "K"; l = "L"; m = "M"; n = "N"; o = "O";
          p = "P"; q = "Q"; r = "R"; s = "S"; t = "T";
          u = "U"; v = "V"; w = "W"; x = "X"; y = "Y";
          z = "Z";
        };
      };
    };
  };

  # ==========================================================================
  # 8. GESTION DE L'ALIMENTATION (BATTERIE LAPTOP)
  # ==========================================================================

  # Désactive power-profiles-daemon (conflit avec TLP)
  services.power-profiles-daemon.enable = false;

  # Fermeture du capot : verrouiller l'écran
  services.logind.settings.Login = {
    HandleLidSwitch = "lock";
    HandleLidSwitchExternalPower = "lock";
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

      # Seuil de charge batterie (prolonge la durée de vie)
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
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
  '';

  users.groups.uinput = {};
  users.groups.vmware = {};

  users.users.user = {
    isNormalUser = true;
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
    ];
  };

  # ==========================================================================
  # BTS SIO — Outils professionnels
  # ==========================================================================

  # --- VMware Workstation ---
  virtualisation.vmware.host = {
    enable = true;
    extraConfig = "";
  };
  systemd.services.vmware-authdlauncher.wantedBy = lib.mkForce [];
  systemd.services.vmware-networks.wantedBy = lib.mkForce [];
  systemd.services.vmware-usbarbitrator.wantedBy = lib.mkForce [];

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

    # --- Notifications ---
    libnotify
    swaynotificationcenter

    # --- Capture d'écran ---
    swappy

    # --- Réseau ---
    networkmanagerapplet
    # --- Processus (pkill, pgrep) ---
    procps

    # --- Gestion alimentation manuelle ---
    linuxPackages.cpupower
    iw
    jq

    # --- Lanceur d'applications ---
    rofi
    league-spartan

    # --- BTS SIO ---
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
  '';
  # ==========================================================================

  # Activer les fonctionnalités expérimentales (flakes + nouvelle CLI)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Optimisation du stockage (déduplication des paquets)
  nix.settings.auto-optimise-store = true;

  # Garbage collection automatique (supprime les générations > 14 jours, chaque semaine)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Version de l'état du système (ne pas modifier après génération)
  system.stateVersion = "25.11";
}
