@tool
class_name FoeWorkbench extends Workbench
## THE FOE BENCH (Regent's Rule, 2026-10-20): a foe on the bench, its model playing its kit's swings, and
## its fight worked out from the content, so a foe is tuned in the Inspector and its effect read here.
## The damage is the server's own rule (`genre::regents::hit_damage`, mirrored in `hit_damage` below);
## the swing's rhythm its brain's (`sidecar/npc/brains/regents/foe.gd`: each swing waits out its lock, a
## string ends, with its finisher, in `rest_ms`).
##
##   sheet    health, its swings and what each does to you, its damage a second over a whole rhythm, its hits
##            on you a second and the least gap between two of them (COMBAT_OVERHAUL.md §2), the XP a kill
##            pays
##   versus   how long each weapon in the game takes to kill it (its light combo, rank 1, an unmade
##            weapon), and how long it takes to kill you
##   loot     what a kill drops on average, and how many kills a rare drop takes

## A player's health (the foundation's default).
const PLAYER_HP: float = 100.0

var _stage: Node3D = null
var _sheet: Label3D = null
var _player: AnimationPlayer = null
## The last test's numbers (tests).
var last_measure: Dictionary = {}


func content_type() -> StringName:
	return &"foe"


func test_actions() -> Array[StringName]:
	return [&"sheet", &"versus", &"loot"]


func test_info(action: StringName) -> String:
	match action:
		&"sheet": return "Its health, its swings and what each does to you, its damage a second, the XP a kill pays"
		&"versus": return "How long each weapon takes to kill it (rank 1), and how long it takes to kill you"
		&"loot": return "What a kill drops on average, and how many kills a rare drop takes"
	return ""


func bench_actions() -> Array[Dictionary]:
	return [{"name": &"swing", "label": "Play its swings", "tooltip": "Its light combo, then its heavy, on the model"}]


func do_action(action: StringName) -> Dictionary:
	if action == &"swing":
		_play_swings()
		return {}
	return super(action)


func load_item(def: ContentDef) -> void:
	_build()
	for c: Node in _stage.get_children():
		c.queue_free()
	_player = null
	var f: FoeDef = def as FoeDef
	if f == null:
		_sheet.text = "no foe on the bench"
		return
	if f.character != null and f.character.visual_scene != null:
		var model: Node3D = f.character.visual_scene.instantiate() as Node3D
		_stage.add_child(model)
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
		var aset: AnimationSet = f.character.animation_set
		if skel != null and aset != null:
			skel.name = "Skeleton3D"
			_player = AnimationPlayer.new()
			model.add_child(_player)
			_player.root_node = _player.get_path_to(skel.get_parent())
			for k: StringName in aset.libraries:
				_player.add_animation_library(k, aset.libraries[k])
			if not aset.root_motion_bone.is_empty():
				_player.root_motion_track = NodePath("Skeleton3D:%s" % aset.root_motion_bone)
			var idle: StringName = aset.anim_name(AnimationSet.IDLE)
			if _player.has_animation(idle):
				_player.play(idle)
	_sheet.text = sheet(f)


## Its swings, one after another, on the model.
func _play_swings() -> void:
	var f: FoeDef = item as FoeDef
	if f == null or f.kit == null or _player == null:
		return
	var aset: AnimationSet = f.character.animation_set
	var clips: Array[StringName] = []
	for a: AbilityDef in f.kit.light:
		var clip: StringName = aset.anim_name(StringName("ability.%d" % a.id))
		if _player.has_animation(clip):
			clips.append(clip)
	clips.append(aset.anim_name(AnimationSet.IDLE))
	_player.play(clips[0])
	for i: int in range(1, clips.size()):
		_player.queue(clips[i])


# --- the numbers -------------------------------------------------------------------------------------

## A hot rule's default, as the server starts with it.
static func rule(name: StringName) -> float:
	return RecipeWorkbench.rule(name)


## THE SERVER'S DAMAGE RULE (`genre::regents::hit_damage`): an ability's damage, at a weapon's %, its
## quality (thousandths) adding up to a fifth, its fighter's mastery rank adding 3 % a rank past the first.
static func hit_damage(ability_damage: float, weapon_pct: int, quality_pm: int, rank: int) -> float:
	var quality: float = RegentsGrade.quality_mult(quality_pm)
	var mastery: float = 1.0 + float(mini(3 * maxi(rank - 1, 0), 27)) / 100.0
	return ability_damage * float(weapon_pct) / 100.0 * quality * mastery


## Its rhythm, as its brain swings: [{ability, damage, wait_ms}] over its string (the finisher last, then
## its rest), and the time it takes.
static func rhythm(f: FoeDef) -> Dictionary:
	var swings: Array[Dictionary] = []
	var total_ms: int = 0
	var kit: KitDef = f.kit
	for i: int in kit.light.size():
		var a: AbilityDef = kit.light[i]
		var wait: int = kit.lock_ms(a)
		if i + 1 == kit.light.size():
			wait += f.rest_ms
		swings.append({"ability": a, "damage": hit_damage(a.damage, f.damage_pct, 0, 1), "wait_ms": wait})
		total_ms += wait
	var dmg: float = 0.0
	for s: Dictionary in swings:
		dmg += float(s["damage"])
	# Its own hits' least gap: one lands its wind-up after it starts, the next starts the wait after it.
	var least_gap: int = 0
	for i: int in swings.size():
		var a: AbilityDef = swings[i]["ability"]
		var b: AbilityDef = swings[(i + 1) % swings.size()]["ability"]
		var gap: int = int(swings[i]["wait_ms"]) - a.wind_up_ms + b.wind_up_ms
		least_gap = gap if i == 0 else mini(least_gap, gap)
	var secs: float = maxf(float(total_ms) / 1000.0, 0.001)
	return {"swings": swings, "ms": total_ms, "damage": dmg, "dps": dmg / secs, "hits_per_s": float(swings.size()) / secs,
		"least_gap_ms": least_gap}


