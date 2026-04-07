{ pkgs, ... }:

let
  _vim-vint = pkgs.vim-vint.overrideAttrs (_: { doCheck = false; doInstallCheck = false; });
in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    # Appended to nix-generated init.lua (which sets lua paths + providers).
    # nvim 0.12 only loads init.lua when it exists, ignoring init.vim/vimrc.
    # myinit.lua sources vimrc.symlink → myvimrc → vimrcs/*.lua
    # TODO: switch to hm-generated.lua approach (see home-manager PR #8586)
    initLua = builtins.readFile ../nvim.configsymlink/myinit.lua;
    plugins = with pkgs.vimPlugins; [
      vim-fugitive
      fzf-lua
      { plugin = fzf-vim; optional = true; }
      { plugin = fzf-wrapper; optional = true; }
      { plugin = nerdtree; optional = true; }
      github-nvim-theme
      lsp-zero-nvim
      lush-nvim
      mason-lspconfig-nvim
      mason-nvim
      mason-tool-installer-nvim
      neomru-vim
      nerdcommenter
      blink-cmp
      todo-comments-nvim
      lsp_signature-nvim
      nvim-dap
      nvim-dap-python
      nvim-dap-ui
      nvim-dap-vscode-js
      nvim-lint
      nvim-lspconfig
      nvim-nio
      nvim-tree-lua
      (nvim-treesitter.withAllGrammars)
      nvim-treesitter-textobjects
      nvim-web-devicons
      plantuml-syntax
      rustaceanvim
      tagbar
      typescript-vim
      undotree
      vim-airline
      vim-airline-themes
      vim-argumentative
      vim-dirdiff
      vim-fubitive
      vim-sleuth
      fidget-nvim
      gitsigns-nvim
      limelight-vim
      indent-blankline-nvim
      mini-ai
      nvim-surround
      vim-jinja
      vim-just
      vim-matchup
      vim-table-mode
      vimproc-vim
      vim-rhubarb
      YankRing-vim
      { plugin = pkgs.vimUtils.buildVimPlugin {
        pname = "vim-log-highlighting";
        version = "1.0.0";
        src = pkgs.fetchFromGitHub {
          owner = "MTDL9";
          repo = "vim-log-highlighting";
          rev = "1037e26f3120e6a6a2c0c33b14a84336dee2a78f";
          hash = "sha256-DqYSCtndUNIZsd9zpTFBhESXw3graNrjGC3WhcZ9uTA=";
        };
      }; }
    ];
  };

  # Dev tools for neovim — nix-installed unless noted
  # Mason-installed tools are listed as comments alongside their language group
  # Linters run via nvim-lint plugin (vimrcs/nvim-lint.lua)
  # All languages have setup in vimrcs/my-*.lua

  home.packages = with pkgs; [
    bash                               # mason       —          needed by Mason installer
    python3                            # mason       —          venv support for debugpy install (system python3 lacks ensurepip)

    # awk
    awk-language-server                # awk         LSP        my-awk.lua (awk_ls)

    # bash/zsh
    bash-language-server               # bash/zsh    LSP        my-zsh.lua (bashls)
    # bash-debug-adapter               # bash/zsh    DAP        my-zsh.lua (mason)
    shellcheck                         # bash/zsh    linter     my-zsh.lua (via bashls)
    shfmt                              # bash/zsh    formatter  my-zsh.lua (via bashls)

    # c/c++
    clang-tools                        # c/c++       LSP+fmt    my-cpp.lua (clangd + clang-format)
    # codelldb                         # c/c++/rust  DAP        nvim-dap.lua, my-rust.lua (mason)
    cppcheck                           # c/c++       linter     my-cpp.lua

    # cmake
    neocmakelsp                        # cmake       LSP        my-cmake.lua (neocmake)
    cmake-lint                         # cmake       linter     my-cmake.lua
    cmake-format                       # cmake       formatter  my-cmake.lua

    # docker
    dockerfile-language-server          # docker      LSP        my-docker.lua (dockerls)
    docker-compose-language-service    # docker      LSP        my-docker.lua (docker_compose_language_service)
    hadolint                           # docker      linter     my-docker.lua

    # glsl
    glsl_analyzer                      # glsl        LSP        my-glsl.lua

    # haskell
    pkgs.haskellPackages.haskell-language-server  # haskell     LSP        my-haskell.lua (hls) — from haskellPackages to match GHC
    pkgs.haskellPackages.ghc                     # haskell     compiler   must match HLS (same package set)
    hlint                              # haskell     linter     my-haskell.lua (via HLS)
    fourmolu                           # haskell     formatter  my-haskell.lua (via HLS)

    # html
    vscode-langservers-extracted       # html/json   LSP        my-html.lua, my-json.lua, my-css.lua (html, jsonls, cssls)
    prettier                           # html/md/js  formatter  my-html.lua, my-css.lua, my-yaml.lua

    # java
    jdt-language-server                # java        LSP        my-java.lua (jdtls)
    # java-debug-adapter               # java        DAP        my-java.lua (mason)
    checkstyle                         # java        linter     nvim-lint.lua
    google-java-format                 # java        formatter  my-java.lua

    # jinja
    jinja-lsp                          # jinja       LSP        my-jinja.lua (jinja_lsp)
    djlint                             # jinja       lint+fmt   my-jinja.lua

    # js/ts
    typescript-language-server         # js/ts       LSP        my-js.lua (ts_ls)
    vscode-js-debug                    # js/ts       DAP        my-js.lua
    biome                              # js/ts       linter     my-js.lua

    # just
    just-lsp                           # just        LSP        my-just.lua

    # kotlin
    kotlin-language-server             # kotlin      LSP        my-kotlin.lua (kotlin_language_server)
    # kotlin-debug-adapter             # kotlin      DAP        my-kotlin.lua (mason)
    ktlint                             # kotlin      lint+fmt   my-kotlin.lua

    # lua
    lua-language-server                # lua         LSP        my-lua.lua (lua_ls)
    selene                             # lua         linter     my-lua.lua
    stylua                             # lua         formatter  my-lua.lua

    # makefile
    checkmake                          # makefile    linter     nvim-lint.lua

    # markdown
    marksman                           # markdown    LSP        my-markdown.lua
    markdownlint-cli2                  # markdown    linter     nvim-lint.lua

    # nim
    nimlangserver                      # nim         LSP        my-nim.lua (nim_langserver)
    nim                                # nim         formatter  my-nim.lua (nimpretty)

    # nix
    nixd                               # nix         LSP        my-nix.lua
    statix                             # nix         linter     nvim-lint.lua
    deadnix                            # nix         linter     nvim-lint.lua
    nixfmt                             # nix         formatter  my-nix.lua

    # python
    basedpyright                       # python      LSP        my-python.lua
    # debugpy                          # python      DAP        my-python.lua (mason)
    ruff                               # python      lint+fmt   my-python.lua

    # rust
    rust-analyzer                      # rust        LSP        my-rust.lua (rustaceanvim)
    # codelldb                         # rust        DAP        my-rust.lua (mason, shared with c/c++)
    clippy                             # rust        linter     my-rust.lua (via rust-analyzer)
    rustfmt                            # rust        formatter  my-rust.lua (via rust-analyzer)

    # sql
    sqls                               # sql         LSP        my-sql.lua
    sqlfluff                           # sql         lint+fmt   nvim-lint.lua

    # text
    vale                               # text        linter     nvim-lint.lua

    # toml
    taplo                              # toml        LSP+all    my-toml.lua

    # vimscript
    vim-language-server                # vimscript   LSP        my-vim.lua (vimls)
    _vim-vint                          # vimscript   linter     nvim-lint.lua (vint, tests disabled)

    # xml
    lemminx                            # xml         LSP+all    my-xml.lua

    # yaml
    yaml-language-server               # yaml        LSP        my-yaml.lua (yamlls)
  ];
}
