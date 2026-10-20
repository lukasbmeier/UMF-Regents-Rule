@tool
class_name FoeWorkbench extends Workbench
## THE FOE BENCH (Regent's Rule, 2026-10-20): a foe on the bench, its model playing its kit's swings, and
## its fight worked out from the content, so a foe is tuned in the Inspector and its effect read here.
## The damage is the server's own rule (`genre::regents::hit_damage`, mirrored in `hit_damage` below);
## the swing's rhythm its brain's (`sidecar/npc/brains/regents/foe.gd`: each swing waits out its lock, a
## combo ends with `rest_ms`, every `heavy_every`th swing is the heavy).
##
##   sheet    health, its swings and what each does to you, its damage a second over a whole rhythm, the
##            XP a kill pays
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
	for a: AbilityDef in f.kit.light + ([f.kit.heavy] if f.kit.heavy != null else []):
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
	var quality: float = 1.0 + float(mini(quality_pm, 1000)) / 5000.0
	var mastery: float = 1.0 + float(mini(3 * maxi(rank - 1, 0), 27)) / 100.0
	return ability_damage * float(weapon_pct) / 100.0 * quality * mastery


## Its rhythm, as its brain swings: [{ability, damage, wait_ms}] over one whole pattern (until the heavy
## comes round again, or one combo when it never swings its heavy), and the time it takes.
static func rhythm(f: FoeDef) -> Dictionary:
	var swings: Array[Dictionary] = []
	var total_ms: int = 0
	var kit: KitDef = f.kit
	var n: int = maxi(f.heavy_every, kit.light.size()) if f.heavy_every > 0 and kit.heavy != null else kit.light.size()
	var step: int = 0
	for i: int in range(1, n + 1):
		var heavy: bool = f.heavy_every > 0 and kit.heavy != null and i % f.heavy_every == 0
		var a: AbilityDef = kit.heavy if heavy else kit.light[step % kit.light.size()]
		step = 0 if heavy else step + 1
		var wait: int = kit.lock_ms(a)
		if heavy or step >= kit.light.size():
			step = 0
			wait += f.rest_ms
		swings.append({"ability": a, "damage": hit_damage(a.damage, f.damage_pct, 0, 1), "wait_ms": wait})
		total_ms += wait
	var dmg: float = 0.0
	for s: Dictionary in swings:
		dmg += float(s["damage"])
	return {"swings": swings, "ms": total_ms, "damage": dmg, "dps": dmg / maxf(float(total_ms) / 1000.0, 0.001)}


## A weapon's light combo against a foe of `hp`: its damage a second at rank 1 (each swing waits out its
## lock, a combo chains as soon as the kit lets it), and the seconds to kill.
static func weapon_versus(weapon: ItemDef, hp: float) -> Dictionary:
	var kit: KitDef = KitDef.by_key(weapon.weapon_kit)
	if kit == null:
		return {}
	var dmg: float = 0.0
	var ms: int = 0
	for i: int in kit.light.size():
		var a: AbilityDef = kit.light[i]
		dmg += hit_damage(a.damage, weapon.weapon_damage_pct, 0, 1)
		# The next step may start just after this one lands; the last waits out its lock.
		ms += a.wind_up_ms + kit.chain_ms if i + 1 < kit.light.size() else kit.lock_ms(a)
	var dps: float = dmg / maxf(float(ms) / 1000.0, 0.001)
	return {"weapon": weapon.display_name, "dps": dps, "seconds": hp / maxf(dps, 0.001)}


static func sheet(f: FoeDef) -> String:
	if f.kit == null:
		return "%s: no kit" % f.display_name
	var r: Dictionary = rhythm(f)
	var swings: PackedStringArray = PackedStringArray()
	for a: AbilityDef in f.kit.light + ([f.kit.heavy] if f.kit.heavy != null else []):
		swings.append("%s %.1f" % [a.display_name, hit_damage(a.damage, f.damage_pct, 0, 1)])
	var xp: int = roundi(float(f.hp) * rule(&"combat_xp_per_damage") * float(f.xp_pct) / 100.0)
	return "%s   %d health\nits swings: %s\n%.1f damage a second; a player dies in %.0f s\na kill pays about %d mastery XP" % [
		f.display_name, f.hp, ", ".join(swings), float(r["dps"]), PLAYER_HP / maxf(float(r["dps"]), 0.001), xp]


## What one kill drops on average: {item name: count}.
static func expected_loot(f: FoeDef) -> Dictionary:
	var out: Dictionary = {}
	for i: int in f.loot.size():
		if f.loot[i] == null:
			continue
		var lo: int = f.loot_min[i] if i < f.loot_min.size() else 1
		var hi: int = f.loot_max[i] if i < f.loot_max.size() else lo
		var chance: int = f.loot_chance_pct[i] if i < f.loot_chance_pct.size() else 100
		out[f.loot[i].display_name] = float(chance) / 100.0 * float(lo + hi) / 2.0
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
			for i: int in f.loot.size():
				var chance: int = f.loot_chance_pct[i] if i < f.loot_chance_pct.size() else 100
				if f.loot[i] != null and chance < 10:
					rare += "  ·  %s: one in %d kills" % [f.loot[i].display_name, roundi(100.0 / float(chance))]
			return "a kill drops on average %s%s" % [", ".join(parts), rare]
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
