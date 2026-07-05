#!/usr/bin/env bash
# Shared voice-selection helper for say / say-ko / say-en. Source it, don't run.
# This is the single place the caller→voice mapping is defined.
#
# Caller contract: $SAY_VOICE_KEY is an OPAQUE, arbitrary identity string chosen
# by the caller (session id, pid, anything). It carries no knowledge of the
# voice pool, its size, or the voice names. Any non-empty value is honoured
# verbatim — including "1".
#
# When no key is given we fall back to $PPID, EXCEPT a PPID of 1: that means the
# process was reparented to init (e.g. spawned under setsid) and has no
# meaningful caller, so it stays unidentified. This setsid detail lives here,
# not in the key contract — so an explicit key of "1" is never conflated with it.

# Echo the resolved caller key, or empty if the caller is unidentified.
say_resolve_key() {
    local key="${SAY_VOICE_KEY:-}"
    if [ -z "$key" ] && [ "${PPID:-1}" != "1" ]; then
        key="$PPID"
    fi
    printf '%s' "$key"
}

# say_pick_index <pool_size> → 0-based voice index.
# Deterministic and uniform for arbitrary opaque keys: index = sha256(key) mod
# pool_size. sha256 (not cksum/CRC32, which is linear over GF(2) and can cluster
# structured keys like sequential PIDs or prefix-sharing session ids) gives a
# flat distribution regardless of what the caller passes, without the caller
# knowing pool_size. 15 hex digits = 60 bits, safely inside bash's 64-bit signed
# arithmetic; modulo bias over 2^60 with pool_size≤~thousands is ~1e-17.
# Unidentified key → 0 (the pool's first entry, i.e. the historical default).
say_pick_index() {
    local count="$1" key h
    key="$(say_resolve_key)"
    if [ -z "$key" ]; then
        printf '0'
        return
    fi
    h=$(printf '%s' "$key" | sha256sum | cut -c1-15)
    printf '%s' "$(( 0x$h % count ))"
}
