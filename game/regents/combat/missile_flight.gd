@tool
class_name MissileFlight extends BodyForces
## A SHOT ENDS WHERE IT FIRST TOUCHES (Luke, 2026-11-12: a bolt at a moving target "gets redeflected in a random
## direction"). The referee says what a shot hit a moment before it touches, and the server takes the shot away when
## that word reaches it; in between the shot is still a body, and one that met its target off its middle (a target
## on the move is led, never met dead on) kept its sideways speed and skidded off for those frames, or was thrown by
## the target's own body moving into it. So: touching anything, a shot stops dead where it is, and stays there until
## the server takes it. A bolt's, a fireball's and an arrow's `BodyDef.forces` (an arrow's is `ArrowFlight`, which
## extends this).
##
## Reads only the body's own state (`BodyForces`' rule).


func apply(state: PhysicsDirectBodyState3D, _def: BodyDef, _dt: float) -> void:
	stop_on_touch(state)


## True when it touches something this frame, and has been stopped.
static func stop_on_touch(state: PhysicsDirectBodyState3D) -> bool:
	if state.get_contact_count() == 0:
		return false
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	return true
