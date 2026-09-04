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
[[ $online != *"#ff79c6"* ]]

for state in limited portal none; do
    offline=$(run_sample "$state" "offline-$state")
    [[ $offline == *"Net:  offline ($state)"* ]]
    [[ $offline == *"#ff79c6"* ]]
    [[ $offline == *"<span color='#ff79c6'>⢈</span>"* ]]
done

run_sample limited paired >/dev/null
paired=$(run_sample limited paired)
[[ $paired == *"<span color='#ff79c6'>⣉</span>"* ]]

unknown=$(run_sample unknown unknown)
[[ $unknown == *"Net:  unknown"* ]]
[[ $unknown != *"#ff79c6"* ]]

run_sample full transient >/dev/null
run_sample limited transient >/dev/null
recovered=$(run_sample full transient)
[[ $recovered == *"Net:  online"* ]]
[[ $recovered == *"#ff79c6"* ]]

printf 'sysmon connectivity tests passed\n'
