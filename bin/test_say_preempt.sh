#!/usr/bin/env bash
# Test: bin/say preempts already-playing TTS via PGID kill.
# Stubs say-en/say-ko with a long-sleeping process so we can observe both the
# kill-previous and the cleanup paths without producing audio.
# Run: bash bin/test_say_preempt.sh

set -uo pipefail
pass=0 fail=0
assert_eq() {
    if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1"; echo "    expected: $3"; echo "    got: $2"; ((fail++)); fi
}
assert_true() {
    if eval "$2"; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1: $2"; ((fail++)); fi
}

dotfiles="$(cd "$(dirname "$0")/.." && pwd)"
real_say="$dotfiles/bin/say"

# Stage a fake DOTFILES_ROOT with stub backends — say-en/say-ko both `sleep 30`
# until killed. Stubs write their PID to a file so we can verify what got killed.
tmp=$(mktemp -d /tmp/test_say_preempt.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cp "$real_say" "$tmp/bin/say"

cat >"$tmp/bin/say-en" <<'EOF'
#!/usr/bin/env bash
echo "$$" >"$SAY_TEST_LAST_BACKEND_PID"
trap 'echo terminated >>"$SAY_TEST_EVENTS"; exit 143' TERM
sleep 30 &
wait $!
EOF
cp "$tmp/bin/say-en" "$tmp/bin/say-ko"
chmod +x "$tmp/bin"/say-*

state_file="$tmp/say.pgid"
events="$tmp/events"
last_pid="$tmp/last_pid"
: >"$events"

run_say() {
    DOTFILES_ROOT="$tmp" \
    SAY_STATE_FILE="$state_file" \
    SAY_TEST_EVENTS="$events" \
    SAY_TEST_LAST_BACKEND_PID="$last_pid" \
        "$tmp/bin/say" "$@"
}

echo "Test 1: state file written when say spawns a backend"
run_say "first" &
say1=$!
# Wait for the backend to record its PID + state file to settle
for _ in $(seq 1 50); do
    [ -s "$state_file" ] && [ -s "$last_pid" ] && break
    sleep 0.05
done
assert_true "state file exists" "[ -s '$state_file' ]"
backend1=$(cat "$last_pid")
recorded1=$(cat "$state_file")
assert_eq "state file matches backend PID (setsid: PID==PGID)" "$recorded1" "$backend1"

echo
echo "Test 2: a second say invocation kills the first backend"
run_say "second" &
say2=$!
# First backend should die; second should now be the recorded one
for _ in $(seq 1 100); do
    if ! kill -0 "$backend1" 2>/dev/null; then break; fi
    sleep 0.05
done
assert_true "first backend was killed" "! kill -0 '$backend1' 2>/dev/null"
assert_true "first backend recorded TERM via trap" "grep -q terminated '$events'"

# Wait for second to settle
for _ in $(seq 1 50); do
    [ -s "$last_pid" ] && [ "$(cat "$last_pid")" != "$backend1" ] && break
    sleep 0.05
done
backend2=$(cat "$last_pid")
recorded2=$(cat "$state_file")
assert_eq "state file now points at second backend" "$recorded2" "$backend2"
assert_true "second backend is alive" "kill -0 '$backend2' 2>/dev/null"

# Wait for first say wrapper to finish (it should have exited cleanly)
wait "$say1" 2>/dev/null || true

echo
echo "Test 3: external TERM to the say wrapper tears down its backend"
# Spawn a fresh say wrapper specifically for this test to avoid harness races
# with prior preemption flows that may have already torn things down.
run_say "test3-target" &
say3_target=$!
for _ in $(seq 1 50); do
    [ -s "$last_pid" ] && [ "$(cat "$last_pid")" != "$backend2" ] && break
    sleep 0.05
done
backend3a=$(cat "$last_pid")
assert_true "test3 backend started" "kill -0 '$backend3a' 2>/dev/null"
assert_true "test3 say wrapper alive" "kill -0 '$say3_target' 2>/dev/null"
sleep 0.3  # ensure trap is registered before we send TERM
echo "    DEBUG: say3_target=$say3_target backend3a=$backend3a"
ps -o pid,ppid,pgid,sid,cmd -p "$say3_target","$backend3a" 2>&1 | sed 's/^/    /'
kill -TERM "$say3_target"
echo "    DEBUG: after kill, say3_target alive: $(kill -0 $say3_target 2>/dev/null && echo yes || echo no)"
for _ in $(seq 1 100); do
    if ! kill -0 "$backend3a" 2>/dev/null; then break; fi
    sleep 0.05
done
echo "    DEBUG: backend3a still alive: $(kill -0 $backend3a 2>/dev/null && echo yes || echo no)"
assert_true "test3 backend killed via wrapper's TERM trap" "! kill -0 '$backend3a' 2>/dev/null"

wait "$say2" 2>/dev/null || true
wait "$say3_target" 2>/dev/null || true

echo
echo "Test 4: stale state file (PID no longer alive) is harmless"
echo 999999 >"$state_file"
run_say "third" &
say4=$!
for _ in $(seq 1 50); do
    [ -s "$last_pid" ] && [ "$(cat "$last_pid")" != "$backend3a" ] && break
    sleep 0.05
done
backend4=$(cat "$last_pid")
assert_true "fourth backend started despite stale state file" "kill -0 '$backend4' 2>/dev/null"
kill -TERM "$say4" 2>/dev/null || true
wait "$say4" 2>/dev/null || true

echo
echo "Test 5: SAY_NO_PREEMPT=1 skips preemption + state-file write"
# Start a victim that should NOT be killed
run_say "victim" &
say_victim=$!
for _ in $(seq 1 50); do
    [ -s "$last_pid" ] && [ "$(cat "$last_pid")" != "$backend4" ] && break
    sleep 0.05
done
victim_backend=$(cat "$last_pid")
victim_state=$(cat "$state_file")

SAY_NO_PREEMPT=1 \
DOTFILES_ROOT="$tmp" \
SAY_STATE_FILE="$state_file" \
SAY_TEST_EVENTS="$events" \
SAY_TEST_LAST_BACKEND_PID="$last_pid" \
    "$tmp/bin/say" "no-preempt-call" &
say_np=$!
sleep 0.3
assert_true "victim backend still alive (no preemption)" "kill -0 '$victim_backend' 2>/dev/null"
# state file should still point at victim, not at the no-preempt call
assert_eq "state file unchanged when SAY_NO_PREEMPT=1" "$(cat "$state_file" 2>/dev/null)" "$victim_state"

# Cleanup
kill -TERM "$say_np" 2>/dev/null || true
kill -TERM "$say_victim" 2>/dev/null || true
wait "$say_np" 2>/dev/null || true
wait "$say_victim" 2>/dev/null || true

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
