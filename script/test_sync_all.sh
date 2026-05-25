#!/usr/bin/env bash
# test_sync_all.sh — harness for script/sync_all.
# Uses a fake plocate DB and a stub sync_repo so we can exercise discovery,
# dedup, and summary behaviour without touching real repos.

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$DOTFILES_ROOT/script/sync_all"

TMPDIR=$(mktemp -d /tmp/test_sync_all.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_MACHINE_NAME="testhost"
export LOG_NOTIFY_MODE=never
# Keep INFO/WARN-only runs so happy-path / discovery / per-failure assertions
# can grep the log file. log.sh defaults LOG_KEEP_THRESHOLD=ERROR which would
# discard all but the ERROR-summary runs.
export LOG_KEEP_THRESHOLD=DEBUG
# Stop sync_all from unsetting our pinned LOG_ROOT (production unsets so logs
# land in ~/.local/state/logs instead of ~/hjdocs/logs).
export SYNC_LOG_ROOT_KEEP=1
export DOTFILES_ROOT

# Fake HOME so ~/.cache/plocate.db points at our temp location.
FAKE_HOME="$TMPDIR/home"
mkdir -p "$FAKE_HOME/.cache"
export HOME_OVERRIDE="$FAKE_HOME"

# Fake jj + git + plocate via a stub bin dir. sync_repo is stubbed to record
# each invocation and optionally fail on request.
STUB_BIN="$TMPDIR/bin"
mkdir -p "$STUB_BIN"
export SYNC_REPO_CALL_LOG="$TMPDIR/sync_repo-calls"
export SYNC_REPO_FAIL_LIST="$TMPDIR/sync_repo-fail"  # one path per line = fail
: > "$SYNC_REPO_CALL_LOG"; : > "$SYNC_REPO_FAIL_LIST"

# Stub sync_repo: recorded, selectively failing.
cat > "$STUB_BIN/sync_repo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$SYNC_REPO_CALL_LOG"
if grep -Fxq "$1" "$SYNC_REPO_FAIL_LIST" 2>/dev/null; then
    exit 1
fi
exit 0
EOF
chmod +x "$STUB_BIN/sync_repo"

# The real script hardcodes SYNC="$DOTFILES_ROOT/script/sync_repo". Put the
# stub there instead via a wrapper DOTFILES_ROOT that points at our tempdir.
mkdir -p "$TMPDIR/fake_dotfiles/script"
ln -sf "$STUB_BIN/sync_repo" "$TMPDIR/fake_dotfiles/script/sync_repo"
# log.sh must still be findable — point to the real one.
mkdir -p "$TMPDIR/fake_dotfiles/script/logger"
ln -sf "$DOTFILES_ROOT/script/logger/log.sh" "$TMPDIR/fake_dotfiles/script/logger/log.sh"

# plocate stub: reads from $TEST_PLOCATE_OUTPUT, ignores other args.
export TEST_PLOCATE_OUTPUT="$TMPDIR/plocate-output"
: > "$TEST_PLOCATE_OUTPUT"
cat > "$STUB_BIN/plocate" <<'EOF'
#!/usr/bin/env bash
# Return everything from TEST_PLOCATE_OUTPUT, ignoring filters and regex.
cat "$TEST_PLOCATE_OUTPUT" 2>/dev/null
EOF
chmod +x "$STUB_BIN/plocate"

# jj / git stubs: tell sync_all that each dir resolves to itself as the repo root.
# We don't need dedup testing to go beyond basename-equality; a dir's own path
# is its "root" unless TEST_JJ_MAP says otherwise.
export TEST_JJ_MAP="$TMPDIR/jj-map"
: > "$TEST_JJ_MAP"
cat > "$STUB_BIN/jj" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "root" ]; then
    cwd=$(pwd)
    mapped=$(grep -E "^$cwd=" "$TEST_JJ_MAP" 2>/dev/null | head -1 | cut -d= -f2-)
    if [ -n "$mapped" ]; then
        echo "$mapped"
    else
        echo "$cwd"
    fi
    exit 0
fi
exit 0
EOF
chmod +x "$STUB_BIN/jj"
cat > "$STUB_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
    pwd
    exit 0
fi
exit 0
EOF
chmod +x "$STUB_BIN/git"

# Counters.
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
        printf 'FAIL: %s (missing /%s/ in %s)\n' "$label" "$pattern" "$file"; _bump "$FAIL_FILE"
    fi
}
not_grep() {
    local label=$1 pattern=$2 file=$3
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
        printf 'FAIL: %s (unexpected /%s/ in %s)\n' "$label" "$pattern" "$file"; _bump "$FAIL_FILE"
    else
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    fi
}

run_under_test() {
    HOME="$HOME_OVERRIDE" DOTFILES_ROOT="$TMPDIR/fake_dotfiles" \
        PATH="$STUB_BIN:/usr/bin:/bin" \
        bash "$UNDER_TEST" >/dev/null 2>&1
    echo $?
}
log_file() { find "$LOG_ROOT" -type f -name 'sync_all.*.log' 2>/dev/null | head -1; }
clear_logs() { rm -rf "$LOG_ROOT"; }
clear_state() { : > "$SYNC_REPO_CALL_LOG"; : > "$SYNC_REPO_FAIL_LIST"; : > "$TEST_JJ_MAP"; : > "$TEST_PLOCATE_OUTPUT"; }

touch "$FAKE_HOME/.cache/plocate.db"   # exists; content doesn't matter with the stub

