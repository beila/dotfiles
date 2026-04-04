# shellcheck shell=bash disable=SC2016,SC2296,SC2298
# JJ / GIT heart FZF
# ------------------
# _j*     — jj implementations
# _git_*  — git implementations
_fzf_functions_sh="${${(%):-%x}:a}"
# _g*     — dispatchers: jj-first, git-fallback

is_in_git_repo() {
  git rev-parse HEAD > /dev/null 2>&1
}

is_in_jj_repo() {
  jj root > /dev/null 2>&1
}

fzf_down() {
  fzf --height 50% --min-height 20 --border --bind ctrl-/:toggle-preview "$@"
}

# --- helpers (git) ---

_gf_remove_status() {
    cut -c4-
}
_gf_remove_original_name() {
    sed "s/.* -> //"
}
_gf_remove_quote() {
    sed 's/^"\(.*\)"$/\1/'
}
_gf_show_diff() {
    DFT_COLOR=always DFT_DISPLAY=inline git diff --color=always --cached HEAD "$@"
    DFT_COLOR=always DFT_DISPLAY=inline git diff --color=always "$@"
}
_gf_get_file() {
    _gf_remove_status | _gf_remove_original_name | _gf_remove_quote
}

_git_log_fzf() {
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
}

# --- helpers (jj) ---

# shellcheck disable=SC2120
_jj_log_fzf() {
  fzf_down --ansi --no-sort --reverse --multi "$@" \
    --preview 'grep -o "[a-z]\{8,\}" <<< {} | head -1 | xargs -I% jj --quiet show --color=always %' |
  grep -o "[a-z]\{8,\}" | head -1
}

_dim_jj_op_ids() {
  # Replace blue operation IDs (ansi 38;5;4) with dim gray, and fully reset after
  sed "s/\x1b\[38;5;4m\([0-9a-f]*\)\x1b\[39m/\x1b[2;90m\1\x1b[0m/g"
}

# --- files ---

_jf() {
  jj --quiet diff --name-only 2>/dev/null |
    fzf_down -m \
      --preview 'jj --quiet diff --color=always -- {}'
}

_git_f() {
# shellcheck disable=SC2016,SC2154
  git -c color.status=always status --ignore-submodules="${_git_status_ignore_submodules}" --short |
    fzf_down -m --ansi --nth 2..,.. \
      --preview-window=right,70% \
      --preview "$(functions _gf_remove_status _gf_remove_original_name _gf_remove_quote _gf_show_diff _gf_get_file)"'
        file=$(_gf_get_file <<< {})
        if [[ "$(_gf_show_diff --no-ext-diff "$file")" ]]; then _gf_show_diff "$file"
        else; bat "$file" 2>/dev/null || cat "$file" 2>/dev/null || ls -l --color=always "$file" ; fi' |
    _gf_get_file
}

_gf() { if is_in_jj_repo; then _jf; elif is_in_git_repo; then _git_f; fi }

# --- file browser (ctrl-f toggle between tracked and all files) ---

_file_browse() {
  local preview='bat --style=numbers --color=always -- {} 2>/dev/null || cat {}'
  if is_in_jj_repo; then
    jj file list 2>/dev/null |
      fzf_down -m --prompt 'tracked> ' \
        --header '☐ all files (ctrl-f)' \
        --preview "$preview" \
        --bind 'ctrl-f:transform:[[ $FZF_PROMPT == tracked* ]] &&
          echo "change-prompt(all> )+change-header(☑ all files (ctrl-f))+reload(fd --type f --hidden --no-ignore)" ||
          echo "change-prompt(tracked> )+change-header(☐ all files (ctrl-f))+reload(jj file list)"'
  elif is_in_git_repo; then
    git ls-files 2>/dev/null |
      fzf_down -m --prompt 'tracked> ' \
        --header '☐ all files (ctrl-f)' \
        --preview "$preview" \
        --bind 'ctrl-f:transform:[[ $FZF_PROMPT == tracked* ]] &&
          echo "change-prompt(all> )+change-header(☑ all files (ctrl-f))+reload(fd --type f --hidden --no-ignore)" ||
          echo "change-prompt(tracked> )+change-header(☐ all files (ctrl-f))+reload(git ls-files)"'
  else
    fd --type f --hidden --no-ignore 2>/dev/null |
      fzf_down -m --prompt 'all> ' --preview "$preview"
  fi
}

# --- bookmarks / branches ---

