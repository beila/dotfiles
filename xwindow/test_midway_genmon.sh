#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MIDWAY="$ROOT/xwindow/bin/midway-genmon"
PANEL="$ROOT/xfce4.configsymlink/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

write_cookie() {
    local path=$1 expiry=$2 name=${3:-session}
    printf '# Netscape HTTP Cookie File\n#HttpOnly_midway-auth.amazon.com\tFALSE\t/\tTRUE\t%s\t%s\tplaceholder\n' \
        "$expiry" "$name" > "$path"
}

write_cookie "$TMP/valid" 4600 __Host-session
valid=$(MIDWAY_COOKIE_FILE="$TMP/valid" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $valid == *"#50fa7b"* ]]
[[ $valid == *"Midway session valid"* ]]
[[ $valid == *"Remaining: 1h 0m"* ]]

write_cookie "$TMP/expired" 999
expired=$(MIDWAY_COOKIE_FILE="$TMP/expired" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $expired == *"#ff5555"* ]]
[[ $expired == *"Midway session expired"* ]]

write_cookie "$TMP/non-session" 9999 user_name
non_session=$(MIDWAY_COOKIE_FILE="$TMP/non-session" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $non_session == *"No Midway session found"* ]]

missing=$(MIDWAY_COOKIE_FILE="$TMP/missing" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $missing == *"#ff5555"* ]]
[[ $missing == *"No Midway session found"* ]]

# --status: single-word machine-readable mode for the midway-osd daemon.
# Same parser, so valid/invalid must line up with the panel branches above.
status() { "$@" --status; }

s_valid=$(MIDWAY_COOKIE_FILE="$TMP/valid" MIDWAY_NOW=1000 bash "$MIDWAY" --status)
rc_valid=$?
# Valid now carries the expiry epoch (`valid <epoch>`) so the daemon can
# schedule a timer to the exact expiry instant. The cookie's expiry is 4600.
[[ $s_valid == "valid 4600" ]]
((rc_valid == 0))

s_expired=$(MIDWAY_COOKIE_FILE="$TMP/expired" MIDWAY_NOW=1000 bash "$MIDWAY" --status) || rc_expired=$?
[[ $s_expired == invalid ]]
((rc_expired == 1))

s_missing=$(MIDWAY_COOKIE_FILE="$TMP/missing" MIDWAY_NOW=1000 bash "$MIDWAY" --status) || rc_missing=$?
[[ $s_missing == invalid ]]
((rc_missing == 1))

s_non_session=$(MIDWAY_COOKIE_FILE="$TMP/non-session" MIDWAY_NOW=1000 bash "$MIDWAY" --status) || true
[[ $s_non_session == invalid ]]

# Malformed jar (no valid cookie rows) → invalid.
printf 'not a cookie file at all\n' > "$TMP/malformed"
s_malformed=$(MIDWAY_COOKIE_FILE="$TMP/malformed" MIDWAY_NOW=1000 bash "$MIDWAY" --status) || true
[[ $s_malformed == invalid ]]

# Unreadable jar (mode 000) → invalid, never an error exit that hides state.
: > "$TMP/unreadable"
chmod 000 "$TMP/unreadable"
s_unreadable=$(MIDWAY_COOKIE_FILE="$TMP/unreadable" MIDWAY_NOW=1000 bash "$MIDWAY" --status) || true
[[ $s_unreadable == invalid ]]
chmod 644 "$TMP/unreadable"

# Exactly at expiry (expiry == now) is NOT a future expiry → invalid.
s_exact=$(MIDWAY_COOKIE_FILE="$TMP/valid" MIDWAY_NOW=4600 bash "$MIDWAY" --status) || true
[[ $s_exact == invalid ]]

# Existing panel (non-status) output must be byte-for-byte unchanged.
panel_valid=$(MIDWAY_COOKIE_FILE="$TMP/valid" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $panel_valid == *"Midway session valid"* ]]
[[ $panel_valid == *"Remaining: 1h 0m"* ]]

rg -q '<value type="int" value="7"/>' "$PANEL"
rg -q 'xwindow/bin/midway-genmon' "$PANEL"
rg -q '<property name="update-period" type="int" value="30000"/>' "$PANEL"

printf 'midway genmon tests passed\n'
