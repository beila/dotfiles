{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # Dev tool coverage for neovim (installed via nix or Mason)
  #
  # Language        LSP                        DAP                    Linter        Formatter
  # awk             awk_ls                     —                       —             —
  # bash/zsh        bashls                     bash-debug-adapter(m)   shellcheck    shfmt
  # c/c++           clangd(clang-tools)        codelldb(m)             cppcheck      clang-format(clang-tools)
  # cmake           neocmake(neocmakelsp)      —                       cmake-lint    cmake-format
  # docker          dockerls+compose           —                       hadolint      —
  # glsl/opengl     glsl_analyzer              —                       —             clang-format(clang-tools)
  # haskell         hls(haskell-language-server) haskell-debug-adapter(m) hlint       fourmolu
  # html            html(vscode-langservers-extracted) —              —             prettier
  # jinja           jinja_lsp(jinja-lsp)       —                       djlint        djlint
  # json            jsonls(vscode-langservers-extracted) —            (jsonls)      prettier
  # js/jsx/ts       ts_ls(typescript-language-server) vscode-js-debug  biome         prettier
  # just            just-lsp                   —                       —             just --fmt(just,home.nix)
  # kotlin          kotlin_language_server     kotlin-debug-adapter   ktlint        ktlint
  # makefile        —                          —                      checkmake     —
  # markdown        marksman (mason)           —                      markdownlint  prettier
  # nim             nimls (mason)              —                      —             —
  # nix             nil_ls (mason)             —                      statix        nixpkgs-fmt
  # python          pyright (mason)            debugpy                ruff          ruff
  # rust            rust_analyzer (mason)      codelldb               —             rustfmt
  # sql             sqlls (mason)              —                      sqlfluff      sql-formatter
  # toml            taplo (mason)              —                      —             (taplo LSP)
  # text            —                          —                      vale          —
  # vimscript       vimls (mason)              —                      —             —
  # lua             lua_ls (mason)             —                      luacheck      stylua
  # systemd         —                          —                      —             —
  #
  # nix-installed tools are set up in vimrcs/my-*.lua and vimrcs/lsp-servers.lua
  # Mason-installed tools are set up in vimrcs/mason.lua

  home.packages = with pkgs; [
    awk-language-server
    bash-language-server  # LSP for bash/zsh — setup in vimrcs/my-zsh.lua
    shfmt                 # formatter for bash/zsh — used by bashls in my-zsh.lua
    cppcheck              # linter for c/c++ — setup in my-cpp.lua
    clang-tools           # clangd + clang-format for c/c++ — setup in my-cpp.lua
    shellcheck            # linter for bash/zsh — used by bashls in my-zsh.lua
    neocmakelsp           # LSP for cmake — setup in my-cmake.lua
    cmake-format          # formatter for cmake — setup in my-cmake.lua
    cmake-lint            # linter for cmake — setup in my-cmake.lua
    dockerfile-language-server-nodejs  # LSP for Dockerfile — setup in my-docker.lua
    docker-compose-language-service    # LSP for docker-compose — setup in my-docker.lua
    hadolint              # linter for Dockerfile — setup in my-docker.lua
    glsl_analyzer         # LSP for GLSL/OpenGL — setup in my-glsl.lua
    haskell-language-server # LSP for Haskell — setup in my-haskell.lua
    fourmolu              # formatter for Haskell — used by HLS in my-haskell.lua
    hlint                 # linter for Haskell — used by HLS in my-haskell.lua
    vscode-langservers-extracted # html/css/json/eslint LSPs — setup in my-html.lua, my-json.lua
    prettier              # formatter for html/json/js/ts/md — setup in my-html.lua
    jinja-lsp             # LSP for Jinja — setup in my-jinja.lua
    djlint                # linter+formatter for Jinja/Nunjucks — setup in my-jinja.lua
    typescript-language-server # LSP for JS/TS — setup in my-js.lua
    vscode-js-debug       # DAP for JS/TS — setup in my-js.lua
    biome                 # linter for JS/TS — setup in my-js.lua
    just-lsp              # LSP for justfiles — setup in my-just.lua
  ];
}
