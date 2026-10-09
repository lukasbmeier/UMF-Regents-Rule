extends "res://tests/suite_base.gd"
## FISHING'S TEST GROUND: what its suites (`game/fishing/tests/suites/`) share on top of the
## foundation's base: the angler, the rival, the rod, the lakeside. The runner finds the suites
## because shared/game.json lists fishing; the template has none of this.


const FISHER_SET: String = "res://game/anim/fisher.tres"
const FISHING_NET_CONFIG: String = "res://game/fishing/fishing_net_config.tres"
const FISHER_DEF: String = "res://game/fishing/fisher_definition.tres"

## Every model the fishing game dresses an entity in: each angler look and the rival's.
func _shipped_looks() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	var fisher: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	var rival: EntityDefinition = load("res://game/fishing/rival_definition.tres") as EntityDefinition
	if fisher != null:
		out.append_array(fisher.visual_variants)
	if rival != null and rival.visual_for(0) != null:
		out.append(rival.visual_for(0))
	return out

const LAKESIDE_SCENE: String = "res://game/world/lakeside.tscn"

## The grips of DECISIONS #147 (clear of every leg through the idle), and one that clears a man's
## leg in the idle's first frame and sits inside a woman's further in (Luke's first edit): fishing
## position and turn, carrying position and turn.
const GRIP_147: Array[Vector3] = [Vector3(-0.03, 0.11, -0.04), Vector3(95.0, 0.0, 0.0),
	Vector3(-0.01, 0.11, -0.04), Vector3(0.0, -90.0, -95.0)]


## A grip that puts the rod's ROOT at `pos`, turned `rot`, written as where its HOLD goes.
func _root_entry(anim: StringName, pos: Vector3, rot: Vector3, steady: bool) -> GripEntry:
	var rod: Node3D = (load("res://game/fishing/fishing_rod.tscn") as PackedScene).instantiate() as Node3D
	var hold: Transform3D = GripFit.hold_of(rod)
	rod.free()
	var root := Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)),
		EULER_ORDER_YXZ), pos)
	var at: Transform3D = root * hold
	var e: Vector3 = at.basis.get_euler(EULER_ORDER_YXZ)
	return _grip_entry(anim, at.origin, Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)), steady)
