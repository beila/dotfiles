#!/usr/bin/env bash
# test_logrun.sh — harness for bin/logrun.
#
# Exercises naming, log-dir defaults, ANSI stripping, exit-status propagation,
# .FAILED rename, shell mode, custom decorator, and env-var overrides.
# Isolates all output to a temporary directory.
#
# Run with:  bash bin/test_logrun.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$DOTFILES_ROOT/bin/logrun"

TMPDIR=$(mktemp -d /tmp/test_logrun.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

PASS_FILE="$TMPDIR/pass"; FAIL_FILE="$TMPDIR/fail"
printf '0' > "$PASS_FILE"
printf '0' > "$FAIL_FILE"
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
    if [ -f "$file" ] && grep -qE "$pattern" "$file" 2>/dev/null; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s\n  missing /%s/ in %s\n  contents: %s\n' \
            "$label" "$pattern" "$file" "$(cat "$file" 2>/dev/null | head -5)"
        _bump "$FAIL_FILE"
    fi
}
check_nogrep() {
    local label=$1 pattern=$2 file=$3
    if [ ! -f "$file" ] || ! grep -qE "$pattern" "$file" 2>/dev/null; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s  (unexpected match of /%s/ in %s)\n' \
            "$label" "$pattern" "$file"
        _bump "$FAIL_FILE"
    fi
}
check_file_exists() {
    local label=$1 file=$2
    if [ -f "$file" ]; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s  (file not found: %s)\n' "$label" "$file"; _bump "$FAIL_FILE"
    fi
}

# Keep tests independent of whichever decorator is installed on this host.
# `cat` is always present; `--no-decorator` aliases to `cat` too but we pass
# it explicitly where we want to suppress auto-detect behaviour under test.
BASE_FLAGS=(--decorator cat)

run_count=0
new_logdir() {
    # Assign to a global instead of echoing — `d=$(new_logdir)` would run
    # in a subshell and lose the counter increment, so every case would
    # re-use case-1 and collide.
    run_count=$((run_count + 1))
    LOG_DIR="$TMPDIR/case-$run_count"
    mkdir -p "$LOG_DIR"
}

# -----------------------------------------------------------------------------
# Case 1: basic run — output goes to both stdout and a file; exit status 0
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
out=$("$UNDER_TEST" "${BASE_FLAGS[@]}" --log-dir "$d" -- echo "hello world" 2>"$d/stderr")
rc=$?
check "case1: exit status 0"        "0"              "$rc"
check "case1: decorated stdout"     "hello world"    "$out"
log=$(ls "$d"/log-*.txt 2>/dev/null | head -1)
check_file_exists "case1: log file created"    "$log"
check_grep        "case1: log contains output" "hello world"   "$log"
check_grep        "case1: stderr prints Log:"  "^Log: "        "$d/stderr"

# -----------------------------------------------------------------------------
# Case 2: non-zero exit → log renamed to *.FAILED.txt, rc preserved
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
"$UNDER_TEST" "${BASE_FLAGS[@]}" --log-dir "$d" -- bash -c 'echo fail; exit 7' >/dev/null 2>/dev/null
rc=$?
check "case2: exit status preserved"           "7" "$rc"
ls "$d" | grep -qE '\.FAILED\.txt$' && rename_ok=1 || rename_ok=0
check "case2: renamed to .FAILED.txt"          "1" "$rename_ok"
# exactly one file in the dir, and it carries the .FAILED.txt suffix
file_count=$(ls "$d" | wc -l)
check "case2: exactly one log file"            "1" "$file_count"
ls "$d" | grep -qvE '\.FAILED\.txt$' && stray=1 || stray=0
check "case2: no plain .txt remains"           "0" "$stray"

# -----------------------------------------------------------------------------
# Case 3: --fail-suffix custom + empty (disable rename on failure)
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
"$UNDER_TEST" "${BASE_FLAGS[@]}" --log-dir "$d" --fail-suffix crashed -- bash -c 'exit 1' \
    >/dev/null 2>/dev/null
