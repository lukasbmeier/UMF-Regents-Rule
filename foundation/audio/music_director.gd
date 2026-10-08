class_name MusicDirector extends Node
## MUSIC BY THE ROUND'S PHASE (DECISIONS #167). Put one in a game's scene and give it a track per
## phase; it crossfades to the right one whenever the local player's session changes phase, and to
## `default_track` for any phase it has no track for and while not in a game (the connect screen).
##
## Everything it plays goes to the Music bus, so the player's Music volume (Settings) is its
## volume. It decides nothing about the game: it only reads `SignalBus.session_phase_changed`.

## Phase number -> track (foundation phases: 0 lobby, 1 playing, 2 results, 3 shop; a genre's own
## from PHASE_FOUNDATION_MAX + 1).
@export var tracks: Dictionary[int, AudioStream] = {}
## Any phase not in `tracks`, and before a game (the connect screen). Empty: silence.
@export var default_track: AudioStream
## How long one track takes to fade into the next.
@export var fade_sec: float = 2.5
## The music's own level under the bus: background, below the sound effects.
@export var volume_db: float = -8.0

const SILENT_DB: float = -60.0

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _current: AudioStream = null
var _tween: Tween = null


func _ready() -> void:
	for i: int in range(2):
		var p := AudioStreamPlayer.new()
		p.name = "Track%d" % i
		p.bus = Settings.BUS_MUSIC
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	SignalBus.session_phase_changed.connect(func(_sid: int, _old: int, phase: int, _ends: int) -> void:
		play(track_for(phase)))
	SpaceTimeSync.connection_state_changed.connect(func(s: SpaceTimeSync.ConnectionState) -> void:
		if s == SpaceTimeSync.ConnectionState.DISCONNECTED:
			play(default_track))
	play(default_track)


## The track for `phase`.
func track_for(phase: int) -> AudioStream:
	return tracks.get(phase, default_track)


## What is playing (or fading in) now; null for silence.
func current() -> AudioStream:
	return _current


## Crossfade to `stream` (null: fade to silence). The same stream again changes nothing.
func play(stream: AudioStream) -> void:
	if stream == _current:
		return
	_current = stream
	var out: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var into: AudioStreamPlayer = _players[_active]
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(out, ^"volume_db", SILENT_DB, fade_sec)
	_tween.chain().tween_callback(out.stop)
	if stream != null:
		into.stream = stream
		into.volume_db = SILENT_DB
		into.play()
		_tween.parallel().tween_property(into, ^"volume_db", volume_db, fade_sec)
