@tool
extends BrainTask
## The `bots` suite's tree task (DECISIONS #245): one step of a brain's tree that writes what it was
## given onto the brain (`state`), and succeeds or fails as set.

@export var succeed: bool = true


func _tick(delta: float) -> Status:
	var b: NpcBrain = brain()
	if b == null:
		return FAILURE
	b.state = StringName("step me=%s world=%s dt=%.2f" % [me() != null, world() != null, delta])
	return done(succeed)
