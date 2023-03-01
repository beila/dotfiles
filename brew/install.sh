#!/usr/bin/env bash

BREW=$(which brew 2> /dev/null)
if [ "$?" -ne 0 ]
then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

for f in /home/linuxbrew/.linuxbrew/bin $HOME/.linuxbrew/bin; do
    if [[ -x $f/brew ]]; then
        BREW=${BREW:-$f/brew}
        mkdir -p $HOME/local
        ln -sf $f/.. $HOME/local/linuxbrew
		break
    fi
done

if [ "$(uname -s)" == "Darwin" ]
then
    $BREW install coreutils
    #$BREW install homebrew/cask-drivers/kensington-trackball-works
    $BREW install iterm2 quicksilver karabiner-elements
    $BREW install vivaldi clion
fi

which zsh 2>&1 > /dev/null || $BREW install zsh
which screen 2>&1 > /dev/null || $BREW install screen
$BREW install ripgrep fzf git-delta bat exa broot

# brew info fzf
#$($BREW --prefix fzf)/install

#$BREW tap homebrew/versions

# gcc is needed because of https://github.com/Linuxbrew/linuxbrew/issues/732#issuecomment-192697040
#$BREW install gcc47 cmake
