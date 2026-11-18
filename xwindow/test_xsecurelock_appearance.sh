#!/usr/bin/env bash
set -euo pipefail

locker=${1:-$(command -v xsecurelock)}
test_dir=$(mktemp -d /tmp/xsecurelock-appearance-test.XXXXXX)
locker_pid=
server_pid=

cleanup() {
	for pid in "$locker_pid" "$server_pid"; do
		if [[ -n $pid ]]; then
			kill "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
		fi
	done
	rm -rf "$test_dir"
}
trap cleanup EXIT

for candidate in $(seq 90 110); do
	if [[ ! -e /tmp/.X"$candidate"-lock && ! -S /tmp/.X11-unix/X"$candidate" ]]; then
		nested_display=:$candidate
		break
	fi
done
[[ -n ${nested_display:-} ]]

Xephyr "$nested_display" -screen 1000x700 -nolisten tcp -noreset \
	>"$test_dir/server.log" 2>&1 &
server_pid=$!
export DISPLAY=$nested_display
for _ in $(seq 1 50); do
	xdpyinfo >/dev/null 2>&1 && break
	sleep 0.1
done
xdpyinfo >/dev/null

cat >"$test_dir/authproto" <<'EOF'
#!/usr/bin/env bash
printf 'P 9\nPassword:\n'
IFS= read -r header
IFS= read -r response
[[ $header == 'p 13' && $response == 'test-password' ]]
EOF
chmod +x "$test_dir/authproto"
convert -size 1000x700 xc:white "$test_dir/wallpaper.png"
convert -size 200x700 xc:red "$test_dir/portrait.png"

export XSECURELOCK_USERNAME=appearance-test
export XSECURELOCK_AUTHPROTO="$test_dir/authproto"
export XSECURELOCK_SAVER=saver_blank
export XSECURELOCK_NO_COMPOSITE=1
export XSECURELOCK_BURNIN_MITIGATION=0
export XSECURELOCK_AUTH_BACKGROUND_OPACITY=65
export XSECURELOCK_AUTH_X_PERCENT=50
export XSECURELOCK_AUTH_Y_PERCENT=80
export XSECURELOCK_AUTH_BACKGROUND_COLOR=black
export XSECURELOCK_AUTH_FOREGROUND_COLOR=white

start_locker() {
	export XSECURELOCK_AUTH_BACKGROUND_IMAGE=$1
	rm -f "$test_dir/locked"
	"$locker" -- touch "$test_dir/locked" >"$test_dir/locker.log" 2>&1 &
	locker_pid=$!
	for _ in $(seq 1 50); do
		if [[ -f $test_dir/locked ]]; then
			break
		fi
		sleep 0.1
	done
	[[ -f $test_dir/locked ]] || {
		cat "$test_dir/locker.log" >&2
		return 1
	}
	xdotool key Return
	auth_window=$(timeout 5 xdotool search --sync --onlyvisible --name '^auth$' | head -n 1)
	sleep 0.2
	import -window "$auth_window" "$test_dir/dialog.png"
}

stop_locker() {
	kill "$locker_pid"
	wait "$locker_pid" 2>/dev/null || true
	locker_pid=
}

assert_pixel() {
	local x=$1 y=$2 expected=$3 actual
	actual=$(convert "$test_dir/dialog.png" -format "%[pixel:p{$x,$y}]" info:)
	[[ $actual == "$expected" ]] || {
		printf 'unexpected pixel at %s,%s: %s (expected %s)\n' "$x" "$y" "$actual" "$expected" >&2
		exit 1
	}
}

start_locker "$test_dir/wallpaper.png"
geometry=$(xdotool getwindowgeometry --shell "$auth_window")
x=$(sed -n 's/^X=//p' <<<"$geometry")
y=$(sed -n 's/^Y=//p' <<<"$geometry")
width=$(sed -n 's/^WIDTH=//p' <<<"$geometry")
height=$(sed -n 's/^HEIGHT=//p' <<<"$geometry")
[[ $x == $(((1000 - width) / 2)) ]]
[[ $y == $(((700 - height) * 80 / 100)) ]]
assert_pixel 2 2 'srgb(89,89,89)'
[[ $(convert "$test_dir/dialog.png" -format '%[fx:maxima]' info:) == 1 ]]

xdotool type --clearmodifiers wrong
xdotool key Return
for _ in $(seq 1 50); do
	xdotool search --onlyvisible --name '^auth$' >/dev/null 2>&1 || break
	sleep 0.1
done
if xdotool search --onlyvisible --name '^auth$' >/dev/null 2>&1; then
	cat "$test_dir/locker.log" >&2
	printf 'failed password dialog did not close\n' >&2
	exit 1
fi
kill -0 "$locker_pid"
sleep 0.1
xdotool key Return
timeout 5 xdotool search --sync --onlyvisible --name '^auth$' >/dev/null
xdotool type --clearmodifiers test-password
xdotool key Return
for _ in $(seq 1 50); do
	kill -0 "$locker_pid" 2>/dev/null || break
	sleep 0.1
done
if kill -0 "$locker_pid" 2>/dev/null; then
	cat "$test_dir/locker.log" >&2
	printf 'correct password did not unlock\n' >&2
	exit 1
fi
wait "$locker_pid"
locker_pid=

start_locker "$test_dir/missing.png"
assert_pixel 2 2 'srgb(0,0,0)'
stop_locker

start_locker "$test_dir/portrait.png"
assert_pixel 2 2 'srgb(0,0,0)'
assert_pixel "$((width / 2))" 2 'srgb(89,0,0)'
stop_locker

printf 'xsecurelock appearance and authentication tests passed\n'
