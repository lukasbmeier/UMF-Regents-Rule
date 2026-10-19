"""THE CHAIN'S MINIGAMES, A THIRD TIME: golden vectors for crack the rock (`CrackModel`), bellows then pour
(`SmeltModel`) and shape to the outline (`ShapeModel`), and their Rust twins (`genre::regents::{crack,
smelt, shape}`), made by this independent Python version so neither twin checks itself. Both twins must
reproduce every case exactly (integers only).

    python game/regents/tests/make_skill_goldens.py      (from the repo root)

writes shared/golden/regents/{crack,smelt,shape}.json. Change a rule here AND in both twins, run this,
and commit the new files with the change. Division and remainder TRUNCATE toward zero here, as they do
in GDScript and Rust (Python's own floor them): `tdiv`.
"""
import json
import os
import random

M32 = 0xFFFFFFFF


def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def next_u32(x):
    x &= M32
    x ^= (x << 13) & M32
    x ^= x >> 17
    x ^= (x << 5) & M32
    return x


def seed_state(seed):
    s = (seed ^ (seed >> 32)) & M32
    return 1 if s == 0 else s


# --- crack the rock: follow the seam ---------------------------------------------------------------
def seams(seed, p, count):
    """`count` seams of `notches` notches each, flat (x, y): even seams run top to bottom, odd ones left
    to right; each notch wanders up to `bend_pm` across from the last, inside the margins."""
    lo, hi = p["margin_pm"], 1000 - p["margin_pm"]
    span = max(0, hi - lo)
    n = p["notches"]
    st = seed_state(seed)
    out = []
    for s in range(count):
        st = next_u32(st)
        across = lo + (st >> 8) % (span + 1)
        for i in range(n):
            along = lo + tdiv(span * i, n - 1)
            if i > 0:
                st = next_u32(st)
                across = min(hi, max(lo, across + (st >> 8) % (2 * p["bend_pm"] + 1) - p["bend_pm"]))
            out.append((across, along) if s % 2 == 0 else (along, across))
    return out


