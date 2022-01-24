LOCAL_ROOTS=($HOME/local $HOME/.local ${DOTFILES_ROOT})

for local_root in $LOCAL_ROOTS
do
    if [[ -d $local_root ]]
    then
        for dir in $(find -L "$local_root" -maxdepth 1 -type d) $(find -L "$local_root" -maxdepth 2 -name 'bin' -type d)
        do
            path=($dir ${(@)path:#$dir})
        done
    fi
done
