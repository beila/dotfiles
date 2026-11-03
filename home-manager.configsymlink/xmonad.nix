{ lib, pkgs, ... }:

let
  xsecurelockPatchedSource = pkgs.applyPatches {
    name = "xsecurelock-ldap-source";
    src = pkgs.xsecurelock.src;
    patches = [
      ./patches/xsecurelock-ldap-username.patch
    ];
  };
  xsecurelockWithMpv = pkgs.xsecurelock.overrideAttrs (old: {
    src = xsecurelockPatchedSource;
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--with-mpv=${lib.getExe pkgs.mpv}"
    ];
  });
in
{
  xsession.windowManager.xmonad = {
    enable = true;
    enableContribAndExtras = true;
    extraPackages = hp: [ ];
  };

  home.packages = [
    pkgs.xfce4-panel
    pkgs.xfconf
    pkgs.xss-lock
    xsecurelockWithMpv
  ];

  systemd.user.services.screen-locker = {
    Unit = {
      Description = "X11 idle and suspend screen locker";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      StartLimitIntervalSec = 0;
    };
    Service = {
      ExecStart = "${pkgs.bash}/bin/bash ${../xwindow/bin/screen-locker-daemon}";
      Environment = [
        "PATH=${
          lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.util-linux
            pkgs.xset
            pkgs.xss-lock
            xsecurelockWithMpv
          ]
        }:/usr/bin:/bin"
      ];
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.activation.xsecurelockHostPam = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH=/usr/bin:/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gawk
      ]
    } \
      $HOME/.dotfiles/xwindow/bin/build-xsecurelock-authproto \
      ${xsecurelockPatchedSource} \
      ${pkgs.linux-pam}/include \
      $HOME/.local/libexec/xsecurelock/authproto_pam-host
  '';

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
