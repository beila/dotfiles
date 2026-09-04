#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SYSMON="$ROOT/xwindow/bin/sysmon-genmon"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/nmcli" <<'MOCK'
#!/usr/bin/env bash
cat "${SYSMON_TEST_CONNECTIVITY_FILE:?}"
MOCK
chmod +x "$TMP/bin/nmcli"

run_sample() {
    local state=$1 sequence=$2
    local state_dir="$TMP/$sequence"
    mkdir -p "$state_dir"
    printf '%s\n' "$state" > "$TMP/connectivity"
    PATH="$TMP/bin:$PATH" \
        SYSMON_TEST_CONNECTIVITY_FILE="$TMP/connectivity" \
        SYSMON_STATE_DIR="$state_dir" \
        SYSMON_HIST="$state_dir/history" \
        bash "$SYSMON"
}

online=$(run_sample full online)
[[ $online == *"Net:  online"* ]]
[[ $online != *"#ffb86c"* ]]

for state in limited portal none; do
    offline=$(run_sample "$state" "offline-$state")
    [[ $offline == *"Net:  offline ($state)"* ]]
    [[ $offline == *"#ffb86c"* ]]
    [[ $offline == *"<span color='#ffb86c'>⢀</span>"* ]]
done

unknown=$(run_sample unknown unknown)
[[ $unknown == *"Net:  unknown"* ]]
[[ $unknown != *"#ffb86c"* ]]

run_sample full transient >/dev/null
run_sample limited transient >/dev/null
recovered=$(run_sample full transient)
[[ $recovered == *"Net:  online"* ]]
[[ $recovered == *"#ffb86c"* ]]

printf 'sysmon connectivity tests passed\n'
