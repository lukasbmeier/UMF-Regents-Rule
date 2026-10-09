@tool
class_name AnimationClipRef extends Resource
## One clip, addressed the way the AnimationTree addresses it, plus how to blend into it.
##
## `anim_name` is the name INSIDE the mixer: `Idle` for the default library, `extra/Fish_Cast`
## for a second one (see `AnimationSet.libraries`). Nothing else in the project spells animation
## names — a genre swapping libraries edits this resource and no code.

## The mixer's name for the clip, including the library prefix if it is not the default one.
@export var anim_name: StringName = &""
## Only meaningful for clips the driver plays as one-shots; looping locomotion clips carry their
## loop mode from the import (Godot's importers set it from a `_Loop` suffix).
@export var loop: bool = false
## Seconds to cross-fade when this clip is entered as a state or fired as a one-shot.
@export var blend_time: float = 0.15
## Playback rate. Raise it when a clip authored for a slower character has to keep up.
@export var speed_scale: float = 1.0


static func make(p_name: StringName, p_loop: bool = false, p_blend: float = 0.15,
		p_speed: float = 1.0) -> AnimationClipRef:
	var c := AnimationClipRef.new()
	c.anim_name = p_name
	c.loop = p_loop
	c.blend_time = p_blend
	c.speed_scale = p_speed
	return c


func is_valid() -> bool:
	return not String(anim_name).is_empty()
