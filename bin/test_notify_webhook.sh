#!/usr/bin/env bash

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_ROOT_UNDER_TEST=$(cd -- "$SCRIPT_DIR/.." && pwd)
DISPATCHER="$DOTFILES_ROOT_UNDER_TEST/bin/notify-webhook"
TELEGRAM_BACKEND="$DOTFILES_ROOT_UNDER_TEST/script/logger/backends/telegram.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

test_root="$tmp_dir/dotfiles"
private_dir="$test_root/private-dotfiles"
backend_dir="$test_root/script/logger/backends"
fake_bin="$tmp_dir/bin"
capture="$tmp_dir/curl.args"
mkdir -p "$private_dir" "$backend_dir" "$fake_bin"
cp "$TELEGRAM_BACKEND" "$backend_dir/telegram.sh"

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$NOTIFY_CAPTURE"
EOF
chmod +x "$fake_bin/curl"

failures=0
assert_success() {
    local name=$1
    shift
    if "$@"; then
        printf 'ok - %s\n' "$name"
    else
        printf 'not ok - %s\n' "$name"
        failures=$((failures + 1))
    fi
}

assert_failure() {
    local name=$1
    shift
    if "$@"; then
        printf 'not ok - %s\n' "$name"
        failures=$((failures + 1))
    else
        printf 'ok - %s\n' "$name"
    fi
}

assert_failure \
    "invalid destination is rejected" \
    "$DISPATCHER" -d ../escape "message"

assert_failure \
    "missing destination value is rejected" \
    "$DISPATCHER" -d

assert_failure \
    "empty destination is rejected" \
    "$DISPATCHER" --destination= "message"

assert_success \
    "unconfigured default remains a no-op" \
    env DOTFILES_ROOT="$test_root" NOTIFY_BACKEND=telegram "$DISPATCHER" "message"

assert_failure \
    "unconfigured named destination fails" \
    env DOTFILES_ROOT="$test_root" NOTIFY_BACKEND=telegram \
        "$DISPATCHER" -d multica-direct "message"

printf '%s\n' \
    'TELEGRAM_BOT_TOKEN=123456:test-token' \
    'TELEGRAM_CHAT_ID=424242' \
    > "$private_dir/telegram.multica-direct.env"

assert_success \
    "named destination sends with its private config" \
    env \
        DOTFILES_ROOT="$test_root" \
        NOTIFY_BACKEND=telegram \
        NOTIFY_CAPTURE="$capture" \
        PATH="$fake_bin:$PATH" \
        "$DISPATCHER" --destination=multica-direct -t Status -p low "ready"

assert_success \
    "named destination selected its bot token" \
    rg -q 'api.telegram.org/bot123456:test-token/sendMessage' "$capture"

assert_success \
    "named destination selected its chat id" \
    rg -q '^chat_id=424242$' "$capture"

exit "$failures"
