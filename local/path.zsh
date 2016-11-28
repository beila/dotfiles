LOCAL_ROOT=$HOME/local

if [[ -d $LOCAL_ROOT ]]
then
  for src in $(find -L "$LOCAL_ROOT" -maxdepth 1 -type d) $(find -L "$LOCAL_ROOT" -maxdepth 2 -name 'bin' -type d)
  do
    export PATH=$PATH:$src
  done
fi
