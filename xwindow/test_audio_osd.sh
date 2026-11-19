#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d /tmp/audio-osd-test.XXXXXX)
worker_pid=

cleanup() {
	if [[ -n $worker_pid ]]; then
		kill "$worker_pid" 2>/dev/null || true
		wait "$worker_pid" 2>/dev/null || true
	fi
	rm -rf "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/bin" "$test_dir/scripts"
for script in volume-osd cycle-audio-input cycle-audio-output; do
	sed "s|/tmp/|$test_dir/|g" "$root/xwindow/bin/$script" >"$test_dir/scripts/$script"
done

cat >"$test_dir/bin/amixer" <<'EOF'
#!/usr/bin/env bash
if [[ ${OSD_TEST_HANG:-0} == 1 ]]; then
	exec sleep 30
fi
printf '  Front Left: Playback 32768 [50%%] [on]\n'
EOF

cat >"$test_dir/bin/wpctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${OSD_TEST_HANG:-0} == 1 ]]; then
	exec sleep 30
fi
[[ $1 == status ]] || exit 0
cat <<'STATUS'
Audio
 ├─ Sinks:
 │  *   33. Speakers [vol: 0.50]
 ├─ Sink endpoints:
 ├─ Sources:
 │  *   44. Microphone [vol: 1.00]
 ├─ Source endpoints:
STATUS
EOF

cat >"$test_dir/bin/dzen2" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$OSD_TEST_VIEWER_PID"
trap 'rm -f "$OSD_TEST_VIEWER_PID"; exit 0' TERM INT
while IFS= read -r line; do
	printf '%s\n' "$line" >>"$OSD_TEST_TEXT"
done
EOF

cat >"$test_dir/bin/xrdb" <<'EOF'
#!/usr/bin/env bash
printf 'Xft.dpi:\t96\n'
EOF

cat >"$test_dir/bin/osd-click-through" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_dir/bin/"*

export PATH="$test_dir/bin:$PATH"
export OSD_TEST_VIEWER_PID="$test_dir/viewer.pid"
export OSD_TEST_TEXT="$test_dir/text"

for script in volume-osd cycle-audio-input cycle-audio-output; do
	rm -f "$OSD_TEST_VIEWER_PID"
	OSD_TEST_HANG=1 timeout --kill-after=1 8 bash "$test_dir/scripts/$script" up \
		>"$test_dir/command.log" 2>&1 &
	worker_pid=$!
	for _ in $(seq 1 45); do
		kill -0 "$worker_pid" 2>/dev/null || break
		sleep 0.1
	done
	if [[ -f $OSD_TEST_VIEWER_PID ]] && kill -0 "$(cat "$OSD_TEST_VIEWER_PID")" 2>/dev/null; then
		printf 'FAIL: %s leaves its overlay visible when the audio query hangs\n' "$script" >&2
		exit 1
	fi
	if kill -0 "$worker_pid" 2>/dev/null; then
		printf 'FAIL: %s waits indefinitely for the audio command\n' "$script" >&2
		exit 1
	fi
	wait "$worker_pid" 2>/dev/null || true
	worker_pid=
	printf 'PASS: %s bounds failed audio commands and leaves no overlay\n' "$script"
done

printf 'audio OSD stall tests passed\n'
