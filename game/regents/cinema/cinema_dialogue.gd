class_name CinemaDialogue extends RefCounted
## DIALOGUE MANAGER 3-COMPATIBLE SCRIPT RUNNER + VOICE RESOLVER (cinema proof-of-concept).
## Parses `.dialogue`-style scripts:
##   ~ section_name
##   Speaker: Line text [#cam=over_shoulder_npc] [#pose=interact] [#voice=res://...] [ID:line_01]
##   - Choice label [if flag == true] [#tag=val]
##       set flag = true
##       do callback(arg)
##       Speaker: Reaction line
##       => target_section
##   => END
##
## Voice-over resolution checks explicit `[#voice=...]` paths first, then `[ID:...]` audio files under
## `voice_dir`, and optionally generates a soft per-speaker `AudioStreamWAV` cadence fallback so
## voice-timed pacing and talking-head animation can be tested before studio lines are recorded.

signal line_started(line: Dictionary)
signal choices_presented(choices: Array[Dictionary])
signal action_triggered(action: String, arg: String)
signal dialogue_ended()

const VOICE_DIR_DEFAULT: String = "res://game/regents/cinema/voice"

## Multi-branch proof-of-concept script showcasing hubs, conditions, inline camera/pose tags,
## voice IDs, and decision-driven flashbacks.
const FRONTIER_SCRIPT: String = """~ start
Drillmaster: [#cam=wide_camp] [#pose=locomotion.idle] Hold a moment, traveler. Before you take iron past the eastern ridge, the Chronicler asked for your word. [ID:drill_01]
Chronicler: [#cam=over_shoulder_npc] [#pose=interact] Every blade tempered in this camp carries a past. Speak plainly, and I will set your record straight. [ID:chron_01]
=> start_hub

~ start_hub
Chronicler: [#cam=two_shot] [#pose=locomotion.idle] What would you hear first, or are you ready to recount the pass? [ID:chron_02]
- Ask about the Regent's Writ [if not asked_writ]
    => ask_writ
- Ask what waits east of camp [if not asked_east]
    => ask_east
- "I remember the night the northern pass fell." [#cam=over_shoulder_player]
    => memory_choice
- Leave the camp for now
    Drillmaster: [#cam=over_shoulder_npc] [#pose=interact] Keep your guard up out there. [ID:drill_02]
    => END

~ ask_writ
set asked_writ = true
Chronicler: [#cam=closeup_npc] [#pose=interact] The Regent is absent, yet his seal still binds every smith and scout in the glade. [ID:chron_03]
Adventurer: [#cam=over_shoulder_player] [#pose=interact] And who answers when the writs come due? [ID:adv_01]
Drillmaster: [#cam=over_shoulder_npc] [#pose=locomotion.idle] Whoever survives the frontier long enough to wear the crest. [ID:drill_03]
=> start_hub

~ ask_east
set asked_east = true
Drillmaster: [#cam=closeup_npc] [#pose=item.draw] Wolves prowl the timberline, and the old watch-camp swarms with skeletons and fiends. [ID:drill_04]
Drillmaster: [#cam=two_shot] [#pose=interact] Watch an archer's glint before you roll, and never turn your back on an imp's circle. [ID:drill_05]
=> start_hub

~ memory_choice
Chronicler: [#cam=closeup_npc] [#pose=interact] Tell us how you survived the ambush. Close your eyes and show me where you stood. [ID:chron_04]
- Relive the ambush in the glade (In-Place Memory Echo)
    do flashback(echo)
    => flashback_prompt
- Recall the burning watch-shrine (Isolated 3D Stage Vision)
    do flashback(stage)
    => flashback_prompt

~ flashback_prompt
Vanguard Captain: [#cam=flashback_focus] [#pose=ability.40023] [#voice=] The ridge is breaking! Two lines closing from the mist — give the order! [ID:cap_01]
- "Hold the shield wall! Buy the wagons time!"
    set memory_deed = shield_wall
    do memory_outcome(shield_wall)
    Vanguard Captain: [#cam=flashback_clash] [#pose=ability.40022] Shields locked! Stand fast against the vanguard! [ID:cap_02]
    => return_present
- "Loose the volley and break east into the timber!"
    set memory_deed = loose_arrow
    do memory_outcome(loose_arrow)
    Vanguard Captain: [#cam=flashback_clash] [#pose=ability.40011] Volley loose! Fall back to the trees! [ID:cap_03]
    => return_present

~ return_present
do end_flashback()
Chronicler: [#cam=over_shoulder_npc] [#pose=interact] So that was your call when the torches went out. [ID:chron_05]
Drillmaster: [#cam=closeup_npc] [#pose=locomotion.idle] A shield-line holds the line, even when it costs blood. The frontier remembers that. [if memory_deed == shield_wall] [ID:drill_06a]
Drillmaster: [#cam=closeup_npc] [#pose=locomotion.idle] A clean withdrawal saves lives to fight another dawn. Cold, perhaps, but smart. [if memory_deed == loose_arrow] [ID:drill_06b]
Chronicler: [#cam=two_shot] [#pose=interact] Name the oath you carry forward from this day. [ID:chron_06]
- Swear to the Regent's Vanguard
    set oath = vanguard
    do commit_oath(vanguard)
    Drillmaster: [#cam=wide_camp] [#pose=ability.40023] Then raise your steel, Vanguard. The camp stands with you. [ID:drill_07a]
    => END
- Walk as a Free Blade
    set oath = free_blade
    do commit_oath(free_blade)
    Chronicler: [#cam=wide_camp] [#pose=interact] No banner, no debt — only your own edge. Safe travels, Free Blade. [ID:chron_07b]
    => END
"""

