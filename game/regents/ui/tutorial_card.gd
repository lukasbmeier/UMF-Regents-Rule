class_name RegentsTutorialCard extends PanelContainer
## THE TUTORIAL'S CARD (Luke, 2026-11-01: T3 "mostly play, a few words, and the first friendly NPC"): what the
## camp's guide says, on the left of the screen under the bag's line. Offered (a new character's): a line saying
## the guide is by the yard. E on the guide: their greeting, and the keys to begin (E again) or not now (N).
## Under way: the lesson now, its place in the run and the guide's few words for it. The tutorial component
## (`TutorialComponent`) is the state; this only shows it. SHOW, DON'T NAME: no role or move name here (the
## lessons' own words are checked by `LessonDef.validate`).

## How long the guide's offer stays up after E, unless taken.
const OFFER_S: float = 12.0

var tutorial: TutorialComponent = null
## The guide's offer is up (E on the guide), until this many msec.
var offer_until_ms: int = 0
var _title: Label
var _body: Label
var _keys: Label


func _init() -> void:
	name = "TutorialCard"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16.0
	offset_top = 78.0
	custom_minimum_size = Vector2(360, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06, 0.78)
	bg.border_color = Color(0.78, 0.62, 0.32, 0.9)
	bg.border_width_left = 3
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 12.0
	bg.content_margin_right = 12.0
	bg.content_margin_top = 8.0
	bg.content_margin_bottom = 8.0
	add_theme_stylebox_override(&"panel", bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override(&"font_size", 17)
	_title.add_theme_color_override(&"font_color", Color(0.95, 0.82, 0.5))
	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(336, 0)
	_body.add_theme_font_size_override(&"font_size", 15)
	_keys = Label.new()
	_keys.name = "Keys"
	_keys.add_theme_font_size_override(&"font_size", 13)
	_keys.modulate = Color(1, 1, 1, 0.65)
	for l: Label in [_title, _body, _keys]:
		box.add_child(l)
	visible = false


## E was pressed on the guide: their offer, or (under way) the lesson again.
func guide_pressed() -> void:
	offer_until_ms = Time.get_ticks_msec() + int(OFFER_S * 1000.0)
	refresh()


## Whether the guide's offer is up (the keys E and N answer it).
func offering() -> bool:
	return tutorial != null and tutorial.state != TutorialComponent.ON and Time.get_ticks_msec() < offer_until_ms


func _process(_delta: float) -> void:
	refresh()


## Show what the tutorial says now.
func refresh() -> void:
	var t: Dictionary = card_text(tutorial, offering())
	visible = not t.is_empty()
	if visible:
		_title.text = String(t["title"])
		_body.text = String(t["body"])
		_keys.text = String(t["keys"])


## What the card says for `tut` ({} when it shows nothing): its title, the guide's words, the keys. `offer` is
## the guide's offer up (E pressed on them). Static so a test can read it.
static func card_text(tut: TutorialComponent, offer: bool) -> Dictionary:
	if tut == null or tut.state == TutorialComponent.NONE:
		return {}
	if offer and tut.state != TutorialComponent.ON:
		var words: String = tut.greeting if tut.state == TutorialComponent.OFFERED else tut.again
		return {"title": tut.guide_name, "body": words, "keys": "E: show me     N: not now"}
	match tut.state:
		TutorialComponent.OFFERED:
			return {"title": tut.guide_name, "body": "By the training yard: I can show you the basics.", "keys": "Walk up and press E     N: not now"}
		TutorialComponent.ON:
			var l: LessonDef = tut.current()
			if l == null:
				return {}
			var at: Vector2i = tut.place()
			return {"title": "%s   %d / %d" % [l.display_name, at.x, at.y], "body": l.words, "keys": "N: set the lessons aside"}
	return {}
