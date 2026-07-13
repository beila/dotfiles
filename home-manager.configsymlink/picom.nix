# picom compositor — focused-window glow only.
#
# Paired with xmonad's 2px #F8BB3D border (xwindow/xmonad.symlink/xmonad.hs):
# the border gives the crisp edge, picom's shadow — same LEGO-orange tint,
# centred, focused-only — adds a soft gradient halo around it. Earlier "no
# compositor for cosmetics" stance (xwindow/AGENTS.md) was overridden by
# explicit user preference for a gradient focus indicator (2026-07-13).
#
# xrender backend: shadows-only workload is cheap there and it avoids
# GL-driver mismatch on non-NixOS hosts (no nixGL wrapper needed).
# Runs under graphical-session.target, so display-less hosts (electra)
# never start it.
{ ... }:
{
  services.picom = {
    enable = true;
    backend = "xrender";
    shadow = true;
    # Full opacity: the gaussian edge already sits at ~50% of peak, so
    # anything below 1.0 makes the glow start visibly dimmer than the
    # border it's supposed to continue from.
    shadowOpacity = 1.0;
    # Centre the glow: offset = -radius, no directional drop-shadow look.
    shadowOffsets = [ (-14) (-14) ];
    shadowExclude = [
      "!focused"
      "window_type = 'dock'"
      "window_type = 'desktop'"
      "window_type = 'notification'"
      # dzen2 OSDs (volume/brightness/audio-cycle) and XShape OSD popups
      # draw their own look; a glow behind them is just noise.
      "class_g = 'dzen'"
    ];
    settings = {
      shadow-radius = 14;
      shadow-color = "#F8BB3D";
    };
  };
}
