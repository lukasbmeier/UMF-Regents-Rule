@tool
class_name ModularCharacter extends Node3D
## GENRE CONTENT. One character put together from Quaternius' modular packs: a head, the pieces
## of an outfit, a haircut — each its own glTF — worn on ONE skeleton.
##
## Every piece in those packs is skinned to the same 65-bone skeleton the animation libraries
## use (`game/anim/`), so assembling is only moving meshes: the head's scene brings the skeleton,
## and each other piece's meshes are lifted off their own copy of it and bound to the head's.
## Their skins bind bones BY NAME (glTF import's default), so the pieces do not even need to
## list bones in the same order. What results is an ordinary rigged model — the animation driver
## finds its `Skeleton3D` and plays the same clips it plays on the mannequin.
##
## It assembles when the scene is instantiated, before it is in any tree, so whoever instantiates
## a look (the spawner, the previews, a test) gets a finished character back from `instantiate()`.
## A TOOL script, so it assembles in the editor too: open a look and see it, and the rod grip
## preview has a body to hold the rod (DECISIONS #147). The assembled pieces are never owned by
## the look's scene, so saving a look in the editor saves only its fields.
##
## A look is a `.tscn` with this script at its root and the fields below filled in
## (`game/characters/looks/`, written by `tools/characters/make_looks.py`).
##
## COLOURS BELONG TO THE LOOK. The pieces share their imported materials, so a tint is applied to
## a copy — one copy per look, kept for the life of the game and shared by everyone wearing that
## look. Per-character copies would cost a material each for nothing, and they were freed along
## with their character in an order the headless renderer reports as an error.

## Brings the skeleton. One of the `Regular_*_OnlyHead` models: a full body under clothes clips
## through them and draws skin nobody sees (the outfit pack's readme).
@export var head: PackedScene
## Everything worn: outfit parts, hair, eyebrows, a hood or a crown.
@export var parts: Array[PackedScene] = []
## The skin's base colour texture; null keeps the head's own. The packs come in light and dark.
@export var skin_texture: Texture2D
## Multiplied over the skin texture.
@export var skin_tint: Color = Color.WHITE
## The hair and eyebrow textures are grey; this is their colour.
@export var hair_color: Color = Color(0.24, 0.16, 0.08)
## An outfit colourway (`T_<Outfit>_2_BaseColor` …); null keeps the outfit's first.
@export var outfit_texture: Texture2D
## Which BODY this is (`female`, `male`), as the head decides. Put on the skeleton as
## `HeldItem.BODY_META`, so an item can be held one way in her hand and another in his
## (DECISIONS #155).
@export var body: StringName = &""

## A PLAYER'S PIECES (DECISIONS #178): what is worn instead of `parts` once a choice swapped one
## (`CharacterLooks.apply`); empty wears `parts`. Never saved: a look's file keeps its own.
var worn: Array[PackedScene] = []
## A colourway per worn piece, by the piece's path, over its outfit's own (`CharacterLooks.apply`).
var dyes: Dictionary[String, Texture2D] = {}

const SKIN_PREFIX: String = "MI_Regular_"
const HAIR_PREFIX: String = "MI_Hair"
## The materials an outfit's colourway replaces: the outfit packs' own. A colourway texture
## (`T_<Outfit>_2_BaseColor`) only ever dresses its own outfit's material (`MI_<Outfit>`): a
## Noble torso on a Peasant look keeps the Noble colours.
const OUTFIT_MATERIALS: Array[String] = ["MI_Peasant", "MI_Ranger", "MI_Noble", "MI_Wizard", "MI_Knight"]
## The meta on each worn mesh naming the piece it came from (its scene's path).
const PIECE_META: StringName = &"piece"
## Head meshes a worn piece can stand in for. The heads come with a pair of eyebrows; a piece
## whose mesh is named `Eyebrows_Thick` wears INSTEAD of them rather than on top of them.
const REPLACEABLE: Array[String] = ["Eyebrows"]

## Dressed materials, by source material and look: see the header.
static var _dressed_cache: Dictionary[String, Material] = {}

var _assembled: bool = false
var _skeleton: Skeleton3D = null
## The pieces the character is assembled from now.
var _assembled_with: Array[PackedScene] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		assemble()


## Built with `new()` rather than from a scene: assemble on entering the tree instead.
func _ready() -> void:
	assemble()


## The skeleton everything is worn on (null until assembled, or with no head).
func skeleton() -> Skeleton3D:
	return _skeleton


## A PLAYER'S CHOICES on top of this look (DECISIONS #166): the `appearance` text the entity was
## spawned with, "ranger_f;torso=3;skin=4" (`CharacterLooks`). Called by the entity before the
## model enters the tree, and by the character picker for its preview. Swapped pieces put the
## character together again (a new skeleton: call it before anything holds this one); colours
## dress it again.
func apply_appearance(appearance: String) -> void:
	CharacterLooks.apply(self, appearance)
	if not _assembled:
		return
	if wearing() != _assembled_with:
		_reassemble()
	elif _skeleton != null:
		_dress()


