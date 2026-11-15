@tool
class_name CastleWall extends Node3D
## WALLS MADE IN CODE (2026-11-15, `docs/regents_rule/SETTLEMENTS_PREP.md` §5, route 1): a wall round any outline,
## towers at its corners, gates in any stretches; the castle's curtain wall, a town's wall, a keep (a small closed wall,
## roofed). Made of the Medieval Village kit's own stone textures at the kit's scale (2 m a tile), so it sits beside
## the houses as if it came with them, and its surfaces are named as the kit's materials so a `Settlement` dresses it
## like any house: the walls and towers are MASONRY (`MI_UnevenBrick`), the plinth, the cap, the battlements and the
## gate's frame CUT STONE (`MI_Brick`), the towers' cones ROOF (`MI_RoundTiles`), the portcullis TIMBER (`MI_WoodTrim`).
##
## Set the outline in `corners` (local x, z; y is ignored), the heights in meters, and press nothing: it rebuilds as
## you change it, in the editor too, and the built mesh is never saved.

## The outline's corners, local (x, z). Two or more.
@export var corners: PackedVector3Array = PackedVector3Array([Vector3(-20, 0, -20), Vector3(20, 0, -20),
	Vector3(20, 0, 20), Vector3(-20, 0, 20)]):
	set(v):
		corners = v
		_changed()
## Joins the last corner to the first.
@export var closed: bool = true:
	set(v):
		closed = v
		_changed()
@export_range(2.0, 40.0) var height: float = 10.0:
	set(v):
		height = v
		_changed()
@export_range(0.6, 8.0) var thickness: float = 2.5:
	set(v):
		thickness = v
		_changed()
## The battlements: a merlon's width and height, and the gap between two.
@export_range(0.4, 3.0) var merlon_width: float = 1.2:
	set(v):
		merlon_width = v
		_changed()
@export_range(0.3, 3.0) var merlon_height: float = 1.3:
	set(v):
		merlon_height = v
		_changed()
@export_range(0.3, 3.0) var crenel_width: float = 0.9:
	set(v):
		crenel_width = v
		_changed()

@export_group("Towers")
## A tower at every corner; 0 for none.
@export_range(0.0, 15.0) var tower_radius: float = 4.0:
	set(v):
		tower_radius = v
		_changed()
@export_range(2.0, 60.0) var tower_height: float = 15.0:
	set(v):
		tower_height = v
		_changed()
## Round (16 sides) or square towers.
@export var round_towers: bool = true:
	set(v):
		round_towers = v
		_changed()
## A tiled cone on each tower (round towers; a pyramid on square ones).
@export var tower_roofs: bool = true:
	set(v):
		tower_roofs = v
		_changed()

@export_group("Gate")
## Which stretches have a gate (stretch i runs from corner i to corner i + 1); empty for none.
@export var gates: PackedInt32Array = PackedInt32Array([0]):
	set(v):
		gates = v
		_changed()
@export_range(2.0, 12.0) var gate_width: float = 5.0:
	set(v):
		gate_width = v
		_changed()
@export_range(2.0, 20.0) var gate_height: float = 6.0:
	set(v):
		gate_height = v
		_changed()
## Two square towers either side of the gate.
@export var gatehouse: bool = true:
	set(v):
		gatehouse = v
		_changed()

@export_group("Keep")
## A floor across the top: a closed wall becomes a solid block (a keep).
@export var roofed: bool = false:
	set(v):
		roofed = v
		_changed()

const MASONRY: String = "MI_UnevenBrick"
const CUT: String = "MI_Brick"
const ROOF: String = "MI_RoundTiles"
const TIMBER: String = "MI_WoodTrim"
## The kit's tiling: 0.5 of a texture a meter.
const UV_PER_M: float = 0.5
## Where the timber band lies on the wood trim sheet (v), for the portcullis.
const TIMBER_V: float = 0.45

var _surfaces: Dictionary[String, SurfaceTool] = {}
var _built: Node3D = null
var _body: StaticBody3D = null
var _queued: bool = false
## The collision shapes the last build made, as (transform, size) for boxes and (transform, radius, height) for
## towers: the suite checks the gate is open with them.
var boxes: Array[Array] = []


func _ready() -> void:
	build()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild_later.call_deferred()


func _rebuild_later() -> void:
	_queued = false
	build()


