{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # Neovim dependencies (LSPs, formatters, DAP)
  home.packages = with pkgs; [
    biome
    cargo   # rust-analyzer from Mason
    python3    # gersemi (CMake formatter)
    taplo   # TOML language server
    uv      # nvim-dap-python
  ];
}
