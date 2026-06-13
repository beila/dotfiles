# shellcheck shell=bash
# backends/telegram.sh — Telegram Bot API backend.
#
# Requires $DOTFILES_ROOT/private-dotfiles/telegram.env with:
#   TELEGRAM_BOT_TOKEN=<bot token from @BotFather>
#   TELEGRAM_CHAT_ID=<your chat id>
#
# Setup steps for the user:
#   1. Message @BotFather in Telegram; send /newbot; get a bot token.
#   2. Send any message to the new bot from your Telegram account.
#   3. Visit https://api.telegram.org/bot<TOKEN>/getUpdates and find
#      "chat":{"id":<NUMBER>,...}. That number is TELEGRAM_CHAT_ID.
#   4. Save both values in private-dotfiles/telegram.env.
#
# Priority handling:
#   low     -> disable_notification=true (silent push)
#   normal  -> default
#   high    -> prepend 🟠 to the title
#   urgent  -> prepend 🔴 to the title AND disable_web_page_preview=false
#
# Behavior:
#   - Silent no-op if telegram.env missing or tokens empty.
#   - Non-zero exit on Telegram API failure; callers decide whether to care.
#   - 5-second network timeout.

notify_send() {
    local title=$1 priority=$2 url=$3 message=$4

    local env_file="${DOTFILES_ROOT:-$HOME/.dotfiles}/private-dotfiles/telegram.env"
    [ -f "$env_file" ] || return 0

    # shellcheck source=/dev/null
    . "$env_file"
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || return 0
    [ -n "${TELEGRAM_CHAT_ID:-}" ]   || return 0

    local silent=false
    local prefix=""
    case "$priority" in
        low)    silent=true ;;
        high)   prefix="🟠 " ;;
        urgent) prefix="🔴 " ;;
    esac

    # Build HTML body: bold title line (if any), then blank line, then message,
    # then optional URL as a plain link.
    # Escape HTML-significant chars in user-controlled text (< > &).
    _telegram_escape() {
        printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
    }
    local body=""
    if [ -n "$title" ]; then
        body+="<b>${prefix}$(_telegram_escape "$title")</b>"$'\n\n'
    fi
    body+="$(_telegram_escape "$message")"
    if [ -n "$url" ]; then
        body+=$'\n\n'"<a href=\"$(_telegram_escape "$url")\">$(_telegram_escape "$url")</a>"
    fi

    curl -sS --max-time 5 -o /dev/null \
        -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${body}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_notification=${silent}"
}
