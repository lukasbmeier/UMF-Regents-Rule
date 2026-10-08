extends Node
## THE GRIP PICTURES (DECISIONS #157). The held-item preview's Save Pictures draws every animation
## (its first frame, and where the item comes closest to the body) into one sheet for a person to
## check. It needs a renderer, so it is checked here (`tests/render_test.sh`), not headless: the
## sheet is the right size for the set's animations, and each picture has people in it, not just
## the background.
##
## Prints `RENDER PASS`/`RENDER FAIL` per check and exits 1 on any failure. Writes to user://, never
## over the grip_pictures/ sheet a person may be looking at.

const PREVIEW: String = "res://game/fishing/rod_grip_preview.tscn"
const OUT: String = "user://grip_pictures_test.png"

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var prev: Node3D = (load(PREVIEW) as PackedScene).instantiate() as Node3D
	add_child(prev)
	for i: int in range(6):
		await get_tree().process_frame
	var grip: ItemGrip = prev.get("grip") as ItemGrip
	var before: String = _grip_text(grip)
	var written: String = await prev.call("save_pictures_now", OUT)
	var sheet: Image = Image.load_from_file(written) if not written.is_empty() else null
	var definition: EntityDefinition = prev.get("definition") as EntityDefinition
	# Two per animation, and two of it put away when it can be (DECISIONS #158).
	var shots: int = definition.animation_set.clips.size() * 2 + (2 if grip.stows() else 0)
	var size: Vector2i = Vector2i(480 * 4, 360 * ceili(float(shots) / 4.0))
	_expect(sheet != null and sheet.get_size() == size,
		"Save Pictures writes one sheet of %d pictures, two per animation and two put away (%s)" % [shots,
			sheet.get_size() if sheet != null else Vector2i.ZERO])
	if sheet != null:
		var bare: Array[int] = []
		var background: Color = sheet.get_pixel(2, 350)
		for n: int in range(shots):
			var at: Vector2i = Vector2i((n % 4) * 480, int(float(n) / 4.0) * 360)
			var different: int = 0
			for y: int in range(60, 360, 6):
				for x: int in range(0, 480, 6):
					var c: Color = sheet.get_pixelv(at + Vector2i(x, y))
					if absf(c.r - background.r) + absf(c.g - background.g) + absf(c.b - background.b) > 0.15:
						different += 1
			if different < 60:
				bare.append(n)
		_expect(bare.is_empty(), "every picture has the characters and the item in it, not only the background (bare: %s)" % str(bare))
	_expect(_grip_text(grip) == before, "and taking pictures changes no grip")
	print("RENDER %s: %d failed" % ["PASS" if _failures == 0 else "FAIL", _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


static func _grip_text(g: ItemGrip) -> String:
	var parts: PackedStringArray = []
	for e: GripEntry in g.entries:
		parts.append("%s|%s|%s|%s|%s" % [e.animation, e.body, e.position, e.rotation_degrees, e.steady])
	return ";".join(parts)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("RENDER PASS ", msg)
	else:
		_failures += 1
		printerr("RENDER FAIL ", msg)
