local funcdir=$(dirname $(readlink -f $0))/functions
local exafuncdir=$(dirname $(readlink -f $0))/exa_functions

fpath=($exafuncdir $funcdir $fpath)

for ff in $(cd $funcdir;ls *)
do
	unhash -f ${ff} 2> /dev/null
	unhash -a ${ff} 2> /dev/null
	autoload ${ff}
done

# refer to smart_sudo in http://zshwiki.org/home/examples/functions
#alias fa='aliased_fa '
for ff in $(cd $funcdir;ls aliased_*)
do
	unhash -af ${ff#aliased_} 2> /dev/null
	alias ${ff#aliased_}="${ff} "
done

local EZA=$(which eza 2> /dev/null)
if [[ -x ${EZA} ]]
then
    for ff in $(cd $exafuncdir;ls *)
    do
        unhash -f ${ff} 2> /dev/null
        unhash -a ${ff} 2> /dev/null
        autoload ${ff}
    done

fi
