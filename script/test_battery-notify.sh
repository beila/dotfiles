#!/usr/bin/env bash
# test_battery-notify.sh — harness for script/battery-notify.
#
# Exercises each decision branch against a fake sysfs tree. Stubs
# notify-send so the desktop isn't spammed and we can see it was called.

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$DOTFILES_ROOT/script/battery-notify"

TMPDIR=$(mktemp -d /tmp/test_battery_notify.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_MACHINE_NAME="testhost"
export LOG_NOTIFY_MODE=never
# Default LOG_KEEP_THRESHOLD is ERROR, which means INFO/WARN log lines are
# discarded on exit. Tests assert on INFO/WARN content, so persist everything.
export LOG_KEEP_THRESHOLD=DEBUG
export DOTFILES_ROOT

# Fake sysfs tree and state file.
FAKE_SYSFS="$TMPDIR/sys"
FAKE_BAT="$FAKE_SYSFS/BAT0"
mkdir -p "$FAKE_BAT"
STATE_FILE="$TMPDIR/state"
export BATTERY_NOTIFY_POWER_SUPPLY_DIR="$FAKE_SYSFS"
export BATTERY_NOTIFY_BAT_DIR="$FAKE_BAT"
export BATTERY_NOTIFY_STATE_FILE="$STATE_FILE"

# Stub notify-send via PATH injection: records calls to $NOTIFY_SEND_LOG.
STUB_BIN="$TMPDIR/bin"
mkdir -p "$STUB_BIN"
export NOTIFY_SEND_LOG="$TMPDIR/notify-send-calls"
: > "$NOTIFY_SEND_LOG"
cat > "$STUB_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'CALL\t%s\n' "$*" >> "$NOTIFY_SEND_LOG"
EOF
chmod +x "$STUB_BIN/notify-send"

# Stub battery-osd via $BATTERY_OSD_BIN override; battery-notify resolves
# this absolute path before invoking, so PATH injection doesn't help.
export BATTERY_OSD_LOG="$TMPDIR/battery-osd-calls"
export BATTERY_OSD_BIN="$STUB_BIN/battery-osd"
: > "$BATTERY_OSD_LOG"
cat > "$BATTERY_OSD_BIN" <<'EOF'
#!/usr/bin/env bash
printf 'CALL\t%s\n' "$*" >> "$BATTERY_OSD_LOG"
EOF
chmod +x "$BATTERY_OSD_BIN"

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

set_bat() {
    local status=$1 cap=$2
    echo "$status" > "$FAKE_BAT/status"
    echo "$cap"    > "$FAKE_BAT/capacity"
}

run_under_test() {
    PATH="$STUB_BIN:$PATH" bash "$UNDER_TEST" >/dev/null 2>&1
    echo $?
}

clear_logs() { rm -rf "$LOG_ROOT"; }
clear_state() { rm -f "$STATE_FILE"; }
clear_notify() { : > "$NOTIFY_SEND_LOG"; : > "$BATTERY_OSD_LOG"; }

log_file() { find "$LOG_ROOT" -type f -name 'battery-notify.*.log' 2>/dev/null | head -1; }

echo
echo "=== Test 1: charging at 50% — nothing happens ==="
clear_logs; clear_state; clear_notify
set_bat "Charging" 50
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "no notify-send call" "0" "$(wc -l < "$NOTIFY_SEND_LOG")"
check "no battery-osd call" "0" "$(wc -l < "$BATTERY_OSD_LOG")"
check "no state file" "no" "$([ -f "$STATE_FILE" ] && echo yes || echo no)"
check "no log line" "no" "$([ -f "$(log_file)" ] && echo yes || echo no)"

echo
echo "=== Test 2: discharging at 50% — nothing ==="
clear_logs; clear_state; clear_notify
set_bat "Discharging" 50
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "no notify-send call" "0" "$(wc -l < "$NOTIFY_SEND_LOG")"
check "no battery-osd call" "0" "$(wc -l < "$BATTERY_OSD_LOG")"
check "no state file" "no" "$([ -f "$STATE_FILE" ] && echo yes || echo no)"

echo
echo "=== Test 3: discharging at 20% — warn popup + INFO log ==="
clear_logs; clear_state; clear_notify
set_bat "Discharging" 20
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "one notify-send call" "1" "$(wc -l < "$NOTIFY_SEND_LOG")"
check_grep "notify-send Battery Low" "Battery Low" "$NOTIFY_SEND_LOG"
check "no battery-osd call (low, not critical)" "0" "$(wc -l < "$BATTERY_OSD_LOG")"
check "state file is 20" "20" "$(cat "$STATE_FILE")"
check_grep "INFO log at low threshold" '\[INFO\] battery at 20%' "$(log_file)"

echo
echo "=== Test 4: discharging at 10% — battery-osd OSD + WARN log ==="
clear_logs; clear_state; clear_notify
set_bat "Discharging" 10
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "no notify-send (replaced by OSD)" "0" "$(wc -l < "$NOTIFY_SEND_LOG")"
check "one battery-osd call" "1" "$(wc -l < "$BATTERY_OSD_LOG")"
check_grep "battery-osd called with 10" $'CALL\t10' "$BATTERY_OSD_LOG"
check "state file is 10" "10" "$(cat "$STATE_FILE")"
check_grep "WARN log at critical threshold" '\[WARN\] battery at 10%' "$(log_file)"

echo
echo "=== Test 5: re-run at 20% already warned — no duplicate notification ==="
clear_logs; clear_notify
echo 20 > "$STATE_FILE"
set_bat "Discharging" 18
rc=$(run_under_test)
check "no notify-send call" "0" "$(wc -l < "$NOTIFY_SEND_LOG")"
check "no battery-osd call" "0" "$(wc -l < "$BATTERY_OSD_LOG")"
check "state file stays 20" "20" "$(cat "$STATE_FILE")"

echo
echo "=== Test 6: re-run at 10% already critical — no duplicate ==="
clear_logs; clear_notify
echo 10 > "$STATE_FILE"
set_bat "Discharging" 8
rc=$(run_under_test)
check "no notify-send call" "0" "$(wc -l < "$NOTIFY_SEND_LOG")"
check "no battery-osd call" "0" "$(wc -l < "$BATTERY_OSD_LOG")"

echo
echo "=== Test 7: crossing 20% -> 10% while discharging — critical OSD fires ==="
clear_logs; clear_notify
echo 20 > "$STATE_FILE"
set_bat "Discharging" 9
rc=$(run_under_test)
check "no notify-send (replaced by OSD)" "0" "$(wc -l < "$NOTIFY_SEND_LOG")"
check "one battery-osd call" "1" "$(wc -l < "$BATTERY_OSD_LOG")"
check_grep "battery-osd called with 9" $'CALL\t9' "$BATTERY_OSD_LOG"
check "state file bumps to 10" "10" "$(cat "$STATE_FILE")"

echo
echo "=== Test 8: charger plugged back in — state reset ==="
clear_logs; clear_notify
echo 10 > "$STATE_FILE"
set_bat "Charging" 15
rc=$(run_under_test)
check "state file removed" "no" "$([ -f "$STATE_FILE" ] && echo yes || echo no)"

echo
echo "=== Test 9: battery missing -> actionable ERROR, logged once ==="
clear_logs; clear_state; clear_notify
# Remove the battery dir
rm -rf "$FAKE_BAT"
mkdir -p "$FAKE_SYSFS/cmb0"  # simulate some other power supply exists
rc=$(run_under_test)
check "exit 0 (don't die)" "0" "$rc"
check_grep "ERROR battery not found" '\[ERROR\] battery not found' "$(log_file)"
check_grep "lists available supplies" "cmb0" "$(log_file)"
check "state=missing" "missing" "$(cat "$STATE_FILE")"

echo
echo "=== Test 10: battery still missing on re-run — no duplicate ERROR ==="
clear_logs; clear_notify
# State=missing set by previous test; run again
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "no new log" "no" "$([ -f "$(log_file)" ] && echo yes || echo no)"

echo
echo "=== Test 11: capacity value is garbage — WARN, not fatal ==="
clear_logs; clear_state; clear_notify
mkdir -p "$FAKE_BAT"
set_bat "Discharging" "abc"
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check_grep "WARN about capacity" '\[WARN\] unexpected capacity' "$(log_file)"
check "no notify-send call" "0" "$(wc -l < "$NOTIFY_SEND_LOG")"
check "no battery-osd call" "0" "$(wc -l < "$BATTERY_OSD_LOG")"

echo
echo "=== Test 12: status file unreadable -> ERROR ==="
clear_logs; clear_state; clear_notify
set_bat "Discharging" 50
chmod 000 "$FAKE_BAT/status"
rc=$(run_under_test)
chmod 644 "$FAKE_BAT/status"  # restore for cleanup
check "non-zero exit" "1" "$rc"
check_grep "ERROR unreadable" 'unreadable\|Check permissions' "$(log_file)"

pass=$(cat "$PASS_FILE")
fail=$(cat "$FAIL_FILE")
echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
