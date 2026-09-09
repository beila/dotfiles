#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
XMONAD_DIR="$ROOT/xwindow/xmonad.symlink"
XMONAD_WRAPPER=$(command -v xmonad || true)
XMONAD_GHC=
if [[ -n "$XMONAD_WRAPPER" ]]; then
    XMONAD_GHC=$(sed -n "s/^export XMONAD_GHC='\\(.*\\)'/\\1/p" "$XMONAD_WRAPPER")
fi
XMONAD_GHC=${XMONAD_GHC:-ghc}
BUILD_DIR=$(mktemp -d /tmp/xmonad-dock-test.XXXXXX)
DISPLAY_NUMBER=

cleanup() {
    for pid in "${FIREFOX_PID:-}" "${NORMAL_PID:-}" "${CLIENT_PID:-}" "${DOCK_PID:-}" "${XMONAD_PID:-}" "${XEPHYR_PID:-}"; do
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
"$XMONAD_GHC" \
    --make \
    test/XMonadTestClient.hs \
    -main-is XMonadTestClient.main \
    -fforce-recomp \
    -outputdir "$BUILD_DIR/client-objects" \
    -o "$BUILD_DIR/xmonad-test-client"

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
DOCK_WINDOW=$(timeout 10 xdotool search --sync --name xmonad-dock-test-panel | head -1)

wait_until_tiled() {
    local geometry
    local width
    local height
    for _ in $(seq 1 50); do
        geometry=$(xdotool getwindowgeometry --shell "$CLIENT_WINDOW")
        width=$(sed -n 's/^WIDTH=//p' <<<"$geometry")
        height=$(sed -n 's/^HEIGHT=//p' <<<"$geometry")
        if ((width >= 900 && height >= 600)); then
            return
        fi
        sleep 0.1
    done
    echo "FAIL: client was not tiled before geometry assertions"
    exit 1
}

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

wait_until_tiled
assert_avoids_panel "initial layout"
xdotool key super+b
sleep 0.2
assert_avoids_panel "after Super+B"

xdotool key super+shift+b
sleep 0.2
geometry=$(xdotool getwindowgeometry --shell "$CLIENT_WINDOW")
y=$(sed -n 's/^Y=//p' <<<"$geometry")
height=$(sed -n 's/^HEIGHT=//p' <<<"$geometry")
if ((y + height <= 652)); then
    echo "FAIL: test-only ToggleStruts did not hide the dock gap"
    exit 1
fi

kill "$XMONAD_PID"
wait "$XMONAD_PID" 2>/dev/null || true
"$BUILD_DIR/xmonad-dock-config" >/dev/null 2>&1 &
XMONAD_PID=$!
sleep 0.5
assert_avoids_panel "after restart"

"$BUILD_DIR/xmonad-test-client" normal xmonad-normal-test >/dev/null 2>&1 &
NORMAL_PID=$!
"$BUILD_DIR/xmonad-test-client" firefox xmonad-firefox-test >/dev/null 2>&1 &
FIREFOX_PID=$!
NORMAL_WINDOW=$(timeout 10 xdotool search --sync --name xmonad-normal-test | head -1)
FIREFOX_WINDOW=$(timeout 10 xdotool search --sync --name xmonad-firefox-test | head -1)

stack_index() {
    local window_id=$1
    local hex_id
    hex_id=$(printf '0x%x' "$window_id")
    xwininfo -root -children |
        awk -v target="$hex_id" 'tolower($1) == tolower(target) { print NR; exit }'
}

assert_above() {
    local upper=$1
    local lower=$2
    local stage=$3
    local upper_index
    local lower_index
    upper_index=$(stack_index "$upper")
    lower_index=$(stack_index "$lower")
    if [[ -z "$upper_index" || -z "$lower_index" || "$upper_index" -ge "$lower_index" ]]; then
        echo "FAIL: $stage stacking order is incorrect: upper=$upper_index lower=$lower_index"
        exit 1
    fi
}

assert_focused() {
    local expected=$1
    local stage=$2
    local focused
    focused=$(xdotool getwindowfocus)
    if [[ "$focused" != "$expected" ]]; then
        echo "FAIL: $stage did not receive focus"
        exit 1
    fi
}

xdotool windowraise "$DOCK_WINDOW"
xdotool mousemove --window "$NORMAL_WINDOW" 20 20
sleep 0.2
assert_focused "$NORMAL_WINDOW" "normal client"
assert_above "$NORMAL_WINDOW" "$DOCK_WINDOW" "normal focused client"

xdotool windowraise "$DOCK_WINDOW"
xdotool mousemove --window "$FIREFOX_WINDOW" 20 20
sleep 0.2
assert_focused "$FIREFOX_WINDOW" "Firefox client"
assert_above "$DOCK_WINDOW" "$FIREFOX_WINDOW" "Firefox exclusion"

echo "PASS: dock struts reset on restart and Firefox stays below the panel"
