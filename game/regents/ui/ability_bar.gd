class_name RegentsAbilityBar extends Control
## THE ABILITY BAR (Luke's B11 and B12, 2026-11-13, `ABILITIES_PREP.md` §7 step 1), low in the middle, in place of the
## text line that said every key:
##
##   [health ...........................................]
##   (weapon) (Ctrl)  ( Q )( E )( R )  ( F )   (G)  |mana| or arrows
##                    `---- ring ----'
##
##   the weapon     its picture; hover for its moves (the string, the guard, the roll, Tab) and its mastery
##   Ctrl           the roll, its cooldown on it
##   Q E R          THE WEAPON'S THREE, its abilities by its kit and your mastery (step 2: the item's level and
##                  picks); a THIN RING round them fills toward the next one that opens
##   F              THE CHEST'S (armor to come; the staff keeps its fourth spell there until then)
##   G              the potion key (B7), apart; nothing to drink yet
##   beside         the staff's mana, or the bow's arrows and its chance to hit
## Every key is its action's binding (`CombatComponent.SLOT_ACTIONS`), never a constant (B5). Out of stance the bar
## FADES (Q E R F are not abilities then, and E works what is in front of you); in stance its slots' edges LIGHT; in a
## fight (hit or hurt lately) a red glow sits under it (B12). No role or mechanic names anywhere (show, don't name).
##
## Two looks, round and square (`RegentsBarStyle`, `LOOKS`), picked in Settings (Game: "Ability bar") or compared
## side by side in `res://game/regents/ui/bar_lab.tscn`. The bar decides nothing: `model_for` reads the combat and
## skilling components into a Dictionary, and `show_model` draws it, so the lab and the tests feed it their own.

## The weapon on the bar was clicked (the cursor free): its abilities window opens (the HUD's).
signal weapon_pressed()

## The looks, by the setting's index.
const LOOKS: Array[String] = ["res://game/regents/ui/bar_round.tres", "res://game/regents/ui/bar_square.tres"]
const LOOK_NAMES: PackedStringArray = ["Round", "Square"]
const SETTING: StringName = &"regents_ability_bar"
## From the screen's bottom edge to the slots' bottom.
const BOTTOM_MARGIN: float = 22.0
const IDLE_FADE_S: float = 0.25

var style: RegentsBarStyle = null
## The last model shown.
var model: Dictionary = {}
var health_bar: ProgressBar = null
## Beside the slots: the staff's mana (filling up), or the bow's arrows (a count and the chance to hit).
var pool_bar: ProgressBar = null
var pool_label: Label = null
var weapon_slot: RegentsAbilitySlot = null
var roll_slot: RegentsAbilitySlot = null
## Q E R F, in order.
var slots: Array[RegentsAbilitySlot] = []
var potion_slot: RegentsAbilitySlot = null
## Where the ring round the weapon's three runs (this control's space), and how full.
var _ring_rect: Rect2 = Rect2()
var _ring: float = 0.0
var _combat: bool = false
var _alpha: float = 1.0
## Whether this bar follows the setting (the HUD's), or keeps the look it was given (the lab's).
var follows_setting: bool = true


## The setting (Game: "Ability bar"): round or square. Defined once.
static func define_setting() -> void:
	if not Settings.entry(SETTING).is_empty():
		return
	Settings.define(SETTING, Settings.GAME, "Ability bar", Settings.Kind.CHOICE, 0, {
		"choices": LOOK_NAMES,
		"tooltip": "How the ability bar at the bottom of the screen looks: round slots, or square ones.",
	})


static func look(index: int) -> RegentsBarStyle:
	return load(LOOKS[clampi(index, 0, LOOKS.size() - 1)]) as RegentsBarStyle


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if follows_setting:
		define_setting()
		Settings.changed.connect(_on_setting)
		style = look(int(Settings.get_value(SETTING)))
	elif style == null:
		style = look(0)
	_build()


