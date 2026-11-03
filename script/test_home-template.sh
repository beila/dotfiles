#!/usr/bin/env bash
# Tests for script/bin/home-template with real jj repositories and a fake $HOME.
#
# Usage: bash script/test_home-template.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HT="${HT:-$DOTFILES_ROOT/script/bin/home-template}"

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
printf '/local%s/x\n' "$H" >other-home.txt
printf -- '-L%s/lib:%s/a\n' "$H" "$H" >flags.txt
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
check "home path at the end of a longer path is not converted" '[ ! -e other-home.txt.home-template ]'
check "home path after a flag and after a separator is converted" '[ "$(cat flags.txt.home-template)" = "-L@HOME@/lib:@HOME@/a" ]'
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

# The legacy rule changed /local$H to /local@HOME@. A one-time fix of the template to
# @HOME@ must reach the live file, and must not look like a local edit.
printf '/local@HOME@/aim\n' >legacy.conf.home-template
printf '/local%s/aim\n' "$H" >legacy.conf
printf '/legacy.conf\n' >>.gitignore
jj status >/dev/null 2>&1
add_state() { mkdir -p "$XDG_STATE_HOME/home-template" && cp "$2" "$XDG_STATE_HOME/home-template/$(printf '%s' "$R/$1" | sha256sum | cut -c1-16)"; }
add_state legacy.conf legacy.conf.home-template
printf '@HOME@/aim\n' >legacy.conf.home-template
"$HT" capture >/dev/null 2>&1
check "capture keeps the fixed template" '[ "$(cat legacy.conf.home-template)" = "@HOME@/aim" ]'
"$HT" render >/dev/null 2>&1
check "render writes the fixed template" '[ "$(cat legacy.conf)" = "$H/aim" ]'

# --- track again when the home directory is gone ------------------------------
printf 'p=%s/q\n' "$H" >r.conf
"$HT" capture >/dev/null 2>&1
printf 'p=/opt/q\n' >r.conf
"$HT" capture >/dev/null 2>&1
check "capture copies the edit without the home directory" '[ "$(cat r.conf.home-template)" = "p=/opt/q" ]'
"$HT" render >"$TMP/out" 2>&1
check "render tracks the file again" 'tracked r.conf && [ ! -e r.conf.home-template ] && ! has_line .gitignore /r.conf'
check "render reports the change" 'grep -q "tracked r.conf again" "$TMP/out"'
check "the file keeps its content" '[ "$(cat r.conf)" = "p=/opt/q" ]'

printf 'z=%s\n' "$H" >keep.log
"$HT" capture >/dev/null 2>&1
printf 'z=%s more\n' "$H" >keep.log
jj config set --repo sync.home-template-exclude 'keep.log' >/dev/null 2>&1
"$HT" capture >/dev/null 2>&1
check "an existing template of an excluded path is not updated" '[ "$(cat keep.log.home-template)" = "z=@HOME@" ]'
jj config unset --repo sync.home-template-exclude >/dev/null 2>&1

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

# --- a remote that tracked the file again ---------------------------------------
N="$TMP/retrack"
mkdir -p "$N"
cd "$N" || exit 1
jj git init >/dev/null 2>&1
printf 'a\nb\n@HOME@/m\nd\ne\n' >x.conf.home-template
printf 'a\nb\n%s/m\nd\ne\n' "$H" >x.conf
printf '/x.conf\n' >.gitignore
"$HT" render >/dev/null 2>&1
jj commit -m base >/dev/null 2>&1
base=$(jj log -r @- --no-graph -T change_id)

jj new "$base" >/dev/null 2>&1
rm x.conf.home-template .gitignore
# The remote removed the home directory and tracked the file again.
printf 'a\nb\n/opt/m\nd\ne-remote\n' >x.conf
jj commit -m remote >/dev/null 2>&1
jj bookmark create upstream -r @- >/dev/null 2>&1

jj new "$base" >/dev/null 2>&1
printf 'a-local\nb\n%s/m\nd\ne\n' "$H" >x.conf
jj config set --repo sync.remote-bookmark upstream >/dev/null 2>&1

"$HT" capture >"$TMP/out" 2>&1
check "capture deletes the template that the remote deleted" '[ ! -e x.conf.home-template ] && grep -q "removed x.conf.home-template" "$TMP/out"'
jj rebase -b @ -d upstream >/dev/null 2>&1
check "rebase after the remote tracked the file again has no conflicts" '[ -z "$(jj log -r "conflicts()" --no-graph -T change_id)" ]'
"$HT" render >"$TMP/out" 2>&1
check "render merges the local edit into the received file" '[ "$(cat x.conf)" = "$(printf "a-local\nb\n/opt/m\nd\ne-remote")" ]'
check "the received file is tracked" 'tracked x.conf'

