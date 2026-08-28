#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$ROOT/bin/dropbox-get"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-dropbox-get.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

STUB_BIN="$TEST_ROOT/bin"
STATE="$TEST_ROOT/state"
mkdir -p "$STUB_BIN" "$STATE"

cat >"$STUB_BIN/rclone" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

case "${1:-} ${2:-}" in
    "listremotes ")
        if [[ -e "$TEST_STATE/configured" ]]; then
            printf 'dropbox:\n'
        fi
        ;;
    "config create")
        touch "$TEST_STATE/configured"
        printf '{"token":"must-not-be-visible"}\n'
        ;;
    "lsf --recursive")
        printf 'Documents/report.txt\t12\t2026-01-01 00:00:00\n'
        printf 'Photos/image.jpg\t34\t2026-01-02 00:00:00\n'
        ;;
    "copy dropbox:")
        if [[ " $* " == *" --files-from-raw "* ]]; then
            list=
            while (($#)); do
                if [[ "$1" == "--files-from-raw" ]]; then
                    list=$2
                    break
                fi
                shift
            done
            cp "$list" "$TEST_STATE/selection"
        fi
        ;;
esac
EOF

cat >"$STUB_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
printf 'fzf ' >>"$TEST_LOG"
printf '%q ' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
cat >/dev/null
case "${TEST_FZF_RESULT:-select}" in
    select)
        printf 'Documents/report.txt\t12\t2026-01-01 00:00:00\n'
        ;;
    cancel)
        exit 130
        ;;
esac
EOF

chmod +x "$STUB_BIN/rclone" "$STUB_BIN/fzf"

export PATH="$STUB_BIN:$PATH"
export TEST_LOG="$STATE/calls"
export TEST_STATE="$STATE"
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

failures=0
check() {
    local description=$1
    local expected=$2
    local actual=$3
    if [[ "$actual" == "$expected" ]]; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' \
            "$description" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

output=$("$UNDER_TEST" report 2>&1)
check "first run authorizes the Dropbox remote" \
    "1" "$(rg -c '^config create dropbox dropbox ' "$TEST_LOG")"
check "OAuth token output is suppressed" \
    "0" "$(printf '%s\n' "$output" | rg -c 'must-not-be-visible' || printf 0)"
check "query is forwarded to fzf" \
    "1" "$(rg -c -- '--query=report ' "$TEST_LOG" 2>/dev/null || true)"
check "selected path is passed to rclone" \
    "Documents/report.txt" "$(cat "$STATE/selection")"
check "default destination is used" \
    "1" "$(rg -c "copy dropbox: $HOME/Downloads/Dropbox " "$TEST_LOG")"

: >"$TEST_LOG"
rm -f "$STATE/selection"
TEST_FZF_RESULT=cancel "$UNDER_TEST"
check "cancelling does not download" \
    "0" "$(rg -c '^copy dropbox: ' "$TEST_LOG" || printf 0)"

: >"$TEST_LOG"
"$UNDER_TEST" --all --to "$TEST_ROOT/all"
check "--all downloads without listing" \
    "0" "$(rg -c '^lsf ' "$TEST_LOG" || printf 0)"
check "--all uses the requested destination" \
    "1" "$(rg -c "copy dropbox: $TEST_ROOT/all --progress " "$TEST_LOG")"

if ((failures)); then
    printf '\n%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf '\nAll dropbox-get tests passed\n'