## The pieces worn: the player's (`worn`) or the look's own (`parts`).
func wearing() -> Array[PackedScene]:
	return worn if not worn.is_empty() else parts


## What the character picker offers on top of choosing this look (`CharacterLooks.options`).
func appearance_options() -> Array[Dictionary]:
	return CharacterLooks.options(self)


## Put the character together. Idempotent: the second call does nothing.
func assemble() -> void:
	if _assembled or head == null:
		return
	_assembled = true
	var base: Node = head.instantiate()
	base.name = "Body"
	add_child(base)
	_skeleton = _find_skeleton(base)
	if _skeleton == null:
		push_error("ModularCharacter: %s has no Skeleton3D to wear anything on" % head.resource_path)
		return
	if not body.is_empty():
		_skeleton.set_meta(HeldItem.BODY_META, body)
	var head_meshes: Array[MeshInstance3D] = _meshes(_skeleton)
	_assembled_with = wearing().duplicate()
	for part: PackedScene in _assembled_with:
		if part == null:
			continue
		var piece: Node = part.instantiate()
		for mi: MeshInstance3D in _meshes(piece):
			_replace_head_mesh(head_meshes, String(mi.name))
			mi.get_parent().remove_child(mi)
			mi.owner = null   # it belonged to the piece's scene, which is about to go
			mi.set_meta(PIECE_META, part.resource_path)
			_skeleton.add_child(mi, true)
			mi.skeleton = NodePath("..")
		piece.free()
	_dress()


## Put it together again from `wearing()`: the head's scene and every piece, freshly.
func _reassemble() -> void:
	var old: Node = get_node_or_null(^"Body")
	if old != null:
		remove_child(old)
		# Undressed first: the headless renderer objects to freeing a mesh with an override
		# material that was never in a tree.
		for mi: MeshInstance3D in _meshes(old):
			for i: int in range(mi.get_surface_override_material_count()):
				mi.set_surface_override_material(i, null)
		old.free()
	_assembled = false
	_skeleton = null
	assemble()


## A worn `Eyebrows_Thick` takes the head's own `Eyebrows` off (REPLACEABLE).
func _replace_head_mesh(head_meshes: Array[MeshInstance3D], worn: String) -> void:
	for kind: String in REPLACEABLE:
		if not worn.begins_with(kind):
			continue
		for hm: MeshInstance3D in head_meshes:
			if is_instance_valid(hm) and String(hm.name) == kind:
				hm.get_parent().remove_child(hm)
				hm.free()


func _dress() -> void:
	for mi: MeshInstance3D in _meshes(_skeleton):
		if mi.mesh == null:
			continue
		var dye: Texture2D = dyes.get(String(mi.get_meta(PIECE_META, "")), null)
		for i: int in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var dressed: Material = _dressed(src, dye)
			mi.set_surface_override_material(i, dressed if dressed != src else null)


## `src` as this look wears it: a cached copy with the look's colours, or `src` itself when the
## look changes nothing about it. `dye` is the colourway chosen for this mesh's piece.
func _dressed(src: StandardMaterial3D, dye: Texture2D = null) -> Material:
	var n: String = src.resource_name
	var what: String = ""
	var outfit: Texture2D = null
	if OUTFIT_MATERIALS.has(n):
		if dye != null and _colourway_fits(n, dye):
			outfit = dye
		elif outfit_texture != null and _colourway_fits(n, outfit_texture):
			outfit = outfit_texture
	if n.begins_with(SKIN_PREFIX):
		what = "skin|%s|%s" % [skin_texture.resource_path if skin_texture != null else "", skin_tint.to_html()]
	elif n.begins_with(HAIR_PREFIX):
		what = "hair|%s" % hair_color.to_html()
	elif outfit != null:
		what = "outfit|%s" % outfit.resource_path
	if what.is_empty():
		return src
	var key: String = "%s|%s|%s" % [src.resource_path, n, what] if not src.resource_path.is_empty() \
		else "%d|%s" % [src.get_instance_id(), what]
	if _dressed_cache.has(key):
		return _dressed_cache[key]
	var mat: StandardMaterial3D = src.duplicate() as StandardMaterial3D
	if n.begins_with(SKIN_PREFIX):
		if skin_texture != null:
			mat.albedo_texture = skin_texture
		mat.albedo_color = skin_tint
	elif n.begins_with(HAIR_PREFIX):
		mat.albedo_color = hair_color
	else:
		mat.albedo_texture = outfit
	_dressed_cache[key] = mat
	return mat


## Whether a colourway texture (`T_Noble_2_BaseColor`) is for an outfit material (`MI_Noble`).
static func _colourway_fits(material: String, texture: Texture2D) -> bool:
	return texture.resource_path.get_file().begins_with("T_%s_" % material.trim_prefix("MI_"))


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c: Node in n.get_children():
		var s: Skeleton3D = _find_skeleton(c)
		if s != null:
			return s
	return null


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out
