local funcdir=$(dirname $(readlink -f $0))/functions

fpath=($funcdir $fpath)

# refer to smart_sudo in http://zshwiki.org/home/examples/functions
#alias fa='_fa '
for ff in $(cd $funcdir;ls _*)
do
	autoload ${ff}
	alias ${ff#_}="${ff} "
done

