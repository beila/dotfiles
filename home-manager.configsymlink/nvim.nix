{ pkgs, ... }:

{
  # Dependencies for Neovim (previously in nvim/flake.nix devShell)
  home.packages = with pkgs; [
    biome
    cargo   # rust-analyzer from Mason
    neovim
    taplo  # TOML language server
    uv  # nvim-dap-python
  ];
}
