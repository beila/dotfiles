# nvim-amazon

A small Neovim plugin with Amazon-internal conveniences:

- **Barium LSP** for Brazil `Config` files (via `nvim-lspconfig`)
- **Bemol workspace-folder support** that adds `ws_root_folders` entries to
  LSP workspace folders when a `.bemol/` directory is found upward from the
  current buffer. Activates automatically on `LspAttach` for `*.java`,
  `*.py`, `*.rb`.
- **`:GBrowse` → code.amazon.com** via `fugitive-gitfarm.vim`: opens the
  current file or a range at the right GitFarm URL, for repositories cloned
  via `ssh://[user@]git.amazon.com[:port]/pkg/<package>`.

Source: `https://w.amazon.com/bin/view/Users/Ethdestr/vim/#HNeovimLocalConfiguration` (Barium + Bemol snippets), with `fugitive-gitfarm.vim` by Benoît Taine.

> **Note**: the plugin source (`plugin/init.lua`, `plugin/fugitive-gitfarm.vim`) was written by people; this README was drafted by an AI assistant. Corrections welcome.

## Requirements

- Neovim (tested with 0.12); the lua init uses `vim.filetype.add`, `vim.fs.find`,
  `vim.lsp.buf.add_workspace_folder`, etc.
- [`nvim-lspconfig`](https://github.com/neovim/nvim-lspconfig) — required by
  `plugin/init.lua` for the Barium registration.
- [`vim-fugitive`](https://github.com/tpope/vim-fugitive) — required for
  `:GBrowse` integration from `plugin/fugitive-gitfarm.vim`.
- `barium` binary on `$PATH` if you want the Brazil Config LSP to start.

## Install

Pick whichever fits your nvim setup. All of these drop the plugin into
`&runtimepath` so the files under `plugin/` load automatically at startup.

### 1. Neovim native package (no plugin manager)

Symlink this directory into nvim's `pack/<group>/start/` so nvim discovers it
as a package:

```sh
mkdir -p ~/.config/nvim/pack/local/start
ln -s "$(pwd)" ~/.config/nvim/pack/local/start/nvim-amazon
```

Use `opt/` instead of `start/` if you prefer to load it manually with
`:packadd nvim-amazon`.

### 2. Direct `runtimepath` prepend (lua)

Put this in your `init.lua` (or any lua file sourced during startup):

```lua
local amazon = vim.fn.expand('~/path/to/nvim-amazon')
if vim.fn.isdirectory(amazon) == 1 then
  vim.opt.runtimepath:prepend(amazon)
end
```

### 3. home-manager (nix)

Append to `programs.neovim.initLua` using `lib.mkAfter` so it runs after
your main init:

```nix
{ lib, ... }:
{
  programs.neovim.initLua = lib.mkAfter ''

    do
      local amazon = vim.fn.expand('~/path/to/nvim-amazon')
      if vim.fn.isdirectory(amazon) == 1 then
        vim.opt.runtimepath:prepend(amazon)
      end
    end
  '';
}
```

Keep this module out of public dotfiles if you don't want Amazon-internal
references there — put it in a private flake input instead.

### 4. lazy.nvim / packer / other plugin managers

Point the manager at this directory as a local plugin. For lazy.nvim:

```lua
{ dir = vim.fn.expand('~/path/to/nvim-amazon'), name = 'nvim-amazon' }
```

## Verify it loaded

```vim
:lua =vim.o.runtimepath                                         " nvim-amazon appears early
:lua =require('lspconfig.configs').barium ~= nil                " true
:lua =vim.filetype.match({ filename = 'Config' })               " 'brazilconfig'
:echo g:fugitive_browse_handlers                                " has at least one Funcref
```

In a Brazil workspace, open a `Config` file and confirm Barium is attached
via `:LspInfo`. With a buffer open inside a package clone, try
`:GBrowse` — a browser tab should open at
`https://code.amazon.com/packages/<pkg>/blobs/<commit>/--/<path>`.

## Troubleshooting

All vim/nvim error messages also land in `~/.vim-messages.log` if your
config sets `set verbosefile=~/.vim-messages.log`. Without that, use
`:messages` inside nvim.

- **`fugitive: no GBrowse handler installed for '...'`**: your `origin`
  (or whatever remote you're browsing) didn't match the handler's regex.
  The handler matches
  `^ssh://[user@]?git.amazon.com[:port]?/pkg/<name>$` where `<name>` may
  include letters, digits, `_`, `.`, and `-`. Remotes with extra path
  components (e.g. `/pkg/<name>/backup/hojin`) are intentionally not
  matched — browse via `origin` rather than the backup remote. If your
  package name legitimately contains other characters, extend
  `[[:alnum:]_.-]\+` in `plugin/fugitive-gitfarm.vim`. An earlier version
  of that regex used `\w\+` which missed hyphens; update if you have an
  old copy.
- **`E481: No range allowed`**: you ran `:'<,'>Gbrowse` (lowercase) on
  recent vim-fugitive. The lowercase alias is a no-range deprecation stub
  in current fugitive. Use `:GBrowse` (capital `B`), which supports a
  range. Or set `let g:fugitive_legacy_commands = 1` to restore the old
  behaviour (fugitive will also print deprecation warnings, and the alias
  is likely to be removed in a future version).
- **Barium not attaching**: ensure `barium` is on `$PATH`, and that you
  opened a `Config` file inside a git repo (the LSP's `root_dir` is the
  nearest `.git/` ancestor).
- **`.bemol` workspace folders not added**: run `:BemolAdditions` manually
  to see a diagnostic. The `LspAttach` autocmd only fires for
  `*.java|*.py|*.rb`; adapt the pattern if you use other languages.

## Uninstall

Remove from your init (or the symlink under `pack/local/start/`) and
restart nvim.

## File layout

```
plugin/
  init.lua               -- Barium + Bemol (lua)
  fugitive-gitfarm.vim   -- :GBrowse handler (vimscript)
```

Both are standard nvim `plugin/*` files, auto-sourced once the directory
is on `&runtimepath`.

## License

Internal Amazon use. Redistribute only within Amazon.
