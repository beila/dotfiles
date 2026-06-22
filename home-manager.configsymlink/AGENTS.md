# home-manager — Context for AI Agent

Activated via `home-manager switch --impure --flake ~/.dotfiles/home-manager.configsymlink`.
`--impure` is required because the flake reads `$HOME` at eval time to resolve sibling repos.

## flake.nix

- Inputs: `nixpkgs`, `home-manager`, `nixGL`. Sibling repos (`private-dotfiles`, `work-dotfiles`) are NOT flake inputs — they're resolved at eval time from `$HOME` (see "Sibling repo resolution" below).
- `mkHost` builds a `homeManagerConfiguration` from shared modules + per-host extras. `nixFilesFrom` auto-loads root `.nix` files from both sibling repos as modules. `hosts/*.nix` (in `private-dotfiles/`) returns `homeConfigurations` attrset fragments keyed by `username@static-hostname`.
- `nix.conf` `warn-dirty = false` is required: jj always has uncommitted changes, and `nix eval`'s dirty-tree warning to stdout would otherwise pollute home-manager's string comparison.

## bare-aliases.nix

At eval time, reads `/etc/hostname` (FQDN and short form both tried) and exposes any `user@<live-host>` entry under bare `user`, so `home-manager switch --impure --flake .` (no explicit `#user@host`) auto-detects via `$USER`. Pure-eval-safe: empty `/etc/hostname` produces no aliases.

**Caveat**: the flake snapshot is read from git's index, so any new file under `home-manager.configsymlink/` (or new `hosts/<hostname>.nix`) needs `git add` before the next switch — jj's auto-snapshot does not bridge to the git index for `git+file://` flake inputs.

## home.nix

Packages, the unfree predicate (albert + 8 nvim plugins reclassified upstream — see "Flake update watchdog" in `script/AGENTS.md`), the `copyq` daemon, and `dotfiles.schedule.jobs` declarations (see `schedule.nix`).

Defines two inline derivations consumed by OSDs:

- `osd` — local Python package built from `xwindow/osd/` (cairo + XShape primitives). Used by both `battery-osd` (a `writePython3Bin` invocation script) and `hangul-osd`.
- `jejuhallasan-ttf` — single `fetchurl` of one ttf from `google/fonts` (SIL OFL 1.1). Avoids `pkgs.google-fonts` (2.3 GB).

