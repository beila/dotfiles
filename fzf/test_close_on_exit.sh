#!/usr/bin/env bash
# test_close_on_exit.sh — test zellij --close-on-exit reliability
# Spawns a separate zellij session via python pty, runs tests inside it.
# Run from any terminal: bash ~/.dotfiles/fzf/test_close_on_exit.sh
set -uo pipefail

RESULT="/tmp/close-on-exit-result-$$.txt"
SESSION="close-on-exit-test-$$"
INNER="/tmp/close-on-exit-inner-$$.sh"
LAYOUT="/tmp/close-on-exit-layout-$$.kdl"

cleanup() { rm -f "$RESULT" "$INNER" "$LAYOUT"; zellij kill-session "$SESSION" 2>/dev/null; }
trap cleanup EXIT

# Inner script: runs inside the zellij session's first pane
cat > "$INNER" <<'INNER_EOF'
#!/usr/bin/env bash
set -uo pipefail
RESULT="$1"
pass=0; fail=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $desc" >> "$RESULT"
    ((pass++))
  else
    echo "  ✗ $desc: expected='$expected' actual='$actual'" >> "$RESULT"
    ((fail++))
  fi
}

pane_count() { zellij action list-panes 2>/dev/null | awk 'NR>1' | wc -l; }

echo "close-on-exit tests:" >> "$RESULT"

# Test 1: short-lived command with --close-on-exit
before=$(pane_count)
zellij run --floating --close-on-exit -- bash -c "echo done" 2>/dev/null
sleep 1
after=$(pane_count)
check "short command: pane closed" "$before" "$after"

# Test 2: fzf --filter (instant exit) with --close-on-exit
before=$(pane_count)
tmpout=$(mktemp)
zellij run --floating --close-on-exit -- bash -c "echo -e 'a\nb\nc' | fzf --filter b > $tmpout" 2>/dev/null
sleep 1
after=$(pane_count)
check "fzf --filter: pane closed" "$before" "$after"
check "fzf --filter: correct output" "b" "$(cat "$tmpout" 2>/dev/null | tr -d '\n')"
rm -f "$tmpout"

# Test 3: repeat 5 times to check reliability
failures=0
for i in $(seq 1 5); do
  before=$(pane_count)
  zellij run --floating --close-on-exit -- bash -c "echo round$i" 2>/dev/null
  sleep 0.5
  after=$(pane_count)
  [[ "$after" != "$before" ]] && ((failures++))
done
check "5 rapid runs: all panes closed (failures=$failures)" "0" "$failures"

echo "" >> "$RESULT"
echo "$((pass+fail)) tests: $pass passed, $fail failed" >> "$RESULT"
echo "DONE" >> "$RESULT"
INNER_EOF
chmod +x "$INNER"

cat > "$LAYOUT" <<EOF
layout {
  pane command="bash" {
    args "-c" "bash $INNER $RESULT"
    close_on_exit true
  }
}
EOF

rm -f "$RESULT"

# Start zellij in a python-pty with proper dimensions
python3 << PYEOF &
import pty, os, struct, fcntl, termios, subprocess, time
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
env = dict(os.environ)
env.pop('ZELLIJ', None)
env['TERM'] = 'xterm-256color'
p = subprocess.Popen(
    ['zellij', '-s', '$SESSION', '-l', '$LAYOUT'],
    stdin=slave, stdout=slave, stderr=slave,
    env=env, start_new_session=True
)
os.close(slave)
for _ in range(60):
    time.sleep(0.5)
    try: os.read(master, 8192)
    except: pass
    if os.path.exists('$RESULT'):
        with open('$RESULT') as f:
            if 'DONE' in f.read(): break
os.close(master)
p.terminate()
p.wait()
PYEOF
PY_PID=$!

# Wait for results
for i in $(seq 1 60); do
  if grep -q '^DONE$' "$RESULT" 2>/dev/null; then
    cat "$RESULT"
    kill $PY_PID 2>/dev/null
    exit 0
  fi
  sleep 0.5
done

echo "TIMEOUT — zellij session may not have started"
kill $PY_PID 2>/dev/null
cat "$RESULT" 2>/dev/null
exit 1
