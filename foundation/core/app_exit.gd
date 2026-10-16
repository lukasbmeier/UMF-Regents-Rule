class_name AppExit extends RefCounted
## QUITTING, one way for every process: stop every sound, give the audio server a moment to let
## them go, then quit (DECISIONS #151).
##
## A stopped sound is not released at once. The audio server fades it out and frees it on its own
## mixing thread, a pass or two later. A process that quit within milliseconds of the stop — a
## node freed as the tree comes down, a test suite tearing down its level — had that pass about
## half the time; the rest ended "2 ObjectDB instances were leaked … 1 resources still in use",
## the pond's looping ambience still held by the mixer. Godot already stops a player that leaves
## the tree: that stop is the one racing the exit. So this stops what is playing FIRST and quits
## AUDIO_RELEASE_SEC later, with nothing left for the mixer to let go. Measured on
## `--only=aim`: 4 leaked in 6 quitting at once, 0 in 6 with the wait.
##
## Every `quit` goes through here (tests/run_tests.sh lints for it). The window's close button too:
## `hold_close_request` turns off the engine's own immediate quit, and the scene's owner calls
## `quit` on NOTIFICATION_WM_CLOSE_REQUEST (foundation/boot.gd does, for every game scene).

## Two or three of the audio server's mixing passes (each ~10 ms), with room to spare.
const AUDIO_RELEASE_SEC: float = 0.1

static var _quitting: bool = false


## Stop every sound under `tree`, wait for the mixer to release them, then quit with `code`. A
## second request while one is under way (a button pressed twice, a close during the wait) is
## the same quit.
static func quit(tree: SceneTree, code: int = 0) -> void:
	if tree == null or _quitting:
		return
	_quitting = true
	stop_sounds(tree.root)
	# The content the game kept loaded (DECISIONS #224), let go so nothing is still held at exit.
	HoldDef.clear_cache()
	StatusDef.clear_cache()
	BodyDef.clear_cache()
	await tree.create_timer(AUDIO_RELEASE_SEC, true, false, true).timeout
	tree.quit(code)


## Every audio player under `root`, stopped. Returns how many were playing. The three kinds share
## no base class that has `stop()`, so each is named.
static func stop_sounds(root: Node) -> int:
	var playing: int = 0
	if root == null:
		return playing
	for n: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		var p: AudioStreamPlayer = n as AudioStreamPlayer
		playing += 1 if p.playing else 0
		p.stop()
	for n: Node in root.find_children("*", "AudioStreamPlayer2D", true, false):
		var p2: AudioStreamPlayer2D = n as AudioStreamPlayer2D
		playing += 1 if p2.playing else 0
		p2.stop()
	for n: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		var p3: AudioStreamPlayer3D = n as AudioStreamPlayer3D
		playing += 1 if p3.playing else 0
		p3.stop()
	return playing


## Take the window's close button off the engine's immediate quit, so the scene can quit through
## here instead (on NOTIFICATION_WM_CLOSE_REQUEST).
static func hold_close_request(tree: SceneTree) -> void:
	if tree != null:
		tree.set_auto_accept_quit(false)
