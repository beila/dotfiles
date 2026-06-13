#!/usr/bin/env bash
# test_random-lockscreen.sh — harness for xwindow/bin/random-lockscreen.
#
# Uses a fake wallpaper directory and a stubbed `gsettings` so we can exercise
# each branch without touching the real GNOME config.

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$DOTFILES_ROOT/xwindow/bin/random-lockscreen"

TMPDIR=$(mktemp -d /tmp/test_rls.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_MACHINE_NAME="testhost"
export LOG_NOTIFY_MODE=never
export DOTFILES_ROOT

WP_DIR="$TMPDIR/walls"
mkdir -p "$WP_DIR"
export WALLPAPER_DIR="$WP_DIR"

# Stub gsettings via PATH. Its behaviour is controlled by $TEST_GSETTINGS_MODE.
STUB_BIN="$TMPDIR/bin"
mkdir -p "$STUB_BIN"
export TEST_GSETTINGS_MODE="$TMPDIR/gsettings-mode"
export GSETTINGS_CALL_LOG="$TMPDIR/gsettings-calls"
cat > "$STUB_BIN/gsettings" <<'EOF'
#!/usr/bin/env bash
mode=$(cat "$TEST_GSETTINGS_MODE" 2>/dev/null || echo ok)
printf 'CALL\t%s\n' "$*" >> "$GSETTINGS_CALL_LOG"
case "$mode" in
    ok)         exit 0 ;;
    dbus)       echo "Cannot autolaunch D-Bus without X11 \$DISPLAY" >&2; exit 1 ;;
    schema)     echo "No such schema 'org.gnome.desktop.screensaver'"   >&2; exit 1 ;;
    other)      echo "gsettings generic failure"                        >&2; exit 1 ;;
    *)          exit 0 ;;
esac
EOF
chmod +x "$STUB_BIN/gsettings"

set_gsettings_mode() { echo "$1" > "$TEST_GSETTINGS_MODE"; }
clear_calls()        { : > "$GSETTINGS_CALL_LOG"; }

PASS_FILE="$TMPDIR/pass"; FAIL_FILE="$TMPDIR/fail"
printf '0' > "$PASS_FILE"; printf '0' > "$FAIL_FILE"
_bump() { local f=$1 n; n=$(cat "$f"); printf '%d' $((n+1)) > "$f"; }
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$label" "$expected" "$actual"; _bump "$FAIL_FILE"
    fi
}
check_grep() {
    local label=$1 pattern=$2 file=$3
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s\n  missing /%s/ in %s\n  contents: %s\n' "$label" "$pattern" "$file" "$(cat "$file" 2>/dev/null | head -3)"; _bump "$FAIL_FILE"
    fi
}
check_nogrep() {
    local label=$1 pattern=$2 file=$3
    if [ ! -f "$file" ] || ! grep -q "$pattern" "$file" 2>/dev/null; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s (unexpected /%s/)\n' "$label" "$pattern"; _bump "$FAIL_FILE"
    fi
}

run_under_test() {
    # Tight PATH so the real gsettings/find/shuf still work (system paths)
    # while our stub takes priority.
    PATH="$STUB_BIN:/usr/bin:/bin" bash "$UNDER_TEST" >/dev/null 2>&1
    echo $?
}
log_file() { find "$LOG_ROOT" -type f -name 'random-lockscreen.*.log' 2>/dev/null | head -1; }
clear_logs() { rm -rf "$LOG_ROOT"; }

# Seed the fake wallpaper directory with a few images.
seed_walls() {
    rm -rf "$WP_DIR"; mkdir -p "$WP_DIR"
    : > "$WP_DIR/one.jpg"
    : > "$WP_DIR/two.png"
    : > "$WP_DIR/three.JPG"
    : > "$WP_DIR/not-an-image.txt"
}

echo
echo "=== Test 1: happy path — image chosen, gsettings called 3x ==="
clear_logs; clear_calls; set_gsettings_mode ok
seed_walls
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "gsettings called 3 times" "3" "$(wc -l < "$GSETTINGS_CALL_LOG")"
check_grep "INFO mentions chosen wallpaper" '\[INFO\] set wallpaper to' "$(log_file)"

