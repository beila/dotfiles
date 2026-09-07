#!/usr/bin/env bash
# Test meeting suppression for the dispatcher and direct language backends.

set -uo pipefail
pass=0 fail=0

assert_exists() {
    if [ -e "$2" ]; then
        echo "  ✓ $1"
        ((pass++))
    else
        echo "  ✗ $1"
        ((fail++))
    fi
}

assert_missing() {
    if [ ! -e "$2" ]; then
        echo "  ✓ $1"
        ((pass++))
    else
        echo "  ✗ $1"
        ((fail++))
    fi
}

dotfiles="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d /tmp/test_say_meeting.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/fake-bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/pw-dump" <<'EOF_PW_DUMP'
#!/usr/bin/env bash
case "${PW_DUMP_MODE:-zoom}" in
    zoom)
        printf '%s\n' '[{"info":{"props":{"media.class":"Stream/Input/Audio","application.process.binary":"zoom","application.name":"ZOOM VoiceEngine"}}}]'
        ;;
    node)
        printf '%s\n' '[{"info":{"props":{"media.class":"Stream/Input/Audio","node.name":"zoom-capture"}}}]'
        ;;
    *)
        printf '%s\n' '[]'
        ;;
esac
EOF_PW_DUMP

dispatcher_root="$tmp/dispatcher"
mkdir -p "$dispatcher_root/bin"
cp "$dotfiles/bin/say" "$dispatcher_root/bin/say"
cp "$dotfiles/bin/say-voice.sh" "$dispatcher_root/bin/say-voice.sh"
cat >"$dispatcher_root/bin/say-en" <<'EOF_BACKEND'
#!/usr/bin/env bash
printf '%s\n' invoked >"$SAY_TEST_MARKER"
EOF_BACKEND
cp "$dispatcher_root/bin/say-en" "$dispatcher_root/bin/say-ko"

backend_root="$tmp/backend"
mkdir -p "$backend_root/bin"
cp "$dotfiles/bin/say-ko" "$backend_root/bin/say-ko"
cp "$dotfiles/bin/say-voice.sh" "$backend_root/bin/say-voice.sh"
cat >"$fake_bin/uv" <<'EOF_UV'
#!/usr/bin/env bash
printf '%s\n' invoked >"$SAY_TEST_MARKER"
while [ "$#" -gt 0 ]; do
    if [ "$1" = "--write-media" ]; then
        : >"$2"
        break
    fi
    shift
done
EOF_UV
cat >"$fake_bin/ffmpeg" <<'EOF_FFMPEG'
#!/usr/bin/env bash
exit 0
EOF_FFMPEG
cat >"$fake_bin/aplay" <<'EOF_APLAY'
#!/usr/bin/env bash
cat >/dev/null
EOF_APLAY
chmod +x "$fake_bin"/* "$dispatcher_root/bin"/* "$backend_root/bin"/*

marker="$tmp/marker"

echo "Test 1: say suppresses playback for Zoom"
PW_DUMP_MODE=zoom PATH="$fake_bin:$PATH" DOTFILES_ROOT="$dispatcher_root" \
    SAY_NO_PREEMPT=1 SAY_TEST_MARKER="$marker" \
    "$dispatcher_root/bin/say" "hello"
assert_missing "dispatcher backend was not invoked" "$marker"

echo "Test 2: say still plays when no meeting stream exists"
PW_DUMP_MODE=idle PATH="$fake_bin:$PATH" DOTFILES_ROOT="$dispatcher_root" \
    SAY_NO_PREEMPT=1 SAY_TEST_MARKER="$marker" \
    "$dispatcher_root/bin/say" "hello"
assert_exists "dispatcher backend was invoked" "$marker"
rm -f "$marker"

echo "Test 3: direct say-ko suppresses playback"
PW_DUMP_MODE=node PATH="$fake_bin:$PATH" SAY_TEST_MARKER="$marker" \
    "$backend_root/bin/say-ko" "테스트"
assert_missing "direct Korean backend did not invoke Edge TTS" "$marker"

echo "Test 4: explicit bypass still permits direct say-ko"
PW_DUMP_MODE=zoom PATH="$fake_bin:$PATH" SAY_NO_MEETING_CHECK=1 \
    SAY_TEST_MARKER="$marker" "$backend_root/bin/say-ko" "테스트"
assert_exists "bypass invoked Edge TTS" "$marker"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
