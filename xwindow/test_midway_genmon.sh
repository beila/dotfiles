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

rg -q '<value type="int" value="7"/>' "$PANEL"
rg -q 'xwindow/bin/midway-genmon' "$PANEL"
rg -q '<property name="update-period" type="int" value="30000"/>' "$PANEL"

printf 'midway genmon tests passed\n'
