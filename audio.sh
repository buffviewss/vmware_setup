# Tác vụ 3.1: Audio Phiên bản 1 (Tỷ lệ: 16%)
# Thay đổi Driver và DSP plugin qua PulseAudio.
change_audio1() {
    echo "=> Đang chạy tác vụ: Audio v1 (PulseAudio + LADSPA)"
    
    sudo apt install -y pulseaudio-utils sox libsox-fmt-all ladspa-sdk

    if systemctl --user is-active pipewire >/dev/null 2>&1; then
        systemctl --user stop pipewire pipewire-pulse wireplumber || true
    elif command -v pulseaudio >/dev/null 2>&1; then
        pulseaudio -k || true
    fi

    sudo modprobe -r snd_ens1371 snd_hda_intel snd_usb_audio || true
    AUDIO_DRIVERS=("snd_ens1371" "snd_hda_intel" "snd_usb_audio")
    TARGET_AUDIO=${AUDIO_DRIVERS[$RANDOM % ${#AUDIO_DRIVERS[@]}]}
    sudo modprobe "$TARGET_AUDIO" || true

    DSP_PLUGINS=("noise" "equalizer_1901" "reverb_1433")
    DSP_PLUGIN=${DSP_PLUGINS[$RANDOM % ${#DSP_PLUGINS[@]}]}
    FILTER_LEVEL=$(shuf -i 1-3 -n1)

    mkdir -p ~/.config/pulse
    cat > ~/.config/pulse/default.pa <<EOF
.include /etc/pulse/default.pa
load-module module-ladspa-sink sink_name=dsp_out plugin=$DSP_PLUGIN source_port=output control=$FILTER_LEVEL
set-default-sink dsp_out
EOF

    if systemctl --user is-active pipewire >/dev/null 2>&1; then
        systemctl --user start pipewire wireplumber pipewire-pulse
    elif command -v pulseaudio >/dev/null 2>&1; then
        pulseaudio --start
    fi

    echo "[Audio] Driver: $TARGET_AUDIO | DSP: $DSP_PLUGIN | Level: $FILTER_LEVEL"
    echo "[HOÀN TẤT] Tác vụ Audio v1 đã thực hiện xong."
}

# ------------------------------------------------------------------------------

