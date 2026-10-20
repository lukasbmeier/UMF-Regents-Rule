@tool
class_name ArrowFlight extends BodyForces
## AN ARROW'S FLIGHT (owner, 2026-10-20: a real arrow, it arcs): its fletching turns it into the wind, so
## it points the way it flies: a torque turning its nose (its -Z) toward its velocity, damped so it does
## not wobble. Run by the referee and the shooter's game alike (`BodyForces`): it reads only the body.

## How hard it turns into its flight, and how its turning dies away.
@export var weathervane: float = 0.02
@export var spin_damp: float = 0.004


func apply(state: PhysicsDirectBodyState3D, _def: BodyDef, _dt: float) -> void:
	var v: Vector3 = state.linear_velocity
	if v.length_squared() < 1.0:
		return
	var nose: Vector3 = -state.transform.basis.z
	state.apply_torque(nose.cross(v.normalized()) * weathervane * v.length() - state.angular_velocity * spin_damp)
