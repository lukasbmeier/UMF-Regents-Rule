extends Control
## THE WOODCUTTING LAB (open `chop_lab.tscn`, F6): play the branch-dodge minigame on its own, no
## server, to feel and tune it. Space or Enter starts a round on a new seed; 1, 2, 3 pick the tree
## (`trees/`: edit their numbers in the Inspector and play again). The end screen shows the score and
## whether the server's replay of your inputs agrees with what you saw.

const TREES: Array[String] = [
	"res://game/regents/skilling/woodcutting/trees/tree.tres",
	"res://game/regents/skilling/woodcutting/trees/oak.tres",
	"res://game/regents/skilling/woodcutting/trees/yew.tres",
]

var game: ChopMinigame
var tree_index: int = 0
var _info: Label
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	game = ChopMinigame.new()
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(game)
	_info = Label.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_info.offset_top = -34.0
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_info)
	game.tree = _tree()
	_show_info()


func _tree() -> ChopParams:
	return load(TREES[tree_index]) as ChopParams


func _show_info() -> void:
	var t: ChopParams = _tree()
	_info.text = "Tree: %s (1-3 to change)   Space / Enter: new round   branches %d%%, swing %d ms, target %d logs   seed %d" % [
		t.display_name, t.branch_permille / 10, t.swing_ms, t.target_chops, game.seed_value]


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or game.state == ChopMinigame.State.PLAYING:
		return
	if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		game.begin(_rng.randi(), _tree())
		_show_info()
	elif k.keycode >= KEY_1 and k.keycode < KEY_1 + TREES.size():
		tree_index = k.keycode - KEY_1
		game.tree = _tree()
		_show_info()
		game.queue_redraw()