# --- limits and ignore sources -------------------------------------------------
G="$TMP/generated"
mkdir -p "$G"
cd "$G" || exit 1
# Without a Git checkout, rg does not read info/exclude by itself.
jj git init --no-colocate >/dev/null 2>&1
mkdir -p build_x
for i in 1 2 3; do printf 'dir=%s/b%s\n' "$H" "$i" >"build_x/f$i.txt"; done
jj config set --repo sync.home-template-max-new 2 >/dev/null 2>&1
"$HT" capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "more new files than the limit: nothing is converted" \
    '[ $rc -eq 1 ] && [ -z "$(find . -name "*.home-template" -not -path "./.jj/*")" ] && [ ! -e build_x/.gitignore ]'
check "the limit warning names the directory" 'grep -q "3 new files" "$TMP/err" && grep -q "build_x/ (3)" "$TMP/err"'

# jj reads info/exclude of the Git store, also in a workspace without a Git checkout.
git_dir=$(jj --ignore-working-copy git root)
mkdir -p "$git_dir/info"
printf '/build_x/\n' >>"$git_dir/info/exclude"
"$HT" capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "files that info/exclude ignores are not converted" '[ $rc -eq 0 ] && [ ! -s "$TMP/out" ]' ||
    cat "$TMP/out" "$TMP/err"
jj config unset --repo sync.home-template-max-new >/dev/null 2>&1

# A conversion that stopped before the untrack step leaves FILE tracked.
printf 'p=%s/half\n' "$H" >half.conf
jj status >/dev/null 2>&1
printf 'p=@HOME@/half\n' >half.conf.home-template
"$HT" capture >"$TMP/out" 2>"$TMP/err"
check "capture untracks a FILE that has a template" '! tracked half.conf && has_line .gitignore /half.conf'

# --- full disk ------------------------------------------------------------------
# On 2026-11-01 a full disk made each write fail. Empty templates replaced all the
# templates, render wrote the empty templates to the live files, and the empty files
# were tracked again. A file size limit makes the large writes fail in the same way.
# SIGXFSZ is ignored, so a write gets EFBIG and the process continues.
R="$TMP/repo-full"
mkdir -p "$R"
cd "$R" || exit 1
jj git init >/dev/null 2>&1
{
    printf 'home=%s/big\n' "$H"
    seq 1 4000
} >big.conf
"$HT" capture >/dev/null 2>&1
jj commit -m base >/dev/null 2>&1
limited() { bash -c 'trap "" XFSZ; ulimit -f 8; exec "$0" "$@"' "$HT" "$@"; }
printf 'more=%s/m\n' "$H" >>big.conf
cp big.conf.home-template "$TMP/template.before"
cp big.conf "$TMP/live.before"
limited capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "full disk: capture fails" '[ $rc -ne 0 ]'
check "full disk: capture keeps the template" 'cmp -s big.conf.home-template "$TMP/template.before"'
check "full disk: capture keeps the live file" 'cmp -s big.conf "$TMP/live.before"'

cp "$TMP/live.before" big.conf
"$HT" capture >/dev/null 2>&1
printf 'remote=@HOME@/r\n' >>big.conf.home-template
cp big.conf "$TMP/live.before"
limited render >"$TMP/out" 2>"$TMP/err"
rc=$?
check "full disk: render fails" '[ $rc -ne 0 ]'
check "full disk: render keeps the live file" 'cmp -s big.conf "$TMP/live.before"'
check "full disk: render leaves no temporary file" '[ -z "$(find . -maxdepth 1 -name "big.conf.??????")" ]'
"$HT" render >/dev/null 2>&1
check "full disk: a later render writes the change" '[ "$(tail -n 1 big.conf)" = "remote=$H/r" ]'

: >big.conf.home-template
cp big.conf "$TMP/live.before"
"$HT" render >"$TMP/out" 2>"$TMP/err"
rc=$?
check "empty template: render fails and keeps the live file" '[ $rc -ne 0 ] && cmp -s big.conf "$TMP/live.before"'
check "empty template: the file is not tracked again" '! tracked big.conf && [ -e big.conf.home-template ] && has_line .gitignore /big.conf'

