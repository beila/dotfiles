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
    jj --quiet diff --stat --color=always 2>/dev/null |
      fzf_down -m --ansi \
        --preview 'file=$(awk "{print \$1}" <<< {}); jj --quiet diff --color=always -- "$file"' |
      awk '{print $1}'
    return
  fi
  if is_in_git_repo; then
# shellcheck disable=SC2016,SC2154
  git -c color.status=always status --ignore-submodules="${_git_status_ignore_submodules}" --short |
    fzf_down -m --ansi --nth 2..,.. \
      --preview-window=right,70% \
      --preview "$(functions _gf_remove_status _gf_remove_original_name _gf_remove_quote _gf_show_diff _gf_get_file)"'
        file=$(_gf_get_file <<< {})
        if [[ "$(_gf_show_diff --no-ext-diff "$file")" ]]; then _gf_show_diff "$file"
        else; bat "$file" 2>/dev/null || cat "$file" 2>/dev/null || ls -l --color=always "$file" ; fi' |
    _gf_get_file
  fi
}

_gb() {
  if is_in_jj_repo; then
    jj --quiet bookmark list --all-remotes --color=always 2>/dev/null |
      fzf_down --ansi --multi --preview-window right:70% \
        --preview 'jj --quiet log --color=always -r "$(awk "{print \$1}" <<< {})"' |
      awk '{print $1}'
    return
  fi
  if is_in_git_repo; then
# shellcheck disable=SC2016
  git branch -a --color=always | grep -v '/HEAD\s' | sort |
  fzf_down --ansi --multi --tac --preview-window right:70% \
    --preview 'git log --oneline --graph --date=short --color=always --pretty="format:%C(auto)%cd %h%d %s" $(sed s/^..// <<< {} | cut -d" " -f1)' |
  sed 's/^..//' | cut -d' ' -f1 |
  sed 's#^remotes/##'
  fi
}

_gbb() {
  if is_in_jj_repo; then
    jj --quiet workspace list --color=always 2>/dev/null |
      fzf_down --ansi --multi --preview-window right:70% \
        --preview 'jj --quiet log --color=always -r "$(cut -d: -f1 <<< {})"' |
      cut -d: -f1
    return
  fi
  if is_in_git_repo; then
# shellcheck disable=SC2016
  git worktree list |
      fzf_down --ansi --multi --tac --preview-window right:70% \
          --preview 'git -C $(awk "{print \$1}" <<< {}) diff --stat --color=always
            git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%d %s (%an)" --color=always "$(awk "{print \$2}" <<< {})" "^$(git merge-base "$(awk "{print \$2}" <<< {})" "origin/HEAD")^@"' |
      cut -d' ' -f1
  fi
}

_gt() {
  if is_in_jj_repo; then
    jj --quiet tag list --color=always 2>/dev/null |
      fzf_down --ansi --multi --preview-window right:70% \
        --preview 'jj --quiet show --color=always "$(awk "{print \$1}" <<< {})"' |
      awk '{print $1}'
    return
  fi
  if is_in_git_repo; then
  git tag --sort -version:refname |
  fzf_down --multi --preview-window right:70% \
    --preview 'git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always {}'
  fi
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
    --preview 'grep -o "[a-z]\{8,\}" <<< {} | head -1 | xargs -I% jj --quiet show --color=always %' |
  grep -o "[a-z]\{8,\}" | head -1
}

_gh() {
  if is_in_jj_repo; then
    jj --quiet log --color=always -T 'builtin_log_oneline' 2>/dev/null | _jj_log_fzf
    return
  fi
  if is_in_git_repo; then
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always |
  _git_log_fzf
  fi
}

_gyy() {
  if is_in_jj_repo; then
    jj --quiet log --color=always -T 'builtin_log_oneline' -r 'all()' 2>/dev/null | _jj_log_fzf
    return
  fi
  if is_in_git_repo; then
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always --all |
  _git_log_fzf
  fi
}

_ghh() {
  if is_in_jj_repo; then
    jj --quiet log --color=always -T 'builtin_log_oneline' -r '::@ & ::remote_bookmarks()' 2>/dev/null | _jj_log_fzf
    return
  fi
  if is_in_git_repo; then
  git rev-parse "@{u}" || { echo "No upstream"; return }
  all_parents_of_merge_base="$(git merge-base HEAD "@{u}")^@"
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always HEAD "@{u}" "^${all_parents_of_merge_base}"|
  _git_log_fzf
  fi
}

_gy() {
  if is_in_jj_repo; then
    jj --quiet operation log --no-graph --color=always -T 'self.time().start().ago() ++ " " ++ self.tags().first_line().remove_prefix("args: ") ++ " " ++ self.id().short() ++ "\n"' 2>/dev/null |
      fzf_down --ansi --no-sort --reverse --multi \
        --preview 'grep -o "[0-9a-f]\{12,\}" <<< {} | tail -1 | xargs -I% jj --quiet operation show --color=always %' |
      grep -o "[0-9a-f]\{12,\}" | tail -1
    return
  fi
  if is_in_git_repo; then
  git reflog --date=relative --color=always |
  _git_log_fzf
  fi
}

_gr() {
  if is_in_jj_repo; then
    jj --quiet git remote list 2>/dev/null |
      fzf_down --tac \
        --preview 'jj --quiet log --color=always -r "remote_bookmarks(exact:$(awk "{print \$1}" <<< {}))"' |
      awk '{print $1}'
    return
  fi
  if is_in_git_repo; then
  git remote -v | awk '{print $1 "\t" $2}' | uniq |
  fzf_down --tac \
    --preview 'git log --oneline --graph --date=short --pretty="format:%C(auto)%cd %h%d %s" {1}' |
  cut -d$'\t' -f1
  fi
}

_gs() {
  if is_in_git_repo; then
  git stash list | fzf_down --reverse -d: \
    --preview-window=right,70% \
    --preview 'DFT_COLOR=always DFT_DISPLAY=inline git show --abbrev-commit --decorate --remerge-diff --patch-with-stat --color=always {1} --ext-diff' |
  cut -d: -f1
  fi
}
