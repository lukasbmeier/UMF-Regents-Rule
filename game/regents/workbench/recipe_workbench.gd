@tool
class_name RecipeWorkbench extends Workbench
## THE RECIPE BENCH (Regent's Rule, owner 2026-10-19): a recipe at its station, with what it costs and
## what it pays worked out from the content, so the chain's numbers (ore to a bar, XP a batch, how long a
## batch takes) are tuned in the Inspector and their effect read here, not guessed. The numbers are the
## server's own rules (`genre::regents`: `work_xp`, `craft_xp`, variety, first make) and the hot rules'
## defaults (`content/rules/regents.tres`); its round is played in the skilling lab.
##
##   sheet      what it takes and makes, XP a batch (its own, the work in its inputs, the first-make
##              bonus), how long a batch takes AFK
##   per hour   AFK and played: batches, XP (fresh, and after an hour of wearing stale), and what it eats
##   chain      the raw materials behind one batch, and the minutes of AFK gathering they are
##   against    an hour of it against an hour of gathering its inputs: the OSRS-glassblowing check

const RULES: String = "res://game/regents/content/rules/regents.tres"
const LAB: String = "res://game/regents/skilling/skilling_lab.tscn"
## A played round's score the per-hour figures assume (a good, not perfect, player).
const PLAYED_SCORE_PM: int = 800

var _station: Node3D = null
var _sheet: Label3D = null
## The last test's numbers (tests).
var last_measure: Dictionary = {}


func content_type() -> StringName:
	return &"recipe"


func test_actions() -> Array[StringName]:
	return [&"sheet", &"per_hour", &"chain", &"against"]


func test_label(action: StringName) -> String:
	match action:
		&"per_hour": return "per hour"
		&"against": return "against gathering"
	return String(action)


func test_info(action: StringName) -> String:
	match action:
		&"sheet": return "What it takes and makes, the XP a batch pays and how long a batch takes"
		&"per_hour": return "An hour of it, AFK and played: batches, XP (fresh and worn stale), what it eats"
		&"chain": return "The raw materials behind one batch, and the minutes of AFK gathering they are"
		&"against": return "An hour of it against an hour of gathering its inputs, in XP"
	return ""


func bench_actions() -> Array[Dictionary]:
	return [{"name": &"lab", "label": "Play its round (skilling lab)", "tooltip": "Opens the skilling lab, where every round is played"}]


func do_action(action: StringName) -> Dictionary:
	if action == &"lab":
		var editor: Object = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
		if editor != null:
			editor.call(&"open_scene_from_path", LAB)
		return {}
	return super(action)


func load_item(def: ContentDef) -> void:
	_build()
	var r: RecipeDef = def as RecipeDef
	for c: Node in _station.get_children():
		c.queue_free()
	if r == null:
		_sheet.text = "no recipe on the bench"
		return
	var st: StationDef = StationDef.by_key(r.station)
	if st != null:
		for i: int in st.pieces.size():
			if st.pieces[i] != null:
				var piece: Node3D = st.pieces[i].instantiate() as Node3D
				piece.transform = st.piece_transforms[i] if i < st.piece_transforms.size() else Transform3D.IDENTITY
				_station.add_child(piece)
	_sheet.text = sheet(r)


## A hot rule's number as authored (the bench runs with no server).
static func rule(name: StringName) -> float:
	var set: RuleSetDef = load(RULES) as RuleSetDef
	if set != null:
		for e: RuleEntry in set.rules:
			if e != null and e.name == name:
				return e.number
	return 0.0


## XP a batch, as the server pays it, fresh: its own plus the share of its inputs' work.
static func batch_xp(r: RecipeDef) -> int:
	return r.craft_xp(int(rule(&"craft_work_share_pct")))


