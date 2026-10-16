@tool
class_name BodyForces extends Resource
## WHAT PUSHES A BODY IN FLIGHT besides gravity, bounce and its damping (FOUNDATION_SYSTEMS milestone
## 13, DECISIONS #246): a disc's lift, turn and fade, a balloon's float, a boomerang's curve. Linked
## from a `BodyDef` (`forces`); a genre extends this with its own exports (a disc's flight numbers) and
## its own `apply`.
##
## THE SAME FUNCTION FLIES IT EVERYWHERE: the world's referee (the authority) and the thrower's game
## (its prediction) both call `apply` on their own `FlyingBody` every physics frame, with the same
## numbers. So it may read only what both have: the body's state (`state`), its def, and the frame's
## length. Never the clock, never a random number, never another node: what it reads that the other
## side does not have is a correction on every throw.

## The forces this frame: add them to `state` (`apply_central_force`, `apply_torque`,
## `apply_force`). `def` is the body's; `dt` the physics frame's length. The default adds none.
func apply(_state: PhysicsDirectBodyState3D, _def: BodyDef, _dt: float) -> void:
	pass
