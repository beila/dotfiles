for brew_path in /home/linuxbrew/.linuxbrew  $HOME/.linuxbrew
do
    if [[ -d ${brew_path} ]]
    then
        local dir=${brew_path}/sbin
        path=($dir ${(@)path:#$dir})
        dir=${brew_path}/bin
        path=($dir ${(@)path:#$dir})

        dir=${brew_path}/share/man
        #manpath=($dir ${(@)manpath:#$dir})

        dir=${brew_path}/share/info
        export INFOPATH=$dir:${INFOPATH://$dir:}
    fi
done

# brew info coreutils
local dir=/usr/local/opt/coreutils/libexec/gnubin 
if [[ -d $dir ]]
then
    path=($dir ${(@)path:#$dir})
fi

# brew info coreutils
#local dir=/usr/local/opt/coreutils/libexec/gnuman
#if [[ -d $dir ]]
#then
    #manpath=($dir ${(@)manpath:#$dir})
#fi

# brew info curl
#local DIR=/usr/local/opt/curl/bin
#export PATH=${DIR}:${PATH//${DIR}:}
# brew curl doesn't support kerberos
