#!/bin/bash
# Run, export, or preview a PICO-8 cart / the web console.
#   ./play.sh                 run tunnel.p8 in PICO-8
#   ./play.sh some.p8         run some.p8
#   ./play.sh export          export web build -> carts/<name>/
#   ./play.sh export some.p8  export a specific cart
#   ./play.sh serve [port]    serve the console at http://localhost:8000
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

# Preview the console locally (reliable iframe loading vs file://).
if [ "$1" = "serve" ]; then
  PORT="${2:-8000}"
  echo "Serving the console at http://localhost:$PORT  (ctrl-c to stop)"
  exec python3 -m http.server "$PORT" --directory "$DIR"
fi

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
  NAME="$(basename "$CART" .p8)"
  OUT="$DIR/carts/$NAME"
  mkdir -p "$OUT"
  echo "Exporting $CART -> carts/$NAME/index.html ..."
  # PICO-8 writes index.html + index.js into carts/<name>/ (cart needs a __label__).
  # The repo-root index.html is our own console page; it loads this in an iframe.
  "$PICO8" "$CART" -export "$OUT/index.html"
  echo
  echo "Done -> carts/$NAME/ (index.html + index.js)."
  echo "Open the repo-root index.html (the console), or push to GitHub Pages."
  exit 0
fi

echo "Running: $CART"
exec "$PICO8" -run "$CART"
