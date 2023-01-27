# GIT heart FZF
# -------------

is_in_git_repo() {
  git rev-parse HEAD > /dev/null 2>&1
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
_gf_get_file() {
    _gf_remove_status | _gf_remove_original_name | _gf_remove_quote
}

_gf() {
  is_in_git_repo || return
# shellcheck disable=SC2016
  git -c color.status=always status --ignore-submodules="${_git_status_ignore_submodules}" --short |
  fzf_down -m --ansi --nth 2..,.. \
  --preview "$(functions _gf_remove_status _gf_remove_original_name _gf_remove_quote _gf_get_file)"'
    file=$(_gf_get_file <<< {})
    diff=$(git diff --color=always --cached HEAD -- "$file" | sed 1,4d
           git diff --color=always -- "$file" | sed 1,4d)
    if [[ "$diff" ]]; then echo "$diff"
    else; bat "$file" 2>/dev/null || cat "$file" 2>/dev/null || ls -l --color=always "$file" ; fi' |
  _gf_get_file
}

_gb() {
  is_in_git_repo || return
# shellcheck disable=SC2016
  git branch -a --color=always | grep -v '/HEAD\s' | sort |
  fzf_down --ansi --multi --tac --preview-window right:70% \
    --preview 'git log --oneline --graph --date=short --color=always --pretty="format:%C(auto)%cd %h%d %s" $(sed s/^..// <<< {} | cut -d" " -f1)' |
  sed 's/^..//' | cut -d' ' -f1 |
  sed 's#^remotes/##'
}

_gbb() {
  is_in_git_repo || return
  git worktree list |
    fzf |
    cut -d' ' -f1
}

_gt() {
  is_in_git_repo || return
  git tag --sort -version:refname |
  fzf_down --multi --preview-window right:70% \
    --preview 'git show --patch-with-stat --color=always {}'
}

_gh() {
  is_in_git_repo || return
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always |
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
}

_ghh() {
  is_in_git_repo || return
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always --all |
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
}

_gy() {
  is_in_git_repo || return
  git reflog --color=always |
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
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
  git stash list | fzf_down --reverse -d: --preview 'git show --patch-with-stat --color=always {1}' |
  cut -d: -f1
}
