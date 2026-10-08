extends SceneTree
## Synthesises the fishing genre's placeholder sound effects into `res://game/fishing/sfx/`.
##
##   godot --headless --path . -s res://tools/synth_fishing_sfx.gd
##   godot --headless --path . --import
##
## Every sound is made here from sine waves and filtered noise, so the repo ships audio it owns
## outright (CC0, like the Quaternius clips) and a designer replaces any of them by dropping a
## file with the same name over it — nothing refers to how a sound was made. Deterministic: the
## noise is seeded, so re-running reproduces the same bytes and git sees no change.
##
## Loops (`pond_ambience`) also get a `.wav.import` written BEFORE the first import, carrying
## `edit/loop_mode`. The importer keeps the params it finds and fills in the rest; an imported
## WAV's loop lives in its .import file, not in the WAV.

const OUT_DIR: String = "res://game/fishing/sfx/"
const RATE: int = 44100

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_rng.seed = 0x5F1511
	_write("cast", _cast())
	_write("plop", _plop())
	_write("reel_hit", _reel_hit())
	_write("reel_miss", _reel_miss())
	_write("splash", _splash())
	_write("catch", _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.085, 0.55, 0.0))
	_write("catch_rare", _arpeggio([587.33, 739.99, 880.0, 1174.66, 1479.98, 1760.0], 0.07, 0.9, 0.35))
	_write("coin", _coin())
	_write("round_start", _bell([392.0, 523.25], 0.18, 1.6))
	_write("round_end", _bell([659.25, 523.25, 392.0], 0.22, 1.8))
	_write("ui_click", _click())
	_write("pond_ambience", _ambience(6.0), true)
	print("synth_fishing_sfx: wrote 12 sounds to ", OUT_DIR)
	quit()


# --- the sounds -------------------------------------------------------------------------

