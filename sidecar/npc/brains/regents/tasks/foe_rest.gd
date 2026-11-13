@tool
extends RegentsFoeTask
## It looks for someone to fight (the one it has, the nearest it sees in front within FoeDef.notice_m or hears within hear_m, who hit it, its pack's); with nobody it rests round its home, wandering FoeDef.wander_m. With somebody, the tasks BELOW this one fight them: never put a fighting task above it (RegentsFoeBrain.rest).


func _generate_name() -> String:
	return "Nobody to fight: rests at home"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.rest(me(), world()))
