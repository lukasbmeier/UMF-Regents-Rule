class_name SkillMinigames extends RefCounted
## THE SKILLING MINIGAMES, IN ONE PLACE: what kind each params resource is (branch dodge, crack the rock,
## bellows then pour, shape to the outline), the challenge kind the server deals it as, its model's replay,
## its UI, and what a faster tool does to it. A node's or a recipe's `minigame` is one of these params
## resources; everything that plays one asks here. A new minigame is a params class, a model (with its
## Rust twin and goldens), a UI, and a line in each function below.

const CHOP: StringName = &"chop"
const CRACK: StringName = &"crack"
const SMELT: StringName = &"smelt"
const SHAPE: StringName = &"shape"

## The challenge kinds the server deals them as (`genre::regents`).
const CHALLENGE: Dictionary[StringName, int] = {CHOP: 100, CRACK: 101, SMELT: 102, SHAPE: 103}


static func kind_of(params: Resource) -> StringName:
	if params is ChopParams:
		return CHOP
	if params is CrackParams:
		return CRACK
	if params is SmeltParams:
		return SMELT
	if params is ShapeParams:
		return SHAPE
	return &""


static func kind_of_challenge(challenge_kind: int) -> StringName:
	for k: StringName in CHALLENGE:
		if CHALLENGE[k] == challenge_kind:
			return k
	return &""


## How many numbers one input is (time and side; time and x, y; time and code; time and column).
static func arity(kind: StringName) -> int:
	return 3 if kind == CRACK else 2


## How long a round of `params` lasts (the server's `Minigame::duration_ms`).
static func duration_of(params: Resource) -> int:
	if params is SmeltParams:
		return (params as SmeltParams).heat_ms + (params as SmeltParams).pour_ms
	return int(params.get(&"duration_ms")) if params != null and kind_of(params) != &"" else 0


## `params` as a tool `speed_pct` (100: as authored) makes it: a faster swing for the gathering rounds.
## The server applies the same (`genre::regents`), from the round's payload.
static func with_speed(params: Resource, speed_pct: int) -> Resource:
	if speed_pct == 100 or not (params is ChopParams or params is CrackParams):
		return params
	var p: Resource = params.duplicate()
	p.set(&"swing_ms", maxi(50, int(p.get(&"swing_ms")) * speed_pct / 100))
	return p


## A round of `params` replayed from its flat inputs: what the server will score.
static func play(seed_value: int, params: Resource, inputs: PackedInt32Array) -> Dictionary:
	match kind_of(params):
		CHOP:
			return ChopModel.play(seed_value, params as ChopParams, inputs)
		CRACK:
			return CrackModel.play(seed_value, params as CrackParams, inputs)
		SMELT:
			return SmeltModel.play(seed_value, params as SmeltParams, inputs)
		SHAPE:
			return ShapeModel.play(seed_value, params as ShapeParams, inputs)
	return {}


## The UI that plays `params`, ready for `begin`.
static func make_ui(params: Resource) -> SkillMinigame:
	match kind_of(params):
		CHOP:
			return ChopMinigame.new()
		CRACK:
			return CrackMinigame.new()
		SMELT:
			return SmeltMinigame.new()
		SHAPE:
			return ShapeMinigame.new()
	return null


## `params` baked for the server: its kind and its numbers.
static func bake(params: Resource) -> Dictionary:
	var kind: StringName = kind_of(params)
	if kind == &"":
		return {}
	var out: Dictionary = {"kind": String(kind)}
	for prop: Dictionary in params.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_STORAGE == 0 or String(prop["name"]) in ["display_name", "script", "resource_local_to_scene", "resource_name", "resource_path"]:
			continue
		var v: Variant = params.get(prop["name"])
		if v is int:
			out[prop["name"]] = v
		elif v is PackedInt32Array:
			out[prop["name"]] = Array(v)
	return out
