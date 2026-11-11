extends Node3D
## A MODEL HELD IN ONE MOMENT OF ONE OF ITS CLIPS (skinning, 2026-11-09: a deer's carcass is its Death clip's last frame):
## the first `AnimationPlayer` under this node plays `clip` and stops `at` seconds in (negative: from the end). Presentation
## only. Used as a node's look (`NodeDef.models`), so a kill's carcass lies as the creature fell.

## The clip to hold, and where in it (seconds; negative counts back from its end).
@export var clip: StringName = &"Death"
@export var at: float = -0.001


func _ready() -> void:
	var players: Array[Node] = find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0] as AnimationPlayer
	if not ap.has_animation(clip):
		push_warning("posed_clip: %s has no clip %s" % [name, clip])
		return
	var length: float = ap.get_animation(clip).length
	ap.play(clip)
	ap.seek(clampf(at if at >= 0.0 else length + at, 0.0, length), true)
	ap.pause()
