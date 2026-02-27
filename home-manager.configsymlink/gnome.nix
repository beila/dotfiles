{ lib, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "ctrl:nocaps" ];
      sources = [
        (lib.gvariant.mkTuple [ "xkb" "us" ])
        (lib.gvariant.mkTuple [ "ibus" "hangul" ])
      ];
    };
    # ibus-hangul: use 3-bulsik layout (requires: sudo apt install ibus-hangul)
    "org/freedesktop/ibus/engine/hangul" = {
      hangul-keyboard = "3f";
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = lib.gvariant.mkUint32 200;
      repeat-interval = lib.gvariant.mkUint32 15;
    };
    "org/gnome/desktop/peripherals/mouse" = {
      speed = 0.75;
    };
  };
}
