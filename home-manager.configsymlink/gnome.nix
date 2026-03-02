{ lib, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.gvariant.mkTuple [ "xkb" "us" ])
        (lib.gvariant.mkTuple [ "ibus" "hangul" ])
      ];
    };
    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = [ "<Shift>space" ];
      switch-input-source-backward = [ "<Shift><Super>space" ];
    };
    # ibus-hangul: use 3-bulsik layout (requires: sudo apt install ibus-hangul)
    "org/freedesktop/ibus/general/hotkey" = {
      triggers = [ "<Shift>space" ];
    };
    "org/freedesktop/ibus/engine/hangul" = {
      hangul-keyboard = "3f";
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
    "org/gnome/desktop/peripherals/mouse" = {
      speed = 0.75;
    };
  };
}
