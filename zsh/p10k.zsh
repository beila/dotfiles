# Prompt — powerlevel10k (installed via nix)
if (( ! ${+_dotfiles_prompt_host} )); then
  typeset -g _dotfiles_prompt_host=
  if (( $+commands[hostnamectl] )); then
    _dotfiles_prompt_host=$(command hostnamectl --pretty 2>/dev/null) || _dotfiles_prompt_host=
  fi
  _dotfiles_prompt_host=${_dotfiles_prompt_host//[[:cntrl:]]/}
  [[ -n ${_dotfiles_prompt_host//[[:space:]]/} ]] || _dotfiles_prompt_host=${HOST%%.*}
  typeset -g _dotfiles_prompt_host_escaped=${_dotfiles_prompt_host//\%/%%}
fi

source ~/.nix-profile/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

_dotfiles_remote_banner() {
  emulate -L zsh
  add-zsh-hook -d precmd _dotfiles_remote_banner
  [[ ${_dotfiles_remote_banner_shown:-0} == 0 ]] || return 0
  [[ -n $SSH_CONNECTION || -n $SSH_CLIENT || -n $SSH_TTY || ${P9K_SSH:-0} == 1 ]] || return 0
  typeset -g _dotfiles_remote_banner_shown=1

  if [[ $TERM == dumb ]]; then
    printf 'REMOTE  %s@%s' "${(%):-%n}" "$_dotfiles_prompt_host"
    [[ -z $ZMX_SESSION ]] || printf ' · zmx:%s' "$ZMX_SESSION"
  else
    printf '\033[1;33mREMOTE  %s@%s\033[0m' "${(%):-%n}" "$_dotfiles_prompt_host"
    [[ -z $ZMX_SESSION ]] || printf '\033[2m · zmx:%s\033[0m' "$ZMX_SESSION"
  fi
  printf '\n'
}

# Display the banner before the first prompt, after SSH detection.
if [[ -o interactive && -t 1 && ${_dotfiles_remote_banner_shown:-0} == 0 ]]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _dotfiles_remote_banner
fi
