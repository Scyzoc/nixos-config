{ pkgs, ... }:

let
  # Vocabulaire perso de départ (~/.config/voice/vocab.txt, créé s'il manque puis modifiable) :
  # sert d'invite à Whisper et de référence à la correction Haiku, qui y ajoute ce qu'elle apprend
  vocabSeed = pkgs.writeText "voice-vocab-seed" ''
    # Vocabulaire de la dictée vocale : un terme par ligne (noms propres, marques, termes techniques).
    # Utilisé par Whisper (orthographe privilégiée) et par la correction Haiku. `voice-vocab add <mot>`
    NixOS
    Hyprland
    Quickshell
    home-manager
    flake
    Wayland
    Atlas
    Claude
    Haiku
    GitHub
    ThinkPad
    Brave
    Spotify
    AirPods
    Whisper
    homelab
    Caddy
    Portainer
    RustDesk
    Notion
  '';

  vocabInit = ''
    VOCAB="$HOME/.config/voice/vocab.txt"
    [ -f "$VOCAB" ] || { mkdir -p "''${VOCAB%/*}"; install -m 644 ${vocabSeed} "$VOCAB"; }
  '';

  pythonBin = "${pkgs.python3}/bin/python3";

  voice-vocab = pkgs.writeShellScriptBin "voice-vocab" ''
    ${vocabInit}
    case "''${1:-}" in
      add) shift; [ $# -gt 0 ] || { echo "usage : voice-vocab add <terme>…"; exit 1; }
           for t in "$@"; do grep -qixF -- "$t" "$VOCAB" || echo "$t" >> "$VOCAB"; done ;;
      rm)  shift; for t in "$@"; do sed -i "/^$(printf '%s' "$t" | sed 's/[]\/$*.^[]/\\&/g')$/Id" "$VOCAB"; done ;;
      edit) exec ''${EDITOR:-nano} "$VOCAB" ;;
      ""|list) grep -v '^#' "$VOCAB" | grep . ;;
      *) echo "usage : voice-vocab [list | add <terme>… | rm <terme>… | edit]"; exit 1 ;;
    esac
  '';

  voice-to-text = pkgs.writeShellScriptBin "voice-to-text" ''
    LOCK_FILE="/tmp/voice_to_text.lock"
    AUDIO_FILE="/tmp/voice_rec.wav"
    LIVE_FILE="/tmp/voice_live.txt"         # texte en direct (assets/voice-live.py) → barre
    LIVE_PID="/tmp/voice_live.pid"
    MODEL_DIR="$HOME/.cache/whisper-models"
    MODEL_PATH="$MODEL_DIR/ggml-base.bin"
    STATE_FILE="/tmp/voice_to_text.state"   # busy | done | sent | error : affiché par la barre (VoiceRec.qml)
    DUCK_FILE="/tmp/voice_duck.txt"         # volumes d'origine des lectures baissées pendant l'enregistrement
    PACTL=${pkgs.pulseaudio}/bin/pactl
    JQ=${pkgs.jq}/bin/jq
    # Fondu progressif du volume d'un flux (id, % de départ, % d'arrivée)
    fade() {
        for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
            $PACTL set-sink-input-volume "$1" "$(( $2 + ($3 - $2) * i / 12 ))%" 2>/dev/null
            sleep 0.04
        done
    }
    duck() {
        # Baisse à 20 % d'amplitude = 58 % sur l'échelle pactl, qui est cubique (en fondu) les flux audio en cours de lecture (non en pause), mémorise leur volume
        $PACTL -f json list sink-inputs 2>/dev/null \
          | $JQ -r '.[] | select(.corked == false) | "\(.index) \([.volume[].value_percent | rtrimstr("%") | tonumber] | max)"' \
          > "$DUCK_FILE"
        while read -r id vol; do [ "$vol" -gt 58 ] && fade "$id" "$vol" 58 & done < "$DUCK_FILE"
    }
    unduck() {
        [ -f "$DUCK_FILE" ] || return 0
        while read -r id vol; do [ "$vol" -gt 58 ] && fade "$id" 58 "$vol" & done < "$DUCK_FILE"
        wait
        rm -f "$DUCK_FILE"
    }
    finish() { echo "$1" > "$STATE_FILE"; ( sleep 2.5; rm -f "$STATE_FILE" ) >/dev/null 2>&1 & }
    ${vocabInit}

    mkdir -p "$MODEL_DIR"
    if [ ! -f "$MODEL_PATH" ]; then
        notify-send "🎙️ Transcription" "Téléchargement du modèle Whisper (base)..." -i audio-input-microphone
        ${pkgs.wget}/bin/wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -O "$MODEL_PATH"
    fi

    if [ -f "$LOCK_FILE" ]; then
        # Mode choisi au démarrage : dictée (collage) ou assistant (modules/assistant.nix)
        MODE=$(cat "$LOCK_FILE")
        echo busy > "$STATE_FILE"
        pkill -INT -f "ffmpeg.*voice_rec.wav"
        [ -f "$LIVE_PID" ] && kill "$(cat "$LIVE_PID")" 2>/dev/null
        pkill -f "whisper-stream -m $MODEL_PATH"
        rm -f "$LOCK_FILE" "$LIVE_PID" "$LIVE_FILE"
        unduck

        # Attendre que ffmpeg termine proprement (finalise l'en-tête WAV)
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "ffmpeg.*voice_rec.wav" >/dev/null || break; sleep 0.05; done
        if [ ! -f "$AUDIO_FILE" ]; then
            finish error
            exit 1
        fi

        # Transcription complète en français, orientée par le vocabulaire (--prompt)
        PROMPT=$(grep -v '^#' "$VOCAB" | grep . | paste -sd, | sed 's/,/, /g' | cut -c1-800)
        if ${pkgs.whisper-cpp}/bin/whisper-cli -m "$MODEL_PATH" -f "$AUDIO_FILE" -nt -l fr -t $(nproc) \
               --prompt "$PROMPT" > "$AUDIO_FILE.txt" 2> /tmp/whisper_error.log; then
            # Nettoyage (timestamps, [Musique], (rires)…)
            TEXT=$(sed 's/\[[^]]*\]//g; s/([^)]*)//g' "$AUDIO_FILE.txt" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')
            rm -f "$AUDIO_FILE.txt"

            if [ -n "$TEXT" ] && [ "$MODE" = assistant ]; then
                assistant "$TEXT"
                finish sent
            elif [ -n "$TEXT" ]; then
                # Correction Haiku (orthographe, ponctuation, vocabulaire) ; texte brut si échec
                # Haiku (~4 s) seulement pour les dictées longues ; phrases courtes collées brutes
                if [ "$(echo "$TEXT" | wc -w)" -gt 15 ]; then
                    TEXT=$(${pythonBin} ${../assets/voice-correct.py} "$TEXT")
                fi
                echo -n "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy
                ${pkgs.wtype}/bin/wtype -M ctrl -k v -m ctrl
                finish done
            else
                finish error
            fi
        else
            finish error
        fi
        rm -f "$AUDIO_FILE"
    else
        # Lancement : enregistrement + transcription en direct (la barre affiche onde et texte)
        rm -f "$STATE_FILE" "$LIVE_FILE"
        if [ "''${1:-}" = --assistant ]; then
            echo assistant > "$LOCK_FILE"
        else
            echo dictate > "$LOCK_FILE"
        fi

        duck
        ${pkgs.ffmpeg}/bin/ffmpeg -y -f pulse -i default -ar 16000 -ac 1 -c:a pcm_s16le "$AUDIO_FILE" > /dev/null 2>&1 &
        PATH="${pkgs.whisper-cpp}/bin:$PATH" setsid ${pythonBin} ${../assets/voice-live.py} "$MODEL_PATH" > /dev/null 2>&1 &
        echo $! > "$LIVE_PID"
    fi
  '';
in
{
  home.packages = with pkgs; [
    whisper-cpp
    ffmpeg
    voice-to-text
    voice-vocab
    wget
    cava
  ];
}
