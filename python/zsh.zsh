# brew info pyenv-virtualenv
if which pyenv-virtualenv-init > /dev/null; then eval "$(pyenv virtualenv-init -)"; fi

# https://stackoverflow.com/a/31116425
if [ -d "/Library/Python/2.7/site-packages" ]
then
	export PYTHONPATH="/Library/Python/2.7/site-packages:$PYTHONPATH"
fi

