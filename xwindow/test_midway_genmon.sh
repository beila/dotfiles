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

write_cookie "$TMP/valid" 33400 __Host-session
valid=$(MIDWAY_COOKIE_FILE="$TMP/valid" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $valid == *"#50fa7b"* ]]
[[ $valid == *"Midway session valid"* ]]
[[ $valid == *"Remaining: 9h 0m"* ]]

write_cookie "$TMP/eight-hours" 29800
eight_hours=$(MIDWAY_COOKIE_FILE="$TMP/eight-hours" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $eight_hours == *"#50fa7b"* ]]
[[ $eight_hours == *"Remaining: 8h 0m"* ]]

write_cookie "$TMP/expiring" 29799
expiring=$(MIDWAY_COOKIE_FILE="$TMP/expiring" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $expiring == *"#F8BB3D"* ]]
[[ $expiring == *"Midway session valid"* ]]
[[ $expiring == *"Remaining: 7h 59m"* ]]

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