## A weapon's string against a foe of `hp`: its damage a second at rank 1 (each step starts the moment its
## follow-through lets it; the finisher waits out its lock), and the seconds to kill.
static func weapon_versus(weapon: ItemDef, hp: float) -> Dictionary:
	var kit: KitDef = KitDef.by_key(weapon.weapon_kit)
	if kit == null:
		return {}
	var dmg: float = 0.0
	var ms: int = 0
	for i: int in kit.light.size():
		var a: AbilityDef = kit.light[i]
		dmg += hit_damage(a.damage, weapon.weapon_damage_pct, 0, 1)
		# The next step may start once this one's follow-through is over; the last waits out its lock.
		ms += mini(a.wind_up_ms + kit.follow_for(i), kit.lock_ms(a)) if i + 1 < kit.light.size() else kit.lock_ms(a)
	var dps: float = dmg / maxf(float(ms) / 1000.0, 0.001)
	return {"weapon": weapon.display_name, "dps": dps, "seconds": hp / maxf(dps, 0.001)}


static func sheet(f: FoeDef) -> String:
	if f.kit == null:
		return "%s: no kit" % f.display_name
	var r: Dictionary = rhythm(f)
	var swings: PackedStringArray = PackedStringArray()
	for a: AbilityDef in f.kit.light:
		swings.append("%s %.1f" % [a.display_name, hit_damage(a.damage, f.damage_pct, 0, 1)])
	var xp: int = roundi(float(f.hp) * rule(&"combat_xp_per_damage") * float(f.xp_pct) / 100.0)
	return ("%s   %d health\nits swings: %s\n%.1f damage a second; a player dies in %.0f s\n%.2f hits on you a second, its own at least %d ms apart; " +
		"a group: %d at a time, at least %d ms apart\na kill pays about %d mastery XP") % [
		f.display_name, f.hp, ", ".join(swings), float(r["dps"]), PLAYER_HP / maxf(float(r["dps"]), 0.001),
		float(r["hits_per_s"]), int(r["least_gap_ms"]), int(rule(&"attack_tokens")), int(rule(&"token_gap_ms")), xp]


## What one kill drops on average, to each player who earns a roll: {item name: count} (its loot table's).
static func expected_loot(f: FoeDef) -> Dictionary:
	var out: Dictionary = {}
	if f.loot_table == null:
		return out
	var e: Dictionary = f.loot_table.expected()
	for item_id: int in e:
		out[(e[item_id] as Dictionary)["name"]] = float((e[item_id] as Dictionary)["n"])
	return out


func run_test(action: StringName) -> String:
	var f: FoeDef = item as FoeDef
	if f == null or f.kit == null:
		return "nothing on the bench"
	match action:
		&"sheet":
			var r: Dictionary = rhythm(f)
			last_measure = {"dps": r["dps"], "ms": r["ms"], "swings": (r["swings"] as Array).size()}
			return sheet(f).replace("\n", "  ·  ")
		&"versus":
			var rows: Array[Dictionary] = []
			for it: ContentDef in RegentsContent.items(&"item"):
				var w: ItemDef = it as ItemDef
				if w != null and w.weapon_kit != &"":
					rows.append(weapon_versus(w, float(f.hp)))
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["seconds"]) < float(b["seconds"]))
			var r: Dictionary = rhythm(f)
			last_measure = {"weapons": rows, "kills_player_s": PLAYER_HP / maxf(float(r["dps"]), 0.001)}
			var parts: PackedStringArray = PackedStringArray()
			for row: Dictionary in rows:
				parts.append("%s %.1f s" % [row["weapon"], float(row["seconds"])])
			return "to kill it (rank 1, its light combo): %s.  It kills you in %.0f s." % [", ".join(parts), float(last_measure["kills_player_s"])]
		&"loot":
			var e: Dictionary = expected_loot(f)
			last_measure = e
			var parts: PackedStringArray = PackedStringArray()
			for k: String in e:
				parts.append("%.2f %s" % [float(e[k]), k])
			var rare: String = ""
			for k: String in e:
				if float(e[k]) > 0.0 and float(e[k]) < 0.1:
					rare += "  ·  %s: about one in %d kills" % [k, roundi(1.0 / float(e[k]))]
			return "a kill drops on average (to each player who earns a roll) %s%s" % [", ".join(parts), rare]
	return "no such test"


## Amber: a foe nothing in the game can kill in a minute, or that kills a player in under three seconds.
func fit_checks() -> Array[String]:
	var out: Array[String] = []
	var f: FoeDef = item as FoeDef
	if f == null or f.kit == null:
		return out
	var r: Dictionary = rhythm(f)
	if PLAYER_HP / maxf(float(r["dps"]), 0.001) < 3.0:
		out.append("it kills a player in under 3 s")
	var best: float = INF
	for it: ContentDef in RegentsContent.items(&"item"):
		var w: ItemDef = it as ItemDef
		if w != null and w.weapon_kit != &"":
			best = minf(best, float(weapon_versus(w, float(f.hp))["seconds"]))
	if best > 60.0:
		out.append("no weapon kills it in a minute (the best takes %.0f s)" % best)
	return out


func _build() -> void:
	if _sheet != null:
		return
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	_sheet = Label3D.new()
	_sheet.name = "Sheet"
	_sheet.position = Vector3(0, 2.7, 0)
	_sheet.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sheet.pixel_size = 0.004
	_sheet.font_size = 40
	_sheet.outline_size = 10
	add_child(_sheet)