## Builds the walls from the fields (dropping the last build). Returns the mesh's node.
func build() -> MeshInstance3D:
	if _built != null and is_instance_valid(_built):
		_built.free()
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built)
	_body = StaticBody3D.new()
	_body.name = "Body"
	_built.add_child(_body)
	_surfaces.clear()
	boxes.clear()
	var pts: Array[Vector3] = []
	for c: Vector3 in corners:
		pts.append(Vector3(c.x, 0.0, c.z))
	if pts.size() < 2:
		return null
	var mid := Vector3.ZERO
	for p: Vector3 in pts:
		mid += p
	mid /= float(pts.size())
	var count: int = pts.size() if closed else pts.size() - 1
	for i: int in count:
		_segment(pts[i], pts[(i + 1) % pts.size()], mid, gates.has(i))
	if tower_radius > 0.0:
		for p: Vector3 in pts:
			_tower(p, tower_radius, tower_height, round_towers)
	if roofed and closed:
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		for p: Vector3 in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var size := Vector3(hi.x - lo.x, 0.4, hi.z - lo.z)
		_box(CUT, Transform3D(Basis.IDENTITY, Vector3((lo.x + hi.x) * 0.5, height - 0.2, (lo.z + hi.z) * 0.5)), size, false)
	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	var mesh := ArrayMesh.new()
	for key: String in [MASONRY, CUT, ROOF, TIMBER]:
		if not _surfaces.has(key):
			continue
		var st: SurfaceTool = _surfaces[key]
		st.generate_tangents()
		mesh = st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, TownKit.placeholder(key))
	mi.mesh = mesh
	_built.add_child(mi)
	return mi


## One stretch of wall from a to b (its outside away from `mid`), with its plinth, cap and battlements; a gate in it.
func _segment(a: Vector3, b: Vector3, mid: Vector3, gate: bool) -> void:
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 0.01:
		return
	d /= length
	var out := Vector3(d.z, 0, -d.x)
	if out.dot((a + b) * 0.5 - mid) < 0.0:
		out = -out
	# The wall's frame: x along it, z outward.
	var frame := Basis(d, Vector3.UP, out)
	var t: float = thickness
	var runs: Array[Vector2] = [Vector2(-t * 0.5, length + t * 0.5)]
	var g0: float = length * 0.5 - gate_width * 0.5
	var g1: float = length * 0.5 + gate_width * 0.5
	if gate:
		runs = [Vector2(-t * 0.5, g0), Vector2(g1, length + t * 0.5)]
	for r: Vector2 in runs:
		var span: float = r.y - r.x
		if span <= 0.05:
			continue
		var c: Vector3 = a + d * ((r.x + r.y) * 0.5)
		_box(MASONRY, Transform3D(frame, c + Vector3.UP * height * 0.5), Vector3(span, height, t), true)
		_box(CUT, Transform3D(frame, c + Vector3.UP * 0.5), Vector3(span, 1.0, t + 0.5), false)
		_box(CUT, Transform3D(frame, c + Vector3.UP * (height - 0.2)), Vector3(span, 0.4, t + 0.3), false)
		_battlements(a, d, out, frame, r.x, r.y)
	if gate:
		var gc: Vector3 = a + d * (length * 0.5)
		var lintel: float = height - gate_height
		if lintel > 0.05:
			_box(MASONRY, Transform3D(frame, gc + Vector3.UP * (gate_height + lintel * 0.5)),
				Vector3(gate_width, lintel, t), true)
		_box(CUT, Transform3D(frame, gc + Vector3.UP * (gate_height + 0.3) + out * (t * 0.5 + 0.1)),
			Vector3(gate_width + 1.2, 0.6, 0.4), false)
		for side: float in [-1.0, 1.0]:
			_box(CUT, Transform3D(frame, gc + d * side * (gate_width * 0.5 + 0.3) + Vector3.UP * gate_height * 0.5
				+ out * (t * 0.5 + 0.1)), Vector3(0.6, gate_height, 0.4), false)
		_battlements(a, d, out, frame, g0, g1)
		_portcullis(gc, d, out, frame)
		if gatehouse:
			var gw: float = maxf(3.0, t * 1.2)
			for side: float in [-1.0, 1.0]:
				var tc: Vector3 = gc + d * side * (gate_width * 0.5 + gw * 0.5 + 0.4) + out * (t * 0.5 + gw * 0.25)
				_tower(tc, gw * 0.5 + 0.5, height + 4.0, false, frame)


## Merlons along the outer edge between x0 and x1 along the wall, a low parapet on the inner edge.
func _battlements(a: Vector3, d: Vector3, out: Vector3, frame: Basis, x0: float, x1: float) -> void:
	var span: float = x1 - x0
	if span <= 0.3:
		return
	var step: float = merlon_width + crenel_width
	var n: int = maxi(1, int(floor((span + crenel_width) / step)))
	var used: float = n * step - crenel_width
	var start: float = x0 + (span - used) * 0.5
	for i: int in n:
		var cx: float = start + i * step + merlon_width * 0.5
		var c: Vector3 = a + d * cx + out * (thickness * 0.5 - 0.3) + Vector3.UP * (height + merlon_height * 0.5)
		_box(CUT, Transform3D(frame, c), Vector3(merlon_width, merlon_height, 0.6), false)
	var rail: Vector3 = a + d * ((x0 + x1) * 0.5) - out * (thickness * 0.5 - 0.2) + Vector3.UP * (height + 0.4)
	_box(CUT, Transform3D(frame, rail), Vector3(span, 0.8, 0.4), false)


