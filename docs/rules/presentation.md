# Presentation, feel, the nature kit, exports and quitting
What presentation may and may not decide, the foliage and lake shaders, what the builds carry, and how a process quits. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## PRESENTATION AND FEEL (DECISIONS #115-#120)
- `interact_requested` fires when a verb STARTS. A genre that claims a press calls
  `InteractionComponent.announce_interact()` itself — only it knows what the press meant — and
  announces OTHER players' verbs when their public state first shows them (#131).
- A client may refuse its own action to avoid ANIMATING something it knows will fail. The server
  still decides. An unknown state (a row that has not arrived) is not a refusal.
- An action one-shot fades out once the body is moving (`action_cancel_speed`). An action that
  should survive movement wants the upper-body filter, not a wider cancel.
- A component stores row state in a VAR. `bind()` replays existing rows before `_on_bound()`, so
  a node built there must render what is already known rather than being the place it is kept.
  It replays EVERY row of each table (#180), so a collection arrives whole and before
  `is_bound()`: announce only what arrives after bind, and key collection rows by their id.
- Retuning `timing_half_width` regenerates `shared/golden/challenge/challenge_timing.json` with
  the NumPy generator; presses are multiples of the half-width so cases keep their intent.

## THE NATURE KIT (DECISIONS #137, #141, #146)
- Every leaf, petal and grass blade is `nature_foliage.gdshader`, swapped in at import by
  `quaternius_import.gd` (`FoliageMaterial`): it lights a back face by the kit's own normal. A
  plain double-sided StandardMaterial3D flips it, and up-facing grass turns black from behind.
- Editing the import script reimports NOTHING. `--only=kits` (test_runner) fails until the kit is
  reimported; `tests/render_test.sh` is what shows the shader actually lights both sides.
- The grass is coloured from a PALETTE of thin stripes (`Grass.png`); mipmaps average a stripe
  into its neighbours and the grass whitens with distance. The opaque variant reads it without
  mipmaps (`FOLIAGE_PALETTE`, #146). Never put a detailed texture on that variant.
- The LAKE's colour is how far DOWN the bed is, from the depth buffer (`lake_water.gdshader`,
  #150), never the length of the line of sight: from a player's camera that is long everywhere,
  and the lake went one flat blue. Tune the stops and colours on the material, not in code.

## EXPORTS (DECISIONS #134)
- The client preset excludes `sidecar/` and test CODE. `tests/levels/` is the game's level — it
  must stay in both builds (the first presets lost it).
- The server preset is dedicated-server mode; `run/main_scene.dedicated_server` boots the sidecar.
- Judge an exported process's log before asking it to exit: 4.7.1 prints engine "BUG:" reports
  on shutdown.

## QUITTING (DECISIONS #151)
- Every process quits through `AppExit.quit(get_tree(), code)`, never `get_tree().quit()` (linted).
  A stopped sound is released by the audio server's mixing thread a pass or two later, and a
  process that quit within milliseconds of the stop reported the pond ambience leaked about half
  the time. AppExit stops every sound and waits 0.1 s first. A window's close button goes the
  same way (`AppExit.hold_close_request` + NOTIFICATION_WM_CLOSE_REQUEST, in `boot.gd`).