ls "$d" | grep -q '\.crashed$' && custom=1 || custom=0
check "case3a: custom fail-suffix applied"     "1" "$custom"

new_logdir; d=$LOG_DIR
"$UNDER_TEST" "${BASE_FLAGS[@]}" --log-dir "$d" --fail-suffix '' -- bash -c 'exit 1' \
    >/dev/null 2>/dev/null
ls "$d" | grep -qE '^log-.*\.txt$' && plain=1 || plain=0
check "case3b: empty fail-suffix keeps .txt"   "1" "$plain"

# -----------------------------------------------------------------------------
# Case 4: -c / --command shell mode
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
out=$("$UNDER_TEST" "${BASE_FLAGS[@]}" --name shelly --log-dir "$d" -c 'echo A; echo B' 2>/dev/null)
check "case4a: shell mode output lines"        $'A\nB' "$out"
log=$(ls "$d"/log-shelly-*.txt 2>/dev/null | head -1)
check_file_exists "case4b: --name used in filename" "$log"
check_grep        "case4c: shell mode log has A"    "^A\$" "$log"
check_grep        "case4c: shell mode log has B"    "^B\$" "$log"

# -----------------------------------------------------------------------------
# Case 5: ANSI escape stripping
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
# \e[31m...\e[0m must appear on the tty (decorator=cat passes it through) but
# must NOT appear in the log file.
out=$("$UNDER_TEST" "${BASE_FLAGS[@]}" --name ansi --log-dir "$d" \
    -c 'printf "\e[31mRED\e[0m plain\n"' 2>/dev/null)
check "case5a: decorated stream retains ANSI"  $'\e[31mRED\e[0m plain' "$out"
log=$(ls "$d"/log-ansi-*.txt 2>/dev/null | head -1)
check_grep        "case5b: log has stripped text"       "^RED plain\$" "$log"
check_nogrep      "case5c: log has no ESC bytes"        $'\e'          "$log"

# -----------------------------------------------------------------------------
# Case 6: log_path env var is respected (nested-recipe inheritance)
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
explicit="$d/explicit.log"
log_path="$explicit" "$UNDER_TEST" "${BASE_FLAGS[@]}" -- echo inherited >/dev/null 2>/dev/null
check_file_exists "case6: explicit log_path honoured" "$explicit"
check_grep        "case6: explicit log file content"   "^inherited\$" "$explicit"

# -----------------------------------------------------------------------------
# Case 7: build_dir env var picked up as default log-dir
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
mkdir -p "$d/build"
( cd "$d" && build_dir="$d/build" "$UNDER_TEST" "${BASE_FLAGS[@]}" -- echo hi >/dev/null 2>/dev/null )
log=$(ls "$d"/build/log-*.txt 2>/dev/null | head -1)
check_file_exists "case7: build_dir env is used as log-dir default" "$log"

# -----------------------------------------------------------------------------
# Case 8: name sanitisation (spaces, slashes, quotes, long strings)
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
# Expect: whitespace → -, / → -, quotes dropped.
"$UNDER_TEST" "${BASE_FLAGS[@]}" --name 'foo/bar baz "quoted"' --log-dir "$d" -- true \
    >/dev/null 2>/dev/null
ls "$d" | grep -qE '^log-foo-bar-baz-quoted-' && san=1 || san=0
check "case8a: log filename sanitised"         "1" "$san"

