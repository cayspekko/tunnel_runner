#!/bin/bash
# Launch a PICO-8 cart. Usage: ./play.sh [cart.p8]
# Defaults to tunnel.p8 in this folder.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
CART="${1:-$DIR/tunnel.p8}"

# Find the pico8 binary (search common locations).
CANDIDATES=(
  "$DIR/pico-8/PICO-8.app/Contents/MacOS/pico8"
  "/Applications/PICO-8.app/Contents/MacOS/pico8"
  "$HOME/Downloads/pico-8/PICO-8.app/Contents/MacOS/pico8"
)
PICO8=""
for c in "${CANDIDATES[@]}"; do
  [ -x "$c" ] && PICO8="$c" && break
done
if [ -z "$PICO8" ]; then
  PICO8="$(find "$DIR" "$HOME/Downloads" /Applications -maxdepth 4 \
    -path '*PICO-8.app/Contents/MacOS/pico8' 2>/dev/null | head -1)"
fi
if [ -z "$PICO8" ]; then
  echo "Could not find the pico8 binary. Edit play.sh CANDIDATES." >&2
  exit 1
fi

# macOS Gatekeeper: clear quarantine so it launches without right-click.
xattr -dr com.apple.quarantine "$(dirname "$(dirname "$(dirname "$PICO8")")")" 2>/dev/null || true

echo "Running: $CART"
exec "$PICO8" -run "$CART"
