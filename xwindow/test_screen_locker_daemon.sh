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
[[ $* == "show-user $UID --property=Display --value" ]] || exit 1
printf 'loginctl:%s\n' "$*" >> "$SCREEN_LOCKER_TEST_EVENTS"
printf 'test-session\n'
EOF

chmod +x "$TEST_DIR/xset" "$TEST_DIR/xss-lock" "$TEST_DIR/loginctl"

SCREEN_LOCKER_XSET="$TEST_DIR/xset" \
	SCREEN_LOCKER_XSS_LOCK="$TEST_DIR/xss-lock" \
	SCREEN_LOCKER_LOGINCTL="$TEST_DIR/loginctl" \
	SCREEN_LOCKER_COMMAND="$TEST_DIR/xsecurelock-run" \
	SCREEN_LOCKER_LOCK_FILE="$TEST_DIR/lock" \
	SCREEN_LOCKER_SESSION_ID='' \
	XDG_SESSION_ID='' \
	SCREEN_LOCKER_ONCE=1 \
	SCREEN_LOCKER_TEST_EVENTS="$EVENT_LOG" \
	"$UNDER_TEST"

rg -q "^loginctl:show-user $UID --property=Display --value$" "$EVENT_LOG"
rg -q '^xset:s 900 5$' "$EVENT_LOG"
rg -q "^xss-lock:-s test-session -l -- $TEST_DIR/xsecurelock-run$" "$EVENT_LOG"

: >"$EVENT_LOG"
SCREEN_LOCKER_XSET="$TEST_DIR/xset" \
	SCREEN_LOCKER_XSS_LOCK="$TEST_DIR/xss-lock" \
	SCREEN_LOCKER_LOGINCTL="$TEST_DIR/loginctl" \
	SCREEN_LOCKER_COMMAND="$TEST_DIR/xsecurelock-run" \
	SCREEN_LOCKER_LOCK_FILE="$TEST_DIR/lock" \
	SCREEN_LOCKER_SESSION_ID=explicit-session \
	SCREEN_LOCKER_ONCE=1 \
	SCREEN_LOCKER_TEST_EVENTS="$EVENT_LOG" \
	"$UNDER_TEST"

if rg -q '^loginctl:' "$EVENT_LOG"; then
	printf 'explicit session triggered a loginctl query\n' >&2
	exit 1
fi
rg -q "^xss-lock:-s explicit-session -l -- $TEST_DIR/xsecurelock-run$" "$EVENT_LOG"

printf 'screen locker daemon tests passed\n'