_jb() {
  local pos_bind=()
  [[ -n "${1:-}" ]] && pos_bind=(--bind "result:pos($(($1+1)))+unbind(result)")
  # Preview uses unique_boundary() revset alias (see jj config.toml)
  # Preprocessing: indented lines ("  @hj ...") are remote tracking info;
  # prefix them with the parent bookmark name so they become "nix@hj ..."
  jj --quiet bookmark list --color=always 2>/dev/null |
    awk '{if(/^ /){gsub(/^ +/,""); $1=parent $1} else {parent=$1; gsub(/:$/,"",parent); gsub(/\033\[[0-9;]*m/,"",parent)} print}' |
    fzf_down --ansi --multi --preview-window right:70% \
      --header '☐ workspaces (ctrl-b)' \
      "${pos_bind[@]}" \
      --bind "ctrl-b:become(zsh -c 'source $_fzf_functions_sh; _jbb {n}')" \
      --preview 'name=$(awk "{gsub(/:$/,\"\",\$1); gsub(/\033\[[0-9;]*m/,\"\",\$1); print \$1}" <<< {})
        jj --quiet log --color=always -r "unique_boundary($name, bookmarks() | remote_bookmarks())"' |
    awk '{gsub(/:$/,"",$1); gsub(/\033\[[0-9;]*m/,"",$1); print $1}'
}

_git_b() {
# shellcheck disable=SC2016
  git branch -a --color=always | grep -v '/HEAD\s' | sort |
  fzf_down --ansi --multi --tac --preview-window right:70% \
    --preview 'git log --oneline --graph --date=short --color=always --pretty="format:%C(auto)%cd %h%d %s" $(sed s/^..// <<< {} | cut -d" " -f1)' |
  sed 's/^..//' | cut -d' ' -f1 |
  sed 's#^remotes/##'
}

_gb() { if is_in_jj_repo; then _jb; elif is_in_git_repo; then _git_b; fi }

# --- workspaces / worktrees ---

_jbb() {
  local pos_bind=()
  [[ -n "${1:-}" ]] && pos_bind=(--bind "result:pos($(($1+1)))+unbind(result)")
  jj --quiet workspace list --color=always 2>/dev/null |
    fzf_down --ansi --multi --preview-window right:70% \
      --header '☑ workspaces (ctrl-b)' \
      "${pos_bind[@]}" \
      --bind "ctrl-b:become(zsh -c 'source $_fzf_functions_sh; _jb {n}')" \
      --preview 'jj --quiet log --color=always -r "::($(awk "{print \$2}" <<< {}))"' |
    cut -d: -f1
}

_git_bb() {
# shellcheck disable=SC2016
  git worktree list |
    fzf_down --ansi --multi --tac --preview-window right:70% \
        --preview 'git -C $(awk "{print \$1}" <<< {}) diff --stat --color=always
          git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%d %s (%an)" --color=always "$(awk "{print \$2}" <<< {})" "^$(git merge-base "$(awk "{print \$2}" <<< {})" "origin/HEAD")^@"' |
    cut -d' ' -f1
}

_gbb() { if is_in_jj_repo; then _jbb; elif is_in_git_repo; then _git_bb; fi }

# --- tags ---

_jt() {
  # Preview uses unique_boundary() revset alias (see jj config.toml)
  jj --quiet tag list --color=always 2>/dev/null |
    fzf_down --ansi --multi --preview-window right:70% \
      --preview 'name=$(awk "{gsub(/:$/,\"\",\$1); gsub(/\033\[[0-9;]*m/,\"\",\$1); print \$1}" <<< {})
        jj --quiet log --color=always -r "unique_boundary($name, tags())"' |
    awk '{gsub(/:$/,"",$1); print $1}'
}

_git_t() {
  git tag --sort -version:refname |
  fzf_down --multi --preview-window right:70% \
    --preview 'git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always {}'
}

_gt() { if is_in_jj_repo; then _jt; elif is_in_git_repo; then _git_t; fi }

# --- log upstream ---

# Extract jj change ID from an fzf line (strips ANSI codes)
_jj_change_id='sed "s/\x1b\[[0-9;]*m//g" <<< {} | grep -o "[a-z]\{8,\}" | head -1'

# Find line number of a change ID in jj log output (head -500 for SIGPIPE early exit)
_jj_find_pos() { jj --quiet log -T 'builtin_log_oneline' ${2:+-r "$2"} 2>/dev/null | head -500 | grep -n -m1 "$1" | cut -d: -f1; }

