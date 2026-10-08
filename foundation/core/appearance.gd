@tool
class_name Appearance extends RefCounted
## A CHOSEN LOOK, AS TEXT (DECISIONS #166): what the `appearance` row holds and the character picker
## writes. "<variant>;<key>=<index>;..." — the look's file name (`EntityDefinition.visual_variants`),
## then the player's choices on top of it by option key, "ranger_f;skin=4;hair=2". Index 0 is never
## written: it is the look's own. What a key means is the look's (`apply_appearance`,
## `appearance_options` on the model); the foundation only spells and reads the text.

## The longest text the module takes (`module.rs` MAX_LOOK_LEN).
const MAX_LENGTH: int = 256
## Every character the module takes in a look.
const ALLOWED: String = "abcdefghijklmnopqrstuvwxyz0123456789_;=,.-"


## The variant it names: the text before the first `;`.
static func look_name(text: String) -> String:
	return text.get_slice(";", 0).strip_edges()


## The choices past the name, {key: index}. Anything that does not read as `key=<int>` is skipped.
static func choices(text: String) -> Dictionary:
	var out: Dictionary = {}
	var parts: PackedStringArray = text.split(";")
	for i: int in range(1, parts.size()):
		var kv: PackedStringArray = parts[i].split("=")
		if kv.size() == 2 and not kv[0].strip_edges().is_empty() and kv[1].strip_edges().is_valid_int():
			out[kv[0].strip_edges()] = int(kv[1])
	return out


## The text for a variant and choices: keys in sorted order, choices of 0 left out.
static func make(variant: String, picked: Dictionary) -> String:
	var keys: Array = picked.keys()
	keys.sort()
	var text: String = variant
	for k: Variant in keys:
		if int(picked[k]) > 0:
			text += ";%s=%d" % [String(k), int(picked[k])]
	return text


## Would the module take it? (Its own check is the one that counts.)
static func is_valid(text: String) -> bool:
	if text.length() > MAX_LENGTH:
		return false
	for c: String in text:
		if not ALLOWED.contains(c):
			return false
	return true
