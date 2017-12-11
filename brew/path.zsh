if [[ -d $HOME/.linuxbrew ]]
then
	export PATH=$HOME/.linuxbrew/sbin:${PATH//$HOME\/.linuxbrew\/sbin:}
	export PATH=$HOME/.linuxbrew/bin:${PATH//$HOME\/.linuxbrew\/bin:}
	export MANPATH=$HOME/.linuxbrew/share/man:${MANPATH://$HOME\/.linuxbrew\/share\/man:}
	export INFOPATH=$HOME/.linuxbrew/share/info:${INFOPATH://$HOME\/.linuxbrew\/share\/info:}
fi

if [[ -d /home/linuxbrew/.linuxbrew ]]
then
	BREWPATH=$(cd /home/linuxbrew/.linuxbrew && pwd)
	echo "==========================${BREWPATH}==----------------------"
	export PATH=$BREWPATH/sbin:${PATH//$BREWPATH\/sbin:}
	echo "==========================${PATH}==----------------------"
	export PATH=$BREWPATH/bin:${PATH//$BREWPATH\/bin:}
	export MANPATH=$BREWPATH/share/man:${MANPATH://$BREWPATH\/share\/man:}
	export INFOPATH=$BREWPATH/share/info:${INFOPATH://$BREWPATH\/share\/info:}
fi

# brew info coreutils
if [[ -d /usr/local/opt/coreutils/libexec/gnubin ]]
then
	PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
fi

# brew info coreutils
if [[ -d /usr/local/opt/coreutils/libexec/gnuman ]]
then
    MANPATH="/usr/local/opt/coreutils/libexec/gnuman:$MANPATH"
fi

