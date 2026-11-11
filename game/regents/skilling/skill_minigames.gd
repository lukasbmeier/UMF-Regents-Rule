class_name SkillMinigames extends RefCounted
## THE SKILLING MINIGAMES, IN ONE PLACE: what kind each params resource is (branch dodge, crack the rock,
## bellows then pour, shape to the outline, smelting's rhythm track), the challenge kind the server deals it as, its model's replay,
## its UI, and what a faster tool does to it. A node's or a recipe's `minigame` is one of these params
## resources; everything that plays one asks here. A new minigame is a params class, a model (with its
## Rust twin and goldens), a UI, and a line in each function below.

const CHOP: StringName = &"chop"
const CRACK: StringName = &"crack"
const SMELT: StringName = &"smelt"
const SHAPE: StringName = &"shape"
## Smelting as a rhythm track (Luke, 2026-11-07); `SMELT` (bellows by the band) stays for old rounds.
const BEAT: StringName = &"beat"
## Woodworking's carve (Luke, 2026-11-07): a vertical stave, wood off either side.
const CARVE: StringName = &"carve"
## Herbalism's pull the root (Luke's H3, 2026-11-07): hold to pull, mind the strain.
const PULL: StringName = &"pull"
## Skinning's cut line (Luke's H4, 2026-11-07): drag the knife along the line, off it tears the hide.
const SKIN: StringName = &"skin"

## The rounds played at a gathering node (a `NodeDef`): the others are a station's (a `RecipeDef`). A new gathering
## kind goes here, and in the server's bake (`server/build/regents.rs`, the node check).
const GATHERING: Array[StringName] = [CHOP, CRACK, PULL, SKIN]

## The challenge kinds the server deals them as (`genre::regents`).
const CHALLENGE: Dictionary[StringName, int] = {CHOP: 100, CRACK: 101, SMELT: 102, SHAPE: 103, BEAT: 104, CARVE: 105, PULL: 106, SKIN: 107}


static func kind_of(params: Resource) -> StringName:
	if params is ChopParams:
		return CHOP
	if params is CrackParams:
		return CRACK
	if params is SmeltParams:
		return SMELT
	if params is ShapeParams:
		return SHAPE
	if params is BeatParams:
		return BEAT
	if params is CarveParams:
		return CARVE
	if params is PullParams:
		return PULL
	if params is SkinParams:
		return SKIN
	return &""


## Whether `kind` is played at a gathering node (its content a `NodeDef`), not at a station.
static func gathers(kind: StringName) -> bool:
	return kind in GATHERING


static func kind_of_challenge(challenge_kind: int) -> StringName:
	for k: StringName in CHALLENGE:
		if CHALLENGE[k] == challenge_kind:
			return k
	return &""


## How many numbers one input is (time and side; time and x, y; time and code; time and column).
static func arity(kind: StringName) -> int:
	return 3 if kind == CRACK or kind == SKIN else 2


## How long a round of `params` lasts (the server's `Minigame::duration_ms`).
static func duration_of(params: Resource) -> int:
	if params is SmeltParams:
		return (params as SmeltParams).heat_ms + (params as SmeltParams).pour_ms
	if params is BeatParams:
		return BeatModel.duration_ms(params as BeatParams)
	return int(params.get(&"duration_ms")) if params != null and kind_of(params) != &"" else 0


## `params` as a tool `speed_pct` (100: as authored) makes it: a faster swing for the gathering rounds, a quicker
## quicker stroke for the trowel (dig, cut), a faster cut for the knife. The server applies the same (`genre::regents`), from the round's payload.
static func with_speed(params: Resource, speed_pct: int) -> Resource:
	if speed_pct == 100 or not gathers(kind_of(params)):
		return params
	var p: Resource = params.duplicate()
	if p is SkinParams:   # a better knife cuts faster
		(p as SkinParams).cut_speed = maxi(1, (p as SkinParams).cut_speed * 100 / maxi(1, speed_pct))
		return p
	var key: StringName = &"stroke_ms" if p is PullParams else &"swing_ms"
	p.set(key, maxi(50, int(p.get(key)) * speed_pct / 100))
	return p


## `params` EASED by `ease_pct` (Luke's M3, 2026-11-05: each mastery rank above the requirement widens a round's
## windows a few percent, capped; the server says how much in the round's payload, its fifth field). The server's
## `Minigame::score_eased` does the same, number for number: a branch staggers for less, the rock's notch is wider,
## the furnace's band or the beat's windows wider (the outer window never past a quarter beat), the anvil's bar hot
## longer and its error scale larger, a root's catches jump less, the knife cuts further off the line. 0: as authored (the content is never changed: a copy).
static func eased(params: Resource, ease_pct: int) -> Resource:
	var e: int = clampi(ease_pct, 0, 50)
	if e == 0 or kind_of(params) == &"":
		return params
	var p: Resource = params.duplicate()
	if p is ChopParams:
		(p as ChopParams).stagger_ms = (p as ChopParams).stagger_ms * (100 - e) / 100
	elif p is CrackParams:
		(p as CrackParams).radius_pm = (p as CrackParams).radius_pm * (100 + e) / 100
	elif p is SmeltParams:
		(p as SmeltParams).band_half_start = (p as SmeltParams).band_half_start * (100 + e) / 100
		(p as SmeltParams).band_half_end = (p as SmeltParams).band_half_end * (100 + e) / 100
	elif p is ShapeParams:
		(p as ShapeParams).error_scale = (p as ShapeParams).error_scale * (100 + e) / 100
		(p as ShapeParams).heat_ms = (p as ShapeParams).heat_ms * (100 + e) / 100   # hot longer: fewer reheats
	elif p is CarveParams:
		(p as CarveParams).error_scale = (p as CarveParams).error_scale * (100 + e) / 100
	elif p is PullParams:
		(p as PullParams).jump_lo = (p as PullParams).jump_lo * (100 - e) / 100
		(p as PullParams).jump_hi = (p as PullParams).jump_hi * (100 - e) / 100
		(p as PullParams).hold_pm = (p as PullParams).hold_pm * (100 - e) / 100
	elif p is SkinParams:
		(p as SkinParams).near = (p as SkinParams).near * (100 + e) / 100
	elif p is BeatParams:
		var b: BeatParams = p as BeatParams
		var good: int = maxi(b.good_ms, mini(b.good_ms * (100 + e) / 100, b.beat_ms / 4))
		b.perfect_ms = mini(b.perfect_ms * (100 + e) / 100, good)
		b.good_ms = good
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
		BEAT:
			return BeatModel.play(seed_value, params as BeatParams, inputs)
		CARVE:
			return CarveModel.play(seed_value, params as CarveParams, inputs)
		PULL:
			return PullModel.play(seed_value, params as PullParams, inputs)
		SKIN:
			return SkinModel.play(seed_value, params as SkinParams, inputs)
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
		BEAT:
			return BeatMinigame.new()
		CARVE:
			return CarveMinigame.new()
		PULL:
			return PullMinigame.new()
		SKIN:
			return SkinMinigame.new()
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
