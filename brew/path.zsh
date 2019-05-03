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
	export PATH=$BREWPATH/sbin:${PATH//$BREWPATH\/sbin:}
	export PATH=$BREWPATH/bin:${PATH//$BREWPATH\/bin:}
	export MANPATH=$BREWPATH/share/man:${MANPATH://$BREWPATH\/share\/man:}
	export INFOPATH=$BREWPATH/share/info:${INFOPATH://$BREWPATH\/share\/info:}
fi

# brew info coreutils
local DIR=/usr/local/opt/coreutils/libexec/gnubin 
if [[ -d $DIR ]]
then
	export PATH=$DIR:${PATH//$DIR:}
fi

# brew info coreutils
local DIR=/usr/local/opt/coreutils/libexec/gnuman
if [[ -d $DIR ]]
then
    export MANPATH=$DIR:${MANPATH//$DIR:}
fi

# brew info curl
#local DIR=/usr/local/opt/curl/bin
#export PATH=${DIR}:${PATH//${DIR}:}
# brew curl doesn't support kerberos
