@tool
class_name StatusDef extends ContentDef
## A STATUS (docs/FOUNDATION_SYSTEMS.md milestone 2, DECISIONS #206): a state an entity is in
## (injured, downed, carried, out), what it lets the entity do while in it, how long it lasts and
## what it becomes after. The server keeps who is in which (`status_state`); everything a status
## MEANS is here, so a designer makes a new one (a stashed chicken, a stunned fox) without code.
##
## Its NUMBER is what goes over the network: the foundation's are 0-99 (normal 0, injured 1, downed
## 2, carried 3, out 4, hidden 5, escaped 6), a genre's 100-255. A genre may REPLACE one of the
## foundation's by giving its own the same number (Fowl Play's downed crawls slower): the game uses
## the genre's, as a rule override replaces a rule's value. Nobody edits the foundation's files.
##
## The movement numbers are PARITY numbers: a player's game predicts its own movement with them and
## the server bounds it by the same ones (baked). Change one in a shipped build and bump `compat`.
## Everything under "How it shows" is presentation, never baked.

## Its number (0-99 the foundation's, 100-255 a genre's, or a foundation number to replace that one).
@export_range(0, 255) var status: int = 100
## How long it lasts on its own (0: until something changes it). A genre may set it for longer or
## shorter each time (`set_status_internal`); this is the length when it says nothing.
@export_range(0.0, 600.0, 0.1, "suffix:s") var lasts_s: float = 0.0
## What it becomes when that time is up (none: normal). A genre's `on_status_expired` may decide
## otherwise each time (a teammate is reviving).
@export var then_status: StatusDef

@export_group("Movement")
## Its speed, as a share of the character's own (1: unchanged, 0.25: a crawl, 0: cannot move).
@export_range(0.0, 3.0, 0.01) var speed: float = 1.0
## A burst at its start (a hit player running for it): speed times this, for `burst_s`.
@export_range(1.0, 3.0, 0.01) var burst: float = 1.0
@export_range(0.0, 10.0, 0.05, "suffix:s") var burst_s: float = 0.0
@export var can_sprint: bool = true
## Jumps and flaps.
@export var can_jump: bool = true
@export var can_dash: bool = true
## ON THE WING (DECISIONS #236): in this status a body holds itself this high (m) and flies there (an
## eagle's Take wing). 0: it walks. Presentation of the model's own branch: not baked to the server.
@export_range(0.0, 50.0, 0.1, "suffix:m") var hover_height: float = 0.0

@export_group("Play")
## May use things and abilities.
@export var can_act: bool = true
## May be used or aimed at by others (an escaped player is not there to hit).
@export var targetable: bool = true
## May be HIT by an ability its referee judges (DECISIONS #226): a downed player is not hit again,
## a pounce passes over them, though a teammate can still help them up (that is `targetable`).
@export var hittable: bool = true

@export_group("How it shows")
## The player watches a teammate instead of themself (out, escaped). Jump picks the next one.
@export var spectate: bool = false
## Its body is not drawn and does not collide (out, escaped). Presentation only: the server still
## sends where it is.
@export var hide_body: bool = false
## A clip from the character's AnimationSet held while in it, in place of walking (`downed`); a
## character without that clip moves as usual. Empty: none.
@export var pose: StringName = &""
## Shown over the head of whoever is in it, in its colour (and on the player's own HUD always).
@export var show_on_nameplate: bool = true
@export var color: Color = Color(1, 1, 1)

## The foundation's statuses (what `status` means unless a genre replaces it).
const NORMAL: int = 0
const INJURED: int = 1
const DOWNED: int = 2
const CARRIED: int = 3
const OUT: int = 4
const HIDDEN: int = 5
const ESCAPED: int = 6
## Where a genre's own start.
const GENRE_FROM: int = 100

## Number -> the PATH of the StatusDef this game uses for it (a genre's over the foundation's).
## Filled on first use while the game runs; the editor reads afresh each time (content is being
## edited there). Paths, not the resources, so this static never keeps a status alive on its own:
## Godot's resource cache holds each one while anything uses it.
static var _by_number: Dictionary = {}
## The statuses themselves, by number, while the game runs: kept, not loaded from their path on every
## `find` (DECISIONS #224, as `HoldDef._held`). Dropped on `clear_cache` and at exit.
static var _held: Dictionary = {}


func content_type() -> StringName:
	return &"status"


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"status": status,
		"lasts_ms": roundi(lasts_s * 1000.0),
		"then": ContentDef.ref(then_status),
		"speed": speed,
		"burst": burst,
		"burst_ms": roundi(burst_s * 1000.0),
		"can_sprint": can_sprint,
		"can_jump": can_jump,
		"can_dash": can_dash,
		"can_act": can_act,
		"targetable": targetable,
		"hittable": hittable,
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	var owner: String = ContentLibrary.owner_of_path(resource_path)
	if owner == ContentLibrary.FOUNDATION and status >= GENRE_FROM:
		out.append("it is the foundation's and numbered %d: the foundation's statuses are 0-%d" % [status, GENRE_FROM - 1])
	if then_status == self:
		out.append("it becomes itself when it ends: leave `then_status` empty for normal, or pick another")
	if burst_s > 0.0 and burst <= 1.0:
		out.append("its burst lasts %s s but adds no speed: set `burst` above 1, or `burst_s` to 0" % burst_s)
	if then_status != null and lasts_s <= 0.0:
		out.append("it becomes '%s' when it ends, but it never ends: give it `lasts_s`" % then_status.display_name)
	return out


