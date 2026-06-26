# input-remapper presets

Managed by input-remapper-daemon (apt). Autoloads on device connect.

If a mapping stops applying mid-session (e.g. the Logitech left-handed swap reverts to right-handed), run `reloadmouse` (in `bin/`) to re-trigger autoload. Do **not** call `input-remapper-control --command autoload` directly from a Nix-wrapped shell — it crashes on the leaked Nix glib; see `keyd/AGENTS.md` "input-remapper stale device list" for the full rationale.

## Logitech USB Optical Mouse — left-handed.json
Swap left/right buttons (BTN_LEFT ↔ BTN_RIGHT).

## ExpertBT5.0 Mouse (Kensington Expert Trackball BT) — remap.json
Left-hand button remap:
- BTN_LEFT(272) → Super+Tab — switch windows
- BTN_MIDDLE(274) → BTN_RIGHT(273)
- BTN_RIGHT(273) → BTN_LEFT(272)
- BTN_SIDE(275) → Super+Shift+C — close window

## Keyboard remapping

See `~/.dotfiles/keyd/README.md` for keyd configuration (all keyboards).
