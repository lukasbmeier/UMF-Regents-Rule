# Handoff — UMF Template, 2026-11-16 (1.8.4: a free colour in the character picker; branch claude/t2-picker-color)

## Where it stands
- 1.8.3 SHIPPED (template main 4437fa4, pushed, all four games pulled): `ModularCharacter.wear` + `assembled` (#313),
  a sweep that hits all (#314, S1), NPCs bind without a session row (#315).
- 1.8.4 (DECISIONS #316) committed on branch `claude/t2-picker-color` (child T2 of Regent's Rule's armor run), cut
  from main 4437fa4; not merged, not pushed, not shipped: the run's master merges and ships. Client only.
- Green: `looks` 68/0 (the new "a free colour" section; 5 mutations each failed it: the stale check dropping colours,
  keeping one out of range, no +1, clamping, no colour row); the full `tests/run_tests.sh` 2530/0 (with `COLOR_OPTIONS`, its check mutation-checked).
  A windowed shot of the picker with a colour row was taken and looked at (the armor run's notes folder,
  `t2_picker_colour_row.png`).

## This session
- `foundation/core/appearance.gd`: `COLOR_MAX`, `color_value`, `is_color`, `color_of` (0xRRGGBB + 1; out of range refused).
- `foundation/ui/character_picker.gd`: an option with `"color": true` is `_color_row` (ColorPickerButton, swatches,
  "Look's own"), `pick_color`, the stale check keeps colours, a dragged colour rebuilds the preview once a frame.
- `tests/fixtures/genre_look/` (a genre's look extending `ModularCharacter` with a colour option),
  `tests/suites/looks.gd` `_run_color_tests`. HANDBOOK (a free colour), CHANGELOG 1.8.4, DECISIONS #316.

## Next, in order
1. The armor run's master merges `claude/t2-picker-color` and ships 1.8.4 (`ship_template.sh`).
2. Regent's Rule's W1 declares its per-slot colour options in its own look scene.

## Waiting on Luke
- From before: strips per expanse; the SDK fix upstream; bandwidth budget; greybox humanoid roll default.

## Watch out
- A `-s` SceneTree script compiles before the autoloads exist: anything naming `Settings` (the picker via
  `SettingsPanel`) must be loaded by path at run time in such a script.
- The picker's colour preview reassembles the model once a frame while a colour is dragged: fine for one preview,
  not something to copy into a list of many.
- From 1.8.3: a respawn (appearance row change) shows the appearance's pieces until a genre's component wears its own.
