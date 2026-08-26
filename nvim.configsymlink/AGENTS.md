# Neovim — Context for AI Agent

`nvim.configsymlink/` symlinked to `~/.config/nvim`. Also symlinked to `~/.vim` via `vim.symlink → nvim.configsymlink`. If `~/.vim/myvimrc` is unreachable (vim.symlink missing/broken), `vimrc.symlink`'s `source ~/.vim/myvimrc` will error and abort everything downstream in `init.lua` — fix with `ln -sfn nvim.configsymlink ~/.dotfiles/vim.symlink`.

## Plugin management

All plugins installed via home-manager `programs.neovim.plugins` (see `home-manager.configsymlink/nvim.nix`); no submodules.

## Config loading

1. `init.lua` (git-tracked, ours) starts with `pcall(require, 'hm-generated')`.
2. `lua/hm-generated.lua` (nix-generated, gitignored) carries the nix-computed content: lua package paths, provider flags, plus any `initLua` appended by other modules (e.g. `work-dotfiles/nvim-amazon.nix`). Written via `xdg.configFile."nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua` in `home-manager.configsymlink/nvim.nix`; the module's own `nvim/init.lua` output is disabled with `mkForce false`, so nix never touches our `init.lua`. The `pcall` lets nvim boot (plugin-less) before the first home-manager switch.
3. `init.lua` sources `vimrc.symlink` (plus clipboard keymaps + yank highlight, formerly in `myinit.lua`, now merged in).
4. `vimrc.symlink` sources `myvimrc`.
5. `myvimrc` runs `runtime! vimrcs/*.vimrc`, `vimrcs/*.nvimrc`, `vimrcs/*.lua`.
6. nvim only loads `init.lua` (not `init.vim`/vimrc) when both exist.

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

Tool sources are nix (`home-manager.configsymlink/nvim.nix`) except **rust-analyzer**, which is configured from `work-dotfiles/`. nixd is installed through a small Home Manager wrapper that sets `NIX_PATH` to the same pinned nixpkgs revision; this prevents its package-evaluation helper from exiting on flake-only systems. `my-nix.lua` sends `vim.empty_dict()` because a plain empty Lua table is encoded as JSON `[]`, which nixd rejects.

## Shared config

- `vimrcs/lsp.lua` — keymaps incl. `<leader>e` floating diagnostic.
- `vimrcs/nvim-dap.lua` — codelldb + shared DAP keymaps.
- `vimrcs/nvim-lint.lua` — linter-by-filetype config.

## Plugin-specific

- **Autoformat** (`vimrcs/my-autoformat.lua`) — format on autosave via `CursorHold` / `BufLeave` / `FocusLost`, checks `vim.b.autoformat_fts`; per-project `.nvim.lua` sets `vim.b.autoformat_fts`. `myvimrc` sets `updatetime=10000` because CursorHold-triggered LSP format bumps `b:changedtick` and resets yank-cycle state (YankRing `<C-n>`/`<C-p>`).
- **Completion** (`vimrcs/blink-cmp.lua`) — blink.cmp.
- **DAP UI** (`vimrcs/nvim-dap-ui.lua`) — auto-open/close debug UI, F7 toggle.
- **Git gutter** (`vimrcs/gitsigns.lua`) — gitsigns.nvim with jj support (diffs against `@-` via `change_base`), `]c`/`[c` hunk nav, `<leader>hp` preview, `<leader>hr` reset, `<leader>hb` blame (no staging — safe for jj). The `jj log` base lookup is asynchronous, limited to one in-flight request, and times out after two seconds so `sync_repo` lock contention cannot freeze Neovim.
- **CodeDiff** (`vimrcs/codediff.lua`, `lua/jj-diff-picker.lua`) — CodeDiff 2.67 is pinned in `home-manager.configsymlink/nvim.nix` for gutter-sign support. `<leader>gh` / `<C-g><C-h>` opens the JJ revision picker; `<leader>gl` / `<C-g><C-l>` limits it to revisions touching the current file.
  In visual mode, the current-file mappings snapshot the saved JJ working copy and use `git log -L` to track the selected logical lines through line-number shifts. Those commit IDs are fed back into the JJ graph, while the preview shows only the tracked range's patch. `Ctrl-H` toggles that range filter against all revisions of the file.
  Enter compares one selected revision with its parent. Fzf multi-selection compares the sole parent of the oldest selected revision with the newest selected descendant, including any revisions between them. The pickers otherwise mirror `_gh`: `Ctrl-H` toggles default/full history, `Ctrl-S` toggles changed-file rows, `Ctrl-O` inserts an empty revision after the focused revision, and `Ctrl-X` copies selected Git commit IDs. Query and focus are retained across toggles.
  Current-file history starts at `all()`, labels that state `all file revisions`, and retains its path filter and JJ graph. Selections spanning unrelated branches or a merge root are rejected. `[c`/`]c` stop at the first/last hunk instead of cycling. Closing a CodeDiff tab returns to the tab that opened that specific session if it still exists.
  CodeDiff consumes Git commit objects. Line-range tracking uses Git's line-log engine because JJ has no line-history `revset`, so JJ mode requires a co-located Git/JJ repository. Outside JJ, the mappings retain the fzf-lua Git fallbacks. Regression coverage: `test_jj_diff_picker.lua`.
