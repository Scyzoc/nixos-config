{ pkgs, ... }:

let
  # Commande `cli` : liste les outils en ligne de commande installés, par catégorie.
  # Seuls les outils réellement présents dans le PATH sont affichés.
  # Usage : cli            → toutes les catégories
  #         cli <filtre>   → seulement les catégories dont le nom contient <filtre>
  cliList = pkgs.writeShellScriptBin "cli" ''
    set -u
    FILTRE="''${1:-}"
    FILTRE="''${FILTRE,,}"

    B=$'\e[1m'; C=$'\e[36m'; G=$'\e[32m'; D=$'\e[2m'; R=$'\e[0m'
    TOTAL=0

    # section "Nom de la catégorie" "outil|description" ...
    section() {
      local titre="$1"; shift
      if [ -n "$FILTRE" ] && [[ "''${titre,,}" != *"$FILTRE"* ]]; then
        return
      fi
      local lignes=() entree nom desc
      for entree in "$@"; do
        nom="''${entree%%|*}"
        desc="''${entree#*|}"
        if command -v "$nom" >/dev/null 2>&1; then
          lignes+=("$(printf '  %s%-22s%s %s' "$G" "$nom" "$R" "$desc")")
        fi
      done
      [ ''${#lignes[@]} -eq 0 ] && return
      printf '\n%s%s▸ %s%s %s(%d)%s\n' "$B" "$C" "$titre" "$R" "$D" "''${#lignes[@]}" "$R"
      printf '%s\n' "''${lignes[@]}"
      TOTAL=$((TOTAL + ''${#lignes[@]}))
    }

    # dossier "Nom" /chemin/bin : liste brute d'un dossier de binaires hors Nix
    dossier() {
      local titre="$1" dir="$2"
      if [ -n "$FILTRE" ] && [[ "''${titre,,}" != *"$FILTRE"* ]]; then
        return
      fi
      [ -d "$dir" ] || return
      local bins=()
      mapfile -t bins < <(${pkgs.coreutils}/bin/ls -1 "$dir" 2>/dev/null)
      [ ''${#bins[@]} -eq 0 ] && return
      printf '\n%s%s▸ %s%s %s(%s)%s\n' "$B" "$C" "$titre" "$R" "$D" "$dir" "$R"
      local b
      for b in "''${bins[@]}"; do
        printf '  %s%s%s\n' "$G" "$b" "$R"
      done
      TOTAL=$((TOTAL + ''${#bins[@]}))
    }

    section "Base" \
      "vim|Éditeur de texte" \
      "wget|Téléchargement HTTP/FTP" \
      "curl|Requêtes HTTP" \
      "unzip|Décompression zip" \
      "zip|Compression zip" \
      "unrar|Décompression rar" \
      "unar|Extraction toutes archives" \
      "7z|Archives 7-Zip" \
      "jq|Manipulation JSON" \
      "tree|Arborescence de dossiers" \
      "rsync|Synchronisation de fichiers" \
      "screen|Multiplexeur de terminal" \
      "pkill|Tuer un processus par nom" \
      "pgrep|Chercher un processus par nom"

    section "Système et monitoring" \
      "htop|Moniteur de processus" \
      "btop|Moniteur système complet" \
      "gdu|Analyse d'espace disque" \
      "fastfetch|Infos système" \
      "cpupower|Gestion fréquence CPU" \
      "brightnessctl|Luminosité écran" \
      "systemctl|Gestion des services" \
      "journalctl|Logs systemd" \
      "lazydocker|Interface TUI Docker" \
      "docker|Conteneurs" \
      "wine|Lancer des .exe Windows" \
      "cmatrix|Effet Matrix"

    section "Réseau" \
      "nmcli|NetworkManager en CLI" \
      "iw|Configuration Wi-Fi" \
      "ethtool|Configuration Ethernet" \
      "ip|Interfaces et routes" \
      "dig|Requêtes DNS" \
      "nslookup|Requêtes DNS" \
      "nc|Netcat" \
      "ssh|Connexion distante" \
      "wg-quick|WireGuard" \
      "openvpn|Client OpenVPN" \
      "tshark|Wireshark en CLI" \
      "kdeconnect-cli|KDE Connect"

    section "Cyber" \
      "dirb|Brute-force de répertoires web" \
      "nmap|Scan réseau"

    section "Développement" \
      "git|Gestion de versions" \
      "gh|GitHub CLI" \
      "node|Node.js" \
      "npm|Gestionnaire de paquets Node" \
      "python3|Python" \
      "uv|Gestionnaire Python rapide" \
      "uvx|Lancer un outil Python" \
      "vercel|Déploiement Vercel"

    section "IA" \
      "claude|Claude Code" \
      "claude-monitor|Suivi d'usage Claude" \
      "gemini|Gemini CLI" \
      "opencode|Agent de code" \
      "graphify|Graphe de connaissances"

    section "NixOS" \
      "nixos-rebuild|Reconstruire le système" \
      "nix|CLI Nix (flakes)" \
      "home-manager|Home-manager" \
      "nixsave|Sauvegarde de la config" \
      "nixfix|Réparation de la config" \
      "check-nixos-updates|Vérifier les mises à jour" \
      "driver-update|Mise à jour pilotes"

    section "Shell et terminal" \
      "kitty|Terminal" \
      "starship|Prompt" \
      "eza|ls moderne"

    section "Wayland et Hyprland" \
      "hyprctl|Contrôle Hyprland" \
      "hyprlock|Écran de verrouillage" \
      "hypridle|Gestion inactivité" \
      "grim|Capture d'écran" \
      "slurp|Sélection de zone" \
      "wayfreeze|Figer l'écran" \
      "swappy|Annoter une capture" \
      "wl-copy|Copier dans le presse-papier" \
      "wl-paste|Coller le presse-papier" \
      "cliphist|Historique presse-papier" \
      "wtype|Simuler la frappe clavier" \
      "playerctl|Contrôle lecteurs média" \
      "wpctl|Contrôle audio PipeWire" \
      "awww|Fond d'écran" \
      "rofi|Lanceur / menus" \
      "notify-send|Envoyer une notification" \
      "swaync-client|Centre de notifications" \
      "magick|ImageMagick" \
      "xhost|Accès X11"

    section "Scripts perso — accès distant" \
      "homelab|SSH homelab (monte le VPN si besoin)" \
      "wakepc|Réveiller le PC Windows (WoL)" \
      "pcoff|Éteindre le PC Windows" \
      "monip|Afficher l'IP publique" \
      "internet-check|Test de connexion internet" \
      "netfix|Diagnostic + réparation réseau"

    section "Scripts perso — bureau" \
      "cli|Cette liste" \
      "audio-switch|Basculer la sortie audio" \
      "screenshot|Capture d'écran" \
      "power-menu|Menu d'alimentation" \
      "veille|Mise en veille" \
      "console|Console" \
      "portail|Portail" \
      "theme|Changer de thème" \
      "wallpaper-picker|Choisir un fond d'écran" \
      "display-menu|Menu des écrans (SUPER+P)" \
      "extract-here|Extraire une archive" \
      "emoji-picker|Sélecteur d'emoji" \
      "clipboard-manager|Gestionnaire presse-papier" \
      "voice-to-text|Dictée vocale" \
      "notion-todo|Tâches Notion" \
      "ws-cycle|Cycler les workspaces" \
      "ws-compact|Compacter les workspaces" \
      "ws-move|Déplacer les fenêtres d'un workspace vers un autre"

    dossier "Hors Nix — nix profile" "$HOME/.nix-profile/bin"
    dossier "Hors Nix — npm global" "$HOME/.npm-global/bin"
    dossier "Hors Nix — ~/.local/bin" "$HOME/.local/bin"

    if [ "$TOTAL" -eq 0 ]; then
      echo "Aucune catégorie ne correspond à « $1 »."
      exit 1
    fi
    printf '\n%s%d outils%s\n' "$D" "$TOTAL" "$R"
  '';
in
{
  home.packages = [ cliList ];
}
