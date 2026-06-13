#!/usr/bin/env bash
# Replace the home-manager managed block inside the user's crontab.
#
# Args:
#   $1  begin marker (single line)
#   $2  end marker   (single line)
#   $3  path to file containing the new managed block (begin marker .. end marker)
#
# Behavior:
#   - Read existing crontab (empty if none installed yet).
#   - Strip everything between the begin and end markers (inclusive).
#   - Append the new managed block.
#   - Install via `crontab -`.
#
# Idempotent: re-running with identical content produces a byte-identical
# crontab. Lines outside the managed block are preserved untouched, so
# user-edited entries survive home-manager switches.
set -euo pipefail

BEGIN=$1
END=$2
NEW=$3

if [ ! -r "$NEW" ]; then
    echo "install-crontab: new block file not readable: $NEW" >&2
    exit 1
fi

if ! command -v crontab >/dev/null 2>&1; then
    echo "install-crontab: crontab(1) not on PATH; cannot install schedule" >&2
    exit 1
fi

tmp=$(mktemp /tmp/dotfiles-crontab.XXXXXX)
trap 'rm -f "$tmp"' EXIT

# Existing crontab — `crontab -l` exits 1 with "no crontab for <user>" when
# none is installed. Treat that as empty rather than fatal.
crontab -l 2>/dev/null > "$tmp" || true

# Drop any prior managed block. Use awk (more portable than sed for line-
# delimited delete-between-markers; no dependency on GNU extensions).
stripped=$(awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
' "$tmp")

# Compose the new crontab: keep the surrounding user content, then the
# managed block. Trailing newline so cron parses cleanly even when the
# managed block is the last thing in the file.
{
    if [ -n "$stripped" ]; then
        printf '%s\n' "$stripped"
    fi
    cat "$NEW"
} > "$tmp.new"

# Skip the install if nothing actually changed — keeps the activation noise
# down (crontab(1) prints nothing on success, but other tooling may watch
# the crontab spool's mtime).
if [ -s "$tmp" ] && cmp -s "$tmp" "$tmp.new"; then
    exit 0
fi

crontab "$tmp.new"
echo "install-crontab: managed block updated ($(grep -c '^[^#]' "$NEW" || true) job(s))"
