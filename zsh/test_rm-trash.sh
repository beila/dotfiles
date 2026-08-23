#!/usr/bin/env bash
# Exercise the interactive rm wrapper without touching the real trash.

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UTILITY="$DOTFILES_ROOT/zsh/utility.zsh"

UTILITY_PATH="$UTILITY" zsh -f <<'ZSH'
emulate -L zsh

TEST_ROOT=$(mktemp -d /tmp/test-rm-trash.XXXXXX)
trap 'command rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

{
  print -r -- '#!/bin/sh'
  print -r -- 'printf "CALL\n" >> "$GIO_LOG"'
  print -r -- 'printf "%s\n" "$@" >> "$GIO_LOG"'
  print -r -- 'if [ "${1-}" = "--version" ]; then printf "gio 1.0\n"; fi'
} > "$TEST_ROOT/bin/gio"
chmod +x "$TEST_ROOT/bin/gio"

export GIO_LOG="$TEST_ROOT/gio.log"
PATH="$TEST_ROOT/bin:$PATH"
source "$UTILITY_PATH" || {
  print -u2 -r -- "FAIL: utility.zsh did not load"
  exit 1
}

typeset -i PASS=0 FAIL=0
_check() {
  local label=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then
    printf 'PASS: %s\n' "$label"
    (( PASS++ ))
  else
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$label" "$expected" "$actual"
    (( FAIL++ ))
  fi
}

: > "$GIO_LOG"
rm "plain file"
_check "plain path goes to trash" $'CALL\ntrash\n--\nplain file' "$(<"$GIO_LOG")"

: > "$GIO_LOG"
rm -rf first -R second
_check "recursive flags are removed and force is preserved" \
  $'CALL\ntrash\n--force\n--\nfirst\nCALL\ntrash\n--force\n--\nsecond' \
  "$(<"$GIO_LOG")"

: > "$GIO_LOG"
rm --recursive --force directory
_check "long recursive and force flags" \
  $'CALL\ntrash\n--force\n--\ndirectory' "$(<"$GIO_LOG")"

: > "$GIO_LOG"
rm -- -leading-dash
_check "option terminator preserves leading-dash path" \
  $'CALL\ntrash\n--\n-leading-dash' "$(<"$GIO_LOG")"

: > "$GIO_LOG"
printf 'y\nn\n' | rm -i first second 2>/dev/null
_check "interactive always trashes only confirmed paths" \
  $'CALL\ntrash\n--\nfirst' "$(<"$GIO_LOG")"

: > "$GIO_LOG"
printf 'y\n' | rm -I one two three four 2>/dev/null
_check "interactive once prompts for more than three paths" \
  $'CALL\ntrash\n--\none\nCALL\ntrash\n--\ntwo\nCALL\ntrash\n--\nthree\nCALL\ntrash\n--\nfour' \
  "$(<"$GIO_LOG")"

: > "$GIO_LOG"
printf 'n\n' | rm --interactive=once --recursive directory 2>/dev/null
_check "interactive once declines recursive operation" "" "$(<"$GIO_LOG")"

: > "$GIO_LOG"
verbose_output=$(rm -dv --one-file-system --preserve-root=all "verbose file")
_check "directory, filesystem, preserve-root, and verbose options" \
  $'CALL\ntrash\n--\nverbose file' "$(<"$GIO_LOG")"
_check "verbose output" 'trashed verbose\ file' "$verbose_output"

: > "$GIO_LOG"
root_output=$(rm -r / 2>&1)
root_status=$?
_check "preserve-root status" "1" "$root_status"
_check "preserve-root message" "rm: refusing to trash root directory '/'" "$root_output"
_check "preserve-root does not call gio" "" "$(<"$GIO_LOG")"

: > "$GIO_LOG"
rm --no-preserve-root -r /
_check "no-preserve-root reaches gio" $'CALL\ntrash\n--\n/' "$(<"$GIO_LOG")"

: > "$GIO_LOG"
invalid_output=$(rm --interactive=sometimes file 2>&1)
invalid_status=$?
_check "invalid interactive mode status" "2" "$invalid_status"
_check "invalid interactive mode message" \
  "rm: invalid argument 'sometimes' for --interactive" "$invalid_output"
_check "invalid interactive mode does not call gio" "" "$(<"$GIO_LOG")"

: > "$GIO_LOG"
help_output=$(rm --help)
_check "help describes trash behavior" "1" \
  "$([[ "$help_output" == *'Move FILEs and directories to the trash with gio.'* ]] &&
    print 1 || print 0)"
_check "help does not call gio" "" "$(<"$GIO_LOG")"

: > "$GIO_LOG"
version_output=$(rm --version)
_check "version identifies wrapper" $'rm (dotfiles gio trash wrapper)\ngio 1.0' \
  "$version_output"
_check "version asks gio for its version" $'CALL\n--version' "$(<"$GIO_LOG")"

missing_output=$(rm 2>&1)
missing_status=$?
_check "missing operand status" "1" "$missing_status"
_check "missing operand message" "rm: missing operand" "$missing_output"

permanent="$TEST_ROOT/permanent"
: > "$permanent"
: > "$GIO_LOG"
command rm -- "$permanent"
_check "command rm bypasses trash" "missing" \
  "$([[ -e "$permanent" ]] && print present || print missing)"
_check "command rm does not call gio" "" "$(<"$GIO_LOG")"

unalias rm
unfunction rm
mkdir "$TEST_ROOT/fallback-bin"
ln -s "${commands[rm]}" "$TEST_ROOT/fallback-bin/rm"
PATH="$TEST_ROOT/fallback-bin"
source "$UTILITY_PATH"
_check "no gio leaves rm as an external command" "0" "$(( $+functions[rm] ))"
fallback_file="$TEST_ROOT/fallback"
: > "$fallback_file"
eval 'rm -- "$fallback_file"'
_check "no-gio fallback permanently removes through original rm" "missing" \
  "$([[ -e "$fallback_file" ]] && print present || print missing)"

printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
ZSH
