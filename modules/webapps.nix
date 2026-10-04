{ config, pkgs, lib, ... }:

let
  # Applis web (brave --app) créées par la commande `webapp` :
  # liste dans webapps/apps.json, icônes (favicon du site) dans webapps/icons/
  # Champs optionnels par appli : comment, categories (défaut [ "Network" ])
  apps = builtins.fromJSON (builtins.readFile ./webapps/apps.json);

  #   webapp <url> [nom]   récupère l'icône, demande le nom, crée l'appli, rebuild
  #   webapp -l            liste les applis web
  #   webapp -r [filtre]   retire une appli (sélection fzf), rebuild
  # Rebuild raté → apps.json et icônes restaurés.
  webapp = pkgs.writeShellScriptBin "webapp" ''
    set -u
    DIR=/etc/nixos/modules/webapps
    JSON=$DIR/apps.json
    JQ=${pkgs.jq}/bin/jq
    PY="${pkgs.python3.withPackages (p: [ p.pillow ])}/bin/python3 ${../assets/webapp.py}"
    G=$'\e[32m'; C=$'\e[36m'; Y=$'\e[33m'; R=$'\e[0m'

    usage() {
      echo "Usage : webapp <url> [nom]    créer une appli web"
      echo "        webapp -l             lister les applis web"
      echo "        webapp -r [filtre]    retirer une appli web"
    }

    # Sauvegarde apps.json + icônes, rebuild ; échec → restauration
    rebuild() {
      SAUVEGARDE=$(mktemp -d)
      cp -a "$DIR/." "$SAUVEGARDE/"
      "$@"
      # Flake : les nouveaux fichiers doivent être suivis par git pour être vus
      git -C /etc/nixos add -A "$DIR"
      echo "''${C}󰑓''${R} Rebuild en cours..."
      if sudo /run/current-system/sw/bin/nixos-rebuild switch --flake /etc/nixos#pc1; then
        rm -rf "$SAUVEGARDE"
        return 0
      fi
      rm -rf "$DIR"; mkdir -p "$DIR"; cp -a "$SAUVEGARDE/." "$DIR/"
      git -C /etc/nixos add -A "$DIR"
      rm -rf "$SAUVEGARDE"
      echo "''${Y}󰅚''${R} Rebuild échoué — applis web restaurées, rien n'a changé." >&2
      exit 1
    }

    case "''${1:-}" in
      ""|-h|--help) usage; exit 0 ;;

      -l|--list)
        $JQ -r '.[] | "\(.name)\t\(.url)"' "$JSON" | ${pkgs.util-linux}/bin/column -t -s $'\t' -o '  '
        exit 0 ;;

      -r|--remove)
        CHOIX=$($JQ -r '.[] | "\(.id)\t\(.name)\t\(.url)"' "$JSON" \
          | ${pkgs.util-linux}/bin/column -t -s $'\t' -o '  ' \
          | ${pkgs.fzf}/bin/fzf --reverse --height=50% --query="''${2:-}" \
              --with-nth=2.. --prompt="retirer > " --header="Entrée = retirer · Échap = quitter")
        [ -z "$CHOIX" ] && { echo "Annulé."; exit 0; }
        ID=$(printf '%s\n' "$CHOIX" | ${pkgs.gawk}/bin/awk '{print $1}')
        NOM=$($JQ -r --arg id "$ID" '.[] | select(.id == $id) | .name' "$JSON")
        read -r -p "Retirer l'appli « $NOM » ? [o/N] " rep
        [[ "$rep" =~ ^[oOyY]$ ]] || { echo "Annulé."; exit 0; }

        retirer() {
          rm -f "$DIR/icons/$($JQ -r --arg id "$ID" '.[] | select(.id == $id) | .icon' "$JSON")"
          $JQ --arg id "$ID" 'map(select(.id != $id))' "$SAUVEGARDE/apps.json" > "$JSON"
        }
        rebuild retirer
        echo "''${G}󰄬''${R} Appli « $NOM » retirée"
        ${pkgs.libnotify}/bin/notify-send "Applis web" "Retirée : $NOM"
        exit 0 ;;

      -*) usage >&2; exit 1 ;;
    esac

    URL="$1"; shift; NOM="$*"
    [[ "$URL" =~ ^https?:// ]] || URL="https://$URL"
    # Caractères qui casseraient la ligne Exec= du .desktop
    if [[ "$URL" =~ [[:space:]\"\`\$\\] ]]; then
      echo "''${Y}󰅚''${R} URL invalide (espace, guillemet, \$ ou \\ interdits)." >&2; exit 1
    fi

    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    echo "''${C}󰖟''${R} Récupération de l'icône de $URL..."
    SORTIE=$($PY fetch "$URL" "$TMP/icone") || exit 1
    ICONE=$(sed -n 1p <<<"$SORTIE")
    SUGGERE=$(sed -n 2p <<<"$SORTIE")
    echo "''${G}󰄬''${R} Icône trouvée : ''${ICONE##*.}"

    [ -z "$NOM" ] && read -r -e -p "Nom de l'appli : " -i "$SUGGERE" NOM
    [ -z "$NOM" ] && { echo "Annulé."; exit 0; }
    ID=$($PY slug "$NOM")

    if $JQ -e --arg id "$ID" 'any(.id == $id)' "$JSON" >/dev/null; then
      read -r -p "L'appli « $ID » existe déjà, la remplacer ? [o/N] " rep
      [[ "$rep" =~ ^[oOyY]$ ]] || { echo "Annulé."; exit 0; }
    fi

    ajouter() {
      mkdir -p "$DIR/icons"
      rm -f "$DIR/icons/$ID".*
      cp "$ICONE" "$DIR/icons/$ID.''${ICONE##*.}"
      $JQ --arg id "$ID" --arg n "$NOM" --arg u "$URL" --arg i "$ID.''${ICONE##*.}" \
        'map(select(.id != $id)) + [{id: $id, name: $n, url: $u, icon: $i}] | sort_by(.name | ascii_downcase)' \
        "$SAUVEGARDE/apps.json" > "$JSON"
    }
    rebuild ajouter
    echo "''${G}󰄬''${R} Appli « $NOM » créée — dispo dans le menu (SUPER+R)"
    ${pkgs.libnotify}/bin/notify-send -i "$DIR/icons/$ID.''${ICONE##*.}" "Applis web" "Créée : $NOM"
  '';
in
{
  home.packages = [ webapp ];

  xdg.desktopEntries = lib.listToAttrs (map (a: lib.nameValuePair "webapp-${a.id}" {
    name = a.name;
    comment = a.comment or "Ouvrir ${a.name} (appli web)";
    # % doit être doublé dans une ligne Exec= de .desktop
    exec = ''brave "--app=${lib.replaceStrings [ "%" ] [ "%%" ] a.url}"'';
    terminal = false;
    type = "Application";
    # Chemin absolu dans le store : pas de collision possible avec une icône Papirus
    icon = "${./webapps/icons + "/${a.icon}"}";
    startupNotify = true;
    categories = a.categories or [ "Network" ];
  }) apps);
}
