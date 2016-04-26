local funcdir=$(dirname $(readlink -f $0))/functions

fpath=($funcdir $fpath)

for ff in $(cd $funcdir;ls *)
do
	unalias ${ff}
	unfunction ${ff}
	autoload ${ff}
done

# refer to smart_sudo in http://zshwiki.org/home/examples/functions
#alias fa='_fa '
for ff in $(cd $funcdir;ls _*)
do
	alias ${ff#_}="${ff} "
done

