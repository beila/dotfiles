#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
XMONAD_DIR="$ROOT/xwindow/xmonad.symlink"
XMONAD_WRAPPER=$(command -v xmonad)
XMONAD_GHC=$(sed -n "s/^export XMONAD_GHC='\\(.*\\)'/\\1/p" "$XMONAD_WRAPPER")
XMONAD_GHC=${XMONAD_GHC:-ghc}
BUILD_DIR=$(mktemp -d /tmp/xmonad-dock-test.XXXXXX)
DISPLAY_NUMBER=

cleanup() {
    for pid in "${CLIENT_PID:-}" "${DOCK_PID:-}" "${XMONAD_PID:-}" "${XEPHYR_PID:-}"; do
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

for candidate in $(seq 90 110); do
    if ! xdpyinfo -display ":$candidate" >/dev/null 2>&1; then
        DISPLAY_NUMBER=$candidate
        break
    fi
done
[[ -n "$DISPLAY_NUMBER" ]] || {
    echo "FAIL: no free nested X display"
    exit 1
}

cd "$XMONAD_DIR"
"$XMONAD_GHC" \
    --make \
    xmonad.hs \
    test/XMonadDockConfig.hs \
    -i. \
    -ilib \
    -main-is XMonadDockConfig.main \
    -fforce-recomp \
    -outputdir "$BUILD_DIR/config-objects" \
    -o "$BUILD_DIR/xmonad-dock-config"
"$XMONAD_GHC" \
    --make \
    test/XMonadDockWindow.hs \
    -main-is XMonadDockWindow.main \
    -fforce-recomp \
    -outputdir "$BUILD_DIR/dock-objects" \
    -o "$BUILD_DIR/xmonad-dock-window"

mkdir -p "$BUILD_DIR/config" "$BUILD_DIR/data" "$BUILD_DIR/cache"
Xephyr ":$DISPLAY_NUMBER" -screen 1000x700 -nolisten tcp -noreset >/dev/null 2>&1 &
XEPHYR_PID=$!
for _ in $(seq 1 50); do
    xdpyinfo -display ":$DISPLAY_NUMBER" >/dev/null 2>&1 && break
    sleep 0.1
done
xdpyinfo -display ":$DISPLAY_NUMBER" >/dev/null

export DISPLAY=":$DISPLAY_NUMBER"
export XMONAD_CONFIG_DIR="$BUILD_DIR/config"
export XMONAD_DATA_DIR="$BUILD_DIR/data"
export XMONAD_CACHE_DIR="$BUILD_DIR/cache"

"$BUILD_DIR/xmonad-dock-config" >/dev/null 2>&1 &
XMONAD_PID=$!
"$BUILD_DIR/xmonad-dock-window" >/dev/null 2>&1 &
DOCK_PID=$!
xmessage -name xmonad-dock-test-client -buttons "" "dock strut regression" >/dev/null 2>&1 &
CLIENT_PID=$!

CLIENT_WINDOW=$(timeout 10 xdotool search --sync --name xmonad-dock-test-client | head -1)

assert_avoids_panel() {
    local stage=$1
    local geometry
    local y
    local height
    geometry=$(xdotool getwindowgeometry --shell "$CLIENT_WINDOW")
    y=$(sed -n 's/^Y=//p' <<<"$geometry")
    height=$(sed -n 's/^HEIGHT=//p' <<<"$geometry")
    if ((y + height > 652)); then
        echo "FAIL: $stage client overlaps 48px dock: y=$y height=$height"
        exit 1
    fi
}

assert_avoids_panel "initial layout"
xdotool key super+b
sleep 0.2
assert_avoids_panel "after Super+B"

kill "$XMONAD_PID"
wait "$XMONAD_PID" 2>/dev/null || true
"$BUILD_DIR/xmonad-dock-config" >/dev/null 2>&1 &
XMONAD_PID=$!
sleep 0.5
assert_avoids_panel "after restart"

echo "PASS: dock strut survives startup, Super+B, and restart"
