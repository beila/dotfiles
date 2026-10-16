#!/usr/bin/env bash
# Tests for script/bin/kiro-agent-split with a fake $HOME.
#
# Usage: bash script/test_kiro-agent-split.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
KAS="$DOTFILES_ROOT/script/bin/kiro-agent-split"

TMP=$(mktemp -d /tmp/kiro_agent_split_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The dot and the plus examine the regular-expression escape of the home directory.
H="$TMP/h.o+me"
T="$TMP/tracked"
L="$H/.kiro/agents"
mkdir -p "$H" "$T"
export HOME="$H" XDG_STATE_HOME="$TMP/state" KIRO_AGENT_SPLIT_TRACKED="$T" KIRO_AGENT_SPLIT_LIVE="$L"

pass=0
fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ng() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ng "$1"; fi; }

# Jackson style, no final newline, as AIM writes it.
agent() { # agent TOKEN PATH [EXTRA]
    printf '{\n  "name" : "a",\n  "args" : [ "%s/skills" ],%s\n  "mcpServers" : {\n    "creds-agent" : {\n      "env" : {\n        "AIM_CREDS_AGENT_INJECTION" : "%s"\n      }\n    }\n  }\n}' \
        "$2" "${3:-}" "$1"
}

# --- migration from a link ----------------------------------------------------
agent tok-old '$HOME' >"$T/a.json"
cp "$T/a.json" "$TMP/a.orig"
mkdir -p "$L"
ln -s "$T/a.json" "$L/a.json"
"$KAS" extract
check "extract replaces the link with a regular file" '[ ! -L "$L/a.json" ] && [ -f "$L/a.json" ]'
check "detach leaves the tracked file unchanged" 'cmp -s "$T/a.json" "$TMP/a.orig"'

"$KAS" apply
check "apply writes the absolute home directory" 'grep -qF "\"$H/skills\"" "$L/a.json"'
check "apply keeps the final byte" '[ "$(tail -c1 "$L/a.json")" = "}" ]'

# --- token rotation -----------------------------------------------------------
agent tok-new "$H" >"$L/a.json"
"$KAS" extract
check "a new live token does not change the tracked file" 'cmp -s "$T/a.json" "$TMP/a.orig"'

# --- live edit ----------------------------------------------------------------
agent tok-newer "$H" '
  "tools" : [ "@x" ],' >"$L/a.json"
"$KAS" extract
check "a live edit goes to the tracked file" 'grep -qF "\"@x\"" "$T/a.json"'
check "the tracked token stays" 'grep -qF "\"tok-old\"" "$T/a.json" && ! grep -qF tok-newer "$T/a.json"'
check "the tracked file keeps \$HOME" 'grep -qF "\"\$HOME/skills\"" "$T/a.json" && ! grep -qF "$H" "$T/a.json"'

# --- tracked edit -------------------------------------------------------------
sed -i 's/"name" : "a"/"name" : "b"/' "$T/a.json"
"$KAS" extract
check "extract keeps a tracked edit when the live file did not change" 'grep -qF "\"name\" : \"b\"" "$T/a.json"'
"$KAS" apply
check "apply copies the tracked edit" 'grep -qF "\"name\" : \"b\"" "$L/a.json"'
check "apply keeps the live token" 'grep -qF "\"tok-newer\"" "$L/a.json"'
check "apply keeps the mode of the live file" '[ "$(stat -c %a "$L/a.json")" = 600 ]'

# --- both changed, no overlap -------------------------------------------------
sed -i 's/"name" : "b"/"name" : "c"/' "$T/a.json"
sed -i 's/"@x"/"@y"/' "$L/a.json"
"$KAS" extract
check "a 3-way merge keeps both edits" 'grep -qF "\"name\" : \"c\"" "$T/a.json" && grep -qF "\"@y\"" "$T/a.json"'

# --- both changed, same line --------------------------------------------------
"$KAS" apply
sed -i 's/"@y"/"@t"/' "$T/a.json"
sed -i 's/"@y"/"@l"/' "$L/a.json"
cp "$T/a.json" "$TMP/a.before"
"$KAS" extract 2>"$TMP/err"
rc=$?
check "a merge conflict fails" '[ $rc -ne 0 ] && grep -q "both changed" "$TMP/err"'
check "a merge conflict keeps the tracked file" 'cmp -s "$T/a.json" "$TMP/a.before"'
"$KAS" apply 2>/dev/null
rc=$?
check "apply refuses while a live edit is unmerged" '[ $rc -ne 0 ] && grep -qF "\"@l\"" "$L/a.json"'

# --- invalid JSON -------------------------------------------------------------
rm -f "$XDG_STATE_HOME"/kiro-agent-split/*/a.json.live
printf '<<<<<<<\n' >>"$T/a.json"
cp "$L/a.json" "$TMP/live.before"
"$KAS" apply 2>/dev/null
rc=$?
check "apply refuses a tracked file with conflict markers" '[ $rc -ne 0 ] && cmp -s "$L/a.json" "$TMP/live.before"'

# --- new host -----------------------------------------------------------------
agent tok-old '$HOME' >"$T/a.json"
rm -rf "$L"
"$KAS" apply
check "apply creates a missing live file with mode 600" '[ -f "$L/a.json" ] && [ "$(stat -c %a "$L/a.json")" = 600 ]'

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
