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
  # java            jdtls(jdt-language-server) java-debug-adapter(m)   checkstyle    google-java-format
  # json            jsonls(vscode-langservers-extracted) —            (jsonls)      prettier
  # js/jsx/ts       ts_ls(typescript-language-server) vscode-js-debug  biome         prettier
  # just            just-lsp                   —                       —             just --fmt(just,home.nix)
  # kotlin          kotlin_language_server     kotlin-debug-adapter(m) ktlint       ktlint
  # lua             lua_ls(lua-language-server) —                       selene        stylua
  # makefile        autotools_ls(autotools-language-server) —          checkmake     —
  # markdown        marksman                   —                       markdownlint-cli2 prettier
  # nim             nim_langserver(nimlangserver) —                    —             nimpretty(nim)
  # nix             nixd                       —                       statix+deadnix nixfmt
  # python          basedpyright               debugpy(m)              ruff          ruff
  # rust            rust_analyzer (mason)      codelldb               —             rustfmt
  # sql             sqlls (mason)              —                      sqlfluff      sql-formatter
  # toml            taplo (mason)              —                      —             (taplo LSP)
  # text            —                          —                      vale          —
  # vimscript       vimls (mason)              —                      —             —
  # systemd         —                          —                      —             —
  #
  # nix-installed tools are set up in vimrcs/my-*.lua and vimrcs/lsp-servers.lua
  # Mason-installed tools are set up in vimrcs/mason.lua

  home.packages = with pkgs; [
    bash                  # needed by Mason installer (exit code 127 without it)
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
    kotlin-language-server # LSP for Kotlin — setup in my-kotlin.lua
    ktlint                # linter+formatter for Kotlin — setup in my-kotlin.lua
    jdt-language-server   # LSP for Java — setup in my-java.lua
    google-java-format    # formatter for Java — setup in my-java.lua
    checkstyle            # linter for Java — setup in my-java.lua
    lua-language-server   # LSP for Lua — setup in my-lua.lua
    selene                # linter for Lua — setup in my-lua.lua
    stylua                # formatter for Lua — setup in my-lua.lua
    checkmake             # linter for Makefile — setup in my-makefile.lua
    # autotools-language-server — broken in nixpkgs, not in mason; revisit on flake update
    marksman              # LSP for Markdown — setup in my-markdown.lua
    markdownlint-cli2     # linter for Markdown — setup in my-markdown.lua
    nimlangserver         # LSP for Nim — setup in my-nim.lua
    nim                   # compiler + nimpretty formatter — setup in my-nim.lua
    nixd                  # LSP for Nix — setup in my-nix.lua
    statix                # linter for Nix — setup in my-nix.lua
    deadnix               # dead code finder for Nix — setup in my-nix.lua
    nixfmt                # official formatter for Nix — setup in my-nix.lua
    basedpyright          # LSP for Python — setup in my-python.lua
    ruff                  # linter+formatter for Python — setup in my-python.lua
  ];
}
