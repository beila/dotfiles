# keyd — system-level key remapping

System daemon, applies at evdev level.
Not affected by GNOME keymap resets.

Split into four files:
- `common` — shared bindings included by all configs
- `default.conf` — all keyboards except Kinesis/ThinkPad, includes common
- `kinesis.conf` — Kinesis Advantage2 aliases (Mac mode) + includes common
- `thinkpad.conf` — ThinkPad laptop keyboard, Copilot key remap + includes common

See each file for detailed comments and layout diagrams.

## xmonad key bindings (tap actions)

- prog1/f21/XF86TouchpadToggle (Super tap) → Albert toggle
- prog2/f22/XF86TouchpadOn (Alt_L tap) → ghostty scratchpad 1
- prog3/f23/XF86TouchpadOff (Alt_R tap) → ghostty scratchpad 2
- Note: keyd v2.6.0 maps prog1/2/3 to f21/f22/f23 (evdev 191/192/193), not KEY_PROG1/2/3
- VolumeUp/Down/Mute → volume-osd
- BrightnessUp/Down → brightness-osd
- Super+VolumeUp → cycle-audio-output
- Super+VolumeDown → cycle-audio-input
