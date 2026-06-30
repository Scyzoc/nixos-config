{ pkgs, ... }:

let
  HYPR   = "${pkgs.hyprland}/bin/hyprctl";
  JQ     = "${pkgs.jq}/bin/jq";
  NOTIFY = "${pkgs.libnotify}/bin/notify-send";
  ROFI   = "${pkgs.rofi}/bin/rofi";
  SOCAT  = "${pkgs.socat}/bin/socat";

  # ==========================================================================
  # SCRIPT CENTRAL : applique un mode d'affichage
  # Usage : display-apply <pc-only|external-only|extend|mirror>
  # ==========================================================================
  display-apply = pkgs.writeShellScriptBin "display-apply" ''
    MODE="$1"
    INTERNAL="eDP-1"
    INT_RES="1920x1080@60"
    INT_SCALE="1"
    # Position de l'écran interne dans la disposition étendue (définie dans home.nix)
    INT_EXT_POS="1520x1440"

    ext_monitors() {
      ${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "eDP-1") | .name'
    }

    mon_desc() {
      ${HYPR} monitors all -j | ${JQ} -r --arg n "$1" '.[] | select(.name == $n) | .description'
    }

    xiaomi_monitor() {
      ${HYPR} monitors all -j | ${JQ} -r '.[] | select(.description | test("Xiaomi")) | .name' | head -1
    }

    move_workspaces() {
      local src="$1" dst="$2"
      ${HYPR} workspaces -j | \
        ${JQ} -r --arg m "$src" '.[] | select(.monitor == $m) | .id' | \
        while read -r ws; do
          ${HYPR} dispatch moveworkspacetomonitor "$ws" "$dst"
        done
    }

    msi_monitor() {
      ${HYPR} monitors all -j | ${JQ} -r '.[] | select(.description | test("MSI|Microstep")) | .name' | head -1
    }

    case "$MODE" in

      pc-only)
        # Désactive les externes, eDP-1 reste à INT_EXT_POS pour éviter
        # le chevauchement avec les externes (0x0) lors d'un re-branchement
        for m in $(ext_monitors); do
          DESC=$(mon_desc "$m")
          ${HYPR} keyword monitor "desc:$DESC,disable"
        done
        ${HYPR} keyword monitor "$INTERNAL,$INT_RES,$INT_EXT_POS,$INT_SCALE"
        ${NOTIFY} "Affichage" "PC uniquement" -i video-display -t 2000
        ;;

      external-only)
        # Déplace les workspaces puis désactive eDP-1.
        # Cible Xiaomi en priorité, sinon premier externe disponible.
        XMON=$(xiaomi_monitor)
        PRIMARY="''${XMON:-$(ext_monitors | head -1)}"
        [ -n "$PRIMARY" ] && move_workspaces "$INTERNAL" "$PRIMARY"
        ${HYPR} keyword monitor "$INTERNAL,disable"
        ${NOTIFY} "Affichage" "Externe uniquement" -i video-display -t 2000
        ;;

      lid-closed)
        # Capot fermé : WS 1-5 → Xiaomi, WS 6-11 → MSI
        XMON=$(xiaomi_monitor)
        MMON=$(msi_monitor)
        if [ -n "$XMON" ] && [ -n "$MMON" ]; then
          for ws in 1 2 3 4 5; do
            ${HYPR} dispatch moveworkspacetomonitor "$ws" "$XMON"
          done
          for ws in 6 7 8 9 10 11; do
            ${HYPR} dispatch moveworkspacetomonitor "$ws" "$MMON"
          done
        elif [ -n "$XMON" ]; then
          move_workspaces "$INTERNAL" "$XMON"
        fi
        ${HYPR} keyword monitor "$INTERNAL,disable"
        ${NOTIFY} "Affichage" "Capot fermé (Xiaomi: 1-5, MSI: 6-11)" -i video-display -t 2000
        ;;

      mirror)
        ${HYPR} keyword monitor "$INTERNAL,$INT_RES,0x0,$INT_SCALE"
        for m in $(ext_monitors); do
          DESC=$(mon_desc "$m")
          ${HYPR} keyword monitor "desc:$DESC,$INT_RES,0x0,$INT_SCALE,mirror,$INTERNAL"
        done
        ${NOTIFY} "Affichage" "Mode miroir" -i video-display -t 2000
        ;;

      extend)
        LID_FILE=$(ls /proc/acpi/button/lid/*/state 2>/dev/null | head -1)
        LID_STATE=$([ -n "$LID_FILE" ] && awk '{print $2}' "$LID_FILE" || echo "open")

        if [ "$LID_STATE" = "closed" ]; then
          # Capot fermé : eDP-1 inaccessible, Xiaomi devient écran principal
          XMON=$(xiaomi_monitor)
          PRIMARY="''${XMON:-$(ext_monitors | head -1)}"
          [ -n "$PRIMARY" ] && move_workspaces "$INTERNAL" "$PRIMARY"
          ${HYPR} keyword monitor "$INTERNAL,disable"
        else
          # Capot ouvert : mode étendu normal, eDP-1 réactivé
          ${HYPR} keyword monitor "$INTERNAL,$INT_RES,$INT_EXT_POS,$INT_SCALE"
        fi
        ${NOTIFY} "Affichage" "Mode étendu" -i video-display -t 2000
        ;;

    esac

    sleep 1 && systemctl --user restart waybar &
  '';

  # ==========================================================================
  # MENU ROFI : sélecteur manuel Super+P
  # ==========================================================================
  display-switch = pkgs.writeShellScriptBin "display-switch" ''
    if pgrep -x rofi > /dev/null; then
      pkill -x rofi
      exit 0
    fi

    HAS_EXT=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "eDP-1") | .name' | head -1)

    if [ -z "$HAS_EXT" ]; then
      OPTIONS="󰌢  PC uniquement"
    else
      OPTIONS="󰌢  PC uniquement\n󰍺  Externe uniquement\n󰆑  Miroir\n󰊓  Étendu"
    fi

    CHOICE=$(printf "$OPTIONS" | ${ROFI} \
      -dmenu \
      -p "󰍹  Affichage" \
      -theme ~/.config/rofi/display-switch.rasi \
      -no-custom)

    [ -z "$CHOICE" ] && exit 0

    case "$CHOICE" in
      *"PC uniquement"*)      ${display-apply}/bin/display-apply pc-only ;;
      *"Externe uniquement"*) ${display-apply}/bin/display-apply external-only ;;
      *"Miroir"*)             ${display-apply}/bin/display-apply mirror ;;
      *"Étendu"*)             ${display-apply}/bin/display-apply extend ;;
    esac
  '';

  # ==========================================================================
  # MONITOR-WATCHER : service systemd, écoute socket Hyprland
  # monitoradded  → extend (capot ouvert) ou external-only (capot fermé)
  # monitorremoved → pc-only (0 externe) ou réapplique mode correct (≥1 externe)
  # ==========================================================================
  monitor-watcher = pkgs.writeShellScriptBin "monitor-watcher" ''
    INTERNAL="eDP-1"

    SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    until [ -S "$SOCKET" ]; do sleep 1; done

    ${SOCAT} -u "UNIX-CONNECT:$SOCKET" - | while IFS= read -r event; do

      ETYPE="''${event%%>>*}"
      EDATA="''${event#*>>}"

      case "$ETYPE" in

        monitoradded)
          MONITOR="$EDATA"
          [ "$MONITOR" = "$INTERNAL" ] && continue

          LOCK="$XDG_RUNTIME_DIR/disp-added-$(echo "$MONITOR" | tr '/' '-')"
          NOW=$(date +%s)
          if [ -f "$LOCK" ]; then
            LAST=$(cat "$LOCK" 2>/dev/null || echo 0)
            [ $(( NOW - LAST )) -lt 10 ] && continue
          fi
          echo "$NOW" > "$LOCK"

          sleep 2
          LID_FILE=$(ls /proc/acpi/button/lid/*/state 2>/dev/null | head -1)
          LID_STATE=$([ -n "$LID_FILE" ] && awk '{print $2}' "$LID_FILE" || echo "open")
          if [ "$LID_STATE" = "closed" ]; then
            ${display-apply}/bin/display-apply lid-closed
          else
            ${display-apply}/bin/display-apply extend
          fi
          ;;

        monitorremoved)
          MONITOR="$EDATA"
          [ "$MONITOR" = "$INTERNAL" ] && continue

          sleep 1
          EXT=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "'"$INTERNAL"'") | .name')
          if [ -z "$EXT" ]; then
            ${display-apply}/bin/display-apply pc-only
          else
            ${display-apply}/bin/display-apply extend
          fi
          ;;

      esac

    done
  '';

  # ==========================================================================
  # LID-WATCHER : service systemd, poll /proc/acpi lid state
  # closed + externe présent → external-only (workspaces migrés)
  # open après triggered    → extend
  # ==========================================================================
  lid-watcher = pkgs.writeShellScriptBin "lid-watcher" ''
    INTERNAL="eDP-1"
    LID_FILE=$(ls /proc/acpi/button/lid/*/state 2>/dev/null | head -1)
    [ -z "$LID_FILE" ] && exit 0

    until ${HYPR} monitors -j >/dev/null 2>&1; do sleep 1; done

    prev_state=$(awk '{print $2}' "$LID_FILE")

    while true; do
      sleep 2
      state=$(awk '{print $2}' "$LID_FILE")

      if [ "$state" != "$prev_state" ]; then
        prev_state="$state"
        EXT=$(${HYPR} monitors all -j | ${JQ} -r '.[] | select(.name != "'"$INTERNAL"'") | .name' | head -1)

        case "$state" in
          closed)
            [ -n "$EXT" ] && ${display-apply}/bin/display-apply lid-closed
            ;;
          open)
            [ -n "$EXT" ] && ${display-apply}/bin/display-apply extend
            ;;
        esac
      fi
    done
  '';

in
{
  # --------------------------------------------------------------------------
  # Thème Rofi — popup centré 4 options
  # --------------------------------------------------------------------------
  xdg.configFile."rofi/display-switch.rasi".text = ''
    configuration {
      show-icons: false;
      font: "JetBrainsMono Nerd Font 13";
      disable-history: true;
      kb-mode-next: "";
      kb-mode-previous: "";
    }
    * {
      background-color: transparent;
      text-color: #ffffff;
    }
    window {
      location: center;
      anchor: center;
      x-offset: 0px;
      y-offset: 0px;
      width: 260px;
      border: 2px;
      border-color: rgba(255, 255, 255, 0.2);
      border-radius: 14px;
      background-color: rgba(0, 0, 0, 0.25);
      padding: 4px;
    }
    mainbox {
      spacing: 4px;
      children: [inputbar, listview];
    }
    inputbar {
      children: [prompt];
      padding: 8px 12px;
      border-radius: 10px;
      background-color: rgba(255, 255, 255, 0.08);
      margin: 0 0 2px 0;
    }
    prompt { text-color: rgba(255, 255, 255, 0.7); }
    textbox-prompt-colon { enabled: false; }
    entry { enabled: false; }
    listview {
      lines: 4;
      spacing: 4px;
      scrollbar: false;
      padding: 2px;
      fixed-height: false;
    }
    element {
      padding: 8px 12px;
      border-radius: 10px;
      orientation: horizontal;
    }
    element-text {
      background-color: transparent;
      text-color: #ffffff;
      font: "JetBrainsMono Nerd Font 13";
      vertical-align: 0.5;
    }
    element selected {
      background-color: rgba(255, 255, 255, 0.1);
      border: 2px;
      border-color: rgba(255, 255, 255, 0.9);
    }
    element-text selected { text-color: #ffffff; }
  '';

  # --------------------------------------------------------------------------
  # Packages
  # --------------------------------------------------------------------------
  home.packages = [ display-apply display-switch monitor-watcher lid-watcher ];

  # --------------------------------------------------------------------------
  # Services systemd user
  # --------------------------------------------------------------------------
  systemd.user.services.lid-watcher = {
    Unit = {
      Description = "Lid state watcher → migrate workspaces eDP-1";
      After       = [ "hyprland-session.target" ];
      PartOf      = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${lid-watcher}/bin/lid-watcher";
      Restart    = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  systemd.user.services.monitor-watcher = {
    Unit = {
      Description = "Hyprland monitor hotplug → mode automatique";
      After       = [ "hyprland-session.target" ];
      PartOf      = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${monitor-watcher}/bin/monitor-watcher";
      Restart    = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  # --------------------------------------------------------------------------
  # Keybinding Super+P
  # --------------------------------------------------------------------------
  wayland.windowManager.hyprland.settings.bind = [
    "$mainMod, P, exec, display-switch"
  ];
}
