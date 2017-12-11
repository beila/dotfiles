unalias run-help 2> /dev/null
autoload run-help
HELPDIR=/usr/local/share/zsh/help

# brew info nvm
local NVM_DIR="$HOME/.nvm"
test -d $NVM_DIR && export NVM_DIR
local NVM_SOURCE="/home/linuxbrew/.linuxbrew/opt/nvm/nvm.sh"
test -d $NVM_SOURCE && source $NVM_SOURCE
