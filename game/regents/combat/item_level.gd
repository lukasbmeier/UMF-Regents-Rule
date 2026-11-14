class_name RegentsItemLevel extends RefCounted
## ITEM LEVELS AND PICKS, the client's twin of the server's (`genre/regents/mod.rs`: `item_xp_of`, `picks_of`,
## `item_level`, `usable_level`, `KitSeed::slot_refusal`, `pick_refusal`; Luke's B1-B6, B15, 2026-11-13,
## `ABILITIES_PREP.md` §7 step 2). An item's XP (`"x"`) and its picks (`"k"`: the first pick, the second, the ult) are
## its own row's `instance_data`, so they go wherever it goes. Its LEVEL is its XP on its kind's mastery curve; a holder
## uses it only up to their own mastery (B2). Its kit says which bar slot each skill goes to (`KitDef.skill_slots`) and
## the level each unlock opens at (`unlock_levels`). Presentation and prediction only: the server decides.

## The bar's four, by key slot: Q the base, E the option picked, R the ult picked, F.
const Q: int = 0
const E: int = 1
const R: int = 2
const F: int = 3


## The item's XP; 0 for none.
static func xp_of(instance_data: String) -> int:
	return int(RegentsGrade.data_of(instance_data).get("x", 0))


## The item's picks [first, second, ult], each an ability id or 0.
static func picks_of(instance_data: String) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	var k: Variant = RegentsGrade.data_of(instance_data).get("k", [])
	if k is Array:
		for i: int in mini(3, (k as Array).size()):
			out[i] = int((k as Array)[i])
	return out


## The level an item with `xp` is at, on kit `k`'s mastery curve.
static func level(k: KitDef, xp: int) -> int:
	return k.skill.rank_of(xp) if k != null and k.skill != null else 1


## The level it counts as in the hands of a holder of `mastery` (B2).
static func usable(item_level: int, mastery: int) -> int:
	return mini(item_level, maxi(mastery, 1))


## What a player may have on each bar slot (Q, E, R, F) with these picks: the ability, or null. The option on E is
## whichever pick took one; R the ult picked. Locked ones are here too (`slot_refusal` says why).
static func bar(k: KitDef, picks: Array[int]) -> Array[AbilityDef]:
	var out: Array[AbilityDef] = [null, null, null, null]
	if k == null:
		return out
	if k.skill_slots.is_empty():
		for i: int in mini(4, k.skills.size()):
			out[i] = k.skills[i]
		return out
	for i: int in k.skills.size():
		var a: AbilityDef = k.skills[i]
		match k.slot_of_skill(i):
			KitDef.SLOT_BASE:
				out[Q] = a
			KitDef.SLOT_F:
				out[F] = a
			KitDef.SLOT_OPTION:
				if picks[0] == a.id or picks[1] == a.id:
					out[E] = a
				elif picks[2] == a.id and not has_ults(k):
					out[R] = a   # the last pick takes an option while the kit has no ult (Luke, 2026-11-14)
			KitDef.SLOT_ULT:
				if picks[2] == a.id:
					out[R] = a
	return out


## Whether kit `k` has an ult of its own (a skill on `SLOT_ULT`). Until it does, its LAST PICK (R) takes the option E did
## not (Luke, 2026-11-14: "fix the R ability not being assigned"; the server's `has_ults`).
static func has_ults(k: KitDef) -> bool:
	return k != null and k.skill_slots.has(KitDef.SLOT_ULT)


## What pick `n` chooses from: the kit's options for the first two, its ults for the last (its options while it has none).
static func choices_for(k: KitDef, n: int) -> Array[AbilityDef]:
	return k.skills_in(KitDef.SLOT_ULT if n == 2 and has_ults(k) else KitDef.SLOT_OPTION)


## The item level bar slot `slot` opens at: Q and F the first unlock; E the first pick's; R the ult's.
static func opens_at(k: KitDef, slot: int) -> int:
	match slot:
		E:
			return k.unlock_level(1)
		R:
			return k.unlock_level(3)
	return k.unlock_level(0)


## Why a player may not use skill `a` of kit `k` with an item used at `usable_level` with `picks`; "" when they may
## (the server's `slot_refusal`).
static func slot_refusal(k: KitDef, a: AbilityDef, usable_level: int, picks: Array[int]) -> String:
	if k == null or a == null or k.skill_slots.is_empty():
		return ""
	var i: int = k.skills.find(a)
	if i < 0:
		return ""
	var counts: String = " (it counts as %d for you)" % usable_level
	match k.slot_of_skill(i):
		KitDef.SLOT_OPTION:
			for j: int in (2 if has_ults(k) else 3):
				if picks[j] == a.id:
					return "" if usable_level >= k.unlock_level(1 + j) else "opens at the weapon's level %d%s" % [k.unlock_level(1 + j), counts]
			return "not chosen: choose it at one of the weapon's picks"
		KitDef.SLOT_ULT:
			if picks[2] != a.id:
				return "not chosen: choose it as the weapon's last pick"
			return "" if usable_level >= k.unlock_level(3) else "opens at the weapon's level %d%s" % [k.unlock_level(3), counts]
	return "" if usable_level >= k.unlock_level(0) else "opens at the weapon's level %d%s" % [k.unlock_level(0), counts]


