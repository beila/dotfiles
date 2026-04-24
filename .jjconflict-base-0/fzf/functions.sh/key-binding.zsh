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
    eval "bindkey -M viins '^g^$c' fzf-g$c-widget"
    eval "bindkey -M vicmd '^g^$c' fzf-g$c-widget"
  done
} f b t r y h s
bindkey -M viins '^g' undefined-key
bindkey -M vicmd '^g' undefined-key

() {
  local c
  for c in $@; do
    eval "fzf-g$c$c-widget() { local result=\$(_g$c$c | join-lines); zle reset-prompt; LBUFFER+=\$result }"
    eval "zle -N fzf-g$c$c-widget"
    eval "bindkey -M viins '^g$c' fzf-g$c$c-widget"
    eval "bindkey -M vicmd '^g$c' fzf-g$c$c-widget"
  done
} b h y

# Ctrl-F: file browser with tracked/all toggle
fzf-file-browse-widget() { local result=$(_file_browse | join-lines); zle reset-prompt; LBUFFER+=$result }
zle -N fzf-file-browse-widget
bindkey -M viins '^f' fzf-file-browse-widget
bindkey -M vicmd '^f' fzf-file-browse-widget
