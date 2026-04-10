# dotfiles

Personal workstation config. NixOS-adjacent (Home Manager on Ubuntu), xmonad, zellij, neovim, jj.

## Structure

- **topic/\*.zsh** — auto-sourced into zsh
- **topic/path.zsh** — sourced first (`$PATH` setup)
- **topic/completion.zsh** — sourced last
- **topic/\*.symlink** — symlinked into `$HOME` (without `.symlink` suffix)
- **topic/\*.configsymlink/** — symlinked into `~/.config/`
- **topic/\*.filesymlink/** — individual files symlinked into `~/.<name>/`
- **bin/** — added to `$PATH`

## Install

```sh
git clone git@github.com:beila/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
script/bootstrap
```

`script/bootstrap` symlinks config files, clones private-dotfiles, runs `install.sh` scripts, and runs Home Manager.

System-level deps (keyd, gnome session, ollama) require:

```sh
sudo home-manager.configsymlink/system-deps.sh
```

Detects package manager (dnf/yum/apt-get) and skips GNOME/keyd on headless machines.

## Key components

- **Home Manager** — `home-manager.configsymlink/flake.nix` manages packages, neovim, xmonad, gnome, systemd timers
- **xmonad** — `xwindow/xmonad.symlink/xmonad.hs`, built via nix GHC
- **keyd** — `keyd/` (CapsLock→Ctrl/Esc, Super/Alt tap actions, per-keyboard configs)
- **zsh** — standalone config in `zsh/` (vi mode, p10k, fast-syntax-highlighting, autosuggestions)
- **neovim** — `nvim.configsymlink/`, plugins via nix, per-language LSP/DAP in `vimrcs/my-*.lua`
- **fzf** — `fzf/` (jj-first/git-fallback functions, ctrl-g sequences, file/log/bookmark pickers)
- **zellij** — `zellij.configsymlink/`, session cycling via `bin/zellij-cycle`
- **ghostty** — `ghostty.configsymlink/`
- **jj** — `jj.configsymlink/`, revset aliases, colocated with git
- **sync** — `script/sync_all` (timer), `script/sync_dotfiles` (per-repo, flock, AI commit messages)

## Docs

- `AGENTS.md` — full architecture reference and TODO list (for AI agents and humans)
- `keyd/README.md` — key remapping stack
- `xwindow/README.md` — input-remapper presets
