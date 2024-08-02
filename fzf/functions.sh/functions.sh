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
_gf_show_diff() {
    DFT_COLOR=always DFT_DISPLAY=inline git diff --color=always --cached HEAD "$@"
    DFT_COLOR=always DFT_DISPLAY=inline git diff --color=always "$@"
}
_gf_get_file() {
    _gf_remove_status | _gf_remove_original_name | _gf_remove_quote
}

_gf() {
  is_in_git_repo || return
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
# shellcheck disable=SC2016
  git worktree list |
      fzf_down --ansi --multi --tac --preview-window right:70% \
          --preview 'git -C $(awk "{print \$1}" <<< {}) diff --stat --color=always
            git log --oneline --graph --date=short --color=always --pretty="format:%C(auto)%cd %h%d %s" $(awk "{print \$2}" <<< {})' |
      cut -d' ' -f1
}

_gt() {
  is_in_git_repo || return
  git tag --sort -version:refname |
  fzf_down --multi --preview-window right:70% \
    --preview 'git show --remerge-diff --patch-with-stat --color=always {}'
}

_gh() {
  is_in_git_repo || return
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always |
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --remerge-diff --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
}

_gyy() {
  is_in_git_repo || return
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always --all |
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --remerge-diff --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
}

_ghh() {
  is_in_git_repo || return
  all_parents_of_merge_base="$(gmb HEAD "@{u}")^@"
  # Exclude (^ prefix) all parents of the merge-base between HEAD and upstream
  # leaving HEAD, upstream head and the merge-base, inclusively.
  git log --date=short --format="%C(green)%C(bold)%cd %C(auto)%h%d %s (%an)" --graph --color=always HEAD "@{u}" "^${all_parents_of_merge_base}"|
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --remerge-diff --patch-with-stat --color=always' |
  grep -o "[a-f0-9]\{7,\}" |
  head -1
}

_gy() {
  is_in_git_repo || return
  git reflog --color=always |
  fzf_down --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
    --header 'Press CTRL-S to toggle sort' \
    --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs git show --remerge-diff --patch-with-stat --color=always' |
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
  git stash list | fzf_down --reverse -d: \
    --preview-window=right,70% \
    --preview 'DFT_COLOR=always DFT_DISPLAY=inline git show --remerge-diff --patch-with-stat --color=always {1} --ext-diff' |
  cut -d: -f1
}
