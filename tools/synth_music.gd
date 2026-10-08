extends SceneTree
## Composes the fishing game's placeholder MUSIC into `res://game/fishing/music/` (DECISIONS #167).
##
##   godot --headless --path . -s res://tools/synth_music.gd
##   godot --headless --path . --import
##
## Like the sound effects (`synth_fishing_sfx.gd`), everything is made here, so the repo owns its
## audio outright (CC0) and a designer replaces a track by dropping a file of the same name over it
## (or pointing the scene's MusicDirector at another stream). Deterministic: re-running writes the
## same bytes.
##
## Each track is a seamless LOOP: it is rendered with a tail and the tail is folded back onto its
## start, so the last notes ring into the first. Its `.wav.import` asks the importer to loop it.
##
##   lakeside        while a round plays: a plucked folk progression in G (I vi IV V), a soft
##                   flute-like tune over it, a pad and a bass. 80 beats a minute, 16 bars.
##   between_rounds  the lobby, results and shop: slower and sparser, the same key, no tune.

const OUT_DIR: String = "res://game/fishing/music/"
const RATE: int = 22050

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_rng.seed = 0x6D7573
	_write("lakeside", _lakeside())
	_rng.seed = 0x6C6F62
	_write("between_rounds", _between())
	print("synth_music: wrote 2 tracks to ", OUT_DIR)
	quit()


# --- the tracks --------------------------------------------------------------------------------

## Chords as MIDI notes, root first. G, Em, C, D.
const PROGRESSION: Array = [[55, 59, 62], [52, 55, 59], [48, 52, 55], [50, 54, 57]]
## G major pentatonic, the tune's notes (G4 A4 B4 D5 E5 G5 A5).
const TUNE_NOTES: Array[int] = [67, 69, 71, 74, 76, 79, 81]


func _lakeside() -> PackedFloat32Array:
	var beat: float = 60.0 / 80.0
	var bars: int = 16
	var length: float = bars * 4 * beat
	var buf: PackedFloat32Array = _buffer(length + 4.0)
	for bar: int in range(bars):
		var chord: Array = PROGRESSION[bar % 4]
		var t0: float = bar * 4 * beat
		_pad(buf, t0, 4 * beat, chord, 0.05)
		_bass(buf, t0, chord[0] - 12, 0.9 * beat, 0.16)
		_bass(buf, t0 + 2 * beat, chord[0] - 12, 0.9 * beat, 0.12)
		# Eighth-note arpeggio, up and back: root, third, fifth, octave, fifth, third...
		var arp: Array[int] = [chord[0], chord[1], chord[2], chord[0] + 12, chord[2], chord[1], chord[2], chord[0] + 12]
		for i: int in range(8):
			_pluck(buf, t0 + i * beat * 0.5, arp[i], 1.4, 0.13 if i % 2 == 0 else 0.09)
	# The tune enters on bar 5, breathes on bars 9-10, and comes back.
	var tune_bars: Array[int] = [4, 5, 6, 7, 10, 11, 12, 13, 14, 15]
	var at: int = 2   # an index into TUNE_NOTES, walked one or two steps at a time
	for bar: int in tune_bars:
		var chord: Array = PROGRESSION[bar % 4]
		var rhythm: Array = [[0.0, 1.5], [1.5, 0.5], [2.0, 1.0], [3.0, 1.0]] if bar % 2 == 0 \
			else [[0.0, 1.0], [1.0, 1.0], [2.0, 2.0]]
		for k: int in range(rhythm.size()):
			var step: int = [-2, -1, -1, 1, 1, 2][_rng.randi_range(0, 5)]
			at = clampi(at + step, 0, TUNE_NOTES.size() - 1)
			var note: int = TUNE_NOTES[at]
			# Land the bar's last note on the chord, so the tune agrees with the harmony.
			if k == rhythm.size() - 1:
				note = _nearest_chord_tone(note, chord)
				at = maxi(TUNE_NOTES.find(note), 0) if TUNE_NOTES.has(note) else at
			var start: float = bar * 4 * beat + float(rhythm[k][0]) * beat
			_flute(buf, start, note, float(rhythm[k][1]) * beat * 0.95, 0.11)
	return _fold(buf, length)


func _between() -> PackedFloat32Array:
	var beat: float = 60.0 / 64.0
	var bars: int = 8
	var length: float = bars * 4 * beat
	var buf: PackedFloat32Array = _buffer(length + 5.0)
	var order: Array = [PROGRESSION[0], PROGRESSION[2], PROGRESSION[1], PROGRESSION[3]]
	for bar: int in range(bars):
		var chord: Array = order[bar % 4]
		var t0: float = bar * 4 * beat
		_pad(buf, t0, 4 * beat, chord, 0.07)
		_bass(buf, t0, chord[0] - 12, 2.5 * beat, 0.1)
		for i: int in range(4):
			if _rng.randf() < 0.75:
				var note: int = chord[_rng.randi_range(0, 2)] + 12
				_pluck(buf, t0 + i * beat + _rng.randf_range(0.0, 0.08), note, 2.2, 0.1)
	return _fold(buf, length)


# --- the instruments ---------------------------------------------------------------------------

