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
  # renderer and dzen2 can find them (they don't read nix font paths).
  # rm + cp instead of cp -u: nix store files are read-only, so cp -u
  # can't overwrite stale copies after a nix upgrade.
  home.activation.copyFonts = ''
    mkdir -p ~/.local/share/fonts
    rm -f ~/.local/share/fonts/JetBrainsMono*.ttf ~/.local/share/fonts/SourceCodePro*.otf 2>/dev/null || true
    cp ${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-*.ttf ~/.local/share/fonts/ 2>/dev/null || true
    cp ${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-*.ttf ~/.local/share/fonts/ 2>/dev/null || true
    cp ${pkgs.source-code-pro}/share/fonts/opentype/SourceCodePro-*.otf ~/.local/share/fonts/ 2>/dev/null || true
    fc-cache -f 2>/dev/null || true
  '';
}
