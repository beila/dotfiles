#!/usr/bin/env bash

BREW=$(which brew 2> /dev/null)
if [ "$?" -ne 0 ]
then
  if [ "$(uname -s)" == "Linux" ]
  then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/linuxbrew/go/install)"
  fi
fi

for f in /home/linuxbrew/.linuxbrew/bin $HOME/.linuxbrew/bin; do
    if [[ -x $f/brew ]]; then
        BREW=${BREW:-$f/brew}
		break
    fi
done

if [ "$(uname -s)" == "Darwin" ]
    $BREW install coreutils
    $BREW install homebrew/cask-drivers/kensington-trackball-works
    $BREW cask install iterm2 quicksilver karabiner-elements
fi

$BREW cask install vivaldi clion

#$BREW tap homebrew/versions

# gcc is needed because of https://github.com/Linuxbrew/linuxbrew/issues/732#issuecomment-192697040
#$BREW install gcc47 cmake
