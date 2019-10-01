set -x
LOCAL_ROOTS=($HOME/local $HOME/.local)

for local_root in $LOCAL_ROOTS
do
    if [[ -d $local_root ]]
    then
        for src in $(find -L "$local_root" -maxdepth 1 -type d) $(find -L "$local_root" -maxdepth 2 -name 'bin' -type d)
        do
            export PATH=:${src}:${PATH//:${src}:}
        done
    fi
done
set +x
