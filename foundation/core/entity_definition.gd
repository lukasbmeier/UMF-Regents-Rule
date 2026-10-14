@tool
class_name EntityDefinition extends ContentDef
## Design-time description of one kind of entity. The spawner maps `entity.kind` from the server
## to one of these and instantiates `scene`.
##
## CONTENT (type `character`, DECISIONS #204): made and fitted in the character workbench (drop a
## rigged model in, fit it, play every clip), listed in the Content dock and the Catalog, kept
## under `foundation/content/character/` or `game/<genre>/content/character/`. Its content `id`
## is not its `kind`: two definitions may share a kind on purpose (the bare foundation's capsule
## player and the humanoid player are both kind 0; a scene's Boot picks which it uses, and a
## genre's definition for a kind replaces the foundation's).
##
## This is the seam that keeps the foundation genre-agnostic: the foundation knows "kind 0 exists
## and maps to some scene", never what a kind means. A genre ships its own `.tres` definitions.

## Matches the server's `entity.kind` column. Foundation kinds: 0 player, 1 npc.
## A genre numbers its own kinds from 100 (same convention as `move_state` and `challenge.kind`).
@export var kind: int = 0

## Instantiated once per entity row. Its root must be a `SpaceTimeEntity`.
@export var scene: PackedScene


## WHO DRIVES THIS ENTITY. Empty means a player does, through their input queue. A name here
## means an authority does: the sidecar looks up a brain by this name and attaches it
## (`docs/SIDECAR_SPEC.md` §3). It is a plain name rather than a script path because nothing in
## `foundation/` or `game/` may reference `res://sidecar` (hard rule 7b) — the brains live there
## and only the authority process ever resolves the name.
##
## A client build reads this field and does nothing with it: an NPC is an ordinary remote entity
## to everyone who is not simulating it.
@export var brain: StringName = &""

@export_group("Presentation")
## SWAP THE MODEL HERE. Instantiated under the entity's `Visual` node at bind time, replacing
## the greybox placeholder. Anything works — a MeshInstance3D, or a rigged character with its
## own AnimationTree. The foundation never looks inside it (hard rule 11: visuals read state,
## they never produce events), so a model change cannot affect gameplay.
@export var visual_scene: PackedScene
## SEVERAL LOOKS FOR ONE KIND. When this has entries, each entity wears one of them instead of
## `visual_scene`: the one a player CHOSE (the `appearance` row names it by its file name, the
## character picker writes it, DECISIONS #166), else one picked by its entity id (`visual_for`),
## so every client dresses the same player the same way. Presentation only, like the rest of this
## group. The picker offers them in this order.
@export var visual_variants: Array[PackedScene] = []
## Vertical offset for the model inside `Visual`, for when a model's origin is not at its feet.
@export var visual_offset: Vector3 = Vector3.ZERO
## Yaw applied to the model, in degrees. A rig authored facing +Z needs 180 here: Godot (and
## this project's movement, camera and `move_dir`) treat -Z as forward, and a model that
## disagrees moonwalks. Measured, not guessed — a root-motion clip's travel says which way a
## rig faces (the Quaternius humanoids move +Z, hence 180 on their definitions).
@export var visual_yaw_deg: float = 0.0
## The model's size (1: as it was made). A model made at another scale (a chicken modelled 3 m tall)
## is fitted here, not in the model file. Presentation only: its body is `collision_*` below.
@export_range(0.01, 100.0, 0.01, "or_greater") var visual_scale: float = 1.0
## Which clips this character has, mapped onto semantic names (ANIMATION_SPEC §3). Handed to
## the entity's AnimationDriverComponent before bind. Null means the character does not animate,
## which is the right answer for a greybox capsule.
@export var animation_set: AnimationSet
## SWAP FIRST/THIRD PERSON HERE. Applied to the entity's CameraRig; null keeps the scene's own.
## `foundation/camera/` ships `first_person.tres` and `third_person.tres`.
@export var camera_rig: CameraRigConfig

@export_group("Body")
## ITS BODY: the capsule it moves and collides with, and that others bump into (DECISIONS #207). 0:
## the entity scene's (foundation/entities/player.tscn: 0.35 m by 1.8 m, a person). A hen is a
## smaller capsule. The character workbench draws it around the model.
@export_range(0.0, 5.0, 0.01, "suffix:m") var collision_radius: float = 0.0
@export_range(0.0, 10.0, 0.01, "suffix:m") var collision_height: float = 0.0
## WHERE IT CARRIES SOMETHING (DECISIONS #228): the point, from its feet, in its own terms (x right,
## y up, -z ahead), that something it carries is drawn at (a hen in the wolf's mouth), and that
## thing's turn from its own heading. Only the drawing: the server keeps the carried thing at the
## carrier's place.
@export var carry_offset: Vector3 = Vector3(0.0, 0.8, -0.6)
@export_range(-180.0, 180.0, 1.0, "suffix:°") var carry_yaw_deg: float = 0.0
## A WALL IT PUTS UP (DECISIONS #229): a box (size, and its centre from its feet in its own terms:
## x right, y up, -z ahead) that stops bodies, and a referee's sweeps and sight, while it is in one of
## `blocks_in` (a gate while shut; empty: always). Zero size: none. Others are kept out of it by the
## level's layer, as by a fence (`EntityBlocker`).
## FRIENDLY COLLISION (DECISIONS #238): a physics layer (5-32) this character's bodies share with
## their own kind, solid to each other when the rule `foundation.friendly_collision` is on (a lobby's
## griefing toggle: hens blocking a gap for each other). 0: never (they pass through each other, as
## every body does by default).
@export_range(0, 32) var kin_layer: int = 0
@export var blocker_size: Vector3 = Vector3.ZERO
@export var blocker_offset: Vector3 = Vector3.ZERO
@export var blocks_in: Array[StatusDef] = []

