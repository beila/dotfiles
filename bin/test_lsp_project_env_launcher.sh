#!/usr/bin/env bash

set -uo pipefail

pass=0
fail=0
assert_eq() {
    if [ "$2" = "$3" ]; then
        echo "  ✓ $1"
        ((pass++))
    else
        echo "  ✗ $1"
        echo "    expected: $3"
        echo "    got: $2"
        ((fail++))
    fi
}
assert_file_contains() {
    if rg -q --fixed-strings -- "$2" "$3"; then
        echo "  ✓ $1"
        ((pass++))
    else
        echo "  ✗ $1"
        echo "    missing: $2"
        ((fail++))
    fi
}

dotfiles=$(cd "$(dirname "$0")/.." && pwd)
launcher="$dotfiles/bin/lsp-project-env-launcher"
tmp=$(mktemp -d /tmp/test_lsp_project_env_launcher.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/direnv" <<'EOF_DIRENV'
#!/usr/bin/env bash
if [ "$1" != exec ]; then
    exit 90
fi
root=$2
shift 2
if [ "$1" = true ]; then
    case "${FAKE_DIRENV_MODE:-success}" in
        fail) exit 23 ;;
        timeout) sleep 2 ;;
    esac
    printf 'preflight output that must not reach LSP stdout\n'
fi
export PROJECT_ENV_ROOT=$root
exec "$@"
EOF_DIRENV

cat >"$tmp/server" <<'EOF_SERVER'
#!/usr/bin/env bash
printf 'env=<%s>\n' "${PROJECT_ENV_ROOT:-direct}"
for arg in "$@"; do
    printf 'arg=<%s>\n' "$arg"
done
exit "${SERVER_EXIT:-0}"
EOF_SERVER
chmod +x "$tmp/direnv" "$tmp/server"

root="$tmp/project root"
mkdir -p "$root"

echo "== successful project environment =="
output=$("$launcher" 1s "$tmp/direnv" "$root" "$tmp/server" "one two" three)
assert_eq "direnv environment reaches server" "$(printf '%s\n' "$output" | sed -n '1p')" "env=<$root>"
assert_eq "arguments survive launcher" "$(printf '%s\n' "$output" | sed -n '2,3p')" \
    $'arg=<one two>\narg=<three>'
if [[ "$output" != *"preflight output"* ]]; then
    echo "  ✓ preflight output is isolated from LSP stdout"
    ((pass++))
else
    echo "  ✗ preflight output reached LSP stdout"
    ((fail++))
fi

echo "== failed project environment =="
failure_stderr="$tmp/failure.stderr"
output=$(FAKE_DIRENV_MODE=fail "$launcher" 1s "$tmp/direnv" "$root" "$tmp/server" 2>"$failure_stderr")
assert_eq "failed preflight starts direct server" "$output" "env=<direct>"
assert_file_contains "failed preflight explains fallback" "exit code 23" "$failure_stderr"

echo "== timed-out project environment =="
timeout_stderr="$tmp/timeout.stderr"
output=$(FAKE_DIRENV_MODE=timeout timeout 2s "$launcher" 0.05s \
    "$tmp/direnv" "$root" "$tmp/server" 2>"$timeout_stderr")
assert_eq "timed-out preflight starts direct server promptly" "$output" "env=<direct>"
assert_file_contains "timeout explains fallback" "timed out after 0.05s" "$timeout_stderr"

echo "== server status =="
set +e
SERVER_EXIT=17 "$launcher" 1s "$tmp/direnv" "$root" "$tmp/server" >/dev/null
status=$?
set -e
assert_eq "server exit status is preserved" "$status" "17"

echo
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
