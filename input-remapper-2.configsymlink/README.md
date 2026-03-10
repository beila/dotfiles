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

              ┌─────┬─────┐              ┌─────┬─────┐
              │LCmd │LAlt │              │RAlt │RCmd │
              │(29) │(56) │              │(100)│(97) │
        ┌─────┼─────┼─────┤        ┌─────┼─────┼─────┤
        │BkSp │ Del │Home │        │Enter│RCtrl│PgUp │
        │     │     │     │        │     │(126)│(104)│
        │     ├─────┼─────┤        │     ├─────┼─────┤
        │     │     │ End │        │     │Space│PgDn │
        └─────┘     │(107)│        └─────┘     │(109)│
                    └─────┘                    └─────┘
```

### Remappings (input-remapper)

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

              ┌─────┬─────┐              ┌─────┬─────┐
              │Super│  =  │              │     │Super│
              │(29→ │(56→ │              │     │(97→ │
              │125) │ 13) │              │     │125) │
        ┌─────┼─────┼─────┤        ┌─────┼─────┼─────┤
        │     │     │     │        │     │  -  │  \  │
        │     │     │     │        │     │(126→│(104→│
        │     ├─────┼─────┤        │     │ 12) │ 43) │
        │     │     │LAlt │        │     ├─────┼─────┤
        └─────┘     │(107→│        └─────┘     │RAlt │
                    │ 56) │                    │(109→│
                    └─────┘                    │100) │
                                               └─────┘
```

### xcape (tap behavior for modifiers)
- Super tap → Albert (XF86Launch1)
- Alt_L tap → ghostty scratchpad 1 (XF86Launch2)
- Alt_R tap → ghostty scratchpad 2 (XF86Launch3)
- Ctrl_R tap → apostrophe

### Summary table

| Physical key     | Evdev | Remapped to     | Code | xcape tap     |
|------------------|-------|-----------------|------|---------------|
| LCmd             | 29    | Super           | 125  | Albert        |
| LAlt             | 56    | equals          | 13   |               |
| End              | 107   | Left Alt        | 56   | ghostty1      |
| RCmd             | 97    | Super           | 125  | Albert        |
| PgDn             | 109   | Right Alt       | 100  | ghostty2      |
| RCtrl            | 126   | minus           | 12   |               |
| PgUp             | 104   | backslash       | 43   |               |
| apostrophe       | 40    | Right Ctrl      | 97   | apostrophe    |
| backslash        | 43    | Tab             | 15   |               |
| minus            | 12    | Escape          | 1    |               |
| equals           | 13    | Escape          | 1    |               |