@export_group("How it plays")
## A PLAYER MAY CHOOSE TO PLAY IT (DECISIONS #217): it is offered in the lobby (Play as), and the
## server lets a player become it (`choose_character`). Off: only the game puts an entity in it (an NPC,
## a nest, the character a new player starts as).
@export var playable: bool = false
## HOW IT MOVES (DECISIONS #205): its speeds, jump, flaps, dash. Empty: the foundation's default
## (`shared/movement_config.json`). Predicted by its player's client and simulated by the sidecar
## with the same numbers.
@export var movement_profile: MovementProfileDef
## WHAT IT CAN USE (DECISIONS #207): its abilities. The server refuses an ability its kind's
## characters do not list; a kind none of whose characters list any may use every ability (as
## before this existed).
@export var abilities: Array[AbilityDef] = []


## The model entity `entity_id` wears: the variant its `appearance` names (DECISIONS #166), else
## one of `visual_variants` by its id — consecutive ids get different ones — else `visual_scene`.
## What else the appearance says (colours) is the model's to apply: a model with an
## `apply_appearance(text)` method is handed the whole text.
func visual_for(entity_id: int, appearance: String = "") -> PackedScene:
	var chosen: PackedScene = variant_named(look_name(appearance))
	if chosen != null:
		return chosen
	if not visual_variants.is_empty():
		return visual_variants[posmod(entity_id, visual_variants.size())]
	return visual_scene


## The variant an appearance names: the text before its first `;` ("ranger_f;skin=2" -> ranger_f).
static func look_name(appearance: String) -> String:
	return Appearance.look_name(appearance)


## The look an entity wears, by name: the one its appearance names, else the one its id picks. ""
## for a definition with no variants. A picker opens on it.
func look_worn(entity_id: int, appearance: String = "") -> String:
	var named: String = look_name(appearance)
	if variant_named(named) != null:
		return named
	var scene: PackedScene = visual_for(entity_id)
	return scene.resource_path.get_file().get_basename() if scene != null and not visual_variants.is_empty() else ""


## A variant by its file name without the extension (`ranger_f` for `.../ranger_f.tscn`), or null.
func variant_named(variant_name: String) -> PackedScene:
	if variant_name.is_empty():
		return null
	for v: PackedScene in visual_variants:
		if v != null and v.resource_path.get_file().get_basename() == variant_name:
			return v
	return null


## Every variant's name, in order: what the character picker offers.
func variant_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for v: PackedScene in visual_variants:
		if v != null:
			out.append(v.resource_path.get_file().get_basename())
	return out


## The movement config this character's entities move by: the game's, with its profile's numbers.
func movement_config() -> MovementConfig:
	if movement_profile == null:
		return MovementConfig.shared()
	return movement_profile.apply_to(MovementConfig.shared())


func content_type() -> StringName:
	return &"character"


## What a server could check a game's kinds against (it compiles nothing from it yet).
func to_bake() -> Dictionary:
	var ability_ids: Array = []
	for a: AbilityDef in abilities:
		ability_ids.append(ContentDef.ref(a))
	return {"id": id, "kind": kind, "name": display_name, "brain": String(brain), "movement": ContentDef.ref(movement_profile),
		"abilities": ability_ids, "playable": playable}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if kind < 0:
		out.append("its kind (%d) is negative" % kind)
	if scene == null:
		out.append("it has no scene: the entity it spawns (instance foundation/entities/player.tscn)")
	if animation_set != null and visual_scene == null and visual_variants.is_empty():
		out.append("it has an animation set but no model to play it on")
	if collision_radius > 0.0 and collision_height > 0.0 and collision_height < collision_radius * 2.0:
		out.append("its body is %.2f m tall but %.2f m wide: a capsule is at least as tall as it is wide (collision_height)" % [collision_height, collision_radius * 2.0])
	if playable and not brain.is_empty():
		out.append("it is playable and has a brain (%s): a player plays it, so it needs none" % brain)
	if has_blocker() and (blocker_size.x <= 0.0 or blocker_size.y <= 0.0 or blocker_size.z <= 0.0):
		out.append("its blocker is %s: give it a size in all three, or none (zero)" % blocker_size)
	if blocks_in.has(null):
		out.append("its blocks_in list has an empty slot: pick a status or remove the slot")
	if abilities.has(null):
		out.append("its abilities list has an empty slot: pick an ability or remove the slot")
	return out


## Whether it puts up a wall (`blocker_size`).
func has_blocker() -> bool:
	return blocker_size != Vector3.ZERO


## Whether its wall is up in status `status` (always, when `blocks_in` is empty).
func blocks_when(status: int) -> bool:
	if not has_blocker():
		return false
	if blocks_in.is_empty():
		return true
	for st: StatusDef in blocks_in:
		if st != null and st.status == status:
			return true
	return false


## The capsule its body is: the entity scene's, resized by `collision_radius`/`collision_height`.
## Null when its scene has no capsule.
func body_capsule() -> CapsuleShape3D:
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var out: CapsuleShape3D = null
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		if (n as CollisionShape3D).shape is CapsuleShape3D:
			out = ((n as CollisionShape3D).shape as CapsuleShape3D).duplicate() as CapsuleShape3D
			break
	root.free()
	if out != null:
		if collision_radius > 0.0:
			out.radius = collision_radius
		if collision_height > 0.0:
			out.height = maxf(collision_height, out.radius * 2.0)
	return out