- **LSP enhancements** (`vimrcs/lsp_signature.lua`) — inlay hints + auto signature help.
- **LSP progress** (`vimrcs/fidget.lua`) — fidget.nvim.
- **Treesitter textobjects** (`vimrcs/nvim-treesitter.lua`) — `vaf`/`vif` function, `vac`/`vic` class, `vaa`/`via` parameter, `<leader>a`/`<leader>A` swap parameter; manual global keymaps (buffer-local may not attach).
- **mini.ai** (`vimrcs/mini-ai.lua`) — extended a/i textobjects; treesitter-powered `F` (function def), `c` (class); pattern-based `f`/`a` work better than treesitter for C++ templates.
- **nvim-surround** (`vimrcs/nvim-surround.lua`) — `ys`/`ds`/`cs` keybindings (matches zsh vi-mode surround).
- **Treesitter incremental selection** — `<C-e>` init/expand node, `<C-d>` shrink node (manual global keymaps).
- **Statusline** (`vimrcs/jj-statusline.lua`, `vimrcs/vim-airline.vimrc`) — airline section B keeps its Gitsigns hunk counts but shows the current JJ workspace name instead of the Git branch. The workspace lookup is asynchronous, uses `--ignore-working-copy`, is cached per window, refreshes when buffer/directory/focus/shell-command context changes, and stays blank outside JJ repositories.
- **Tabline** (`vimrcs/my-tabline.lua`) — custom `&tabline` showing `<tabnr> <path>` per tab (strips `$HOME/`, elides middle with `…` under tight budgets). Replaces nvim's default (which prepended a window-count digit) and airline's tabline extension (disabled in `vim-airline.vimrc`). Tab number highlighted via `MyTabNum`.
- **Indent detection** — vim-sleuth (auto-detects tabstop/shiftwidth).
- **Limelight** (`my-text.lua`) — auto-enabled for text, markdown, rst, org, asciidoc, tex, mail, gitcommit.
- **Table mode** (`my-markdown.lua`) — `silent! TableModeEnable` on markdown FileType.
- **fzf-lua** (`vimrcs/fzf.lua`) — `<leader>f` selects JJ/Git tracked files. `Ctrl-G` toggles submodule files, while `Ctrl-F` toggles all files and preserves the query. `<leader>F` lists all files, `<C-g><C-f>` lists changed files, and `Ctrl-N`/`Ctrl-P` scroll the preview. Global `--no-mouse` leaves dragging to Neovim for terminal text selection across every picker, including the CodeDiff JJ revision picker.

  **Grep dialog toggles** appear in a stacked header. `Ctrl-R` runs `actions.toggle_ignore`, `Ctrl-G` runs `actions.grep_lgrep`, `Ctrl-W` toggles `--word-regexp`, and `Ctrl-S` toggles `--case-sensitive`. The two flag toggles use a local `toggle_rg_flag` helper instead of `actions.toggle_flag`. It inserts the flag immediately before the trailing `-e`, keeping the user's query as the ripgrep pattern. It also positions the flag after `--smart-case`, so ripgrep's last case flag takes effect. `Ctrl-S` shadows the inherited `file_split` action only within grep.
- **Font** (`gvimrc`) — neovide guifont `JetBrains Mono Thin,LXGW WenKai Mono:h11` (Latin + Hangul/CJK fallback, matches ghostty). `:h<Size>` goes once at the very end; repeating per font fails with "Invalid size". `neovide.nix` copies LXGW Mono into `~/.local/share/fonts/` (skia ignores nix paths). Source Code Pro must be installed for neovide's default fallback.
- **Linting** — `nvim-lint` runs CLI linters (checkmake, hadolint, checkstyle, markdownlint-cli2, vale, statix, deadnix) on save. Vale covers the prose filetypes configured in `vimrcs/nvim-lint.lua`; `Vale.Spelling` is disabled because spelling has one shared source of truth below. `markdownlint-cli2` is fed via stdin, and over stdin it only auto-discovers a config in the *exact* cwd (no upward walk), so `~/.markdownlint-cli2.yaml` (which disables `line-length`) is ignored everywhere except `$HOME`. `nvim-lint.lua` overrides its args to pass `--config ~/.markdownlint-cli2.yaml` explicitly.
- **Prose grammar** — `vimrcs/harper.lua` enables `harper_ls` for text, markdown, gitcommit, rst, org, asciidoc, tex, and mail. It uses `spell/en.utf-8.add` as its user dictionary and disables `SpellCheck` plus `SentenceCapitalization`; the former is intentionally delegated to the lower-noise spelling layer.
- **Spell check** — nvim uses built-in `:set spell` (auto-on for markdown/gitcommit via `myvimrc`) with the personal allowlist at `spell/en.utf-8.add` (edit via `zg`; recompile the `.spl` with `:mkspell!`). **To spell-check the same way from the CLI / an agent session, run `spellcheck-md FILE...`** (`~/.dotfiles/bin/`): it runs codespell using that exact `en.utf-8.add` as the ignore-list, so results match nvim's highlighting. Prefer it over invoking `aspell`/`codespell` by hand — aspell can't even load the allowlist (rejects digit-suffixed words like `EC2`/`dup2`). The shared agent hook adds Harper grammar and Vale style checks around this spelling layer. See `~/.dotfiles/bin/AGENTS.md`.

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
