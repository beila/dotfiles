# GIT heart FZF
# -------------

is_in_git_repo() {
  git rev-parse HEAD > /dev/null 2>&1
}

is_in_jj_repo() {
  jj root > /dev/null 2>&1
}

fzf_down() {
  fzf --height 50% --min-height 20 --border --bind ctrl-/:toggle-preview "$@"
}

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

_gf() {
  if is_in_jj_repo; then
    jj status --color=always | grep '^[AMD]' |
      fzf_down -m --ansi --nth 2.. \
        --preview 'file=$(awk "{print \$2}" <<< {}); jj diff --color=always -- "$file"' |
      awk '{print $2}'
    return
  fi
  if ! is_in_git_repo; then return; fi
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

_gb() {
  if is_in_jj_repo; then
    jj bookmark list --all-remotes --color=always |
      fzf_down --ansi --multi --preview-window right:70% \
        --preview 'jj log --color=always -r "$(awk "{print \$1}" <<< {})"' |
      awk '{print $1}'
    return
  fi
  if ! is_in_git_repo; then return; fi
# shellcheck disable=SC2016
  git branch -a --color=always | grep -v '/HEAD\s' | sort |
  fzf_down --ansi --multi --tac --preview-window right:70% \
    --preview 'git log --oneline --graph --date=short --color=always --pretty="format:%C(auto)%cd %h%d %s" $(sed s/^..// <<< {} | cut -d" " -f1)' |
  sed 's/^..//' | cut -d' ' -f1 |
  sed 's#^remotes/##'
}

_gbb() {
  is_in_git_repo || return
# shellcheck disable=SC2016
  git worktree list |
      fzf_down --ansi --multi --tac --preview-window right:70% \
          --preview 'git -C $(awk "{print \$1}" <<< {}) diff --stat --color=always
            git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%d %s (%an)" --color=always "$(awk "{print \$2}" <<< {})" "^$(git merge-base "$(awk "{print \$2}" <<< {})" "origin/HEAD")^@"' |
      cut -d' ' -f1
}

_gt() {
  is_in_git_repo || return
  git tag --sort -version:refname |
  fzf_down --multi --preview-window right:70% \
    --preview 'git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always {}'
}

_git_log_fzf() {
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
}

_jj_log_fzf() {
  fzf_down --ansi --no-sort --reverse --multi \
    --preview 'grep -o "[a-z]\{8,\}" <<< {} | head -1 | xargs -I% jj show --color=always %' |
  grep -o "[a-z]\{8,\}" | head -1
}

_gh() {
  is_in_git_repo || return
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always |
  _git_log_fzf
}

_gyy() {
  is_in_git_repo || return
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always --all |
  _git_log_fzf
}

_ghh() {
  is_in_git_repo || return
  git rev-parse "@{u}" || { echo "No upstream"; return }
  all_parents_of_merge_base="$(git merge-base HEAD "@{u}")^@"
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always HEAD "@{u}" "^${all_parents_of_merge_base}"|
  _git_log_fzf
}

_gy() {
  is_in_git_repo || return
  git reflog --date=relative --color=always |
  _git_log_fzf
}

_gr() {
  is_in_git_repo || return
  git remote -v | awk '{print $1 "\t" $2}' | uniq |
  fzf_down --tac \
    --preview 'git log --oneline --graph --date=short --pretty="format:%C(auto)%cd %h%d %s" {1}' |
  cut -d$'\t' -f1
}

_gs() {
  is_in_git_repo || return
  git stash list | fzf_down --reverse -d: \
    --preview-window=right,70% \
    --preview 'DFT_COLOR=always DFT_DISPLAY=inline git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always {1} --ext-diff' |
  cut -d: -f1
}
