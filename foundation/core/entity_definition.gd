class_name EntityDefinition extends Resource
## Design-time description of one kind of entity. The spawner maps `entity.kind` from the server
## to one of these and instantiates `scene`.
##
## This is the seam that keeps the foundation genre-agnostic: the foundation knows "kind 0 exists
## and maps to some scene", never what a kind means. A genre ships its own `.tres` definitions.

## Matches the server's `entity.kind` column. Foundation kinds: 0 player, 1 npc.
## A genre numbers its own kinds from 100 (same convention as `move_state` and `challenge.kind`).
@export var kind: int = 0

## Instantiated once per entity row. Its root must be a `SpaceTimeEntity`.
@export var scene: PackedScene

## For nameplates and debug output. Not an identifier.
@export var display_name: String = ""

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
## Which clips this character has, mapped onto semantic names (ANIMATION_SPEC §3). Handed to
## the entity's AnimationDriverComponent before bind. Null means the character does not animate,
## which is the right answer for a greybox capsule.
@export var animation_set: AnimationSet
## SWAP FIRST/THIRD PERSON HERE. Applied to the entity's CameraRig; null keeps the scene's own.
## `foundation/camera/` ships `first_person.tres` and `third_person.tres`.
@export var camera_rig: CameraRigConfig


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