func _on_setting(key: StringName, value: Variant) -> void:
	if key == SETTING:
		set_style(look(int(value)))


## Change the look (the setting, or the lab).
func set_style(s: RegentsBarStyle) -> void:
	style = s
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	slots.clear()
	_build()
	if not model.is_empty():
		show_model(model)


func _build() -> void:
	health_bar = RegentsHud.make_bar(self, style.health_color, float(style.health_height), "Health")
	pool_bar = RegentsHud.make_bar(self, style.mana_color, 10.0, "Pool")
	pool_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	pool_bar.visible = false
	pool_label = Label.new()
	pool_label.name = "PoolText"
	pool_label.add_theme_font_size_override(&"font_size", 14)
	pool_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	pool_label.add_theme_constant_override(&"outline_size", 5)
	pool_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pool_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(pool_label)
	weapon_slot = _slot("Weapon", true)
	weapon_slot.pressed.connect(func() -> void: weapon_pressed.emit())
	roll_slot = _slot("Roll", true)
	for i: int in 4:
		slots.append(_slot("Slot%d" % (i + 1), false))
	potion_slot = _slot("Potion", true)
	_layout()


func _slot(slot_name: String, small: bool) -> RegentsAbilitySlot:
	var s: RegentsAbilitySlot = RegentsAbilitySlot.new()
	s.name = slot_name
	s.style = style
	var side: float = float(style.small_size if small else style.slot_size)
	s.size = Vector2(side, side)
	s.custom_minimum_size = s.size
	add_child(s)
	return s


## Lay the row out (this control is as wide as it, bottom center, its own size).
func _layout() -> void:
	var big: float = float(style.slot_size)
	var small: float = float(style.small_size)
	var gap: float = float(style.gap)
	var group: float = float(style.group_gap)
	var pool_w: float = 64.0
	var width: float = small * 2.0 + gap + group + big * 3.0 + gap * 2.0 + group + big + group + small + gap + pool_w
	var top: float = float(style.health_height) + 10.0 + float(style.ring_margin)
	var x: float = 0.0
	var mid: float = top + big * 0.5
	weapon_slot.position = Vector2(x, mid - small * 0.5)
	x += small + gap
	roll_slot.position = Vector2(x, mid - small * 0.5)
	x += small + group
	var ring_from: float = x
	for i: int in 3:
		slots[i].position = Vector2(x, top)
		x += big + (gap if i < 2 else 0.0)
	_ring_rect = Rect2(Vector2(ring_from, top), Vector2(x - ring_from, big)).grow(float(style.ring_margin))
	x += group
	slots[3].position = Vector2(x, top)
	x += big + group
	potion_slot.position = Vector2(x, mid - small * 0.5)
	x += small + gap
	pool_bar.position = Vector2(x, top + 4.0)
	pool_bar.size = Vector2(12.0, big - 8.0)
	pool_label.position = Vector2(x + 18.0, top)
	pool_label.size = Vector2(pool_w, big)
	var height: float = top + big + float(style.ring_margin) + 12.0
	health_bar.position = Vector2(ring_from - small - gap, 0.0)
	health_bar.size = Vector2(_ring_rect.end.x + group + big - (ring_from - small - gap), float(style.health_height))
	custom_minimum_size = Vector2(width, height)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -height - BOTTOM_MARGIN
	offset_bottom = -BOTTOM_MARGIN
	queue_redraw()


