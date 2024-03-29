join-lines() {
  local item
  while read item; do
    echo -n "${(q-)item} "
  done
}

() {
  local c
  for c in $@; do
    eval "fzf-g$c-widget() { local result=\$(_g$c | join-lines); zle reset-prompt; LBUFFER+=\$result }"
    eval "zle -N fzf-g$c-widget"
    eval "bindkey '^g^$c' fzf-g$c-widget"
  done
} f b t r y h s

() {
  local c
  for c in $@; do
    eval "fzf-g$c$c-widget() { local result=\$(_g$c$c | join-lines); zle reset-prompt; LBUFFER+=\$result }"
    eval "zle -N fzf-g$c$c-widget"
    eval "bindkey '^g$c' fzf-g$c$c-widget"
  done
} b h y