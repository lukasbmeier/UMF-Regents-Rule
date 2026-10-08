extends SceneTree
## Paints the lakeside terrain's six ground textures into res://game/world/terrain/textures/.
##
##   godot --headless --path . -s res://tools/world/lakeside_textures.gd
##   godot --headless --path . --import
##
## Stylized rather than photographic, to sit with the Quaternius kits: soft colour, low-frequency
## variation, a little grain. Every one is SEAMLESS (FastNoiseLite's seamless images, and a
## blade/pebble layer drawn with wrap-around) so the terrain can tile it.
##
## Packed the way Terrain3D samples them: `<name>_albedo.png` is RGB colour with HEIGHT in alpha
## (for height-blending between textures), `<name>_normal.png` is RGB normal with ROUGHNESS in
## alpha. All the same size and format, which Terrain3D requires of a texture list. Each gets a
## `.png.import` written before the first import: VRAM-compressed with mipmaps, and NOT imported
## as a normal map, because Terrain3D reads the packed channels itself.
##
## Deterministic: fixed seeds, so re-running reproduces the same bytes.

const OUT: String = "res://game/world/terrain/textures/"
const SIZE: int = 1024

## name -> [base colour, secondary colour, grain, roughness, normal strength, seed]
const LOOKS: Dictionary[String, Array] = {
	"grass": [Color(0.34, 0.54, 0.20), Color(0.46, 0.60, 0.22), 0.10, 0.92, 2.0, 11],
	"dirt": [Color(0.47, 0.35, 0.22), Color(0.37, 0.27, 0.17), 0.12, 0.88, 3.0, 23],
	"rock": [Color(0.50, 0.49, 0.47), Color(0.38, 0.37, 0.36), 0.08, 0.78, 5.0, 37],
	"sand": [Color(0.78, 0.70, 0.52), Color(0.70, 0.62, 0.45), 0.07, 0.94, 1.5, 41],
	"mud": [Color(0.27, 0.25, 0.17), Color(0.20, 0.19, 0.13), 0.06, 0.55, 2.0, 53],
	"forest": [Color(0.24, 0.31, 0.14), Color(0.35, 0.28, 0.16), 0.12, 0.93, 2.5, 67],
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for name: String in LOOKS:
		_paint(name, LOOKS[name])
	print("lakeside_textures: wrote %d texture pairs to %s" % [LOOKS.size(), OUT])
	quit()


func _paint(name: String, look: Array) -> void:
	var base: Color = look[0]
	var second: Color = look[1]
	var grain: float = look[2]
	var roughness: float = look[3]
	var strength: float = look[4]
	var seed_value: int = look[5]

	var broad: Image = _noise(seed_value, 0.004, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	var mid: Image = _noise(seed_value + 1, 0.02, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	var fine: Image = _noise(seed_value + 2, 0.12, 2, FastNoiseLite.TYPE_VALUE)
	var cells: Image = _cells(seed_value + 3, 0.012) if name == "rock" or name == "dirt" else null

	var height := Image.create(SIZE, SIZE, false, Image.FORMAT_RF)
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var b: float = broad.get_pixel(x, y).r
			var m: float = mid.get_pixel(x, y).r
			var f: float = fine.get_pixel(x, y).r
			var h: float = b * 0.45 + m * 0.4 + f * 0.15
			var mix: float = clampf(b * 0.7 + m * 0.5 - 0.35, 0.0, 1.0)
			var col: Color = base.lerp(second, mix)
			match name:
				"rock":
					# Cracks: the cell edges sit low and dark.
					var c: float = cells.get_pixel(x, y).r
					h = h * 0.5 + c * 0.5
					col = col.darkened(clampf(0.35 - c * 0.6, 0.0, 0.35))
				"dirt":
					# Pebbles: round bumps from the cell centres.
					var c: float = cells.get_pixel(x, y).r
					if c > 0.72:
						h += (c - 0.72) * 1.4
						col = col.lightened((c - 0.72) * 0.8)
				"sand":
					# Wind ripples, running across the tile and wrapping with it.
					var r: float = sin((x + m * 60.0) * TAU / SIZE * 48.0) * 0.5 + 0.5
					h = h * 0.6 + r * 0.4
					col = col.lightened((r - 0.5) * 0.08)
				"forest":
					# Leaf litter: warm specks.
					if f > 0.78:
						col = col.lerp(Color(0.55, 0.36, 0.14), (f - 0.78) * 2.5)
				"grass":
					# Blades: short bright flecks.
					if f > 0.8:
						col = col.lightened((f - 0.8) * 1.2)
				_:
					pass
			col = col.lightened((f - 0.5) * grain)
			height.set_pixel(x, y, Color(h, 0, 0))
			albedo.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(h, 0.0, 1.0)))

	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var l: float = height.get_pixel((x - 1 + SIZE) % SIZE, y).r
			var r: float = height.get_pixel((x + 1) % SIZE, y).r
			var u: float = height.get_pixel(x, (y - 1 + SIZE) % SIZE).r
			var d: float = height.get_pixel(x, (y + 1) % SIZE).r
			var n := Vector3((l - r) * strength, (u - d) * strength, 1.0).normalized()
			var rough: float = clampf(roughness + (height.get_pixel(x, y).r - 0.5) * 0.08, 0.0, 1.0)
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, rough))

	_save(albedo, name + "_albedo.png")
	_save(normal, name + "_normal.png")


func _noise(seed_value: int, frequency: float, octaves: int, kind: FastNoiseLite.NoiseType) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = kind
	n.frequency = frequency
	n.fractal_octaves = octaves
	var img: Image = n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
	img.convert(Image.FORMAT_RF)
	return img


func _cells(seed_value: int, frequency: float) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = frequency
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var img: Image = n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
	img.convert(Image.FORMAT_RF)
	return img


func _save(img: Image, file: String) -> void:
	var path: String = OUT + file
	var err: int = img.save_png(path)
	if err != OK:
		push_error("lakeside_textures: could not write %s (%s)" % [path, error_string(err)])
		return
	var import_path: String = ProjectSettings.globalize_path(path + ".import")
	if FileAccess.file_exists(import_path):
		return   # the importer owns it now; the editor's Import dock edits it
	var f: FileAccess = FileAccess.open(import_path, FileAccess.WRITE)
	f.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
		+ "compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\n"
		+ "compress/normal_map=2\ncompress/channel_pack=0\nmipmaps/generate=true\n"
		+ "mipmaps/limit=-1\nroughness/mode=0\nprocess/fix_alpha_border=true\n"
		+ "process/premult_alpha=false\nprocess/normal_map_invert_y=false\n"
		+ "process/size_limit=0\ndetect_3d/compress_to=0\n")
	f.close()
