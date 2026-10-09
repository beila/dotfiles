#!/usr/bin/env bash
# Tests for script/bin/home-template with real jj repositories and a fake $HOME.
#
# Usage: bash script/test_home-template.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HT="$DOTFILES_ROOT/script/bin/home-template"

TMP=$(mktemp -d /tmp/home_template_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The dot and the plus examine the regular-expression escape of the home directory.
H="$TMP/h.o+me"
mkdir -p "$H"
export HOME="$H"
export XDG_STATE_HOME="$TMP/state"
export JJ_CONFIG="$TMP/jj.toml"
cat >"$JJ_CONFIG" <<'EOF'
user.name = "Test"
user.email = "test@example.com"
EOF

pass=0
fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ng() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ng "$1"; return 1; fi; }
tracked() { [ -n "$(jj --ignore-working-copy file list "root:$1" 2>/dev/null)" ]; }
has_line() { grep -qxF -- "$2" "$1"; }

# --- conversion --------------------------------------------------------------
R="$TMP/repo"
mkdir -p "$R"
cd "$R" || exit 1
jj git init >/dev/null 2>&1
mkdir -p sub
printf 'path=%s/x\n' "$H" >a.conf
printf 'dir=%s\n' "$H" >sub/b.conf
printf 'echo "$HOME"\n' >legit.sh
printf '\0%s\n' "$H" >bin.dat
printf '%s2/x\n' "$H" >prefix.txt
jj commit -m base >/dev/null 2>&1
printf 'new=%s/n\n' "$H" >new.txt

"$HT" capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "capture exits 0" '[ $rc -eq 0 ]'
check "template replaces the home directory" '[ "$(cat a.conf.home-template)" = "path=@HOME@/x" ]'
check "live file keeps the home directory" '[ "$(cat a.conf)" = "path=$H/x" ]'
check "root .gitignore has /a.conf" 'has_line .gitignore /a.conf'
check "subdirectory .gitignore has /b.conf" 'has_line sub/.gitignore /b.conf'
check "a.conf is untracked" '! tracked a.conf'
check "templates are tracked" 'tracked a.conf.home-template && tracked sub/b.conf.home-template'
check "new file is converted and never tracked" '[ -f new.txt.home-template ] && ! tracked new.txt && tracked new.txt.home-template'
check "literal \$HOME is not converted" '[ ! -e legit.sh.home-template ] && tracked legit.sh'
check "binary file is not converted" '[ ! -e bin.dat.home-template ]'
check "longer name with the same prefix is not converted" '[ ! -e prefix.txt.home-template ]'
check "capture reports conversions" 'grep -q "converted a.conf to a.conf.home-template" "$TMP/out"'

printf '%s @HOME@\n' "$H" >tok.txt
"$HT" capture >/dev/null 2>"$TMP/err"
rc=$?
check "file with the token is refused" '[ $rc -eq 1 ] && [ ! -e tok.txt.home-template ] && grep -q "tok.txt contains" "$TMP/err"'
rm tok.txt

"$HT" capture >"$TMP/out" 2>&1
check "second capture is a no-op" '[ ! -s "$TMP/out" ]'

mkdir -p logs/host
printf 'cwd=%s\n' "$H" >logs/host/run.log
printf 'cwd=%s\n' "$H" >keep.jsonl
jj config set --repo sync.home-template-exclude 'logs/* *.jsonl' >/dev/null 2>&1
"$HT" capture >/dev/null 2>&1
check "excluded paths are not converted, also in subdirectories" '[ ! -e logs/host/run.log.home-template ] && [ ! -e keep.jsonl.home-template ]'
rm -r logs keep.jsonl

# --- render ----------------------------------------------------------------
printf 'path=@HOME@/x\nb=@HOME@/y\n' >a.conf.home-template
inode=$(stat -c %i a.conf)
"$HT" capture >/dev/null 2>&1
check "capture keeps a template-only change" '[ "$(sed -n 2p a.conf.home-template)" = "b=@HOME@/y" ]'
"$HT" render >"$TMP/out" 2>&1
check "render writes the template change" '[ "$(sed -n 2p a.conf)" = "b=$H/y" ]'
check "render keeps the inode" '[ "$(stat -c %i a.conf)" = "$inode" ]'

