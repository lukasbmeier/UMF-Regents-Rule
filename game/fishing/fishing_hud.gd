extends Control
## GENRE CODE. The fishing HUD: what to do next, the cast's charge and where it will land, the
## bite, the catch banner, the live leaderboard while a round is played, and the results after.
##
## The ring on the water is drawn in the world (`FishingFx`); this names it — which spot, what it
## is known for, how far — and says why a cast will not go. Everything it shows is read off the
## local angler's components; the only thing it sends is a shop purchase.

## How long a notice (a refusal, a lost line, a purchase) stays on screen.
const NOTICE_SECONDS: float = 3.0
## How long a catch's banner stays up.
const CATCH_SECONDS: float = 5.0
## Mirrors SessionComponent.Phase.
## The session kind fishing's rounds run as (`shared/rules.json` names its phases).
const _SESSION_KIND: int = 0
## The shop's three keys. Registered in project.godot next to the movement actions.
const _SHOP_KEYS: Array[StringName] = [&"shop_buy_1", &"shop_buy_2", &"shop_buy_3"]
const _SHOP_KEY_LABELS: Array[String] = ["1", "2", "3"]
## How often the standings are rebuilt. Scores change a few times a minute, not every frame.
const STANDINGS_SECONDS: float = 0.25
## Rows on the live board. The results panel lists everyone.
const BOARD_ROWS: int = 5
const _LOCAL_TINT: Color = Color(1.0, 0.86, 0.45)
## The HUD's own sounds: things that happen to the PLAYER rather than somewhere in the world.
## Splashes and casts belong to the world and are played there, by FishingFx.
const SFX_HIT: AudioStream = preload("res://game/fishing/sfx/reel_hit.wav")
const SFX_MISS: AudioStream = preload("res://game/fishing/sfx/reel_miss.wav")
const SFX_COIN: AudioStream = preload("res://game/fishing/sfx/coin.wav")
const SFX_ROUND_START: AudioStream = preload("res://game/fishing/sfx/round_start.wav")
const SFX_ROUND_END: AudioStream = preload("res://game/fishing/sfx/round_end.wav")
const _DIM_TINT: Color = Color(1.0, 1.0, 1.0, 0.5)
## The fight gauge's distance from the screen's right edge; how far above the bottom its foot is
## (clear of the prompt, whose top is 128 px up, and the hook-set bar under it); and the window it is
## drawn full size in. A smaller window shrinks it, no smaller than GAUGE_MIN_SCALE.
const GAUGE_MARGIN: float = 24.0
const GAUGE_FOOT: float = 140.0
const GAUGE_FULL_AT: Vector2 = Vector2(1280.0, 720.0)
const GAUGE_MIN_SCALE: float = 0.6

@onready var _prompt: Label = $Prompt
@onready var _banner: Label = $Banner
@onready var _status: Label = $Status
@onready var _bar: Control = $Bar
@onready var _crosshair: Control = $Crosshair
@onready var _board: Control = $Board
@onready var _board_grid: GridContainer = $Board/VBox/Grid
@onready var _results: Control = $Results
@onready var _results_title: Label = $Results/VBox/Title
@onready var _results_winner: Label = $Results/VBox/Winner
@onready var _results_grid: GridContainer = $Results/VBox/Grid
@onready var _results_footer: Label = $Results/VBox/Footer

var _entity: SpaceTimeEntity
var _fishing: FishingComponent
var _session: SessionComponent
var _inventory: SpaceTimeInventoryComponent
var _gear: GearComponent
var _gauge: ReelGauge = null
var _press_voice: AudioStreamPlayer = null
var _ui_voice: AudioStreamPlayer = null
## What the HUD has played, by name. For tests: a sound is otherwise only checkable by ear.
var _sfx_counts: Dictionary[StringName, int] = {}
var _notice: String = ""
var _notice_left: float = 0.0
## The last standings built, best first (FishingStandings.build).
var _standings: Array[Dictionary] = []
var _standings_left: float = 0.0
## What each panel last drew, so it is rebuilt — and printed — only when something changed.
var _board_drawn: String = ""
var _results_drawn: String = ""
## THE JOURNAL (DECISIONS #171): a page of the Escape menu, its button added there and J opens it.
const ACTION_JOURNAL: StringName = &"open_journal"
var _journal: CatchJournal = null