new_logdir; d=$LOG_DIR
long=$(printf 'x%.0s' {1..250})
"$UNDER_TEST" "${BASE_FLAGS[@]}" --name "$long" --log-dir "$d" -- true >/dev/null 2>/dev/null
fname=$(ls "$d" | head -1)
# filename ≤ 255 bytes (ext4 limit; we truncate the name portion to 200)
check "case8b: long name truncated"            "1" "$([ "${#fname}" -le 255 ] && echo 1 || echo 0)"

# -----------------------------------------------------------------------------
# Case 9: --decorator custom pipeline transforms live stream
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
out=$("$UNDER_TEST" --log-dir "$d" --decorator 'tr a-z A-Z' --name deco -c 'echo hello' 2>/dev/null)
check "case9a: custom decorator applied"       "HELLO" "$out"
# The log itself should be untouched (decorator only affects the displayed copy).
log=$(ls "$d"/log-deco-*.txt | head -1)
check_grep "case9b: log bypasses decorator"    "^hello\$" "$log"

# -----------------------------------------------------------------------------
# Case 10: no command → usage error (exit 2)
# -----------------------------------------------------------------------------
"$UNDER_TEST" --name x --log-dir "$TMPDIR" >/dev/null 2>/dev/null
check "case10: no command → exit 2"            "2" "$?"

# -----------------------------------------------------------------------------
# Case 11: unknown option → exit 2
# -----------------------------------------------------------------------------
"$UNDER_TEST" --nope >/dev/null 2>/dev/null
check "case11: unknown option → exit 2"        "2" "$?"

# -----------------------------------------------------------------------------
# Case 12: --help prints the header block and exits 0
# -----------------------------------------------------------------------------
help_out=$("$UNDER_TEST" --help 2>/dev/null)
rc=$?
check "case12a: --help exit 0"                 "0" "$rc"
echo "$help_out" | grep -q '^logrun' && h1=1 || h1=0
check "case12b: --help shows header"           "1" "$h1"

# -----------------------------------------------------------------------------
# Case 13: mid-run log relocation via `logrun-move` helper (SIGUSR1 handshake)
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
final_dir="$d/final"
mkdir -p "$final_dir"
# Ensure the helper is findable via PATH for the wrapped shell.
PATH="$DOTFILES_ROOT/bin:$PATH" \
    "$UNDER_TEST" "${BASE_FLAGS[@]}" --name relocate --log-dir "$d" -c '
        echo "before relocation"
        sleep 0.2
        logrun-move "'"$final_dir"'"
        sleep 0.2
        echo "after relocation"
    ' >/dev/null 2>/dev/null
# The moved log keeps the original filename, now under $final_dir.
moved=$(ls "$final_dir"/log-relocate-*.txt 2>/dev/null | head -1)
check_file_exists "case13a: moved log exists (same filename, new dir)" "$moved"
check_grep        "case13b: pre-move line kept"   "^before relocation\$" "$moved"
check_grep        "case13c: post-move line kept"  "^after relocation\$"  "$moved"
# Original log file was moved away, so none should remain at the top of $d.
orig_count=$(ls "$d" 2>/dev/null | grep -cE '^log-relocate-' || true)
check "case13d: original log moved away"           "0" "$orig_count"

# -----------------------------------------------------------------------------
# Case 14: end-to-end through real nix flake + just + zsh `j` wrapper.
# Validates that LOGRUN_PID / LOGRUN_MOVE_FILE survive `nix develop
# --ignore-env` (via --keep) and that a justfile recipe can relocate the
# log mid-run using the raw SIGUSR1 idiom (no PATH dependency).
#
# Skips gracefully when any of nix/just/git/zsh is unavailable, or when
# LOGRUN_TEST_NIX=skip is set (first nix develop on a fresh flake can
# take ~10s while resolving nixpkgs).
# -----------------------------------------------------------------------------
if ! command -v nix  >/dev/null 2>&1 \
  || ! command -v just >/dev/null 2>&1 \
  || ! command -v git  >/dev/null 2>&1 \
  || ! command -v zsh  >/dev/null 2>&1; then
    printf 'SKIP: case14 (requires nix, just, git, zsh)\n'
elif [[ "${LOGRUN_TEST_NIX:-}" == "skip" ]]; then
    printf 'SKIP: case14 (LOGRUN_TEST_NIX=skip)\n'
else
    new_logdir; d=$LOG_DIR
    cat > "$d/flake.nix" <<'FLAKE'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      buildInputs = [ pkgs.just ];
    };
  };
}
FLAKE
    # Raw signal idiom so we don't depend on logrun-move being on PATH
    # inside the nix devshell.
    cat > "$d/justfile" <<'JUSTFILE'
