# Repository-aware Ctrl-R widget. The generated fzf widget remains untouched;
# this module replaces it after fzf/fzf.zsh has loaded.

typeset -g _repo_history_fzf_action="${DOTFILES_ROOT:-$HOME/.dotfiles}/zsh/repo-history/fzf-action"

_repo_history_adapt_command() {
  emulate -L zsh
  local old_root="$1" current_root="$2" remaining="$3"
  local output="" escaped_old="${(b)old_root}"

  if [[ -z "$old_root" || "$old_root" == "$current_root" ]]; then
    REPLY="$remaining"
    return 0
  fi

  while [[ "$remaining" == *${~escaped_old}* ]]; do
    local before="${remaining%%${~escaped_old}*}"
    remaining="${remaining#*${~escaped_old}}"
    local previous="${before[-1,-1]-}"
    local next="${remaining[1,1]-}"

    output+="$before"
    if { [[ -z "$previous" || "$previous" != [[:alnum:]_./-] ]] &&
         [[ -z "$next" || "$next" != [[:alnum:]_.-] ]] }; then
      output+="$current_root"
    else
      output+="$old_root"
    fi
  done

  REPLY="${output}${remaining}"
}

_repo_history_write_global_candidates() {
  emulate -L zsh
  setopt pipefail
  local output="$1"
  : >| "$output"

  zmodload -F zsh/parameter p:{commands,history} 2>/dev/null || return 0

  if (( ${+commands[perl]} )); then
    builtin printf '%s\t%s\000' "${(kv)history[@]}" |
      command perl -0 -ne '
        if (/^\s*([0-9]+)\**\t(.*)$/s && !$seen{$2}++) {
          print "g:$1\t$2\0";
        }
      ' >| "$output"
    return $?
  fi

  local event command
  typeset -A seen
  for event in ${(Onk)history}; do
    command="${history[$event]}"
    [[ -n "${seen[$command]-}" ]] && continue
    seen[$command]=1
    print -rN -- "g:${event}"$'\t'"${command}" >>! "$output"
  done
}

