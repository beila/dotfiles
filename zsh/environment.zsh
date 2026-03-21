# Environment — replaces zprezto 'environment' module
# Smart URLs: auto-quote special chars when pasting URLs
autoload -Uz is-at-least
if [[ ${ZSH_VERSION} != 5.1.1 && ${TERM} != "dumb" ]]; then
  if is-at-least 5.2; then
    autoload -Uz bracketed-paste-url-magic
    zle -N bracketed-paste bracketed-paste-url-magic
  elif is-at-least 5.1; then
    autoload -Uz bracketed-paste-magic
    zle -N bracketed-paste bracketed-paste-magic
  fi
  autoload -Uz url-quote-magic
  zle -N self-insert url-quote-magic
fi

# General
setopt COMBINING_CHARS      # render accented characters correctly
setopt INTERACTIVE_COMMENTS # allow # comments in interactive shell
setopt RC_QUOTES            # 'it''s' instead of 'it'\''s'
unsetopt MAIL_WARNING       # no mail file access warning

# Free Ctrl+S/Ctrl+Q from terminal flow control
[[ -r ${TTY:-} && -w ${TTY:-} && $+commands[stty] == 1 ]] && stty -ixon <$TTY >$TTY

# Jobs
setopt LONG_LIST_JOBS       # verbose job listing
setopt AUTO_RESUME          # resume existing job before creating new process
setopt NOTIFY               # report background job status immediately
unsetopt BG_NICE            # don't lower priority of background jobs
unsetopt HUP                # don't kill jobs on shell exit
unsetopt CHECK_JOBS         # don't warn about running jobs on exit

# Colored man pages in less
export LESS_TERMCAP_mb=$'\E[01;31m'    # blinking
export LESS_TERMCAP_md=$'\E[01;31m'    # bold
export LESS_TERMCAP_me=$'\E[0m'        # end mode
export LESS_TERMCAP_se=$'\E[0m'        # end standout
export LESS_TERMCAP_so=$'\E[00;47;30m' # standout (search highlight)
export LESS_TERMCAP_ue=$'\E[0m'        # end underline
export LESS_TERMCAP_us=$'\E[01;32m'    # underline
