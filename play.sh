#!/bin/bash
# Run or export a PICO-8 cart.
#   ./play.sh                 run tunnel.p8
#   ./play.sh some.p8         run some.p8
#   ./play.sh export          export web build (web/index.html + index.js)
#   ./play.sh export some.p8  export a specific cart
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

MODE="run"
if [ "$1" = "export" ] || [ "$1" = "-e" ] || [ "$1" = "--export" ]; then
  MODE="export"; shift
fi
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

if [ "$MODE" = "export" ]; then
  echo "Exporting $CART -> $DIR/index.html ..."
  # PICO-8 writes index.html + index.js into the repo root (cart needs a __label__).
  "$PICO8" "$CART" -export "$DIR/index.html"
  echo
  echo "Done. index.html + index.js are in the repo root, ready for GitHub Pages."
  exit 0
fi

echo "Running: $CART"
exec "$PICO8" -run "$CART"
