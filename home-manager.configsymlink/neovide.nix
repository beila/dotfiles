{ config, pkgs, ... }:
let
  # Apply upstream fix 2cc8df2292378410e3026c1bb4df5f56144a5425 until nixos-unstable includes it.
  neovide =
    if
      pkgs.neovide.version == "0.17.1"
      && pkgs.neovide.src.outputHash == "sha256-ahqSduR4sCkcEmoo++PpxfcH0SZH4o6k/n8ZZmB1aA0="
    then
      pkgs.neovide.overrideAttrs {
        src = pkgs.fetchFromGitHub {
          owner = "neovide";
          repo = "neovide";
          tag = "0.17.1";
          hash = "sha256-trl/YctM/E9vIXeJfwBEZLfNK7LS5fEaWthTbeg7Ba0=";
        };
        cargoHash = "sha256-WS44afUizU6qhXQY77TayNRvlUoS6GrBZ/uaXk+gjU0=";
      }
    else
      pkgs.neovide;
in
{
  home.packages = [
    (config.lib.nixGL.wrap neovide)
    pkgs.jetbrains-mono
    pkgs.source-code-pro
  ];

  xdg.desktopEntries.neovide = {
    name = "Neovide";
    comment = "No Nonsense Neovim Client in Rust";
    # login shell needed so GNOME can find nix-installed neovide and nvim.
    # We tried WINIT_X11_SCALE_FACTOR=randr to fix winit's unreliable
    # ScaleFactorChanged on monitor *disconnect* under X11, but `randr`
    # uses each output's true physical PPI (3840×2400 / 344×215 mm ≈
    # 283 DPI → 2.95× scale on this laptop) which mismatches Xft.dpi=192
    # (2×) used by the rest of the system. Default mode reads Xft.dpi →
    # matches everything else; on monitor disconnect the scale may go
    # stale and a neovide restart is the workaround.
    exec = ''bash -lc "neovide %F"'';
    icon = "neovide";
    type = "Application";
    categories = [
      "Utility"
      "TextEditor"
    ];
  };

  # Copy nix-installed fonts to ~/.local/share/fonts so neovide's skia
  # renderer and dzen2 can find them (they don't read nix font paths).
  # rm + cp instead of cp -u: nix store files are read-only, so cp -u
  # can't overwrite stale copies after a nix upgrade.
  home.activation.copyFonts = ''
    mkdir -p ~/.local/share/fonts
    rm -f ~/.local/share/fonts/JetBrainsMono*.ttf ~/.local/share/fonts/SourceCodePro*.otf ~/.local/share/fonts/LXGWWenKaiMono-*.ttf 2>/dev/null || true
    cp ${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-*.ttf ~/.local/share/fonts/ 2>/dev/null || true
    cp ${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-*.ttf ~/.local/share/fonts/ 2>/dev/null || true
    cp ${pkgs.source-code-pro}/share/fonts/opentype/SourceCodePro-*.otf ~/.local/share/fonts/ 2>/dev/null || true
    cp ${pkgs.lxgw-wenkai}/share/fonts/truetype/LXGWWenKaiMono-*.ttf ~/.local/share/fonts/ 2>/dev/null || true
    fc-cache -f 2>/dev/null || true
  '';
}
