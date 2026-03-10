# input-remapper presets

Managed by input-remapper-daemon (apt). Autoloads on device connect.

## Logitech USB Optical Mouse — left-handed.json
Swap left/right buttons (BTN_LEFT ↔ BTN_RIGHT).

## ExpertBT5.0 Mouse (Kensington Expert Trackball BT) — remap.json
Left-hand button remap:
- BTN_LEFT(272) → Super+Tab — switch windows
- BTN_MIDDLE(274) → BTN_RIGHT(273)
- BTN_RIGHT(273) → BTN_LEFT(272)
- BTN_SIDE(275) → Super+Shift+C — close window

## Kinesis Advantage2 Keyboard (Mac mode) — remap.json

The keyboard is in Mac mode, which swaps Ctrl↔Cmd at the hardware level.
Keycodes below are what Linux actually sees (evdev codes).

### Physical Layout (Mac mode keycodes)

In Mac mode the top four thumb keys are: Cmd | Option | Ctrl | Cmd (left to right).
Keycodes shown are what Linux sees (evdev), not what the keycap says.

```
LEFT HAND                                              RIGHT HAND

 ┌─────┬─────┬─────┬─────┬─────┬─────┐  ┌─────┬─────┬─────┬─────┬─────┬─────┐
 │ =   │ 1   │ 2   │ 3   │ 4   │ 5   │  │ 6   │ 7   │ 8   │ 9   │ 0   │ -   │
 │(13) │     │     │     │     │     │  │     │     │     │     │     │(12) │
 ├─────┼─────┼─────┼─────┼─────┼─────┤  ├─────┼─────┼─────┼─────┼─────┼─────┤
 │Tab  │ Q   │ W   │ E   │ R   │ T   │  │ Y   │ U   │ I   │ O   │ P   │ \   │
 │     │     │     │     │     │     │  │     │     │     │     │     │(43) │
 ├─────┼─────┼─────┼─────┼─────┼─────┤  ├─────┼─────┼─────┼─────┼─────┼─────┤
 │Caps │ A   │ S   │ D   │ F   │ G   │  │ H   │ J   │ K   │ L   │ ;   │ '   │
 │     │     │     │     │     │     │  │     │     │     │     │     │(40) │
 ├─────┼─────┼─────┼─────┼─────┼─────┤  ├─────┼─────┼─────┼─────┼─────┼─────┤
 │LShft│ Z   │ X   │ C   │ V   │ B   │  │ N   │ M   │ ,   │ .   │ /   │RShft│
 └─────┴─────┴─────┴─────┴─────┴─────┘  └─────┴─────┴─────┴─────┴─────┴─────┘

         LEFT THUMB CLUSTER                      RIGHT THUMB CLUSTER

              ┌─────┬─────┐        ┌─────┬─────┬─────┐
              │ Cmd │ Opt │        │Ctrl │ Cmd │     │
              │(29) │(56) │        │(126)│(97) │     │
        ┌─────┼─────┼─────┤        ├─────┼─────┤Space│
        │BkSp │ Del │Home │        │PgDn │     │     │
        │     │     │     │        │(109)│Enter│     │
        │     │     ├─────┤        ├─────┤     │     │
        │     │     │ End │        │PgUp │     │     │
        │     │     │(107)│        │(104)│     │     │
        └─────┴─────┴─────┘        └─────┴─────┴─────┘
```

### Remappings (input-remapper)

Only remapped keys shown. Blank = unchanged.

```
LEFT HAND                                              RIGHT HAND

 ┌─────┬─────┬─────┬─────┬─────┬─────┐  ┌─────┬─────┬─────┬─────┬─────┬─────┐
 │ Esc │     │     │     │     │     │  │     │     │     │     │     │ Esc │
 │(13→1)     │     │     │     │     │  │     │     │     │     │     │(12→1)
 ├─────┼─────┼─────┼─────┼─────┼─────┤  ├─────┼─────┼─────┼─────┼─────┼─────┤
 │     │     │     │     │     │     │  │     │     │     │     │     │ Tab │
 │     │     │     │     │     │     │  │     │     │     │     │     │(43→15)
 ├─────┼─────┼─────┼─────┼─────┼─────┤  ├─────┼─────┼─────┼─────┼─────┼─────┤
 │     │     │     │     │     │     │  │     │     │     │     │     │RCtrl│
 │     │     │     │     │     │     │  │     │     │     │     │     │(40→97)
 ├─────┼─────┼─────┼─────┼─────┼─────┤  ├─────┼─────┼─────┼─────┼─────┼─────┤
 │     │     │     │     │     │     │  │     │     │     │     │     │     │
 └─────┴─────┴─────┴─────┴─────┴─────┘  └─────┴─────┴─────┴─────┴─────┴─────┘

         LEFT THUMB CLUSTER                      RIGHT THUMB CLUSTER

              ┌─────┬─────┐        ┌─────┬─────┬─────┐
              │Super│  =  │        │  -  │Super│     │
              │(29→ │(56→ │        │(126→│(97→ │     │
              │125) │ 13) │        │ 12) │125) │     │
        ┌─────┼─────┼─────┤        ├─────┼─────┤     │
        │     │     │     │        │RAlt │     │     │
        │     │     │     │        │(109→│     │     │
        │     │     ├─────┤        │100) │     │     │
        │     │     │LAlt │        ├─────┤     │     │
        │     │     │(107→│        │  \  │     │     │
        │     │     │ 56) │        │(104→│     │     │
        └─────┴─────┴─────┘        │ 43) │     │     │
                                   └─────┴─────┴─────┘
```

### xcape (tap behavior for modifiers)
- Super tap → Albert (XF86Launch1)
- Alt_L tap → ghostty scratchpad 1 (XF86Launch2)
- Alt_R tap → ghostty scratchpad 2 (XF86Launch3)
- Ctrl_R tap → apostrophe

### Summary table

| Physical key     | Evdev | Remapped to     | Code | xcape tap     |
|------------------|-------|-----------------|------|---------------|
| L Cmd            | 29    | Super           | 125  | Albert        |
| L Option         | 56    | equals          | 13   |               |
| End              | 107   | Left Alt        | 56   | ghostty1      |
| R Cmd            | 97    | Super           | 125  | Albert        |
| R Ctrl           | 126   | minus           | 12   |               |
| PgUp             | 104   | backslash       | 43   |               |
| PgDn             | 109   | Right Alt       | 100  | ghostty2      |
| apostrophe       | 40    | Right Ctrl      | 97   | apostrophe    |
| backslash        | 43    | Tab             | 15   |               |
| minus            | 12    | Escape          | 1    |               |
| equals           | 13    | Escape          | 1    |               |
