{ pkgs, ... }:

let
  voice-to-text = pkgs.writeShellScriptBin "voice-to-text" ''
    LOCK_FILE="/tmp/voice_to_text.lock"
    AUDIO_FILE="/tmp/voice_rec.wav"
    MODEL_DIR="$HOME/.cache/whisper-models"
    MODEL_PATH="$MODEL_DIR/ggml-base.bin"
    CAVA_CONFIG="/tmp/voice_cava_config"

    # Création du dossier de cache pour le modèle si nécessaire
    if [ ! -d "$MODEL_DIR" ]; then
        mkdir -p "$MODEL_DIR"
    fi

    # Téléchargement du modèle si manquant
    if [ ! -f "$MODEL_PATH" ]; then
        notify-send "🎙️ Transcription" "Téléchargement du modèle Whisper (base)..." -i audio-input-microphone
        ${pkgs.wget}/bin/wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -O "$MODEL_PATH"
    fi

    if [ -f "$LOCK_FILE" ]; then
        # Arrêt de l'enregistrement et du visualiseur
        pkill -INT -f "ffmpeg.*voice_rec.wav"
        pkill -f "kitty --class voice-visualizer"
        rm "$LOCK_FILE"
        notify-send "🤖 Transcription" "Retranscription en cours..." -i audio-input-microphone
        
        # Attendre que ffmpeg termine proprement
        sleep 0.5
        
        if [ ! -f "$AUDIO_FILE" ]; then
            notify-send "❌ Erreur" "Fichier audio non trouvé" -i dialog-error
            exit 1
        fi

        # Transcription en français (-l fr)
        if ${pkgs.whisper-cpp}/bin/whisper-cli -m "$MODEL_PATH" -f "$AUDIO_FILE" -nt -l fr > "$AUDIO_FILE.txt" 2> "/tmp/whisper_error.log"; then
            RESULT_FILE="$AUDIO_FILE.txt"
            # Nettoyage du texte (supprime les timestamps [00:00:00.000 -> 00:00:00.000])
            TEXT=$(cat "$RESULT_FILE" | sed 's/\[.*\] *//g' | tr -d '\n' | sed 's/^ *//;s/ *$//')
            
            if [ -n "$TEXT" ]; then
                echo -n "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy
                notify-send "✅ Terminé" "Texte copié et inséré" -i audio-input-microphone
                ${pkgs.wtype}/bin/wtype -M ctrl -k v -m ctrl
            else
                notify-send "❌ Erreur" "Aucun texte détecté" -i dialog-error
            fi
            rm "$RESULT_FILE"
        else
             ERROR_MSG=$(cat "/tmp/whisper_error.log" | tail -n 1)
             notify-send "❌ Erreur Whisper" "$ERROR_MSG" -i dialog-error
        fi
        rm "$AUDIO_FILE"
    else
        # Configuration de CAVA simplifiée
        cat > "$CAVA_CONFIG" <<EOF
[general]
framerate = 60
[input]
method = pulse
source = default
[color]
foreground = 'cyan'
EOF

        # Lancement de l'enregistrement et du visualiseur
        touch "$LOCK_FILE"
        notify-send "🎙️ Enregistrement..." "Appuyez à nouveau pour arrêter" -i audio-input-microphone
        
        # On lance kitty avec un wrapper pour voir les erreurs si cava plante
        ${pkgs.kitty}/bin/kitty --class voice-visualizer sh -c "${pkgs.cava}/bin/cava -p $CAVA_CONFIG || sleep 5" &
        
        ${pkgs.ffmpeg}/bin/ffmpeg -y -f pulse -i default -ar 16000 -ac 1 -c:a pcm_s16le "$AUDIO_FILE" > /dev/null 2>&1 &
    fi
  '';
in
{
  home.packages = with pkgs; [
    whisper-cpp
    ffmpeg
    voice-to-text
    wget
    cava
  ];
}