func _ready() -> void:
	SignalBus.entity_spawned.connect(_on_entity_spawned)
	SignalBus.entity_despawned.connect(_on_entity_despawned)
	SignalBus.session_phase_changed.connect(_on_phase_changed)
	_bar.draw.connect(draw_bar)
	_crosshair.draw.connect(draw_crosshair)
	# The cursor coming and going changes what the prompt should say, and whether aiming is
	# even possible — so the HUD is told rather than polling.
	MouseCapture.capture_changed.connect(func(_c: bool) -> void: _crosshair.queue_redraw())
	set_process(true)
	_press_voice = AudioStreamPlayer.new()
	_press_voice.name = "PressVoice"
	_press_voice.bus = Settings.BUS_EFFECTS
	add_child(_press_voice)
	_ui_voice = AudioStreamPlayer.new()
	_ui_voice.name = "UiVoice"
	_ui_voice.bus = Settings.BUS_EFFECTS
	_ui_voice.volume_db = -3.0
	add_child(_ui_voice)
	_banner.text = ""
	_status.text = "connecting…"
	# THE FIGHT'S GAUGE (DECISIONS #144, #161): on the right, its foot just above the prompt, so the
	# prompt and the hook-set bar along the bottom are never under it (they were, in a small window).
	_gauge = ReelGauge.new()
	_gauge.name = "ReelGauge"
	add_child(_gauge)
	_gauge.anchor_left = 1.0
	_gauge.anchor_right = 1.0
	_gauge.anchor_top = 1.0
	_gauge.anchor_bottom = 1.0
	_gauge.offset_left = -ReelGauge.SIZE.x - GAUGE_MARGIN
	_gauge.offset_right = -GAUGE_MARGIN
	_gauge.offset_top = -ReelGauge.SIZE.y - GAUGE_FOOT
	_gauge.offset_bottom = -GAUGE_FOOT
	_gauge.pivot_offset = ReelGauge.SIZE
	_gauge.visible = false
	_fit_gauge()
	get_viewport().size_changed.connect(_fit_gauge)
	# Fishing's own keys in the settings, so a player can rebind them (DECISIONS #165).
	for k: Array in [[&"fish_cast", "Cast, reel, heave"], [&"fish_give", "Give line"],
			[ACTION_JOURNAL, "Journal"], [&"shop_buy_1", "Buy a rod (shop)"],
			[&"shop_buy_2", "Buy a reel (shop)"], [&"shop_buy_3", "Buy a line (shop)"]]:
		if InputMap.has_action(k[0]):
			Settings.define_key(k[0], k[1], "Fishing")
	_journal = CatchJournal.new()
	_add_journal_button.call_deferred()


## The fight's gauge, for tests.
func reel_gauge() -> ReelGauge:
	return _gauge


## Shrink the gauge to a small window, about its bottom-right corner (which stays put).
func _fit_gauge() -> void:
	var view: Vector2 = get_viewport_rect().size
	var k: float = clampf(minf(view.x / GAUGE_FULL_AT.x, view.y / GAUGE_FULL_AT.y), GAUGE_MIN_SCALE, 1.0)
	_gauge.scale = Vector2(k, k)


## Latch onto the local player's components once it spawns.
func _on_entity_spawned(entity_id: int, _kind: int) -> void:
	if not EntityRegistry.is_local(entity_id):
		return
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(entity_id) as SpaceTimeEntity
	if ent == null:
		return
	_entity = ent
	_fishing = ent.find_component(FishingComponent) as FishingComponent
	_session = ent.find_component(SessionComponent) as SessionComponent
	_inventory = ent.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	_gear = ent.find_component(GearComponent) as GearComponent
	if _gear != null:
		_gear.purchase_refused.connect(_on_notice)
		_gear.purchase_succeeded.connect(_on_purchase_succeeded)
	if _fishing != null:
		_fishing.cast_refused.connect(_on_notice)
		_fishing.line_lost.connect(_on_notice)
		_fishing.catch_landed.connect(_on_catch_landed)
		_fishing.hookset_graded.connect(_on_hookset_graded)
		_fishing.bite_started.connect(_on_bite)
		_fishing.fight_started.connect(_on_fight_started)
		_fishing.pumped.connect(_on_pumped)


