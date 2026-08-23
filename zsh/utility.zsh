# From zprezto modules/utility/init.zsh (partial)
#
# Defines general aliases and functions.
#
# Authors:
#   Robby Russell <robby@planetargon.com>
#   Suraj N. Kurapati <sunaku@gmail.com>
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

#
# Helper functions (from zprezto modules/helper/init.zsh)
#

function is-callable { (( $+commands[$1] || $+functions[$1] || $+aliases[$1] || $+builtins[$1] )) }
function is-darwin { [[ "$OSTYPE" == darwin* ]] }
function is-linux { [[ "$OSTYPE" == linux* ]] }
function is-bsd { [[ "$OSTYPE" == *bsd* ]] }

#
# Correction
#

setopt CORRECT

# Disable correction for commands where it's annoying.
alias ack='nocorrect ack'
alias cd='nocorrect cd'
alias cp='nocorrect cp'
alias gcc='nocorrect gcc'
alias grep='nocorrect grep'
alias ln='nocorrect ln'
alias man='nocorrect man'
alias mkdir='nocorrect mkdir'
alias mv='nocorrect mv'

# Keep the familiar rm interface while making interactive deletion recoverable.
if is-callable 'gio'; then
  function rm {
    emulate -L zsh
    setopt local_options

    local -a gio_options targets target_stat parent_stat
    local arg char reply target target_abs parent
    local interactive=never
    local -i force=0 options=1 recursive=0 verbose=0
    local -i preserve_root=1 preserve_all=0 exit_status=0 gio_status

    for arg in "$@"; do
      if (( options )); then
        case "$arg" in
          --)
            options=0
            continue
            ;;
          --force)
            force=1
            interactive=never
            continue
            ;;
          --interactive)
            interactive=always
            continue
            ;;
          --interactive=never|--interactive=once|--interactive=always)
            interactive=${arg#*=}
            continue
            ;;
          --interactive=*)
            print -u2 -r -- "rm: invalid argument '${arg#*=}' for --interactive"
            return 2
            ;;
          --recursive)
            recursive=1
            continue
            ;;
          --dir|--one-file-system)
            continue
            ;;
          --no-preserve-root)
            preserve_root=0
            preserve_all=0
            continue
            ;;
          --preserve-root)
            preserve_root=1
            preserve_all=0
            continue
            ;;
          --preserve-root=all)
            preserve_root=1
            preserve_all=1
            continue
            ;;
          --preserve-root=*)
            print -u2 -r -- "rm: invalid argument '${arg#*=}' for --preserve-root"
            return 2
            ;;
          --verbose)
            verbose=1
            continue
            ;;
          --help)
            print -r -- 'Usage: rm [OPTION]... [FILE]...
Move FILEs and directories to the trash with gio.

  -f, --force              ignore nonexistent files and never prompt
  -i, --interactive=always prompt before every file
  -I, --interactive=once   prompt once for recursion or more than three files
  -r, -R, --recursive      accepted; gio already handles directories
  -d, --dir                accepted; gio already handles directories
      --one-file-system    accepted; gio does not recursively unlink files
      --preserve-root[=all] protect root or separate-device arguments
      --no-preserve-root   disable root protection
  -v, --verbose            print each successfully trashed path
      --help               display this help and exit
      --version            output wrapper and gio versions