var sections: Dictionary = {}
var state: Dictionary[String, Variant] = {}
var current_section: String = ""
var step_index: int = 0
var active_line: Dictionary = {}
var active_choices: Array[Dictionary] = []
var finished: bool = false
var _pending: Array[Dictionary] = []


func load_script(source: String) -> void:
	sections = parse(source)
	state.clear()
	current_section = ""
	step_index = 0
	active_line = {}
	active_choices.clear()
	_pending.clear()
	finished = false


func start(section: String = "start") -> void:
	if not sections.has(section):
		finished = true
		dialogue_ended.emit()
		return
	current_section = section
	step_index = 0
	active_line = {}
	active_choices.clear()
	_pending.clear()
	finished = false
	advance()


func advance() -> void:
	if finished or not active_choices.is_empty():
		return
	var guard: int = 0
	while guard < 128:
		guard += 1
		var step: Dictionary = _next_step()
		if step.is_empty():
			finished = true
			active_line = {}
			dialogue_ended.emit()
			return
		var kind: String = String(step.get("kind", ""))
		if kind == "line":
			var cond: String = String(step.get("condition", ""))
			if not cond.is_empty() and not eval_condition(cond):
				continue
			active_line = step
			line_started.emit(step)
			return
		elif kind == "set":
			var k: String = String(step.get("key", ""))
			state[k] = step.get("value")
		elif kind == "do":
			action_triggered.emit(String(step.get("action", "")), String(step.get("arg", "")))
		elif kind == "jump":
			var target: String = String(step.get("target", ""))
			if target == "END" or not sections.has(target):
				finished = true
				active_line = {}
				dialogue_ended.emit()
				return
			current_section = target
			step_index = 0
			_pending.clear()
		elif kind == "choices":
			var visible_choices: Array[Dictionary] = []
			var raw_items: Array = step.get("items", []) as Array
			for item_v: Variant in raw_items:
				var item: Dictionary = item_v as Dictionary
				var cond: String = String(item.get("condition", ""))
				if cond.is_empty() or eval_condition(cond):
					visible_choices.append(item)
			if visible_choices.is_empty():
				continue
			active_choices = visible_choices
			choices_presented.emit(visible_choices)
			return


func choose(choice_idx: int) -> void:
	if finished or choice_idx < 0 or choice_idx >= active_choices.size():
		return
	var picked: Dictionary = active_choices[choice_idx]
	active_choices.clear()
	var body: Array = picked.get("body", []) as Array
	if not body.is_empty():
		var prepended: Array[Dictionary] = []
		for b_v: Variant in body:
			prepended.append(b_v as Dictionary)
		prepended.append_array(_pending)
		_pending = prepended
	advance()


func eval_condition(expr: String) -> bool:
	var s: String = expr.strip_edges()
	if s.is_empty():
		return true
	if s.begins_with("not "):
		var key: String = s.substr(4).strip_edges()
		return not bool(state.get(key, false))
	if s.contains("=="):
		var parts: PackedStringArray = s.split("==", false, 1)
		if parts.size() == 2:
			var k: String = parts[0].strip_edges()
			var rhs: Variant = _parse_scalar(parts[1].strip_edges())
			return str(state.get(k, "")) == str(rhs)
	if s.contains("!="):
		var parts: PackedStringArray = s.split("!=", false, 1)
		if parts.size() == 2:
			var k: String = parts[0].strip_edges()
			var rhs: Variant = _parse_scalar(parts[1].strip_edges())
			return str(state.get(k, "")) != str(rhs)
	return bool(state.get(s, false))


