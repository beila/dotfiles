local funcdir=$(dirname $(readlink -f $0))/functions

fpath=($funcdir $fpath)

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

