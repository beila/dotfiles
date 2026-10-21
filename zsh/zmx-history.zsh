# Persist the final rendered scrollback while the zmx socket is still alive.
if [[ -n ${ZMX_SESSION:-} ]]; then
  autoload -Uz add-zsh-hook

  # zmx-select renames a running session through its socket path, but this
  # shell keeps the old ZMX_SESSION. Follow the rename map of zmx-select. The
  # shell pid in each entry prevents a reused name from renaming this shell.
  _zmx_follow_rename() {
    local map_dir="${ZMX_RENAME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zmx-select/renamed}"
    local name=$ZMX_SESSION next pid hops=0
    [[ -r $map_dir/$name ]] || return 0
    while [[ -r $map_dir/$name ]] && (( hops++ < 10 )); do
      IFS=$'\t' read -r next pid < "$map_dir/$name" || break
      [[ -n $next && ( -z $pid || $pid == $$ ) ]] || break
      name=$next
    done
    [[ $name == $ZMX_SESSION ]] || export ZMX_SESSION=$name
  }

  # Run first, so that the title hooks use the new name.
  precmd_functions=(_zmx_follow_rename ${precmd_functions:#_zmx_follow_rename})

  _zmx_history_snapshot_on_exit() {
    local helper="${DOTFILES_ROOT:-$HOME/.dotfiles}/bin/zmx-history"
    [[ -x "$helper" ]] || return 0
    _zmx_follow_rename

    if (( $+commands[timeout] )); then
      command timeout 5 "$helper" snapshot "$ZMX_SESSION" "$PWD" >/dev/null 2>&1 || true
    else
      "$helper" snapshot "$ZMX_SESSION" "$PWD" >/dev/null 2>&1 || true
    fi
  }

  add-zsh-hook -d zshexit _zmx_history_snapshot_on_exit 2>/dev/null
  add-zsh-hook zshexit _zmx_history_snapshot_on_exit
fi
