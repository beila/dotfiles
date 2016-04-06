if [[ -d .linuxbrew ]]
then
	export PATH=$HOME/.linuxbrew/sbin:${PATH//$HOME\/.linuxbrew\/sbin}
	export PATH=$HOME/.linuxbrew/bin${PATH//$HOME\/.linuxbrew\/bin}
	export MANPATH=$HOME/.linuxbrew/share/man:${MANPATH://$HOME\/.linuxbrew\/share\/man}
	export INFOPATH=$HOME/.linuxbrew/share/info:${INFOPATH://$HOME\/.linuxbrew\/share\/info}
fi
