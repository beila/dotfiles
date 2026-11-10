#!/usr/bin/env bash
set -euo pipefail

scratch=$(mktemp -d /tmp/clipboard-neovide.XXXXXXXX)
xvfb_pid=
neovide_pid=
# shellcheck disable=SC2329
cleanup() {
    [[ -z $neovide_pid ]] || kill "$neovide_pid" 2>/dev/null || true
    [[ -z $xvfb_pid ]] || kill "$xvfb_pid" 2>/dev/null || true
    rm -rf -- "$scratch"
}
trap cleanup EXIT

xvfb=${XVFB:-Xvfb}
for number in {120..150}; do
    if [[ ! -e /tmp/.X"$number"-lock && ! -S /tmp/.X11-unix/X"$number" ]]; then
        export DISPLAY=":$number"
        break
    fi
done
export XAUTHORITY="$scratch/auth"
touch "$XAUTHORITY"
xauth add "$DISPLAY" . "$(mcookie)"
"$xvfb" "$DISPLAY" -screen 0 800x600x24 -nolisten tcp -auth "$XAUTHORITY" \
    >"$scratch/xvfb.log" 2>&1 &
xvfb_pid=$!
export XDG_CONFIG_HOME="$scratch/config" XDG_CACHE_HOME="$scratch/cache"
export XDG_DATA_HOME="$scratch/data" XDG_STATE_HOME="$scratch/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
for _ in {1..100}; do
    xdpyinfo >/dev/null 2>&1 && break
    sleep 0.05
done
neovide --no-fork -- -u NONE -i NONE --listen "$scratch/nvim.sock" \
    -c 'nnoremap <F20> <Cmd>let g:clipboard_f20_seen=1<CR>' \
    >"$scratch/neovide.log" 2>&1 &
neovide_pid=$!
window=$(timeout 20 xdotool search --sync --onlyvisible --class neovide | head -1) || {
    cat "$scratch/neovide.log"
    exit 1
}
for _ in {1..100}; do
    [[ -S $scratch/nvim.sock ]] && break
    sleep 0.05
done
xdotool windowfocus --sync "$window"
xdotool key --clearmodifiers --window "$window" F20
for _ in {1..100}; do
    seen=$(nvim --server "$scratch/nvim.sock" --remote-expr "get(g:,'clipboard_f20_seen',0)")
    if [[ $seen == 1 ]]; then
        printf 'PASS: targeted F20 reaches Neovide\n'
        exit
    fi
    sleep 0.05
done
cat "$scratch/neovide.log"
exit 1
