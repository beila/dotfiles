#!env zsh
which git.exe 2> /dev/null 1>&2
if [ "$?" -eq 0 ]
then
    function git() {git.exe "$@"}
fi

