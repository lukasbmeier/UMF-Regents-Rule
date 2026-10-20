class_name RegentsSkillsWindow extends UiWindow
## THE SKILLS (K, owner 2026-10-20: dedicated UI): each skill, its rank, and a bar to the next.

var skilling: SkillingComponent = null
var _rows: VBoxContainer = null


func _init() -> void:
	super()
	title = "Skills"
	place = Place.LEFT
	size_min = Vector2(340, 300)
	_rows = VBoxContainer.new()
	content.add_child(_rows)
	opened.connect(refresh)


func refresh() -> void:
	if not visible or skilling == null:
		return
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for s: SkillDef in SkillDef.all():
		var xp: int = int(skilling.xp.get(s.id, 0))
		var p: Vector2i = s.progress(xp)
		var head := HBoxContainer.new()
		head.name = "Skill_%s" % s.key
		var n := UiKit.line(s.display_name)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_color_override(&"font_color", s.color)
		head.add_child(n)
		head.add_child(UiKit.line("rank %d" % s.rank_of(xp), &"accent"))
		_rows.add_child(head)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.max_value = maxi(p.y, 1)
		bar.value = p.x if p.y > 0 else 1
		bar.tooltip_text = "%d / %d XP to the next rank" % [p.x, p.y] if p.y > 0 else "The highest rank"
		_rows.add_child(bar)
	fit.call_deferred()
