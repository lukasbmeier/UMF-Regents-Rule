class_name AccountPage extends PanelContainer
## YOUR ACCOUNT (template 1.0, DECISIONS #278), a page of the Escape menu. Says who you play as (signed
## in, or a guest on this machine), lists your account's characters with Play and New character (as many
## as the game's `foundation.characters_per_account`), shows a LINK CODE to type on another machine or
## takes one typed here, and signs in or out. What it shows comes from the server's rows for you alone
## (`account_login`, `account_character`, `link_code`: each player is sent only their own); every
## change is a reducer the server checks. Signing in and out is Boot's (`sign_in_requested`,
## `sign_out_requested`): they change who this machine connects as.
##
## A page of the Escape menu (`PauseMenu.open_page`): `open`, `close`, `closed`.

signal closed
signal sign_in_requested
signal sign_out_requested

## Whether this game has a sign-in to offer (Boot sets it: shared/game.json names a client id).
var can_sign_in: bool = false

var _who: Label = null
var _chars: VBoxContainer = null
var _new: Button = null
var _code_label: Label = null
var _show_code: Button = null
var _code_in: LineEdit = null
var _join: Button = null
var _sign: Button = null
var _said: Label = null


func _ready() -> void:
	visible = false
	name = "AccountPage"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Account"
	title.add_theme_font_size_override(&"font_size", 22)
	box.add_child(title)
	_who = Label.new()
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_who)
	_chars = VBoxContainer.new()
	box.add_child(_chars)
	_new = Button.new()
	_new.text = "New character"
	_new.pressed.connect(func() -> void: _call(&"new_character", [], [], "A new character"))
	box.add_child(_new)
	_code_label = Label.new()
	_code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_code_label)
	_show_code = Button.new()
	_show_code.text = "Play on another machine (show a link code)"
	_show_code.pressed.connect(_make_code)
	box.add_child(_show_code)
	var row := HBoxContainer.new()
	box.add_child(row)
	_code_in = LineEdit.new()
	_code_in.placeholder_text = "A link code from your signed-in machine"
	_code_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_in.max_length = 8
	row.add_child(_code_in)
	_join = Button.new()
	_join.text = "Join"
	_join.pressed.connect(func() -> void:
		_call(&"use_link_code", [_code_in.text.strip_edges().to_upper()], ["string"], "Joined the account"))
	row.add_child(_join)
	_said = Label.new()
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_said)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	_sign = Button.new()
	_sign.pressed.connect(func() -> void:
		if is_signed_in():
			sign_out_requested.emit()
		else:
			sign_in_requested.emit())
	buttons.add_child(_sign)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(close)
	buttons.add_child(back)


func open() -> void:
	visible = true
	_said.text = ""
	refresh()


func close() -> void:
	visible = false
	closed.emit()


## Signed in (or linked): this identity is one of an account's ways in.
func is_signed_in() -> bool:
	return my_account() >= 0


## This identity's account, -1 for a guest. The server sends each player their own row only.
func my_account() -> int:
	var rows: Array = SpaceTimeSync.find_rows(&"account_login", func(_r: RefCounted) -> bool: return true)
	return int((rows[0] as RefCounted).get(&"account_id")) if not rows.is_empty() else -1


## Redraw from the rows as they are now.
func refresh() -> void:
	var acc: int = my_account()
	var me: int = EntityRegistry.local_entity_id
	for c: Node in _chars.get_children():
		c.queue_free()
	var chars: Array = SpaceTimeSync.find_rows(&"account_character", func(_r: RefCounted) -> bool: return true)
	chars.sort_custom(func(a: RefCounted, b: RefCounted) -> bool: return int(a.get(&"entity_id")) < int(b.get(&"entity_id")))
	_who.text = ("Signed in. Your characters are kept on the server: sign in the same way on any machine to play them."
		if acc >= 0 else "Playing as a guest: this character belongs to this machine.%s"
			% (" Sign in to keep it on any machine." if can_sign_in else ""))
	for c: RefCounted in chars:
		var line := HBoxContainer.new()
		var name_label := Label.new()
		var eid: int = int(c.get(&"entity_id"))
		var nm: String = str(c.get(&"name"))
		name_label.text = (nm if not nm.is_empty() else "Character %d" % eid) + ("  (playing)" if eid == me else "")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		if eid != me:
			var play := Button.new()
			play.text = "Play"
			play.pressed.connect(func() -> void: _call(&"play_character", [eid], ["u64"], "Playing %s" % nm))
			line.add_child(play)
		_chars.add_child(line)
	var allowed: int = maxi(1, int(HotRules.number(&"foundation.characters_per_account")))
	_new.visible = acc >= 0 and chars.size() < allowed
	_show_code.visible = acc >= 0
	_code_in.get_parent().visible = acc < 0
	var codes: Array = SpaceTimeSync.find_rows(&"link_code", func(_r: RefCounted) -> bool: return true)
	_code_label.text = ("Your link code: %s. Type it on the other machine (Account, Join) within %d minutes."
		% [str((codes[0] as RefCounted).get(&"code")), int(HotRules.number(&"foundation.link_code_s") / 60.0)]) \
		if acc >= 0 and not codes.is_empty() else ""
	_sign.text = "Sign out" if acc >= 0 else "Sign in"
	_sign.visible = acc >= 0 or can_sign_in


func _make_code() -> void:
	await _call(&"make_link_code", [SignIn.new_link_code()], ["string"], "")


func _call(reducer: StringName, args: Array, types: Array[String], done: String) -> void:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(reducer, args, types)
	if req.outcome == ReducerRequest.Outcome.PENDING:
		await req.settled
	if req.outcome == ReducerRequest.Outcome.OK:
		_said.text = done
	else:
		_said.text = req.error_message if not req.error_message.is_empty() else "That did not work."
	# The rows it changed arrive just after the call settles.
	await get_tree().create_timer(0.3).timeout
	if visible:
		refresh()