def seam_count(p):
    return (p["duration_ms"] // p["swing_ms"] + 1) // p["notches"] + 2


class Crack:
    """Strike the seam's next notch (within `radius_pm`): the crack opens to it. A seam opened end to end
    splits the rock (`split_ms` before the next strike) and the next seam begins. Anywhere else jars the
    pick (`stagger_ms`). A strike during a swing or a split is HELD (the latest) and lands when it ends;
    one while staggered is lost."""

    def __init__(self, seed, p):
        self.p = p
        self.points = seams(seed, p, seam_count(p))
        self.k = 0
        self.hits = self.jars = self.combo = self.best = self.splits = 0
        self.next_ok, self.last_t, self.staggered, self.held = 0, -1, False, None

    def act(self, t, x, y):
        p = self.p
        at = self.points[self.k % len(self.points)]
        if (x - at[0]) ** 2 + (y - at[1]) ** 2 <= p["radius_pm"] ** 2:
            self.hits += 1
            self.combo += 1
            self.best = max(self.best, self.combo)
            self.k += 1
            self.staggered = False
            if self.k % p["notches"] == 0:
                self.splits += 1
                self.next_ok = t + max(p["swing_ms"], p["split_ms"])
            else:
                self.next_ok = t + p["swing_ms"]
            return 1
        self.jars += 1
        self.combo = 0
        self.next_ok, self.staggered = t + p["stagger_ms"], True
        return 2

    def settle(self, t):
        if self.held is not None and self.held[0] <= t:
            at, x, y = self.held
            self.held = None
            if at <= self.p["duration_ms"]:
                return self.act(at, x, y)
        return 0

    def strike(self, t, x, y):
        if t < self.last_t:
            return 0
        self.last_t = t
        self.settle(t)
        if t < 0 or t > self.p["duration_ms"] or x < 0 or x > 1000 or y < 0 or y > 1000:
            return 0
        if t < self.next_ok:
            if self.staggered:
                return 0
            self.held = (self.next_ok, x, y)
            return 3
        return self.act(t, x, y)

    def result(self):
        self.settle(self.p["duration_ms"])
        return {"hits": self.hits, "jars": self.jars, "best_combo": self.best, "splits": self.splits,
                "score_pm": min(1000, self.hits * 1000 // self.p["target_hits"])}


def crack_play(seed, p, inputs):
    m = Crack(seed, p)
    for t, x, y in inputs:
        m.strike(t, x, y)
    return m.result()


def crack_bot(seed, p, aim_ms, aim_err, rng):
    """A miner who takes `aim_ms` to find each notch once the pick is free, and lands near it."""
    m = Crack(seed, p)
    out = []
    t = aim_ms
    while t <= p["duration_ms"]:
        if t >= m.next_ok + aim_ms:
            at = m.points[m.k % len(m.points)]
            x = at[0] + rng.randint(-aim_err, aim_err)
            y = at[1] + rng.randint(-aim_err, aim_err)
            out.append([t, x, y])
            m.strike(t, x, y)
        t += 10
    return out


# --- bellows then pour -----------------------------------------------------------------------------
TICK = 50


class Smelt:
    def __init__(self, seed, p):
        self.p = p
        st = next_u32(seed_state(seed))
        self.phase = (st >> 8) % max(1, p["band_period_ticks"])
        st = next_u32(st)
        self.target = p["target_lo"] + (st >> 8) % max(1, p["target_hi"] - p["target_lo"] + 1)
        self.tick, self.heat, self.fill = 0, p["start_heat"], 0
        self.pouring = self.poured = False
        self.in_band = self.burnt = 0
        self.next_pump, self.last_t = 0, -1
        self.heat_ticks = p["heat_ms"] // TICK
        self.total = p["heat_ms"] // TICK + p["pour_ms"] // TICK

    @staticmethod
    def tri(x, period):
        u = x % period
        v = u * 4000 // period
        if v <= 1000:
            return v
        if v <= 3000:
            return 2000 - v
        return v - 4000

    def band(self, k):
        p = self.p
        c = p["band_center"] + tdiv(p["band_amp"] * self.tri(k + self.phase, max(1, p["band_period_ticks"])), 1000)
        h = p["band_half_start"] + tdiv((p["band_half_end"] - p["band_half_start"]) * k, max(1, self.heat_ticks))
        return c, h

    def advance_to(self, t):
        while (self.tick + 1) * TICK <= t and self.tick < self.total:
            if self.tick < self.heat_ticks:
                self.heat = max(0, self.heat - self.p["cool_per_tick"])
                c, h = self.band(self.tick)
                if abs(self.heat - c) <= h:
                    self.in_band += 1
                if self.heat > self.p["burn_line"]:
                    self.burnt += 1
            elif self.pouring:
                self.fill += self.p["pour_rate"]
            self.tick += 1

    def press(self, t, code):
        if t < self.last_t:
            return 0
        self.last_t = t
        if t < 0 or t > self.total * TICK:
            return 0
        self.advance_to(t)
        in_heat = self.tick < self.heat_ticks
        if code == 1:
            if not in_heat or t < self.next_pump:
                return 0
            self.heat = min(1000, self.heat + self.p["pump_heat"])
            self.next_pump = t + self.p["pump_ms"]
            return 1
        if code == 2:
            if in_heat or self.pouring or t < self.p["heat_ms"] + self.p["pour_ready_ms"]:
                return 0
            self.pouring = self.poured = True
            return 1
        if code == 3:
            if not self.pouring:
                return 0
            self.pouring = False
            return 1
        return 0

    def result(self):
        p = self.p
        self.advance_to(self.total * TICK)
        heat_pm = max(0, min(1000, tdiv((self.in_band - self.burnt) * 1000, max(1, self.heat_ticks))))
        pour_pm = 0 if self.fill > 1000 else max(0, 1000 - abs(self.fill - self.target) * 1000 // p["pour_tolerance"])
        score = (heat_pm * p["heat_weight_pct"] + pour_pm * (100 - p["heat_weight_pct"])) // 100
        return {"in_band": self.in_band, "burnt": self.burnt, "fill": self.fill, "target": self.target,
                "heat_pm": heat_pm, "pour_pm": pour_pm, "score_pm": score}


def smelt_play(seed, p, inputs):
    m = Smelt(seed, p)
    for t, c in inputs:
        m.press(t, c)
    return m.result()


def smelt_bot(seed, p, pump_bias, pour_late_ms):
    """Pumps whenever the heat sits under the band's middle (+ bias); pours, and stops at the line."""
    m = Smelt(seed, p)
    out = []
    t = 0
    while t < p["heat_ms"]:
        m.advance_to(t)
        c, _ = m.band(m.tick)
        if m.heat < c + pump_bias and t >= m.next_pump:
            out.append([t, 1])
            m.press(t, 1)
        t += 10
    t = p["heat_ms"] + p["pour_ready_ms"] + 100
    out.append([t, 2])
    m.press(t, 2)
    while m.fill < m.target and t < (m.total - 1) * TICK:
        t += 10
        m.advance_to(t)
    t += pour_late_ms
    out.append([t, 3])
    m.press(t, 3)
    return out


# --- shape to the outline --------------------------------------------------------------------------
class Shape:
    def __init__(self, seed, p):
        self.p = p
        st = seed_state(seed)
        self.h = []
        for _ in range(len(p["outline"])):
            st = next_u32(st)
            self.h.append(p["start_height"] + (st >> 8) % (p["start_jitter"] + 1))
        self.hot_until, self.next_ok, self.last_t, self.held = p["heat_ms"], 0, -1, None
        self.strikes = self.colds = self.reheats = 0

    def settle(self, t):
        if self.held is not None and self.held[0] <= t:
            at, c = self.held
            self.held = None
            if at <= self.p["duration_ms"]:
                return self.act(at, c)
        return 0

    def strike(self, t, c):
        """A strike during a swing or a reheat is HELD (the latest) and lands when it ends."""
        if t < self.last_t:
            return 0
        self.last_t = t
        self.settle(t)
        if t < 0 or t > self.p["duration_ms"] or c < -1 or c >= len(self.h):
            return 0
        if t < self.next_ok:
            self.held = (self.next_ok, c)
            return 4
        return self.act(t, c)

    def act(self, t, c):
        p = self.p
        if c == -1:
            self.reheats += 1
            self.next_ok = t + p["reheat_ms"]
            self.hot_until = t + p["reheat_ms"] + p["heat_ms"]
            return 3
        self.next_ok = t + p["swing_ms"]
        if t >= self.hot_until:
            self.colds += 1
            return 2
        d = min(self.h[c], p["hammer_drop"])
        self.h[c] -= d
        side = d * p["spread_pct"] // 100
        if c > 0:
            self.h[c - 1] += side
        if c < len(self.h) - 1:
            self.h[c + 1] += side
        self.strikes += 1
        return 1

    def result(self):
        self.settle(self.p["duration_ms"])
        err = sum(abs(a - b) for a, b in zip(self.h, self.p["outline"]))
        return {"strikes": self.strikes, "colds": self.colds, "reheats": self.reheats, "error": err,
                "score_pm": max(0, 1000 - err * 1000 // self.p["error_scale"])}


def shape_play(seed, p, inputs):
    m = Shape(seed, p)
    for t, c in inputs:
        m.strike(t, c)
    return m.result()


def shape_bot(seed, p, reheat_margin_ms):
    """Strikes the column furthest above the outline each swing; reheats when the bar is nearly cold."""
    m = Shape(seed, p)
    out = []
    t = 0
    while t <= p["duration_ms"]:
        if t >= m.next_ok:
            if m.hot_until - t < reheat_margin_ms:
                out.append([t, -1])
                m.strike(t, -1)
            else:
                over = [m.h[i] - p["outline"][i] for i in range(len(m.h))]
                c = max(range(len(over)), key=lambda i: over[i])
                if over[c] <= 0:
                    break
                out.append([t, c])
                m.strike(t, c)
        t += 10
    return out


def main():
    rng = random.Random(20261019)
    crack_p = {"duration_ms": 10000, "swing_ms": 260, "stagger_ms": 700, "split_ms": 600, "notches": 7,
               "bend_pm": 120, "radius_pm": 80, "margin_pm": 120, "reveal_ahead": 6, "target_hits": 16}
    smelt_p = {"heat_ms": 7000, "pour_ms": 4000, "pour_ready_ms": 600, "pump_ms": 40, "pump_heat": 45, "cool_per_tick": 10,
               "start_heat": 350, "band_center": 600, "band_amp": 140, "band_period_ticks": 80,
               "band_half_start": 120, "band_half_end": 60, "burn_line": 900, "pour_rate": 28,
               "target_lo": 620, "target_hi": 820, "pour_tolerance": 220, "heat_weight_pct": 60}
    shape_p = {"duration_ms": 15000, "swing_ms": 280, "heat_ms": 5000, "reheat_ms": 1500, "start_height": 20,
               "start_jitter": 2, "hammer_drop": 4, "spread_pct": 20,
               "outline": [22, 20, 16, 12, 10, 10, 10, 10, 10, 10, 12, 14, 18, 22, 24, 24], "error_scale": 100}

    def seed_fields(seed):
        return {"seed_hi": (seed >> 32) & M32, "seed_lo": seed & M32}

    crack = []

    def add_crack(name, seed, p, inputs):
        crack.append(dict(name=name, **seed_fields(seed), params=p, inputs=inputs,
                          points=[c for xy in seams(seed, p, 3) for c in xy], expected=crack_play(seed, p, inputs)))

    add_crack("a quick, sure hand", 77, crack_p, crack_bot(77, crack_p, 150, 30, rng))
    add_crack("a high-bit seed, a shaky hand", 0xFEDCBA9876543210, crack_p, crack_bot(0xFEDCBA9876543210, crack_p, 300, 90, rng))
    add_crack("seed 0, slow eyes", 0, crack_p, crack_bot(0, crack_p, 700, 20, rng))
    flail = [[t, rng.randint(-50, 1050), rng.randint(-50, 1050)] for t in sorted(rng.randint(-100, 10100) for _ in range(90))]
    flail.insert(30, [100, 500, 500])   # out of order
    add_crack("flailing: random strikes, off the face, out of order", 0x1234567890ABCDEF, crack_p, flail)
    tight = dict(crack_p, radius_pm=45, notches=9, bend_pm=200, reveal_ahead=2, target_hits=20)
    add_crack("an iron rock: tight notches, a wild seam", 31337, tight, crack_bot(31337, tight, 120, 25, rng))
    eager = []
    em = Crack(5, crack_p)
    for i in range(40):   # every notch clicked 100 ms apart: each held through the swing or split before it
        at = em.points[i]
        eager.append([i * 100, at[0], at[1]])
    add_crack("an eager hand: every notch clicked early, held to the swing", 5, crack_p, eager)
    through = []
    tm = Crack(9, crack_p)
    n = crack_p["notches"]
    for i in range(n):   # a seam opened a swing at a time, then two clicks inside the split's pause
        through.append([i * 260, tm.points[i][0], tm.points[i][1]])
    t_end = (n - 1) * 260
    through.append([t_end + 260, tm.points[n][0], tm.points[n][1]])
    through.append([t_end + 400, tm.points[n + 1][0], tm.points[n + 1][1]])
    through.append([t_end + 900, tm.points[n][0], tm.points[n][1]])
    add_crack("clicking through the split: held to its end, the latest click wins", 9, crack_p, through)
    add_crack("nothing struck", 42, crack_p, [])

    smelt = []

    def add_smelt(name, seed, p, inputs):
        m = Smelt(seed, p)
        smelt.append(dict(name=name, **seed_fields(seed), params=p, inputs=inputs,
                          bands=[list(m.band(k)) for k in range(0, 140, 7)], expected=smelt_play(seed, p, inputs)))

    add_smelt("a steady smelter", 99, smelt_p, smelt_bot(99, smelt_p, 0, 0))
    add_smelt("a high-bit seed, pumping hot", 0xFEDCBA9876543210, smelt_p, smelt_bot(0xFEDCBA9876543210, smelt_p, 260, 0))
    add_smelt("seed 0, pours late (spills)", 0, smelt_p, smelt_bot(0, smelt_p, 0, 3000))
    add_smelt("never pumps, never stops pouring", 5, smelt_p, [[7700, 2]])
    add_smelt("mashing into the pour: too soon is ignored, then top-ups", 8, smelt_p,
              [[6900, 1], [6950, 1], [7010, 2], [7080, 3], [7300, 2], [7350, 3], [7700, 2], [9000, 3], [9500, 2], [9800, 3]])
    mash = [[t, rng.choice([1, 1, 1, 2, 3, 0, 9])] for t in sorted(rng.randint(-200, 11300) for _ in range(160))]
    mash.insert(40, [50, 1])
    add_smelt("mashing every key, out of order", 0x1234567890ABCDEF, smelt_p, mash)
    narrow = dict(smelt_p, band_half_start=70, band_half_end=25, band_amp=220, band_period_ticks=41, pour_rate=45)
    add_smelt("iron: a narrow, quick band", 31337, narrow, smelt_bot(31337, narrow, 0, 0))
    add_smelt("nothing pressed", 42, smelt_p, [])

    shape = []

    def add_shape(name, seed, p, inputs):
        m = Shape(seed, p)
        shape.append(dict(name=name, **seed_fields(seed), params=p, inputs=inputs, start=list(m.h),
                          expected=shape_play(seed, p, inputs)))

    add_shape("a careful smith", 7, shape_p, shape_bot(7, shape_p, 400))
    add_shape("a high-bit seed, never reheats", 0xFEDCBA9876543210, shape_p, shape_bot(0xFEDCBA9876543210, shape_p, -100000))
    add_shape("seed 0", 0, shape_p, shape_bot(0, shape_p, 400))
    wild = [[t, rng.randint(-2, 17)] for t in sorted(rng.randint(-100, 15200) for _ in range(120))]
    wild.insert(20, [10, 3])
    add_shape("hammering anywhere, out of order", 0x1234567890ABCDEF, shape_p, wild)
    heavy = dict(shape_p, hammer_drop=7, spread_pct=40, heat_ms=3000, start_jitter=5)
    add_shape("a heavy hammer, a quick-cooling bar", 31337, heavy, shape_bot(31337, heavy, 600))
    add_shape("nothing struck", 42, shape_p, [])

    here = os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.join(here, "..", "..", "..", "shared", "golden", "regents")
    os.makedirs(outdir, exist_ok=True)
    for name, cases in (("crack", crack), ("smelt", smelt), ("shape", shape)):
        doc = {"_comment": "GENERATED by game/regents/tests/make_skill_goldens.py (%s): for the GDScript model and its "
                           "Rust twin. Do not edit." % name, "cases": cases}
        with open(os.path.join(outdir, name + ".json"), "wb") as f:
            f.write((json.dumps(doc, indent=1) + "\n").encode())
        for c in cases:
            print(name, "|", c["name"], c["expected"])


main()
