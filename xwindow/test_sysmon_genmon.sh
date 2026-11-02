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

# Free space in KiB for each filesystem that df reports.
cat > "$TMP/bin/df" <<'MOCK'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/root 100000000 1 %s 1%% /\n' "${SYSMON_TEST_DISK_FREE_KB:-50000000}"
printf '/dev/home 100000000 1 50000000 1%% /home\n'
MOCK
chmod +x "$TMP/bin/df"

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

# Disk space: the graph appears only while free space is below 1 GiB.
plenty=$(run_sample full disk-plenty)
[[ $plenty != *"🗄️"* ]]
[[ $plenty == *"Disk: 47G free"* ]]
SYSMON_TEST_DISK_FREE_KB=$(( 1200 * 1024 )) run_sample full disk-edge >/dev/null
edge=$(SYSMON_TEST_DISK_FREE_KB=$(( 1200 * 1024 )) run_sample full disk-edge)
[[ $edge != *"🗄️"* ]]
SYSMON_TEST_DISK_FREE_KB=$(( 3 * 1024 * 1024 )) run_sample full disk-low >/dev/null
low=$(SYSMON_TEST_DISK_FREE_KB=$(( 1023 * 1024 )) run_sample full disk-low)
[[ $low == *"🗄️"* ]]
# The newest cell pairs the yellow 3 GiB sample with the red one, and shows red.
disk_part=${low##*🗄️}
[[ $disk_part == *"<span color='#ff5555'>"* ]]
recovered_disk=$(SYSMON_TEST_DISK_FREE_KB=$(( 2 * 1024 * 1024 )) run_sample full disk-low)
[[ $recovered_disk != *"🗄️"* ]]

printf 'sysmon connectivity and disk tests passed\n'
