{ lib, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.gvariant.mkTuple [ "xkb" "us" ])
        (lib.gvariant.mkTuple [ "ibus" "hangul" ])
      ];
    };
    # ibus-hangul: use Sebeolsik 390 layout (requires: sudo apt install ibus-hangul)
    "org/freedesktop/ibus/general/hotkey" = {
      triggers = [ "<Shift>space" ];
    };
    "org/freedesktop/ibus/engine/hangul" = {
      hangul-keyboard = "39";
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = lib.gvariant.mkUint32 200;
      repeat-interval = lib.gvariant.mkUint32 15;
    };
    "org/gnome/gnome-flashback" = {
      desktop = false;
    };
    # Remove gnome-panel bars (replaced by xfce4-panel)
    "org/gnome/gnome-panel/layout" = {
      toplevel-id-list = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
    };
    "org/gnome/desktop/interface" = {
      cursor-size = 48;
    };
    "org/gnome/desktop/peripherals/mouse" = {
      speed = 0.75;
    };
  };

  # Change lock screen wallpaper daily
  systemd.user.services.random-lockscreen = {
    Unit.Description = "Set random lock screen wallpaper";
    Service.ExecStart = "%h/.dotfiles/xwindow/bin/random-lockscreen";
    Service.Type = "oneshot";
  };
  systemd.user.timers.random-lockscreen = {
    Unit.Description = "Daily random lock screen wallpaper";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
