#!/usr/bin/env bash
# test_flake-update.sh — harness for script/flake-update.
#
# Stubs `nix`, `home-manager`, and `claude` via PATH override so we can
# exercise each branch (network fail, build fail, news classified as
# BREAKING, news classified as OK, classifier unavailable, lock unchanged)
# without touching the real flake or invoking real LLMs.

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$DOTFILES_ROOT/script/flake-update"

TMPDIR=$(mktemp -d /tmp/test_flake_update.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_MACHINE_NAME="testhost"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG  # persist all log lines for assertions
export DOTFILES_ROOT

# Fake flake dir: real flake.nix + flake.lock with a "before" + "after" pair.
FAKE_FLAKE="$TMPDIR/flake"
mkdir -p "$FAKE_FLAKE"
cat > "$FAKE_FLAKE/flake.nix" <<'EOF'
{ outputs = { ... }: {}; }
EOF
# Initial lock — what's "before" the update.
cat > "$FAKE_FLAKE/flake.lock.before" <<'EOF'
{ "nodes": { "nixpkgs": { "locked": { "rev": "aaaaaaaa" } } } }
EOF
# Post-update lock — what `nix flake update` should produce.
cat > "$FAKE_FLAKE/flake.lock.after" <<'EOF'
{ "nodes": { "nixpkgs": { "locked": { "rev": "bbbbbbbb" } } } }
EOF
export FLAKE_UPDATE_FLAKE_DIR="$FAKE_FLAKE"

# Stub bin dir; PATH = stubs only + system paths needed for jq, head, sed, etc.
STUB_BIN="$TMPDIR/bin"
mkdir -p "$STUB_BIN"

# Stubs are controlled by env vars so each test case can flip behaviour
# without rewriting the script.
export STUB_NIX_MODE_FILE="$TMPDIR/nix-mode"
export STUB_HM_MODE_FILE="$TMPDIR/hm-mode"
export STUB_CLAUDE_MODE_FILE="$TMPDIR/claude-mode"
export STUB_HM_NEWS_FILE="$TMPDIR/hm-news"
export STUB_CLAUDE_OUT_FILE="$TMPDIR/claude-out"

cat > "$STUB_BIN/nix" <<'EOF'
#!/usr/bin/env bash
mode=$(cat "$STUB_NIX_MODE_FILE" 2>/dev/null || echo ok)
if [ "$1" = "flake" ] && [ "$2" = "update" ]; then
    case "$mode" in
        ok)         cp "$FLAKE_UPDATE_FLAKE_DIR/flake.lock.after" "$FLAKE_UPDATE_FLAKE_DIR/flake.lock"; exit 0 ;;
        nochange)   cp "$FLAKE_UPDATE_FLAKE_DIR/flake.lock.before" "$FLAKE_UPDATE_FLAKE_DIR/flake.lock"; exit 0 ;;
        network)    echo "error: unable to download 'github:nixos/nixpkgs': Could not resolve hostname" >&2; exit 1 ;;
        other)      echo "error: something else broke" >&2; exit 1 ;;
        *)          exit 1 ;;
    esac
fi
exit 0
EOF
chmod +x "$STUB_BIN/nix"

cat > "$STUB_BIN/home-manager" <<'EOF'
#!/usr/bin/env bash
mode=$(cat "$STUB_HM_MODE_FILE" 2>/dev/null || echo ok)
if [ "$1" = "build" ]; then
    case "$mode" in
        ok)        ln -sf /tmp /tmp/result_link 2>/dev/null; touch "$FLAKE_UPDATE_FLAKE_DIR/result"; exit 0 ;;
        fail)      echo "error: option 'foo' has been removed" >&2; echo "warning: see release notes" >&2; exit 1 ;;
    esac
fi
if [ "$1" = "news" ]; then
    cat "$STUB_HM_NEWS_FILE" 2>/dev/null || echo ""
    exit 0
fi
exit 0
EOF
chmod +x "$STUB_BIN/home-manager"

cat > "$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
mode=$(cat "$STUB_CLAUDE_MODE_FILE" 2>/dev/null || echo missing)
case "$mode" in
    breaking)  echo "BREAKING: nixpkgs option services.foo.bar removed in 25.11" ;;
    ok)        echo "OK" ;;
    empty)     echo "" ;;
    fail)      exit 1 ;;
    *)         exit 127 ;;
esac
EOF
chmod +x "$STUB_BIN/claude"

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
        printf 'FAIL: %s\n  missing /%s/ in %s\n  contents tail: %s\n' "$label" "$pattern" "$file" "$(tail -3 "$file" 2>/dev/null)"; _bump "$FAIL_FILE"
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

reset_fixtures() {
    cp "$FAKE_FLAKE/flake.lock.before" "$FAKE_FLAKE/flake.lock"
    rm -rf "$LOG_ROOT"
    rm -f "$FAKE_FLAKE/result"
    : > "$STUB_HM_NEWS_FILE"
}

run_under_test() {
    # Explicitly unset CLAUDECODE — when this harness is run from inside a
    # Claude Code session (common during dev), the env var would otherwise
    # cause flake-update to take the "skip classifier" branch and we can't
    # exercise the BREAKING / OK paths. Test 8 sets CLAUDECODE deliberately.
    env -u CLAUDECODE PATH="$STUB_BIN:/usr/bin:/bin" bash "$UNDER_TEST" >/dev/null 2>&1
    echo $?
}

