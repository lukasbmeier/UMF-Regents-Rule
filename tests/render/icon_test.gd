extends Node
## AN ICON FROM A MODEL, for real (DECISIONS #271): a long thing (a stand-in sword: a blade and a guard)
## drawn by `IconRender` is a square picture, transparent at its corners, the model filling it along the
## diagonal (its longest side), lit (more than one shade of its colour). Needs a renderer
## (tests/render_test.sh opens a window). Prints `RENDER PASS`/`RENDER FAIL` and exits 1 on any failure.

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var sword := Node3D.new()
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 1.0, 0.03)
	blade.mesh = bm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.8, 0.3, 0.25)
	blade.material_override = steel
	sword.add_child(blade)
	blade.owner = sword
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.3, 0.05, 0.05)
	guard.mesh = gm
	guard.position = Vector3(0, -0.3, 0)
	guard.material_override = steel
	sword.add_child(guard)
	guard.owner = sword
	var scene := PackedScene.new()
	scene.pack(sword)
	sword.free()
	var img: Image = await IconRender.render(scene, self)
	_expect(img != null and img.get_size() == Vector2i(IconRender.SIZE, IconRender.SIZE),
		"a square of %d (%s)" % [IconRender.SIZE, img.get_size() if img != null else "nothing"])
	if img == null:
		_finish()
		return
	var s: int = img.get_width()
	var corners: Array[Color] = [img.get_pixel(1, 1), img.get_pixel(s - 2, 1), img.get_pixel(1, s - 2), img.get_pixel(s - 2, s - 2)]
	var clear: int = corners.filter(func(c: Color) -> bool: return c.a < 0.05).size()
	_expect(clear >= 2, "transparent where the model is not (%d of 4 corners)" % clear)
	var lo := Vector2i(s, s)
	var hi := Vector2i(-1, -1)
	var shades: Dictionary = {}
	for y: int in s:
		for x: int in s:
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
				shades[Color(snappedf(c.r, 0.02), snappedf(c.g, 0.02), snappedf(c.b, 0.02)).to_html(false)] = true
	var span := Vector2(hi - lo)
	_expect(span.x > s * 0.6 and span.y > s * 0.6, "the model along the diagonal, filling it (%s of %d)" % [span, s])
	_expect(shades.size() > 4, "lit: %d shades of its colour" % shades.size())
	img.save_png("user://icon_test.png")
	_finish()


func _finish() -> void:
	print("RENDER %s: %d failed" % ["PASS" if _failures == 0 else "FAIL", _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print("RENDER %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failures += 1