## The sheet: inputs, output, XP, time.
static func sheet(r: RecipeDef) -> String:
	var ins: PackedStringArray = PackedStringArray()
	for i: int in r.inputs.size():
		ins.append("%d %s" % [r.input_qty[i], r.inputs[i].display_name if r.inputs[i] != null else "?"])
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s at the %s (%s rank %d)" % [r.display_name, r.station, r.skill.display_name if r.skill != null else "?", r.min_rank])
	lines.append("%s  ->  %d %s" % [", ".join(ins), r.output_qty, r.output.display_name if r.output != null else "?"])
	if r.part_slot >= 0:
		var parts: PackedStringArray = PackedStringArray()
		for p: ItemDef in r.part_choices():
			parts.append(p.display_name + (" (%s)" % p.handle_trait_text() if p.handle_trait_text() != "" else ""))
		lines.append("handle: %s" % ", ".join(parts))
	var own: int = r.xp
	var xp: int = batch_xp(r)
	lines.append("XP a batch: %d (its own %d + the work in its inputs %d); the first ever: +%d" % [xp, own, xp - own,
		xp * int(rule(&"first_make_mult"))])
	lines.append("a batch every %.1f s AFK%s" % [r.afk_ms / 1000.0, "; or a round: %s" % SkillMinigames.kind_of(r.minigame) if r.minigame != null else " (AFK only)"])
	return "\n".join(lines)


## An hour of `r`: {"batches", "xp_fresh", "xp_hour" (with variety), "fresh_end" (per mille), "eats" {item: qty}}.
## `played`: rounds at PLAYED_SCORE_PM instead of AFK.
static func per_hour(r: RecipeDef, played: bool) -> Dictionary:
	var mult: float = 1.0
	if played and r.minigame != null and r.quality != RecipeDef.Quality.FROM_ROUND:
		mult = rule(&"active_yield_mult") * PLAYED_SCORE_PM / 1000.0
	var batch_ms: float = float(r.afk_ms) / mult
	if played and r.quality == RecipeDef.Quality.FROM_ROUND and r.minigame != null:
		batch_ms = float(SkillMinigames.duration_of(r.minigame)) + 2000.0   # one a round, and the walk back in
	var batches: int = int(3_600_000.0 / batch_ms)
	var xp: int = batch_xp(r)
	var drain: int = int(round(rule(&"variety_drain_pm_per_min") * r.afk_ms / 60000.0))
	var recover_per_batch: int = int(batch_ms / 1000.0 * rule(&"variety_recover_pm_per_min") / 60.0)
	var floor_pct: int = int(rule(&"variety_floor_pct"))
	var fresh: int = 1000
	var total: int = 0
	for i: int in batches:
		var floor_pm: int = floor_pct * 10
		total += xp * (floor_pm + (1000 - floor_pm) * fresh / 1000) / 1000
		fresh = clampi(fresh - drain + recover_per_batch, 0, 1000)
	var eats: Dictionary = {}
	for i: int in r.inputs.size():
		if r.inputs[i] != null:
			eats[r.inputs[i].display_name] = r.input_qty[i] * batches
	return {"batches": batches, "xp_fresh": xp * batches, "xp_hour": total, "fresh_end": fresh, "eats": eats}


## The raw (gathered) materials behind one batch, {name: qty}, and the AFK minutes gathering them takes
## (a copper tool, rank 1).
static func chain(r: RecipeDef) -> Dictionary:
	var raw: Dictionary = {}
	var ms: Array[float] = [0.0]
	for i: int in r.inputs.size():
		_raw_of(r.inputs[i], float(r.input_qty[i]), raw, ms, 0)
	return {"raw": raw, "minutes": ms[0] / 60000.0}


static func _raw_of(item: ItemDef, qty: float, raw: Dictionary, ms: Array[float], depth: int) -> void:
	if item == null or depth > 8:
		return
	for d: ContentDef in ContentLibrary.items(&"node"):
		var n: NodeDef = d as NodeDef
		if n != null and n.yield_item == item:
			raw[item.display_name] = float(raw.get(item.display_name, 0.0)) + qty
			ms[0] += qty * n.afk_ms_per_item
			return
	for r: RecipeDef in RecipeDef.all():
		if r.output == item:
			var batches: float = qty / maxf(1.0, r.output_qty)
			ms[0] += batches * r.afk_ms
			for i: int in r.inputs.size():
				_raw_of(r.inputs[i], batches * r.input_qty[i], raw, ms, depth + 1)
			return
	raw[item.display_name] = float(raw.get(item.display_name, 0.0)) + qty   # nothing makes it: given