echo
echo "=== Test 2: wallpaper dir missing ==="
clear_logs; clear_calls; set_gsettings_mode ok
rm -rf "$WP_DIR"
rc=$(run_under_test)
check "non-zero exit" "1" "$rc"
check "no gsettings calls" "0" "$(wc -l < "$GSETTINGS_CALL_LOG")"
check_grep "ERROR names directory" 'wallpaper directory not found' "$(log_file)"
check_grep "ERROR includes path" "$WP_DIR" "$(log_file)"

echo
echo "=== Test 3: wallpaper dir empty (no images) ==="
clear_logs; clear_calls; set_gsettings_mode ok
mkdir -p "$WP_DIR"
: > "$WP_DIR/readme.txt"   # non-image file
rc=$(run_under_test)
check "exit 0 (not an error, just nothing to do)" "0" "$rc"
check "no gsettings calls" "0" "$(wc -l < "$GSETTINGS_CALL_LOG")"
check_grep "WARN no wallpapers found" '\[WARN\] no wallpapers found' "$(log_file)"

echo
echo "=== Test 4: DBus unavailable -> ERROR with hint ==="
clear_logs; clear_calls; set_gsettings_mode dbus
seed_walls
rc=$(run_under_test)
check "non-zero exit" "1" "$rc"
check_grep "ERROR mentions D-Bus" 'D-Bus' "$(log_file)"
check_grep "ERROR mentions import-environment hint" 'import-environment' "$(log_file)"
# After DBus error we break, so exactly 1 gsettings call
check "stopped after first failure" "1" "$(wc -l < "$GSETTINGS_CALL_LOG")"

echo
echo "=== Test 5: schema missing -> ERROR with schema hint ==="
clear_logs; clear_calls; set_gsettings_mode schema
seed_walls
rc=$(run_under_test)
check "non-zero exit" "1" "$rc"
check_grep "ERROR mentions schema" 'schema' "$(log_file)"
check_grep "ERROR mentions GNOME" 'GNOME' "$(log_file)"

echo
echo "=== Test 6: gsettings generic failure -> WARN, continues ==="
clear_logs; clear_calls; set_gsettings_mode other
seed_walls
rc=$(run_under_test)
check "exit 0 (continues through remaining calls)" "0" "$rc"
# All 3 keys attempted despite each failing
check "gsettings called 3 times" "3" "$(wc -l < "$GSETTINGS_CALL_LOG")"
check_grep "WARN mentions key" '\[WARN\] gsettings set' "$(log_file)"
# Final INFO still printed (because fail=0)
check_grep "INFO still logged (best effort)" '\[INFO\] set wallpaper' "$(log_file)"

echo
echo "=== Test 7: gsettings binary missing -> ERROR ==="
# We cannot cleanly simulate this on a system where /usr/bin/gsettings exists
# (our stub shadow only works while it's present). Skip if the real binary is
# on the system; otherwise, exercise the path.
if PATH=/usr/bin:/bin command -v gsettings >/dev/null 2>&1; then
    echo "SKIP: real gsettings on system; cannot simulate absence without reimplementing PATH"
else
    clear_logs; clear_calls; set_gsettings_mode ok
    seed_walls
    rm -f "$STUB_BIN/gsettings"
    rc=$(run_under_test)
    check "non-zero exit" "1" "$rc"
    check_grep "ERROR mentions gsettings not installed" 'gsettings not installed' "$(log_file)"
    # Restore for any further tests
    cat > "$STUB_BIN/gsettings" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$STUB_BIN/gsettings"
fi

echo
echo "=== Test 8: WALLPAPER_DIR override works ==="
clear_logs; clear_calls; set_gsettings_mode ok
alt="$TMPDIR/alt-walls"
mkdir -p "$alt"; : > "$alt/alt.jpg"
WALLPAPER_DIR="$alt" rc=$(PATH="$STUB_BIN:/usr/bin:/bin" WALLPAPER_DIR="$alt" bash "$UNDER_TEST" >/dev/null 2>&1; echo $?)
check "exit 0 with alt dir" "0" "$rc"
check_grep "INFO says alt.jpg" 'alt.jpg' "$(log_file)"

pass=$(cat "$PASS_FILE")
fail=$(cat "$FAIL_FILE")
echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
