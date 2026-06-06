{ pkgs, ... }:

let
  # Descriptions EDID stables (ne changent pas au rebranché)
  xiaomiDesc = "Xiaomi Corporation Mi monitor 5505610117971";
  xiaomiRes  = "3440x1440@180.00";
  xiaomiPos  = "0x0";
  msiDesc    = "Microstep MSI MAG241C 0x00000010";
  msiRes     = "1920x1080@144";
  msiPos     = "3440x0";
  # Position du laptop sous le Xiaomi (centré horizontalement)
  laptopPos  = "1520x1440";

  # Fonctions shell partagées — utilisent desc: pour être indépendantes du nom de port.
  applyExtMonitor = ''
    XIAOMI_DESC="${xiaomiDesc}"
    XIAOMI_RES="${xiaomiRes}"
    XIAOMI_POS="${xiaomiPos}"
    MSI_DESC="${msiDesc}"
    MSI_RES="${msiRes}"
    MSI_POS="${msiPos}"
    LAPTOP_POS="${laptopPos}"

    get_mon_desc() {
      ${pkgs.hyprland}/bin/hyprctl monitors all -j | \
        ${pkgs.jq}/bin/jq -r --arg p "$1" '.[] | select(.name == $p) | .description'
    }

    # Place un écran externe à sa position fixe connue (ou en fallback à pos fournie)
    apply_ext_monitor() {
      local port="$1" fallback_pos="$2" desc
      desc=$(get_mon_desc "$port")
      if [ "$desc" = "$XIAOMI_DESC" ]; then
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "desc:$desc,''${XIAOMI_RES},''${XIAOMI_POS},1"
      elif [ "$desc" = "$MSI_DESC" ]; then
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "desc:$desc,''${MSI_RES},''${MSI_POS},1"
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "desc:$desc,transform,3"
      else
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "desc:$desc,preferred,''${fallback_pos}x0,1"
      fi
    }

    apply_ext_mirror() {
      local port="$1" res="$2" scale="$3" internal="$4" desc
      desc=$(get_mon_desc "$port")
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "desc:$desc,''${res},0x0,''${scale},mirror,''${internal}"
    }

    disable_ext_monitor() {
      local port="$1" desc
      desc=$(get_mon_desc "$port")
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "desc:$desc,disable"
    }

    # Déplace tous les workspaces d'un moniteur source vers un moniteur cible
    move_workspaces_to_monitor() {
      local src="$1" dst="$2"
      ${pkgs.hyprland}/bin/hyprctl workspaces -j | \
        ${pkgs.jq}/bin/jq -r --arg m "$src" '.[] | select(.monitor == $m) | .id' | \
        while read -r ws; do
          ${pkgs.hyprland}/bin/hyprctl dispatch moveworkspacetomonitor "$ws" "$dst"
        done
    }
  '';

  monitor-watcher = pkgs.writeShellScriptBin "monitor-watcher" ''
    INTERNAL="eDP-1"
    INT_RES="1920x1080@60"
    INT_SCALE="1"
    MODE_FILE="$HOME/.cache/display-mode"
    NOTIFY="${pkgs.libnotify}/bin/notify-send"

    ${applyExtMonitor}

    SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    while [ ! -S "$SOCKET" ]; do
      sleep 1
    done

    ${pkgs.socat}/bin/socat -u "UNIX-CONNECT:$SOCKET" - | while IFS= read -r event; do

      if echo "$event" | grep -q "^monitorremoved>>"; then
        MONITOR=$(echo "$event" | sed 's/monitorremoved>>//')
        if [ "$MONITOR" != "$INTERNAL" ]; then
          sleep 1
          EXT_REMAINING=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
            ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
          if [ -z "$EXT_REMAINING" ]; then
            ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,0x0,$INT_SCALE"
            echo "pc-only" > "$MODE_FILE"
            $NOTIFY "Affichage" "Écran externe déconnecté — PC uniquement" -i video-display -t 3000
          else
            $NOTIFY "Affichage" "Écran déconnecté" -i video-display -t 2000
          fi
          sleep 1 && systemctl --user restart waybar &
        fi

      elif echo "$event" | grep -q "^monitoradded>>"; then
        MONITOR=$(echo "$event" | sed 's/monitoradded>>//')
        if [ "$MONITOR" != "$INTERNAL" ]; then
          # Debounce : ignorer si ce moniteur a déjà été traité il y a moins de 10s
          # (hyprctl keyword monitor déclenche parfois un second monitoradded)
          LOCK_FILE="/tmp/monitor-watcher-$(echo "$MONITOR" | tr '/' '-')"
          if [ -f "$LOCK_FILE" ]; then
            LAST=$(cat "$LOCK_FILE" 2>/dev/null || echo 0)
            NOW=$(date +%s)
            if [ $(( NOW - LAST )) -lt 10 ]; then
              continue
            fi
          fi
          date +%s > "$LOCK_FILE"

          sleep 2

          # Identifier si c'est le Xiaomi ou le MSI
          NEW_DESC=$(get_mon_desc "$MONITOR")
          IS_KNOWN_EXT=false
          if [ "$NEW_DESC" = "$XIAOMI_DESC" ] || [ "$NEW_DESC" = "$MSI_DESC" ]; then
            IS_KNOWN_EXT=true
          fi

          # Désactiver l'écran interne avant de placer les externes pour éviter le chevauchement à 0x0
          if [ "$IS_KNOWN_EXT" = "true" ]; then
            ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,disable"
          fi

          EXT_PORTS=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
            ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
          X_OFFSET=0
          for port in $EXT_PORTS; do
            apply_ext_monitor "$port" "$X_OFFSET"
            WIDTH=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
              ${pkgs.jq}/bin/jq -r --arg p "$port" '.[] | select(.name == $p) | .width // 1920')
            X_OFFSET=$((X_OFFSET + WIDTH))
          done

          if [ "$IS_KNOWN_EXT" = "true" ]; then
            FIRST_EXT=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
              ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | head -1)
            [ -n "$FIRST_EXT" ] && move_workspaces_to_monitor "$INTERNAL" "$FIRST_EXT"
            echo "external-only" > "$MODE_FILE"
            $NOTIFY "Affichage" "Externe uniquement — écran interne désactivé" -i video-display -t 2000
          else
            # Moniteur inconnu → restaurer le mode sauvegardé
            SAVED_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "external-only")
            [ "$SAVED_MODE" = "pc-only" ] && SAVED_MODE="external-only"
            if [ "$SAVED_MODE" = "extend" ]; then
              ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,''${LAPTOP_POS},$INT_SCALE"
              $NOTIFY "Affichage" "Mode étendu restauré" -i video-display -t 2000
            elif [ "$SAVED_MODE" = "duplicate" ]; then
              ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,0x0,$INT_SCALE"
              for port in $EXT_PORTS; do
                apply_ext_mirror "$port" "$INT_RES" "$INT_SCALE" "$INTERNAL"
              done
              $NOTIFY "Affichage" "Mode dupliqué restauré" -i video-display -t 2000
            else
              ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,disable"
              echo "external-only" > "$MODE_FILE"
              $NOTIFY "Affichage" "Externe uniquement — écran interne désactivé" -i video-display -t 2000
            fi
          fi

          sleep 1 && systemctl --user restart waybar &
        fi
      fi

    done
  '';

  display-switch = pkgs.writeShellScriptBin "display-switch" ''
    if pgrep -x rofi > /dev/null; then
      pkill -x rofi
      exit 0
    fi

    INTERNAL="eDP-1"
    INT_RES="1920x1080@60"
    INT_SCALE="1"
    MODE_FILE="$HOME/.cache/display-mode"

    ${applyExtMonitor}

    OPTIONS="󰌢  PC uniquement\n󰊓  Étendre\n󰆑  Dupliquer\n󰍺  Externe uniquement"

    THEME_OVERRIDE='window { location: center; anchor: center; x-offset: 0px; y-offset: 0px; width: 280px; background-color: rgba(0, 0, 0, 0.25); border-radius: 14px; } listview { lines: 4; }'

    CHOICE=$(printf "$OPTIONS" | ${pkgs.rofi}/bin/rofi \
      -dmenu \
      -p "Affichage" \
      -theme ~/.config/rofi/power-menu.rasi \
      -theme-str "$THEME_OVERRIDE" \
      -no-custom)

    [ -z "$CHOICE" ] && exit 0

    NOTIFY="${pkgs.libnotify}/bin/notify-send"

    restart_waybar() {
      sleep 1 && systemctl --user restart waybar
    }

    case "$CHOICE" in
      *"PC uniquement"*)
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,0x0,$INT_SCALE"
        ${pkgs.hyprland}/bin/hyprctl monitors -j | \
          ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | \
          while read -r port; do
            disable_ext_monitor "$port"
          done
        echo "pc-only" > "$MODE_FILE"
        $NOTIFY "Affichage" "PC uniquement" -i video-display -t 2000
        restart_waybar &
        ;;
      *"Étendre"*)
        EXT_PORTS=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
          ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
        X_OFFSET=0
        for port in $EXT_PORTS; do
          apply_ext_monitor "$port" "$X_OFFSET"
          WIDTH=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
            ${pkgs.jq}/bin/jq -r --arg p "$port" '.[] | select(.name == $p) | .width // 1920')
          X_OFFSET=$((X_OFFSET + WIDTH))
        done
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,''${LAPTOP_POS},$INT_SCALE"
        echo "extend" > "$MODE_FILE"
        $NOTIFY "Affichage" "Mode étendu" -i video-display -t 2000
        restart_waybar &
        ;;
      *"Dupliquer"*)
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,0x0,$INT_SCALE"
        EXT_PORTS=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
          ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
        for port in $EXT_PORTS; do
          apply_ext_mirror "$port" "$INT_RES" "$INT_SCALE" "$INTERNAL"
        done
        (sleep 0.3 && ${pkgs.swaynotificationcenter}/bin/swaync-client --dismiss-all) &
        echo "duplicate" > "$MODE_FILE"
        $NOTIFY "Affichage" "Mode dupliqué" -i video-display -t 2000
        restart_waybar &
        ;;
      *"Externe uniquement"*)
        EXT_PORTS=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
          ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
        X_OFFSET=0
        for port in $EXT_PORTS; do
          apply_ext_monitor "$port" "$X_OFFSET"
          WIDTH=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
            ${pkgs.jq}/bin/jq -r --arg p "$port" '.[] | select(.name == $p) | .width // 1920')
          X_OFFSET=$((X_OFFSET + WIDTH))
        done
        FIRST_EXT=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
          ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | head -1)
        [ -n "$FIRST_EXT" ] && move_workspaces_to_monitor "$INTERNAL" "$FIRST_EXT"
        ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,disable"
        echo "external-only" > "$MODE_FILE"
        $NOTIFY "Affichage" "Externe uniquement" -i video-display -t 2000
        restart_waybar &
        ;;
    esac
  '';

  display-init = pkgs.writeShellScriptBin "display-init" ''
    INTERNAL="eDP-1"
    INT_RES="1920x1080@60"
    INT_SCALE="1"
    MODE_FILE="$HOME/.cache/display-mode"
    NOTIFY="${pkgs.libnotify}/bin/notify-send"

    ${applyExtMonitor}

    echo "extend" > "$MODE_FILE"

    sleep 3

    EXT_PORTS=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
      ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')

    if [ -z "$EXT_PORTS" ]; then
      exit 0
    fi

    X_OFFSET=0
    for port in $EXT_PORTS; do
      apply_ext_monitor "$port" "$X_OFFSET"
      WIDTH=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
        ${pkgs.jq}/bin/jq -r --arg p "$port" '.[] | select(.name == $p) | .width // 1920')
      X_OFFSET=$((X_OFFSET + WIDTH))
    done
    FIRST_EXT=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
      ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | head -1)
    [ -n "$FIRST_EXT" ] && move_workspaces_to_monitor "$INTERNAL" "$FIRST_EXT"
    ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,disable"
    echo "external-only" > "$MODE_FILE"
    $NOTIFY "Affichage" "Externes détectés — écran interne désactivé" -i video-display -t 2000
    sleep 1 && systemctl --user restart waybar &
  '';

  lid-watcher = pkgs.writeShellScriptBin "lid-watcher" ''
    INTERNAL="eDP-1"
    INT_RES="1920x1080@60"
    INT_SCALE="1"
    MODE_FILE="$HOME/.cache/display-mode"
    LID_FILE="/proc/acpi/button/lid/LID/state"
    LID_TRIGGERED="$HOME/.cache/lid-display-triggered"
    NOTIFY="${pkgs.libnotify}/bin/notify-send"

    ${applyExtMonitor}

    [ ! -f "$LID_FILE" ] && LID_FILE="/proc/acpi/button/lid/LID0/state"

    PREV_STATE=""

    while true; do
      if [ ! -f "$LID_FILE" ]; then
        sleep 2
        continue
      fi

      STATE=$(grep -o "open\|closed" "$LID_FILE")

      if [ "$STATE" != "$PREV_STATE" ] && [ -n "$PREV_STATE" ]; then

        if [ "$STATE" = "closed" ]; then
          EXT_PORTS=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
            ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
          if [ -n "$EXT_PORTS" ]; then
            touch "$LID_TRIGGERED"
            X_OFFSET=0
            for port in $EXT_PORTS; do
              apply_ext_monitor "$port" "$X_OFFSET"
              WIDTH=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
                ${pkgs.jq}/bin/jq -r --arg p "$port" '.[] | select(.name == $p) | .width // 1920')
              X_OFFSET=$((X_OFFSET + WIDTH))
            done
            FIRST_EXT=$(${pkgs.hyprland}/bin/hyprctl monitors -j | \
              ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | head -1)
            [ -n "$FIRST_EXT" ] && move_workspaces_to_monitor "$INTERNAL" "$FIRST_EXT"
            ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,disable"
            echo "external-only" > "$MODE_FILE"
            sleep 1 && systemctl --user restart waybar &
          fi

        elif [ "$STATE" = "open" ]; then
          if [ -f "$LID_TRIGGERED" ]; then
            rm -f "$LID_TRIGGERED"
            EXT_PORTS=$(${pkgs.hyprland}/bin/hyprctl monitors all -j | \
              ${pkgs.jq}/bin/jq -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
            if [ -n "$EXT_PORTS" ]; then
              ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,''${LAPTOP_POS},$INT_SCALE"
              echo "extend" > "$MODE_FILE"
              $NOTIFY "Affichage" "Capot ouvert — mode étendu" -i video-display -t 2000
              sleep 1 && systemctl --user restart waybar &
            else
              ${pkgs.hyprland}/bin/hyprctl keyword monitor "$INTERNAL,$INT_RES,0x0,$INT_SCALE"
              echo "pc-only" > "$MODE_FILE"
            fi
          fi
        fi

      fi

      PREV_STATE="$STATE"
      sleep 1
    done
  '';
in
{
  imports = [];

  home.packages = [ display-switch monitor-watcher display-init lid-watcher ];
}
