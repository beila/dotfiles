LOCAL_ROOTS=($HOME/local $HOME/.local ${DOTFILES_ROOT})

for local_root in $LOCAL_ROOTS
do
    if [[ -d $local_root ]]
    then
        for dir in $(find -L "$local_root" -maxdepth 1 -type d) $(find -L "$local_root" -maxdepth 3 -name 'bin' -type d)
        do
            path=($dir ${(@)path:#$dir})
        done
        for dir in $(find -L "$local_root" -maxdepth 3 -name 'man' -type d)
        do
            #manpath=($dir ${(@)manpath:#$dir})
        done
    fi
done
