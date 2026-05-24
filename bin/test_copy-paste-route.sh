#!/usr/bin/env bash
# test_copy-paste-route.sh — harness for bin/copy-paste-route.
#
# Stubs `xdotool` via PATH so we can exercise the routing logic without an
# X server. The stub records its argv to $TMPDIR/xdotool-calls and emits
# canned output for `getactivewindow` / `getwindowclassname` based on
# $TMPDIR/active-class (which each test sets).

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$DOTFILES_ROOT/bin/copy-paste-route"

TMPDIR=$(mktemp -d /tmp/test_copy_paste.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_MACHINE_NAME="testhost"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG
export DOTFILES_ROOT

# Stub xdotool that:
# - prints the focused window's "id" for `getactivewindow`,
# - prints the contents of $ACTIVE_CLASS_FILE for `getwindowclassname <id>`,
# - records `key <combo>` invocations to $XDOTOOL_CALLS.
STUB_BIN="$TMPDIR/bin"
mkdir -p "$STUB_BIN"
ACTIVE_CLASS_FILE="$TMPDIR/active-class"
ACTIVE_WID_FILE="$TMPDIR/active-wid"
XDOTOOL_CALLS="$TMPDIR/xdotool-calls"
: > "$XDOTOOL_CALLS"
echo "0x42" > "$ACTIVE_WID_FILE"

cat > "$STUB_BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    getactivewindow)
        cat "${ACTIVE_WID_FILE:-/dev/null}" 2>/dev/null
        # Empty file → exit 1 (X session unavailable)
        [ -s "$ACTIVE_WID_FILE" ] || exit 1
        ;;
    getwindowclassname)
        cat "${ACTIVE_CLASS_FILE:-/dev/null}" 2>/dev/null
        [ -s "$ACTIVE_CLASS_FILE" ] || exit 1
        ;;
    key)
        printf '%s\n' "$*" >> "$XDOTOOL_CALLS"
        ;;
    *)
        echo "stub xdotool: unhandled $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$STUB_BIN/xdotool"
export ACTIVE_CLASS_FILE ACTIVE_WID_FILE XDOTOOL_CALLS

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n  %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

set_class() { printf '%s' "$1" > "$ACTIVE_CLASS_FILE"; }
clear_calls() { : > "$XDOTOOL_CALLS"; }
last_call() { tail -1 "$XDOTOOL_CALLS"; }
run() { PATH="$STUB_BIN:/usr/bin:/bin" bash "$UNDER_TEST" "$@"; echo "rc=$?"; }

# Helper: assert the last key call ends with $1 (the combo) AND has
# --clearmodifiers (which prevents xmonad-held Super from polluting the
# dispatched keystroke). Window targeting is asserted via $2 if set.
assert_combo() {
    local label="$1" combo="$2" want_window="${3:-}"
    local line; line=$(last_call)
    if ! printf '%s' "$line" | grep -q -- "--clearmodifiers"; then
        fail "$label" "missing --clearmodifiers in: $line"; return
    fi
    if [ -n "$want_window" ] && ! printf '%s' "$line" | grep -q -- "--window"; then
        fail "$label" "missing --window targeting in: $line"; return
    fi
    if [[ "$line" != *"$combo" ]]; then
        fail "$label" "expected combo '$combo' at end of: $line"; return
    fi
    pass "$label"
}

echo "=== Test 1: ghostty + copy → ctrl+shift+c (with --clearmodifiers + --window) ==="
clear_calls; set_class "ghostty"
out=$(run copy)
assert_combo "ghostty + copy" "ctrl+shift+c" yes
echo "$out" | grep -q "rc=0" && pass "exit 0" || fail "exit 0" "got: $out"

echo
echo "=== Test 2: ghostty + paste → ctrl+shift+v ==="
clear_calls; set_class "ghostty"
run paste >/dev/null
assert_combo "ghostty + paste" "ctrl+shift+v" yes

echo
echo "=== Test 3: firefox + copy → ctrl+c ==="
clear_calls; set_class "firefox"
run copy >/dev/null
assert_combo "firefox + copy" "ctrl+c" yes

echo
echo "=== Test 4: vivaldi + paste → ctrl+v ==="
clear_calls; set_class "Vivaldi-stable"
run paste >/dev/null
assert_combo "vivaldi + paste" "ctrl+v" yes

echo
echo "=== Test 5: empty class but valid wid → ctrl+c (default routing) ==="
clear_calls
: > "$ACTIVE_CLASS_FILE"  # class lookup returns empty
run copy >/dev/null
# wid is still 0x42; class is empty so the ghostty match misses → ctrl+c.
# --window is still passed because we have a wid.
assert_combo "empty-class fallback" "ctrl+c" yes

echo
echo "=== Test 6: bad action → exit 2 ==="
clear_calls
out=$(run frobnicate 2>&1)
echo "$out" | grep -q "rc=2" && pass "exit 2 on bad action" || fail "exit 2 on bad action" "got: $out"
[ "$(wc -l < "$XDOTOOL_CALLS")" = "0" ] && pass "no xdotool call on bad action" || fail "no xdotool call on bad action" "calls: $(cat "$XDOTOOL_CALLS")"

echo
echo "=== Test 7: getactivewindow fails → still emits ctrl+c, no --window ==="
clear_calls
: > "$ACTIVE_WID_FILE"  # empty → stub exits 1
run copy >/dev/null
last=$(last_call)
# No wid → no --window flag, but --clearmodifiers still applied.
[[ "$last" == *"ctrl+c" ]] && [[ "$last" == *"--clearmodifiers"* ]] && [[ "$last" != *"--window"* ]] \
    && pass "getactivewindow fail falls back without --window" \
    || fail "getactivewindow fail falls back" "got: $last"
echo "0x42" > "$ACTIVE_WID_FILE"  # restore

echo
echo "=== Test 8: COPY_PASTE_GHOSTTY_CLASSES env override ==="
clear_calls; set_class "MyCustomTerminal"
COPY_PASTE_GHOSTTY_CLASSES="MyCustomTerminal AnotherTerm" run copy >/dev/null
assert_combo "env override matches" "ctrl+shift+c" yes

echo
echo "=== Test 9: multi-word class with the alternate variant ==="
clear_calls; set_class "com.mitchellh.ghostty"
run copy >/dev/null
assert_combo "alt ghostty class" "ctrl+shift+c" yes

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