## Why `choice` may not be chosen at pick `n` (0, 1, 2 the ult) now; "" when it may (the server's `pick_refusal`).
static func pick_refusal(k: KitDef, n: int, choice: AbilityDef, usable_level: int, picks: Array[int]) -> String:
	if n < 0 or n > 2 or k == null:
		return "no such pick"
	if usable_level < k.unlock_level(1 + n):
		return "that pick opens at the weapon's level %d (it counts as %d for you)" % [k.unlock_level(1 + n), usable_level]
	var cid: int = choice.id if choice != null else 0
	if picks[n] == cid and cid != 0:
		return "already chosen"
	if picks[n] != 0:
		return "chosen already: change it instead (free once a week from level 20, else at a workbench)"
	var i: int = k.skills.find(choice)
	var want: int = KitDef.SLOT_ULT if n == 2 and has_ults(k) else KitDef.SLOT_OPTION
	if i < 0 or k.skill_slots.is_empty() or k.slot_of_skill(i) != want:
		return "that is not one of this weapon's last picks" if n == 2 else "that is not one of this weapon's picks"
	for j: int in 3:
		if j != n and picks[j] == cid:
			return "it is on the weapon already, at another pick"
	if n < 2:
		var other: int = k.skills.find(ContentLibrary.find(&"ability", picks[1 - n]) as AbilityDef) if picks[1 - n] > 0 else -1
		if other >= 0 and k.slot_of_skill(other) == KitDef.SLOT_OPTION:
			return "E holds one ability: this pick will take an upgrade, once there are any"
	return ""


## The picks open now and not yet chosen, each {n, options}: what the item asks its holder to choose.
static func open_picks(k: KitDef, usable_level: int, picks: Array[int]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if k == null or k.skill_slots.is_empty():
		return out
	for n: int in 3:
		if picks[n] != 0 or usable_level < k.unlock_level(1 + n):
			continue
		var options: Array[AbilityDef] = []
		for a: AbilityDef in choices_for(k, n):
			if pick_refusal(k, n, a, usable_level, picks).is_empty():
				options.append(a)
		if not options.is_empty():
			out.append({"n": n, "options": options})
	return out


## The item's level toward its next unlock: {level, usable, next (0: none left), frac 0..1 of the way from the last}.
static func progress(k: KitDef, xp: int, mastery: int) -> Dictionary:
	var lvl: int = level(k, xp)
	var use: int = usable(lvl, mastery)
	var next: int = 0
	var prev: int = 1
	for n: int in 4:
		var at: int = k.unlock_level(n)
		if at > lvl and (next == 0 or at < next):
			next = at
		if at <= lvl and at > prev:
			prev = at
	var frac: float = 1.0
	if next > 0 and k.skill != null:
		var from: int = RegentsAbilityBar._xp_for(k.skill, prev)
		var to: int = RegentsAbilityBar._xp_for(k.skill, next)
		frac = clampf(float(xp - from) / maxf(float(to - from), 1.0), 0.0, 1.0)
	return {"level": lvl, "usable": use, "next": next, "frac": frac}


# --- CHANGING A PICK (Luke's B13, 2026-11-13; the server's `change_pick`) -----------------------------------------
# One free change a week from the weapon's level `regents.respec_free_level`; past it the head's material at a workbench,
# doubling with each paid change, a doubling forgiven each `regents.respec_halve_days` without one. The item keeps when
# (`"f"`), how far the price has climbed (`"e"`) and when it last paid (`"c"`).

## Why pick `n`, chosen already, may not change to `choice`; "" when it may (the server's `change_refusal`).
static func change_refusal(k: KitDef, n: int, choice: AbilityDef, usable_level: int, picks: Array[int]) -> String:
	if n < 0 or n > 2:
		return "no such pick"
	if picks[n] == 0:
		return "nothing chosen there yet: choose it, no change needed"
	if choice != null and picks[n] == choice.id:
		return "already chosen"
	var cleared: Array[int] = picks.duplicate()
	cleared[n] = 0
	return pick_refusal(k, n, choice, usable_level, cleared)


## THE HEAD'S MATERIAL of a made item (the server's `head_material`): its recipe's input no part slot takes, and what
## that is made of first (an iron blade: Iron bar); null for an item no recipe makes.
static func head_material(it: ItemDef) -> ItemDef:
	if it == null:
		return null
	for r: RecipeDef in RecipeDef.all():
		if r.output != it:
			continue
		var parts: PackedInt32Array = r.pick_slots()
		for i: int in r.inputs.size():
			if not parts.has(i):
				var core: ItemDef = r.inputs[i]
				for x: RecipeDef in RecipeDef.all():
					if x.output == core and not x.inputs.is_empty():
						return x.inputs[0]
				return core
		return null
	return null


## WHAT CHANGING ONE PICK OF THIS ITEM COSTS NOW: {free: bool, item: ItemDef (the head's material), qty: int}. `level` is
## the item's own level; `now_s` the server's clock in seconds.
static func change_price(it: ItemDef, instance_data: String, item_level: int, now_s: int) -> Dictionary:
	var d: Dictionary = RegentsGrade.data_of(instance_data)
	var last_free: int = int(d.get("f", 0))
	var free_days: float = HotRules.number(&"regents.respec_free_days")
	var free: bool = item_level >= int(HotRules.number(&"regents.respec_free_level")) \
		and (last_free == 0 or float(now_s - last_free) >= maxf(free_days, 0.0) * 86400.0)
	var steps: int = int(d.get("e", 0))
	var halve: float = HotRules.number(&"regents.respec_halve_days")
	if halve <= 0.0:
		steps = 0
	elif steps > 0:
		steps = maxi(0, steps - floori(float(now_s - int(d.get("c", 0))) / (halve * 86400.0)))
	var max_steps: int = int(HotRules.number(&"regents.respec_max_steps"))
	var qty: int = int(HotRules.number(&"regents.respec_bars")) * (1 << mini(mini(steps, max_steps), 16))
	return {"free": free, "item": head_material(it), "qty": qty}
