{ config, pkgs, ... }:
{
  home.packages = [
    (config.lib.nixGL.wrap pkgs.neovide)
    pkgs.jetbrains-mono
    pkgs.source-code-pro
  ];

  xdg.desktopEntries.neovide = {
    name = "Neovide";
    comment = "No Nonsense Neovim Client in Rust";
    # login shell needed so GNOME can find nix-installed neovide and nvim
    exec = ''bash -lc "neovide %F"'';
    icon = "neovide";
    type = "Application";
    categories = [ "Utility" "TextEditor" ];
  };

  # Copy nix-installed fonts to ~/.local/share/fonts so neovide's skia
  # renderer and dzen2 can find them (they don't read nix font paths)
  home.activation.copyFonts = ''
    mkdir -p ~/.local/share/fonts
    cp -u ${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-*.ttf ~/.local/share/fonts/ 2>/dev/null || true
    cp -u ${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-*.ttf ~/.local/share/fonts/ 2>/dev/null || true
    cp -u ${pkgs.source-code-pro}/share/fonts/opentype/SourceCodePro-*.otf ~/.local/share/fonts/ 2>/dev/null || true
    fc-cache -f 2>/dev/null || true
  '';
}
