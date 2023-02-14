#!env zsh
which git.exe 2> /dev/null 1>&2
if [ "$?" -eq 0 ]
then
    setx.exe GIT_SSH 'C:\Windows\System32\OpenSSH\ssh.exe' > /dev/null
    function git() {
        #rm -v $(wslpath "$(git.exe rev-parse --git-dir)/index.lock") 1>&2
        git.exe "$@"
    }
fi

