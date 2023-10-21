#source ${DOTFILES_ROOT}/git/git-subrepo/.rc

local dir=${DOTFILES_ROOT}/git/git-subrepo/lib
path=(${(@)path:#$dir} $dir)
local dir=${DOTFILES_ROOT}/git/git-subrepo/man
#manpath=(${(@)manpath:#$dir} $dir)
