# Animation & Visual Feedback — modular, data-driven, network-safe

Animation is presentation. It reads state; it never produces gameplay. This document defines a contract that any character (humanoid, animal, bird, vehicle) satisfies, a resource that maps clips onto that contract, a builder that generates the `AnimationTree` from the resource, and a feedback layer for visual clarity. Nothing here touches the module.

## STATUS — implemented 2026-09-24 (Task 15), with three deliberate deviations

Built and tested: the contract (§2), `AnimationSet` + `AnimationClipRef` (§3), the generated
tree (§4) and the driver (§5). `foundation/anim/`, content in `game/anim/`, decisions #94-#98.

Deviations, each recorded in `docs/DECISIONS.md`:
- The driver is a component under `Components/`, fed by `EntityDefinition.animation_set`, not a
  node under `Visual/` (#96). It builds the `AnimationTree` itself and holds the libraries
  directly — Godot 4.2+ made `AnimationTree` an `AnimationMixer`, so there is no `AnimationPlayer`
  to find or assign.
- No retargeting: both Quaternius libraries and every Base Character share one 65-bone skeleton,
  so clips play directly. `SkeletonProfileHumanoid` retargeting (§1) is still the answer for a rig
  from elsewhere.
- Clip lengths are fitted to the game's own jump timing through `AnimationClipRef.speed_scale`
  (#97), which §3 lists but §4 does not say how to apply: it is a custom timeline on the state's
  `AnimationNodeAnimation`, because a state machine has nowhere to put a `TimeScale` node.

Built since: an UPPER-BODY one-shot (`upper`, DECISIONS #158) for drawing and putting away a held
item while the legs walk, filtered to `upper_body_filter` or the humanoid's chest, arms and fingers.
An action or hit that covers the whole body ends it (#160): left under one, it froze and played on
after it.
Not built yet: `locomotion_blend_2d` (strafe blending, §4), the hit reaction on the upper body (§5),
and `FeedbackComponent` (§7). The set carries the fields; nothing reads
them, and no test covers them. §5's "skip the tree on a dedicated server" guard is also absent on
purpose — there is no sidecar yet (Task 13), and a branch no test can reach is how speculative
code rots. Whoever builds the sidecar adds it there.

## 1. Asset pipeline (Quaternius / any GLTF)
- Characters: GLTF/GLB, in-place animations only (no root motion — motion comes from `MovementModel`).
- Humanoids: at import, assign `SkeletonProfileHumanoid` bone map (Godot 4 retargeting). All humanoids then share **one** `AnimationLibrary` (`res://game/anim/humanoid.res`, e.g. Quaternius Universal Animation Library). Never store animations per character model.
- Non-humanoids (chicken, wolf, eagle): their own `AnimationLibrary` per skeleton family, same semantic names.
- Naming inside libraries is free-form; the `AnimationSet` resource resolves semantic names → clips.

## 2. The animation contract
`AnimationDriverComponent` (client-only, child of `Visual/`) is the only writer of AnimationTree parameters.

**Continuous (written every frame from `Movement.get_render_state()`):**
| Parameter | Source |
|---|---|
| `speed_normalized: float` | `vel.length() / max(walk_speed, sprint_speed)` on the XZ plane |
| `strafe: float` (−1..1) | lateral component of velocity in look space |
| `vertical_velocity: float` | `vel.y` |
| `is_grounded: bool` | `grounded` |
| `move_state: int` | `MovementState.move_state` (IDLE, WALK, SPRINT, AIR, DASH, SWIM, MOUNT, FLY…) |
| `look_pitch: float` | from `InputFrame`/row for aim layering |

**One-shots (requested from entity-local signals):**
| Request | Signal |
|---|---|
| `jump` | `Movement.jumped` |
| `land` (`impact_speed` → light/heavy variant) | `Movement.landed` |
| `hit` | `Health.damaged` |
| `death` / `revive` | `Health.died` / `Health.revived` |
| `ability_<id>` | `Action.action_started(ability_id)` (predicted); `Action.event_revoked` cancels |
| `interact` | `Interaction.interact_requested` |
| `emote_<id>` | genre layer |

Rule: gameplay hit frames come from `action_event` rows, **never** from animation method tracks.

## 3. `AnimationSet` resource
```gdscript
class_name AnimationSet extends Resource
@export var library: AnimationLibrary
@export var skeleton_family: StringName          # &"humanoid", &"quadruped", &"bird"
@export var clips: Dictionary[StringName, AnimationClipRef]   # semantic → clip
@export var locomotion_blend_2d: bool = false    # strafing games
@export var upper_body_filter: Array[StringName] # bone names for reaction layering
# AnimationClipRef: { anim_name: StringName, loop: bool, blend_time: float, speed_scale: float }
```
Semantic names (foundation minimum): `locomotion.idle`, `locomotion.walk`, `locomotion.run`, `jump.start`, `jump.loop`, `jump.land`, `jump.land_heavy`, `react.hit`, `react.death`, `react.revive`, `interact`. Genre layers add `ability.*`, `emote.*`, `swim.*`, `fly.*`, `mount.*`.

`tools/animation_set_builder.gd` (EditorScript): given a library, fuzzy-matches clip names (`Idle`→`locomotion.idle`, `Walk`, `Run`/`Sprint`, `Jump`→`jump.start`, `Jump_Idle`→`jump.loop`, `Jump_Land`→`jump.land`, `HitReact`, `Death`) and writes an `AnimationSet.tres` for review. Unmatched semantics are listed; missing ones fall back to the nearest (`jump.loop` → `jump.start` last frame, `react.revive` → reverse of death or idle).

## 4. Generated `AnimationTree` — `AnimationTreeBuilder`
`AnimationTreeBuilder.build(set: AnimationSet) -> AnimationTree`, called by `AnimationDriverComponent._on_bound()`. Nobody hand-edits the graph.

```
Root: AnimationNodeBlendTree
 ├─ StateMachine "body"
 │   ├─ Grounded: BlendSpace1D(speed_normalized) [idle, walk, run]   (BlendSpace2D(strafe, speed) if locomotion_blend_2d)
 │   ├─ Air:      StateMachine [jump.start → jump.loop]  (enter on !is_grounded)
 │   ├─ Land:     jump.land / jump.land_heavy → Grounded
 │   ├─ Dead:     react.death (hold last frame) → Revive → Grounded
 │   └─ per move_state branches when the set has them (Swim, Fly, Mount, Dash)
 ├─ Blend2 "pose"      a clip HELD over the body, blended in by weight (DECISIONS #144):
 │   └─ pose_clip → TimeScale → TimeSeek   looping, or frozen at a point a value drives
 ├─ OneShot "upper"     filter = upper_body_filter (or the chest, arms, fingers): item.draw /
 │                      item.stow while the legs keep walking (DECISIONS #158)
 ├─ OneShot "hit"       filter = upper_body_filter, mix over "body"
 ├─ OneShot "ability"   filter configurable per ability (upper body for casts, full body for melee)
 ├─ OneShot "interact"  upper body
 └─ Output
```
Transitions use `blend_time` from the set; `advance_mode` auto with conditions bound to the contract parameters. `travel()` is only used for `Dead`/`Revive`.

**The held pose** is the driver's `hold_pose(semantic, weight, at)`: `at` < 0 loops the set's clip, `at` in 0..1 freezes it at that fraction of its length (scale 0 and a seek each frame) — how far a rod is heaved, a bow drawn. It eases in and out and lets go while the body moves, like an action. A genre's presentation calls it every frame from state it reads; `release_pose()` lets go; `play_action(semantic)` fires a genre's own one-shot. While a one-shot fully covers the body, Godot does not process the state machine underneath, so a travel asked for then lands when the one-shot ends.

## 5. `AnimationDriverComponent`
- `_on_bound`: finds `AnimationPlayer` under `Visual/Model`, builds the tree, assigns `anim_player`, sets `active = true`.
- `_process`: reads `Movement.get_render_state()` (works for LOCAL_PREDICTED, REMOTE_INTERPOLATED, SERVER_DRIVEN identically) and writes parameters. Never reads rows or the SDK.
- Connects entity-local signals to one-shot requests. `event_revoked` aborts the matching one-shot.
- A genre's presentation layers on top through `hold_pose` / `release_pose` / `play_action` (§4) —
  it asks for a semantic from the set, never a clip, and never writes a tree parameter itself.
- Sidecar builds: component is present but `AnimationTree` is never built (`OS.has_feature("dedicated_server")` → `set_process(false)`). NPCs animate on clients from state exactly like players.

## 6. Reference character & tests
- `game/characters/reference_humanoid.tscn`: a Quaternius humanoid with the shared library and generated set. Every contract change is verified against it.
- Headless test `test_animation_driver`: build tree from the reference set; drive parameters (grounded→air→land, speed ramp, hit during run, death→revive); assert `AnimationTree` state-machine current node and that one-shots become active/inactive. No rendering needed.

## 7. Visual clarity — `FeedbackComponent` + `FeedbackSet`
Same pattern: a resource maps SignalBus events to responses; the component has no game knowledge.
| Event | Default response (overridable per game) |
|---|---|
| `interact_target_changed` | outline shader on/off (`Visual` material overlay) + prompt UI |
| `entity_health_changed` (delta < 0, local) | hit flash (material param), damage number (world-space Label3D pool), light camera shake |
| `entity_died` | desaturation tint (local), ragdoll/fade (remote) per `HealthConfig.death_behavior` |
| `entity_action(actor, ability, target, outcome)` | VFX scene from `ability_def.data.vfx`, SFX, hit-stop frames on outcome HIT |
| `telegraph` rows (`global_row_event`) | decal/mesh on ground for the shape; colorblind-safe palette (blue/orange, never red/green only) |
| `entity_teleported` | dissolve/puff to mask the snap |
| `session_phase_changed` | phase banner + countdown |
| `action_rejected` | shake on the relevant UI element + toast |

Rules: responses are scenes/resources under `game/feedback/`; the component pools and despawns them; timing constants live in `FeedbackSet`, not code.

## 8. Ownership
| Foundation | Game layer |
|---|---|
| `AnimationDriverComponent`, `AnimationSet`, `AnimationTreeBuilder`, `animation_set_builder.gd`, `FeedbackComponent`, `FeedbackSet`, reference humanoid + test | libraries, per-character `AnimationSet.tres`, ability/emote clips, VFX/SFX scenes, palettes |
