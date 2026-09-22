#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATUS="$ROOT/bin/midway-status"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

write_cookie() {
    local path=$1 session_expiry=$2 aea_expiry=${3:-9000} name=${4:-session}
    printf '# Netscape HTTP Cookie File\n' > "$path"
    printf '#HttpOnly_midway-auth.amazon.com\tFALSE\t/\tTRUE\t%s\t%s\tplaceholder\n' \
        "$session_expiry" "$name" >> "$path"
    printf '#HttpOnly_.midway-auth.amazon.com\tFALSE\t/\tTRUE\t%s\tamazon_enterprise_access\tplaceholder\n' \
        "$aea_expiry" >> "$path"
}

cat > "$TMP/curl" <<'EOF'
#!/usr/bin/env bash
printf x >> "$MIDWAY_TEST_CALLS"
printf '%s\n' "$MIDWAY_TEST_RESPONSE"
exit "${MIDWAY_TEST_CURL_EXIT:-0}"
EOF
chmod +x "$TMP/curl"

cat > "$TMP/mcscli" <<'EOF'
#!/usr/bin/env bash
printf x >> "$MIDWAY_TEST_MCS_CALLS"
printf '{"is_valid":%s,"expiration_time":%s}\n' \
    "${MIDWAY_TEST_AEA_VALID:-true}" "${MIDWAY_TEST_POSTURE_EXPIRY:-9000}"
[[ ${MIDWAY_TEST_AEA_VALID:-true} == true ]]
EOF
chmod +x "$TMP/mcscli"

run_status() {
    MIDWAY_COOKIE_FILE="$TMP/cookie" \
    MIDWAY_STATUS_CACHE_FILE="$TMP/cache" \
    MIDWAY_STATUS_CURL="$TMP/curl" \
    MIDWAY_STATUS_MCSCLI="$TMP/mcscli" \
    MIDWAY_TEST_CALLS="$TMP/calls" \
    MIDWAY_TEST_MCS_CALLS="$TMP/mcs-calls" \
    MIDWAY_TEST_RESPONSE="${MIDWAY_TEST_RESPONSE-}" \
    MIDWAY_TEST_CURL_EXIT="${MIDWAY_TEST_CURL_EXIT:-0}" \
    MIDWAY_TEST_AEA_VALID="${MIDWAY_TEST_AEA_VALID:-true}" \
    MIDWAY_TEST_POSTURE_EXPIRY="${MIDWAY_TEST_POSTURE_EXPIRY:-9000}" \
    MIDWAY_NOW="${MIDWAY_NOW:-1000}" \
        "$STATUS" "$@"
}

write_cookie "$TMP/cookie" 10000
MIDWAY_TEST_RESPONSE='{"authenticated":true}' run_status --refresh > "$TMP/out"
rg -q $'^valid\t10000\t1000\tserver\t9000$' "$TMP/out"

MIDWAY_TEST_RESPONSE='{"authenticated":false}' run_status > "$TMP/out"
rg -q $'^valid\t10000\t1000\tserver\t9000$' "$TMP/out"
[[ $(wc -c < "$TMP/calls") == 1 ]]
[[ $(wc -c < "$TMP/mcs-calls") == 1 ]]

set +e
MIDWAY_TEST_RESPONSE='{"authenticated":false}' run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^invalid\t10000\t1000\tserver\t9000$' "$TMP/out"

set +e
MIDWAY_TEST_CURL_EXIT=7 run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 2 ]]
rg -q $'^unknown\t10000\t1000\tnetwork\t9000$' "$TMP/out"

set +e
MIDWAY_TEST_AEA_VALID=false MIDWAY_TEST_POSTURE_EXPIRY=999 \
    MIDWAY_TEST_RESPONSE='{"authenticated":true}' run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^invalid\t10000\t1000\taea-posture\t9000$' "$TMP/out"

write_cookie "$TMP/cookie" 10000 999
set +e
MIDWAY_TEST_AEA_VALID=true MIDWAY_TEST_POSTURE_EXPIRY=9000 \
    MIDWAY_TEST_RESPONSE='{"authenticated":true}' run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^invalid\t10000\t1000\taea-cookie\t999$' "$TMP/out"

write_cookie "$TMP/cookie" 999
set +e
MIDWAY_TEST_RESPONSE='{"authenticated":true}' run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^expired\t999\t0\tlocal\t9000$' "$TMP/out"

write_cookie "$TMP/cookie" 10000 9000 user_name
set +e
run_status --refresh > "$TMP/out"
status=$?
set -e
[[ $status == 1 ]]
rg -q $'^missing\t0\t0\tlocal\t9000$' "$TMP/out"

run_status --invalidate
[[ ! -e $TMP/cache ]]

printf 'midway status tests passed\n'
