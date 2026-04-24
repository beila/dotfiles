# From zprezto modules/utility/init.zsh (partial)
#
# Defines general aliases and functions.
#
# Authors:
#   Robby Russell <robby@planetargon.com>
#   Suraj N. Kurapati <sunaku@gmail.com>
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

#
# Helper functions (from zprezto modules/helper/init.zsh)
#

function is-callable { (( $+commands[$1] || $+functions[$1] || $+aliases[$1] || $+builtins[$1] )) }
function is-darwin { [[ "$OSTYPE" == darwin* ]] }
function is-linux { [[ "$OSTYPE" == linux* ]] }
function is-bsd { [[ "$OSTYPE" == *bsd* ]] }

#
# Correction
#

setopt CORRECT

# Disable correction for commands where it's annoying.
alias ack='nocorrect ack'
alias cd='nocorrect cd'
alias cp='nocorrect cp'
alias gcc='nocorrect gcc'
alias grep='nocorrect grep'
alias ln='nocorrect ln'
alias man='nocorrect man'
alias mkdir='nocorrect mkdir'
alias mv='nocorrect mv'
alias rm='nocorrect rm'

# Disable globbing for commands that do their own.
alias fc='noglob fc'
alias find='noglob find'
alias history='noglob history'
alias locate='noglob locate'
alias rsync='noglob rsync'
alias scp='noglob scp'

#
# ls
#

if is-callable 'dircolors'; then
  # GNU Core Utilities
  alias ls="${aliases[ls]:-ls} --group-directories-first"

  if [[ -z "$LS_COLORS" ]]; then
    if [[ -s "$HOME/.dir_colors" ]]; then
      eval "$(dircolors --sh "$HOME/.dir_colors")"
    else
      eval "$(dircolors --sh)"
    fi
  fi

  alias ls="${aliases[ls]:-ls} --color=auto"
else
  # BSD Core Utilities
  if [[ -z "$LSCOLORS" ]]; then
    export LSCOLORS='exfxcxdxbxGxDxabagacad'
  fi
  if [[ -z "$LS_COLORS" ]]; then
    export LS_COLORS='di=34:ln=35:so=32:pi=33:ex=31:bd=36;01:cd=33;01:su=31;40;07:sg=36;40;07:tw=32;40;07:ow=33;40;07:'
  fi

  alias ls="${aliases[ls]:-ls} -G"
fi

alias l='ls -1A'         # Lists in one column, hidden files.
alias ll='ls -lh'        # Lists human readable sizes.
alias lr='ll -R'         # Lists human readable sizes, recursively.
alias la='ll -A'         # Lists human readable sizes, hidden files.
alias lm='la | "$PAGER"' # Lists human readable sizes, hidden files through pager.
alias lx='ll -XB'        # Lists sorted by extension (GNU only).
alias lk='ll -Sr'        # Lists sorted by size, largest last.
alias lt='ll -tr'        # Lists sorted by date, most recent last.
alias lc='lt -c'         # Lists sorted by date, most recent last, shows change time.
alias lu='lt -u'         # Lists sorted by date, most recent last, shows access time.
alias sl='ls'            # I often screw this up.

#
# Grep
#

export GREP_COLOR='37;45'           # BSD.
export GREP_COLORS="mt=$GREP_COLOR" # GNU.
alias grep="${aliases[grep]:-grep} --color=auto"
