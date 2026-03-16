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
  # awk             awk_ls (nix)               —                      —             —
  # bash/zsh        bashls (mason)             bash-debug-adapter     shellcheck    shfmt
  # c/c++           clangd (nix)               codelldb               cppcheck      clang-format
  # cmake           cmake (mason)              —                      —             cmake-format
  # docker          dockerls + compose (mason) —                      hadolint      —
  # glsl/opengl     glsl_analyzer (mason)      —                      —             clang-format
  # haskell         hls (mason)                haskell-debug-adapter  —             fourmolu
  # html/jinja      html (mason)               —                      —             prettier
  # json            jsonls (mason)             —                      jsonlint      prettier
  # js/jsx/ts       ts_ls (mason)              js-debug-adapter       eslint_d      prettier
  # jq              jqls (mason)               —                      —             jq
  # just            —                          —                      —             —
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
  # nix-installed tools are set up in vimrcs/lsp-servers.lua
  # Mason-installed tools are set up in vimrcs/mason.lua

  home.packages = with pkgs; [
    awk-language-server
  ];
}
