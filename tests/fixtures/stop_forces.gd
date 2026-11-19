@tool
extends BodyForces
## The `bodies` suite's stop-on-touch forces (DECISIONS #317): touching anything, it stops dead, as a
## genre's shot does (Regent's Rule's `MissileFlight.stop_on_touch`). A body flown with these must still
## say what it hit: `FlyingBody` reads its contacts before its forces run.


func apply(state: PhysicsDirectBodyState3D, _def: BodyDef, _dt: float) -> void:
	if state.get_contact_count() > 0:
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
