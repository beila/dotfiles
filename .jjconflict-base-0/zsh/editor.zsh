# Based on zprezto modules/editor/init.zsh
#
# Sets key bindings.
#
# Original authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

[[ "$TERM" == 'dumb' ]] && return

setopt BEEP  # beep on error in line editor

# Word characters for vi word motions
WORDCHARS='*?_-.[]~&;!#$%^(){}<>'

# Vi mode
bindkey -v

# Terminal application mode (makes terminfo keys work in ZLE)
zmodload zsh/terminfo
function zle-line-init {
  (( $+terminfo[smkx] )) && echoti smkx
}
function zle-line-finish {
  (( $+terminfo[rmkx] )) && echoti rmkx
}
zle -N zle-line-init
zle -N zle-line-finish

# Edit command in external editor
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd '^X^E' edit-command-line

# Undo/redo
bindkey -M vicmd 'u' undo
bindkey -M viins '^_' undo
bindkey -M vicmd '^R' redo

# History search
bindkey -M vicmd '?' history-incremental-pattern-search-backward
bindkey -M vicmd '/' history-incremental-pattern-search-forward

# Home/End in all modes
bindkey -M viins "$terminfo[khome]" beginning-of-line
bindkey -M vicmd "$terminfo[khome]" beginning-of-line
bindkey -M viins "$terminfo[kend]" end-of-line
bindkey -M vicmd "$terminfo[kend]" end-of-line

# Insert/Delete/Backspace in insert mode
bindkey -M viins "$terminfo[kich1]" overwrite-mode
bindkey -M viins "$terminfo[kdch1]" delete-char
bindkey -M viins '^?' backward-delete-char
bindkey -M vicmd "$terminfo[kdch1]" delete-char

# Arrow keys
bindkey -M viins "$terminfo[kcub1]" backward-char
bindkey -M viins "$terminfo[kcuf1]" forward-char

# Ctrl+Left/Right word movement
bindkey -M viins '\e[1;5D' vi-backward-word
bindkey -M viins '\e[1;5C' vi-forward-word
bindkey -M vicmd '\e[1;5D' vi-backward-word
bindkey -M vicmd '\e[1;5C' vi-forward-word

# Shift+Tab: reverse menu complete
bindkey -M viins "$terminfo[kcbt]" reverse-menu-complete

# Space: expand history
bindkey -M viins ' ' magic-space

# Ctrl+L: clear screen
bindkey -M viins '^L' clear-screen

# Ctrl+Q: push line (type another command, then return to this one)
bindkey -M viins '^Q' push-line-or-edit

# Expand .... to ../..
function expand-dot-to-parent-directory-path {
  if [[ $LBUFFER = *.. ]]; then
    LBUFFER+='/..'
  else
    LBUFFER+='.'
  fi
}
zle -N expand-dot-to-parent-directory-path
bindkey -M viins '.' expand-dot-to-parent-directory-path
bindkey -M isearch '.' self-insert 2>/dev/null  # don't expand during search

# vim-surround: cs'" ds" ys"
autoload -Uz surround
zle -N delete-surround surround
zle -N add-surround surround
zle -N change-surround surround
bindkey -M vicmd cs change-surround
bindkey -M vicmd ds delete-surround
bindkey -M vicmd ys add-surround
bindkey -M visual S add-surround

# Text objects: ci" da( etc.
autoload -Uz select-bracketed select-quoted
zle -N select-bracketed
zle -N select-quoted
for m in viopp visual; do
  for c in {a,i}${(s..)^:-'()[]{}<>bB'}; do
    bindkey -M $m $c select-bracketed
  done
  for c in {a,i}${(s..)^:-\'\"\`}; do
    bindkey -M $m $c select-quoted
  done
done