## A portcullis half raised in the gate: timber bars, crossed.
func _portcullis(gc: Vector3, d: Vector3, out: Vector3, frame: Basis) -> void:
	var bottom: float = gate_height * 0.55
	var bars: int = maxi(2, int(gate_width / 0.7))
	for i: int in bars:
		var x: float = -gate_width * 0.5 + (i + 0.5) * gate_width / bars
		var c: Vector3 = gc + d * x + out * (thickness * 0.25) + Vector3.UP * (bottom + (gate_height - bottom) * 0.5)
		_box(TIMBER, Transform3D(frame, c), Vector3(0.18, gate_height - bottom, 0.18), false)
	for j: int in 3:
		var y: float = bottom + 0.3 + j * (gate_height - bottom - 0.6) / 2.0
		var c: Vector3 = gc + out * (thickness * 0.25 + 0.12) + Vector3.UP * y
		_box(TIMBER, Transform3D(frame, c), Vector3(gate_width, 0.16, 0.12), false)


## A tower standing at `c`: round (16 sides) or square, with a plinth, a parapet of merlons and a roof.
func _tower(c: Vector3, r: float, h: float, round_one: bool, frame: Basis = Basis.IDENTITY) -> void:
	var sides: int = 16 if round_one else 4
	var turn: float = 0.0 if round_one else PI * 0.25
	var rr: float = r if round_one else r * sqrt(2.0)
	_prism(MASONRY, c, rr, 0.0, h, sides, turn, frame)
	_prism(CUT, c, rr + 0.3, 0.0, 1.2, sides, turn, frame)
	_prism(CUT, c, rr + 0.2, h - 0.4, h, sides, turn, frame)
	_cap(CUT, c, rr + 0.2, h, sides, turn, frame)
	var circ: float = TAU * r if round_one else 8.0 * r
	var step: float = merlon_width + crenel_width
	var n: int = maxi(4, int(circ / step))
	if not round_one:
		n = maxi(1, int(round(2.0 * r / step))) * 4
	for i: int in n:
		var p: Vector3
		var tangent: Vector3
		if round_one:
			var ang: float = TAU * i / n
			p = Vector3(cos(ang), 0, sin(ang)) * (r - 0.15)
			tangent = Vector3(-sin(ang), 0, cos(ang))
		else:
			var per: int = floori(n / 4.0)
			var side: int = floori(float(i) / per)
			var k: int = i % per
			var along: float = -r + (k + 0.5) * (2.0 * r / per)
			var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
			var normal: Vector3 = dirs[side]
			tangent = Vector3(-normal.z, 0, normal.x)
			p = normal * (r - 0.15) + tangent * along
		p = frame * p
		tangent = frame * tangent
		var mb := Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP))
		_box(CUT, Transform3D(mb, c + p + Vector3.UP * (h + merlon_height * 0.5)), Vector3(merlon_width, merlon_height, 0.5), false)
	if tower_roofs:
		_cone(ROOF, c, rr + 0.5, h + merlon_height * 0.6, r * 1.9, sides, turn, frame)
	var shape := CollisionShape3D.new()
	if round_one:
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = h
		shape.shape = cyl
	else:
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.0 * r, h, 2.0 * r)
		shape.shape = bs
	shape.transform = Transform3D(frame, c + Vector3.UP * h * 0.5)
	_body.add_child(shape)


func _st(material: String) -> SurfaceTool:
	if not _surfaces.has(material):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = st
	return _surfaces[material]


## A quad a b c d (in order round its edge) facing `n`, with the kit's tiling: walls by their run and height, tops by
## x and z. Wound so its front faces `n`.
func _quad(material: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv_override: PackedVector2Array = PackedVector2Array()) -> void:
	var st: SurfaceTool = _st(material)
	var pts: Array[Vector3] = [a, b, c, d]
	var uvs: Array[Vector2] = []
	if uv_override.size() == 4:
		for u: Vector2 in uv_override:
			uvs.append(u)
	else:
		for p: Vector3 in pts:
			var uv: Vector2 = _uv(p, n)
			if material == TIMBER:
				# The trim sheet is bands: keep the timber's.
				uv = Vector2(uv.x, TIMBER_V + fposmod(uv.y, 1.0) * 0.12)
			uvs.append(uv)
	# Godot draws clockwise triangles as front faces: wind so the cross product points away from the normal.
	var flip: bool = (b - a).cross(c - a).dot(n) > 0.0
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	if flip:
		order = [0, 2, 1, 0, 3, 2]
	for i: int in order:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(0.0, 1.0))
		st.add_vertex(pts[i])


