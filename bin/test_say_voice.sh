#!/usr/bin/env bash
# Test the shared deterministic mapping, numbered selection, speed parsing,
# backend option wiring, and say's SAY_VOICE_KEY propagation.
# Run: bash bin/test_say_voice.sh

set -uo pipefail
pass=0 fail=0
assert_eq() {
    if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1"; echo "    expected: $3"; echo "    got: $2"; ((fail++)); fi
}
assert_true() {
    if eval "$2"; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1: $2"; ((fail++)); fi
}
assert_fails() {
    if eval "$2"; then echo "  ✗ $1: command succeeded"; ((fail++)); else echo "  ✓ $1"; ((pass++)); fi
}
assert_file_contains() {
    if rg -q --fixed-strings -- "$2" "$3"; then
        echo "  ✓ $1"
        ((pass++))
    else
        echo "  ✗ $1"
        echo "    missing: $2"
        echo "    file: $(cat "$3")"
        ((fail++))
    fi
}

dotfiles="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d /tmp/test_say_voice.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

# Source the real shared helper so the tests exercise the production mapping.
source "$dotfiles/bin/say-voice.sh"

echo "== say-voice.sh: key contract =="

i1=$(SAY_VOICE_KEY="session-abc" say_pick_index 3)
i2=$(SAY_VOICE_KEY="session-abc" say_pick_index 3)
assert_eq "same key → same index" "$i1" "$i2"

# "1" remains an opaque hash key unless supplied as the explicit second arg.
expect_one=$(( 0x$(printf '%s' 1 | sha256sum | cut -c1-15) % 3 ))
got_one=$(SAY_VOICE_KEY=1 say_pick_index 3)
assert_eq "SAY_VOICE_KEY=1 is hashed" "$got_one" "$expect_one"

assert_eq "empty SAY_VOICE_KEY → default index 0" "$(SAY_VOICE_KEY='' say_pick_index 3)" "0"
assert_eq "empty SAY_VOICE_KEY → resolver empty" "$(SAY_VOICE_KEY='' say_resolve_key)" ""

key_unset=$(unset SAY_VOICE_KEY; say_resolve_key)
assert_true "unset SAY_VOICE_KEY → resolver is a PPID number ($key_unset)" "[[ '$key_unset' =~ ^[0-9]+$ ]]"

seen=$(for k in a b c d e f g h; do SAY_VOICE_KEY="$k" say_pick_index 3; echo; done | sort -u | wc -l)
assert_true "distinct keys spread across pool (>1 index seen)" "[ $seen -gt 1 ]"

echo "== numbered selection and common options =="
assert_eq "voice 1 → index 0" "$(say_pick_index 7 1)" "0"
assert_eq "voice 7 → index 6" "$(say_pick_index 7 7)" "6"
assert_fails "voice 0 is rejected" "say_pick_index 7 0 >/dev/null 2>&1"
assert_fails "voice 8 is rejected" "say_pick_index 7 8 >/dev/null 2>&1"
assert_fails "non-numeric voice is rejected" "say_pick_index 7 random >/dev/null 2>&1"

say_parse_options --voice=3 --speed 25 "hola mundo"
assert_eq "--voice parses" "$SAY_CLI_VOICE_NUMBER" "3"
assert_eq "--speed parses" "$SAY_CLI_SPEED" "25"
assert_eq "text remains positional" "${SAY_CLI_TEXT_ARGS[*]}" "hola mundo"
assert_eq "unsigned speed normalizes positive" "$(say_normalize_speed 25)" "+25%"
assert_eq "signed negative speed is retained" "$(say_normalize_speed -10%)" "-10%"
assert_fails "invalid speed is rejected" "say_normalize_speed fast >/dev/null 2>&1"

echo "== backend command wiring (stubbed playback) =="
mkdir -p "$tmp/fake-bin"
cat >"$tmp/fake-bin/uv" <<'EOF_UV'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${SAY_TEST_EDGE_ARGS:-$SAY_TEST_ARGS}"
[ "${SAY_TEST_EDGE_FAIL:-0}" = 1 ] && exit 1
while [ "$#" -gt 0 ]; do
    if [ "$1" = --write-media ]; then
        : >"$2"
        break
    fi
    shift
