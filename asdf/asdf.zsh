ASDF_FORCE_PREPEND=yes
[ -s "/home/linuxbrew/.linuxbrew/opt/asdf/libexec/asdf.sh" ] && . "/home/linuxbrew/.linuxbrew/opt/asdf/libexec/asdf.sh"
[ -s "/usr/local/opt/asdf/libexec/asdf.sh" ] && . "/usr/local/opt/asdf/libexec/asdf.sh"

# I need venv before asdf
. $(dirname "$0")/../python/path.zsh
