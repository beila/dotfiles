#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MIDWAY="$ROOT/xwindow/bin/midway-genmon"
PANEL="$ROOT/xfce4.configsymlink/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

write_status() {
    local path=$1 status=$2 expiry=$3 checked_at=${4:-1000} reason=${5:-server}
    local aea_expiry=${6:-7000}
    printf '#!/usr/bin/env bash\nprintf "%%s\\\\t%%s\\\\t%%s\\\\t%%s\\\\t%%s\\\\n" %q %q %q %q %q\n' \
        "$status" "$expiry" "$checked_at" "$reason" "$aea_expiry" > "$path"
    chmod +x "$path"
}

write_status "$TMP/valid" valid 33400
valid=$(MIDWAY_STATUS_COMMAND="$TMP/valid" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $valid == *"#50fa7b"* ]]
[[ $valid == *"Midway and AEA verified"* ]]
[[ $valid == *"Midway remaining: 9h 0m"* ]]
[[ $valid == *"AEA remaining: 1h 40m"* ]]

write_status "$TMP/eight-hours" valid 29800
eight_hours=$(MIDWAY_STATUS_COMMAND="$TMP/eight-hours" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $eight_hours == *"#50fa7b"* ]]
[[ $eight_hours == *"Midway remaining: 8h 0m"* ]]

write_status "$TMP/expiring" valid 29799
expiring=$(MIDWAY_STATUS_COMMAND="$TMP/expiring" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $expiring == *"#F8BB3D"* ]]
[[ $expiring == *"Midway and AEA verified"* ]]
[[ $expiring == *"Midway remaining: 7h 59m"* ]]

write_status "$TMP/two-hours" valid 8200
two_hours=$(MIDWAY_STATUS_COMMAND="$TMP/two-hours" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $two_hours == *"#F8BB3D"* ]]
[[ $two_hours == *"Midway and AEA verified"* ]]
[[ $two_hours == *"Midway remaining: 2h 0m"* ]]

write_status "$TMP/critical" valid 8199
critical=$(MIDWAY_STATUS_COMMAND="$TMP/critical" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $critical == *"#ff5555"* ]]
[[ $critical == *"Midway and AEA verified"* ]]
[[ $critical == *"Midway remaining: 1h 59m"* ]]

write_status "$TMP/aea-expired" invalid 33400 1000 aea-cookie 999
aea_expired=$(MIDWAY_STATUS_COMMAND="$TMP/aea-expired" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $aea_expired == *"#50fa7b"* ]]
[[ $aea_expired != *"#ff5555"* ]]
[[ $aea_expired == *"AEA cookie expired"* ]]
[[ $aea_expired == *"Midway remaining: 9h 0m"* ]]
[[ $aea_expired == *"Run mwinit to authenticate."* ]]

write_status "$TMP/aea-missing" invalid 33400 1000 aea-missing 0
aea_missing=$(MIDWAY_STATUS_COMMAND="$TMP/aea-missing" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $aea_missing == *"#50fa7b"* ]]
[[ $aea_missing == *"No AEA cookie found"* ]]
[[ $aea_missing == *"Midway remaining: 9h 0m"* ]]

write_status "$TMP/aea-posture" invalid 33400 1000 aea-posture 7000
aea_posture=$(MIDWAY_STATUS_COMMAND="$TMP/aea-posture" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $aea_posture == *"#50fa7b"* ]]
[[ $aea_posture == *"AEA posture rejected"* ]]
[[ $aea_posture == *"Midway remaining: 9h 0m"* ]]

write_status "$TMP/aea-expired-midway-expiring" invalid 29799 1000 aea-cookie 999
aea_expired_midway_expiring=$(
    MIDWAY_STATUS_COMMAND="$TMP/aea-expired-midway-expiring" \
        MIDWAY_NOW=1000 bash "$MIDWAY"
)
[[ $aea_expired_midway_expiring == *"#F8BB3D"* ]]
[[ $aea_expired_midway_expiring == *"AEA cookie expired"* ]]

write_status "$TMP/invalid" invalid 33400 1000 server
invalid=$(MIDWAY_STATUS_COMMAND="$TMP/invalid" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $invalid == *"#ff5555"* ]]
[[ $invalid == *"Midway session rejected by server"* ]]
[[ $invalid == *"Cookie expires:"* ]]

write_status "$TMP/unknown" unknown 33400 1000 network
unknown=$(MIDWAY_STATUS_COMMAND="$TMP/unknown" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $unknown == *"#ff79c6"* ]]
[[ $unknown == *"Midway verification unavailable"* ]]
[[ $unknown == *"Local expiry is not proof of authentication."* ]]

write_status "$TMP/expired" expired 999 0 local
expired=$(MIDWAY_STATUS_COMMAND="$TMP/expired" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $expired == *"#ff5555"* ]]
[[ $expired == *"Midway session expired"* ]]

write_status "$TMP/missing" missing 0 0 local
missing=$(MIDWAY_STATUS_COMMAND="$TMP/missing" MIDWAY_NOW=1000 bash "$MIDWAY")
[[ $missing == *"#ff5555"* ]]
[[ $missing == *"No Midway session found"* ]]

rg -q '<value type="int" value="7"/>' "$PANEL"
rg -q 'xwindow/bin/midway-genmon' "$PANEL"
rg -q '<property name="update-period" type="int" value="30000"/>' "$PANEL"

printf 'midway genmon tests passed\n'
