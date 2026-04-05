{ pkgs, ... }:
{
  xsession.windowManager.xmonad = {
    enable = true;
    enableContribAndExtras = true;
    extraPackages = hp: [];
  };

  home.packages = [ pkgs.xfce4-panel pkgs.xfconf ];

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
