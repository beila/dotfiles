#!/usr/bin/env bash
# Shared voice-selection helper for say / say-ko / say-en. Source it, don't run.
# This is the single place the caller→voice mapping is defined.
#
# Caller contract: $SAY_VOICE_KEY is an OPAQUE, arbitrary identity string chosen
# by the caller (session id, pid, anything). It carries no knowledge of the
# voice pool, its size, or the voice names. Any non-empty value is honoured
# verbatim — including "1".
#
# Unset vs set-but-empty is meaningful:
#   - unset            → caller didn't specify; fall back to $PPID (a stable
#                        identity for interactive / directly-spawned callers).
#   - set but empty    → caller tried and has no identity (e.g. a hook whose
#                        session id came back empty) → stay UNIDENTIFIED, which
#                        the pickers map to the default voice.
# Detaching callers (the Claude hooks, mcp-tts) pass an explicit key rather than
# relying on the $PPID fallback: once a backgrounded `setsid` child is reparented
# to the init/subreaper (NOT necessarily pid 1 — a user systemd is common), its
# $PPID is either that reaper's pid or a racy short-lived parent, neither of which
# is the semantic caller identity we want the voice keyed to.

# Echo the resolved caller key, or empty if the caller is unidentified.
say_resolve_key() {
    # Set (even if empty) → honour verbatim; empty means "no identity".
    if [ -n "${SAY_VOICE_KEY+set}" ]; then
        printf '%s' "$SAY_VOICE_KEY"
        return
    fi
    # Unset → fall back to the parent pid, unless we're an orphan (PPID 1/absent).
    [ "${PPID:-1}" != "1" ] && printf '%s' "$PPID"
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
