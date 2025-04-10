#!/usr/bin/env bash

BREW=$(which brew 2> /dev/null)
if [ "$BREW" == "" ]
then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

function install_if_missing(){
    for p in "$@"
    do
        which "$p" > /dev/null 2>&1 ||
            $BREW install "$p"
    done
}

install_if_missing zsh
$BREW install coreutils screen ripgrep fzf bat git-subrepo zoxide neovim just eza difftastic fd broot dust glow feedgnuplot neovide spacer
#$BREW install exa fasd

if [ "$(uname -s)" == "Darwin" ]
then
    #$BREW install homebrew/cask-drivers/kensington-trackball-works
    $BREW install iterm2 quicksilver karabiner-elements
    #$BREW install vivaldi clion
fi

# brew info fzf
#$($BREW --prefix fzf)/install

#$BREW tap homebrew/versions

# gcc is needed because of https://github.com/Linuxbrew/linuxbrew/issues/732#issuecomment-192697040
#$BREW install gcc47 cmake