func _uv(p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.5:
		return Vector2(p.x, p.z) * UV_PER_M
	var t: Vector3 = Vector3.UP.cross(n).normalized()
	return Vector2(p.dot(t), -p.y) * UV_PER_M


## A box: its frame (x along, y up, z out), its full size. `solid` adds its collision.
func _box(material: String, xf: Transform3D, size: Vector3, solid: bool) -> void:
	var h: Vector3 = size * 0.5
	var b: Basis = xf.basis
	var o: Vector3 = xf.origin
	var corner: Callable = func(x: float, y: float, z: float) -> Vector3: return o + b * Vector3(x * h.x, y * h.y, z * h.z)
	var faces: Array[Array] = [
		[Vector3(1, 0, 0), [Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
		[Vector3(-1, 0, 0), [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1)]],
		[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
		[Vector3(0, -1, 0), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(-1, -1, -1)]],
		[Vector3(0, 0, 1), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
		[Vector3(0, 0, -1), [Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)]],
	]
	for f: Array in faces:
		var q: Array = f[1]
		var v: Array[Vector3] = []
		for k: Vector3 in q:
			v.append(corner.call(k.x, k.y, k.z) as Vector3)
		_quad(material, v[0], v[1], v[2], v[3], (b * (f[0] as Vector3)).normalized())
	if solid:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		shape.transform = xf
		_body.add_child(shape)
		boxes.append([xf, size])


## A prism's sides from y0 to y1 round `c`: `sides` faces at radius r (to its corners), the first corner at `turn`.
func _prism(material: String, c: Vector3, r: float, y0: float, y1: float, sides: int, turn: float, frame: Basis) -> void:
	var run: float = 0.0
	for i: int in sides:
		var a0: float = turn + TAU * i / sides
		var a1: float = turn + TAU * (i + 1) / sides
		var p0: Vector3 = c + frame * (Vector3(cos(a0), 0, sin(a0)) * r)
		var p1: Vector3 = c + frame * (Vector3(cos(a1), 0, sin(a1)) * r)
		var n: Vector3 = frame * Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var w: float = p0.distance_to(p1)
		var uv := PackedVector2Array([Vector2(run, -y0), Vector2(run + w, -y0), Vector2(run + w, -y1), Vector2(run, -y1)])
		for k: int in 4:
			uv[k] *= UV_PER_M
		_quad(material, p0 + Vector3.UP * y0, p1 + Vector3.UP * y0, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1, n, uv)
		run += w


## A prism's flat top at y.
func _cap(material: String, c: Vector3, r: float, y: float, sides: int, turn: float, frame: Basis) -> void:
	var top: Vector3 = c + Vector3.UP * y
	for i: int in sides:
		var a0: float = turn + TAU * i / sides
		var a1: float = turn + TAU * (i + 1) / sides
		var p0: Vector3 = top + frame * (Vector3(cos(a0), 0, sin(a0)) * r)
		var p1: Vector3 = top + frame * (Vector3(cos(a1), 0, sin(a1)) * r)
		_quad(material, top, p0, p1, top, Vector3.UP)


## A tiled cone (a pyramid with 4 sides): the tiles' rows run round it, down the slope.
func _cone(material: String, c: Vector3, r: float, y: float, rise: float, sides: int, turn: float, frame: Basis) -> void:
	var tip: Vector3 = c + Vector3.UP * (y + rise)
	var slant: float = sqrt(r * r + rise * rise)
	var run: float = 0.0
	for i: int in sides:
		var a0: float = turn + TAU * i / sides
		var a1: float = turn + TAU * (i + 1) / sides
		var p0: Vector3 = c + Vector3.UP * y + frame * (Vector3(cos(a0), 0, sin(a0)) * r)
		var p1: Vector3 = c + Vector3.UP * y + frame * (Vector3(cos(a1), 0, sin(a1)) * r)
		var n: Vector3 = (p1 - p0).cross(tip - p0).normalized()
		if n.y < 0.0:
			n = -n
		var w: float = p0.distance_to(p1)
		var k: float = 0.42
		var uv := PackedVector2Array([Vector2(run, slant) * k, Vector2(run + w, slant) * k,
			Vector2(run + w * 0.5, 0.0) * k, Vector2(run + w * 0.5, 0.0) * k])
		_quad(material, p0, p1, tip, tip, n, uv)
		run += w