## A rod swung through the air: band-limited noise that rises then falls, with a pitched swish.
func _cast() -> PackedFloat32Array:
	var n: int = _len(0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / RATE
		var env: float = sin(PI * clampf(t / 0.5, 0.0, 1.0)) ** 2.0
		# The cutoff sweeps up and back down: that is what makes noise sound like motion.
		var cut: float = 0.03 + 0.22 * sin(PI * clampf(t / 0.5, 0.0, 1.0))
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * cut
		lp2 += (lp - lp2) * cut
		out[i] = (lp - lp2 * 0.6) * env * 1.6
	return out


## The bobber hitting water: a short resonant "bloop" that drops in pitch, plus a little spray.
func _plop() -> PackedFloat32Array:
	var n: int = _len(0.32)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / RATE
		var f: float = 180.0 + 900.0 * exp(-t * 38.0)
		phase += TAU * f / RATE
		var body: float = sin(phase) * exp(-t * 16.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var spray: float = lp * exp(-t * 30.0) * 0.35
		out[i] = (body * 0.8 + spray) * minf(1.0, t * 400.0)
	return out


## A good press: a crisp reel click with a bright ring on top.
func _reel_hit() -> PackedFloat32Array:
	var n: int = _len(0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in range(n):
		var t: float = float(i) / RATE
		var click: float = _rng.randf_range(-1.0, 1.0) * exp(-t * 400.0)
		var ring: float = (sin(TAU * 1567.98 * t) + 0.4 * sin(TAU * 3135.96 * t)) * exp(-t * 28.0)
		out[i] = click * 0.5 + ring * 0.45
	return out


## A missed press: a dull knock, no ring.
func _reel_miss() -> PackedFloat32Array:
	var n: int = _len(0.14)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / RATE
		var knock: float = sin(TAU * (140.0 - 60.0 * t) * t) * exp(-t * 32.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.08
		out[i] = knock * 0.7 + lp * exp(-t * 45.0) * 0.6
	return out


## A fish breaking the surface: a burst of noise whose brightness falls away, then droplets.
func _splash() -> PackedFloat32Array:
	var n: int = _len(0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / RATE
		var cut: float = 0.45 * exp(-t * 5.0) + 0.04
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * cut
		out[i] = lp * exp(-t * 5.5) * minf(1.0, t * 300.0) * 1.3
	# Droplets: short falling blips scattered through the tail.
	for d: int in range(9):
		var start: float = 0.12 + _rng.randf() * 0.6
		var f0: float = 900.0 + _rng.randf() * 1400.0
		var amp: float = 0.12 + _rng.randf() * 0.12
		var phase: float = 0.0
		for j: int in range(_len(0.05)):
			var k: int = int(start * RATE) + j
			if k >= n:
				break
			var tt: float = float(j) / RATE
			phase += TAU * f0 * (1.0 - tt * 6.0) / RATE
			out[k] += sin(phase) * exp(-tt * 90.0) * amp
	return out


## The reward: notes one after another, each a soft sine with a little octave above it. `shimmer`
## adds a fast tremolo for the rare fish, so rarity is audible without looking.
func _arpeggio(notes: Array, step: float, tail: float, shimmer: float) -> PackedFloat32Array:
	var n: int = _len(step * notes.size() + tail)
	var out := PackedFloat32Array()
	out.resize(n)
	for idx: int in range(notes.size()):
		var f: float = float(notes[idx])
		var start: int = int(idx * step * RATE)
		for j: int in range(n - start):
			var t: float = float(j) / RATE
			var env: float = minf(1.0, t * 180.0) * exp(-t * 4.5)
			var trem: float = 1.0 - shimmer * 0.5 * (1.0 + sin(TAU * 11.0 * t))
			out[start + j] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * trem * 0.28
	return out


## Money: two quick bright pings, the second higher.
func _coin() -> PackedFloat32Array:
	var n: int = _len(0.4)
	var out := PackedFloat32Array()
	out.resize(n)
	for pair: Array in [[987.77, 0.0], [1318.51, 0.07]]:
		var f: float = float(pair[0])
		var start: int = int(float(pair[1]) * RATE)
		for j: int in range(n - start):
			var t: float = float(j) / RATE
			out[start + j] += (sin(TAU * f * t) + 0.5 * sin(TAU * f * 3.0 * t)) \
				* exp(-t * 14.0) * minf(1.0, t * 800.0) * 0.35
	return out


## A bell for the round's start and end: inharmonic partials (1, 2.76, 5.4 — a struck bar, not
## a string) each decaying at its own rate. Notes are struck `gap` seconds apart.
func _bell(notes: Array, gap: float, length: float) -> PackedFloat32Array:
	var n: int = _len(length + gap * notes.size())
	var out := PackedFloat32Array()
	out.resize(n)
	var partials: Array = [[1.0, 1.0, 2.2], [2.76, 0.45, 4.0], [5.4, 0.25, 7.0]]
	for idx: int in range(notes.size()):
		var f: float = float(notes[idx])
		var start: int = int(idx * gap * RATE)
		for j: int in range(n - start):
			var t: float = float(j) / RATE
			var v: float = 0.0
			for pt: Array in partials:
				v += sin(TAU * f * float(pt[0]) * t) * float(pt[1]) * exp(-t * float(pt[2]))
			out[start + j] += v * minf(1.0, t * 1000.0) * 0.22
	return out


func _click() -> PackedFloat32Array:
	var n: int = _len(0.045)
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in range(n):
		var t: float = float(i) / RATE
		out[i] = (sin(TAU * 2200.0 * t) * 0.6 + _rng.randf_range(-1.0, 1.0) * 0.4) * exp(-t * 160.0)
	return out


## Water lapping at a pond's edge, for looping. Low filtered noise with a slow swell, and a few
## soft drips. The last half-second is cross-faded into the first so the seam cannot be heard.
func _ambience(seconds: float) -> PackedFloat32Array:
	var n: int = _len(seconds)
	var fade: int = _len(0.5)
	var total: int = n + fade
	var raw := PackedFloat32Array()
	raw.resize(total)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i: int in range(total):
		var t: float = float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		var swell: float = 0.55 + 0.45 * sin(TAU * t / 3.0) * sin(TAU * t / 1.7 + 1.0)
		raw[i] = lp2 * 3.2 * swell
	for d: int in range(7):
		var start: int = int(_rng.randf() * (n - _len(0.1)))
		var f0: float = 700.0 + _rng.randf() * 900.0
		for j: int in range(_len(0.08)):
			var tt: float = float(j) / RATE
			raw[start + j] += sin(TAU * f0 * (1.0 - tt * 4.0) * tt) * exp(-tt * 60.0) * 0.08
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in range(n):
		out[i] = raw[i]
	for i: int in range(fade):
		var w: float = float(i) / fade
		out[i] = raw[i] * w + raw[n + i] * (1.0 - w)
	return out


# --- writing ------------------------------------------------------------------------------

func _len(seconds: float) -> int:
	return int(seconds * RATE)


## Normalise to a common peak, convert to 16-bit mono, save as WAV.
func _write(name: String, samples: PackedFloat32Array, loop: bool = false) -> void:
	var peak: float = 0.0
	for v: float in samples:
		peak = maxf(peak, absf(v))
	var gain: float = 0.8 / peak if peak > 0.0 else 1.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, clampi(roundi(samples[i] * gain * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var path: String = OUT_DIR + name + ".wav"
	var err: int = wav.save_to_wav(path)
	if err != OK:
		push_error("synth_fishing_sfx: could not write %s (%s)" % [path, error_string(err)])
		return
	if loop:
		_write_loop_import(path)


## The params the importer should use for a looping sound. Only written when there is no .import
## yet: once the importer has run, the file is its, and the editor's Import dock edits it.
func _write_loop_import(path: String) -> void:
	var import_path: String = ProjectSettings.globalize_path(path + ".import")
	if FileAccess.file_exists(import_path):
		return
	var f: FileAccess = FileAccess.open(import_path, FileAccess.WRITE)
	f.store_string("[remap]\n\nimporter=\"wav\"\ntype=\"AudioStreamWAV\"\n\n[params]\n\n"
		+ "force/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\n"
		+ "edit/trim=false\nedit/normalize=false\nedit/loop_mode=2\nedit/loop_begin=0\n"
		+ "edit/loop_end=-1\ncompress/mode=2\n")
	f.close()
