class_name FightBot extends RefCounted
## TEST CODE. The probe players from Fishing for Compliments' tune probe — what each would press
## on a tick of the fight — the same decisions as the bots in `server/tests/fight.rs`.
##
## Used where a real fight has to be PLAYED rather than scripted: the integration suite plays one
## from a shell (`tools/fishing/fight_bot_cli.gd`) and submits it for the module to replay, and
## the fishing playtest plays one through the real input actions. Either way the log a bot makes
## goes through the client's simulation and the module's replay both — which is the claim.

enum Kind { ACE, GOOD, SLOPPY, MASHER, STUBBORN, REELER }


static func kind_named(name: String) -> Kind:
	match name:
		"good":
			return Kind.GOOD
		"sloppy":
			return Kind.SLOPPY
		"masher":
			return Kind.MASHER
		"stubborn":
			return Kind.STUBBORN
		"reeler":
			return Kind.REELER
		_:
			return Kind.ACE


## What `kind` presses this tick, as [pump (0/1), give (0/1), crank (0..255)].
##   ACE       dead centre every beat, gives line on every run, heaves every snag, cranks flat out
##   GOOD      inside the band, late in it
##   SLOPPY    lets go short of the band
##   MASHER    never lets go
##   STUBBORN  an ace who never gives line
##   REELER    only ever winds: never loads the rod, never gives line
## ACE and GOOD read the fish: while it rests after a run they wind, which is when the reel pays.
static func decide(kind: Kind, f: FightSim) -> PackedInt32Array:
	if not f.is_armed():
		return PackedInt32Array([0, 0, 0])   # let go of the click that set the hook
	if kind == Kind.MASHER:
		return PackedInt32Array([1, 0, 0])
	if kind == Kind.REELER:
		return PackedInt32Array([0, 0, 255])
	if f.behavior == FightSim.Behavior.RUNNING:
		return PackedInt32Array([0, 0, 255]) if kind == Kind.STUBBORN else PackedInt32Array([0, 1, 0])
	if f.behavior == FightSim.Behavior.SNAGGED:
		return PackedInt32Array([1, 0, 0])
	if f.slack > 0.001:
		return PackedInt32Array([0, 0, 255])
	if f.behavior == FightSim.Behavior.RESTING and (kind == Kind.ACE or kind == Kind.GOOD):
		return PackedInt32Array([0, 0, 255])
	if f.band_hi <= f.band_lo:
		return PackedInt32Array([0, 0, 255])
	var target: float
	match kind:
		Kind.GOOD:
			target = f.band_lo + (f.band_hi - f.band_lo) * 0.85
		Kind.SLOPPY:
			target = f.band_lo * 0.7
		_:
			target = (f.band_lo + f.band_hi) * 0.5
	return PackedInt32Array([1, 0, 0]) if f.load < target else PackedInt32Array([0, 0, 255])


## Play a whole fight: the log it made (runs of [ticks, flags, crank]) and the fight at its end.
static func play(kind: Kind, f: FightSim) -> Array[PackedInt32Array]:
	var log_runs: Array[PackedInt32Array] = []
	while f.state == FightSim.State.FIGHTING and f.ticks < FightSim.max_ticks():
		var d: PackedInt32Array = decide(kind, f)
		var flags: int = d[0] | (d[1] << 1)
		if not log_runs.is_empty() and log_runs[-1][1] == flags and log_runs[-1][2] == d[2]:
			log_runs[-1][0] += 1
		else:
			log_runs.append(PackedInt32Array([1, flags, d[2]]))
		f.tick(d[0] == 1, d[1] == 1, d[2])
	return log_runs
