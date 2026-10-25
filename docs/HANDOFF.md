# Handoff — UMF Template, 2026-10-24

## Where it stands
**1.1.0 SHIPPED to all four games (2026-10-24, Luke's say)**: the low-end hardware work (DECISIONS #282,
CHANGELOG 1.1.0) and the accounts suite's pinned defaults (`511eee3`, from a Regent's Rule session: a game
overriding `characters_per_account` / `park_offline_s` failed 6 of its checks). No schema change: nothing
to publish. Each game's suites after the pull: its own HANDOFF.
Suites this session, all green: unit sweep (run_tests.sh, every lint) 2193/0, then `settings`,
`quality`, `remote_animation` 100/0 and, after the last change, `settings` + `quality` 94/0; e2e 11/0; export 34/0 (two new checks);
render_test.sh ok (the renderer steps, the self-restart, Low vs High on both renderers). Five
mutations of the new code each caught by `quality`. Not run: the other server suites (no server code
changed), any game's suites (not shipped).

## This session
- Why Intel Iris Plus crashed: the template runs Vulkan on Windows; Iris Plus (Gen 9.5/11) has
  Intel's frozen legacy drivers; Godot's `fallback_to_opengl3` only catches a renderer that fails to
  start. Notes in the shared folder of the session that asked (`low-end-hardware.md`).
- `foundation/core/renderer_choice.gd` + `project.godot` `config/project_settings_override=
  "user://renderer.cfg"`: Settings > Video > Renderer (Automatic, Full, Compatibility, Restart now);
  Automatic switches and restarts itself on `LEGACY_GPUS` or after a crashed start (exports only).
- `Settings`: Graphics quality Low/Medium/High/Custom (`QUALITY_PRESETS`), `shadow_quality` (with Off;
  the old `shadows` read across), `effects`, `detail`. High is the old look exactly.
- `foundation/core/graphics_quality.gd`: a level's effects and lights turned down from what it was
  made with (a copy's meta is not trusted); designer groups `detail_high`, `detail_medium`,
  `detail_density`.
- `foundation/anim/animation_rate.gd` + the driver: other characters posed less often far away / off
  screen on Low and Medium, drawn to 80/150 m. The driver always advances its tree itself now.
- `tools/perf/perf_bench.tscn` (the bench); tests: unit `quality`, `remote_animation` rates,
  `tests/render/renderer_steps.*` in `render_test.sh`, a renderer check in `export_test.sh`.
- HANDBOOK §3 "Running well on a weak computer", §6 Settings, §8 table, §10; rules
  `version_settings_looks.md`, `animation.md`; FOUNDATION_SYSTEMS "Low-end hardware".

## Next, in order
1. Luke: try it (Escape, Settings, Video: Graphics quality, Renderer). Shipped; restart each game's
   editor once (project.godot gained a line).
2. A friend's build on the Iris Plus laptop (`tools\release.cmd` per game): its first start should
   restart itself onto Compatibility and Low. Ask for its `godot.log` and its telemetry.
3. Each game's own levels through the bench (`-- --level=res://...`); Fishing's meadow grass into
   `detail_density`, clutter into `detail_high`.

## Waiting on Luke
- Decided 2026-10-24: Apple M1, Iris Xe and AMD integrated graphics start on High; only old Intel
  (`RendererChoice.LEGACY_GPUS`) starts on Low. Do not widen the list without asking.

## Watch out
- Changing an AnimationTree's `callback_mode_process` restarts what it plays: the driver sets manual
  once, before it plays. Do not set it anywhere else.
- `render_test.sh` and `export_test.sh` set the player's `renderer.cfg` aside and put it back; a run
  killed halfway can leave one behind in `%APPDATA%\Godot\app_userdata\<game>\`.
- This PC's Intel iGPU is disabled in Windows: no real iGPU numbers yet (WARP stood in).
- The Edit tool rewrote `tests/export_test.sh` with CRLF once: check line endings of a `.sh` after editing.
- Every Compatibility start prints "TAA is only available..." once (project.godot's TAA, read before
  Settings turns it off); harmless.
