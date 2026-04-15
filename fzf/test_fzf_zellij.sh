#!/usr/bin/env bash
# test_fzf_zellij.sh — fzf-zellij tests (run inside zellij or standalone)
# Run: bash ~/.dotfiles/fzf/test_fzf_zellij.sh
set -uo pipefail

# If not inside zellij or not on a tty (e.g. kiro), spawn a temporary session and re-run inside it
if [[ -z ${_FZF_ZELLIJ_TEST_INNER:-} ]] && { [[ -z ${ZELLIJ:-} ]] || [[ ! -t 1 ]]; }; then
  RESULT=$(mktemp)
  SESSION="fzf-zellij-test-$$"
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  python3 -c "
import pty,os,struct,fcntl,termios,subprocess,time,threading
master,slave=pty.openpty()
fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',40,120,0,0))
env=dict(os.environ)
[env.pop(k,None) for k in list(env) if k.startswith('ZELLIJ')]
env['TERM']='xterm-256color'
def drain(fd):
 while True:
  try:
   if not os.read(fd,8192):break
  except OSError:break
p=subprocess.Popen(['zellij','-s','$SESSION'],stdin=slave,stdout=slave,stderr=slave,env=env)
os.close(slave)
threading.Thread(target=drain,args=(master,),daemon=True).start()
for _ in range(20):
 time.sleep(0.5)
 if '$SESSION' in subprocess.run(['zellij','list-sessions'],capture_output=True,text=True).stdout:break
else:
 print('session never started');p.terminate();exit(1)
time.sleep(1)
te=dict(os.environ);[te.pop(k,None) for k in list(te) if k.startswith('ZELLIJ')]
te['ZELLIJ_SESSION_NAME']='$SESSION'
subprocess.run(['zellij','-s','$SESSION','run','--floating','--close-on-exit','--','bash','-c',
 '_FZF_ZELLIJ_TEST_INNER=1 bash $SELF > $RESULT 2>&1; echo ALLDONE >> $RESULT'],env=te,capture_output=True)
for _ in range(120):
 time.sleep(0.5)
 if os.path.exists('$RESULT'):
  with open('$RESULT') as f:
   if 'ALLDONE' in f.read():break
p.terminate();p.wait();os.close(master)
os.system('zellij kill-session $SESSION 2>/dev/null')
"
  # Print results and propagate exit code
  sed '/^ALLDONE$/d' "$RESULT"
  grep -q '0 failed' "$RESULT"; rc=$?
  rm -f "$RESULT"
  exit "$rc"
fi

FZF_ZELLIJ="$(dirname "$0")/fzf-zellij"
pass=0; fail=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $desc"
    ((pass++))
  else
    echo "  ✗ $desc: expected='$expected' actual='$actual'"
    ((fail++))
  fi
}

pane_ids() { zellij action list-panes 2>/dev/null | awk 'NR>1{print $1}'; }

cleanup() {
  local before="$1" leftover=0
  for p in $(pane_ids); do
    if ! echo "$before" | grep -qx "$p"; then
      ((leftover++))
      zellij action close-pane --pane-id "$p" 2>/dev/null || true
    fi
  done
  echo "$leftover"
}

before=$(pane_ids)

echo "basic:"
out=$(timeout 5 bash -c 'echo -e "apple\nbanana\ncherry" | '"$FZF_ZELLIJ"' -- --filter banana' 2>/dev/null)
check "piped input + filter returns match" "banana" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo "fallback:"
out=$(ZELLIJ= timeout 5 bash -c 'echo -e "one\ntwo" | '"$FZF_ZELLIJ"' -- --filter two' 2>/dev/null)
check "fallback when ZELLIJ unset" "two" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo "pipeline:"
out=$(timeout 5 bash -c 'echo -e "◆  abc 1h some description\n○  xyz 2h another" |
  '"$FZF_ZELLIJ"' -- --ansi --no-sort --reverse --filter "abc" |
  sed "s/\x1b\[[0-9;]*m//g" | grep -o "^[^a-z(]*[a-z]\{1,\}" | grep -o "[a-z]\{1,\}$" | head -1' 2>/dev/null)
check "pipeline extracts id" "abc" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo "nested:"
out=$(FZF_ZELLIJ=1 timeout 5 bash -c 'echo -e "apple\nbanana" | '"$FZF_ZELLIJ"' -- --filter apple' 2>/dev/null)
check "FZF_ZELLIJ=1 skips floating pane" "apple" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

out=$(FZF_ZELLIJ=1 timeout 5 bash -c 'echo -e "◆  abc 1h desc\n○  xyz 2h other" |
  '"$FZF_ZELLIJ"' -- --ansi --no-sort --reverse --filter "xyz" |
  sed "s/\x1b\[[0-9;]*m//g" | grep -o "^[^a-z(]*[a-z]\{1,\}" | grep -o "[a-z]\{1,\}$" | head -1' 2>/dev/null)
check "nested pipeline extracts id" "xyz" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo "close-on-exit (zellij #5010 race fix):"
# Test: short-lived command pane auto-closes with --close-on-exit
before_coe=$(pane_ids)
tmpout=$(mktemp)
zellij run --floating --close-on-exit -- bash -c "echo hello > $tmpout" 2>/dev/null
sleep 1
check "short command: pane auto-closed" "0" "$(cleanup "$before_coe")"
check "short command: output written" "hello" "$(cat "$tmpout" 2>/dev/null)"
rm -f "$tmpout"

# Test: fzf --filter via zellij run --close-on-exit (instant exit)
before_coe=$(pane_ids)
tmpout=$(mktemp)
zellij run --floating --close-on-exit -- bash -c 'echo -e "a\nb\nc" | fzf --filter b > '"$tmpout" 2>/dev/null
sleep 1
check "fzf --filter: pane auto-closed" "0" "$(cleanup "$before_coe")"
check "fzf --filter: correct output" "b" "$(cat "$tmpout" 2>/dev/null | tr -d '\n')"
rm -f "$tmpout"

# Test: 5 rapid runs to check reliability
coe_failures=0
for i in $(seq 1 5); do
  before_coe=$(pane_ids)
  zellij run --floating --close-on-exit -- bash -c "true" 2>/dev/null >/dev/null
  sleep 0.5
  leftover=$(cleanup "$before_coe")
  [[ "$leftover" != "0" ]] && ((coe_failures++))
done
check "5 rapid runs: all panes auto-closed" "0" "$coe_failures"

echo ""
echo "$((pass+fail)) tests: $pass passed, $fail failed"
exit "$fail"
