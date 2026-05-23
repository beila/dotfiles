# From zprezto modules/completion/init.zsh
#
# Sets completion options.
#
# Authors:
#   Robby Russell <robby@planetargon.com>
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Return if requirements are not found.
if [[ "$TERM" == 'dumb' ]]; then
  return 1
fi

# Add zsh-completions to $fpath (installed via nix).
# Also add nix's own completions (for the `nix` command) from its store path.
local _nix_zsh="$(readlink -f "$(whence -p nix)")"; _nix_zsh="${_nix_zsh%/bin/nix}/share/zsh/site-functions"
fpath=(~/.nix-profile/share/zsh/site-functions ${_nix_zsh:+$_nix_zsh} $fpath)

#
# Options
#

setopt COMPLETE_IN_WORD    # Complete from both ends of a word.
setopt ALWAYS_TO_END       # Move cursor to the end of a completed word.
setopt PATH_DIRS           # Perform path search even on command names with slashes.
setopt AUTO_MENU           # Show completion menu on a successive tab press.
setopt AUTO_LIST           # Automatically list choices on ambiguous completion.
setopt AUTO_PARAM_SLASH    # If completed parameter is a directory, add a trailing slash.
setopt EXTENDED_GLOB       # Needed for file modification glob modifiers with compinit
unsetopt MENU_COMPLETE     # Do not autoselect the first completion entry.
unsetopt FLOW_CONTROL      # Disable start/stop characters in shell editor.