## XP an hour of gathering AFK at the node giving `item` (copper tool, rank 1), or -1 when none does.
static func gathering_xp_hour(item: ItemDef) -> int:
	for d: ContentDef in ContentLibrary.items(&"node"):
		var n: NodeDef = d as NodeDef
		if n != null and n.yield_item == item:
			return int(3_600_000.0 / n.afk_ms_per_item) * n.xp
	return -1


func run_test(action: StringName) -> String:
	var r: RecipeDef = item as RecipeDef
	if r == null:
		return "nothing on the bench"
	match action:
		&"sheet":
			last_measure = {"xp": batch_xp(r)}
			return sheet(r).replace("\n", "  ·  ")
		&"per_hour":
			var afk: Dictionary = per_hour(r, false)
			var played: Dictionary = per_hour(r, true)
			last_measure = {"afk": afk, "played": played}
			var eats: PackedStringArray = PackedStringArray()
			for k: String in afk["eats"]:
				eats.append("%d %s" % [afk["eats"][k], k])
			return "AFK: %d batches, %d XP (%d if it never wore stale; %d%% fresh at the end), eating %s.  Played (rounds at %d%%): %d batches, %d XP" % [
				afk["batches"], afk["xp_hour"], afk["xp_fresh"], int(afk["fresh_end"]) / 10, ", ".join(eats), PLAYED_SCORE_PM / 10,
				played["batches"], played["xp_hour"]]
		&"chain":
			var c: Dictionary = chain(r)
			last_measure = c
			var raw: PackedStringArray = PackedStringArray()
			for k: String in c["raw"]:
				raw.append("%s %s" % [str(snappedf(float(c["raw"][k]), 0.01)), k])
			return "one batch is %s: %.1f minutes of AFK gathering and making" % [", ".join(raw), float(c["minutes"])]
		&"against":
			var me: Dictionary = per_hour(r, false)
			var best: int = -1
			var from: String = ""
			for i: int in r.inputs.size():
				var g: int = gathering_xp_hour(r.inputs[i])
				if g > best:
					best = g
					from = r.inputs[i].display_name
			last_measure = {"craft": me["xp_hour"], "gather": best}
			if best < 0:
				return "an hour of it: %d XP (its inputs are made, not gathered: compare the recipes that make them)" % me["xp_hour"]
			var ratio: float = float(me["xp_hour"]) / float(maxi(1, best))
			return "an hour of it: %d XP; an hour gathering %s: %d XP (x%.2f)%s" % [me["xp_hour"], from, best, ratio,
				"  — crafting is far behind: raise its XP or craft_work_share_pct" if ratio < 0.5 else ""]
	return "no such test"


## Amber: a part slot on no part, inputs it cannot be given.
func fit_checks() -> Array[String]:
	var out: Array[String] = []
	var r: RecipeDef = item as RecipeDef
	if r == null:
		return out
	for i: int in r.inputs.size():
		if r.inputs[i] != null and gathering_xp_hour(r.inputs[i]) < 0 and RecipeDef.all().all(func(x: RecipeDef) -> bool: return x.output != r.inputs[i]):
			out.append("nothing gathers or makes %s: only an admin can give it" % r.inputs[i].display_name)
	return out


func _build() -> void:
	if _sheet != null:
		return
	_station = Node3D.new()
	_station.name = "Station"
	add_child(_station)
	_sheet = Label3D.new()
	_sheet.name = "Sheet"
	_sheet.position = Vector3(0, 2.6, 0)
	_sheet.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sheet.pixel_size = 0.004
	_sheet.font_size = 40
	_sheet.outline_size = 10
	add_child(_sheet)
