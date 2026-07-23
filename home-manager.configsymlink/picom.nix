# picom compositor — focused-window glow only.
#
# Paired with xmonad's 1px #F8BB3D border (xwindow/xmonad.symlink/xmonad.hs):
# the border gives the crisp edge, picom's shadow — same LEGO-orange tint,
# centred, focused-only — adds a soft gradient halo around it. Earlier "no
# compositor for cosmetics" stance (xwindow/AGENTS.md) was overridden by
# explicit user preference for a gradient focus indicator (2026-07-13).
#
# The shadow renders at the window's Z-level, so it is only visible where
# no higher-stacked window overlaps it. xmonad's `raiseFocused` logHook
# keeps the focused window on top of the stack so its glow paints above
# tiled neighbors on every side.
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
      # dzen2 OSDs (volume/brightness/audio-cycle): no glow (they draw
      # their own look), but picom makes them 80% transparent via opacityRules.
      "class_g = 'dzen'"
    ];
    opacityRules = [
      "80:class_g = 'dzen'"
    ];
    settings = {
      shadow-radius = 14;
      shadow-color = "#F8BB3D";
      # A fullscreen window's glow otherwise spills onto the adjacent
      # monitor, reading as a focus indicator for whatever sits there.
      crop-shadow-to-monitor = true;
      # xmonad sets _NET_ACTIVE_WINDOW correctly; without this, picom uses
      # FocusIn/Out events which can mark windows on inactive monitors as
      # focused (giving them glow they shouldn't have).
      use-ewmh-active-win = true;
    };
  };
}
