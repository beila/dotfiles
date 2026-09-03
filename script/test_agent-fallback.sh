#!/usr/bin/env bash

set -u

SCRIPT=${1:-"$(cd "$(dirname "$0")" && pwd)/agent-fallback"}
LOGGER=${2:-"$(cd "$(dirname "$SCRIPT")" && pwd)/logger/log.sh"}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-agent-fallback.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/output" "$tmp/work"
printf 'do the task' > "$tmp/prompt"
printf '' > "$tmp/calls"

make_agent() {
    local name=$1 body=$2
    {
        echo '#!/usr/bin/env bash'
        printf 'echo %q >> %q\n' "$name" "$tmp/calls"
        printf '%s\n' "$body"
    } > "$tmp/bin/$name"
    chmod +x "$tmp/bin/$name"
}

run_fallback() {
    LOG_ROOT="$tmp/logs" \
    LOG_NOTIFY_MODE=never \
    AGENT_FALLBACK_LOGGER="$LOGGER" \
    AGENT_FALLBACK_CODEX="$tmp/bin/codex" \
    AGENT_FALLBACK_CLAUDE="$tmp/bin/claude" \
    AGENT_FALLBACK_KIRO="$tmp/bin/kiro" \
        "$SCRIPT" \
        --cwd "$tmp/work" \
        --prompt-file "$tmp/prompt" \
        --output-dir "$tmp/output" \
        --timeout 10 \
        --task-name "test generation" \
        --failure-message "Test generation failed" "$@"
}

report_error() {
    LOG_ROOT="$tmp/logs" \
    AGENT_FALLBACK_LOGGER="$LOGGER" \
        "$SCRIPT" \
        --task-name "test report" \
        --log-context "test-report" \
        --report-error "$1"
}

make_agent codex 'echo "Please sign in" >&2; exit 1'
make_agent claude 'echo "compiler failed" >&2; exit 2'
make_agent kiro 'echo "generated"; exit 0'
selected=$(run_fallback)
[ "$selected" = kiro ] || { echo "expected kiro, got $selected" >&2; exit 1; }
[ "$(tr '\n' ' ' < "$tmp/calls")" = "codex claude kiro " ] || exit 1

: > "$tmp/calls"
make_agent codex 'echo "generated"; exit 0'
make_agent claude 'echo "must not run" >&2; exit 2'
selected=$(run_fallback)
[ "$selected" = codex ] || exit 1
[ "$(cat "$tmp/calls")" = codex ] || exit 1

: > "$tmp/calls"
make_agent codex 'echo "Please sign in" >&2; exit 1'
make_agent claude 'echo "HTTP 401 Unauthorized" >&2; exit 1'
make_agent kiro 'echo "temporarily unavailable" >&2; exit 1'
run_fallback >/dev/null 2>"$tmp/error"
[ "$?" -eq 75 ] || exit 1
[ ! -s "$tmp/error" ] || exit 1

: > "$tmp/calls"
make_agent codex 'echo "must not run" >&2; exit 2'
make_agent claude 'echo "generated"; exit 0'
selected=$(run_fallback --skip codex)
[ "$selected" = claude ] || exit 1
[ "$(cat "$tmp/calls")" = claude ] || exit 1

: > "$tmp/calls"
make_agent codex 'echo "must not run" >&2; exit 2'
make_agent claude 'echo "must not run" >&2; exit 2'
make_agent kiro 'echo "must not run" >&2; exit 2'
run_fallback \
    --skip codex \
    --skip claude \
    --skip kiro \
    --prior-error "codex: result validation failed" \
    >/dev/null 2>"$tmp/error"
[ "$?" -eq 1 ] || exit 1
rg -q "Test generation failed: caller: codex: result validation failed" "$tmp/logs"

report_error "request 123456 failed" >/dev/null 2>&1
[ "$?" -eq 1 ] || exit 1
rg -q "request 123456 failed" "$tmp/logs"

echo "agent-fallback tests passed"
