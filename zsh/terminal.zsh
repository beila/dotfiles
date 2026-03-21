# Based on zprezto modules/terminal/init.zsh
#
# Sets terminal window and tab titles.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#   Olaf Conradi <olaf@conradi.org>
#

# Return if requirements are not found.
[[ "$TERM" == (dumb|linux|*bsd*|eterm*) ]] && return

# Sets the tab and window titles with a given command.
function _terminal-set-titles-with-command {
  emulate -L zsh; setopt EXTENDED_GLOB

  # Get the command name that is under job control.
  if [[ "${2[(w)1]}" == (fg|%*)(';'|) ]]; then
    local job_name="${${2[(wr)%*(';'|)]}:-%+}"
    local -A jobtexts_from_parent_shell=("${(kv)jobtexts}")
    jobs "$job_name" 2>/dev/null > >(
      read index _
      _terminal-set-titles-with-command "${(e):-\$jobtexts_from_parent_shell$index}"
    )
    return
  fi

  # Set the command name, or in the case of sudo or ssh, the next command.
  local cmd="${${2[(wr)^(*=*|sudo|ssh|-*)]}:t}"
  local truncated_cmd="${cmd/(#m)?(#c15,)/${MATCH[1,12]}...}"
  unset MATCH

  [[ "$TERM" == screen* ]] && printf '\ek%s\e\\' "$truncated_cmd"
  printf '\e]1;%s\a' "$truncated_cmd"  # tab/pane title
  printf '\e]2;%s\a' "$cmd"            # window title
}

# Sets the tab and window titles with a given path.
function _terminal-set-titles-with-path {
  emulate -L zsh; setopt EXTENDED_GLOB

  local absolute_path="${${1:a}:-$PWD}"
  local abbreviated_path="${absolute_path/#$HOME/~}"
  local truncated_path="${abbreviated_path/(#m)?(#c15,)/...${MATCH[-12,-1]}}"
  unset MATCH

  [[ "$TERM" == screen* ]] && printf '\ek%s\e\\' "$truncated_path"
  printf '\e]1;%s\a' "$truncated_path"  # tab/pane title
  printf '\e]2;%s\a' "$abbreviated_path" # window title
}

autoload -Uz add-zsh-hook

# Set up the Apple Terminal.
if [[ "$TERM_PROGRAM" == 'Apple_Terminal' ]] && ! [[ -n "$STY" || -n "$TMUX" || -n "$DVTM" ]]; then
  function _terminal-set-proxy-icon {
    printf '\e]7;%s\a' "file://${HOST}${PWD// /%20}"
  }
  function _terminal-unset-proxy-icon {
    [[ "${2[(w)1]:t}" == (screen|tmux|dvtm|ssh|mosh) ]] && print '\e]7;\a'
  }
  add-zsh-hook precmd _terminal-set-proxy-icon
  add-zsh-hook preexec _terminal-unset-proxy-icon
  return
fi

# Set up non-Apple terminals.
add-zsh-hook precmd _terminal-set-titles-with-path
add-zsh-hook preexec _terminal-set-titles-with-command
