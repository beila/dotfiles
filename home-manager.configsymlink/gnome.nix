{ lib, pkgs, ... }:
{
  # ibus-hangul, plus the GTK4 IM module so ghostty (which links the nix-store
  # gtk4-4.22.4 closure) finds it. The system's `ibus-gtk4` package only ships
  # `/usr/lib/x86_64-linux-gnu/gtk-4.0/.../libim-ibus.so`, which the nix gtk4
  # never looks at — it only searches its own closure + `$GTK_PATH`. nixpkgs
  # `ibus` builds the same module against the matching libgtk-4.so.1, so
  # GTK_PATH=${pkgs.ibus} resolves to an ABI-compatible drop-in.
  home.packages = [ pkgs.ibus ];

  # Emit ~/.config/environment.d/30-ibus.conf via home-manager.
  # systemd-user imports environment.d BEFORE gnome-flashback-xmonad, so xmonad
  # and every app it spawns (ghostty, firefox, etc.) inherits these. /etc/environment
  # already sets XMODIFIERS + QT_IM_MODULE on this Ubuntu box, but GTK_IM_MODULE
  # is left to im-config (which doesn't run for the custom xmonad session) — hence
  # we set it here unconditionally.
  xdg.configFile."environment.d/30-ibus.conf".text = ''
    GTK_IM_MODULE=ibus
    QT_IM_MODULE=ibus
    XMODIFIERS=@im=ibus
    GTK_PATH=${pkgs.ibus}
  '';

  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.gvariant.mkTuple [ "ibus" "hangul" ])
      ];
    };
    # ibus-hangul: use Sebeolsik 390 layout. The hangul *engine* itself still comes
    # from the system package (`sudo apt install ibus-hangul`); only the GTK4 IM
    # client module is sourced from nix above.
    "org/freedesktop/ibus/general/hotkey" = {
      triggers = [ "<Shift>space" ];
    };
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
  # gnome-only module, so non-GNOME hosts (electra) won't try to schedule it
  # at all — the gsettings call needs DBUS_SESSION_BUS_ADDRESS which only
  # exists in a graphical session.
  dotfiles.schedule.jobs.random-lockscreen = {
    description = "Set random lock screen wallpaper";
    command = "%h/.dotfiles/xwindow/bin/random-lockscreen";
    schedule = { systemd = "daily"; cron = "0 0 * * *"; };
    persistent = true;
  };
}
