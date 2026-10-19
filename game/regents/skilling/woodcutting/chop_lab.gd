extends Control
## THE WOODCUTTING LAB (open `chop_lab.tscn`, F6): play the branch-dodge minigame on its own, no
## server, to feel and tune it. Space or Enter starts a round on a new seed; the Tree / Oak / Yew
## buttons at the top (or 1, 2, 3...) pick the tree between rounds, and its trunk shows at once: every
## tree in the game's content (`game/regents/content/tree/`, lowest tier first; edit a tree's `chop` in
## the Inspector and play again). The end screen shows the score and whether the server's replay of
## your inputs agrees with what you saw.

## Every tree, lowest tier first.
var trees: Array[TreeDef] = []

var game: ChopMinigame
var tree_index: int = 0
## One per tree, in `trees`' order.
var tree_buttons: Array[Button] = []
var _info: Label
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	trees = TreeDef.all_by_tier()
	game = ChopMinigame.new()
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(game)
	game.round_finished.connect(func(_live: Dictionary, _replayed: Dictionary) -> void: _show_info())
	var bar: HBoxContainer = HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.offset_top = 64.0
	bar.add_theme_constant_override("separation", 8)
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in trees.size():
		var b: Button = Button.new()
		b.text = "%d  %s" % [i + 1, trees[i].display_name]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE   # Space starts a round; it must not press a button
		b.custom_minimum_size = Vector2(110, 36)
		b.pressed.connect(pick_tree.bind(i))
		bar.add_child(b)
		tree_buttons.append(b)
	add_child(bar)
	bar.position.x = -bar.get_combined_minimum_size().x * 0.5
	_info = Label.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_info.offset_top = -34.0
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_info)
	pick_tree(0)


func _tree() -> ChopParams:
	return trees[tree_index].chop


## Tree `i` for the next round, its trunk shown now. Not mid-round.
func pick_tree(i: int) -> void:
	if game.state == ChopMinigame.State.PLAYING or i < 0 or i >= trees.size():
		return
	tree_index = i
	for j: int in tree_buttons.size():
		tree_buttons[j].set_pressed_no_signal(j == i)   # no_signal skips the group's own unpressing
	game.preview(_rng.randi(), _tree())
	_show_info()


func _show_info() -> void:
	var t: ChopParams = _tree()
	var playing: bool = game.state == ChopMinigame.State.PLAYING
	for b: Button in tree_buttons:
		b.disabled = playing
	_info.text = "%s   branches %d%%, swing %d ms, target %d logs   seed %d" % [
		"Chop: A / D, arrows, or click a side" if playing else "Space / Enter: new round   Tree / Oak / Yew or 1-3: pick the tree",
		t.branch_permille / 10, t.swing_ms, t.target_chops, game.seed_value]


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or game.state == ChopMinigame.State.PLAYING:
		return
	if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		# The trunk on show (a fresh pick); after a round, a new one.
		game.begin(game.seed_value if game.state == ChopMinigame.State.READY else _rng.randi(), _tree())
		_show_info()
	elif k.keycode >= KEY_1 and k.keycode < KEY_1 + trees.size():
		pick_tree(k.keycode - KEY_1)
	elif k.keycode >= KEY_KP_1 and k.keycode < KEY_KP_1 + trees.size():
		pick_tree(k.keycode - KEY_KP_1)
