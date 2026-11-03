#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REAL_SLEEP=$(command -v sleep)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_CALLS"
if [[ $* == *--stream-state* ]]; then
    printf '%s\n' "$$" > "$TEST_WATCHER_PID"
    printf 'prompt\t~/project\n'
    exec "$TEST_REAL_SLEEP" 30
fi
for _ in {1..100}; do
    [[ ! -f $TEST_WATCHER_PID ]] || exit "$TEST_SSH_STATUS"
    "$TEST_REAL_SLEEP" 0.01
done
exit 98
EOF
chmod +x "$TMP/bin/ssh"

export PATH="$TMP/bin:$PATH" ZMX_SESSION="local/session"
export TEST_REAL_SLEEP="$REAL_SLEEP"
for expected in 0 42 255; do
    export ZMX_REMOTE_DIR="$TMP/runtime-$expected"
    export TEST_CALLS="$TMP/calls-$expected"
    export TEST_WATCHER_PID="$TMP/watcher-$expected"
    export TEST_SSH_STATUS="$expected"
    status=0
    timeout 5 "$ROOT/zmx-remote-attach" c "remote session" || status=$?
    [[ $status == "$expected" ]]
    [[ ! -e $ZMX_REMOTE_DIR/local_session ]]
    [[ ! -e $ZMX_REMOTE_DIR/local_session.state ]]
    [[ ! -e $ZMX_REMOTE_DIR/local_session.state.tmp ]]
    rg -q -- '-t -o BatchMode=yes -o ConnectTimeout=10' "$TEST_CALLS"
    [[ $(rg -c 'ServerAliveInterval=15 -o ServerAliveCountMax=3' "$TEST_CALLS") == 2 ]]
    [[ $(rg -c 'remote\\ session' "$TEST_CALLS") == 2 ]]
    watcher=$(< "$TEST_WATCHER_PID")
    for _ in {1..100}; do
        ! kill -0 "$watcher" 2>/dev/null && break
        "$REAL_SLEEP" 0.01
    done
    if kill -0 "$watcher" 2>/dev/null; then
        printf 'remote state watcher survived SSH exit\n' >&2
        exit 1
    fi
done

printf 'zmx remote attach tests passed\n'
