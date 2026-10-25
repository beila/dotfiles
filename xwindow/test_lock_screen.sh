#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UNDER_TEST="$ROOT/xwindow/bin/lock-screen"
TEST_DIR=$(mktemp -d /tmp/lock-screen-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

STATE_FILE="$TEST_DIR/albert-checks"
EVENT_LOG="$TEST_DIR/events"
printf '0\n' >"$STATE_FILE"

cat >"$TEST_DIR/xprop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $1 == -root ]]; then
    printf '_NET_ACTIVE_WINDOW(WINDOW): window id # 0x42\n'
    exit 0
fi

checks=$(cat "$LOCK_SCREEN_TEST_STATE")
checks=$((checks + 1))
printf '%s\n' "$checks" > "$LOCK_SCREEN_TEST_STATE"
if ((checks < 3)); then
    printf 'WM_CLASS(STRING) = "albert", "Albert"\n'
else
    printf 'WM_CLASS(STRING) = "ghostty", "com.mitchellh.ghostty"\n'
fi
EOF

cat >"$TEST_DIR/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep:%s\n' "$1" >> "$LOCK_SCREEN_TEST_EVENTS"
EOF

cat >"$TEST_DIR/locker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
checks=$(cat "$LOCK_SCREEN_TEST_STATE")
if ((checks < 3)); then
    printf 'locker started while Albert was active\n' >&2
    exit 1
fi
printf 'locker:%s\n' "$*" >> "$LOCK_SCREEN_TEST_EVENTS"
EOF

chmod +x "$TEST_DIR/xprop" "$TEST_DIR/sleep" "$TEST_DIR/locker"

LOCK_SCREEN_XPROP="$TEST_DIR/xprop" \
	LOCK_SCREEN_SLEEP="$TEST_DIR/sleep" \
	LOCK_SCREEN_COMMAND="$TEST_DIR/locker" \
	LOCK_SCREEN_TEST_STATE="$STATE_FILE" \
	LOCK_SCREEN_TEST_EVENTS="$EVENT_LOG" \
	"$UNDER_TEST"

[[ $(cat "$STATE_FILE") == 3 ]]
[[ $(tail -n 1 "$EVENT_LOG") == "locker:--lock" ]]

cat >"$TEST_DIR/xprop-stuck" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $1 == -root ]]; then
    printf '_NET_ACTIVE_WINDOW(WINDOW): window id # 0x42\n'
else
    printf 'WM_CLASS(STRING) = "albert", "Albert"\n'
fi
EOF

cat >"$TEST_DIR/locker-unexpected" <<'EOF'
#!/usr/bin/env bash
printf 'locker was called\n' >&2
exit 1
EOF

chmod +x "$TEST_DIR/xprop-stuck" "$TEST_DIR/locker-unexpected"

set +e
LOCK_SCREEN_XPROP="$TEST_DIR/xprop-stuck" \
	LOCK_SCREEN_SLEEP="$TEST_DIR/sleep" \
	LOCK_SCREEN_COMMAND="$TEST_DIR/locker-unexpected" \
	LOCK_SCREEN_WAIT_ATTEMPTS=2 \
	LOCK_SCREEN_TEST_EVENTS="$EVENT_LOG" \
	timeout 1 "$UNDER_TEST" 2>"$TEST_DIR/stuck-error"
rc=$?
set -e

[[ $rc == 1 ]]
rg -q 'Albert did not release input focus' "$TEST_DIR/stuck-error"

albert_lock_command=$(
	sed -n 's/^command_lock=//p' "$ROOT/albert.configsymlink/config"
)
[[ $albert_lock_command == "\$HOME/.dotfiles/xwindow/bin/lock-screen" ]]

printf 'lock-screen tests passed\n'