_repo_history_write_repo_candidates() {
  emulate -L zsh
  local output="$1"
  : >| "$output"
  _repo_history_resolve || return 1
  [[ -r "$_repo_history_file" ]] || return 0

  local epoch workspace_root cwd command
  local -a epochs workspace_roots commands
  while IFS= read -r -d $'\0' epoch &&
        IFS= read -r -d $'\0' workspace_root &&
        IFS= read -r -d $'\0' cwd &&
        IFS= read -r -d $'\0' command; do
    epochs+=("$epoch")
    workspace_roots+=("$workspace_root")
    commands+=("$command")
  done < "$_repo_history_file"

  typeset -A seen
  local i adapted
  for (( i = ${#commands}; i >= 1; --i )); do
    _repo_history_adapt_command \
      "${workspace_roots[i]}" \
      "$_repo_history_workspace_root" \
      "${commands[i]}"
    adapted="$REPLY"
    [[ -n "${seen[$adapted]-}" ]] && continue
    seen[$adapted]=1
    print -rN -- "r:${epochs[i]}:${i}"$'\t'"${adapted}" >>! "$output"
  done
}

_repo_history_apply_selection() {
  emulate -L zsh
  local selected_file="$1" item id query=""
  local -a commands

  while IFS= read -r -d $'\0' item; do
    if [[ "$item" == *$'\t'* ]]; then
      id="${item%%$'\t'*}"
      if [[ "$id" == g:* || "$id" == r:* ]]; then
        commands+=("${item#*$'\t'}")
        continue
      fi
    fi
    query="$item"
  done < "$selected_file"

  if (( ${#commands} )); then
    BUFFER="${(pj:\n:)${(@)commands%%$'\n'#}}"
    CURSOR=${#BUFFER}
  elif [[ -n "$query" ]]; then
    LBUFFER="$query"
  fi
}

_repo_history_toggle_binding() {
  emulate -L zsh
  local state_file="$1" global_file="$2" repo_file="$3"
  local action="${(qq)_repo_history_fzf_action}"
  local state="${(qq)state_file}"
  local global="${(qq)global_file}"
  local repo="${(qq)repo_file}"

  REPLY="ctrl-r:execute-silent(sh ${action} toggle ${state})"
  REPLY+="+reload(sh ${action} list ${state} ${global} ${repo})"
  REPLY+="+transform-prompt(sh ${action} prompt ${state})"
  REPLY+="+transform-header(sh ${action} header ${state})"
}

fzf-history-widget() {
  emulate -L zsh
  setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases \
    no_glob no_sh_glob no_ksharrays extendedglob

  local temp_dir
  temp_dir=$(command mktemp -d "${TMPDIR:-/tmp}/repo-history-fzf.XXXXXX") || {
    zle redisplay
    return 1
  }

  local global_file="$temp_dir/global"
  local repo_file="$temp_dir/repo"
  local state_file="$temp_dir/scope"
  local selected_file="$temp_dir/selected"
  local in_repo=0 scope=global prompt header input_file
  local ret=0 toggle_binding="" ctrl_r_opts="${FZF_CTRL_R_OPTS-}"

  {
    _repo_history_resolve && in_repo=1
    _repo_history_write_global_candidates "$global_file"

    if (( in_repo )); then
      _repo_history_write_repo_candidates "$repo_file"
      scope="$_repo_history_scope"
      [[ "$scope" == repo || "$scope" == global ]] || scope=repo
      print -r -- "$scope" >| "$state_file"
      _repo_history_toggle_binding "$state_file" "$global_file" "$repo_file"
      toggle_binding="$REPLY"
    else
      : >| "$repo_file"
      print -r -- global >| "$state_file"
    fi

    if [[ "$scope" == repo ]]; then
      input_file="$repo_file"
      prompt='repo> '
      header='repo scope · Ctrl-R global · Alt-S sort · Alt-R raw'
    else
      input_file="$global_file"
      prompt='global> '
      if (( in_repo )); then
        header='global scope · Ctrl-R repo · Alt-S sort · Alt-R raw'
      else
        header='global scope · Alt-S sort · Alt-R raw'
      fi
    fi

    # FZF_CTRL_R_OPTS currently previews {}, but field 1 is our hidden record
    # ID. Point existing previews at the displayed command fields instead.
    ctrl_r_opts="${ctrl_r_opts//\{\}/\{2..\}}"

    local -a binding_args
    binding_args=(--bind 'alt-s:toggle-sort,alt-r:toggle-raw')
    [[ -n "$toggle_binding" ]] && binding_args+=(--bind "$toggle_binding")

    FZF_DEFAULT_OPTS=$(__fzf_defaults "" "$ctrl_r_opts") \
      FZF_DEFAULT_OPTS_FILE='' \
      $(__fzfcmd) \
        --read0 \
        --print0 \
        --delimiter=$'\t' \
        --with-nth=2.. \
        -n2..,.. \
        --scheme=history \
        --wrap-sign=$'\t↳ ' \
        --highlight-line \
        --multi \
        --query="$LBUFFER" \
        --prompt="$prompt" \
        --header="$header" \
        "${binding_args[@]}" \
        < "$input_file" >| "$selected_file"
    ret=$?

    if (( in_repo )); then
      IFS= read -r scope < "$state_file"
      [[ "$scope" == repo || "$scope" == global ]] &&
        _repo_history_scope="$scope"
    fi

    _repo_history_apply_selection "$selected_file"
  } always {
    command rm -rf -- "$temp_dir"
  }

  zle reset-prompt
  return "$ret"
}

if [[ -o interactive ]] && (( ${+functions[__fzfcmd]} )); then
  zle -N fzf-history-widget
  bindkey -M emacs '^R' fzf-history-widget
  bindkey -M viins '^R' fzf-history-widget
  bindkey -M vicmd '^R' fzf-history-widget
fi
