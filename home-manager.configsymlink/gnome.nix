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
    # Two input sources so that Shift+Space switches between English (xkb:us)
    # and Hangul (ibus-hangul) at the IBus level — this fires the
    # GlobalEngineChanged D-Bus signal, which `hangul-osd` subscribes to.
    # The single-source setup (only ibus:hangul, with Shift+Space toggling
    # within the engine) was indistinguishable from the outside; ibus-hangul's
    # internal mode flips don't surface on D-Bus.
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.gvariant.mkTuple [ "xkb" "us" ])
        (lib.gvariant.mkTuple [ "ibus" "hangul" ])
      ];
    };
    # ibus-hangul: Sebeolsik 390. The hangul engine comes from the system
    # package (apt install ibus-hangul); only the GTK4 client module is
    # sourced from nix.
    #
    # Hotkey trigger Shift+Space is the IBus-level source switcher (preferred
    # over GNOME's `switch-input-source` because it works under xmonad/
    # gnome-flashback too — GNOME Shell's keybinding handler is not running).
    # NOTE: schema path is /desktop/ibus/general/hotkey/, NOT
    # /org/freedesktop/ibus/general/hotkey/ — the latter writes to dconf but
    # the gsettings schema doesn't read from there, so it silently no-ops.
    "desktop/ibus/general/hotkey" = {
      triggers = [ "<Shift>space" ];
    };
    "org/freedesktop/ibus/engine/hangul" = {
      hangul-keyboard = "39";
      hanja-keys = "F9";
      # Empty: don't toggle within the hangul engine — the source switch
      # above does the English/Hangul flip and emits a D-Bus signal we can
      # observe. Leaving Shift+space here would still work (IBus consumes
      # the hotkey before the engine sees it) but blanking it avoids future
      # confusion if the source list shrinks back to one.
      switch-keys = "";
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

  # hangul-osd: persistent OSD shown on every monitor while ibus's current
  # engine is hangul. Long-lived daemon (subscribes to ibus's
  # global-engine-changed D-Bus signal). Tied to the graphical session so
  # it starts when xmonad+gnome-flashback comes up and dies when the
  # session ends. Only declared from gnome.nix because hangul-osd is
  # useless without ibus, and ibus only runs in this module's hosts.
  systemd.user.services.hangul-osd = {
    Unit = {
      Description = "Hangul (Korean input) OSD indicator";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "ibus-daemon.service" ];
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