func _next_step() -> Dictionary:
	if not _pending.is_empty():
		return _pending.pop_front() as Dictionary
	if current_section.is_empty() or not sections.has(current_section):
		return {}
	var list: Array = sections[current_section] as Array
	if step_index >= list.size():
		return {}
	var step: Dictionary = list[step_index] as Dictionary
	step_index += 1
	return step


# --- Parser --------------------------------------------------------------------------

static func parse(source: String) -> Dictionary:
	var out: Dictionary = {}
	var lines: PackedStringArray = source.replace("\r\n", "\n").split("\n")
	var current_name: String = ""
	var raw_lines: Array[String] = []
	for line: String in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("~ "):
			if not current_name.is_empty():
				out[current_name] = _parse_block(raw_lines, 0, raw_lines.size(), 0)
			current_name = trimmed.substr(2).strip_edges()
			raw_lines.clear()
		elif not current_name.is_empty():
			if trimmed.is_empty() or trimmed.begins_with("#") or trimmed.begins_with("//"):
				continue
			raw_lines.append(line)
	if not current_name.is_empty():
		out[current_name] = _parse_block(raw_lines, 0, raw_lines.size(), 0)
	return out


static func _parse_block(lines: Array[String], from_idx: int, to_idx: int, min_indent: int) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var i: int = from_idx
	while i < to_idx:
		var raw: String = lines[i]
		var indent: int = _indent_of(raw)
		if indent < min_indent:
			break
		var trimmed: String = raw.strip_edges()
		if trimmed.begins_with("- "):
			var choice_indent: int = indent
			var items: Array[Dictionary] = []
			while i < to_idx:
				var c_raw: String = lines[i]
				var c_indent: int = _indent_of(c_raw)
				var c_trim: String = c_raw.strip_edges()
				if c_indent != choice_indent or not c_trim.begins_with("- "):
					break
				var header: String = c_trim.substr(2).strip_edges()
				var meta: Dictionary = _extract_brackets(header)
				var clean_text: String = _unquote(String(meta["text"]))
				i += 1
				var body_start: int = i
				while i < to_idx and _indent_of(lines[i]) > choice_indent:
					i += 1
				var body: Array[Dictionary] = _parse_block(lines, body_start, i, choice_indent + 1)
				items.append({
					"text": clean_text,
					"condition": meta["condition"],
					"tags": meta["tags"],
					"body": body,
				})
			steps.append({"kind": "choices", "items": items})
			continue
		steps.append(_parse_command_or_line(trimmed))
		i += 1
	return steps


static func _parse_command_or_line(trimmed: String) -> Dictionary:
	if trimmed.begins_with("=> "):
		return {"kind": "jump", "target": trimmed.substr(3).strip_edges()}
	if trimmed.begins_with("set "):
		var rest: String = trimmed.substr(4).strip_edges()
		var eq: int = rest.find("=")
		if eq > 0:
			var key: String = rest.substr(0, eq).strip_edges()
			var val_s: String = rest.substr(eq + 1).strip_edges()
			return {"kind": "set", "key": key, "value": _parse_scalar(val_s)}
	if trimmed.begins_with("do "):
		var call_str: String = trimmed.substr(3).strip_edges()
		var open_p: int = call_str.find("(")
		var close_p: int = call_str.rfind(")")
		if open_p > 0 and close_p > open_p:
			var fn_name: String = call_str.substr(0, open_p).strip_edges()
			var arg: String = _unquote(call_str.substr(open_p + 1, close_p - open_p - 1).strip_edges())
			return {"kind": "do", "action": fn_name, "arg": arg}
		return {"kind": "do", "action": call_str, "arg": ""}
	var meta: Dictionary = _extract_brackets(trimmed)
	var body_text: String = String(meta["text"])
	var speaker: String = ""
	var line_text: String = body_text
	var colon: int = body_text.find(": ")
	if colon > 0 and colon < 36:
		speaker = body_text.substr(0, colon).strip_edges()
		line_text = body_text.substr(colon + 2).strip_edges()
	return {
		"kind": "line",
		"speaker": speaker,
		"text": _unquote(line_text),
		"tags": meta["tags"],
		"condition": meta["condition"],
		"line_id": meta["line_id"],
	}