Use command rm for permanent deletion.'
            return 0
            ;;
          --version)
            print -r -- 'rm (dotfiles gio trash wrapper)'
            command gio --version
            return $?
            ;;
          --*)
            print -u2 -r -- "rm: unrecognized option '$arg'"
            return 2
            ;;
          -?*)
            for char in ${(s::)${arg#-}}; do
              case "$char" in
                f)
                  force=1
                  interactive=never
                  ;;
                i)
                  interactive=always
                  ;;
                I)
                  interactive=once
                  ;;
                r|R)
                  recursive=1
                  ;;
                d)
                  ;;
                v)
                  verbose=1
                  ;;
                *)
                  print -u2 -r -- "rm: invalid option -- '$char'"
                  return 2
                  ;;
              esac
            done
            continue
            ;;
        esac
      fi
      targets+=("$arg")
    done

    if (( ! ${#targets} )); then
      print -u2 -r -- "rm: missing operand"
      return 1
    fi

    (( force )) && gio_options+=(--force)

    if [[ "$interactive" == once ]] &&
      (( recursive || ${#targets} > 3 )); then
      printf 'rm: trash %d arguments? ' "${#targets}" >&2
      IFS= read -r reply
      [[ "$reply" == [yY]* ]] || return 0
    fi

    (( preserve_all )) && zmodload -F zsh/stat b:zstat

    for target in "${targets[@]}"; do
      target_abs=${target:a}
      if (( preserve_root )) && [[ "$target_abs" == / ]]; then
        print -u2 -r -- "rm: refusing to trash root directory '$target'"
        exit_status=1
        continue
      fi

      if (( preserve_all )); then
        parent=${target_abs:h}
        target_stat=()
        parent_stat=()
        zstat -L -A target_stat +device -- "$target" 2>/dev/null
        zstat -L -A parent_stat +device -- "$parent" 2>/dev/null
        if (( ${#target_stat} && ${#parent_stat} )) &&
          [[ "$target_stat[1]" != "$parent_stat[1]" ]]; then
          print -u2 -r -- "rm: refusing separate-device argument '$target'"
          exit_status=1
          continue
        fi
      fi

      if [[ "$interactive" == always ]]; then
        printf 'rm: trash %q? ' "$target" >&2
        IFS= read -r reply
        [[ "$reply" == [yY]* ]] || continue
      fi

      command gio trash "${gio_options[@]}" -- "$target"
      gio_status=$?
      if (( gio_status )); then
        exit_status=$gio_status
      elif (( verbose )); then
        printf 'trashed %q\n' "$target"
      fi
    done

    return $exit_status
  }
fi
alias rm='nocorrect rm'

# Disable globbing for commands that do their own.
alias fc='noglob fc'
alias find='noglob find'
alias history='noglob history'
alias locate='noglob locate'
alias rsync='noglob rsync'
alias scp='noglob scp'

#
# ls
#

if is-callable 'dircolors'; then
  # GNU Core Utilities
  alias ls="${aliases[ls]:-ls} --group-directories-first"

  if [[ -z "$LS_COLORS" ]]; then
    if [[ -s "$HOME/.dir_colors" ]]; then
      eval "$(dircolors --sh "$HOME/.dir_colors")"
    else
      eval "$(dircolors --sh)"
    fi
  fi

  alias ls="${aliases[ls]:-ls} --color=auto"
else
  # BSD Core Utilities
  if [[ -z "$LSCOLORS" ]]; then
    export LSCOLORS='exfxcxdxbxGxDxabagacad'
  fi
  if [[ -z "$LS_COLORS" ]]; then
    export LS_COLORS='di=34:ln=35:so=32:pi=33:ex=31:bd=36;01:cd=33;01:su=31;40;07:sg=36;40;07:tw=32;40;07:ow=33;40;07:'
  fi

  alias ls="${aliases[ls]:-ls} -G"
fi

alias l='ls -1A'         # Lists in one column, hidden files.
alias ll='ls -lh'        # Lists human readable sizes.
alias lr='ll -R'         # Lists human readable sizes, recursively.
alias la='ll -A'         # Lists human readable sizes, hidden files.
alias lm='la | "$PAGER"' # Lists human readable sizes, hidden files through pager.
alias lx='ll -XB'        # Lists sorted by extension (GNU only).
alias lk='ll -Sr'        # Lists sorted by size, largest last.
alias lt='ll -tr'        # Lists sorted by date, most recent last.
alias lc='lt -c'         # Lists sorted by date, most recent last, shows change time.
alias lu='lt -u'         # Lists sorted by date, most recent last, shows access time.
alias sl='ls'            # I often screw this up.
alias z='zmx-select'     # zmx session picker

#
# Grep
#

export GREP_COLOR='37;45'           # BSD.
export GREP_COLORS="mt=$GREP_COLOR" # GNU.
alias grep="${aliases[grep]:-grep} --color=auto"
