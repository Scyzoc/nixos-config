{ pkgs, lib, ... }:

let
  # Environnement Python GTK + layer-shell pour la pilule d'enregistrement
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ps.pycairo ]);
  voice-pill = pkgs.writeShellScriptBin "voice-pill" ''
    export GI_TYPELIB_PATH=${lib.makeSearchPath "lib/girepository-1.0" [
      pkgs.gtk3
      pkgs.gtk-layer-shell
      pkgs.glib.out
      pkgs.pango.out
      pkgs.gdk-pixbuf
      pkgs.harfbuzz
      pkgs.atk
      pkgs.gobject-introspection
    ]}
    export GDK_BACKEND=wayland
    exec ${pythonEnv}/bin/python3 ${../assets/voice-pill.py} "$@"
  '';

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
        pkill -f "voice-pill"
        pkill -f "voice-pill.py"
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
        # Lancement de l'enregistrement et de la pilule
        touch "$LOCK_FILE"
        notify-send "🎙️ Enregistrement..." "Appuyez à nouveau pour arrêter" -i audio-input-microphone

        PATH="${pkgs.cava}/bin:$PATH" ${voice-pill}/bin/voice-pill &

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
