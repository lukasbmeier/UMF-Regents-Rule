class_name StandBrain extends NpcBrain
## Stands where it is and does nothing: a bot whose genre has given it no brain yet, or a test's.
## Made by name through its path (`NpcBrainComponent.make_brain(&"stand")`), as a genre's brains are.
##
## SERVER-ONLY (hard rule 7b).


func _init(_seed_value: int = 0) -> void:
	state = &"standing"
