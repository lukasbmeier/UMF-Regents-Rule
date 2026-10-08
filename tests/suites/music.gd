extends "res://tests/suite_base.gd"
## The `music` suite (tests/test_runner.gd runs it; `-- --only=music` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_music_tests()



## MUSIC BY PHASE (DECISIONS #167): the director plays the phase's track, the default for any
## other phase and out of a game, on the Music bus; and both fishing scenes ship one with a track
## for the round itself, which loops.
func _run_music_tests() -> void:
	print("== music ==")
	var playing: AudioStream = load("res://game/fishing/music/lakeside.wav") as AudioStream
	var between: AudioStream = load("res://game/fishing/music/between_rounds.wav") as AudioStream
	_check(playing != null and between != null, "the generated tracks import")
	_check((playing as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
		and (between as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, "and loop")
	var d := MusicDirector.new()
	d.tracks = {1: playing}
	d.default_track = between
	d.fade_sec = 0.05
	get_tree().root.add_child(d)
	_check(d.current() == between, "out of a game it plays the default track")
	SignalBus.session_phase_changed.emit(1, 0, 1, 0)
	_check(d.current() == playing, "the round's phase plays its own track")
	await get_tree().create_timer(0.2).timeout
	var sounding: Array[AudioStreamPlayer] = []
	for c: Node in d.get_children():
		var p: AudioStreamPlayer = c as AudioStreamPlayer
		if p != null and p.playing:
			sounding.append(p)
	_check(sounding.size() == 1 and sounding[0].stream == playing and sounding[0].bus == Settings.BUS_MUSIC
		and is_equal_approx(sounding[0].volume_db, d.volume_db),
		"after the fade one track sounds, on the Music bus, at the music's level")
	SignalBus.session_phase_changed.emit(1, 1, 3, 0)
	_check(d.current() == between, "a phase with no track of its own plays the default")
	d.queue_free()
	for scene: String in ["res://game/fishing/fishing_world.tscn"]:
		var state: SceneState = (load(scene) as PackedScene).get_state()
		var found: bool = false
		for i: int in range(state.get_node_count()):
			for k: int in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, k) == &"tracks":
					var t: Dictionary = state.get_node_property_value(i, k)
					found = t.get(1) == playing
		_check(found, "%s has music for the round" % scene.get_file())
	var fishing_mod: GenreModule = load("res://game/fishing/genre.tres") as GenreModule
	_check(fishing_mod.scenes.has(load("res://game/fishing/fishing_world.tscn")),
		"and the fishing genre puts it in the game")