done
EOF_UV
cat >"$tmp/fake-bin/ffmpeg" <<'EOF_FFMPEG'
#!/usr/bin/env bash
exit 0
EOF_FFMPEG
cat >"$tmp/fake-bin/aplay" <<'EOF_APLAY'
#!/usr/bin/env bash
cat >/dev/null
EOF_APLAY
cat >"$tmp/fake-bin/piper" <<'EOF_PIPER'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${SAY_TEST_PIPER_ARGS:-$SAY_TEST_ARGS}"
cat >/dev/null
EOF_PIPER
chmod +x "$tmp/fake-bin"/*

edge_args="$tmp/edge-args"
PATH="$tmp/fake-bin:$PATH" SAY_TEST_ARGS="$edge_args" \
    "$dotfiles/bin/say-es" --voice 7 --speed 25 "hola mundo"
assert_file_contains "say-es voice 7 selects Paloma" "--voice es-US-PalomaNeural" "$edge_args"
assert_file_contains "say-es numeric speed becomes +25%" "--rate=+25%" "$edge_args"

PATH="$tmp/fake-bin:$PATH" SAY_TEST_ARGS="$edge_args" EDGE_TTS_VOICE=custom-Korean \
    "$dotfiles/bin/say-ko" --speed -10% "test"
assert_file_contains "say-ko retains EDGE_TTS_VOICE override" "--voice custom-Korean" "$edge_args"
assert_file_contains "say-ko passes negative speed" "--rate=-10%" "$edge_args"

mkdir -p "$tmp/home/.local/share/piper"
: >"$tmp/home/.local/share/piper/en_US-ryan-high.onnx"
edge_en_args="$tmp/edge-en-args"
piper_args="$tmp/piper-args"
HOME="$tmp/home" PATH="$tmp/fake-bin:$PATH" SAY_TEST_EDGE_ARGS="$edge_en_args" \
    SAY_TEST_PIPER_ARGS="$piper_args" \
    "$dotfiles/bin/say-en" --voice 3 --speed +50% "hello"
assert_file_contains "say-en voice 3 selects Andrew on Edge" \
    "--voice en-US-AndrewMultilingualNeural" "$edge_en_args"
assert_file_contains "say-en passes +50% to Edge" "--rate=+50%" "$edge_en_args"
assert_true "say-en does not invoke Piper after Edge succeeds" "[ ! -e '$piper_args' ]"

HOME="$tmp/home" PATH="$tmp/fake-bin:$PATH" SAY_TEST_EDGE_ARGS="$edge_en_args" \
    SAY_TEST_PIPER_ARGS="$piper_args" SAY_TEST_EDGE_FAIL=1 \
    "$dotfiles/bin/say-en" --voice 3 --speed +50% "hello" >/dev/null 2>&1
assert_file_contains "say-en Edge failure falls back to numbered Piper voice" \
    "en_US-ryan-high.onnx" "$piper_args"
assert_file_contains "say-en converts fallback +50% to Piper length scale" \
    "--length-scale 0.666667" "$piper_args"

custom_model="$tmp/home/custom.onnx"
: >"$custom_model"
rm -f "$edge_en_args"
HOME="$tmp/home" PATH="$tmp/fake-bin:$PATH" SAY_TEST_EDGE_ARGS="$edge_en_args" \
    SAY_TEST_PIPER_ARGS="$piper_args" PIPER_MODEL="$custom_model" \
    "$dotfiles/bin/say-en" "hello"
assert_file_contains "PIPER_MODEL retains the explicit Piper path" "$custom_model" "$piper_args"
assert_true "PIPER_MODEL bypasses Edge" "[ ! -e '$edge_en_args' ]"

assert_fails "say-es rejects an out-of-range voice before playback" \
    "'$dotfiles/bin/say-es' --voice 8 hola >/dev/null 2>&1"
assert_true "say-es is executable" "[ -x '$dotfiles/bin/say-es' ]"

echo "== say: resolves + exports SAY_VOICE_KEY to backend =="

# Stage a fake DOTFILES_ROOT whose backends echo the inherited key. Copy the
# real say-voice.sh alongside so say's source resolves normally.
mkdir -p "$tmp/root/bin"
cp "$dotfiles/bin/say" "$tmp/root/bin/say"
cp "$dotfiles/bin/say-voice.sh" "$tmp/root/bin/say-voice.sh"
cat >"$tmp/root/bin/say-en" <<'EOF_BACKEND'
#!/usr/bin/env bash
printf 'KEY=%s\n' "${SAY_VOICE_KEY-UNSET}" >"$SAY_TEST_OUT"
EOF_BACKEND
cp "$tmp/root/bin/say-en" "$tmp/root/bin/say-ko"
chmod +x "$tmp/root/bin"/say-*

out="$tmp/out"
SAY_TEST_OUT="$out" DOTFILES_ROOT="$tmp/root" SAY_NO_PREEMPT=1 SAY_NO_MEETING_CHECK=1 \
    SAY_VOICE_KEY="explicit-key" "$tmp/root/bin/say" "hello world" >/dev/null 2>&1
assert_eq "explicit SAY_VOICE_KEY propagates to backend" "$(cat "$out")" "KEY=explicit-key"

SAY_TEST_OUT="$out" DOTFILES_ROOT="$tmp/root" SAY_NO_PREEMPT=1 SAY_NO_MEETING_CHECK=1 \
    "$tmp/root/bin/say" "hello world" >/dev/null 2>&1
got=$(cat "$out")
assert_true "default key is a non-empty PPID number ($got)" "[[ '$got' =~ ^KEY=[0-9]+$ ]]"

echo
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
