set -x
(which just >& /dev/null && test -f $HOME/.justfile) && eval $(just setup_shell)
set +x
