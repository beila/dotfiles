# zsh — Context for AI Agent

`~/.dotfiles/zsh/`. Standalone files (zprezto fully removed). zsh is **not** managed by home-manager. The user is on LDAP and can't `chsh`, so `$SHELL` stays bash and zsh is started via `exec` from `.bashrc`.

## Loading order

- `zshenv.symlink` — sets `$DOTFILES_ROOT` via `%N`, sources `*/path.zsh`. Also sources home-manager's `hm-session-vars.sh`.
- `zshrc.symlink` — sources `**/*.zsh` (excludes `path.zsh`, `completion.zsh`); `completion.zsh` sourced last.

## Files

- `environment.zsh` — smart URLs, setopt, jobs, colored man pages.
- `terminal.zsh` — window/tab/pane titles via precmd/preexec.
- `editor.zsh` — vi mode, dot expansion, key bindings, vim-surround, text objects. `KEYTIMEOUT=1` and `zle-line-init` forces insert mode on every new prompt so stray escape sequences (e.g. from zmx re-attach or kitty keyboard protocol) don't silently leave ZLE in vicmd mode. Bindkey setup is skipped when `! -o shinstdin` (e.g. under `zsh -ic 'cmd'`) because terminfo keycaps aren't populated yet.
- `history.zsh` — 10M entries, dedup, `HIST_IGNORE_SPACE` disabled.
- `directory.zsh` — `auto_cd`, `auto_pushd`, `extended_glob`, no clobber.
- `utility.zsh` — correction, `nocorrect`/`noglob` aliases, colored ls/grep.
- `completion.zsh` — compinit, caching, fuzzy match, case-insensitive, menu select, AWS bashcompinit, **fzf-tab** (see below).
- `syntax-highlighting.zsh` — `fast-syntax-highlighting` (nix).
- `autosuggestions.zsh` — `zsh-autosuggestions` (nix).
- `git.zsh` — git aliases, no git-flow.
- `gnu-utility.zsh` — g-prefixed GNU utils on macOS, no-op on Linux.
- `p10k.zsh` — powerlevel10k (nix) + user config.

## Functions (`zsh/functions/`)

- `c` — copy (Wayland/X11 aware)
- `p` — paste (Wayland/X11 aware)
- `o` — open (Wayland/X11 aware)
- `say_done` — TTS notification when commands >10s finish; only on desktop machines; runs in a subshell. Calls `bin/say` (see `bin/AGENTS.md`).
- `ju` — jj unique
- `jda` — jj describe with AI commit-msg; prints the generated description

## fzf-tab tab completion

`pkgs.zsh-fzf-tab` (loaded from `~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh` at the end of `zsh/completion.zsh`, after compinit). Replaces zsh's built-in `<Tab>` menu-select with an fzf picker.

**Runs inline in the current zsh shell**, NOT through fzf-zellij — fzf-tab generates preview strings as zsh code referencing compsys variables (`$realpath`, `$word`, `$desc`) that aren't visible to the bash subshell `fzf-zellij` spawns inside the floating pane. Other widgets (`_gh`, `_jb`, file picker) still use fzf-zellij; only completion is inline.

zstyles set:

- `use-fzf-default-opts yes` — inherits ctrl-n/ctrl-p preview-page bindings.
- `switch-group ',' '.'` — cycle between groups.
- `show-group full` — group headers shown inline above each group.
- `prefix ''` — no leading middle-dot marker (renders as a stray "." in many fonts).
- `default-color $'\033[37m'`.

Previews: a generic `:fzf-tab:complete:*:*' fzf-preview` rule branches at runtime — `[[ -d $realpath ]]` → eza listing, `-f` → bat (200 lines), else `file` metadata. Specific overrides for `cd` (eza), `git-(add|diff|restore|stash)` (git diff), `git-show` (commit body), `git-(log|reflog)` (per-commit log), `systemctl-*` (status). Plugin-file guard so machines without the package fall back gracefully to zsh's built-in menu.

**Required `:completion:*:descriptions' format` change**: the colorful `' %F{yellow}-- %d --%f'` form leaked literal escape codes into the picker as candidates because fzf-tab doesn't expand zsh prompt escapes; switched to plain `'[%d]'` bracketed form.

Test harness: `zsh/test_fzf-tab.sh` (6 assertions: plugin file present, widget registered, fzf-command unset (intentional — verifies we don't accidentally re-introduce the fzf-zellij integration), compinit cold + warm OK, plugin loads cleanly even when fzf-zellij missing from PATH).

## Known issues

- **vi mode**: custom zle widget bindings must use `bindkey -M viins` and `bindkey -M vicmd` explicitly.
- **fzf source order**: `source <(fzf --zsh)` must come before custom bindkeys that reference fzf widgets; `zshrc.symlink` globs alphabetically — don't put static copies of fzf scripts in the glob path.
