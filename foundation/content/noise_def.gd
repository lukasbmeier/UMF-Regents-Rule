@tool
class_name NoiseDef extends ContentDef
## A NOISE (DECISIONS #233): what one kind of the world's `noise` rows sounds like, how far it carries,
## and who is shown where it was. The server says only that one happened (an egg cracked, a player
## pinged); everything it MEANS to the people who hear it is here, so a designer adds one, or gives a
## character its own sound for the same kind, without code.
##
## Its KIND is the number the server writes: the foundation's ping is 1; a genre's are 100 and up
## (`make_noise` in its rules). Several pieces may share a kind for different makers (`made_by`): a
## hen's ping is a bawk, the wolf's a growl. A genre's replaces the foundation's for the same kind and
## maker, as a status does.
##
## Presentation only: never baked into the server (the bake writes it for the record).

## The `noise` row's kind it is (1: a ping; 100 and up: a genre's).
@export_range(1, 65535) var kind: int = 1
## Whose noise this is (a hen's ping, the wolf's): the characters that make it. Empty: anyone's.
@export var made_by: Array[EntityDefinition] = []
## What it sounds like, where it was made.
@export var sound: AudioStream
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db: float = 0.0
## How far it carries (0: everywhere in its world, a loud crack heard farm-wide).
@export_range(0.0, 500.0, 1.0, "suffix:m") var heard_within_m: float = 0.0
## Whether those of another character than its maker's hear it (a hen's bawk: the wolf does; the wolf's
## mark: only the wolf). Its maker's own kind always does.
@export var others_hear: bool = true
@export_group("Where it was")
## Who is shown a marker where it was: nobody, its maker's own kind (a hen's ping, to the hens),
## everyone else (an egg cracking, to the wolf), or everyone.
@export_enum("Nobody", "Its maker's kind", "Everyone else", "Everyone") var marker_for: int = 0
## What the marker says ("Egg cracked!"). Empty: the maker's word for what they pointed at (a ping).
@export var label: String = ""
@export_range(0.5, 20.0, 0.1, "suffix:s") var marker_s: float = 3.0
@export var color: Color = Color(1.0, 0.85, 0.35)

const MARKER_NOBODY: int = 0
const MARKER_MAKERS: int = 1
const MARKER_OTHERS: int = 2
const MARKER_EVERYONE: int = 3

## kind -> [defs, the genre's before the foundation's]
static var _by_kind: Dictionary = {}


func content_type() -> StringName:
	return &"noise"


func why_no_workbench() -> String:
	return "a noise is a sound and a marker: its sound plays in the Inspector, and the game's ping key makes one to hear"


func summary() -> String:
	var who: String = "anyone's" if made_by.is_empty() else ", ".join(made_by.map(func(d: EntityDefinition) -> String: return d.display_name if d else "?"))
	var reach: String = "everywhere" if heard_within_m <= 0.0 else "%d m" % roundi(heard_within_m)
	return "kind %d, %s, heard %s%s" % [kind, who, reach, "" if others_hear else " (its maker's kind only)"]


func to_bake() -> Dictionary:
	return {"id": id, "name": display_name, "kind": kind, "heard_within_m": heard_within_m, "others_hear": others_hear,
		"marker_for": marker_for, "made_by": made_by.map(func(d: EntityDefinition) -> Variant: return ContentDef.ref(d))}


func validate() -> Array[String]:
	var out: Array[String] = super()
	var owner: String = ContentLibrary.owner_of_path(resource_path)
	if owner != ContentLibrary.FOUNDATION and owner != "" and kind > 1 and kind < 100:
		out.append("a genre's noises are numbered from 100 (1 is the ping, to give it a maker's own sound)")
	if sound == null:
		out.append("it has no sound")
	return out


## Whether it is made by a character of `maker_kind` (any, when it names none).
func made_by_kind(maker_kind: int) -> bool:
	if made_by.is_empty():
		return true
	for d: EntityDefinition in made_by:
		if d != null and d.kind == maker_kind:
			return true
	return false


## Whether someone of `my_kind` hears one made by `maker_kind`, `dist` metres off.
func heard(maker_kind: int, my_kind: int, dist: float) -> bool:
	if not others_hear and my_kind != maker_kind:
		return false
	return heard_within_m <= 0.0 or dist <= heard_within_m


## Whether someone of `my_kind` is shown where one made by `maker_kind` was (`maker_kind` 0 and a
## noise of the world's own: "everyone else" is everyone).
func marked_for(maker_kind: int, my_kind: int, mine: bool) -> bool:
	match marker_for:
		MARKER_MAKERS:
			return my_kind == maker_kind
		MARKER_OTHERS:
			return not mine and (maker_kind <= 0 or my_kind != maker_kind)
		MARKER_EVERYONE:
			return true
	return false


## THE NOISE a row of `kind` made by a character of `maker_kind` is: the genre's that names its maker,
## then the genre's for anyone, then the foundation's likewise. Null: none (it is not heard).
static func find(p_kind: int, maker_kind: int) -> NoiseDef:
	var defs: Array = _table().get(p_kind, [])
	for pass_named: bool in [true, false]:
		for d: NoiseDef in defs:
			if (not d.made_by.is_empty()) == pass_named and d.made_by_kind(maker_kind):
				return d
	return null


static func clear_cache() -> void:
	_by_kind.clear()


static func _table() -> Dictionary:
	if not _by_kind.is_empty() and not Engine.is_editor_hint():
		return _by_kind
	var genre: Dictionary = {}
	var foundation: Dictionary = {}
	for f: Dictionary in ContentLibrary.files():
		var folder: String = ContentLibrary.folder_for(&"noise", String(f["owner"])) + "/"
		if not String(f["path"]).begins_with(folder):
			continue
		var d: NoiseDef = load(String(f["path"])) as NoiseDef
		if d == null:
			continue
		var into: Dictionary = foundation if String(f["owner"]) == ContentLibrary.FOUNDATION else genre
		if not into.has(d.kind):
			into[d.kind] = []
		(into[d.kind] as Array).append(d)
	var out: Dictionary = {}
	for k: int in genre:
		out[k] = (genre[k] as Array).duplicate()
	for k: int in foundation:
		if not out.has(k):
			out[k] = []
		(out[k] as Array).append_array(foundation[k])
	_by_kind = out
	return out
