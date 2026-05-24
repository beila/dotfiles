{ pkgs, ... }:

let
  # Tiny C tool that polls XQueryKeymap until a named key is released.
  # Used by bin/copy-paste-route to wait for the user's still-held Super
  # to lift before xdotool dispatches Ctrl+Shift+C/V — otherwise the
  # synthetic keystroke gets paired with Super and falls through as `^V`,
  # or fires xmonad's Super+letter defaults. Compiled to a static binary
  # via stdenv, ~2ms cold start (vs 70ms for Python xlib). C over Haskell
  # because we want minimal RTS startup on every Super+V keypress.
  wait-for-key-release = pkgs.stdenv.mkDerivation {
    pname = "wait-for-key-release";
    version = "0.1.0";
    src = ../bin;
    buildInputs = [ pkgs.xorg.libX11 ];
    dontUnpack = true;
    buildPhase = ''
      $CC -O2 -Wall -Wextra -o wait-for-key-release \
        $src/wait-for-key-release.c -lX11
    '';
    installPhase = ''
      install -Dm755 wait-for-key-release $out/bin/wait-for-key-release
    '';
  };
in
{
  xsession.windowManager.xmonad = {
    enable = true;
    enableContribAndExtras = true;
    extraPackages = hp: [];
  };

  home.packages = [ pkgs.xfce4-panel pkgs.xfconf wait-for-key-release ];

  # Register xfconfd with dbus/systemd so xfce4-panel can persist config.
  # Re-runs on every home-manager switch to keep symlinks pointing to the
  # current nix store path.
  home.activation.xfconfDbus = ''
    XFCONF_STORE=$(${pkgs.nix}/bin/nix-store -qR ${pkgs.xfconf} | grep xfconf | head -1)
    mkdir -p ~/.local/share/dbus-1/services ~/.config/systemd/user
    ln -sf "$XFCONF_STORE/share/dbus-1/services/org.xfce.Xfconf.service" ~/.local/share/dbus-1/services/
    ln -sf "$XFCONF_STORE/share/systemd/user/xfconfd.service" ~/.config/systemd/user/
    systemctl --user daemon-reload 2>/dev/null || true
  '';
}
