# Neovim — Context for AI Agent

`nvim.configsymlink/` symlinked to `~/.config/nvim`. Also symlinked to `~/.vim` via `vim.symlink → nvim.configsymlink`. If `~/.vim/myvimrc` is unreachable (vim.symlink missing/broken), `vimrc.symlink`'s `source ~/.vim/myvimrc` will error and abort everything downstream in `init.lua` — fix with `ln -sfn nvim.configsymlink ~/.dotfiles/vim.symlink`.

## Plugin management

All plugins installed via home-manager `programs.neovim.plugins` (see `home-manager.configsymlink/nvim.nix`); no submodules.

## Config loading

1. nix generates `init.lua` (lua paths + `myinit.lua` content via `initLua`).
2. `myinit.lua` sources `vimrc.symlink`.
3. `vimrc.symlink` sources `myvimrc`.
4. `myvimrc` runs `runtime! vimrcs/*.vimrc`, `vimrcs/*.nvimrc`, `vimrcs/*.lua`.
5. `init.lua` is gitignored (nix-generated); nvim only loads `init.lua` (not `init.vim`/vimrc) when both exist.

## Logs

- `~/.vim-messages.log` — vim's verbose output AND any `:echoerr` / plugin error messages (via `set verbosefile=~/.vim-messages.log` in `myvimrc`). Rotated to `~/.vim-messages.log.old` at nvim exit when > 1MB (autocmd in `myvimrc`).
- `~/.local/state/nvim/lsp.log` — full LSP RPC traffic.
- `~/.local/state/nvim/mason.log` — Mason installer output.
- Debug recipe: `grep -i '<pattern>' ~/.vim-messages.log{,.old} 2>/dev/null` for error strings; `tail -50 ~/.local/state/nvim/lsp.log` for LSP issues.
- Inside running nvim: `:messages` (history), `:messages clear` (drops in-memory copy; doesn't rotate the file).

## Project-local config

`myvimrc` sources `.nvim.lua` from cwd or ancestors on `BufEnter`, with per-buffer dedup.

## User commands (defined in `myvimrc`)

- `:Rename {newpath}` — rename current file.
- `:Ext {ext}` — change current file's extension; re-runs `filetype detect`.

## Per-language setup (`vimrcs/my-<lang>.lua`)

LSP via `vim.lsp.config.NAME = { ... }` + `vim.lsp.enable('NAME')`, DAP, filetype-specific config.

Languages: my-awk, my-bash (bash/sh only — no zsh LSP), my-cmake, my-cpp, my-css, my-docker, my-glsl, my-haskell, my-html, my-java, my-jinja, my-js (js/ts), my-json, my-just, my-kotlin, my-lua, my-markdown, my-nim, my-nix, my-python, my-rust (rustaceanvim, not vim.lsp.config), my-sql, my-text, my-toml, my-vim, my-xml, my-yaml.

## Shared config

- `vimrcs/lsp.lua` — keymaps incl. `<leader>e` floating diagnostic.
- `vimrcs/nvim-dap.lua` — codelldb + shared DAP keymaps.
- `vimrcs/nvim-lint.lua` — linter-by-filetype config.

## Plugin-specific

- **Autoformat** (`vimrcs/my-autoformat.lua`) — format on autosave via `CursorHold` / `BufLeave` / `FocusLost`, checks `vim.b.autoformat_fts`; per-project `.nvim.lua` sets `vim.b.autoformat_fts`. `myvimrc` sets `updatetime=10000` because CursorHold-triggered LSP format bumps `b:changedtick` and resets yank-cycle state (YankRing `<C-n>`/`<C-p>`).
- **Completion** (`vimrcs/blink-cmp.lua`) — blink.cmp.
- **DAP UI** (`vimrcs/nvim-dap-ui.lua`) — auto-open/close debug UI, F7 toggle.
- **Git gutter** (`vimrcs/gitsigns.lua`) — gitsigns.nvim with jj support (diffs against `@-` via `change_base`), `]c`/`[c` hunk nav, `<leader>hp` preview, `<leader>hr` reset, `<leader>hb` blame (no staging — safe for jj).
- **LSP enhancements** (`vimrcs/lsp_signature.lua`) — inlay hints + auto signature help.
- **LSP progress** (`vimrcs/fidget.lua`) — fidget.nvim.
- **Treesitter textobjects** (`vimrcs/nvim-treesitter.lua`) — `vaf`/`vif` function, `vac`/`vic` class, `vaa`/`via` parameter, `<leader>a`/`<leader>A` swap parameter; manual global keymaps (buffer-local may not attach).
- **mini.ai** (`vimrcs/mini-ai.lua`) — extended a/i textobjects; treesitter-powered `F` (function def), `c` (class); pattern-based `f`/`a` work better than treesitter for C++ templates.
- **nvim-surround** (`vimrcs/nvim-surround.lua`) — `ys`/`ds`/`cs` keybindings (matches zsh vi-mode surround).
- **Treesitter incremental selection** — `<C-e>` init/expand node, `<C-d>` shrink node (manual global keymaps).
- **Tabline** (`vimrcs/my-tabline.lua`) — custom `&tabline` showing `<tabnr> <path>` per tab (strips `$HOME/`, elides middle with `…` under tight budgets). Replaces nvim's default (which prepended a window-count digit) and airline's tabline extension (disabled in `vim-airline.vimrc`). Tab number highlighted via `MyTabNum`.
- **Indent detection** — vim-sleuth (auto-detects tabstop/shiftwidth).
- **Limelight** (`my-text.lua`) — auto-enabled for text, markdown, rst, org, asciidoc, tex, mail, gitcommit.
- **Table mode** (`my-markdown.lua`) — `silent! TableModeEnable` on markdown FileType.
- **fzf-lua** (`vimrcs/fzf.lua`) — `<leader>f` jj/git tracked files (ctrl-g toggles submodule files, ctrl-f toggles all files, query preserved), `<leader>F` all files, `<C-g><C-f>` changed files, ctrl-n/p preview scroll. **Grep dialog toggles** (header strip, separated by newline so it stacks instead of forming one long line): `ctrl-r` `actions.toggle_ignore` (live-labelled "Respect/Disable .gitignore"), `ctrl-g` default `actions.grep_lgrep` (live/regex), `ctrl-w` `--word-regexp`, `ctrl-s` `--case-sensitive`. The two flag toggles use a local `toggle_rg_flag` helper instead of `actions.toggle_flag`: it inserts the flag immediately before the trailing `-e` (so the user's query stays the rg pattern arg, not the toggled flag) AND keeps the flag positioned after `--smart-case` so rg's last-case-flag-wins rule lets `--case-sensitive` actually take effect. `ctrl-s` shadows the inherited `file_split` action inside grep only.
- **Font** (`gvimrc`) — neovide guifont `JetBrains Mono Thin,LXGW WenKai Mono:h11` (Latin + Hangul/CJK fallback, matches ghostty). `:h<Size>` goes once at the very end; repeating per font fails with "Invalid size". `neovide.nix` copies LXGW Mono into `~/.local/share/fonts/` (skia ignores nix paths). Source Code Pro must be installed for neovide's default fallback.
- **Linting** — `nvim-lint` runs CLI linters (checkmake, hadolint, checkstyle, markdownlint-cli2, statix, deadnix) on save. `markdownlint-cli2` is fed via stdin, and over stdin it only auto-discovers a config in the *exact* cwd (no upward walk), so `~/.markdownlint-cli2.yaml` (which disables `line-length`) is ignored everywhere except `$HOME`. `nvim-lint.lua` overrides its args to pass `--config ~/.markdownlint-cli2.yaml` explicitly.

## Tool installation

Prefer nix (`home-manager.configsymlink/nvim.nix`) over Mason. Mason is only for DAPs not in nixpkgs (bash-debug-adapter, codelldb, kotlin-debug-adapter, java-debug-adapter, debugpy); the `bash` package in `nvim.nix` is required by the Mason installer.

## Site-specific plugin loader

A sibling-repo home-manager module appends a snippet to `programs.neovim.initLua` (`lib.mkAfter`) that prepends an extra path to `&runtimepath` for site-specific plugins. Auto-loaded by the main flake's sibling-repo resolution (see `home-manager.configsymlink/AGENTS.md`). Guarded on `vim.fn.isdirectory` so machines without that path are unaffected.

## Universal copy/paste

`vimrcs/my-clipboard.lua` maps `<F24>`/`<F20>` AND `<XF86Copy>`/`<XF86Paste>` (sent by keyd's Super+C / Super+V macro): copy yanks visual selection / `<cword>` / cmdline (mode-aware) to `+`; paste uses `"+P` / `"_d"+P` / `<C-r>+` / `<C-\><C-n>"+pi`. Default `yy`/`p` registers stay independent — only Super+C/V crosses to `+`. See `keyd/AGENTS.md`.

## Known issues

- **fzf-lua**: `fzf_opts['--bind']` overwritten by `create_fzf_binds` — custom fzf binds must go through the `actions` table or `keymap.fzf`, not `fzf_opts`.
- **fzf-lua**: `ctrl-o` intercepted by neovim terminal mode; `ctrl-g` is fzf's default abort but can be overridden via Lua actions.
- **fzf `--bind`**: `transform(...)` parenthesis form breaks with nested parens — use the colon form `transform:` instead.
- **nvim-treesitter**: `ensure_installed` + `auto_install` fail trying to write to the nix store; use `auto_install = false` and `ensure_installed = {}`. nvim-treesitter 1.0 removed `nvim-treesitter.configs` module — `nvim-treesitter.lua` uses pcall for compat.
- **C++ treesitter textobjects**: `#make-range!` directives can silently fail; `@function.outer` misses lambdas. mini.ai pattern-based `f`/`a` is more reliable for C++.