static func _extract_brackets(text: String) -> Dictionary:
	var tags: Dictionary[String, String] = {}
	var condition: String = ""
	var line_id: String = ""
	var clean: String = text
	var search_from: int = 0
	while true:
		var open_idx: int = clean.find("[", search_from)
		if open_idx < 0:
			break
		var close_idx: int = clean.find("]", open_idx)
		if close_idx < 0:
			break
		var inner: String = clean.substr(open_idx + 1, close_idx - open_idx - 1).strip_edges()
		var matched: bool = false
		if inner.begins_with("#"):
			matched = true
			var tag_body: String = inner.substr(1).strip_edges()
			var eq: int = tag_body.find("=")
			if eq >= 0:
				tags[tag_body.substr(0, eq).strip_edges()] = tag_body.substr(eq + 1).strip_edges()
			else:
				tags[tag_body] = "true"
		elif inner.begins_with("if "):
			matched = true
			condition = inner.substr(3).strip_edges()
		elif inner.begins_with("ID:"):
			matched = true
			line_id = inner.substr(3).strip_edges()
		if matched:
			clean = (clean.substr(0, open_idx) + clean.substr(close_idx + 1)).strip_edges()
		else:
			search_from = close_idx + 1
	return {
		"text": clean,
		"tags": tags,
		"condition": condition,
		"line_id": line_id,
	}


static func _indent_of(raw: String) -> int:
	var count: int = 0
	for i: int in raw.length():
		var ch: String = raw.substr(i, 1)
		if ch == " ":
			count += 1
		elif ch == "\t":
			count += 4
		else:
			break
	return count


static func _unquote(s: String) -> String:
	var t: String = s.strip_edges()
	if t.length() >= 2 and ((t.begins_with("\"") and t.ends_with("\"")) or (t.begins_with("'") and t.ends_with("'"))):
		return t.substr(1, t.length() - 2)
	return t


static func _parse_scalar(s: String) -> Variant:
	var t: String = _unquote(s)
	if t == "true":
		return true
	if t == "false":
		return false
	if t.is_valid_int():
		return int(t)
	if t.is_valid_float():
		return float(t)
	return t


# --- Voice-Over Resolution & Cadence Synthesis ---------------------------------------

## Resolve an AudioStream for `line`:
## 1) Explicit `[#voice=res://...]` tag (when non-empty and exists)
## 2) `[ID:line_key]` -> `voice_dir/<line_key>.wav` or `.ogg` if present
## 3) Deterministic, speaker-pitched soft cadence `AudioStreamWAV` when `synth_fallback` is true.
static func resolve_voice(line: Dictionary, voice_dir: String = VOICE_DIR_DEFAULT, synth_fallback: bool = true) -> AudioStream:
	var tags: Dictionary = line.get("tags", {}) as Dictionary
	if tags.has("voice"):
		var explicit: String = String(tags.get("voice", "")).strip_edges()
		if not explicit.is_empty() and ResourceLoader.exists(explicit):
			return load(explicit) as AudioStream
	var lid: String = String(line.get("line_id", "")).strip_edges()
	if not lid.is_empty():
		for ext: String in [".wav", ".ogg"]:
			var candidate: String = "%s/%s%s" % [voice_dir, lid, ext]
			if ResourceLoader.exists(candidate):
				return load(candidate) as AudioStream
	if not synth_fallback:
		return null
	var speaker: String = String(line.get("speaker", ""))
	var text: String = String(line.get("text", ""))
	return _synth_cadence_wav(speaker, text)


static func _synth_cadence_wav(speaker: String, text: String) -> AudioStreamWAV:
	var base_hz: float = 132.0
	match speaker:
		"Drillmaster":
			base_hz = 112.0
		"Chronicler":
			base_hz = 156.0
		"Adventurer":
			base_hz = 138.0
		"Vanguard Captain":
			base_hz = 104.0
	var words: PackedStringArray = text.split(" ", false)
	var syllables: int = clampi(words.size(), 2, 7)
	var rate: int = 22050
	var syllable_s: float = 0.135
	var gap_s: float = 0.035
	var total_s: float = clampf(float(syllables) * (syllable_s + gap_s), 0.35, 1.35)
	var sample_count: int = int(total_s * float(rate))
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(sample_count * 2)
	var phase: float = 0.0
	var step_samples: int = int((syllable_s + gap_s) * float(rate))
	var active_samples: int = int(syllable_s * float(rate))
	for i: int in sample_count:
		var syl_idx: int = i / maxi(1, step_samples)
		var local_i: int = i % maxi(1, step_samples)
		var env: float = 0.0
		if local_i < active_samples:
			var u: float = float(local_i) / float(maxi(1, active_samples))
			env = sin(u * PI)
		var pitch_drop: float = 1.0 - 0.06 * (float(syl_idx) / float(maxi(1, syllables)))
		var freq: float = base_hz * pitch_drop * (1.0 + 0.03 * sin(float(syl_idx * 17)))
		phase += TAU * freq / float(rate)
		var wave: float = (sin(phase) * 0.65 + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.10)
		var sample_f: float = clampf(wave * env * 0.18, -1.0, 1.0)
		pcm.encode_s16(i * 2, int(roundf(sample_f * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = pcm
	return wav