# Load and initialize the completion system ignoring insecure directories with a
# cache time of 20 hours, so it should almost always regenerate the first time a
# shell is opened each day.
autoload -Uz compinit
_comp_path="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
# #q expands globs in conditional expressions
if [[ $_comp_path(#qNmh-20) ]]; then
  # -C (skip function check) implies -i (skip security check).
  compinit -C -d "$_comp_path"
else
  mkdir -p "$_comp_path:h"
  compinit -i -d "$_comp_path"
fi
unset _comp_path

#
# Styles
#

# Use caching to make completion for commands such as dpkg and apt usable.
zstyle ':completion::complete:*' use-cache on
zstyle ':completion::complete:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# Case-insensitive (all), partial-word, and then substring completion.
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
unsetopt CASE_GLOB

# Group matches and describe.
zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*:matches' group 'yes'
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:options' auto-description '%d'
# fzf-tab parses these formats as group headers and does NOT expand zsh
# prompt escapes (`%F{...}`/`%f`); leaving them in produces literal
# "%F{yellow}-- external command --%f" rows inside the fzf picker. Use
# plain bracketed form so fzf-tab can read it cleanly. The regular zsh
# menu (when fzf-tab is bypassed) loses the colorful header but keeps
# the grouping, which is the right trade-off here.
zstyle ':completion:*:corrections' format '[%d (errors: %e)]'
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:messages' format '[%d]'
zstyle ':completion:*:warnings' format '[no matches found]'
zstyle ':completion:*:default' list-prompt '%S%M matches%s'
zstyle ':completion:*' format '[%d]'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes

# Fuzzy match mistyped completions.
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 1 numeric

# Increase the number of errors based on the length of the typed word. But make
# sure to cap (at 7) the max-errors to avoid hanging.
zstyle -e ':completion:*:approximate:*' max-errors 'reply=($((($#PREFIX+$#SUFFIX)/3>7?7:($#PREFIX+$#SUFFIX)/3))numeric)'

# Don't complete unavailable commands.
zstyle ':completion:*:functions' ignored-patterns '(_*|pre(cmd|exec))'

# Array completion element sorting.
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters

# Directories
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
zstyle ':completion:*:*:cd:*:directory-stack' menu yes select
zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'users' 'expand'
zstyle ':completion:*' squeeze-slashes true

# History
zstyle ':completion:*:history-words' stop yes
zstyle ':completion:*:history-words' remove-all-dups yes
zstyle ':completion:*:history-words' list false
zstyle ':completion:*:history-words' menu yes

# Environment Variables
zstyle ':completion::*:(-command-|export):*' fake-parameters ${${${_comps[(I)-value-*]#*,}%%,*}:#-*-}

# Populate hostname completion.
zstyle -e ':completion:*:hosts' hosts 'reply=(
  ${=${=${=${${(f)"$(cat {/etc/ssh/ssh_,~/.ssh/}known_hosts(|2)(N) 2> /dev/null)"}%%[#| ]*}//\]:[0-9]*/ }//,/ }//\[/ }
  ${=${(f)"$(cat /etc/hosts(|)(N) <<(ypcat hosts 2> /dev/null))"}%%(\#)*}
  ${=${${${${(@M)${(f)"$(cat ~/.ssh/config 2> /dev/null)"}:#Host *}#Host }:#*\**}:#*\?*}}
)'

# Don't complete uninteresting users...
zstyle ':completion:*:*:*:users' ignored-patterns \
  adm amanda apache avahi beaglidx bin cacti canna clamav daemon \
  dbus distcache dovecot fax ftp games gdm gkrellmd gopher \
  hacluster haldaemon halt hsqldb ident junkbust ldap lp mail \
  mailman mailnull mldonkey mysql nagios \
  named netdump news nfsnobody nobody nscd ntp nut nx openvpn \
  operator pcap postfix postgres privoxy pulse pvm quagga radvd \
  rpc rpcuser rpm shutdown squid sshd sync uucp vcsa xfs '_*'

# ... unless we really want to.
zstyle '*' single-ignored show

# Ignore multiple entries.
zstyle ':completion:*:(rm|kill|diff):*' ignore-line other
zstyle ':completion:*:rm:*' file-patterns '*:all-files'

# Kill
zstyle ':completion:*:*:*:*:processes' command 'ps -u $LOGNAME -o pid,user,command -w'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;36=0=01'
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*' force-list always
zstyle ':completion:*:*:kill:*' insert-ids single

# Man
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.(^1*)' insert-sections true

# Media Players
zstyle ':completion:*:*:mpg123:*' file-patterns '*.(mp3|MP3):mp3\ files *(-/):directories'
zstyle ':completion:*:*:mpg321:*' file-patterns '*.(mp3|MP3):mp3\ files *(-/):directories'
zstyle ':completion:*:*:ogg123:*' file-patterns '*.(ogg|OGG|flac):ogg\ files *(-/):directories'
zstyle ':completion:*:*:mocp:*' file-patterns '*.(wav|WAV|mp3|MP3|ogg|OGG|flac):ogg\ files *(-/):directories'

# Mutt
if [[ -s "$HOME/.mutt/aliases" ]]; then
  zstyle ':completion:*:*:mutt:*' menu yes select
  zstyle ':completion:*:mutt:*' users ${${${(f)"$(<"$HOME/.mutt/aliases")"}#alias[[:space:]]}%%[[:space:]]*}
fi

# SSH/SCP/RSYNC
zstyle ':completion:*:(ssh|scp|rsync):*' tag-order 'hosts:-host:host hosts:-domain:domain hosts:-ipaddr:ip\ address *'
zstyle ':completion:*:(scp|rsync):*' group-order users files all-files hosts-domain hosts-host hosts-ipaddr
zstyle ':completion:*:ssh:*' group-order users hosts-domain hosts-host users hosts-ipaddr
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-host' ignored-patterns '*(.|:)*' loopback ip6-loopback localhost ip6-localhost broadcasthost
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-domain' ignored-patterns '<->.<->.<->.<->' '^[-[:alnum:]]##(.[-[:alnum:]]##)##' '*@*'
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-ipaddr' ignored-patterns '^(<->.<->.<->.<->|(|::)([[:xdigit:].]##:(#c,2))##(|%*))' '127.0.0.<->' '255.255.255.255' '::1' 'fe80::*'

# AWS CLI: uses bash-style completion via aws_completer
autoload -Uz bashcompinit && bashcompinit
complete -C aws_completer aws

# --- fzf-tab: replace the menu-select <Tab> UI with fzf -----------------------
# Must be loaded AFTER compinit (above) but BEFORE syntax-highlighting (sourced
# earlier by the alphabetical glob in zshrc.symlink — fast-syntax-highlighting
# only intercepts redraw, not widget binding, so order vs it doesn't matter).
#
# The package is `pkgs.zsh-fzf-tab` from home.nix; the plugin entry lives at
# `~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh`. Guard so machines without
# the package (e.g. mid-migration) just keep zsh's built-in menu.
if [[ -e ~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh ]]; then
    source ~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh

    # Tried routing through fzf-zellij so completion would appear in a
    # floating pane (consistent with _gh / _jb / file picker), but it broke:
    # fzf-zellij runs fzf in a bash subshell inside the pane, while fzf-tab
    # generates its preview strings as zsh code (`[[ -d $realpath ]]`, etc.)
    # and exports compsys variables like $realpath / $word / $desc only
    # within the parent zsh widget. Bash inside the pane can't see those,
    # and even if it could, the syntax doesn't parse. fzf-tab is designed
    # to run inline in the current zsh shell; honour that. The other widgets
    # (_gh, _jb, file picker) still use fzf-zellij — those are independent.
    # Default fzf-command is "fzf"; nothing to set.

    # Inherit FZF_DEFAULT_OPTS (ctrl-n/ctrl-p preview-page bindings, etc).
    zstyle ':fzf-tab:*' use-fzf-default-opts yes

    # Comma/period switch between completion groups (e.g. files vs dirs).
    zstyle ':fzf-tab:*' switch-group ',' '.'

    # Render group headers as headers (not as selectable rows). `full` puts
    # the header line above each group inline (so command completion shows
    # `[external command]` then commands, then `[parameter]` then params,
    # etc.). `brief` only shows the current selection's group header — less
    # useful when scrolling.
    zstyle ':fzf-tab:*' show-group full

    # Strip the per-row prefix marker. fzf-tab adds a middle-dot (·) before
    # each candidate when `:completion:*:descriptions:format` is set, as a
    # visual hint that the row belongs to a group. We have group headers
    # via show-group=full, so the prefix is redundant noise — and renders
    # as a leading "." in fonts without proper U+00B7 glyph spacing.
    zstyle ':fzf-tab:*' prefix ''

    # Plain default colour for non-selected rows; lets terminal theme show
    # through instead of fzf-tab's slightly dim default.
    zstyle ':fzf-tab:*' default-color $'\033[37m'

    # Generic file/dir preview for ANY command that completes a path. Runs
    # whenever the more-specific rules below don't match. Branches at runtime:
    # directory → name-only listing (eza --tree -L 1 if available, else
    # `ls -1 -F` so file/dir names get the full preview width — `ls -la` was
    # truncating names because perm/owner/group/size/date eats half the
    # column budget); text file → bat (200 lines); binary/other → file metadata.
    zstyle ':fzf-tab:complete:*:*' fzf-preview '
        if [[ -d $realpath ]]; then
            if command -v eza >/dev/null 2>&1; then
                eza --color=always --icons=auto -1 -F --group-directories-first $realpath
            else
                ls -1 -F --color=always $realpath
            fi
        elif [[ -f $realpath ]]; then
            bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null \
                || cat $realpath 2>/dev/null \
                || file $realpath
        elif [[ -n $realpath ]]; then
            file $realpath 2>/dev/null
        fi
    '

    # Command-specific overrides go below — these win over the generic rule
    # because fzf-tab matches the most-specific zstyle pattern. Keep tight:
    # more rules = slower tab cycle.
    zstyle ':fzf-tab:complete:cd:*' fzf-preview '
        if command -v eza >/dev/null 2>&1; then
            eza --color=always --icons=auto -1 -F --group-directories-first $realpath
        else
            ls -1 -F --color=always $realpath
        fi
    '
    zstyle ':fzf-tab:complete:git-(add|diff|restore|stash):*' fzf-preview \
        'git diff --color=always -- $realpath 2>/dev/null'
    zstyle ':fzf-tab:complete:git-show:*' fzf-preview \
        'git show --color=always $word 2>/dev/null'
    zstyle ':fzf-tab:complete:git-(log|reflog):*' fzf-preview \
        'git log --color=always $word 2>/dev/null'
    zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview \
        'SYSTEMD_COLORS=1 systemctl status $word 2>/dev/null'
fi