printf 'c=%s/z\n' "$H" >>a.conf
"$HT" capture >/dev/null 2>&1
check "capture copies a local change" '[ "$(sed -n 3p a.conf.home-template)" = "c=@HOME@/z" ]'

sed -i "1s|.*|path=$H/x2|" a.conf
sed -i '3s|.*|c=@HOME@/z2|' a.conf.home-template
"$HT" capture >/dev/null 2>&1
check "capture merges changes on both sides" '[ "$(sed -n 1p a.conf.home-template)" = "path=@HOME@/x2" ] && [ "$(sed -n 3p a.conf.home-template)" = "c=@HOME@/z2" ]'
"$HT" render >/dev/null 2>&1
check "render writes the merge result" '[ "$(cat a.conf)" = "$(printf "path=%s/x2\nb=%s/y\nc=%s/z2" "$H" "$H" "$H")" ]'

sed -i "2s|.*|b=$H/local|" a.conf
sed -i '2s|.*|b=@HOME@/remote|' a.conf.home-template
"$HT" render >/dev/null 2>"$TMP/err"
rc=$?
check "render keeps the file on a conflict" '[ $rc -eq 1 ] && [ "$(sed -n 2p a.conf)" = "b=$H/local" ]'
"$HT" capture >/dev/null 2>&1
check "capture lets the file win a conflict" '[ "$(sed -n 2p a.conf.home-template)" = "b=@HOME@/local" ]'

rm sub/b.conf
"$HT" render >/dev/null 2>&1
check "render creates a missing file" '[ "$(cat sub/b.conf)" = "dir=$H" ]'

# --- migration from a remote that converted the file first -------------------
M="$TMP/migrate"
mkdir -p "$M"
cd "$M" || exit 1
jj git init >/dev/null 2>&1
# git merge-file conflicts on changes in adjacent lines. Line 2 separates the edits.
printf '%s/old\nmid\nline3\n' "$H" >x.conf
jj commit -m base >/dev/null 2>&1
base=$(jj log -r @- --no-graph -T change_id)

jj new "$base" >/dev/null 2>&1
printf '@HOME@/old\nmid\nline3-remote\n' >x.conf.home-template
printf '/x.conf\n' >.gitignore
jj file untrack x.conf >/dev/null 2>&1
jj commit -m remote >/dev/null 2>&1
jj bookmark create upstream -r @- >/dev/null 2>&1

jj new "$base" >/dev/null 2>&1
printf '%s/new\nmid\nline3\n' "$H" >x.conf
jj commit -m local >/dev/null 2>&1
jj config set --repo sync.remote-bookmark upstream >/dev/null 2>&1

"$HT" capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "migration exits 0" '[ $rc -eq 0 ]'
check "migration untracks x.conf" '! tracked x.conf && has_line .gitignore /x.conf'
check "migration creates no local template" '[ ! -e x.conf.home-template ]'
check "migration keeps the local edit" '[ "$(sed -n 1p x.conf)" = "$H/new" ]'

jj rebase -b @ -d upstream >/dev/null 2>&1
check "rebase has no conflicts" '[ -z "$(jj log -r "conflicts()" --no-graph -T change_id)" ]'
"$HT" render >"$TMP/out" 2>"$TMP/err"
rc=$?
check "render after migration exits 0" '[ $rc -eq 0 ]' || cat "$TMP/err"
check "render merges the local edit and the remote change" '[ "$(cat x.conf)" = "$(printf "%s/new\nmid\nline3-remote" "$H")" ]'
"$HT" capture >/dev/null 2>&1
check "capture after migration copies the local edit" '[ "$(cat x.conf.home-template)" = "$(printf "@HOME@/new\nmid\nline3-remote")" ]'

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