## The local player left the world: a disconnect, or the Escape menu's Disconnect. Every
## reference above points at a node that is about to be freed, and a HUD that kept reading them
## would fill the log with errors behind the connect screen. Forget them all; the next spawn
## latches on afresh.
func _on_entity_despawned(entity_id: int) -> void:
	if _entity == null or not is_instance_valid(_entity) or _entity.entity_id != entity_id:
		return
	_entity = null
	_fishing = null
	_session = null
	_inventory = null
	_gear = null
	_standings = []
	_board.visible = false
	_results.visible = false
	_board_drawn = ""
	_results_drawn = ""
	_notice = ""
	_notice_left = 0.0
	_banner.text = ""
	_prompt.text = ""
	_bar.queue_redraw()
	_crosshair.queue_redraw()


func _process(delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice = ""
			_banner.text = ""
	_standings_left -= delta
	if _standings_left <= 0.0:
		_standings_left = STANDINGS_SECONDS
		_refresh_standings()
	_update_status()
	_bar.queue_redraw()
	var f: FightSim = _fishing.fight() if _fishing != null else null
	_gauge.visible = f != null
	if f != null:
		_gauge.show_fight(f, _fishing.crank(), delta)


## The journal's button in the Escape menu (boot builds the menu before this runs; deferred anyway).
func _add_journal_button() -> void:
	var menu: PauseMenu = PauseMenu.find(get_tree())
	if menu == null or _journal == null:
		return
	menu.add_child(_journal)   # the menu's from now on: it shows it, and frees it with itself
	var b: Button = menu.add_button("Journal")
	b.pressed.connect(func() -> void: menu.open_page(_journal))


## The journal page (tests open it).
func journal() -> CatchJournal:
	return _journal


func _exit_tree() -> void:
	# No menu took the page (a HUD on its own, in a test): it is ours to free.
	if _journal != null and _journal.get_parent() == null:
		_journal.free()
		_journal = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_JOURNAL) and _entity != null and MouseCapture.is_captured():
		var menu: PauseMenu = PauseMenu.find(get_tree())
		if menu != null and _journal != null:
			get_viewport().set_input_as_handled()
			menu.show_page(_journal)
			return
	# The shop, between rounds. 1/2/3 rather than a mouse UI because the cursor belongs to
	# looking around (DECISIONS #89) and a shop that stole it mid-session would be worse than
	# three keys. The server is the one that decides whether a buy is allowed; these keys only
	# ask, and a refusal comes back as a notice rather than as nothing happening.
	if _shop_open():
		for i: int in range(3):
			if event.is_action_pressed(_SHOP_KEYS[i]):
				get_viewport().set_input_as_handled()
				_gear.request_buy(i as GearComponent.Kind)
				return


# --- fishing events -------------------------------------------------------------------

func _on_notice(text: String) -> void:
	_notice = text
	_notice_left = NOTICE_SECONDS
	_banner.text = text


func _on_bite() -> void:
	_on_notice("BITE!")


func _on_hookset_graded(grade: int, reaction: float) -> void:
	var hooked: bool = grade != FishingData.HookSet.NONE
	_play(_press_voice, SFX_HIT if hooked else SFX_MISS, &"press_hit" if hooked else &"press_miss")
	if hooked:
		_on_notice("%s hook-set  (%.2f s)" % [FishingData.hookset_word(grade).capitalize(), reaction])


func _on_fight_started(_key: String) -> void:
	_on_notice("FISH ON!")
	_gauge.reset()


