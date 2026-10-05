# jj repository history. Resolution and filesystem work stay lazy so sourcing
# this file adds no external commands to shell startup.

typeset -g REPO_HISTORY_STATE_DIR="${REPO_HISTORY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/zsh/repo-history}"
typeset -g _repo_history_scope="${_repo_history_scope:-repo}"
typeset -g _repo_history_cached_pwd=""
typeset -g _repo_history_workspace_root=""
typeset -g _repo_history_repo_dir=""
typeset -g _repo_history_file=""
typeset -gA _repo_history_ready_files

_repo_history_clear_resolution() {
  _repo_history_cached_pwd=""
  _repo_history_workspace_root=""
  _repo_history_repo_dir=""
  _repo_history_file=""
}

_repo_history_path_is_within() {
  emulate -L zsh
  local path="$1" root="$2"
  local root_length=${#root}

  [[ "$path" == "$root" ]] && return 0
  [[ "$root" == / && "$path" == /* ]] && return 0
  (( ${#path} > root_length )) || return 1
  [[ "${path[1,root_length]}" == "$root" && "${path[root_length + 1]}" == / ]]
}

_repo_history_resolve() {
  emulate -L zsh
  local pwd_abs="${PWD:A}"

  if [[ "$_repo_history_cached_pwd" == "$pwd_abs" ]]; then
    [[ -n "$_repo_history_repo_dir" ]]
    return
  fi

  if [[ -n "$_repo_history_workspace_root" ]] &&
      _repo_history_path_is_within "$pwd_abs" "$_repo_history_workspace_root"; then
    _repo_history_cached_pwd="$pwd_abs"
    return 0
  fi

  _repo_history_clear_resolution

  local dir="$pwd_abs"
  while true; do
    if [[ -d "$dir/.jj" ]]; then
      local repo_marker="$dir/.jj/repo"
      local repo_dir="" pointer=""

      if [[ -d "$repo_marker" ]]; then
        repo_dir="${repo_marker:A}"
      elif [[ -f "$repo_marker" ]]; then
        IFS= read -r pointer < "$repo_marker"
        if [[ -n "$pointer" ]]; then
          if [[ "$pointer" == /* ]]; then
            repo_dir="${pointer:A}"
          else
            repo_dir="${dir}/.jj/${pointer}"
            repo_dir="${repo_dir:A}"
          fi
        fi
      fi

      _repo_history_cached_pwd="$pwd_abs"
      [[ -n "$repo_dir" && -d "$repo_dir" ]] || return 1

      _repo_history_workspace_root="$dir"
      _repo_history_repo_dir="$repo_dir"
      # Mirroring the `.jj/repo` path verbatim would create `.jj` directories
      # in the state tree, which repo scanners (sync_all via plocate) then
      # mistake for broken repositories.
      _repo_history_file="${REPO_HISTORY_STATE_DIR}/repos${repo_dir%/.jj/repo}.history"
      local legacy_file="${REPO_HISTORY_STATE_DIR}/repos${repo_dir}/history"
      # Append rather than move: shells started before the layout change keep
      # writing to the legacy path until they restart.
      if [[ -f "$legacy_file" ]]; then
        command cat -- "$legacy_file" >>! "$_repo_history_file" 2>/dev/null &&
          command rm -f -- "$legacy_file" &&
          command rmdir -p -- "${legacy_file:h}" 2>/dev/null
      fi
      return 0
    fi

    [[ "$dir" == / ]] && break
    dir="${dir:h}"
  done

  _repo_history_cached_pwd="$pwd_abs"
  return 1
}

_repo_history_chpwd() {
  emulate -L zsh
  local pwd_abs="${PWD:A}"

  if [[ -n "$_repo_history_workspace_root" ]] &&
      _repo_history_path_is_within "$pwd_abs" "$_repo_history_workspace_root"; then
    _repo_history_cached_pwd="$pwd_abs"
  else
    _repo_history_clear_resolution
  fi
}

_repo_history_ensure_file() {
  emulate -L zsh
  local file="$1"
  [[ -n "${_repo_history_ready_files[$file]-}" ]] && return 0

  local old_umask
  old_umask=$(umask)
  local result=0
  umask 077
  command mkdir -p -- "${file:h}" || result=$?
  if (( result == 0 )); then
    : >>! "$file" || result=$?
  fi
  umask "$old_umask"

  if (( result == 0 )); then
    _repo_history_ready_files[$file]=1
  fi
  return "$result"
}

_repo_history_should_record() {
  emulate -L zsh
  setopt extendedglob
  local command="$1"

  [[ -n "$command" ]] || return 1
  if [[ -n "${HISTORY_IGNORE-}" && "$command" == ${~HISTORY_IGNORE} ]]; then
    return 1
  fi
  [[ "${command%%[[:space:]]*}" != (fc|history) ]]
}

_repo_history_zshaddhistory() {
  emulate -L zsh
  local command="${_logrun_orig_buffer:-$1}"
  command="${command%%$'\n'}"

  _repo_history_should_record "$command" || return 0
  _repo_history_resolve || return 0
  _repo_history_ensure_file "$_repo_history_file" || return 0

  local epoch="${(%):-%D{%s}}"
  {
    print -rN -- \
      "$epoch" \
      "$_repo_history_workspace_root" \
      "${PWD:A}" \
      "$command" >>! "$_repo_history_file"
  } 2>/dev/null || unset "_repo_history_ready_files[$_repo_history_file]"
  return 0
}

if [[ -o interactive ]]; then
  autoload -Uz add-zsh-hook

  add-zsh-hook -d chpwd _repo_history_chpwd 2>/dev/null
  add-zsh-hook chpwd _repo_history_chpwd

  add-zsh-hook -d zshaddhistory _repo_history_zshaddhistory 2>/dev/null
  add-zsh-hook zshaddhistory _repo_history_zshaddhistory

  # The repository recorder must observe logrun's original buffer before the
  # existing logrun hook clears it.
  zshaddhistory_functions=(
    _repo_history_zshaddhistory
    ${zshaddhistory_functions:#_repo_history_zshaddhistory}
  )
fi
