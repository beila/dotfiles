# input-remapper presets

Managed by input-remapper-daemon (apt). Autoloads on device connect.

## Logitech USB Optical Mouse — left-handed.json
Swap left/right buttons (BTN_LEFT ↔ BTN_RIGHT).

## ExpertBT5.0 Mouse (Kensington Expert Trackball BT) — remap.json
Left-hand button remap matching `xmodmap "pointer = 2 3 1"`:
- BTN_LEFT(272) → Alt+Tab — toggle last two windows
- BTN_MIDDLE(274) → BTN_RIGHT(273)
- BTN_RIGHT(273) → BTN_LEFT(272)
- BTN_SIDE(275) → Super(125) — opens GNOME overview

## Kinesis Advantage2 Keyboard — remap.json
- Left Ctrl(29) → Super/Win(125)
- Right Ctrl(97) → Super/Win(125)
- Right Super(126) → Right Ctrl(97)
- Pause/Break(119) → Volume Up(115)
- Scroll Lock(70) → Volume Down(114)
- Print Screen(99) → Mute(113)
