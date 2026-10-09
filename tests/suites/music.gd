extends "res://tests/suite_base.gd"
## The `music` suite (tests/test_runner.gd runs it; `-- --only=music` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_music_tests()



## MUSIC BY PHASE (DECISIONS #167): the director plays the phase's track, the default for any
## other phase and out of a game, on the Music bus. Tracks are made here; a game's suites check the
## scenes and music it ships (fishing's: fishing_music).
func _run_music_tests() -> void:
	print("== music ==")
	var playing: AudioStream = _tone(440.0)
	var between: AudioStream = _tone(330.0)
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


## A second of a looping sine, as a track.
func _tone(hz: float) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(22050 * 2)
	for i: int in range(22050):
		data.encode_s16(i * 2, int(sin(TAU * hz * float(i) / 22050.0) * 8000.0))
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = 22050
	return w