# --- home directory is a symbolic link ----------------------------------------
# On electra, $HOME is a link like /home/alice -> /local/home/alice. Programs that resolve
# links write the real path. Both forms must become the token.
mkdir -p "$TMP/local/link-home"
ln -s "$TMP/local/link-home" "$TMP/link-home"
R="$TMP/repo-link"
mkdir -p "$R"
cd "$R" || exit 1
jj git init >/dev/null 2>&1
printf 'real=%s/local/link-home/a\nlink=%s/link-home/b\n' "$TMP" "$TMP" >paths.conf
HOME="$TMP/link-home" XDG_STATE_HOME="$TMP/state-link" "$HT" capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "symlinked home: capture exits 0" '[ $rc -eq 0 ]'
check "symlinked home: real path and link path become the token" \
    '[ "$(cat paths.conf.home-template)" = "$(printf "real=@HOME@/a\nlink=@HOME@/b")" ]'
rm paths.conf
HOME="$TMP/link-home" XDG_STATE_HOME="$TMP/state-link" "$HT" render >"$TMP/out" 2>"$TMP/err"
check "symlinked home: render writes \$HOME" \
    '[ "$(cat paths.conf)" = "$(printf "real=%s/link-home/a\nlink=%s/link-home/b" "$TMP" "$TMP")" ]'
HOME="$TMP/link-home" XDG_STATE_HOME="$TMP/state-link" "$HT" capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "symlinked home: capture after render changes nothing" \
    '[ $rc -eq 0 ] && [ ! -s "$TMP/out" ] && [ ! -s "$TMP/err" ]'

# --- TOML keys with a symlinked home --------------------------------------------
# Codex finds project keys with the real path and hook keys with the link. The live
# file must have each key in both forms, and the template must have it one time.
htl() { HOME="$TMP/link-home" XDG_STATE_HOME="$TMP/state-link" "$HT" "$@"; }
toml_valid() { python3 -I -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; }
L="$TMP/link-home"
RL="$TMP/local/link-home"
cat >cfg.toml <<EOF
model = "m"

[hooks.state."$L/.codex/hooks.json:a:0:0"]
trusted_hash = "h1"

[projects."$RL/p"]
trust_level = "trusted"
EOF
htl capture >/dev/null 2>"$TMP/err"
check "toml: capture converts both forms to one token" \
    'grep -qxF "[projects.\"@HOME@/p\"]" cfg.toml.home-template && grep -qxF "[hooks.state.\"@HOME@/.codex/hooks.json:a:0:0\"]" cfg.toml.home-template'
rm cfg.toml
htl render >/dev/null 2>"$TMP/err"
check "toml: render writes each key in both home forms" \
    'grep -qxF "[projects.\"$L/p\"]" cfg.toml && grep -qxF "[projects.\"$RL/p\"]" cfg.toml &&
     grep -qxF "[hooks.state.\"$L/.codex/hooks.json:a:0:0\"]" cfg.toml &&
     grep -qxF "[hooks.state.\"$RL/.codex/hooks.json:a:0:0\"]" cfg.toml'
check "toml: the rendered file is valid TOML" 'toml_valid cfg.toml'
cp cfg.toml.home-template "$TMP/cfg.template"
htl capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "toml: capture after render changes nothing" \
    '[ $rc -eq 0 ] && [ ! -s "$TMP/out" ] && cmp -s cfg.toml.home-template "$TMP/cfg.template"'

sed -i "\|^\[hooks.state.\"$L/|,+1 s|h1|h2|" cfg.toml
htl capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "toml: capture takes the changed link copy" \
    '[ $rc -eq 0 ] && grep -qxF "trusted_hash = \"h2\"" cfg.toml.home-template && [ "$(grep -c "^\[hooks" cfg.toml.home-template)" -eq 1 ]'
check "toml: capture writes the merged value to both copies" \
    '[ "$(grep -cxF "trusted_hash = \"h2\"" cfg.toml)" -eq 2 ] && ! grep -qF h1 cfg.toml && toml_valid cfg.toml'
htl capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "toml: the next capture keeps the merged value" \
    '[ $rc -eq 0 ] && [ ! -s "$TMP/out" ] && grep -qxF "trusted_hash = \"h2\"" cfg.toml.home-template'

