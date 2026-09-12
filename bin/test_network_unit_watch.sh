#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WATCH="$ROOT/bin/network-unit-watch"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STUBS="$TMP/bin"
ACTIVE_CONNECTIONS="$TMP/active-connections"
ACTIVE_UNIT="$TMP/active-unit"
CALLS="$TMP/systemctl.calls"
mkdir -p "$STUBS"

cat >"$STUBS/nmcli" <<'EOF'
#!/usr/bin/env bash
[[ -f "$TEST_ACTIVE_CONNECTIONS" ]] || exit 1
cat "$TEST_ACTIVE_CONNECTIONS"
EOF

cat >"$STUBS/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == "--user" ]] || exit 2
shift

case ${1:-} in
    is-active)
        [[ ${2:-} == "--quiet" ]] || exit 2
        [[ -f "$TEST_ACTIVE_UNIT" ]]
        ;;
    start)
        printf 'start %s\n' "$2" >>"$TEST_SYSTEMCTL_CALLS"
        : >"$TEST_ACTIVE_UNIT"
        ;;
    stop)
        printf 'stop %s\n' "$2" >>"$TEST_SYSTEMCTL_CALLS"
        rm -f "$TEST_ACTIVE_UNIT"
        ;;
    *)
        exit 2
        ;;
esac
EOF

cat >"$STUBS/gdbus" <<'EOF'
#!/usr/bin/env bash
if [[ -n ${TEST_EVENT_CONNECTIONS:-} ]]; then
    printf '%s\n' "$TEST_EVENT_CONNECTIONS" >"$TEST_ACTIVE_CONNECTIONS"
fi
printf '/org/freedesktop/NetworkManager: org.freedesktop.DBus.Properties.PropertiesChanged\n'
EOF

chmod +x "$STUBS/nmcli" "$STUBS/systemctl" "$STUBS/gdbus"

pass=0
fail=0

check() {
    local description=$1 expected=$2 actual=$3
    if [[ "$actual" == "$expected" ]]; then
        printf 'PASS: %s\n' "$description"
        pass=$((pass + 1))
    else
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' \
            "$description" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

run_once() {
    TEST_ACTIVE_CONNECTIONS="$ACTIVE_CONNECTIONS" \
        TEST_ACTIVE_UNIT="$ACTIVE_UNIT" \
        TEST_SYSTEMCTL_CALLS="$CALLS" \
        PATH="$STUBS:/usr/bin:/bin" \
        "$WATCH" --once "InsukHojin4" "network-rclone-mount.service"
}

: >"$CALLS"
printf 'Other\nInsukHojin4\n' >"$ACTIVE_CONNECTIONS"
run_once
check "starts the unit when the exact connection is active" \
    "start network-rclone-mount.service" "$(cat "$CALLS")"

run_once
check "does not restart an already-active unit" \
    "1" "$(wc -l <"$CALLS" | tr -d ' ')"

printf 'InsukHojin40\n' >"$ACTIVE_CONNECTIONS"
run_once
check "a prefix match does not count as the configured connection" \
    "stop network-rclone-mount.service" "$(tail -n 1 "$CALLS")"

: >"$ACTIVE_UNIT"
rm -f "$ACTIVE_CONNECTIONS"
run_once
check "stops the unit when NetworkManager state is unavailable" \
    "stop network-rclone-mount.service" "$(tail -n 1 "$CALLS")"

: >"$CALLS"
rm -f "$ACTIVE_UNIT"
printf 'Other\n' >"$ACTIVE_CONNECTIONS"
TEST_ACTIVE_CONNECTIONS="$ACTIVE_CONNECTIONS" \
    TEST_ACTIVE_UNIT="$ACTIVE_UNIT" \
    TEST_SYSTEMCTL_CALLS="$CALLS" \
    TEST_EVENT_CONNECTIONS="InsukHojin4" \
    NETWORK_UNIT_WATCH_RETRY_SEC=5 \
    PATH="$STUBS:/usr/bin:/bin" \
    timeout 1 "$WATCH" "InsukHojin4" "network-rclone-mount.service" || true
check "reacts to a NetworkManager property-change event" \
    "start network-rclone-mount.service" "$(head -n 1 "$CALLS")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
