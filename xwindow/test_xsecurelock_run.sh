#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UNDER_TEST="$ROOT/xwindow/bin/xsecurelock-run"
TEST_DIR=$(mktemp -d /tmp/xsecurelock-run-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

EVENT_LOG="$TEST_DIR/events"

cat >"$TEST_DIR/xprop" <<'EOF'
#!/usr/bin/env bash
printf 'xprop:%s\n' "$*" >> "$XSECURELOCK_RUN_TEST_EVENTS"
EOF

cat >"$TEST_DIR/wallpaper" <<'EOF'
#!/usr/bin/env bash
printf '/tmp/wallpaper.jpg\n'
EOF

cat >"$TEST_DIR/locker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'saver:%s\n' "$XSECURELOCK_SAVER" >> "$XSECURELOCK_RUN_TEST_EVENTS"
printf 'wallpaper:%s\n' "$XSECURELOCK_LIST_VIDEOS_COMMAND" >> "$XSECURELOCK_RUN_TEST_EVENTS"
printf 'username:%s\n' "$XSECURELOCK_USERNAME" >> "$XSECURELOCK_RUN_TEST_EVENTS"
printf 'authproto:%s\n' "$XSECURELOCK_AUTHPROTO" >> "$XSECURELOCK_RUN_TEST_EVENTS"
while (($#)); do
	if [[ $1 == -- ]]; then
		shift
		"$@"
		break
	fi
	shift
done
EOF

touch "$TEST_DIR/authproto"
chmod +x "$TEST_DIR/xprop" "$TEST_DIR/wallpaper" "$TEST_DIR/locker" "$TEST_DIR/authproto"

XSECURELOCK_RUN_XPROP="$TEST_DIR/xprop" \
	XSECURELOCK_RUN_COMMAND="$TEST_DIR/locker" \
	XSECURELOCK_RUN_WALLPAPER="$TEST_DIR/wallpaper" \
	XSECURELOCK_RUN_AUTHPROTO="$TEST_DIR/authproto" \
	XSECURELOCK_RUN_LOCK_FILE="$TEST_DIR/lock" \
	XSECURELOCK_RUN_TEST_EVENTS="$EVENT_LOG" \
	"$UNDER_TEST"

rg -q '^saver:saver_mpv$' "$EVENT_LOG"
rg -q "^wallpaper:$TEST_DIR/wallpaper$" "$EVENT_LOG"
rg -q "^username:$(/usr/bin/id -un)$" "$EVENT_LOG"
rg -q "^authproto:$TEST_DIR/authproto$" "$EVENT_LOG"
mapfile -t states < <(rg 'xprop:.*-set _XMONAD_SCREEN_LOCKED [01]$' "$EVENT_LOG")
[[ ${#states[@]} == 2 ]]
[[ ${states[0]} == *"_XMONAD_SCREEN_LOCKED 1" ]]
[[ ${states[1]} == *"_XMONAD_SCREEN_LOCKED 0" ]]

cat >"$TEST_DIR/locker-fail" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TEST_DIR/locker-fail"
: >"$EVENT_LOG"

set +e
XSECURELOCK_RUN_XPROP="$TEST_DIR/xprop" \
	XSECURELOCK_RUN_COMMAND="$TEST_DIR/locker-fail" \
	XSECURELOCK_RUN_WALLPAPER="$TEST_DIR/wallpaper" \
	XSECURELOCK_RUN_AUTHPROTO="$TEST_DIR/authproto" \
	XSECURELOCK_RUN_LOCK_FILE="$TEST_DIR/lock" \
	XSECURELOCK_RUN_TEST_EVENTS="$EVENT_LOG" \
	"$UNDER_TEST"
rc=$?
set -e

[[ $rc == 1 ]]
if rg -q '_XMONAD_SCREEN_LOCKED 1$' "$EVENT_LOG"; then
	printf 'failed locker published the locked state\n' >&2
	exit 1
fi
rg -q '_XMONAD_SCREEN_LOCKED 0$' "$EVENT_LOG"

printf 'xsecurelock runner tests passed\n'