sed -i "\|^\[projects.\"$RL/p\"\]|,+1 s|\"trusted\"|\"untrusted\"|" cfg.toml
htl capture >/dev/null 2>"$TMP/err"
check "toml: capture takes the changed real-path copy" \
    'grep -qxF "trust_level = \"untrusted\"" cfg.toml.home-template && [ "$(grep -cxF "trust_level = \"untrusted\"" cfg.toml)" -eq 2 ]'

sed -i "\|^\[projects.\"$L/p\"\]|,+1d" cfg.toml
htl capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "toml: a missing copy is not a deletion" \
    '[ $rc -eq 0 ] && [ ! -s "$TMP/out" ] && grep -qxF "[projects.\"@HOME@/p\"]" cfg.toml.home-template'

printf '\n[projects."%s/new"]\ntrust_level = "trusted"\n' "$RL" >>cfg.toml
htl capture >/dev/null 2>"$TMP/err"
check "toml: a new real-path key becomes one key" '[ "$(grep -cxF "[projects.\"@HOME@/new\"]" cfg.toml.home-template)" -eq 1 ]'

printf '\n[projects."@HOME@/remote"]\ntrust_level = "trusted"\n' >>cfg.toml.home-template
htl render >/dev/null 2>"$TMP/err"
check "toml: render of a remote change writes copies of all keys" \
    'grep -qxF "[projects.\"$L/remote\"]" cfg.toml && grep -qxF "[projects.\"$RL/remote\"]" cfg.toml &&
     grep -qxF "[projects.\"$L/p\"]" cfg.toml && toml_valid cfg.toml'

sed -i "\|^\[projects.\"$L/remote\"\]|,+1 s|\"trusted\"|\"untrusted\"|; \|^\[projects.\"$RL/remote\"\]|,+1 s|\"trusted\"|\"other\"|" cfg.toml
cp cfg.toml.home-template "$TMP/cfg.template"
htl capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "toml: different changes in both copies stop the capture" \
    '[ $rc -eq 1 ] && cmp -s cfg.toml.home-template "$TMP/cfg.template" && grep -q "both home forms" "$TMP/err"'
sed -i 's|"other"|"untrusted"|' cfg.toml
htl capture >/dev/null 2>"$TMP/err"
rc=$?
check "toml: equal copies let the capture continue" '[ $rc -eq 0 ] && [ "$(grep -c "untrusted" cfg.toml.home-template)" -eq 2 ]'

# Without tomllib, the line rules apply. The key guard then stops the copies from
# becoming one key two times.
mkdir -p "$TMP/nopython"
printf '#!/bin/sh\nexit 1\n' >"$TMP/nopython/python3"
chmod +x "$TMP/nopython/python3"
cp cfg.toml.home-template "$TMP/cfg.template"
PATH="$TMP/nopython:$PATH" htl capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "toml without python: the key guard stops the capture" \
    '[ $rc -eq 1 ] && cmp -s cfg.toml.home-template "$TMP/cfg.template" && grep -q "become one key" "$TMP/err"'

printf '{\n  "%s/x": 1,\n  "%s/x": 2\n}\n' "$L" "$RL" >keys.json
htl capture >"$TMP/out" 2>"$TMP/err"
rc=$?
check "json: two home forms of a key stop the conversion" \
    '[ $rc -eq 1 ] && [ ! -e keys.json.home-template ] && grep -q "become one key" "$TMP/err"'
rm keys.json
printf '[\n  "%s/x",\n  "%s/x"\n]\n' "$L" "$RL" >values.json
htl capture >/dev/null 2>"$TMP/err"
rc=$?
check "json: equal values in an array are permitted" '[ $rc -eq 0 ] && [ -f values.json.home-template ]'
printf 'a:\n  %s/x: 1\nb:\n  %s/x: 2\n' "$L" "$L" >same.yaml
htl capture >/dev/null 2>"$TMP/err"
rc=$?
check "yaml: one key below two parents is permitted" '[ $rc -eq 0 ] && [ -f same.yaml.home-template ]'

# Without a symbolic link, both forms are the same. Render writes no copies.
R="$TMP/repo-plain"
mkdir -p "$R"
cd "$R" || exit 1
jj git init >/dev/null 2>&1
printf '[projects."%s/p"]\ntrust_level = "trusted"\n' "$H" >plain.toml
"$HT" capture >/dev/null 2>"$TMP/err"
rm plain.toml
"$HT" render >/dev/null 2>"$TMP/err"
check "toml without a symlinked home: render writes one key" \
    '[ "$(cat plain.toml)" = "$(printf "[projects.\"%s/p\"]\ntrust_level = \"trusted\"" "$H")" ]'

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
