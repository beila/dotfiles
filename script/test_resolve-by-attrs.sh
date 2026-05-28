#!/usr/bin/env bash
# Smoke test for script/bin/resolve-by-attrs. Builds throwaway colocated jj/git
# repos with hand-crafted conflicts and a .gitattributes that maps each
# conflicted path to a different merge driver. Exercises:
#   - no-op (no conflicts) -> exit 0, nothing reported
#   - merge=theirs              -> jj :theirs        -> right side wins
#   - merge=ours                -> jj :ours          -> left side wins
#   - merge=union  (git builtin) -> emulated         -> concatenated content
#   - merge=text   (git default) -> left alone       -> still conflicted
#   - merge=binary              -> left alone       -> still conflicted
#   - merge=<custom>            -> [merge.<>.driver] -> driver runs
#   - merge=unknown (no driver) -> left alone, exit 0 (no error)
#   - mixed batch               -> resolvables resolved, rest left, exit 0
#   - path with spaces          -> handled
#   - non-colocated repo        -> exits cleanly with an error
#   - .gitattributes itself in conflict -> degrades gracefully
#
# Convention: exits with non-zero on any test failure; otherwise prints
# "ALL N TESTS PASSED" and exits 0.
#
# Usage: bash script/test_resolve-by-attrs.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
RESOLVER="$DOTFILES_ROOT/script/bin/resolve-by-attrs"

if [ ! -x "$RESOLVER" ]; then
    echo "FATAL: $RESOLVER not executable (chmod +x first)"
    exit 2
fi

TMPDIR=$(mktemp -d /tmp/resolve_by_attrs_test.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== test dir: $TMPDIR ==="

pass=0
fail=0

check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"
        pass=$((pass+1))
    else
        echo "FAIL: $label"
        echo "  expected: [$expected]"
        echo "  actual:   [$actual]"
        fail=$((fail+1))
    fi
}

# `jj resolve --list` exits 2 with stderr "No conflicts found at this
# revision" when the working copy has no conflicts; rc=0 with the path list
# on stdout otherwise. Discriminate on rc, not stdout text — the success-rc
# stderr message ("No conflicts found") contains the substring "conflict",
# so naive grep matching falsely flips between states.
assert_no_conflicts_at() {
    local label=$1 dir=$2
    local out rc
    out=$(cd "$dir" && jj resolve --list 2>/dev/null) || rc=$?
    rc=${rc:-0}
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
        echo "PASS: $label"
        pass=$((pass+1))
    else
        echo "FAIL: $label (conflicts still present)"
        echo "$out" | sed 's/^/    /'
        fail=$((fail+1))
    fi
}

assert_still_conflicted() {
    local label=$1 dir=$2 path=$3
    local out rc
    out=$(cd "$dir" && jj resolve --list 2>/dev/null) || rc=$?
    rc=${rc:-0}
    if [ "$rc" -eq 0 ] && echo "$out" | grep -qF "$path"; then
        echo "PASS: $label"
        pass=$((pass+1))
    else
        echo "FAIL: $label ($path is no longer conflicted but should be)"
        echo "$out" | sed 's/^/    /'
        fail=$((fail+1))
    fi
}

