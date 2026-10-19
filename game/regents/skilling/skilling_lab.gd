extends Control
## THE SKILLING LAB (open `skilling_lab.tscn`, F6): play any skill's minigame on its own, no server, to
## feel and tune it. A button per node and per recipe that has a round (game/regents/content/node/,
## recipe/: edit its `minigame` in the Inspector and play again); Space or Enter starts a round on a new
## seed (or the one on show); 1-9 pick a button. The end screen shows the score and whether the server's
## replay of your inputs agrees with what you saw.

## What each button plays: the content that names the round, and the round's params.
var choices: Array[ContentDef] = []
var choice_index: int = 0
var buttons: Array[Button] = []
var game: SkillMinigame = null
var _info: Label
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame != null:
			choices.append(n)
	for r: RecipeDef in RecipeDef.all():
		if r.minigame != null:
			choices.append(r)
	var bar: HFlowContainer = HFlowContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 64.0
	bar.offset_left = 16.0
	bar.offset_right = -16.0
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in choices.size():
		var b: Button = Button.new()
		b.text = "%d  %s" % [i + 1, choices[i].display_name]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE   # Space starts a round; it must not press a button
		b.custom_minimum_size = Vector2(120, 34)
		b.pressed.connect(pick.bind(i))
		bar.add_child(b)
		buttons.append(b)
	add_child(bar)
	_info = Label.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_info.offset_top = -34.0
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_info)
	if not choices.is_empty():
		pick(0)


## The params of the round on show.
func params() -> Resource:
	var c: ContentDef = choices[choice_index]
	return (c as NodeDef).minigame if c is NodeDef else (c as RecipeDef).minigame


## Button `i`'s round on show, ready to play. Not mid-round.
func pick(i: int) -> void:
	if (game != null and game.state == SkillMinigame.State.PLAYING) or i < 0 or i >= choices.size():
		return
	choice_index = i
	for j: int in buttons.size():
		buttons[j].set_pressed_no_signal(j == i)   # no_signal skips the group's own unpressing
	var p: Resource = params()
	if game == null or SkillMinigames.kind_of(game.params) != SkillMinigames.kind_of(p):
		if game != null:
			game.queue_free()
		game = SkillMinigames.make_ui(p)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(game)
		move_child(game, 0)
		game.round_finished.connect(func(_live: Dictionary, _replayed: Dictionary) -> void: _show_info())
	game.preview(_rng.randi(), p)
	_show_info()


func _show_info() -> void:
	var playing: bool = game != null and game.state == SkillMinigame.State.PLAYING
	for b: Button in buttons:
		b.disabled = playing
	_info.text = "%s   seed %d" % ["Playing: " + game.how_to() if playing else "Space / Enter: new round   buttons or 1-9: pick the round",
		game.seed_value if game != null else 0]


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or game == null or game.state == SkillMinigame.State.PLAYING:
		return
	if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		# The round on show (a fresh pick); after a round, a new one.
		game.begin(game.seed_value if game.state == SkillMinigame.State.READY else _rng.randi(), params())
		_show_info()
		get_viewport().set_input_as_handled()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_9:
		pick(k.keycode - KEY_1)
	elif k.keycode >= KEY_KP_1 and k.keycode <= KEY_KP_9:
		pick(k.keycode - KEY_KP_1)