## Show `m` (as `model_for` makes it).
func show_model(m: Dictionary) -> void:
	model = m
	var stance: bool = bool(m.get("stance", false))
	weapon_slot.show_data(m.get("weapon", {}) as Dictionary, stance)
	roll_slot.show_data(m.get("roll", {}) as Dictionary, stance)
	var list: Array = m.get("slots", []) as Array
	for i: int in slots.size():
		slots[i].show_data(list[i] as Dictionary if i < list.size() else {}, stance)
	potion_slot.show_data(m.get("potion", {}) as Dictionary, stance)
	var h: Vector2 = m.get("health", Vector2(-1.0, -1.0)) as Vector2
	health_bar.visible = h.y > 0.0
	if h.y > 0.0:
		RegentsHud.set_bar(health_bar, h.x, h.y, "%d / %d" % [roundi(h.x), roundi(h.y)])
	var pool: Dictionary = m.get("pool", {}) as Dictionary
	var kind: String = String(pool.get("kind", ""))
	pool_bar.visible = kind == "mana"
	if kind == "mana":
		RegentsHud.set_bar(pool_bar, float(pool.get("value", 0.0)), float(pool.get("most", 1.0)), "")
	pool_label.text = String(pool.get("text", ""))
	pool_label.tooltip_text = String(pool.get("tip", ""))
	var ring: float = float(m.get("ring", 0.0))
	var fight: bool = bool(m.get("combat", false))
	if not is_equal_approx(ring, _ring) or fight != _combat:
		_ring = ring
		_combat = fight
		queue_redraw()


## A slot fired (`CombatComponent.swung`): the one holding `ability_id` flashes.
func fired(ability_id: int) -> void:
	for s: RegentsAbilitySlot in slots:
		if int(s.data.get("ability_id", -1)) == ability_id:
			s.flash()


func _process(delta: float) -> void:
	# Out of stance the bar fades; in it, full (B11).
	var want: float = 1.0 if bool(model.get("stance", false)) or model.is_empty() else style.idle_alpha
	_alpha = move_toward(_alpha, want, delta / IDLE_FADE_S)
	var slot_alpha: Color = Color(1, 1, 1, _alpha)
	for s: RegentsAbilitySlot in slots:
		s.modulate = slot_alpha
	potion_slot.modulate = slot_alpha
	if _combat:
		queue_redraw()


func _draw() -> void:
	if style == null:
		return
	# The fight's glow under the whole row, breathing.
	if _combat:
		var glow: Color = style.combat_glow
		glow.a *= 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) / 220.0)
		var area: Rect2 = Rect2(Vector2(0.0, _ring_rect.position.y), Vector2(size.x - 70.0, _ring_rect.size.y)).grow(4.0)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(glow, glow.a * 0.06)
		box.border_color = glow
		box.set_border_width_all(2)
		box.set_corner_radius_all(int(area.size.y * 0.5) if style.round_slots() else style.corner_radius + 4)
		box.shadow_color = Color(glow, glow.a * 0.6)
		box.shadow_size = 14
		draw_style_box(box, area)
	# The ring round the weapon's three: its track, then how full.
	var pts: PackedVector2Array = ring_points(_ring_rect, style.round_slots())
	draw_polyline(pts, style.ring_back, style.ring_width, true)
	var part: PackedVector2Array = along(pts, _ring)
	if part.size() >= 2:
		draw_polyline(part, style.ring_fill, style.ring_width, true)


