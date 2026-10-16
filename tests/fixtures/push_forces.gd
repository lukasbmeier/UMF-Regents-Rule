@tool
extends BodyForces
## The `bodies` suite's forces (DECISIONS #246): a steady push along `push`, newtons, every frame.

@export var push: Vector3 = Vector3(2.0, 0.0, 0.0)


func apply(state: PhysicsDirectBodyState3D, _def: BodyDef, _dt: float) -> void:
	state.apply_central_force(push)