func _on_pumped(grade: int, _metres: float) -> void:
	var f: FightSim = _fishing.fight() if _fishing != null else null
	if grade == FightSim.Grade.PERFECT:
		_play(_press_voice, SFX_HIT, &"pump_perfect")
		if f != null and f.combo >= 2:
			_on_notice("PERFECT  ×%d" % f.combo)
	else:
		_play(_press_voice, SFX_MISS, &"pump")


func _on_catch_landed(c: Dictionary) -> void:
	var def: Dictionary = FishingData.catch_def(str(c["key"]))
	var text: String = "%s — %.2f kg  ·  +%d coins" % [def.get("name", c["key"]), float(c["kg"]),
		int(c["coins"])]
	if int(c.get("best_combo", 0)) >= 2:
		text += "  ·  combo ×%d" % int(c["best_combo"])
	if bool(c.get("clean", false)):
		text += "  ·  clean"
	if bool(c["deadlift"]):
		text += "  ·  DEADLIFT, double coins!"
	_notice = text
	_notice_left = CATCH_SECONDS
	_banner.text = text


func _on_purchase_succeeded(kind: int) -> void:
	_play(_ui_voice, SFX_COIN, &"coin")
	_on_notice("Bought the %s" % _gear.item_name(kind as GearComponent.Kind))


func _on_phase_changed(_sid: int, old_phase: int, new_phase: int, _ends: int) -> void:
	# Bells mark the round, and only a real transition rings one: the first phase this client
	# learns about (old -1) is where it came in, not something that just happened.
	if old_phase < 0:
		return
	if new_phase == SessionComponent.Phase.PLAYING:
		_play(_ui_voice, SFX_ROUND_START, &"round_start")
		var cond: FishingConditions = FishingConditions.find(get_tree())
		if cond != null and cond.known:
			_on_notice(cond.describe())
	elif new_phase == SessionComponent.Phase.RESULTS:
		_play(_ui_voice, SFX_ROUND_END, &"round_end")


# --- presentation ---------------------------------------------------------------------

## True when the shop is open AND we have something to open it with.
func _shop_open() -> bool:
	return _gear != null and _session != null \
		and _session.get_phase() == SessionComponent.Phase.SHOP


func _gear_line() -> String:
	if _gear == null:
		return ""
	return "  •  %s · %s · %s" % [_gear.item_name(GearComponent.Kind.ROD),
		_gear.item_name(GearComponent.Kind.REEL), _gear.item_name(GearComponent.Kind.LINE)]


## What each upgrade is and costs right now, or that it is maxed. Prices come from the same file
## the server charges from (FishingData); the server charges them.
func _shop_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(3):
		var kind: GearComponent.Kind = i as GearComponent.Kind
		var cost: int = _gear.next_cost(kind)
		var label: String = "%s) %s: " % [_SHOP_KEY_LABELS[i], GearComponent.name_of(kind)]
		if cost < 0:
			parts.append(label + "MAX")
		else:
			var opens: String = ""
			if kind == GearComponent.Kind.ROD:
				# FfC: "'cast 32m -> 40m' is a number; 'opens The Marina' is a reason."
				var names: PackedStringArray = FishingData.spots_opened_by(_gear.rod_tier() + 1, _bake())
				opens = "" if names.is_empty() else " (reaches %s)" % ", ".join(names)
			parts.append(label + "%s %d%s%s" % [_gear.next_name(kind), cost, opens,
				" ✗" if cost > _session.get_coins() else ""])
	return "SHOP — " + "   ".join(parts)


## The level's bake, for the spots' names; null in a scene without a fishing level.
func _bake() -> LevelBake:
	if not is_inside_tree():
		return null
	var level: LakesideLevel = get_tree().get_first_node_in_group(LakesideLevel.GROUP) as LakesideLevel
	return level.bake() if level != null else null


