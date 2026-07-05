#!/usr/bin/env bash
# Test: the shared voice mapping (bin/say-voice.sh) is stable per caller key,
# treats the key as an opaque arbitrary string (honours "1" verbatim; only
# emptiness / PPID==1 means unidentified), spreads across the pool, and that
# bin/say resolves + exports SAY_VOICE_KEY down to the backend. Also checks the
# backends still honour their explicit voice overrides.
# Run: bash bin/test_say_voice.sh

set -uo pipefail
pass=0 fail=0
assert_eq() {
    if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1"; echo "    expected: $3"; echo "    got: $2"; ((fail++)); fi
}
assert_true() {
    if eval "$2"; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1: $2"; ((fail++)); fi
}

dotfiles="$(cd "$(dirname "$0")/.." && pwd)"

# Source the REAL shared helper so we test the actual mapping, not a copy.
source "$dotfiles/bin/say-voice.sh"

echo "== say-voice.sh: key contract =="

# Determinism: same explicit key → same index.
i1=$(SAY_VOICE_KEY="session-abc" say_pick_index 3)
i2=$(SAY_VOICE_KEY="session-abc" say_pick_index 3)
assert_eq "same key → same index" "$i1" "$i2"

# Opaque key: "1" is honoured verbatim, NOT treated as the setsid default.
# (Its hash mod 3 is deterministic; assert it equals the hash, not a forced 0.)
expect_one=$(( 0x$(printf '%s' 1 | sha256sum | cut -c1-15) % 3 ))
got_one=$(SAY_VOICE_KEY=1 say_pick_index 3)
assert_eq "explicit key '1' is hashed, not defaulted" "$got_one" "$expect_one"

# Set-but-EMPTY key → caller has no identity → unidentified → index 0 (default).
# (Distinct from unset: an explicit empty means "I tried, I have nothing".)
assert_eq "empty SAY_VOICE_KEY → default index 0" "$(SAY_VOICE_KEY='' say_pick_index 3)" "0"
assert_eq "empty SAY_VOICE_KEY → resolver empty" "$(SAY_VOICE_KEY='' say_resolve_key)" ""

# UNSET key → fall back to $PPID (a real number in this test process).
# (PPID is readonly in bash, so the PPID==1 orphan branch can't be unit-tested
# here; it's exercised by the integration behaviour of detached callers.)
key_unset=$(unset SAY_VOICE_KEY; say_resolve_key)
assert_true "unset SAY_VOICE_KEY → resolver is a PPID number ($key_unset)" "[[ '$key_unset' =~ ^[0-9]+$ ]]"

# Spread: distinct keys should touch >1 index (not all-collapsed).
seen=$(for k in a b c d e f g h; do SAY_VOICE_KEY="$k" say_pick_index 3; echo; done | sort -u | wc -l)
assert_true "distinct keys spread across pool (>1 index seen)" "[ $seen -gt 1 ]"

echo "== backends honour explicit voice overrides =="
assert_true "say-ko honours \$EDGE_TTS_VOICE" "grep -q 'EDGE_TTS_VOICE:-' '$dotfiles/bin/say-ko'"
assert_true "say-en honours \$PIPER_MODEL"    "grep -q 'PIPER_MODEL:-' '$dotfiles/bin/say-en'"

echo "== say: resolves + exports SAY_VOICE_KEY to backend =="

# Stage a fake DOTFILES_ROOT whose backends echo the inherited key. Copy the
# real say-voice.sh alongside so `say`'s `source` finds it.
tmp=$(mktemp -d /tmp/test_say_voice.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cp "$dotfiles/bin/say" "$tmp/bin/say"
cp "$dotfiles/bin/say-voice.sh" "$tmp/bin/say-voice.sh"
cat >"$tmp/bin/say-en" <<'EOF'
#!/usr/bin/env bash
printf 'KEY=%s\n' "${SAY_VOICE_KEY-UNSET}" >"$SAY_TEST_OUT"
EOF
cp "$tmp/bin/say-en" "$tmp/bin/say-ko"
chmod +x "$tmp/bin"/say-*

out="$tmp/out"
# Explicit key must pass through unchanged.
SAY_TEST_OUT="$out" DOTFILES_ROOT="$tmp" SAY_NO_PREEMPT=1 SAY_NO_MEETING_CHECK=1 \
    SAY_VOICE_KEY="explicit-key" "$tmp/bin/say" "hello world" >/dev/null 2>&1
assert_eq "explicit SAY_VOICE_KEY propagates to backend" "$(cat "$out")" "KEY=explicit-key"

# With no explicit key, say substitutes its own PPID (a number; say itself is
# not setsid'd here so PPID != 1).
SAY_TEST_OUT="$out" DOTFILES_ROOT="$tmp" SAY_NO_PREEMPT=1 SAY_NO_MEETING_CHECK=1 \
    "$tmp/bin/say" "hello world" >/dev/null 2>&1
got=$(cat "$out")
assert_true "default key is a non-empty PPID number ($got)" "[[ '$got' =~ ^KEY=[0-9]+$ ]]"

echo
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
