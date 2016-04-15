_fa() {
	local TARGETS=${FA_TARGETS:-$(find . -mindepth 1 -maxdepth 1 -type d)}
	local TARGET
	# turning on SH_WORD_SPLIT as http://zsh.sourceforge.net/FAQ/zshfaq03.html
	for TARGET in ${=TARGETS}
	do
		echo "$TARGET:"
		(cd $TARGET; "$@")
		echo
	done
}
# refer to smart_sudo in http://zshwiki.org/home/examples/functions
alias fa='_fa '

fad () {
	if (( $# == 0 ))
	then
		export FA_TARGETS=
	else
		export FA_TARGETS=$(find "$@" -maxdepth 0 -type d -print0|xargs -0r readlink -f) 
	fi
	echo "FA_TARGETS=${FA_TARGETS}"
}