func _update_status() -> void:
	if _session == null:
		_status.text = _connection_line()
		return
	var phase_name: String = Rules.phase_name(_SESSION_KIND, _session.get_phase()).to_upper()
	if phase_name.is_empty():
		phase_name = "PHASE %d" % _session.get_phase()
	# The round's time of day and weather (DECISIONS #168), the server's.
	var cond: FishingConditions = FishingConditions.find(get_tree())
	var weather: String = "  •  " + cond.words() if cond != null and cond.known else ""
	_status.text = "%s%s  •  %s  •  %d pts  •  %d coins%s" % [
		phase_name, weather, "waiting for players" if _session.is_waiting() \
			else "%ds left" % int(maxf(0.0, _session.seconds_remaining())), _session.get_score(),
		_session.get_coins(), _gear_line()]

	# Order matters: the most immediate thing the player has to do comes first.
	var rig: FishingComponent.Rig = _fishing.rig() if _fishing != null else FishingComponent.Rig.READY
	if MouseCapture.is_wanted() and not MouseCapture.is_captured():
		_prompt.text = "Click in the window to look around   ·   Esc frees the mouse"
	elif _shop_open():
		_prompt.text = _shop_line()
	elif _session.get_phase() == SessionComponent.Phase.RESULTS:
		_prompt.text = "Round over — the shop opens in %ds" % _seconds_left()
	elif _session.get_phase() == SessionComponent.Phase.LOBBY:
		var next: String = cond.describe() if cond != null and cond.known else ""
		var starts: String = "The match starts when everyone is ready" if _session.is_waiting() \
			else "Next round starts in %ds" % _seconds_left()
		_prompt.text = "%s%s" % [starts, "" if next.is_empty() else "  —  " + next]
	elif _session.get_phase() != SessionComponent.Phase.PLAYING:
		_prompt.text = "Fishing opens in the PLAYING phase"
	elif _fishing == null:
		_prompt.text = ""
	else:
		match rig:
			FishingComponent.Rig.READY:
				_prompt.text = "Hold the left mouse button to cast · let go to throw"
			FishingComponent.Rig.CHARGING:
				_prompt.text = _aim_line()
			FishingComponent.Rig.FLYING:
				_prompt.text = ""
			FishingComponent.Rig.WAITING:
				_prompt.text = "Waiting for a bite…   (click to reel in)"
			FishingComponent.Rig.STRIKE:
				_prompt.text = "BITE! Click now!"
			FishingComponent.Rig.FIGHTING:
				_prompt.text = _fight_line()
			FishingComponent.Rig.RESOLVING:
				_prompt.text = "…"


## What the fight wants from the player right now, and how far out it still is.
func _fight_line() -> String:
	var f: FightSim = _fishing.fight()
	if f == null:
		return ""
	var what: String
	if f.behavior == FightSim.Behavior.RUNNING:
		what = "IT'S RUNNING — hold the right button to give line!"
	elif f.behavior == FightSim.Behavior.SNAGGED:
		what = "SNAGGED — hold the left button to heave it free"
	elif f.cranking():
		what = "Reel in the slack — scroll, or circle the mouse"
	elif f.load > 0.0:
		what = "Too far — let go!" if f.is_overloaded() else "…let go in the sweet spot"
	elif f.behavior == FightSim.Behavior.RESTING:
		what = "It's resting — reel it in!"
	elif f.reel_pays() >= ReelGauge.PAYS_WELL:
		what = "It's tiring — reel, or heave"
	else:
		what = "Hold the left button to bend the rod"
	return "%s   ·   %.1f m" % [what, f.line_out_m()]


## Under the ring, while charging: where it will land, or why it will not.
func _aim_line() -> String:
	var a: Dictionary = _fishing.aim()
	if not bool(a["valid"]):
		return str(a["reason"])
	var spot: Dictionary = a["spot"] as Dictionary
	var where: String = str(spot.get("name", "Open water"))
	var words: PackedStringArray = FishingData.favoured_words(str(spot.get("id", "")))
	var line: String = "%s — %s  ·  %.0f m" % [where, ", ".join(words), float(a["range"])]
	# FfC's gate, said where the player is looking: what a better rod would reach this way.
	var beyond: Dictionary = a.get("beyond", {}) as Dictionary
	if not beyond.is_empty():
		var needs: Dictionary = FishingData.gear("rod", FishingData.min_rod(str(beyond.get("id", ""))))
		line += "      (%s is further out: the %s reaches it)" % [str(beyond.get("name", "?")),
			str(needs.get("name", "a better rod"))]
	return line