log_file() { find "$LOG_ROOT" -type f -name 'flake-update.*.log' 2>/dev/null | head -1; }

set_nix() { echo "$1" > "$STUB_NIX_MODE_FILE"; }
set_hm()  { echo "$1" > "$STUB_HM_MODE_FILE"; }
set_claude() { echo "$1" > "$STUB_CLAUDE_MODE_FILE"; }
set_news() { printf '%s\n' "$1" > "$STUB_HM_NEWS_FILE"; }

echo
echo "=== Test 1: happy path — update ok, build ok, no news, lock changed ==="
reset_fixtures; set_nix ok; set_hm ok; set_claude missing; set_news ""
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check_grep "INFO START"      '\[INFO\] START flake_dir=' "$(log_file)"
check_grep "INFO build OK"   '\[INFO\] home-manager build OK' "$(log_file)"
check_grep "INFO no news"    'no unread home-manager news' "$(log_file)"
check_grep "INFO DONE"       '\[INFO\] DONE flake_dir=' "$(log_file)"
check_nogrep "no ERROR"      '\[ERROR\]' "$(log_file)"
check_nogrep "no WARN"       '\[WARN\]' "$(log_file)"

echo
echo "=== Test 2: network failure during nix flake update — WARN, exit 0 ==="
reset_fixtures; set_nix network; set_hm ok
rc=$(run_under_test)
check "exit 0 (transient = no scream)" "0" "$rc"
check_grep "WARN NETWORK-ERR" '\[WARN\] NETWORK-ERR' "$(log_file)"
check_nogrep "no ERROR fired" '\[ERROR\]' "$(log_file)"

echo
echo "=== Test 3: non-network nix failure — ERROR, exit 1 ==="
reset_fixtures; set_nix other; set_hm ok
rc=$(run_under_test)
check "exit 1" "1" "$rc"
check_grep "ERROR nix update" '\[ERROR\] nix flake update failed' "$(log_file)"

echo
echo "=== Test 4: home-manager build fails — ERROR, exit 1 ==="
reset_fixtures; set_nix ok; set_hm fail
rc=$(run_under_test)
check "exit 1" "1" "$rc"
check_grep "ERROR build FAILED" 'home-manager build FAILED' "$(log_file)"
check_grep "captures stderr" 'option .foo. has been removed' "$(log_file)"

echo
echo "=== Test 5: build OK + news exists + claude says BREAKING — ERROR notify ==="
reset_fixtures; set_nix ok; set_hm ok; set_claude breaking
set_news "* services.x.y has been removed. Use services.a.b instead."
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check_grep "WARN flagged"    '\[WARN\] home-manager news flagged' "$(log_file)"
check_grep "ERROR escalated" '\[ERROR\] BREAKING home-manager news' "$(log_file)"

echo
echo "=== Test 6: build OK + news exists + claude says OK — silent ==="
reset_fixtures; set_nix ok; set_hm ok; set_claude ok
set_news "* New optional feature: services.foo can now be enabled."
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check_grep "INFO classifier OK" 'claude classifier: OK' "$(log_file)"
check_nogrep "no WARN"       '\[WARN\]' "$(log_file)"
check_nogrep "no ERROR"      '\[ERROR\]' "$(log_file)"

echo
echo "=== Test 7: build OK + news exists + claude returns empty — silent INFO ==="
reset_fixtures; set_nix ok; set_hm ok; set_claude empty
set_news "* something something."
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check_grep "empty classifier" 'classifier returned empty' "$(log_file)"
check_grep "preserves news"   'news (unclassified)' "$(log_file)"
check_nogrep "no ERROR"       '\[ERROR\]' "$(log_file)"

echo
echo "=== Test 8: build OK + news exists + CLAUDECODE set — silent INFO ==="
reset_fixtures; set_nix ok; set_hm ok; set_claude breaking
set_news "* deprecation notice."
rc=$(env CLAUDECODE=1 PATH="$STUB_BIN:/usr/bin:/bin" bash "$UNDER_TEST" >/dev/null 2>&1; echo $?)
check "exit 0" "0" "$rc"
check_grep "claude skipped" 'claude skipped .running inside Claude Code' "$(log_file)"
check_nogrep "no ERROR"     '\[ERROR\]' "$(log_file)"

echo
echo "=== Test 9: lock unchanged — fast path skips build + news ==="
reset_fixtures; set_nix nochange; set_hm ok
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check_grep "skipped fast path" 'flake.lock unchanged' "$(log_file)"
check_nogrep "no build line"   'home-manager build OK' "$(log_file)"

echo
echo "=== Test 10: FLAKE_UPDATE_DRY_RUN=1 — skips nix call but runs build ==="
reset_fixtures; set_hm ok
# DRY_RUN means flake.lock won't move; expect "unchanged" fast path
rc=$(FLAKE_UPDATE_DRY_RUN=1 PATH="$STUB_BIN:/usr/bin:/bin" bash "$UNDER_TEST" >/dev/null 2>&1; echo $?)
check "exit 0" "0" "$rc"
check_grep "DRY-RUN logged" 'DRY-RUN: skipping' "$(log_file)"

pass=$(cat "$PASS_FILE")
fail=$(cat "$FAIL_FILE")
echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