# shellcheck disable=SC2120
_jh() {
  local pos_bind=()
  if [[ -n "${1:-}" ]]; then
    local pos; pos=$(_jj_find_pos "$1")
    [[ -n "$pos" ]] && pos_bind=(--bind "result:pos($pos)+unbind(result)")
  fi
  jj --quiet log --color=always -T 'fzf_oneline' 2>/dev/null | _jj_log_fzf \
    --header '☐ full log (ctrl-h)' \
    "${pos_bind[@]}" \
    --bind "ctrl-h:become(FZF_ID=\$($_jj_change_id) zsh -c 'source $_fzf_functions_sh; _jhh \$FZF_ID')"
}

_git_h() {
  git rev-parse "@{u}" || { echo "No upstream"; return; }
  all_parents_of_merge_base="$(git merge-base HEAD "@{u}")^@"
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always HEAD "@{u}" "^${all_parents_of_merge_base}"|
  _git_log_fzf
}

_gh() { if is_in_jj_repo; then _jh; elif is_in_git_repo; then _git_h; fi }

# --- log all ---

_jyy() {
  local pos_bind=()
  [[ -n "${1:-}" ]] && pos_bind=(--bind "result:pos($(($1+1)))+unbind(result)")
  jj --quiet log --color=always -T 'fzf_oneline_author' -r 'all()' 2>/dev/null | _jj_log_fzf \
    --header '☐ op log (ctrl-y)' \
    "${pos_bind[@]}" \
    --bind "ctrl-y:become(zsh -c 'source $_fzf_functions_sh; _jy {n}')"
}

_git_yy() {
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always --all |
  _git_log_fzf
}

_gyy() { if is_in_jj_repo; then _jyy; elif is_in_git_repo; then _git_yy; fi }

# --- log ---

# shellcheck disable=SC2120
_jhh() {
  local pos_bind=()
  if [[ -n "${1:-}" ]]; then
    local pos; pos=$(_jj_find_pos "$1" '::@')
    [[ -n "$pos" ]] && pos_bind=(--bind "result:pos($pos)+unbind(result)")
  fi
  jj --quiet log --color=always -T 'fzf_oneline_author' -r '::@' 2>/dev/null | _jj_log_fzf \
    --header '☑ full log (ctrl-h)' \
    "${pos_bind[@]}" \
    --bind "ctrl-h:become(FZF_ID=\$($_jj_change_id) zsh -c 'source $_fzf_functions_sh; _jh \$FZF_ID')"
}

_git_hh() {
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always |
  _git_log_fzf
}

_ghh() { if is_in_jj_repo; then _jhh; elif is_in_git_repo; then _git_hh; fi }

# --- reflog / operation log ---

_jy() {
  local pos_bind=()
  [[ -n "${1:-}" ]] && pos_bind=(--bind "result:pos($(($1+1)))+unbind(result)")
  jj --quiet operation log --no-graph --color=always -T 'self.time().start().ago() ++ " " ++ self.tags().first_line().remove_prefix("args: ") ++ " " ++ self.id().short() ++ "\n"' 2>/dev/null |
    _dim_jj_op_ids |
    fzf_down --ansi --no-sort --reverse --multi \
      --header '☑ op log (ctrl-y)' \
      "${pos_bind[@]}" \
      --bind "ctrl-y:become(zsh -c 'source $_fzf_functions_sh; _jyy {n}')" \
      --preview 'grep -o "[0-9a-f]\{12,\}" <<< {} | tail -1 | xargs -I% jj --quiet operation show --color=always %' |
    grep -o "[0-9a-f]\{12,\}" | tail -1
}

_git_y() {
  git reflog --date=relative --color=always |
  _git_log_fzf
}

_gy() { if is_in_jj_repo; then _jy; elif is_in_git_repo; then _git_y; fi }

# --- remotes ---

_jr() {
  jj --quiet git remote list 2>/dev/null |
    fzf_down --tac \
      --preview 'jj --quiet log --color=always -r "remote_bookmarks(remote=\"$(awk "{print \$1}" <<< {})\")"' |
    awk '{print $1}'
}

_git_r() {
  git remote -v | awk '{print $1 "\t" $2}' | uniq |
  fzf_down --tac \
    --preview 'git log --oneline --graph --date=short --pretty="format:%C(auto)%cd %h%d %s" {1}' |
  cut -d$'\t' -f1
}

_gr() { if is_in_jj_repo; then _jr; elif is_in_git_repo; then _git_r; fi }

# --- stash (git only) ---

_gs() {
  if is_in_git_repo; then
  git stash list | fzf_down --reverse -d: \
    --preview-window=right,70% \
    --preview 'DFT_COLOR=always DFT_DISPLAY=inline git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always {1} --ext-diff' |
  cut -d: -f1
  fi
}