## Called by the bar child's draw signal: the charge while charging, the closing hook-set window
## once it bites, nothing otherwise.
func draw_bar() -> void:
	if _fishing == null:
		return
	var size: Vector2 = _bar.size
	match _fishing.rig():
		FishingComponent.Rig.CHARGING:
			_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.11, 0.8))
			var ok: bool = bool(_fishing.aim()["valid"])
			var fill: Color = Color(0.45, 0.95, 0.55, 0.9) if ok else Color(1.0, 0.45, 0.35, 0.9)
			_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * _fishing.charge(), size.y)), fill)
		FishingComponent.Rig.STRIKE:
			var left: float = _fishing.strike_left()
			_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.11, 0.8))
			_bar.draw_rect(Rect2(Vector2(size.x * (1.0 - left) * 0.5, 0.0),
				Vector2(size.x * left, size.y)), Color(1.0, 0.82, 0.25, 0.95))
		_:
			pass   # the fight has its own gauge (ReelGauge)


## A plain crosshair: the cast goes where the camera looks. Hidden while the cursor is free (there
## is nothing to aim).
func draw_crosshair() -> void:
	var c: Vector2 = _crosshair.size * 0.5
	if MouseCapture.is_wanted() and not MouseCapture.is_captured():
		return
	var tint := Color(1, 1, 1, 0.45)
	_crosshair.draw_arc(c, 6.0, 0.0, TAU, 24, tint, 1.5)
	_crosshair.draw_circle(c, 1.5, tint)


# --- sound --------------------------------------------------------------------------------

func _play(voice: AudioStreamPlayer, stream: AudioStream, what: StringName) -> void:
	_sfx_counts[what] = _sfx_counts.get(what, 0) + 1
	voice.stream = stream
	voice.play()


## How many times the HUD played `what`. For tests.
func sfx_count(what: StringName) -> int:
	return _sfx_counts.get(what, 0)


# --- standings ------------------------------------------------------------------------

## Who is winning, rebuilt a few times a second. The live board while a round is PLAYED; the
## results once it is over, through RESULTS and on into the SHOP, where the scores still stand
## (they reset only when the next round starts, `advance_phases`).
func _refresh_standings() -> void:
	var phase: int = _session.get_phase() if _session != null else -1
	var over: bool = phase == SessionComponent.Phase.RESULTS or phase == SessionComponent.Phase.SHOP
	var playing: bool = phase == SessionComponent.Phase.PLAYING
	if _session == null or not _session.is_in_session() or not (over or playing):
		_board.visible = false
		_results.visible = false
		return
	_standings = FishingStandings.build(_session.get_session_id(), _session.get_round())
	_board.visible = playing
	_results.visible = over
	if playing:
		_draw_board()
	else:
		_draw_results(phase)