# Build a colocated jj/git repo at $1 with three commits forming a conflict
# graph:  base ── left ── right (where left and right both edit each path
# differently). Caller can then run `jj new <left-id> <right-id>` to materialise
# the conflict at @.
#
# Args:
#   $1 - dir (will be created)
#   $2... - "name|base|left|right" tuples; one per conflicted file. The pipes
#           let us include spaces in `name` and arbitrary content in each side.
make_repo_with_conflict() {
    local dir=$1; shift
    mkdir -p "$dir"
    (
        cd "$dir"
        jj git init --colocate >/dev/null 2>&1
        jj config set --repo user.email 'test@example.com' >/dev/null
        jj config set --repo user.name  'Test User' >/dev/null

        # Base commit: write the base content of every conflicted file.
        local spec name base
        for spec in "$@"; do
            name=${spec%%|*}; rest=${spec#*|}
            base=${rest%%|*}
            printf '%s' "$base" > "$name"
        done
        jj commit -m base >/dev/null 2>&1

        # left: overwrite each file with its `left` content.
        local left
        for spec in "$@"; do
            name=${spec%%|*}; rest=${spec#*|}
            base=${rest%%|*}; rest=${rest#*|}
            left=${rest%%|*}
            printf '%s' "$left" > "$name"
        done
        jj commit -m left >/dev/null 2>&1

        # right: re-derive from base, then write each file's `right` content.
        jj new -r 'subject("base")' >/dev/null 2>&1
        local right
        for spec in "$@"; do
            name=${spec%%|*}; rest=${spec#*|}
            base=${rest%%|*}; rest=${rest#*|}
            left=${rest%%|*}; rest=${rest#*|}
            right=${rest%%|*}
            printf '%s' "$right" > "$name"
        done
        jj commit -m right >/dev/null 2>&1

        # Materialise the merge at @. Resolve change ids by subject() — jj
        # stores descriptions with a trailing newline, so description("left")
        # (exact match) returns nothing. subject() compares only the first
        # line and is the right choice for one-line descriptions.
        local left_id right_id
        left_id=$(jj log --no-graph -r 'subject("left")' -T 'change_id.short()')
        right_id=$(jj log --no-graph -r 'subject("right")' -T 'change_id.short()')
        jj new "$left_id" "$right_id" >/dev/null 2>&1
    )
}

# Read a file at @ in repo $1.
file_at() {
    local dir=$1 path=$2
    cat "$dir/$path"
}

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 1: no conflicts -> no-op, exit 0 ==="
mkdir -p "$TMPDIR/clean"
(
    cd "$TMPDIR/clean"
    jj git init --colocate >/dev/null 2>&1
    jj config set --repo user.email t@e >/dev/null
    jj config set --repo user.name  t >/dev/null
    echo hi > README
    jj commit -m hi >/dev/null 2>&1
)
out=$("$RESOLVER" "$TMPDIR/clean" 2>&1); rc=$?
check "exit 0 on clean repo" "0" "$rc"
echo "$out" | grep -qi 'no conflicts\|nothing to do' \
    && { echo "PASS: announces no-op"; pass=$((pass+1)); } \
    || { echo "FAIL: didn't announce no-op (got: $out)"; fail=$((fail+1)); }

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 2: merge=theirs ==="
make_repo_with_conflict "$TMPDIR/theirs" "lock|0|1|2"
echo 'lock merge=theirs' > "$TMPDIR/theirs/.gitattributes"
"$RESOLVER" "$TMPDIR/theirs" >/dev/null 2>&1
rc=$?
check "exit 0 on theirs-only batch" "0" "$rc"
assert_no_conflicts_at "theirs leaves no conflicts" "$TMPDIR/theirs"
content=$(file_at "$TMPDIR/theirs" lock)
check "theirs picked side 2 (right)" "2" "$content"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 3: merge=ours ==="
make_repo_with_conflict "$TMPDIR/ours" "lock|0|1|2"
echo 'lock merge=ours' > "$TMPDIR/ours/.gitattributes"
"$RESOLVER" "$TMPDIR/ours" >/dev/null 2>&1
rc=$?
check "exit 0 on ours-only batch" "0" "$rc"
assert_no_conflicts_at "ours leaves no conflicts" "$TMPDIR/ours"
content=$(file_at "$TMPDIR/ours" lock)
check "ours picked side 1 (left)" "1" "$content"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 4: merge=union (git builtin, emulated) ==="
# Multi-line file so each side genuinely has a line the other doesn't —
# union should yield a file containing both LEFT_ONLY and RIGHT_ONLY.
# Spec strings use 'B'/'L'/'R' as markers; we substitute newlines via $'…'.
make_repo_with_conflict "$TMPDIR/union" \
    "notes|$(printf 'common\nBASE_ONLY\n')|$(printf 'common\nLEFT_ONLY\n')|$(printf 'common\nRIGHT_ONLY\n')"
echo 'notes merge=union' > "$TMPDIR/union/.gitattributes"
"$RESOLVER" "$TMPDIR/union" >/dev/null 2>&1
rc=$?
check "exit 0 on union batch" "0" "$rc"
assert_no_conflicts_at "union leaves no conflicts" "$TMPDIR/union"
got=$(file_at "$TMPDIR/union" notes)
echo "$got" | grep -q 'LEFT_ONLY'  && \
echo "$got" | grep -q 'RIGHT_ONLY' && \
    { echo "PASS: union output contains both sides"; pass=$((pass+1)); } || \
    { echo "FAIL: union output missing a side (got: $got)"; fail=$((fail+1)); }

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 5: merge=text -> left alone (jj already 3-way merged) ==="
make_repo_with_conflict "$TMPDIR/text" "lock|0|1|2"
echo 'lock merge=text' > "$TMPDIR/text/.gitattributes"
"$RESOLVER" "$TMPDIR/text" >/dev/null 2>&1
rc=$?
check "exit 0 with merge=text" "0" "$rc"
assert_still_conflicted "merge=text leaves the conflict alone" "$TMPDIR/text" lock

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 6: merge=binary -> left alone ==="
make_repo_with_conflict "$TMPDIR/bin" "img|0|1|2"
echo 'img merge=binary' > "$TMPDIR/bin/.gitattributes"
"$RESOLVER" "$TMPDIR/bin" >/dev/null 2>&1
rc=$?
check "exit 0 with merge=binary" "0" "$rc"
assert_still_conflicted "merge=binary leaves the conflict alone" "$TMPDIR/bin" img

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 7: custom driver via [merge.<name>.driver] ==="
# Driver: always write the literal string "DRIVER" to %A.
make_repo_with_conflict "$TMPDIR/custom" "data|0|1|2"
echo 'data merge=stamp' > "$TMPDIR/custom/.gitattributes"
git -C "$TMPDIR/custom" config merge.stamp.name 'always-stamp'
git -C "$TMPDIR/custom" config merge.stamp.driver 'printf DRIVER > %A'
"$RESOLVER" "$TMPDIR/custom" >/dev/null 2>&1
rc=$?
check "exit 0 with custom driver" "0" "$rc"
assert_no_conflicts_at "custom driver resolves the conflict" "$TMPDIR/custom"
content=$(file_at "$TMPDIR/custom" data)
check "custom driver wrote 'DRIVER'" "DRIVER" "$content"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 8: merge=<unknown>, no driver configured ==="
make_repo_with_conflict "$TMPDIR/unk" "x|0|1|2"
echo 'x merge=nosuchthing' > "$TMPDIR/unk/.gitattributes"
out=$("$RESOLVER" "$TMPDIR/unk" 2>&1); rc=$?
check "exit 0 with unknown driver" "0" "$rc"
assert_still_conflicted "unknown merge value leaves conflict alone" "$TMPDIR/unk" x

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 9: mixed batch -> resolvables resolved, rest remain ==="
make_repo_with_conflict "$TMPDIR/mix" \
    "auto|0|1|2" \
    "manual|0|A|B"
cat > "$TMPDIR/mix/.gitattributes" <<EOF
auto   merge=theirs
manual merge=text
EOF
"$RESOLVER" "$TMPDIR/mix" >/dev/null 2>&1
rc=$?
check "exit 0 on mixed batch" "0" "$rc"
content=$(file_at "$TMPDIR/mix" auto)
check "mix: auto resolved (side 2)" "2" "$content"
assert_still_conflicted "mix: manual still conflicted" "$TMPDIR/mix" manual

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 10: path with spaces ==="
make_repo_with_conflict "$TMPDIR/sp" "with space|0|1|2"
echo '"with space" merge=theirs' > "$TMPDIR/sp/.gitattributes"
"$RESOLVER" "$TMPDIR/sp" >/dev/null 2>&1
rc=$?
check "exit 0 with spaced path" "0" "$rc"
assert_no_conflicts_at "spaced path resolved" "$TMPDIR/sp"
content=$(file_at "$TMPDIR/sp" "with space")
check "spaced path picked side 2" "2" "$content"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 11: non-colocated jj repo ==="
mkdir -p "$TMPDIR/standalone"
(
    cd "$TMPDIR/standalone"
    # No --colocate: bare jj repo, no .git visible to git check-attr.
    jj git init >/dev/null 2>&1 || true
)
# Even without conflicts, the resolver should bail out gracefully (or no-op)
# rather than crashing on missing .git.
out=$("$RESOLVER" "$TMPDIR/standalone" 2>&1); rc=$?
check "exit 0 on non-colocated repo" "0" "$rc"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 12: .gitattributes itself in conflict ==="
make_repo_with_conflict "$TMPDIR/atrconf" \
    ".gitattributes|base|left|right" \
    "data|0|1|2"
# At @, .gitattributes is conflicted; the working-copy materialisation has
# conflict markers in it. The resolver must not crash; it should at minimum
# leave both files alone or resolve `data` if it can read the gitattributes
# despite the conflict markers (git check-attr reads from the working tree
# in some configurations).
out=$("$RESOLVER" "$TMPDIR/atrconf" 2>&1); rc=$?
check "exit 0 with conflicted .gitattributes" "0" "$rc"
# We don't assert what happens to data — both behaviours are reasonable.
# We only assert no crash and exit 0.

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 13: defaults to cwd when no arg given ==="
make_repo_with_conflict "$TMPDIR/cwd" "lock|0|1|2"
echo 'lock merge=theirs' > "$TMPDIR/cwd/.gitattributes"
(cd "$TMPDIR/cwd" && "$RESOLVER" >/dev/null 2>&1)
rc=$?
check "exit 0 with no arg (cwd default)" "0" "$rc"
assert_no_conflicts_at "cwd default resolves" "$TMPDIR/cwd"

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 14: stdout reports counts ==="
make_repo_with_conflict "$TMPDIR/report" "a|0|1|2" "b|0|1|2"
cat > "$TMPDIR/report/.gitattributes" <<EOF
a merge=theirs
b merge=ours
EOF
out=$("$RESOLVER" "$TMPDIR/report" 2>&1); rc=$?
check "exit 0 on reportable batch" "0" "$rc"
# Loose check: the resolver should mention "2" somewhere in its summary, since
# two paths were resolved. We don't pin the exact wording.
echo "$out" | grep -qE '\b2\b' \
    && { echo "PASS: stdout mentions resolved count"; pass=$((pass+1)); } \
    || { echo "FAIL: stdout doesn't mention resolved count (got: $out)"; fail=$((fail+1)); }

# ────────────────────────────────────────────────────────────────────────────
# Note: there's no "operates only on @" scenario because jj propagates
# conflicts forward. A child of a conflicted commit is itself conflicted at
# the same paths, so "move @ off the conflict to make it benign" isn't a
# meaningful state — the resolver would still see the conflict at @ and
# rewriting @ would still rewrite the original (jj's first-class conflict
# semantics keep both views consistent).

# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Summary ==="
echo "PASS: $pass"
echo "FAIL: $fail"
if [ "$fail" -eq 0 ]; then
    echo "ALL $pass TESTS PASSED"
    exit 0
else
    exit 1
fi
