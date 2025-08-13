local dir=node_modules/.bin
path=($dir ${(@)path:#$dir})
local dir=.npm/bin
path=($dir ${(@)path:#$dir})
