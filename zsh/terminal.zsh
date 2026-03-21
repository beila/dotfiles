# Terminal titles — replaces zprezto 'terminal' module
# Sets window/tab/pane titles to current path (idle) or running command

[[ "$TERM" == (dumb|linux|*bsd*|eterm*) ]] && return

# Title escape sequences: \e]2; = window, \e]1; = tab, \ek...\e\\ = multiplexer
function _set-title-to-command {
  emulate -L zsh; setopt EXTENDED_GLOB

  # Resolve fg/% to the actual job command
  if [[ "${2[(w)1]}" == (fg|%*)(';'|) ]]; then
    local job_name="${${2[(wr)%*(';'|)]}:-%+}"
    local -A jobtexts_copy=("${(kv)jobtexts}")
    jobs "$job_name" 2>/dev/null > >(
      read index _
      _set-title-to-command "${(e):-\$jobtexts_copy$index}"
    )
    return
  fi

  # Extract command name, skip sudo/ssh/flags
  local cmd="${${2[(wr)^(*=*|sudo|ssh|-*)]}:t}"
  local short="${cmd/(#m)?(#c15,)/${MATCH[1,12]}...}"
  unset MATCH

  [[ "$TERM" == screen* ]] && printf '\ek%s\e\\' "$short"
  printf '\e]1;%s\a' "$short"  # tab/pane title
  printf '\e]2;%s\a' "$cmd"    # window title
}

function _set-title-to-path {
  emulate -L zsh; setopt EXTENDED_GLOB

  local full="${${1:a}:-$PWD}"
  local abbr="${full/#$HOME/~}"
  local short="${abbr/(#m)?(#c15,)/...${MATCH[-12,-1]}}"
  unset MATCH

  [[ "$TERM" == screen* ]] && printf '\ek%s\e\\' "$short"
  printf '\e]1;%s\a' "$short"  # tab/pane title
  printf '\e]2;%s\a' "$abbr"   # window title
}

autoload -Uz add-zsh-hook

# Apple Terminal: set proxy icon (CWD) instead of custom titles
if [[ "$TERM_PROGRAM" == 'Apple_Terminal' ]] && ! [[ -n "$STY" || -n "$TMUX" || -n "$DVTM" ]]; then
  add-zsh-hook precmd  function { printf '\e]7;%s\a' "file://${HOST}${PWD// /%20}" }
  add-zsh-hook preexec function {
    [[ "${2[(w)1]:t}" == (screen|tmux|dvtm|ssh|mosh) ]] && print '\e]7;\a'
  }
  return
fi

add-zsh-hook precmd _set-title-to-path
add-zsh-hook preexec _set-title-to-command