## Top few and, if they are not among them, you.
func _draw_board() -> void:
	var shown: Array[int] = []
	for i: int in range(mini(BOARD_ROWS, _standings.size())):
		shown.append(i)
	var mine: int = _local_rank()
	if mine >= BOARD_ROWS:
		shown.append(mine)
	var parts: PackedStringArray = PackedStringArray()
	for i: int in shown:
		parts.append("%d. %s %d" % [i + 1, _standings[i]["name"], _standings[i]["score"]])
	var drawn: String = "  ".join(parts)
	if drawn == _board_drawn:
		return
	_board_drawn = drawn
	# Printed for the same reason the nameplate prints: what one client knows about ANOTHER
	# client's score is only checkable with two processes, and they can only compare logs.
	print("[Board] ", drawn)
	_clear(_board_grid)
	for i: int in shown:
		var row: Dictionary = _standings[i]
		var tint: Color = _LOCAL_TINT if bool(row["is_local"]) else Color.WHITE
		_cell(_board_grid, "%d." % (i + 1), _DIM_TINT, 14)
		_cell(_board_grid, String(row["name"]), tint, 14)
		_cell(_board_grid, str(row["score"]), tint, 14, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_results(phase: int) -> void:
	_results_footer.text = "The shop opens in %ds" % _seconds_left() \
		if phase == SessionComponent.Phase.RESULTS \
		else "Shop open: 1 / 2 / 3 to buy  ·  next round in %ds" % _seconds_left()
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(_standings.size()):
		var row: Dictionary = _standings[i]
		var has_best: bool = not str(row["best_catch"]).is_empty()
		parts.append("%s %s %d (%d caught%s)" % [FishingStandings.ordinal(i + 1), row["name"],
			row["score"], row["catches"], ", best " + _best_text(row) if has_best else ""])
	# The round of the MATCH (DECISIONS #182); the standings are filed under the session's own count.
	var drawn: String = "round %d: %s" % [_session.get_match_round(), " · ".join(parts)]
	if drawn == _results_drawn:
		return
	_results_drawn = drawn
	print("[Results] ", drawn)

	_results_title.text = "Round %d results" % _session.get_match_round()
	_results_winner.text = _winner_line()
	_clear(_results_grid)
	for header: String in ["", "Angler", "Points", "Caught", "Best catch"]:
		_cell(_results_grid, header, _DIM_TINT, 13)
	for i: int in range(_standings.size()):
		var row: Dictionary = _standings[i]
		var tint: Color = _LOCAL_TINT if bool(row["is_local"]) else Color.WHITE
		_cell(_results_grid, FishingStandings.ordinal(i + 1), tint, 16)
		_cell(_results_grid, String(row["name"]) + ("  (you)" if bool(row["is_local"]) else ""),
			tint, 16)
		_cell(_results_grid, str(row["score"]), tint, 16, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(_results_grid, str(row["catches"]), tint, 16, HORIZONTAL_ALIGNMENT_RIGHT)
		var best: String = str(row["best_catch"])
		_cell(_results_grid, _best_text(row) if not best.is_empty() else "—",
			FishingFx.rarity_color(FishingData.rarity_of(best)) if not best.is_empty() else _DIM_TINT, 16)


func _winner_line() -> String:
	if _standings.is_empty() or int(_standings[0]["score"]) <= 0:
		return "Nobody landed anything this round"
	var top: Dictionary = _standings[0]
	var tied: bool = _standings.size() > 1 and int(_standings[1]["score"]) == int(top["score"])
	if tied:
		return "A tie at the top on %d points" % int(top["score"])
	if bool(top["is_local"]):
		return "You win with %d points!" % int(top["score"])
	return "%s wins with %d points" % [top["name"], int(top["score"])]


func _best_text(row: Dictionary) -> String:
	var def: Dictionary = FishingData.catch_def(str(row["best_catch"]))
	return "%s %.2f kg" % [def.get("name", row["best_catch"]), float(row["best_kg"])]


## Index of the local player in the standings, or -1.
func _local_rank() -> int:
	for i: int in range(_standings.size()):
		if bool(_standings[i]["is_local"]):
			return i
	return -1


func _seconds_left() -> int:
	return int(ceilf(maxf(0.0, _session.seconds_remaining()))) if _session != null else 0


## What the leaderboard and the results panel currently hold. For tests.
func standings() -> Array[Dictionary]:
	return _standings


func _cell(grid: GridContainer, text: String, tint: Color, font_size: int,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = tint
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", font_size)
	grid.add_child(l)


static func _clear(grid: GridContainer) -> void:
	for c: Node in grid.get_children():
		grid.remove_child(c)
		c.queue_free()


## Before the local player exists: what the connection is doing.
func _connection_line() -> String:
	match SpaceTimeSync.state:
		SpaceTimeSync.ConnectionState.CONNECTED:
			return "joining…"
		SpaceTimeSync.ConnectionState.CONNECTING:
			return "connecting…"
		SpaceTimeSync.ConnectionState.RECONNECTING:
			return "reconnecting…"
		_:
			return "not connected"
