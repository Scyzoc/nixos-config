{ pkgs, ... }:

{
  home.packages = [

    # --- Script défilement MPRIS (texte principal Waybar) ---
    (pkgs.writeShellScriptBin "mpris-scroller" ''
      PLAYERCTL="${pkgs.playerctl}/bin/playerctl"
      DISPLAY_LEN=25
      SCROLL_POS=0
      LAST_TITLE=""
      LAST_UPDATE=0
      CURRENT_TOOLTIP=""

      # Icônes définies via printf pour éviter les problèmes d'encodage
      ICON_SPOTIFY=$(printf '\xef\x86\xbc')    # U+F1BC
      ICON_YOUTUBE=$(printf '\xf3\xb0\x97\x83') # U+F05C3 󰗃
      ICON_WEB=$(printf '\xf3\xb0\x96\x9f')    # U+F059F 󰖟
      ICON_VLC=$(printf '\xf3\xb0\x95\xbc')    # U+F057C 󰕼
      ICON_MUSIC=$(printf '\xef\x80\x81')       # U+F001

      format_time() {
          local T=$1
          [ -z "$T" ] && T=0
          printf "%02d:%02d" $((T/60)) $((T%60))
      }

      generate_tooltip() {
          local TITLE ARTIST ALBUM POS_SECS DURATION_MICROS DURATION_SECS TIME_STR
          TITLE=$($PLAYERCTL metadata title 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\\"/g')
          [ -z "$TITLE" ] && echo "" && return
          ARTIST=$($PLAYERCTL metadata artist 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\\"/g')
          ALBUM=$($PLAYERCTL metadata album 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\\"/g')
          POS_SECS=$($PLAYERCTL position 2>/dev/null | cut -d. -f1)
          [ -z "$POS_SECS" ] && POS_SECS=0
          DURATION_MICROS=$($PLAYERCTL metadata mpris:length 2>/dev/null)
          if [ -n "$DURATION_MICROS" ]; then
              DURATION_SECS=$((DURATION_MICROS / 1000000))
              TIME_STR="$(format_time $POS_SECS) / $(format_time $DURATION_SECS)"
          else
              TIME_STR="$(format_time $POS_SECS)"
          fi
          echo "<span color='#89b4fa'>󰠃 Artiste:</span> $ARTIST\n<span color='#cba6f7'>󰀥 Album:</span> $ALBUM\n<span color='#f9e2af'> Temps:</span> $TIME_STR"
      }

      while true; do
          STATUS=$($PLAYERCTL status 2>/dev/null)

          if [ -z "$STATUS" ] || [ "$STATUS" = "Stopped" ]; then
              echo '{"text": "", "class": "stopped"}'
              SCROLL_POS=0
              sleep 1
              continue
          fi

          TITLE=$($PLAYERCTL metadata title 2>/dev/null)
          PLAYER=$($PLAYERCTL metadata --format '{{playerName}}' 2>/dev/null | tr '[:upper:]' '[:lower:]')

          SOURCE=""
          case "$PLAYER" in
              *spotify*) ICON="$ICON_SPOTIFY" ;;
              *firefox*|*chromium*|*brave*)
                  # Agréger les classes de toutes les instances Hyprland
                  WIN_CLASSES=""
                  for HIS in $(ls "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null); do
                      R=$(HYPRLAND_INSTANCE_SIGNATURE="$HIS" hyprctl clients 2>/dev/null | awk '/class:/{print $2}' | tr '[:upper:]' '[:lower:]')
                      WIN_CLASSES="$WIN_CLASSES $R"
                  done
                  if echo "$WIN_CLASSES" | grep -q "spotify"; then
                      ICON="$ICON_SPOTIFY"
                  elif echo "$WIN_CLASSES" | grep -q "youtube"; then
                      ICON="$ICON_YOUTUBE"
                      SOURCE="youtube"
                  else
                      ICON="$ICON_WEB"
                      SOURCE="web"
                  fi ;;
              *vlc*)  ICON="$ICON_VLC" ;;
              *mpv*)  ICON="$ICON_MUSIC" ;;
              *)      ICON="$ICON_MUSIC" ;;
          esac

          # Reset scroll si le titre change
          if [ "$TITLE" != "$LAST_TITLE" ]; then
              SCROLL_POS=0
              LAST_TITLE="$TITLE"
          fi

          # Mise à jour tooltip toutes les 2s
          NOW=$(date +%s)
          if [ $((NOW - LAST_UPDATE)) -ge 2 ]; then
              CURRENT_TOOLTIP=$(generate_tooltip)
              LAST_UPDATE=$NOW
          fi

          TITLE_CLEAN=$(echo "$TITLE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\\"/g')
          TITLE_LEN=''${#TITLE_CLEAN}

          if [ "$STATUS" = "Playing" ] && [ "$TITLE_LEN" -gt "$DISPLAY_LEN" ]; then
              PADDED="$TITLE_CLEAN   "
              PADDED_LEN=''${#PADDED}
              START=$((SCROLL_POS % PADDED_LEN))
              DISPLAY="''${PADDED:$START:$DISPLAY_LEN}"
              REST=$((DISPLAY_LEN - ''${#DISPLAY}))
              [ "$REST" -gt 0 ] && DISPLAY="$DISPLAY''${PADDED:0:$REST}"
              SCROLL_POS=$((SCROLL_POS + 1))
          else
              DISPLAY="''${TITLE_CLEAN:0:$DISPLAY_LEN}"
          fi

          if [ -n "$SOURCE" ]; then
              CLASS="[\"$STATUS\", \"$SOURCE\"]"
          else
              CLASS="\"$STATUS\""
          fi
          echo "{\"text\": \"$ICON  $DISPLAY\", \"tooltip\": \"$CURRENT_TOOLTIP\", \"class\": $CLASS}"
          sleep 0.1
      done
    '')

  ];
}
