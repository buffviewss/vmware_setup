MIN=1.01
MAX=1.45
RANDOM_DPI=$(awk -v min=$MIN -v max=$MAX 'BEGIN{srand(); printf "%.2f", min+rand()*(max-min)}')

gsettings set org.gnome.desktop.interface text-scaling-factor "$RANDOM_DPI" || true
echo "[Canvas] DPI scaling: $RANDOM_DPI"