# History — replaces zprezto 'history' module + zshrc history config

HISTFILE="${HISTFILE:-${ZDOTDIR:-$HOME}/.zhistory}"
HISTSIZE=10000000
SAVEHIST=10000000
HISTORY_IGNORE="(ls|l|la|lal|ll|lla|ls|sl|cd|pwd|exit) *"
HIST_STAMPS="yyyy-mm-dd"

setopt BANG_HIST              # ! expansion (e.g. !! for last command)
setopt EXTENDED_HISTORY       # save timestamps and duration
setopt INC_APPEND_HISTORY     # write to history file immediately, not on exit
setopt APPEND_HISTORY         # append rather than overwrite
setopt SHARE_HISTORY          # share history across all sessions in real time
setopt HIST_EXPIRE_DUPS_FIRST # expire duplicates first when trimming
setopt HIST_IGNORE_DUPS       # don't record consecutive duplicates
setopt HIST_IGNORE_ALL_DUPS   # remove older duplicate when new one is added
setopt HIST_FIND_NO_DUPS      # skip duplicates when searching
setopt HIST_SAVE_NO_DUPS      # don't write duplicates to file
setopt HIST_VERIFY            # show expansion before executing (e.g. !!)
setopt HIST_NO_STORE          # don't store history/fc commands themselves
setopt HIST_REDUCE_BLANKS     # trim extra whitespace
setopt HIST_BEEP              # beep at end of history
unsetopt HIST_IGNORE_SPACE    # DO record commands starting with space

alias history-stat="history 0 | awk '{print \$2}' | sort | uniq -c | sort -n -r | head"