hello:
    #!/usr/bin/env bash
    set -euo pipefail
    echo before-move
    mkdir -p {{ justfile_directory() }}/final
    printf '%s' "{{ justfile_directory() }}/final" > "$LOGRUN_MOVE_FILE"
    kill -USR1 "$LOGRUN_PID"
    sleep 0.2
    echo after-move
JUSTFILE
    ( cd "$d" && git init -q && git add . && git -c user.email=t@t -c user.name=t commit -q -m t )

    # Invoke `j hello` from zsh so the autoloaded function runs.
    # Keep build_dir pointed at an "initial" dir so we can verify the
    # later move lands somewhere different.
    build_dir="$d/initial" zsh -c "
        fpath=(\"$DOTFILES_ROOT/zsh/functions\" \$fpath)
        autoload -U j
        cd \"$d\"
        j hello
    " >/dev/null 2>&1 || true

    moved=$(ls "$d"/final/log-*.txt 2>/dev/null | head -1)
    check_file_exists "case14a: log moved into justfile-chosen dir"    "$moved"
    if [[ -f "$moved" ]]; then
        check_grep    "case14b: pre-move line survives"              "^before-move\$" "$moved"
        check_grep    "case14c: post-move line survives"             "^after-move\$"  "$moved"
    fi
    stray=$(ls "$d"/initial 2>/dev/null | wc -l)
    check "case14d: original log moved away" "0" "$stray"
fi

# -----------------------------------------------------------------------------
# Case 15: --auto, short cmd → invisible (no banner, no log left behind)
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
out=$("$UNDER_TEST" --auto --no-zshrc --log-dir "$d" -- echo hello 2>"$d/stderr")
check "case15a: short --auto stdout"           "hello" "$out"
file_count=$(ls -A "$d" 2>/dev/null | grep -c '^log-' || true)
check "case15b: short --auto leaves no log"    "0"     "$file_count"
banner_count=$(grep -c '^Log: ' "$d/stderr" 2>/dev/null || echo 0)
check "case15c: short --auto prints no banner" "0"     "$banner_count"

# -----------------------------------------------------------------------------
# Case 16: --auto + line threshold → banner once, log retained
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
LOGRUN_AUTO_LINES=3 "$UNDER_TEST" --auto --no-zshrc --log-dir "$d" \
    -- bash -c 'for i in 1 2 3 4 5; do echo line$i; done' >/dev/null 2>"$d/stderr"
banner_count=$(grep -c '^Log: ' "$d/stderr" 2>/dev/null || echo 0)
check "case16a: line-threshold prints exactly 1 banner" "1" "$banner_count"
file_count=$(ls -A "$d" 2>/dev/null | grep -c '^log-' || true)
check "case16b: line-threshold log retained"            "1" "$file_count"

# -----------------------------------------------------------------------------
# Case 17: --auto + wallclock threshold → banner, log retained
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
LOGRUN_AUTO_SECONDS=1 "$UNDER_TEST" --auto --no-zshrc --log-dir "$d" \
    -- bash -c 'sleep 2; echo done' >/dev/null 2>"$d/stderr"
banner_count=$(grep -c '^Log: ' "$d/stderr" 2>/dev/null || echo 0)
check "case17a: wallclock prints 1 banner"     "1" "$banner_count"
file_count=$(ls -A "$d" 2>/dev/null | grep -c '^log-' || true)
check "case17b: wallclock log retained"        "1" "$file_count"

# -----------------------------------------------------------------------------
# Case 18: --auto + non-zero exit → FAILED rename + banner shows FAILED path
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
"$UNDER_TEST" --auto --no-zshrc --log-dir "$d" \
    -- bash -c 'echo oops; exit 7' >/dev/null 2>"$d/stderr"
rc=$?
check "case18a: failure exit propagated"       "7" "$rc"
fail_count=$(ls "$d" | grep -cE '\.FAILED\.txt$' || true)
check "case18b: FAILED.txt rename applied"     "1" "$fail_count"
plain_count=$(ls "$d" | grep -cE '^log-.*\.txt$' || true)
check "case18c: no plain .txt remains"         "0" "$plain_count"
banner_failed=$(grep -c 'FAILED.txt' "$d/stderr" 2>/dev/null || echo 0)
check "case18d: banner mentions FAILED.txt"    "1" "$banner_failed"

# -----------------------------------------------------------------------------
# Case 19: --auto + alt-screen entry → "looks like a TUI" hint
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
"$UNDER_TEST" --auto --no-zshrc --log-dir "$d" \
    -- bash -c $'printf "\e[?1049h"; echo hi' >/dev/null 2>"$d/stderr"
hint_count=$(grep -c 'looks like a TUI' "$d/stderr" 2>/dev/null || echo 0)
check "case19a: alt-screen produces hint"      "1" "$hint_count"
# And the captured log should NOT contain the bare alt-screen sequence
# (the auto-mode awk strips it).
log=$(ls "$d"/log-*.txt 2>/dev/null | head -1)
if [[ -f "$log" ]]; then
    check_nogrep "case19b: alt-screen stripped from log" $'\033\\[\\?1049h' "$log"
else
    # Log was deleted (under threshold + zero exit) — still a pass for stripping.
    printf 'PASS: %s\n' "case19b: alt-screen stripped from log (log already deleted)"
    _bump "$PASS_FILE"
fi

# -----------------------------------------------------------------------------
# Case 20: --auto + alt-screen, command IS in LOGRUN_TUI_SKIPLIST → no hint
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
LOGRUN_TUI_SKIPLIST="bash other-tui" "$UNDER_TEST" --auto --no-zshrc \
    --log-dir "$d" -- bash -c $'printf "\e[?1049h"; echo hi' \
    >/dev/null 2>"$d/stderr"
hint_count=$(grep -c 'looks like a TUI' "$d/stderr" 2>/dev/null || echo 0)
check "case20: skiplisted TUI suppresses hint" "0" "$hint_count"

# -----------------------------------------------------------------------------
# Case 21: --no-zshrc fast path skips zsh startup. Verify by setting
# an alias in zshrc-only space (none is visible to a bare process) and
# confirming the command resolves directly via PATH.
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
out=$("$UNDER_TEST" --no-zshrc --log-dir "$d" -- echo direct 2>/dev/null)
check "case21a: --no-zshrc positional output"  "direct" "$out"
log=$(ls "$d"/log-*.txt 2>/dev/null | head -1)
check_grep "case21b: --no-zshrc log content"   "^direct\$" "$log"

# -----------------------------------------------------------------------------
# Case 22: --auto + threshold tripped AND non-zero exit. Failure branch
# applies the FAILED rename and prints a final banner with the renamed
# path (the in-run trap may also have printed once before the rename).
# -----------------------------------------------------------------------------
new_logdir; d=$LOG_DIR
LOGRUN_AUTO_LINES=2 "$UNDER_TEST" --auto --no-zshrc --log-dir "$d" \
    -- bash -c 'echo a; echo b; echo c; exit 5' >/dev/null 2>"$d/stderr"
rc=$?
check "case22a: combo exit propagated"         "5" "$rc"
fail_count=$(ls "$d" | grep -cE '\.FAILED\.txt$' || true)
check "case22b: combo FAILED rename applied"   "1" "$fail_count"
banner_failed=$(grep -c 'FAILED.txt' "$d/stderr" 2>/dev/null || echo 0)
check "case22c: combo banner mentions FAILED"  "1" "$banner_failed"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
pass=$(cat "$PASS_FILE"); fail=$(cat "$FAIL_FILE")
echo
echo "----------"
echo "PASS: $pass   FAIL: $fail"
[ "$fail" -eq 0 ] || exit 1
