"""Write shared/fishing/fight.json: THE PUMP's tuning, and a fight profile for every catch.

    python tools/fishing/gen_fight.py

The fight is Fishing for Compliments' fifth and final one ("v5: THE PUMP", its
design/data/fight.toml tells why the first four went). This file carries two things:

  params    the fight's numbers, as FfC PLAYED them. Its fight.toml documents a set that had
            drifted from what the game ran (pump_stress 0.50 against a live 0.72, give_run_damping
            0.45 against 0.28): the toml was never loaded, and its own maxim — "two copies of a
            number are two numbers" — applies to it. These are FightParams' values, the ones the
            playtests and the tune probe measured.
  profiles  what each catch in shared/fishing/fishing.json IS in a fight: its band, its pull,
            its wind. FfC tuned eight by play and fitted curves through them for the rest; the
            curves are reproduced here, on this catalogue's weights, with the four tuned species
            this catalogue shares (bluegill, bass, pike, sturgeon) restored verbatim.

THE CURVES ARE EVALUATED HERE, NOT AT RUNTIME. They take a logarithm of the weight, and the fight
is simulated twice — by the client, for feel, and by the module, to decide what really happened
(server/src/genre/fight.rs and game/fishing/fight_sim.gd, bit for bit). A transcendental is the
one thing two languages are not guaranteed to agree on; a number in a file is. Every value is
rounded to 4 decimals so the file reads as tuning rather than as noise.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "shared" / "fishing" / "fishing.json"
OUT = ROOT / "shared" / "fishing" / "fight.json"

# The simulation steps at a fixed rate, whatever the frame rate: the input log is one entry per
# tick, and a replay is only a replay if both sides cut time the same way.
TICK_HZ = 60
# The longest fight the module will replay. FfC's slowest clean catch (a sturgeon, a jet ski)
# ran ~30 s; a poor one twice that. Past this the line is cut.
MAX_FIGHT_S = 120.0

PARAMS = {
    # --- distance -------------------------------------------------------------------------
    "distance_rate": 12.0,        # drift and slip only; pumps are metres directly
    "give_factor_idle": 0.06,     # what a fish takes back between beats
    "give_factor_dead": 0.0,      # junk does not swim off; it sits there being heavy
    # THE CAST IS THE FIGHT LENGTH (FfC's rig): 0.9 of the range, clamped at the bottom so a short
    # lob is still a fight, and at the top so it stays inside the range the sim was tuned against
    # (FfC's cast_distance_m, 40). Each catch then scales it by its own distance_scale.
    "cast_to_fight": 0.9,
    "fight_min_m": 10.0,
    "fight_max_m": 40.0,
    # --- the arc ----------------------------------------------------------------------------
    "spent_power_floor": 0.30,    # a spent catch fights at 30%: the fight gets a third act
    "spent_wind_penalty": 2.2,    # and gets its wind back slower, so runs thin out
    # --- the line ---------------------------------------------------------------------------
    "drag_setting": 0.62,         # where the clutch starts slipping
    "tension_response": 3.2,      # a PROPORTIONAL chase, never move_toward
    "tension_release": 2.4,
    "drag_slip": 9.0,
    "slip_metres": 1.2,           # metres paid out per unit of slipped tension
    "drag_slip_max": 1.4,         # the spool can only give so fast: the fail state
    "shock_gain": 1.5,            # danger from the CATCH's pull alone
    "shock_threshold": 0.35,
    "snap_grace_seconds": 0.35,
    "snap_tension": 1.0,          # the line's ceiling; the line track raises it
    "overload_fatigue": 0.42,     # ~2.4 s of continuous overload breaks a fresh line
    "fatigue_recover": 0.35,
    "bare_reel_fraction": 0.12,   # winding with no slack on offer, against a FRESH fish: badly
    "bare_reel_tension": 0.40,
    # REEL ANY TIME; IT PAYS WHEN THE FISH IS SPENT (Luke, after playing it: "I should be able to
    # reel anytime but it should only reward a lot of distance at little cost of tension if the
    # fish is worn out"). A bare reel wins more line, and strains the line less, the more the
    # fish is spent; a resting fish counts as spent. Winding against a RUN wins nothing and loads
    # the line hard. A pure reeler never tires a fish, so heaving still beats winding.
    "spent_reel_fraction": 0.45,  # share of the crank rate against a fully spent fish
    "rest_reel_fraction": 0.50,   # ...and while it rests after a run. At 0.75 one rest wound in
                                  # 20 m on the best reel and the fight ended in it; at 0.50 an
                                  # ace's fights stay near FfC's tuned lengths (`reel_probe`)
    "spent_reel_strain": 0.20,    # how much of the reel's load reaches the line when spent
    "run_reel_strain": 2.25,      # ...and when winding against a run

    "pull_response": 1.5,         # the catch's pull eases rather than switching
    # --- the pump ---------------------------------------------------------------------------
    "load_rate": 0.62,            # a full lift is about two seconds of leaning on it
    "load_slow_start": 0.35,      # ...off the bottom at 35% and accelerating into the band
    # THE YELLOW: from the band's edge to its sweet spot takes at least this long. FfC let the lift
    # run into the band at full speed ("a top end that arrives faster than you expect"); with the
    # band hidden, a fresh pike showed amber for 0.13 s before the sweet spot, and a sturgeon
    # 0.10 s — a flash, not a warning. 0 is FfC's lift. Measured with
    # `cargo test --test fight approach -- --ignored --nocapture`: 0.35 s costs an ace 1-2 s a
    # fight (a sturgeon 37.7 -> 39.5 s), 0.6 s 2-4 s; a catch whose yellow was longer is untouched.
    "band_approach_s": 0.35,      # Luke: "I want the yellow to be longer" (+0.25 s on a fresh pike)
    "overload_limit": 1.30,
    "pump_recover": 0.22,         # lockout after a release: the rhythm has a floor
    "snag_load_transfer": 0.35,   # heaving on something immovable loads the ROD
    "snag_break_load": 0.72,      # THE SET: overload a snag this far to free it
    "pump_metres": 2.4,           # the rod track multiplies this (reel_power)
    "weak_yield": 0.35,           # harsh below the band: rate must never beat depth
    "perfect_yield": 1.45,
    "perfect_fraction": 0.42,     # the middle slice of the band that is PERFECT
    "load_to_tension": 0.75,
    "release_dump": 1.05,         # not a full reset: tension carries between beats
    "overload_tension": 1.30,
    "pump_stress": 0.72,          # your aggression is what panics it
    "stress_settle": 0.06,        # per second, against a ~2.5 s beat
    "pump_stamina_mult": 0.35,
    # --- the crank --------------------------------------------------------------------------
    "crank_window": 1.5,          # slack not reeled down in this long is lost
    "crank_rate": 4.5,            # the reel track multiplies this (reel_speed)
    # --- the wander (alive only) ------------------------------------------------------------
    "lateral_speed": 0.85,
    "lateral_range": 3.2,
    "lateral_run_mult": 2.4,
    "wander_min": 0.45,
    "wander_max": 1.5,
    # --- give line --------------------------------------------------------------------------
    "give_tension_relief": 2.2,
    "give_run_damping": 0.28,     # giving line cuts a run to under a third
    "run_take": 2.6,
    # --- juice (part of the mechanic, and part of the replay: hit-stop freezes time) ---------
    "shake_per_pump": 0.45,
    "shake_decay": 3.2,
    "hitstop_perfect": 0.075,
    "hitstop_snag_free": 0.14,
    # --- the hook-set carried into the fight ------------------------------------------------
    "perfect_drag_bonus": 0.05,   # a PERFECT set starts with a little more drag
    "late_start_tension": 0.35,   # a LATE one starts with the line already loaded
    "clean_catch_max_peak_tension": 0.82,
    # --- deadlift: over the line's rating ---------------------------------------------------
    "deadlift_load_mult": 1.45,
    "deadlift_creep": 0.09,       # a ratcheting tension floor: an ~11.5 s timer
}

# Profile fields, with the defaults FfC's CatchProfile carried for anything a curve does not set.
DEFAULTS = {
    "alive": True, "distance_scale": 0.55,
    "hold_force": 0.32, "run_power": 0.62, "rest_force": 0.08,
    "band_centre": 0.68, "band_width": 0.26, "band_centre_spent": 0.42, "band_width_spent": 0.52,
    "pump_yield": 1.0, "panic_gain": 1.30,
    "burst_drain": 0.32, "burst_regen": 0.30, "burst_recover": 0.65,
    "stamina_drain": 0.34, "never_tires": False,
    "dead_load": 0.0,
    "snag_interval_min": 3.0, "snag_interval_max": 6.0, "snag_duration": 1.4, "snag_load": 0.35,
}

# The species FfC tuned by play, restored verbatim over the curves.
TUNED = {
    "bluegill": dict(band_centre=0.44, band_width=0.44, band_centre_spent=0.34, band_width_spent=0.60,
                     pump_yield=0.80, distance_scale=0.30, hold_force=0.12, run_power=0.25,
                     panic_gain=2.60, burst_drain=0.55, burst_regen=0.55, stamina_drain=0.85),
    "largemouth_bass": dict(band_centre=0.68, band_width=0.26, band_centre_spent=0.42, band_width_spent=0.52,
                            pump_yield=1.70, distance_scale=0.55, panic_gain=1.30, burst_drain=0.32,
                            burst_regen=0.30, stamina_drain=0.34),
    "northern_pike": dict(band_centre=0.74, band_width=0.22, band_centre_spent=0.46, band_width_spent=0.48,
                          pump_yield=1.78, distance_scale=0.70, hold_force=0.30, run_power=0.52,
                          panic_gain=1.70, burst_drain=0.28, burst_regen=0.26, stamina_drain=0.28),
    "lake_sturgeon": dict(band_centre=0.83, band_width=0.17, band_centre_spent=0.50, band_width_spent=0.44,
                          pump_yield=2.25, distance_scale=1.00, hold_force=0.36, run_power=0.56,
                          panic_gain=0.95, burst_drain=0.20, burst_regen=0.17, stamina_drain=0.15),
}


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def log_t(kg: float, low: float, high: float) -> float:
    """0 at `low`, 1 at `high`, on a log scale, free to run outside."""
    return math.log(max(kg, 0.01) / low) / math.log(high / low)


def derive_alive(p: dict, kg: float) -> None:
    # 0 at a bluegill, 1 at a sturgeon. The band is clamped (a band that keeps narrowing is a
    # refusal, not a difficulty), and so is length: past 40 kg extra mass buys deadlift risk
    # and score, not minutes. Pull climbs a little further, so a marlin is heavier on the rod.
    t = log_t(kg, 0.3, 40.0)
    band = clamp(t, 0.0, 1.0)
    size = band
    heft = clamp(t, 0.0, 1.25)
    p["band_centre"] = lerp(0.44, 0.83, band)
    p["band_width"] = lerp(0.44, 0.17, band)
    p["band_centre_spent"] = lerp(0.34, 0.50, band)
    p["band_width_spent"] = lerp(0.60, 0.44, band)
    p["pump_yield"] = lerp(0.80, 2.25, size)
    p["distance_scale"] = lerp(0.30, 1.00, size)
    p["hold_force"] = lerp(0.12, 0.36, heft)
    p["run_power"] = lerp(0.25, 0.56, heft)
    p["panic_gain"] = lerp(2.60, 0.95, band)
    p["burst_drain"] = lerp(0.55, 0.20, band)
    p["burst_regen"] = lerp(0.55, 0.17, band)
    p["stamina_drain"] = lerp(0.85, 0.15, band)


def derive_dead(p: dict, kg: float) -> None:
    # 0 at a tire (9 kg), 1 at a shipping container (2400 kg), negative for the trivial.
    t = clamp(log_t(kg, 9.0, 2400.0), -0.6, 1.0)
    p["band_centre"] = lerp(0.38, 0.62, t)
    p["band_width"] = lerp(0.48, 0.30, t)
    p["band_centre_spent"] = p["band_centre"]   # inert things never tire
    p["band_width_spent"] = p["band_width"]
    p["pump_yield"] = lerp(1.00, 1.72, t)
    p["distance_scale"] = max(lerp(0.45, 1.00, t), 0.10)
    p["dead_load"] = max(lerp(0.20, 0.50, t), 0.02)
    p["snag_interval_min"] = lerp(8.0, 5.0, t)
    p["snag_interval_max"] = lerp(14.0, 9.0, t)
    p["snag_duration"] = lerp(1.0, 1.3, t)
    p["snag_load"] = lerp(0.35, 0.32, t)


def seat_band(p: dict) -> None:
    """Keep the band on the dial: a lower edge below 0.06 means "too early" cannot happen."""
    floor = 0.06
    if p["band_centre"] - p["band_width"] * 0.5 < floor:
        p["band_width"] = max((p["band_centre"] - floor) * 2.0, 0.12)
    if p["band_centre_spent"] - p["band_width_spent"] * 0.5 < floor:
        p["band_width_spent"] = max((p["band_centre_spent"] - floor) * 2.0, 0.12)


def main() -> None:
    doc = json.loads(CATALOG.read_text(encoding="utf-8"))
    alive_of = {c["id"]: bool(c.get("alive", True)) for c in doc["categories"]}
    profiles = {}
    for c in doc["catches"]:
        p = dict(DEFAULTS)
        p["alive"] = alive_of[c["category"]]
        if p["alive"]:
            derive_alive(p, float(c["kg"]))
        else:
            derive_dead(p, float(c["kg"]))
        seat_band(p)
        p.update(TUNED.get(c["id"], {}))
        profiles[c["id"]] = {k: (round(v, 4) if isinstance(v, float) else v) for k, v in p.items()}
    # HARD CONSTRAINT (FfC's tests asserted it): every dead load sits below the drag, or easing
    # off can never bring the line back under the clutch and the catch cannot be landed at all.
    for cid, p in profiles.items():
        assert p["dead_load"] < PARAMS["drag_setting"], (cid, p["dead_load"])
        assert 0.0 < p["band_width"] and 0.0 < p["band_width_spent"], cid
    out = {
        "_comment": "GENERATED by tools/fishing/gen_fight.py from shared/fishing/fishing.json. "
                    "The fight (Fishing for Compliments' THE PUMP) is simulated by the client for feel and "
                    "REPLAYED by the module to decide what happened, bit for bit, so every number here is "
                    "read by both. Tune the generator and re-run it; do not edit this file.",
        "tick_hz": TICK_HZ,
        "max_fight_s": MAX_FIGHT_S,
        "params": PARAMS,
        "profiles": profiles,
    }
    OUT.write_bytes((json.dumps(out, indent=1) + "\n").encode("utf-8"))
    print("wrote %s: %d profiles" % (OUT.relative_to(ROOT), len(profiles)))


if __name__ == "__main__":
    main()
