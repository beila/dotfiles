#!/usr/bin/env bash

BREW=$(which brew 2> /dev/null)
if [ "$?" -ne 0 ]
then
  if [ "$(uname -s)" == "Linux" ]
  then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/linuxbrew/go/install)"
  fi
fi

for f in $HOME/.linuxbrew/bin; do
    if [[ -d $f/brew ]]; then
        BREW=${BREW:-$f/brew}
    fi
done

# gcc is needed because of https://github.com/Linuxbrew/linuxbrew/issues/732#issuecomment-192697040
$BREW install gcc cmake make