echo
echo "=== Test 1: happy path — two repos, both succeed ==="
clear_logs; clear_state
mkdir -p "$TMPDIR/repoA" "$TMPDIR/repoB"
printf '%s\n%s\n' "$TMPDIR/repoA/.jj" "$TMPDIR/repoB/.git" > "$TEST_PLOCATE_OUTPUT"
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "2 sync_repo invocations" "2" "$(wc -l < "$SYNC_REPO_CALL_LOG")"
check_grep "log START" '\[INFO\] START' "$(log_file)"
check_grep "log discovery count" 'discovered 2 repo' "$(log_file)"
check_grep "SUMMARY success" 'SUMMARY processed=2 failed=0' "$(log_file)"

echo
echo "=== Test 2: one repo fails — SUMMARY is ERROR, exit 1 ==="
clear_logs; clear_state
mkdir -p "$TMPDIR/repoC" "$TMPDIR/repoD"
printf '%s\n%s\n' "$TMPDIR/repoC/.jj" "$TMPDIR/repoD/.git" > "$TEST_PLOCATE_OUTPUT"
# Tell the stub to fail on repoD
echo "$TMPDIR/repoD" >> "$SYNC_REPO_FAIL_LIST"
rc=$(run_under_test)
check "exit 1" "1" "$rc"
check "still ran both" "2" "$(wc -l < "$SYNC_REPO_CALL_LOG")"
check_grep "SUMMARY includes failed=1" 'SUMMARY processed=2 failed=1' "$(log_file)"
check_grep "SUMMARY logged as ERROR" '\[ERROR\].*SUMMARY' "$(log_file)"
# Per-repo failure must be logged at WARN with the repo path so the user can
# rerun it for diagnostics without needing a separate sync_repo log file.
check_grep "FAILED line carries repo path" '\[WARN\].*FAILED rc=.*repoD' "$(log_file)"
# Successful repos must NOT emit a FAILED line.
not_grep "no FAILED for repoC" 'FAILED.*repoC' "$(log_file)"

echo
echo "=== Test 3: dedup — multiple markers in one repo -> single call ==="
clear_logs; clear_state
mkdir -p "$TMPDIR/mono"
printf '%s\n%s\n%s\n' \
    "$TMPDIR/mono/.jj" \
    "$TMPDIR/mono/sub1/.git" \
    "$TMPDIR/mono/sub2/.git" > "$TEST_PLOCATE_OUTPUT"
# Map subdir paths to the same root so dedup catches them
printf '%s=%s\n%s=%s\n%s=%s\n' \
    "$TMPDIR/mono" "$TMPDIR/mono" \
    "$TMPDIR/mono/sub1" "$TMPDIR/mono" \
    "$TMPDIR/mono/sub2" "$TMPDIR/mono" > "$TEST_JJ_MAP"
mkdir -p "$TMPDIR/mono/sub1" "$TMPDIR/mono/sub2"
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "deduped to 1 sync_repo call" "1" "$(wc -l < "$SYNC_REPO_CALL_LOG")"
check_grep "discovered 1 repo" 'discovered 1 repo' "$(log_file)"

echo
echo "=== Test 4: noise paths filtered ==="
clear_logs; clear_state
mkdir -p "$TMPDIR/real" "$TMPDIR/cachey/.cache/foo" "$TMPDIR/modsy/node_modules/pkg"
printf '%s\n%s\n%s\n' \
    "$TMPDIR/real/.jj" \
    "$TMPDIR/cachey/.cache/foo/.git" \
    "$TMPDIR/modsy/node_modules/pkg/.git" > "$TEST_PLOCATE_OUTPUT"
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "only the real repo processed" "1" "$(wc -l < "$SYNC_REPO_CALL_LOG")"
check "cachey not in call log" "0" "$(grep -c cachey "$SYNC_REPO_CALL_LOG")"
check "modsy not in call log" "0" "$(grep -c modsy "$SYNC_REPO_CALL_LOG")"

echo
echo "=== Test 5: missing plocate DB -> actionable ERROR ==="
clear_logs; clear_state
rm -f "$FAKE_HOME/.cache/plocate.db"
rc=$(run_under_test)
check "exit 1" "1" "$rc"
check_grep "ERROR names DB path" 'plocate database not found' "$(log_file)"
check_grep "ERROR mentions updatedb" 'updatedb' "$(log_file)"
touch "$FAKE_HOME/.cache/plocate.db"  # restore

echo
echo "=== Test 6: missing sync_repo script -> actionable ERROR ==="
clear_logs; clear_state
# Break the symlink
rm -f "$TMPDIR/fake_dotfiles/script/sync_repo"
rc=$(run_under_test)
check "exit 1" "1" "$rc"
check_grep "ERROR names sync_repo path" 'sync_repo script not executable' "$(log_file)"
# Restore
ln -sf "$STUB_BIN/sync_repo" "$TMPDIR/fake_dotfiles/script/sync_repo"

echo
echo "=== Test 7: empty plocate output — no iterations, clean exit ==="
clear_logs; clear_state
: > "$TEST_PLOCATE_OUTPUT"
rc=$(run_under_test)
check "exit 0" "0" "$rc"
check "no sync_repo calls" "0" "$(wc -l < "$SYNC_REPO_CALL_LOG")"
check_grep "discovered 0 repos" 'discovered 0 repo' "$(log_file)"
check_grep "SUMMARY 0 failures" 'SUMMARY processed=0 failed=0' "$(log_file)"

pass=$(cat "$PASS_FILE")
fail=$(cat "$FAIL_FILE")
echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