## Two statuses of one owner with one number, or two genres with one; a genre's under 100 that
## replaces none of the foundation's (the build refuses the same: server/build/content.rs).
func validate_with(all_of_type: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	var mine: String = ContentLibrary.owner_of_path(resource_path)
	var replaces: bool = false
	for other: ContentDef in all_of_type:
		var o: StatusDef = other as StatusDef
		if o == null or o == self or o.status != status:
			continue
		var theirs: String = ContentLibrary.owner_of_path(o.resource_path)
		if theirs == mine:
			out.append("'%s' has the same number (%d) as '%s', of the same owner" % [display_name, status, o.display_name])
		elif theirs == ContentLibrary.FOUNDATION:
			replaces = true
		elif mine != ContentLibrary.FOUNDATION:
			out.append("'%s' (%s) and '%s' (%s) are both status %d" % [display_name, mine, o.display_name, theirs, status])
	if mine != ContentLibrary.FOUNDATION and status < GENRE_FROM and not replaces:
		out.append("'%s' is number %d, the foundation's range, but replaces none of its statuses: a genre's start at %d" % [display_name, status, GENRE_FROM])
	return out


## A copy beside the original (New from this) takes the owner's next free number; one replacing it
## (Copy into a genre) keeps its number, which is what makes it replace the foundation's.
func on_copied(owner: String, replacing: bool) -> void:
	if replacing:
		return
	var taken: Array[int] = []
	for d: ContentDef in ContentLibrary.items(&"status"):
		taken.append((d as StatusDef).status)
	var n: int = GENRE_FROM if owner != ContentLibrary.FOUNDATION else 1
	while taken.has(n) and n < 255:
		n += 1
	status = n


## Whether it changes nothing about how its entity moves.
func moves_as_usual() -> bool:
	return is_equal_approx(speed, 1.0) and (burst_s <= 0.0 or burst <= 1.0) and can_sprint and can_jump and can_dash and hover_height <= 0.0


## The movement config an entity in this status moves by: `cfg` with its speeds scaled (by the
## burst too, while `bursting`), and sprint, flaps and dash taken away when it cannot.
func apply_to(cfg: MovementConfig, bursting: bool = false) -> MovementConfig:
	if moves_as_usual():
		return cfg
	var k: float = speed * (maxf(burst, 1.0) if bursting else 1.0)
	var c: MovementConfig = cfg.duplicate() as MovementConfig
	c.walk_speed = cfg.walk_speed * k
	c.run_speed = cfg.run_speed * k
	c.sprint_speed = cfg.sprint_speed * k if can_sprint else c.run_speed
	# Its speed scales the gaits, not the dash (DECISIONS #256): a dash it allows is the whole dash, so a
	# slow status (a committed swing) can still roll out of it at full length.
	c.dash_impulse = cfg.dash_impulse if can_dash else 0.0
	if not can_jump:
		c.flap_charges = 0
	if hover_height > 0.0:
		c.hover_height = hover_height
	return c


## The input an entity in this status moves by: a press it cannot act on (jump, sprint, dash)
## is taken out, so the model neither jumps nor shows a sprint. The same frame unless one is.
func filter_input(frame: InputFrame) -> InputFrame:
	if (can_jump or not frame.jump) and (can_sprint or not frame.sprint) and (can_dash or not frame.dash):
		return frame
	var f: InputFrame = InputFrame.from_dict(frame.to_dict())
	f.jump = frame.jump and can_jump
	f.sprint = frame.sprint and can_sprint
	f.dash = frame.dash and can_dash
	return f


## Whether it is bursting `elapsed_s` after it began.
func bursting_at(elapsed_s: float) -> bool:
	return burst > 1.0 and elapsed_s >= 0.0 and elapsed_s < burst_s


# --- the game's statuses ------------------------------------------------------------------------

## The status this game has for number `n` (a genre's over the foundation's), or null.
static func find(n: int) -> StatusDef:
	if not Engine.is_editor_hint() and _held.has(n):
		return _held[n]
	var path: String = String(_table().get(n, ""))
	var s: StatusDef = load(path) as StatusDef if not path.is_empty() else null
	if s != null and not Engine.is_editor_hint():
		_held[n] = s
	return s


## Normal (status 0): what an entity with no status is in, and what an unknown number shows as.
static func normal() -> StatusDef:
	var s: StatusDef = find(NORMAL)
	if s == null:
		s = StatusDef.new()
		s.status = NORMAL
		s.display_name = "Normal"
		s.show_on_nameplate = false
	return s


## Every status this game has, by number.
static func all() -> Dictionary:
	var out: Dictionary = {}
	for n: int in _table():
		out[n] = find(n)
	return out


## Forget what was read (a suite that changes the content, or the genres).
static func clear_cache() -> void:
	_by_number.clear()
	_held.clear()


static func _table() -> Dictionary:
	if not _by_number.is_empty() and not Engine.is_editor_hint():
		return _by_number
	var out: Dictionary = {}
	# Only the status folders are loaded (not every piece of content), the foundation's first, then
	# each genre's in the game's order: a genre's replaces the foundation's of the same number.
	for f: Dictionary in ContentLibrary.files():
		var folder: String = ContentLibrary.folder_for(&"status", String(f["owner"])) + "/"
		if not String(f["path"]).begins_with(folder):
			continue
		var s: StatusDef = load(String(f["path"])) as StatusDef
		if s == null:
			continue
		var held: String = String(out.get(s.status, ""))
		if held.is_empty() or ContentLibrary.owner_of_path(held) == ContentLibrary.FOUNDATION:
			out[s.status] = s.resource_path
	_by_number = out
	return out
