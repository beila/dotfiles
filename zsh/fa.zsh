export FA_TARGETS=${FA_TARGETS:-${HOME}}
function _fa() {
	local TARGET
	# turning on SH_WORD_SPLIT as http://zsh.sourceforge.net/FAQ/zshfaq03.html
	for TARGET in ${=FA_TARGETS}
	do
		echo "$TARGET:"
		(cd $TARGET; "$@")
		echo
	done
}
# refer to smart_sudo in http://zshwiki.org/home/examples/functions
alias fa='_fa '
