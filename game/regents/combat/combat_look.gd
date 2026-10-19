class_name CombatLook extends SpaceTimeComponent
## COMBAT, SHOWN, on every player's character (presentation only): the weapon they wield is in the hand
## (`ItemDef.held_scene`), except while they work a skill (the tool is then; `SkillingLook`). It reads the
## combat component's `weapon`, from the `wielded` row everyone has.

var weapon_held: HeldItem = null
var weapon_scene: PackedScene = null
var _combat: CombatComponent = null
var _skilling_look: SkillingLook = null
var _driver: AnimationDriverComponent = null


func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null:
		return
	_combat = ent.find_component(CombatComponent) as CombatComponent
	_skilling_look = ent.find_component(SkillingLook) as SkillingLook
	_driver = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent


func _process(_delta: float) -> void:
	if _combat == null or not is_bound():
		return
	var working: bool = _skilling_look != null and _skilling_look.working()
	var want: PackedScene = _combat.weapon.held_scene if _combat.weapon != null and not working else null
	if want != weapon_scene:
		if weapon_held != null:
			weapon_held.queue_free()
			weapon_held = null
		weapon_scene = want
	if weapon_held == null and weapon_scene != null:
		var skel: Skeleton3D = SkillingLook.skeleton_of(entity)
		if skel != null:
			weapon_held = HeldItem.attach(skel, weapon_scene)
			if weapon_held != null:
				weapon_held.driver = _driver
