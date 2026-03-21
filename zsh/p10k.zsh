# Prompt — replaces zprezto 'prompt' module
# Load zsh prompt system and activate powerlevel10k
autoload -Uz promptinit && promptinit
prompt powerlevel10k
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
