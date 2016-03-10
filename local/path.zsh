LOCAL_ROOT=$HOME/local

if [[ -d $LOCAL_ROOT ]]
then
  for src in $(find -H "$LOCAL_ROOT" -maxdepth 2 -name 'bin' -type d)
  do
    export PATH=$PATH:$src
  done
fi
