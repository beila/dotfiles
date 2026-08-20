# Persist the final rendered scrollback while the zmx socket is still alive.
if [[ -n ${ZMX_SESSION:-} ]]; then
  autoload -Uz add-zsh-hook

  _zmx_history_snapshot_on_exit() {
    local helper="${DOTFILES_ROOT:-$HOME/.dotfiles}/bin/zmx-history"
    [[ -x "$helper" ]] || return 0

    if (( $+commands[timeout] )); then
      command timeout 5 "$helper" snapshot "$ZMX_SESSION" "$PWD" >/dev/null 2>&1 || true
    else
      "$helper" snapshot "$ZMX_SESSION" "$PWD" >/dev/null 2>&1 || true
    fi
  }

  add-zsh-hook -d zshexit _zmx_history_snapshot_on_exit 2>/dev/null
  add-zsh-hook zshexit _zmx_history_snapshot_on_exit
fi
