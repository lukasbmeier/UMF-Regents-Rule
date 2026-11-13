@tool
extends RegentsFoeTask
## In reach with a turn: it stands, faces its target and swings its kit's string, the last its finisher, then rests FoeDef.rest_ms (RegentsFoeBrain.swing).


func _generate_name() -> String:
	return "In reach, its turn: swings its string"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.swing())
