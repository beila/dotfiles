#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UNDER_TEST="$ROOT/xwindow/bin/screen-locker-daemon"
TEST_DIR=$(mktemp -d /tmp/screen-locker-daemon-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

EVENT_LOG="$TEST_DIR/events"

cat >"$TEST_DIR/xset" <<'EOF'
#!/usr/bin/env bash
printf 'xset:%s\n' "$*" >> "$SCREEN_LOCKER_TEST_EVENTS"
EOF

cat >"$TEST_DIR/xss-lock" <<'EOF'
#!/usr/bin/env bash
printf 'xss-lock:%s\n' "$*" >> "$SCREEN_LOCKER_TEST_EVENTS"
EOF

cat >"$TEST_DIR/loginctl" <<'EOF'
#!/usr/bin/env bash
printf 'test-session %s test-user seat0 tty2 active no -\n' "$(id -u)"
EOF

chmod +x "$TEST_DIR/xset" "$TEST_DIR/xss-lock" "$TEST_DIR/loginctl"

SCREEN_LOCKER_XSET="$TEST_DIR/xset" \
	SCREEN_LOCKER_XSS_LOCK="$TEST_DIR/xss-lock" \
	SCREEN_LOCKER_LOGINCTL="$TEST_DIR/loginctl" \
	SCREEN_LOCKER_COMMAND="$TEST_DIR/xsecurelock-run" \
	SCREEN_LOCKER_LOCK_FILE="$TEST_DIR/lock" \
	SCREEN_LOCKER_ONCE=1 \
	SCREEN_LOCKER_TEST_EVENTS="$EVENT_LOG" \
	"$UNDER_TEST"

rg -q '^xset:s 900 5$' "$EVENT_LOG"
rg -q "^xss-lock:-s test-session -l -- $TEST_DIR/xsecurelock-run$" "$EVENT_LOG"

printf 'screen locker daemon tests passed\n'