The `hangul-osd` `writeShellScriptBin` wrapper exports `GI_TYPELIB_PATH` (Pango / PangoCairo / cairo / IBus / harfbuzz typelibs from the nix store + the gobject-introspection wrapper for cairo's `cairo-1.0.typelib`, which Pango pulls in transitively) and `HANGUL_OSD_FONT_FILE` before exec'ing the inner `writePython3Bin` impl. Both env vars are required — see `xwindow/AGENTS.md` for the Pango/fontconfig rationale.

## gnome.nix

- dconf settings (key repeat, mouse speed, cursor size 64, Korean Sebeolsik 390, disable gnome-panel/desktop).
- IBus integration (`pkgs.ibus` for the GTK4 IM module + `~/.config/environment.d/30-ibus.conf` for `GTK_IM_MODULE` etc.).
- gnome-flashback systemd drop-ins (xmonad session requires `gnome-flashback.target` + service-restart override).
- Declares `random-lockscreen` via `dotfiles.schedule.jobs` and `hangul-osd` as a `systemd.user.services.*` (`PartOf=graphical-session.target`) — both depend on a graphical session and ibus, so they're gnome-only.

## schedule.nix

Cross-backend scheduler. One job declaration → one of two backends, picked per host:

- `dotfiles.schedule.backend = "systemd"` (default) emits `systemd.user.{services,timers}`.
- `"cron"` emits a managed crontab block via `install-crontab.sh` activation.

Per-job options: `enable`, `description`, `command` (with `%h` expansion for cron), `schedule.{systemd,cron}` (both required — no auto-translation), `nice`, `ioSchedulingClass` (mapped to `ionice -c` under cron), `randomizedDelaySec` (native systemd; emitted as `sleep $((RANDOM \% N))` under cron), `persistent` (native systemd; no-op under cron), `env` (per-job; `Environment=` under systemd, `/usr/bin/env KEY=VAL` prefix under cron).

Top-level `dotfiles.schedule.pathExtra` applies to **both** backends — it's the single source of truth for the job PATH (cron header line; `Environment=PATH=` on each systemd service). Needed because both run with a stripped PATH: cron defaults to `/usr/bin:/bin`, and the systemd user manager's PATH is a login-time snapshot that omits what interactive shells prepend. Default covers `~/.toolbox/bin` (first — version-stable claude/kiro-cli shims that `commit-msg` shells out to; the `~/.local/bin` kiro-cli shim pins a version path toolbox deletes on auto-update, so it's listed after and gets shadowed), `~/.nix-profile/bin`, `/nix/var/nix/profiles/default/bin`, `~/.local/bin`, `/run/current-system/sw/bin`, `/usr/local/bin`. Top-level `dotfiles.schedule.environment` is cron-only; systemd mode otherwise picks env from `~/.config/environment.d/` (managed by `private-dotfiles/logger.nix`, which mirrors `LOG_ROOT`/`LOG_REL_BASE` into `dotfiles.schedule.environment` so cron jobs see the same env).

**Why this exists**: nix systemd ≥256 hard-requires cgroup v2 — `systemd --user` exits silently with rc=1 after `statfs("/sys/fs/cgroup/")` returns `TMPFS_MAGIC` instead of `CGROUP2_SUPER_MAGIC`. Switching the host to cgroup v2 needs a kernel cmdline change (`systemd.unified_cgroup_hierarchy=1`) and a reboot, neither feasible on every host (e.g. managed images). cron is universal and good enough for the scheduling features we use.

## install-crontab.sh

Activation helper for the cron backend. Reads existing crontab, strips any prior `# >>> home-manager managed (dotfiles.schedule) >>>` … `# <<< home-manager managed (dotfiles.schedule) <<<` block via awk, appends the new block, installs via `crontab -`. Marker contract preserves user-edited entries outside the block. Idempotent (`cmp -s` skips reinstalling identical content). Activation prepends `/usr/bin:/usr/sbin` to PATH so the system `crontab(1)` is found from home-manager's minimal-PATH activation env.

## neovide.nix

nixGL-wrapped neovide (GPU access on non-NixOS), font-copying activation (JetBrains Mono + Nerd Font + Source Code Pro for neovide's default fallback).

## nvim.nix

neovim (default editor, vi/vim aliases). `initLua` sources `myinit.lua`. nix generates `init.lua` which overwrites `nvim.configsymlink/init.lua` on every switch; `init.lua` is gitignored. Dev tool packages (LSPs, linters, formatters, DAP deps), rustaceanvim. See `nvim.configsymlink/AGENTS.md`.

## xmonad.nix

xmonad + contrib via nix 0.18, xfce4-panel + xfconf, xfconf dbus activation hook. See `xwindow/AGENTS.md`.

## xdg.nix

firefox-container desktop entry + mimeapps.

## zmx.nix

Prebuilt zmx binary from `zmx.sh` (session persistence). Source build via zmx's flake fails because `zig2nix` cannot vendor ghostty's `git+https?ref=HEAD` dependency.

## system-deps.sh

**Bootstrap-only** (run from `script/install`, NOT `home-manager switch`).

- Detects package manager (dnf/yum preferred for Amazon Linux). Installs GNOME + xmonad session files when `gnome-session` is present.
- Copies keyd configs to `/etc/keyd` and enables the service when `/dev/input` exists. Runs `loginctl enable-linger`.
- Idempotently patches `/usr/share/X11/xkb/symbols/inet` so keycodes 198/202 (`KEY_F20`/`KEY_F24`) map to `F20`/`F24` keysyms — keyd's Super+C/V macro emits these for neovide, and `setxkbmap` (called by ibus engine switches) would otherwise wipe an `xmodmap` override. See `keyd/AGENTS.md`.

**Re-run `script/install` after `apt upgrade xkeyboard-config`** since the package may overwrite the file (backup at `inet.dotfiles-bak`).

## Sibling repo resolution

`private-dotfiles` and `work-dotfiles` are gitignored sibling repos resolved at flake eval time via `builtins.getEnv "HOME"` — that's why `--impure` is required. A sentinel path falls back to empty when unavailable, so pure eval still succeeds. See each sibling's own `AGENTS.md` for layout.

## Known gotchas

- **Nix flakes and gitignored content**: flakes copy git-tracked source tree to store. `getEnv "HOME"` + `--impure` keeps `flake.lock` portable; the alternative (`git+file://` input) bakes a per-machine path into `flake.lock`.
- **xfconf needs dbus service registration** — handled by Home Manager activation.
- **Fonts need copying to `~/.local/share/fonts`** for neovide / dzen2 (skia / dzen2 don't read nix font paths).
- **Nix-installed GTK apps don't show in xfce4-panel systray** (library mismatch).
