[ -n "$PYENV_DEBUG" ] && set -x
export PYENV_ROOT="/Users/hojin/.dotfiles/python/pyenv"
program="$("/Users/hojin/.dotfiles/python/pyenv/libexec/pyenv" which "${BASH_SOURCE##*/}")"
if [ -e "${program}" ]; then
  . "${program}" "$@"
fi
