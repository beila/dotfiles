local dir=$(dirname $(readlink -f $0))
path=(${(@)path:#$dir} $dir)
