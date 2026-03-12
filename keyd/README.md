# keyd — system-level key remapping

System daemon, applies at evdev level.
Not affected by GNOME keymap resets.

Split into three files:
- `common` — shared bindings included by both configs
- `default.conf` — all keyboards except Kinesis, includes common
- `kinesis.conf` — Kinesis Advantage2 aliases (Mac mode) + includes common

See each file for detailed comments and layout diagrams.

## xmonad key bindings (tap actions)

- prog1/XF86Launch1 (Super tap) → Albert toggle
- prog2/XF86Launch2 (Alt_L tap) → ghostty scratchpad 1
- prog3/XF86Launch3 (Alt_R tap) → ghostty scratchpad 2
- VolumeUp/Down/Mute → volume-osd
- Super+VolumeUp → cycle-audio-output
- Super+VolumeDown → cycle-audio-input
