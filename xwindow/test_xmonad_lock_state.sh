#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=xwindow/bin/xmonad-lock-state
source "$ROOT/xwindow/bin/xmonad-lock-state"

[[ $(state_from_text '(true,)') == 1 ]]
[[ $(state_from_text '(false,)') == 0 ]]
[[ $(state_from_text '   boolean true') == 1 ]]
[[ $(state_from_text '   boolean false') == 0 ]]
if state_from_text 'unknown' >/dev/null; then
    printf 'unknown lock state was accepted\n' >&2
    exit 1
fi

printf 'xmonad lock-state tests passed\n'
