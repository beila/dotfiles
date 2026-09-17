#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATUS="$ROOT/bin/midway-status"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

write_cookie() {
    local name=${3:-session}
    printf '# Netscape HTTP Cookie File\n#HttpOnly_midway-auth.amazon.com\tFALSE\t/\tTRUE\t%s\t%s\tplaceholder\n' \
        "$2" "$name" > "$1"
}

cat > "$TMP/curl" <<'EOF'
#!/usr/bin/env bash
printf x >> "$MIDWAY_TEST_CALLS"
printf '%s\n' "$MIDWAY_TEST_RESPONSE"
exit "${MIDWAY_TEST_CURL_EXIT:-0}"
EOF
chmod +x "$TMP/curl"

run_status() {
    MIDWAY_COOKIE_FILE="$TMP/cookie" \
    MIDWAY_STATUS_CACHE_FILE="$TMP/cache" \
    MIDWAY_STATUS_CURL="$TMP/curl" \
    MIDWAY_TEST_CALLS="$TMP/calls" \
    MIDWAY_TEST_RESPONSE="${MIDWAY_TEST_RESPONSE-}" \
    MIDWAY_TEST_CURL_EXIT="${MIDWAY_TEST_CURL_EXIT:-0}" \
    MIDWAY_NOW="${MIDWAY_NOW:-1000}" \
        "$STATUS" "$@"
}

write_cookie "$TMP/cookie" 10000
MIDWAY_TEST_RESPONSE='{"authenticated":true}' run_status --refresh > "$TMP/out"
rg -q $'^valid\t10000\t1000\tserver$' "$TMP/out"

MIDWAY_TEST_RESPONSE='{"authenticated":false}' run_status > "$TMP/out"
rg -q $'^valid\t10000\t1000\tserver$' "$TMP/out"
[[ $(wc -c < "$TMP/calls") == 1 ]]

set +e
MIDWAY_TEST_RESPONSE='{"authenticated":false}' run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^invalid\t10000\t1000\tserver$' "$TMP/out"

set +e
MIDWAY_TEST_CURL_EXIT=7 run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 2 ]]
rg -q $'^unknown\t10000\t1000\tnetwork$' "$TMP/out"

write_cookie "$TMP/cookie" 999
set +e
MIDWAY_TEST_RESPONSE='{"authenticated":true}' run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^expired\t999\t0\tlocal$' "$TMP/out"

write_cookie "$TMP/cookie" 10000 user_name
set +e
run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^missing\t0\t0\tlocal$' "$TMP/out"

run_status --invalidate
[[ ! -e $TMP/cache ]]

printf 'midway status tests passed\n'
