local funcdir=$(dirname $(readlink -f $0))/functions

fpath=($funcdir $fpath)

for ff in $(cd $funcdir;ls *)
do
	unhash -f ${ff} 2> /dev/null
	unhash -a ${ff} 2> /dev/null
	autoload ${ff}
done

# refer to smart_sudo in http://zshwiki.org/home/examples/functions
#alias fa='_fa '
for ff in $(cd $funcdir;ls _*)
do
	unhash -af ${ff#_} 2> /dev/null
	alias ${ff#_}="${ff} "
done