## A plucked string (Karplus-Strong): a burst of noise in a delay line, averaged as it recirculates.
func _pluck(buf: PackedFloat32Array, start: float, note: int, seconds: float, amp: float) -> void:
	var period: int = maxi(2, roundi(RATE / _hz(note)))
	var line := PackedFloat32Array()
	line.resize(period)
	for i: int in range(period):
		line[i] = _rng.randf_range(-1.0, 1.0)
	# A softened burst: nylon rather than steel (raw noise is a harsh, clicky attack).
	for _pass: int in range(3):
		for i: int in range(period):
			line[i] = 0.5 * (line[i] + line[(i + 1) % period])
	var s0: int = int(start * RATE)
	var n: int = mini(int(seconds * RATE), buf.size() - s0)
	var idx: int = 0
	for i: int in range(n):
		var nxt: int = (idx + 1) % period
		var v: float = line[idx]
		line[idx] = 0.497 * (line[idx] + line[nxt])
		idx = nxt
		var fade: float = 1.0 - float(i) / float(n)
		buf[s0 + i] += v * amp * fade
	return


## A soft breathy tone: a sine with a little second harmonic and a slow vibrato.
func _flute(buf: PackedFloat32Array, start: float, note: int, seconds: float, amp: float) -> void:
	var hz: float = _hz(note)
	var s0: int = int(start * RATE)
	var n: int = mini(int((seconds + 0.35) * RATE), buf.size() - s0)
	var phase: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / RATE
		var env: float = minf(t / 0.06, 1.0) * (1.0 if t < seconds else maxf(0.0, 1.0 - (t - seconds) / 0.35))
		var vib: float = 1.0 + 0.004 * sin(TAU * 5.0 * t) * minf(t / 0.4, 1.0)
		phase += TAU * hz * vib / RATE
		buf[s0 + i] += (sin(phase) + 0.18 * sin(2.0 * phase) + 0.05 * sin(3.0 * phase)) * env * amp
	return


## A chord held softly, fading in and out so consecutive chords overlap.
func _pad(buf: PackedFloat32Array, start: float, seconds: float, chord: Array, amp: float) -> void:
	var s0: int = int(start * RATE)
	var fade: float = 0.6
	var n: int = mini(int((seconds + fade) * RATE), buf.size() - s0)
	for note: Variant in chord:
		var hz: float = _hz(int(note))
		for detune: float in [-0.003, 0.003]:
			var w: float = TAU * hz * (1.0 + detune) / RATE
			for i: int in range(n):
				var t: float = float(i) / RATE
				var env: float = minf(t / fade, 1.0) * (1.0 if t < seconds else maxf(0.0, 1.0 - (t - seconds) / fade))
				buf[s0 + i] += sin(w * i) * env * amp * 0.5
	return


## A round low note.
func _bass(buf: PackedFloat32Array, start: float, note: int, seconds: float, amp: float) -> void:
	var w: float = TAU * _hz(note) / RATE
	var s0: int = int(start * RATE)
	var n: int = mini(int(seconds * RATE), buf.size() - s0)
	for i: int in range(n):
		var t: float = float(i) / RATE
		var env: float = minf(t / 0.02, 1.0) * exp(-2.2 * t / seconds)
		buf[s0 + i] += (sin(w * i) + 0.25 * sin(2.0 * w * i)) * env * amp
	return


# --- helpers -----------------------------------------------------------------------------------

func _hz(note: int) -> float:
	return 440.0 * pow(2.0, float(note - 69) / 12.0)


func _nearest_chord_tone(note: int, chord: Array) -> int:
	var best: int = note
	var gap: int = 99
	for c: Variant in chord:
		for octave: int in [0, 12, 24, 36]:
			var cand: int = int(c) + octave
			if absi(cand - note) < gap:
				gap = absi(cand - note)
				best = cand
	return best


func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## The loop: the tail past `length` is mixed back onto the start, so the end rings into the start.
func _fold(buf: PackedFloat32Array, length: float) -> PackedFloat32Array:
	var n: int = int(length * RATE)
	for i: int in range(n, buf.size()):
		buf[i - n] += buf[i]
	buf.resize(n)
	return buf


## Normalise, 16-bit mono WAV, and an import that loops it.
func _write(track: String, samples: PackedFloat32Array) -> void:
	var peak: float = 0.0
	for v: float in samples:
		peak = maxf(peak, absf(v))
	var gain: float = 0.7 / peak if peak > 0.0 else 1.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, clampi(roundi(samples[i] * gain * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var path: String = OUT_DIR + track + ".wav"
	var err: int = wav.save_to_wav(path)
	if err != OK:
		push_error("synth_music: could not write %s (%s)" % [path, error_string(err)])
		return
	var import_path: String = ProjectSettings.globalize_path(path + ".import")
	if not FileAccess.file_exists(import_path):
		var f: FileAccess = FileAccess.open(import_path, FileAccess.WRITE)
		f.store_string("[remap]\n\nimporter=\"wav\"\ntype=\"AudioStreamWAV\"\n\n[params]\n\n"
			+ "force/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\n"
			+ "edit/trim=false\nedit/normalize=false\nedit/loop_mode=2\nedit/loop_begin=0\n"
			+ "edit/loop_end=-1\ncompress/mode=2\n")
		f.close()
	print("  ", track, ": %.1f s" % (float(samples.size()) / RATE))
