# Syntax highlighting — replaces zprezto 'syntax-highlighting' module
# Wraps zsh-syntax-highlighting plugin (installed via nix)

source ~/.nix-profile/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh || return

ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern line root)

ZSH_HIGHLIGHT_STYLES[builtin]='bg=blue'
ZSH_HIGHLIGHT_STYLES[command]='bg=blue'
ZSH_HIGHLIGHT_STYLES[function]='bg=blue'

ZSH_HIGHLIGHT_PATTERNS['rm*-rf*']='fg=white,bold,bg=red'
