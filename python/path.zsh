local dir=venv/bin
path=($dir ${(@)path:#$dir})
dir=venv/Scripts
path=($dir ${(@)path:#$dir})
