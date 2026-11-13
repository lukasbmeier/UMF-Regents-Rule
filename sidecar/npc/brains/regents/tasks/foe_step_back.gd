@tool
extends RegentsFoeTask
## Its target within FoeDef.back_within_m: it walks back_m away, facing them, at most once every back_every_ms, never past its leash (RegentsFoeBrain.step_back).


func _generate_name() -> String:
	return "They are close: one step back"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.step_back(me(), world()))
