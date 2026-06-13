{ config, lib, pkgs, ... }:
{
  # GTK4 IM module for ibus, ABI-matched against the gtk4 closure ghostty links.
  # The system's ibus-gtk4 lives outside that closure so the nix gtk4 can't see it.
  home.packages = [ pkgs.ibus ];

  # systemd-user imports environment.d before gnome-flashback-xmonad, so xmonad
  # and its descendants inherit these. GTK_PATH must end in `/lib/gtk-4.0` —
  # GTK4 appends `<gtk_binary_version>/<host>/immodules` per entry.
  xdg.configFile."environment.d/30-ibus.conf".text = ''
    GTK_IM_MODULE=ibus
    QT_IM_MODULE=ibus
    XMODIFIERS=@im=ibus
    GTK_PATH=${pkgs.ibus}/lib/gtk-4.0
  '';

  dconf.settings = {
    # Single source: ibus-hangul. Hangul/English toggle happens *inside* the
    # engine via its `switch-keys`, not via IBus's source-switching hotkey.
    # The two-source pattern (xkb:us + ibus:hangul) is what GNOME Shell
    # offers, but xmonad+gnome-flashback doesn't run GNOME Shell — and the
    # ibus daemon itself doesn't grab the keyboard, so there's no neutral
    # actor to trigger source switches. Engine-internal toggling works
    # because application keystrokes are forwarded to the active engine
    # through the ibus IM client lib regardless of WM.
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.gvariant.mkTuple [ "ibus" "hangul" ])
      ];
    };
    # ibus-hangul: Sebeolsik 390. The hangul engine comes from the system
    # package (apt install ibus-hangul); only the GTK4 client module is
    # sourced from nix.
    "org/freedesktop/ibus/engine/hangul" = {
      hangul-keyboard = "39";
      hanja-keys = "F9";
      switch-keys = "Shift+space";
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = lib.gvariant.mkUint32 200;
      repeat-interval = lib.gvariant.mkUint32 15;
    };
    "org/gnome/gnome-flashback" = {
      desktop = false;
    };
    # Free up Super+V for our universal-paste binding (keyd's [meta] layer
    # emits M-v as the second token; gnome-shell otherwise grabs <Super>v
    # before any app sees it). Default was ['<Super>v', '<Super>m']; keep
    # message-tray on Super+M alone.
    "org/gnome/shell/keybindings" = {
      toggle-message-tray = [ "<Super>m" ];
    };
    # Fallback: empty gnome-panel layout (primary fix is session override below)
    "org/gnome/gnome-panel/layout" = {
      toplevel-id-list = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
    };
    "org/gnome/desktop/interface" = {
      cursor-size = 64;
    };
    "org/gnome/desktop/peripherals/mouse" = {
      speed = 0.75;
    };
  };

  # gnome-flashback provides org.gnome.Mutter.DisplayConfig DBus interface,
  # which GNOME Settings "Displays" panel needs.
  #
  # Problem: The stock metacity/compiz session targets include
  # Requires=gnome-flashback.target, but the xmonad session has no such
  # drop-in. Without it, gnome-flashback.service is never started by
  # systemd — it only runs if DBus-activated, which is unreliable after
  # hard power loss. This drop-in ensures systemd starts it with the session.
  xdg.configFile."systemd/user/gnome-session@gnome-flashback-xmonad.target.d/session.conf".text = ''
    [Unit]
    Requires=gnome-flashback.target
  '';

  # Remove restart rate limit so gnome-flashback recovers from repeated crashes.
  xdg.configFile."systemd/user/gnome-flashback.service.d/override.conf".text = ''
    [Unit]
    StartLimitIntervalSec=0

    [Service]
    Restart=always
    RestartSec=2s
  '';

  # Change lock screen wallpaper daily. Driven via dotfiles.schedule so the
  # backend (systemd-user vs cron) tracks the host. Only declared from this
  # gnome-only module, so non-GNOME hosts won't try to schedule it at all —
  # the gsettings call needs DBUS_SESSION_BUS_ADDRESS which only exists in
  # a graphical session.
  dotfiles.schedule.jobs.random-lockscreen = {
    description = "Set random lock screen wallpaper";
    command = "%h/.dotfiles/xwindow/bin/random-lockscreen";
    schedule = { systemd = "daily"; cron = "0 0 * * *"; };
    persistent = true;
  };

  # hangul-osd: persistent OSD shown while ibus-hangul is in Hangul mode.
  # Long-lived daemon — listens to gnome-flashback's InputSources `Changed`
  # D-Bus signal (push, no polling). PartOf=graphical-session.target so it
  # comes up with xmonad+gnome-flashback and dies when the session ends.
  systemd.user.services.hangul-osd = {
    Unit = {
      Description = "Hangul (Korean input) OSD indicator";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${config.home.profileDirectory}/bin/hangul-osd";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
