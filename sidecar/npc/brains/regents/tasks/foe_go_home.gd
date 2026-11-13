@tool
extends RegentsFoeTask
## Past FoeDef.leash_m from home it walks back, deaf to everyone until it is there (RegentsFoeBrain.go_home).


func _generate_name() -> String:
	return "Past its leash: walks home"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.go_home(me(), world()))
