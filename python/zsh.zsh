# https://github.com/pyenv/pyenv#basic-github-checkoutn
export PYENV_ROOT="${DOTFILES_ROOT}/python/pyenv"
local dir=${DOTFILES_ROOT}/python/pyenv/bin
path=($dir ${(@)path:#$dir})

if command -v pyenv 1>/dev/null 2>&1; then
	eval "$(pyenv init -)"
fi

# https://github.com/pyenv/pyenv-virtualenv#installing-as-a-pyenv-plugin
eval "$(pyenv virtualenv-init -)"

# https://stackoverflow.com/a/31116425
if [ -d "/Library/Python/2.7/site-packages" ]
then
	export PYTHONPATH="/Library/Python/2.7/site-packages:$PYTHONPATH"
fi