## The ring's path round `r`, from its top middle clockwise: a stadium (round) or a rounded box (square).
static func ring_points(r: Rect2, rounded_ends: bool) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var rad: float = r.size.y * 0.5 if rounded_ends else minf(10.0, r.size.y * 0.25)
	var corners: Array[Vector2] = [
		Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	out.append(Vector2(r.get_center().x, r.position.y))
	for k: int in 4:
		var from_a: float = -PI * 0.5 + PI * 0.5 * float(k)
		for i: int in 13:
			var a: float = from_a + PI * 0.5 * float(i) / 12.0
			out.append(corners[k] + Vector2(cos(a), sin(a)) * rad)
	out.append(Vector2(r.get_center().x, r.position.y))
	return out


## The first `frac` of path `pts` by its length.
static func along(pts: PackedVector2Array, frac: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if pts.size() < 2 or frac <= 0.0:
		return out
	var total: float = 0.0
	for i: int in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var want: float = total * clampf(frac, 0.0, 1.0)
	out.append(pts[0])
	var done: float = 0.0
	for i: int in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if done + seg >= want:
			out.append(pts[i - 1].lerp(pts[i], (want - done) / maxf(seg, 0.0001)))
			return out
		done += seg
		out.append(pts[i])
	return out


# --- the model: what the bar shows, read from the game (static, so a test or the lab can make one) -------------

## THE BAR'S MODEL for the local player: {weapon, roll, slots (Q E R F), potion, stance, combat, ring, ring_tip,
## pool, health}. Each slot {key, name, glyph, icon, state, left, total, note, tip, count, ability_id}.
static func model_for(c: CombatComponent, sk: SkillingComponent, health: SpaceTimeHealthComponent = null) -> Dictionary:
	var m: Dictionary = {"stance": false, "combat": false, "ring": 0.0, "ring_tip": "", "pool": {}, "slots": []}
	if health != null and is_instance_valid(health):
		m["health"] = Vector2(health.get_current(), health.get_max())
	var slots_out: Array[Dictionary] = []
	if c == null or c.kit == null:
		m["weapon"] = {"state": RegentsAbilitySlot.EMPTY, "glyph": "", "tip": "No weapon wielded.  I opens the bag."}
		m["roll"] = _roll_slot(c)
		for i: int in 4:
			slots_out.append(_empty_slot(i, null))
		m["slots"] = slots_out
		m["potion"] = _potion_slot()
		m["combat"] = c != null and c.in_combat()
		return m
	var k: KitDef = c.kit
	m["stance"] = c.in_stance()
	m["combat"] = c.in_combat()
	# THE ITEM (ABILITIES_PREP.md §7 step 2): its level as you use it, its picks; the bar by its kit's layout.
	var mastery: int = sk.rank_in(k.skill) if sk != null and k.skill != null else c.mastery()
	var xp: int = c.item_xp()
	var picks: Array[int] = c.item_picks()
	var use: int = RegentsItemLevel.usable(RegentsItemLevel.level(k, xp), mastery)
	var on_bar: Array[AbilityDef] = RegentsItemLevel.bar(k, picks)
	on_bar[RegentsItemLevel.F] = c.chest_ability()   # F IS THE WORN CHEST'S (S4, B5): whatever is wielded
	var open: Array[Dictionary] = RegentsItemLevel.open_picks(k, use, picks)
	m["weapon"] = {"state": RegentsAbilitySlot.READY, "icon": c.weapon.icon() if c.weapon != null else null,
		"glyph": c.weapon.display_name.left(1) if c.weapon != null else "?", "tip": moves_words(c, sk) + "
Click it (the cursor free, say with the bag open) for its abilities."}
	m["roll"] = _roll_slot(c)
	var pool: ResourceComponent = c.pool() if k.casts() else null
	for i: int in 4:
		var a: AbilityDef = on_bar[i]
		if a == null:
			slots_out.append(_unfilled_slot(i, c, use, open))
			continue
		var d: Dictionary = {"key": CombatComponent.key_label(CombatComponent.SLOT_ACTIONS[i]), "name": a.display_name,
			"glyph": a.display_name.left(1), "mark": mark_of(a, k), "icon": a.icon(), "ability_id": a.id, "left": 0.0, "total": 0.0,
			"note": "", "count": -1, "state": RegentsAbilitySlot.READY}
		var words: String = ability_words(a, k)
		var why: String = "" if i == RegentsItemLevel.F else RegentsItemLevel.slot_refusal(k, a, use, picks)
		if not why.is_empty():
			d["state"] = RegentsAbilitySlot.LOCKED
			d["note"] = "lvl %d" % RegentsItemLevel.opens_at(k, i)
			d["tip"] = "%s\n%s\n%s." % [a.display_name, words, why.left(1).to_upper() + why.substr(1)]
			slots_out.append(d)
			continue
		d["tip"] = "%s\n%s" % [a.display_name, words]
		var left: float = c.cooldown_left(a)
		if left > 0.0:
			d["state"] = RegentsAbilitySlot.COOLING
			d["left"] = left
			d["total"] = maxf(c.cooldown_total(a), left)
		elif pool != null and k.resource != null and i != RegentsItemLevel.F:
			var spell: SpellDef = SpellDef.by_ability(a.id)
			var cost: float = spell.cost * HotRules.number(&"regents.mana_cost_pct") / 100.0 if spell != null else 0.0
			if cost > 0.0 and not pool.can_pay(k.resource.id, cost):
				d["state"] = RegentsAbilitySlot.COST
		slots_out.append(d)
	m["slots"] = slots_out
	m["potion"] = _potion_slot()
	var p: Dictionary = RegentsItemLevel.progress(k, xp, mastery)
	m["ring"] = float(p["frac"])
	m["ring_tip"] = level_words(c, mastery)
	m["level"] = int(p["level"])
	m["usable"] = int(p["usable"])
	if pool != null and k.resource != null:
		var rid: int = k.resource.id
		m["pool"] = {"kind": "mana", "value": pool.level(rid), "most": pool.max_of(rid),
			"text": "%d" % roundi(pool.level(rid)), "tip": "%d / %d %s" % [roundi(pool.level(rid)), roundi(pool.max_of(rid)), k.resource.display_name.to_lower()]}
	elif k.draws:
		var chance: float = c.hit_chance_now()
		m["pool"] = {"kind": "arrows", "value": float(c.ammo_count()),
			"text": "%d arrows%s" % [c.ammo_count(), ("\n%d%% to hit" % roundi(chance)) if chance >= 0.0 else ""],
			"tip": "Arrows in your bag.  With a target picked, the chance this draw hits it." if chance >= 0.0 else "Arrows in your bag.  No target: it flies where you aim."}
	return m


static func _roll_slot(c: CombatComponent) -> Dictionary:
	var roll: Vector2 = c.roll_cooldown() if c != null else Vector2.ZERO
	var key: String = CombatComponent.key_label(CombatComponent.ACTION_DODGE)
	return {"key": key, "glyph": "", "mark": "roll", "state": RegentsAbilitySlot.COOLING if roll.x > 0.0 else RegentsAbilitySlot.READY,
		"left": roll.x, "total": roll.y, "count": -1,
		"tip": "Roll (%s): nothing hits you while you roll.%s" % [key, "" if roll.x <= 0.0 else "  Ready in %.1f s." % roll.x]}


static func _potion_slot() -> Dictionary:
	return {"key": CombatComponent.key_label(CombatComponent.POTION_ACTION), "glyph": "", "state": RegentsAbilitySlot.EMPTY,
		"tip": "Potions go here, once there are any to drink."}


## A slot with nothing on it yet (`i`: 0 Q .. 3 F): a PICK OPEN now (E, R: "choose"), a pick to come (locked at its
## level, naming what it offers), or nothing for this weapon (`_empty_slot`).
static func _unfilled_slot(i: int, c: CombatComponent, use: int, open: Array[Dictionary]) -> Dictionary:
	var k: KitDef = c.kit
	if i == RegentsItemLevel.E or i == RegentsItemLevel.R:
		var offers: PackedStringArray = PackedStringArray()
		for a: AbilityDef in RegentsItemLevel.choices_for(k, 0 if i == RegentsItemLevel.E else 2):
			offers.append(a.display_name)
		for o: Dictionary in open:
			if (int(o["n"]) < 2) == (i == RegentsItemLevel.E):
				var names: PackedStringArray = PackedStringArray()
				for a: AbilityDef in o["options"] as Array[AbilityDef]:
					names.append(a.display_name)
				return {"key": CombatComponent.key_label(CombatComponent.SLOT_ACTIONS[i]), "glyph": "+", "state": RegentsAbilitySlot.CHOOSE,
					"count": -1, "note": "choose", "tip": "A pick is open: %s.\nClick your weapon (on this bar, or in the bag) to choose." % " or ".join(names)}
		if not offers.is_empty() and use < RegentsItemLevel.opens_at(k, i):
			return {"key": CombatComponent.key_label(CombatComponent.SLOT_ACTIONS[i]), "glyph": "", "state": RegentsAbilitySlot.LOCKED,
				"count": -1, "note": "lvl %d" % RegentsItemLevel.opens_at(k, i),
				"tip": "At the weapon's level %d, choose one: %s." % [RegentsItemLevel.opens_at(k, i), ", ".join(offers)]}
	return _empty_slot(i, c)


## An empty slot `i` (0 Q .. 3 F), and what goes there (B7: until tools exist it shows what fills it).
static func _empty_slot(i: int, c: CombatComponent) -> Dictionary:
	var tip: String
	if i == 3:
		tip = "Empty.  A chest you wear may put its own ability here: a robe, a jerkin or a cuirass each gives one."
	elif c == null or c.kit == null:
		tip = "Empty.  Wield a weapon: its abilities go here."
	else:
		tip = "Empty.  More comes with mastering the %s." % String(c.kit.key)
	return {"key": CombatComponent.key_label(CombatComponent.SLOT_ACTIONS[i]), "glyph": "", "state": RegentsAbilitySlot.EMPTY,
		"tip": tip, "count": -1}


## The XP rank `r` takes (0 for rank 1).
static func _xp_for(s: SkillDef, r: int) -> int:
	return s.xp_to_rank[clampi(r - 2, 0, s.xp_to_rank.size() - 1)] if r >= 2 and not s.xp_to_rank.is_empty() else 0


## THE WEAPON'S LEVEL in words (B11: the item's level against your mastery, in its tooltip): "Level 7, counting as 5 for
## you (Sorcery 5). At level 12: its second pick."
static func level_words(c: CombatComponent, mastery: int) -> String:
	if c == null or c.kit == null or c.kit.skill == null:
		return ""
	var k: KitDef = c.kit
	var p: Dictionary = RegentsItemLevel.progress(k, c.item_xp(), mastery)
	var lvl: int = int(p["level"])
	var line: String = "Level %d" % lvl
	if int(p["usable"]) < lvl:
		line += ", counting as %d for you (%s %d)" % [int(p["usable"]), k.skill.display_name, mastery]
	line += "."
	var next: int = int(p["next"])
	if next > 0:
		var what: String = {k.unlock_level(1): "its first pick", k.unlock_level(2): "its second pick", k.unlock_level(3): "its last pick"}.get(next, "more")
		line += "  At level %d: %s (%d%% of the way)." % [next, what, roundi(float(p["frac"]) * 100.0)]
	return line


## The mark drawn for `a` until it has an icon (`RegentsAbilitySlot.draw_mark`): by how it lands.
static func mark_of(a: AbilityDef, k: KitDef) -> String:
	var spell: SpellDef = SpellDef.by_ability(a.id) if (k != null and k.casts()) or RegentsItemLevel.is_worn_ability(a) else null
	if spell != null:
		return ["bolt", "area", "blink", "cone"][spell.kind]
	return "lunge" if a.lunges else "strike"


## WHAT AN ABILITY DOES, in the player's words, from its numbers (no role or mechanic names).
static func ability_words(a: AbilityDef, k: KitDef) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var spell: SpellDef = SpellDef.by_ability(a.id) if (k != null and k.casts()) or RegentsItemLevel.is_worn_ability(a) else null
	if spell != null:
		var dmg: String = "%d damage" % roundi(a.damage)
		match spell.kind:
			SpellDef.Kind.BOLT:
				var extra: String = ""
				if spell.splash_m > 0.0 and spell.splash_pct > 0:
					extra += ", and %d%% of it to those within %.0f m" % [spell.splash_pct, spell.splash_m]
				if spell.burn_dps > 0.0 and spell.burn_ms > 0:
					extra += "; it burns %d a second for %.0f s" % [roundi(spell.burn_dps), float(spell.burn_ms) / 1000.0]
				lines.append("Flies at your target, or where you aim: %s%s." % [dmg, extra])
			SpellDef.Kind.AREA:
				var then: String = " and %s for %.0f s" % [spell.status.display_name.to_lower(), float(spell.status_ms) / 1000.0] if spell.status != null else ""
				lines.append("A circle %.0f m wide where you aim, up to %.0f m away, landing after %.1f s: %s%s." % [
					spell.radius_m * 2.0, a.range_m, float(spell.delay_ms) / 1000.0, dmg, then])
			SpellDef.Kind.BLINK:
				lines.append("Carries you %.0f m the way you look, at once." % a.range_m)
			SpellDef.Kind.CONE:
				var slows: String = ", %s for %.1f s" % [spell.status.display_name.to_lower(), float(spell.status_ms) / 1000.0] if spell.status != null else ""
				lines.append("Everything within %.0f m in front of you: %s%s%s.  It can knock a foe off its feet." % [
					a.range_m, dmg, ", pushed away" if spell.push_mps > 0.0 else "", slows])
		if spell.cast_ms > 0:
			lines.append("Takes %.1f s to cast%s." % [float(spell.cast_ms) / 1000.0, "" if spell.cast_while_moving else ", standing still"])
		if spell.cost > 0.0 and k.resource != null:
			lines.append("Costs %d %s." % [roundi(spell.cost * HotRules.number(&"regents.mana_cost_pct") / 100.0), k.resource.display_name.to_lower()])
	elif a.lunges:
		lines.append("Carries you forward into a strike: %d damage, reaching %.1f m." % [roundi(a.damage), a.reach_m])
	else:
		lines.append("A strike in front of you: %d damage, reaching %.1f m." % [roundi(a.damage), a.reach_m])
	if a.cooldown_ms > 0:
		lines.append("Ready again %.0f s after." % (float(a.cooldown_ms) / 1000.0))
	return "\n".join(lines)


## THE WEAPON'S MOVES, what the old text line said (B11: off the bar, into the weapon's tooltip and the tutorial):
## the string by its moves' names, the guard, the roll, Tab; and its mastery toward the next unlock.
static func moves_words(c: CombatComponent, sk: SkillingComponent) -> String:
	if c == null or c.kit == null:
		return "No weapon wielded.  I opens the bag."
	var k: KitDef = c.kit
	var lines: PackedStringArray = PackedStringArray([c.weapon.display_name if c.weapon != null else "?"])
	var roll: String = CombatComponent.key_label(CombatComponent.ACTION_DODGE)
	if k.casts():
		lines.append("Left click: %s" % k.light[0].display_name)
	elif k.draws:
		lines.append("Hold left click: draw.  Let go: loose.")
		lines.append("Right click: let the draw go and parry")
	else:
		var role: RoleDef = c.role()
		lines.append("Left click: %s" % RegentsHud.string_names(k, role))
		var guard: String = "hold for " + role.guard_words.get_slice(":", 0) if role != null and not role.guard_words.is_empty() else "hold to block"
		lines.append("Right click: tap to parry, %s" % guard)
		var entry: KitRole = k.role_entry(role) if role != null else null
		if entry != null and not entry.does.is_empty():
			lines.append(entry.does)
	lines.append("%s: roll    Tab: the next target in front    Esc: none" % roll)
	var lvl: String = level_words(c, sk.rank_in(k.skill) if sk != null and k.skill != null else c.mastery())
	if not lvl.is_empty():
		lines.append(lvl)
	return "\n".join(lines)
