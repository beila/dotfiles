{ ... }:
{
  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "ctrl:nocaps" ];
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = 100;
      repeat-interval = 10;
    };
  };
}
