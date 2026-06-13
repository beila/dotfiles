# shellcheck shell=bash
# backends/mock.sh — test-only backend. Appends each call to a file at
# $NOTIFY_MOCK_FILE (required). One line per call in TSV-ish format:
#   <timestamp>\t<priority>\t<title>\t<url>\t<message (single-line)>
# Message newlines are replaced with literal '\n' so one event = one line.

notify_send() {
    local title=$1 priority=$2 url=$3 message=$4
    : "${NOTIFY_MOCK_FILE:?NOTIFY_MOCK_FILE must be set for mock backend}"
    local flat_msg
    flat_msg=$(printf '%s' "$message" | awk 'BEGIN{ORS="\\n"} {print}' | sed 's/\\n$//')
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$priority" "$title" "$url" "$flat_msg" >> "$NOTIFY_MOCK_FILE"
}
