"""THE CHAIN'S MINIGAMES, A THIRD TIME: golden vectors for crack the rock (`CrackModel`), bellows then pour
(`SmeltModel`) and shape to the outline (`ShapeModel`), and their Rust twins (`genre::regents::{crack,
smelt, shape}`), made by this independent Python version so neither twin checks itself. Both twins must
reproduce every case exactly (integers only).

    python game/regents/tests/make_skill_goldens.py      (from the repo root)

writes shared/golden/regents/{crack,smelt,shape,beat,carve,pull,skin}.json (beat: smelting as a rhythm track; pull: herbalism; skin: skinning). Change a rule here AND in both twins, run this,
and commit the new files with the change. Division and remainder TRUNCATE toward zero here, as they do
in GDScript and Rust (Python's own floor them): `tdiv`.
"""
import json
import os
import random

M32 = 0xFFFFFFFF
TAP = 1000  # smithing: a light tap on column c is sent as TAP + c


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


# BRITTLE NOTCHES (MINIGAMES_PREP.md §3, band 2's new thing for mining, a TEST for Luke's play, 2026-11-07): after a hit
# the rock rings for `ring_ms`; a brittle notch struck before the ring has faded cracks wrong (a jar). Drawn from their
# own stream (the seed folded with RING_SALT), so the seams never change; a seam's first notch is never brittle;
# `brittle_permille` 0 (or absent): none.
RING_SALT = 0x72696E67


def brittle_of(seed, p, n):
    if p.get("brittle_permille", 0) <= 0:
        return [0] * n
    out = []
    st = seed_state(seed ^ RING_SALT)
    for i in range(n):
        if i % p["notches"] == 0:
            out.append(0)
            continue
        st = next_u32(st)
        out.append(1 if ((st >> 8) * 1000) >> 24 < p["brittle_permille"] else 0)
    return out


class Crack:
    """Strike the seam's next notch (within `radius_pm`): the crack opens to it. A seam opened end to end
    splits the rock (`split_ms` before the next strike) and the next seam begins. Anywhere else jars the
    pick (`stagger_ms`). A strike during a swing or a split is HELD (the latest) and lands when it ends;
    one while staggered is lost."""

    def __init__(self, seed, p):
        self.p = p
        self.points = seams(seed, p, seam_count(p))
        self.brittle = brittle_of(seed, p, len(self.points))
        self.last_hit = None
        self.k = 0
        self.hits = self.jars = self.combo = self.best = self.splits = 0
        self.next_ok, self.last_t, self.staggered, self.held = 0, -1, False, None

    def act(self, t, x, y):
        p = self.p
        at = self.points[self.k % len(self.points)]
        on = (x - at[0]) ** 2 + (y - at[1]) ** 2 <= p["radius_pm"] ** 2
        ringing = self.brittle[self.k % len(self.points)] == 1 and self.last_hit is not None and t < self.last_hit + p.get("ring_ms", 0)
        if on and not ringing:
            self.last_hit = t
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


def crack_patient(seed, p, eager=False):
    """Dead on every notch; on a brittle one, waits for the ring to fade (or, `eager`, strikes the moment the pick is free)."""
    m = Crack(seed, p)
    out = []
    t = 0
    while t <= p["duration_ms"]:
        k = m.k % len(m.points)
        if not eager and m.brittle[k] == 1 and m.last_hit is not None:
            t = max(t, m.last_hit + p["ring_ms"])
        at = m.points[k]
        out.append([t, at[0], at[1]])
        m.strike(t, at[0], at[1])
        t = max(t + 1, m.next_ok)
    return out


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
DONE, LAY, LIFT = 2000, 2001, 2002  # smithing: set the part down (and quench it), lay the template on, lift it off


def g(p, k):
    """A param added later (2026-11-05): absent in older cases, so 0 (off)."""
    return p.get(k, 0)


def shape_outline(seed, p):
    """The round's outline: the part's, varied from the seed by up to `outline_vary` (three smooth bumps), the
    total kept (so every variant takes as much beating off)."""
    base = list(p["outline"])
    vary = g(p, "outline_vary")
    n = len(base)
    if vary <= 0:
        return base
    st = seed_state(seed)
    for _ in range(n):
        st = next_u32(st)  # the bar's own draws (start heights)
    offs = [0] * n
    for _ in range(3):
        st = next_u32(st)
        c = (st >> 8) % n
        st = next_u32(st)
        a = (st >> 8) % (2 * vary + 1) - vary
        for j in range(-2, 3):
            if 0 <= c + j < n:
                w = 3 - abs(j)
                offs[c + j] += (1 if a >= 0 else -1) * (abs(a) * w // 3)
    out = [max(1, base[i] + offs[i]) for i in range(n)]
    total = sum(out) - sum(base)
    st = next_u32(st)
    i = (st >> 8) % n
    for _ in range(100000):
        if total == 0:
            break
        if total > 0 and out[i] > 1:
            out[i] -= 1
            total -= 1
        elif total < 0:
            out[i] += 1
            total += 1
        i = (i + 1) % n
    return out


class Shape:
    def __init__(self, seed, p):
        self.p = p
        st = seed_state(seed)
        self.h = []
        for _ in range(len(p["outline"])):
            st = next_u32(st)
            self.h.append(p["start_height"] + (st >> 8) % (p["start_jitter"] + 1))
        self.outline = shape_outline(seed, p)
        self.hot_until, self.next_ok, self.last_t, self.held = p["heat_ms"], 0, -1, None
        self.strikes = self.colds = self.reheats = 0
        self.lays = self.cracks = 0
        self.laid = g(p, "hide_outline") > 0
        self.done_ms = -1

    def valid(self, c):
        p, n = self.p, len(self.h)
        if c >= DONE:
            if c == DONE:
                return g(p, "max_reheats") > 0
            return g(p, "hide_outline") > 0 and c in (LAY, LIFT)
        if c >= TAP:
            return g(p, "tap_drop") > 0 and c - TAP < n
        return -1 <= c < n

    def settle(self, t):
        if self.held is not None and self.held[0] <= t:
            at, c = self.held
            self.held = None
            if at <= self.p["duration_ms"]:
                return self.act(at, c)
        return 0

    def strike(self, t, c):
        """A strike during a swing or a reheat is HELD (the latest) and lands when it ends. Setting the part down
        and the template are instant, never held; after the part is set down, nothing more."""
        if t < self.last_t or self.done_ms >= 0:
            return 0
        self.last_t = t
        self.settle(t)
        if t < 0 or t > self.p["duration_ms"] or not self.valid(c):
            return 0
        if c == DONE:
            self.held = None
            self.done_ms = t
            return 6
        if c == LAY or c == LIFT:
            if self.laid == (c == LAY):
                return 0
            self.laid = c == LAY
            self.lays += int(c == LAY)
            return 7
        if t < self.next_ok:
            self.held = (self.next_ok, c)
            return 4
        return self.act(t, c)

    def act(self, t, c):
        p = self.p
        if c == -1:
            if 0 < g(p, "max_reheats") <= self.reheats:
                return 0
            self.reheats += 1
            self.next_ok = t + p["reheat_ms"]
            self.hot_until = t + p["reheat_ms"] + p["heat_ms"]
            return 3
        if self.laid:
            return 0  # no strikes while the template is on the bar
        self.next_ok = t + p["swing_ms"]
        if t >= self.hot_until:
            self.colds += 1
            return 2
        if t >= self.hot_until - g(p, "red_ms"):
            self.cracks += 1  # struck red: it does not move, it cracks
            return 5
        tap = c >= TAP
        if tap:
            c -= TAP
        d = min(self.h[c], p["tap_drop"] if tap else p["hammer_drop"])
        self.h[c] -= d
        side = d * (p["tap_spread_pct"] if tap else p["spread_pct"]) // 100
        if c > 0:
            self.h[c - 1] += side
        if c < len(self.h) - 1:
            self.h[c + 1] += side
        self.strikes += 1
        return 1

    def heat_pm(self, t):
        return max(0, min(1000, (self.hot_until - t) * 1000 // self.p["heat_ms"])) if self.hot_until > t else 0

    def result(self):
        p = self.p
        if self.done_ms < 0:
            self.settle(p["duration_ms"])
        err = sum(abs(a - b) for a, b in zip(self.h, self.outline))
        raw = max(0, 1000 - err * 1000 // p["error_scale"])
        ceiling = max(0, 1000 - self.reheats * g(p, "reheat_cost_pm") - self.lays * g(p, "lay_cost_pm")
                      - self.cracks * g(p, "crack_cost_pm"))
        quench = 0
        lo, hi = g(p, "quench_lo_pm"), g(p, "quench_hi_pm")
        if hi > 0:
            h = self.heat_pm(self.done_ms if self.done_ms >= 0 else p["duration_ms"])
            if lo <= h <= hi:
                quench = g(p, "quench_bonus_pm")
            else:
                dist = lo - h if h < lo else h - hi
                quench = -min(g(p, "quench_loss_pm"), dist * g(p, "quench_loss_pm") // max(1, hi - lo))
        return {"strikes": self.strikes, "colds": self.colds, "reheats": self.reheats, "lays": self.lays,
                "cracks": self.cracks, "error": err, "ceiling_pm": ceiling, "quench_pm": quench,
                "score_pm": max(0, min(ceiling, raw + quench))}


def shape_play(seed, p, inputs):
    m = Shape(seed, p)
    for t, c in inputs:
        m.strike(t, c)
    return m.result()


def shape_bot(seed, p, reheat_margin_ms):
    """Strikes the column furthest above the outline each swing (a light tap once it is closer than a heavy
    strike's drop, when taps are on); reheats when the bar is nearly cold (before it goes red), while it has heats
    left. A round with a template lifts it first and lays it again every tenth strike; a round with heats sets
    the part down when done (in the quench window, if it has one)."""
    m = Shape(seed, p)
    out = []
    t = 0
    struck = 0

    def send(c):
        out.append([t, c])
        m.strike(t, c)

    while t <= p["duration_ms"] and m.done_ms < 0:
        if m.laid:
            if t >= 400:
                send(LIFT)
        elif t >= m.next_ok:
            left = g(p, "max_reheats") == 0 or m.reheats < g(p, "max_reheats")
            over = [m.h[i] - m.outline[i] for i in range(len(m.h))]
            c = max(range(len(over)), key=lambda i: over[i])
            if over[c] <= 0 or (not left and t >= m.hot_until - g(p, "red_ms")):
                if g(p, "max_reheats") > 0:
                    hi = g(p, "quench_hi_pm")
                    if hi == 0 or m.heat_pm(t) <= (g(p, "quench_lo_pm") + hi) // 2:
                        send(DONE)
                        break
                    t += 10
                    continue
                break
            if m.hot_until - g(p, "red_ms") - t < reheat_margin_ms and left:
                send(-1)
            elif g(p, "hide_outline") > 0 and struck > 0 and struck % 10 == 0:
                send(LAY)
                struck += 1
            else:
                if g(p, "tap_drop") > 0 and over[c] < p["hammer_drop"]:
                    c += TAP
                send(c)
                struck += 1
        t += 10
    return out


# --- smelting as a rhythm track (Luke, 2026-11-07), then the pour -------------------------------------
# SLAG (MINIGAMES_PREP.md §3, band 2's new thing for smelting, a TEST, 2026-11-07): a tap note may be slag (`slag_pm`),
# drawn from its own stream (the seed folded with SLAG_SALT, one draw a note), skimmed with the second button (SKIM, 3):
# a SKIM meets only slag, a DOWN never does; a SKIM on no slag is wasted breath. A round with no slag ignores a SKIM.
SLAG_SALT = 0x736C6167


class Beat:
    def __init__(self, seed, p):
        self.p = p
        st = next_u32(seed_state(seed))
        self.target = p["target_lo"] + (st >> 8) % max(1, p["target_hi"] - p["target_lo"] + 1)
        self.notes = []   # [time, end]
        covered = -1
        for i in range(p["beats"]):
            rolls = []
            for _ in range(3):
                st = next_u32(st)
                rolls.append((st >> 8) % 1000)
            r_rest, r_off, r_hold = rolls
            on_t = (p["lead_beats"] + i) * p["beat_ms"]
            rest = i % 4 != 0 and r_rest < p["rest_pm"]
            if i > covered and not rest:
                if p["hold_beats"] > 0 and r_hold < p["hold_pm"] and i + p["hold_beats"] <= p["beats"] - 1:
                    self.notes.append([on_t, on_t + p["hold_beats"] * p["beat_ms"]])
                    covered = i + p["hold_beats"]
                else:
                    self.notes.append([on_t, on_t])
            if i >= covered and r_off < p["offbeat_pm"]:
                half = p["beat_ms"] // 2
                self.notes.append([on_t + half, on_t + half])
        self.slag = [0] * len(self.notes)
        if p.get("slag_pm", 0) > 0:
            st2 = seed_state(seed ^ SLAG_SALT)
            for j, (nt, end) in enumerate(self.notes):
                st2 = next_u32(st2)
                self.slag[j] = 1 if end == nt and (st2 >> 8) % 1000 < p["slag_pm"] else 0
        self.got = [-1] * len(self.notes)
        self.perfect = self.good = self.strays = 0
        self.down = False
        self.holding = None
        self.hold_pts = 0
        self.pour_tick = self.fill = 0
        self.pouring = False
        self.last_t = -1
        self.track_end = (p["lead_beats"] + p["beats"]) * p["beat_ms"]
        self.total = self.track_end + p["pour_ms"]

    def advance_to(self, t):
        if self.holding is not None and t >= self.notes[self.holding][1]:
            self.got[self.holding] = self.hold_pts
            self.holding = None
        while self.pour_tick < self.p["pour_ms"] // TICK and self.track_end + (self.pour_tick + 1) * TICK <= t:
            if self.pouring:
                self.fill += self.p["pour_rate"]
            self.pour_tick += 1

    def press(self, t, code):
        p = self.p
        if t < self.last_t:
            return
        self.last_t = t
        if t < 0 or t > self.total:
            return
        self.advance_to(t)
        if code == 1:
            if self.down:
                return
            self.down = True
            if t >= self.track_end:
                if not self.pouring and t >= self.track_end + p["pour_ready_ms"]:
                    self.pouring = True
                return
            for j, (nt, end) in enumerate(self.notes):
                if self.got[j] < 0 and j != self.holding and self.slag[j] == 0 and abs(t - nt) <= p["good_ms"]:
                    if abs(t - nt) <= p["perfect_ms"]:
                        pts = 1000
                        self.perfect += 1
                    else:
                        pts = p["good_pm"]
                        self.good += 1
                    if end > nt:
                        self.holding, self.hold_pts = j, pts
                    else:
                        self.got[j] = pts
                    return
            self.strays += 1
        elif code == 3:
            if t >= self.track_end or p.get("slag_pm", 0) <= 0:
                return   # a round with no slag ignores a skim (so every round before slag replays as it did)
            for j, (nt, end) in enumerate(self.notes):
                if self.got[j] < 0 and self.slag[j] == 1 and abs(t - nt) <= p["good_ms"]:
                    if abs(t - nt) <= p["perfect_ms"]:
                        self.got[j] = 1000
                        self.perfect += 1
                    else:
                        self.got[j] = p["good_pm"]
                        self.good += 1
                    return
            self.strays += 1
        elif code == 2:
            if not self.down:
                return
            self.down = False
            if self.pouring:
                self.pouring = False
            elif self.holding is not None:
                j = self.holding
                self.holding = None
                nt, end = self.notes[j]
                if t >= end - p["good_ms"]:
                    self.got[j] = self.hold_pts
                else:
                    self.got[j] = self.hold_pts * max(0, t - nt) // max(1, end - nt)

    def result(self):
        p = self.p
        self.advance_to(self.total)
        n = len(self.notes)
        track = max(0, min(1000, tdiv(sum(max(0, g) for g in self.got) - self.strays * p["stray_pm"], max(1, n))))
        pour = 0 if self.fill > 1000 else max(0, 1000 - abs(self.fill - self.target) * 1000 // p["pour_tolerance"])
        w = p["track_weight_pct"] if p["pour_ms"] > 0 else 100
        return {"notes": n, "perfect": self.perfect, "good": self.good, "strays": self.strays, "fill": self.fill,
                "target": self.target, "track_pm": track, "pour_pm": pour, "score_pm": (track * w + pour * (100 - w)) // 100}


def beat_play(seed, p, inputs):
    m = Beat(seed, p)
    for t, c in inputs:
        m.press(t, c)
    return m.result()


def beat_bot_slag(seed, p, wrong_key=False):
    """On every note's time: a slag note skimmed (or, `wrong_key`, pressed with the main button), the rest pressed."""
    m = Beat(seed, p)
    out = []
    for j, (nt, end) in enumerate(m.notes):
        if m.slag[j] == 1 and not wrong_key:
            out.append([nt, 3])
        else:
            out.append([nt, 1])
            out.append([end if end > nt else nt + 60, 2])
    out.append([m.track_end + 50, 3])   # a skim after the track: nothing
    return out


def beat_bot(seed, p, spread_ms, rng, skip_pct=0, early_release_ms=0, pour_late_ms=0):
    """Presses each note at its time give or take `spread_ms`, lets a tap go 60 ms later and a draw at its end (less
    `early_release_ms`); skips `skip_pct` of the notes; then tilts and stops at the line (late by `pour_late_ms`)."""
    m = Beat(seed, p)
    out = []
    last = 0
    for nt, end in m.notes:
        if rng.randint(1, 100) <= skip_pct:
            continue
        t = max(last + 1, nt + rng.randint(-spread_ms, spread_ms))
        out.append([t, 1])
        up = max(t + 1, (end - early_release_ms) if end > nt else t + 60)
        out.append([up, 2])
        last = up
    t = m.track_end + p["pour_ready_ms"] + 100
    out.append([t, 1])
    fill_ticks = -(-m.target // p["pour_rate"])   # ticks to reach the line
    stop = m.track_end + (tdiv(t - m.track_end, TICK) + fill_ticks) * TICK + pour_late_ms
    out.append([stop, 2])
    return out


# --- carving (woodworking; Luke, 2026-11-07: a vertical stave, wood off either side) ---------------------
CARVE_DONE, CARVE_LAY, CARVE_LIFT = 5000, 5001, 5002   # a cut is kind * 1000 + row: 1 left deep, 2 left fine, 3 right deep, 4 right fine


class Carve:
    def __init__(self, seed, p):
        self.p = p
        n = len(p["left_outline"])
        self.n = n
        st = seed_state(seed)
        j = p["start_jitter"]
        self.left, self.right = [], []
        for _ in range(n):
            st = next_u32(st)
            self.left.append(p["start_half"] + (st >> 8) % (2 * j + 1) - j)
            st = next_u32(st)
            self.right.append(p["start_half"] + (st >> 8) % (2 * j + 1) - j)
        # The flip (Luke, 2026-11-07: an unstrung bow "backwards (curve going right or left)"): one draw; with `mirror`
        # on, an odd draw swaps the profiles (the C bends the other way).
        st = next_u32(st)
        flip = p.get("mirror", 0) > 0 and (st >> 8) % 2 == 1
        bases = (p["right_outline"], p["left_outline"]) if flip else (p["left_outline"], p["right_outline"])
        v = p["outline_vary"]
        outs = []
        for base in bases:
            st = next_u32(st)
            r0 = (st >> 8) % n
            st = next_u32(st)
            a = (st >> 8) % (2 * v + 1) - v
            outs.append([base[i] + tdiv(a * max(0, 3 - abs(i - r0)), 3) for i in range(n)])
        self.tl, self.tr = outs
        self.laid = p["hide_outline"] > 0
        self.lays = self.cuts = 0
        self.next_ok, self.held, self.done, self.last_t = 0, None, -1, -1

    def apply(self, t, code):
        kind, row = code // 1000, code % 1000
        depth = self.p["deep_cut"] if kind in (1, 3) else self.p["fine_cut"]
        # Edges are signed (an edge may cross the middle line, for a curved stave); a cut stops at the other edge.
        if kind <= 2:
            self.left[row] = max(-self.right[row], self.left[row] - depth)
        else:
            self.right[row] = max(-self.left[row], self.right[row] - depth)
        self.cuts += 1
        self.next_ok = t + self.p["swing_ms"]

    def settle(self, t):
        if self.held is not None and self.held[0] <= t:
            at, code = self.held
            self.held = None
            if at <= self.p["duration_ms"] and self.done < 0 and not self.laid:
                self.apply(at, code)

    def press(self, t, code):
        if t < self.last_t:
            return
        self.last_t = t
        if t < 0 or t > self.p["duration_ms"] or self.done >= 0:
            return
        self.settle(t)
        if code == CARVE_DONE:
            self.done = t
            self.held = None
        elif code == CARVE_LAY:
            if self.p["hide_outline"] > 0 and not self.laid:
                self.laid = True
                self.lays += 1
        elif code == CARVE_LIFT:
            self.laid = False
        elif 1000 <= code < 5000 and code % 1000 < self.n:
            if self.laid:
                return
            if t < self.next_ok:
                self.held = (self.next_ok, code)
                return
            self.apply(t, code)

    def result(self):
        if self.done < 0:
            self.settle(self.p["duration_ms"])
        error = sum(abs(self.left[i] - self.tl[i]) + abs(self.right[i] - self.tr[i]) for i in range(self.n))
        raw = max(0, 1000 - error * 1000 // self.p["error_scale"])
        ceiling = max(0, 1000 - self.lays * self.p["lay_cost_pm"])
        return {"error": error, "cuts": self.cuts, "lays": self.lays, "ceiling_pm": ceiling, "score_pm": min(raw, ceiling)}


def carve_play(seed, p, inputs):
    m = Carve(seed, p)
    for t, c in inputs:
        m.press(t, c)
    return m.result()


def carve_bot(seed, p, look_again=False, done=True):
    """Lifts the pattern, then cuts the edge furthest past its profile (deep while a deep cut fits, then fine) every
    swing; `look_again` lays the pattern on once more halfway; sets the piece down when nothing is past."""
    m = Carve(seed, p)
    out = []
    t = 200
    if m.laid:
        out.append([t, CARVE_LIFT])
        m.press(t, CARVE_LIFT)
    looked = not look_again
    while t <= p["duration_ms"]:
        t += p["swing_ms"]
        if not looked and m.cuts >= 10:
            out.append([t, CARVE_LAY])
            m.press(t, CARVE_LAY)
            out.append([t + 50, CARVE_LIFT])
            m.press(t + 50, CARVE_LIFT)
            t += 50
            looked = True
            continue
        best, code = 0, -1
        for i in range(m.n):
            for side, cur, tgt in ((0, m.left[i], m.tl[i]), (1, m.right[i], m.tr[i])):
                over = cur - tgt
                if over > best:
                    best = over
                    deep = over >= p["deep_cut"]
                    code = (1 if side == 0 else 3) * 1000 + (0 if deep else 1000) + i
        if code < 0:
            break
        out.append([t, code])
        m.press(t, code)
    if done:
        out.append([t + 10, CARVE_DONE])
    return out


# --- pull the root (herbalism; HERBALISM_HUNTING_PREP.md §3, Luke's H3, 2026-11-07; the trowel's work 2026-11-08) ---
PULL_DOWN, PULL_UP, PULL_LEFT, PULL_RIGHT = 1, 2, 3, 4
# Which sides of a stem start LOOSE (Luke, 2026-11-09: "cutaway, no chore"): their own stream, so the side roots never change.
PULL_LOOSE_SALT = 0x6C6F6F73


class Pull:
    """In ticks of 50 ms, a clump (Luke, 2026-11-08): stem after stem, each drawing its own side roots (depth, jump,
    side), until the time runs out. A trowel stroke cuts the side root showing on its side, else digs that side's packed
    soil; while it runs the stem is not pulled. Held, the strain rises and the root comes up (faster at a higher strain,
    slower in packed soil); let go it eases; a side root pulled through uncut jumps the strain; past 1000 it snaps
    (worth snap_keep_pm of what came up), at 1000 up it is whole. The rules in full are on PullModel."""

    def __init__(self, seed, p):
        self.p = p
        self.st = seed_state(seed)
        self.draw()
        self.first = (list(self.depth), list(self.jump), list(self.side))
        self.tick = 0
        self.down = False
        self.plant = 0
        self.strain = self.up_by = self.next_snag = 0
        self.soil = seed_state(seed ^ PULL_LOOSE_SALT)
        self.draw_soil()
        self.stroke_until = self.stroke_to_tick = 0
        self.whole = self.snapped = self.caught = self.cut = self.dug = self.worth = 0
        self.over = False
        self.finished = False
        self.last_t = -1

    def draw(self):
        p = self.p
        seg = 900 // max(1, p["snags"])
        self.depth, self.jump, self.side = [], [], []
        for k in range(p["snags"]):
            self.st = next_u32(self.st)
            self.depth.append(50 + k * seg + (self.st >> 8) % max(1, seg))
            self.st = next_u32(self.st)
            self.jump.append(p["jump_lo"] + (self.st >> 8) % max(1, p["jump_hi"] - p["jump_lo"] + 1))
            self.st = next_u32(self.st)
            self.side.append(PULL_LEFT + (self.st >> 8) % 2)

    def draw_soil(self):
        # Each side packed (1000), or LOOSE (0) with a chance of loose_pm, left then right; 0: both packed, no draw.
        self.pack_left = self.pack_right = 1000
        loose = self.p.get("loose_pm", 0)
        if loose > 0:
            self.soil = next_u32(self.soil)
            if (self.soil >> 8) % 1000 < loose:
                self.pack_left = 0
            self.soil = next_u32(self.soil)
            if (self.soil >> 8) % 1000 < loose:
                self.pack_right = 0

    def showing(self):
        p = self.p
        if self.over or self.up_by <= 0 or self.next_snag >= p["snags"] or self.depth[self.next_snag] - self.up_by > p["show_depth"]:
            return 0
        return self.side[self.next_snag]

    def stroking(self, t):
        return t < self.stroke_until

    def advance_to(self, t):
        total = self.p["duration_ms"] // TICK
        while not self.over and (self.tick + 1) * TICK <= t and self.tick < total:
            self.step()
            self.tick += 1

    def step(self):
        p = self.p
        if not self.down or self.tick < self.stroke_to_tick:
            self.strain = max(0, self.strain - p["strain_ease"])
            return
        self.strain += p["strain_rise"]
        pack = (self.pack_left + self.pack_right) // 2
        self.up_by += tdiv((p["pull_rate"] + tdiv(self.strain * p["pull_gain"], 1000)) * (1000 - tdiv(pack * p["hold_pm"], 1000)), 1000)
        while self.next_snag < p["snags"] and self.up_by >= self.depth[self.next_snag]:
            self.strain += self.jump[self.next_snag]
            self.next_snag += 1
            self.caught += 1
        if self.strain > 1000:
            self.worth += tdiv(min(self.up_by, 1000) * p["snap_keep_pm"], 1000)
            self.snapped += 1
            self.next_plant()
        elif self.up_by >= 1000:
            self.worth += 1000
            self.whole += 1
            self.next_plant()

    def next_plant(self):
        self.plant += 1
        self.draw()
        self.strain = self.up_by = self.next_snag = 0
        self.draw_soil()

    def press(self, t, code):
        if t < self.last_t:
            return
        self.last_t = t
        if t < 0 or t > self.p["duration_ms"]:
            return
        self.advance_to(t)
        if self.over:
            return
        if code == PULL_DOWN:
            self.down = True
        elif code == PULL_UP:
            self.down = False
        elif code in (PULL_LEFT, PULL_RIGHT) and not self.stroking(t):
            self.stroke_until = t + self.p["stroke_ms"]
            self.stroke_to_tick = self.stroke_until // TICK
            if self.showing() == code:
                self.next_snag += 1
                self.cut += 1
            elif code == PULL_LEFT and self.pack_left > 0:
                self.pack_left = max(0, self.pack_left - self.p["dig_pm"])
                self.dug += 1
            elif code == PULL_RIGHT and self.pack_right > 0:
                self.pack_right = max(0, self.pack_right - self.p["dig_pm"])
                self.dug += 1

    def result(self):
        if not self.finished:
            self.finished = True
            self.advance_to(self.p["duration_ms"] // TICK * TICK)
            self.over = True
            self.worth += tdiv(min(self.up_by, 1000) * self.p["snap_keep_pm"], 1000)
        return {"whole": self.whole, "snapped": self.snapped, "caught": self.caught, "cut": self.cut, "dug": self.dug,
                "worth": self.worth, "score_pm": min(1000, self.worth // max(1, self.p["target_plants"]))}


def pull_play(seed, p, inputs):
    m = Pull(seed, p)
    for t, c in inputs:
        m.press(t, c)
    return m.result()


def pull_bot(seed, p, hi=850, lo=500, digs=2, cuts=True, react_ms=0):
    """Digs each stem round first (`digs` strokes on each packed side, left then right; a loose side not at all), then holds while the strain is under `hi`,
    lets go at it and pulls again once it has eased to `lo`; with `cuts`, strokes the side whose soil cracks (seen
    `react_ms` late). Looks every 50 ms; a stroke only once the last is done."""
    m = Pull(seed, p)
    out = []
    t = 0
    seen_since = None
    plant = -1
    left = right = 0
    while t <= p["duration_ms"]:
        m.advance_to(t)
        if m.plant != plant:
            plant, left, right = m.plant, 0, 0
        show = m.showing()
        if show and seen_since is None:
            seen_since = t
        elif not show:
            seen_since = None
        code = None
        if not m.stroking(t):
            if cuts and show and t - seen_since >= react_ms:
                code = show
            elif m.up_by == 0 and left < digs and m.pack_left > 0:
                code, left = PULL_LEFT, left + 1
            elif m.up_by == 0 and right < digs and m.pack_right > 0:
                code, right = PULL_RIGHT, right + 1
        if code is not None:
            out.append([t, code])
            m.press(t, code)
        elif ((left >= digs or m.pack_left == 0) and (right >= digs or m.pack_right == 0)) or m.up_by > 0:
            want = m.strain < hi if m.down else m.strain <= lo
            if want != m.down:
                c = PULL_DOWN if want else PULL_UP
                out.append([t, c])
                m.press(t, c)
        t += 50
    return out


# --- skinning's cut line (HERBALISM_HUNTING_PREP.md H4, Luke 2026-11-07: drag the knife along it; built 2026-11-10) ---
SKIN_LIFT = -1


def skin_isqrt(n):
    """The floor of the square root (any exact method agrees; this one is not Newton's, so the twins' are checked)."""
    if n <= 0:
        return 0
    lo, hi = 0, n
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if mid * mid <= n:
            lo = mid
        else:
            hi = mid - 1
    return lo


class Skin:
    """The hide 1000 x 1000; a line of `points` points across it (left to right or back), each up or down by up to
    `wobble`, drawn from the seed as it starts. The knife held in the hide cuts along the line while it is on it (within
    `near` of the tip's stretch or the next) and within `reach` of the tip, no faster than cut_speed a tick; anywhere
    else it tears. A line done is worth 1000 less tear_pm a tear; the knife lifts; the next is drawn. The rules in full
    are on SkinModel."""

    def __init__(self, seed, p):
        self.p = p
        self.st = seed_state(seed)
        self.draw()
        self.first = (list(self.xs), list(self.ys))
        self.tick = 0
        self.down = False
        self.kx = self.ky = 0
        self.lines = self.clean = self.torn = self.worth = 0
        self.last_t = -1
        self.over = False

    def draw(self):
        p = self.p
        n = max(2, p["points"])
        self.st = next_u32(self.st)
        back = (self.st >> 8) % 2 == 1
        self.xs, self.ys = [], []
        for k in range(n):
            u = 100 + tdiv(k * 800, n - 1)
            self.st = next_u32(self.st)
            self.xs.append(1000 - u if back else u)
            self.ys.append(500 + (self.st >> 8) % (2 * p["wobble"] + 1) - p["wobble"])
        self.lens = [max(1, skin_isqrt((self.xs[k + 1] - self.xs[k]) ** 2 + (self.ys[k + 1] - self.ys[k]) ** 2)) for k in range(n - 1)]
        self.seg = self.f = self.tears = 0

    def tip(self):
        s = self.seg
        return (self.xs[s] + tdiv((self.xs[s + 1] - self.xs[s]) * self.f, 1000), self.ys[s] + tdiv((self.ys[s + 1] - self.ys[s]) * self.f, 1000))

    def on_stretch(self, k, x, y):
        dx, dy = self.xs[k + 1] - self.xs[k], self.ys[k + 1] - self.ys[k]
        cross = dx * (y - self.ys[k]) - dy * (x - self.xs[k])
        return cross * cross <= self.p["near"] ** 2 * (dx * dx + dy * dy)

    def cuts_at(self, x, y):
        tx, ty = self.tip()
        if (x - tx) ** 2 + (y - ty) ** 2 > self.p["reach"] ** 2:
            return False
        return self.on_stretch(self.seg, x, y) or (self.seg + 2 < len(self.xs) and self.on_stretch(self.seg + 1, x, y))

    def advance_to(self, t):
        total = self.p["duration_ms"] // TICK
        while not self.over and (self.tick + 1) * TICK <= t and self.tick < total:
            self.step()
            self.tick += 1

    def step(self):
        p = self.p
        if not self.down:
            return
        if not self.cuts_at(self.kx, self.ky):
            self.tears += 1
            self.torn += 1
            return
        s = self.seg
        dx, dy = self.xs[s + 1] - self.xs[s], self.ys[s + 1] - self.ys[s]
        dot = dx * (self.kx - self.xs[s]) + dy * (self.ky - self.ys[s])
        along = tdiv(dot * 1000, dx * dx + dy * dy) if dot > 0 else 0
        if s + 2 < len(self.xs) and self.on_stretch(s + 1, self.kx, self.ky) and                 (self.xs[s + 2] - self.xs[s + 1]) * (self.kx - self.xs[s + 1]) + (self.ys[s + 2] - self.ys[s + 1]) * (self.ky - self.ys[s + 1]) > 0:
            along = 1000   # past the bend, on the next stretch: the cut runs to the bend
        if along <= self.f:
            return
        self.f = min(along, self.f + max(1, tdiv(p["cut_speed"] * 1000, self.lens[s])))
        if self.f < 1000:
            return
        if s + 2 < len(self.xs):
            self.seg, self.f = s + 1, 0
            return
        self.worth += max(0, 1000 - self.tears * p["tear_pm"])
        self.lines += 1
        self.clean += self.tears == 0
        self.down = False
        self.draw()

    def press(self, t, x, y):
        if t < self.last_t:
            return
        self.last_t = t
        if t < 0 or t > self.p["duration_ms"]:
            return
        self.advance_to(t)
        if self.over:
            return
        if x == SKIN_LIFT:
            self.down = False
        elif 0 <= x <= 1000 and 0 <= y <= 1000:
            self.kx, self.ky, self.down = x, y, True

    def result(self):
        if not self.over:
            p = self.p
            self.advance_to(p["duration_ms"] // TICK * TICK)
            self.over = True
            done = tdiv(self.seg * 1000 + self.f, max(1, len(self.xs) - 1))
            self.worth += tdiv(tdiv(max(0, 1000 - self.tears * p["tear_pm"]) * done, 1000) * p["part_keep_pm"], 1000)
        return {"lines": self.lines, "clean": self.clean, "torn": self.torn, "worth": self.worth,
                "score_pm": min(1000, self.worth // max(1, self.p["target_lines"]))}


def skin_play(seed, p, inputs):
    m = Skin(seed, p)
    for t, x, y in inputs:
        m.press(t, x, y)
    return m.result()


def skin_bot(seed, p, lead=None, wander=0, react_ms=0, lift_after=0, rng=None, until=None, off=0):
    """A hand on the knife, looking every 50 ms: presses at a new line's start `react_ms` after it shows; held, aims
    `lead` along the line past the tip (the cut's pace by default) and `wander` across it (a random walk with `rng`);
    torn `lift_after` looks running (0: never), it lifts and presses again at the tip. `off`: held, it aims this far
    across the line (70: every look tears)."""
    m = Skin(seed, p)
    lead = p["cut_speed"] if lead is None else lead
    out, t, line_at, line, drift, torn_run, seen_torn = [], 0, 0, 0, 0.0, 0, 0
    end = p["duration_ms"] if until is None else until
    while t <= end:
        m.advance_to(t)
        torn_run = torn_run + 1 if m.down and m.torn > seen_torn else 0
        seen_torn = m.torn
        if m.lines != line:
            line, line_at = m.lines, t
        if not m.down:
            if t - line_at >= react_ms:
                tx, ty = m.tip()
                out.append([t, tx, ty])
                m.press(t, tx, ty)
                torn_run = 0
        else:
            tx, ty = m.tip()
            # `lead` along the line from the tip (over the stretch's end into the next), then off it by the drift.
            s, left, x, y = m.seg, float(lead), float(tx), float(ty)
            while left > 0 and s < len(m.xs) - 1:
                ex, ey = m.xs[s + 1] - x, m.ys[s + 1] - y
                d = (ex * ex + ey * ey) ** 0.5
                if d >= left or s == len(m.xs) - 2:
                    k = min(1.0, left / d) if d > 0 else 0.0
                    x, y, left = x + ex * k, y + ey * k, 0
                else:
                    x, y, left, s = float(m.xs[s + 1]), float(m.ys[s + 1]), left - d, s + 1
            if rng is not None and wander > 0:
                drift = drift * 0.8 + rng.gauss(0.0, wander * 0.6)
            ax, ay = max(0, min(1000, round(x))), max(0, min(1000, round(y + drift + off)))
            if lift_after > 0 and torn_run >= lift_after:
                out.append([t, SKIN_LIFT, SKIN_LIFT])
                m.press(t, SKIN_LIFT, SKIN_LIFT)
                drift, torn_run = 0.0, 0
                line_at = t + 50 - react_ms   # presses again at the next look
            else:
                out.append([t, ax, ay])
                m.press(t, ax, ay)
        t += 50
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
        case = dict(name=name, **seed_fields(seed), params=p, inputs=inputs,
                    points=[c for xy in seams(seed, p, 3) for c in xy], expected=crack_play(seed, p, inputs))
        if p.get("brittle_permille", 0) > 0:
            case["brittle"] = brittle_of(seed, p, 3 * p["notches"])
        crack.append(case)

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

    # Brittle notches (band 2, a test, 2026-11-07): their own stream, so the cases above never change.
    coal = dict(crack_p, notches=9, bend_pm=200, radius_pm=60, target_hits=28, brittle_permille=350, ring_ms=450)
    add_crack("brittle: a patient miner waits out the ring", 4242, coal, crack_patient(4242, coal))
    add_crack("brittle: an eager miner strikes in the ring and cracks it wrong", 4242, coal, crack_patient(4242, coal, eager=True))
    add_crack("brittle everywhere, a seam's first notch never", 7, dict(coal, brittle_permille=1000), crack_patient(7, dict(coal, brittle_permille=1000), eager=True))

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
                          outline=list(m.outline), expected=shape_play(seed, p, inputs)))

    add_shape("a careful smith", 7, shape_p, shape_bot(7, shape_p, 400))
    add_shape("a high-bit seed, never reheats", 0xFEDCBA9876543210, shape_p, shape_bot(0xFEDCBA9876543210, shape_p, -100000))
    add_shape("seed 0", 0, shape_p, shape_bot(0, shape_p, 400))
    wild = [[t, rng.randint(-2, 17)] for t in sorted(rng.randint(-100, 15200) for _ in range(120))]
    wild.insert(20, [10, 3])
    add_shape("hammering anywhere, out of order", 0x1234567890ABCDEF, shape_p, wild)
    heavy = dict(shape_p, hammer_drop=7, spread_pct=40, heat_ms=3000, start_jitter=5)
    add_shape("a heavy hammer, a quick-cooling bar", 31337, heavy, shape_bot(31337, heavy, 600))
    add_shape("nothing struck", 42, shape_p, [])
    # The light tap (2026-11-05): a heavy strike that spreads, and a tap to finish the line.
    two = dict(shape_p, hammer_drop=6, spread_pct=17, tap_drop=1, tap_spread_pct=0)
    add_shape("two strikes: rough out, then tap to the line", 7, two, shape_bot(7, two, 400))
    add_shape("taps switched off: every tap ignored", 7, shape_p, [[300 * i, TAP + i % 16] for i in range(12)] + [[3610, 3]])
    spready = dict(two, tap_drop=2, tap_spread_pct=50)
    taps = [[t, rng.choice([TAP + rng.randint(-2, 17), rng.randint(-2, 17), 999, TAP + 16, TAP + 15, TAP])]
            for t in sorted(rng.randint(-100, 15200) for _ in range(120))]
    add_shape("taps that spread, taps off the bar", 0x1234567890ABCDEF, spready, taps)
    # The anvil's bands, a test (Luke, 2026-11-05): heats instead of a clock, each costing the ceiling; the outline
    # varies and shows only when the template is laid on (no strikes while it is); iron also pays for each lay;
    # steel cracks when struck red and ends in a quench.
    band1 = dict(two, duration_ms=60000, reheat_ms=600, max_reheats=5, reheat_cost_pm=40, hide_outline=1, outline_vary=3)
    band2 = dict(band1, hammer_drop=5, spread_pct=20, start_height=23, lay_cost_pm=30)
    band3 = dict(band2, red_ms=1200, crack_cost_pm=60, quench_lo_pm=250, quench_hi_pm=450, quench_bonus_pm=60,
                 quench_loss_pm=150)
    add_shape("band 1: template, heats, set down", 7, band1, shape_bot(7, band1, 300))
    add_shape("band 2: harder metal, each lay costs", 0xFEDCBA9876543210, band2, shape_bot(0xFEDCBA9876543210, band2, 300))
    add_shape("band 3: red strikes crack, quenched", 99, band3, shape_bot(99, band3, 300))
    add_shape("the outline varies, nothing else", 5, dict(shape_p, outline_vary=4), [])
    add_shape("struck under the template: nothing", 3, band1,
              [[100, 4], [200, LAY], [300, LIFT], [400, 4], [500, LAY], [700, 5], [900, LIFT], [900, 5], [1300, LIFT]])
    reheats = [[t * 700, -1] for t in range(9)]
    add_shape("heats run out: the sixth reheat is not one", 3, dict(band1, hide_outline=0), reheats)
    add_shape("set down: nothing after counts", 3, dict(band1, hide_outline=0), [[100, 2], [500, DONE], [900, 2], [1300, -1]])
    add_shape("no heats, no set down (an old round)", 3, dict(shape_p, hide_outline=0), [[100, 2], [500, DONE], [900, 2]])
    add_shape("no template: lay and lift are nothing", 3, dict(band1, hide_outline=0), [[100, LAY], [200, 2], [600, LIFT]])
    red = [[300, LIFT], [3900, 1], [4300, 2], [4700, 3], [5100, 4], [5400, DONE]]
    add_shape("struck red, then quenched cold", 11, band3, red)
    add_shape("quenched in the window", 11, band3, [[300, LIFT], [400, 1], [700, 2], [3600, DONE]])
    add_shape("quenched too hot", 11, band3, [[300, LIFT], [400, 1], [700, 2], [1000, DONE]])

    # Smelting as a rhythm track (Luke, 2026-11-07): its own random source, so the cases above never change.
    brng = random.Random(20261107)
    beat_p = {"beat_ms": 600, "lead_beats": 4, "beats": 16, "rest_pm": 150, "offbeat_pm": 120, "hold_pm": 100,
              "hold_beats": 2, "perfect_ms": 70, "good_ms": 150, "good_pm": 600, "stray_pm": 250, "pour_ms": 4000,
              "pour_ready_ms": 600, "pour_rate": 28, "target_lo": 620, "target_hi": 820, "pour_tolerance": 220,
              "track_weight_pct": 70}
    beat = []

    def add_beat(name, seed, p, inputs):
        m = Beat(seed, p)
        case = dict(name=name, **seed_fields(seed), params=p, inputs=inputs, notes=[c for n in m.notes for c in n],
                    expected=beat_play(seed, p, inputs))
        if p.get("slag_pm", 0) > 0:
            case["slag"] = m.slag
        beat.append(case)

    add_beat("on the beat", 99, beat_p, beat_bot(99, beat_p, 0, brng))
    add_beat("a high-bit seed, a loose hand", 0xFEDCBA9876543210, beat_p, beat_bot(0xFEDCBA9876543210, beat_p, 140, brng))
    add_beat("seed 0, notes skipped, draws let go early, pours late (spills)", 0, beat_p,
             beat_bot(0, beat_p, 40, brng, skip_pct=25, early_release_ms=500, pour_late_ms=3000))
    busy = dict(beat_p, beat_ms=480, beats=20, rest_pm=100, offbeat_pm=320, hold_pm=150, perfect_ms=50, good_ms=115)
    add_beat("steel: quick, off-beats, more draws", 31337, busy, beat_bot(31337, busy, 60, brng))
    mash = [[t, 1 + (i % 2)] for i, t in enumerate(range(0, 16000, 40))]
    add_beat("mashing: every note hit, every stray paid for", 8, beat_p, mash)
    wild = [[t, brng.choice([1, 1, 2, 2, 0, 3, 9])] for t in sorted(brng.randint(-200, 16300) for _ in range(160))]
    wild.insert(40, [50, 1])
    add_beat("every key, out of order", 0x1234567890ABCDEF, beat_p, wild)
    held = Beat(5, beat_p)
    add_beat("held down from the first note: one hit, the rest missed", 5, beat_p, [[held.notes[0][0], 1]])
    add_beat("no pour: the track is the score", 7, dict(beat_p, pour_ms=0), beat_bot(7, dict(beat_p, pour_ms=0), 30, brng))
    add_beat("in the pour: a press too soon does nothing, then tilts and tops up", 12, beat_p,
             [[12000, 1], [12500, 2], [12650, 1], [13000, 2], [13100, 1], [14500, 2]])
    add_beat("nothing pressed", 42, beat_p, [])
    # Slag (band 2, a test): only the steel round has it; the cases above never change.
    slag_p = dict(busy, slag_pm=200)
    add_beat("slag: skimmed with the second button", 31337, slag_p, beat_bot_slag(31337, slag_p))
    add_beat("slag: pressed with the main button, wasted and missed", 31337, slag_p, beat_bot_slag(31337, slag_p, wrong_key=True))
    add_beat("a round with no slag ignores a skim", 99, beat_p, [[2400, 3], [2700, 3], [3000, 1], [3060, 2]])
    add_beat("slag: a skim on no slag is wasted", 31337, slag_p, [[100, 3], [1000, 3]] + beat_bot_slag(31337, slag_p))

    # Carving (Luke, 2026-11-07): its own random source.
    crng = random.Random(20261108)
    carve_p = {"duration_ms": 16000, "swing_ms": 240, "start_half": 10, "start_jitter": 1, "deep_cut": 3, "fine_cut": 1,
               "left_outline": [3, 4, 5, 6, 7, 8, 9, 9, 9, 8, 7, 6, 5, 4, 3, 2],
               "right_outline": [3, 3, 4, 4, 5, 6, 8, 9, 9, 8, 6, 5, 4, 4, 3, 3],
               "outline_vary": 2, "error_scale": 30, "hide_outline": 1, "lay_cost_pm": 30, "mirror": 0}
    carve = []

    def add_carve(name, seed, p, inputs):
        m = Carve(seed, p)
        carve.append(dict(name=name, **seed_fields(seed), params=p, inputs=inputs, start_left=m.left, start_right=m.right,
                          target_left=m.tl, target_right=m.tr, expected=carve_play(seed, p, inputs)))

    add_carve("a careful carver, set down when done", 7, carve_p, carve_bot(7, carve_p))
    add_carve("a high-bit seed, looks again", 0xFEDCBA9876543210, carve_p, carve_bot(0xFEDCBA9876543210, carve_p, look_again=True))
    add_carve("seed 0, never sets it down", 0, carve_p, carve_bot(0, carve_p, done=False))
    add_carve("cuts under the pattern: nothing", 3, carve_p, [[100, 1000], [200, 3005], [300, CARVE_LIFT], [600, 1000], [700, 1001]])
    add_carve("mid-swing: held to the swing's end, the latest wins", 5, carve_p,
              [[300, CARVE_LIFT], [400, 1000], [450, 1001], [500, 4002], [800, 3003], [2000, CARVE_DONE], [2100, 1000]])
    over = [[300, CARVE_LIFT]] + [[400 + k * 240, 1000] for k in range(8)]
    add_carve("over-cut: wood never goes back", 9, carve_p, over)
    wild = [[t, crng.choice([1000 + crng.randint(0, 17), 2000 + crng.randint(0, 17), 3000 + crng.randint(-1, 16),
                              4000 + crng.randint(0, 16), CARVE_LAY, CARVE_LIFT, 999, 6000])]
            for t in sorted(crng.randint(-100, 16300) for _ in range(140))]
    wild.insert(30, [50, CARVE_LIFT])
    add_carve("every code, out of order", 0x1234567890ABCDEF, carve_p, wild)
    add_carve("no pattern: always shown", 11, dict(carve_p, hide_outline=0), carve_bot(11, dict(carve_p, hide_outline=0)))
    add_carve("nothing pressed", 42, carve_p, [])
    # The unstrung bow: a C, both edges curving across the middle line, flipped by the seed.
    bow_c = dict(carve_p, start_half=10, deep_cut=4, mirror=1,
                 left_outline=[1, 0, -2, -2, -3, -3, -3, -3, -2, -2, 0, 1], right_outline=[3, 4, 6, 8, 9, 9, 9, 9, 8, 6, 4, 3])
    add_carve("an unstrung bow, flipped by its seed", 7, bow_c, carve_bot(7, bow_c))
    add_carve("an unstrung bow, as written", 99, bow_c, carve_bot(99, bow_c))
    add_carve("a cut never goes through the other edge", 3, dict(bow_c, hide_outline=0),
              [[200 + k * 240, 1000 + 4] for k in range(12)])

    pull_p = {"duration_ms": 15000, "stroke_ms": 350, "target_plants": 3, "dig_pm": 500, "hold_pm": 600, "strain_rise": 40,
              "strain_ease": 60, "pull_rate": 10, "pull_gain": 40, "snags": 3, "jump_lo": 200, "jump_hi": 400, "show_depth": 350,
              "snap_keep_pm": 250}
    pull = []

    def add_pull(name, seed, p, inputs):
        m = Pull(seed, p)
        pull.append(dict(name=name, **seed_fields(seed), params=p, inputs=inputs, snag_depth=m.first[0], snag_jump=m.first[1],
                         snag_side=m.first[2], expected=pull_play(seed, p, inputs)))

    add_pull("dug round, every side root cut", 7, pull_p, pull_bot(7, pull_p))
    add_pull("dug round, cut late", 1 + 7919, pull_p, pull_bot(1 + 7919, pull_p, react_ms=300))
    add_pull("never digs: packed soil holds the root", 1 + 2 * 7919, pull_p, pull_bot(1 + 2 * 7919, pull_p, digs=0))
    add_pull("never cuts: pulled through every side root", 1 + 3 * 7919, pull_p, pull_bot(1 + 3 * 7919, pull_p, cuts=False))
    add_pull("greedy, never cuts: they snap", 1 + 4 * 7919, pull_p, pull_bot(1 + 4 * 7919, pull_p, hi=980, lo=800, cuts=False))
    add_pull("held from the start: stem after stem snaps", 0, pull_p, [[0, PULL_DOWN]])
    add_pull("a high-bit seed, dug once a side", 0xFEDCBA9876543210, pull_p, pull_bot(0xFEDCBA9876543210, pull_p, digs=1, react_ms=200))
    add_pull("nothing pressed", 42, pull_p, [])
    add_pull("only strokes: dug, then scraped, nothing pulled", 3, pull_p,
             [[0, PULL_LEFT], [100, PULL_LEFT], [350, PULL_LEFT], [700, PULL_LEFT], [1050, PULL_RIGHT], [1400, PULL_LEFT]])
    add_pull("a stroke stops the pull while it runs", 5, dict(pull_p, snags=0, hold_pm=0),
             [[0, PULL_DOWN], [400, PULL_LEFT], [600, PULL_RIGHT], [800, PULL_RIGHT], [3000, PULL_UP]])
    add_pull("the wrong side digs, it does not cut", 9, pull_p,
             [[0, PULL_LEFT], [400, PULL_LEFT], [800, PULL_RIGHT], [1200, PULL_RIGHT], [1500, PULL_DOWN]] +
             [[1550 + 100 * k, PULL_LEFT + (k % 2)] for k in range(40)])
    wild = [[0, PULL_UP], [100, PULL_DOWN], [100, PULL_DOWN], [90, PULL_UP], [700, 9], [800, PULL_UP], [800, PULL_RIGHT], [-5, PULL_DOWN],
            [1200, PULL_DOWN], [1210, PULL_LEFT], [1220, PULL_LEFT], [20000, PULL_UP]]
    add_pull("every code, out of order, past the end", 0x1234567890ABCDEF, pull_p, wild)
    add_pull("still in the ground at the end: part of what came up", 1 + 5 * 7919, dict(pull_p, duration_ms=2500),
             pull_bot(1 + 5 * 7919, dict(pull_p, duration_ms=2500)))
    add_pull("no side roots", 11, dict(pull_p, snags=0), pull_bot(11, dict(pull_p, snags=0), hi=950, lo=800))
    top_p = dict(pull_p, snags=0, hold_pm=0)
    add_pull("held to exactly the top: 1000 holds", 13, top_p, [[0, PULL_DOWN], [1250, PULL_UP], [2000, PULL_DOWN], [3000, PULL_UP]])
    add_pull("one tick past the top: it snaps", 13, top_p, [[0, PULL_DOWN], [1300, PULL_UP]])
    quick = dict(pull_p, stroke_ms=175, jump_lo=176, jump_hi=352, hold_pm=528)
    add_pull("a quick trowel, eased side roots and soil", 1 + 6 * 7919, quick, pull_bot(1 + 6 * 7919, quick, react_ms=250))
    flax_p = dict(pull_p, stroke_ms=250, snags=2)
    add_pull("flax as first tuned: dug round, cut", 1 + 7 * 7919, flax_p, pull_bot(1 + 7 * 7919, flax_p, react_ms=200))
    add_pull("flax as first tuned: dug once a side, never cuts", 1 + 8 * 7919, flax_p,
             pull_bot(1 + 8 * 7919, flax_p, digs=1, cuts=False, hi=900, lo=600))
    # LOOSE OR PACKED (Luke, 2026-11-09: no chore): each side of each stem loose with a chance, from its own stream.
    soil_p = dict(flax_p, loose_pm=500, dig_pm=1000)
    add_pull("loose or packed: only the packed sides dug, cut", 1 + 9 * 7919, soil_p, pull_bot(1 + 9 * 7919, soil_p, digs=1, react_ms=200))
    add_pull("loose or packed: never digs", 1 + 10 * 7919, soil_p, pull_bot(1 + 10 * 7919, soil_p, digs=0, react_ms=200))
    add_pull("every side loose: nothing to dig", 1 + 11 * 7919, dict(soil_p, loose_pm=1000), pull_bot(1 + 11 * 7919, dict(soil_p, loose_pm=1000), digs=1))
    add_pull("loose or packed, a high-bit seed: a stroke into loose soil scrapes", 0xFEDCBA9876543210, soil_p,
             [[0, PULL_LEFT], [300, PULL_RIGHT], [600, PULL_DOWN], [4000, PULL_UP], [4100, PULL_LEFT], [4400, PULL_DOWN]])
    # SKINNING'S CUT LINE (Luke's H4; built 2026-11-10): drag the knife along it, off it tears the hide.
    skin_p = {"duration_ms": 12000, "target_lines": 3, "points": 5, "wobble": 120, "near": 40, "reach": 120, "cut_speed": 30,
              "tear_pm": 60, "part_keep_pm": 500}
    skin = []

    def add_skin(name, seed, p, inputs):
        m = Skin(seed, p)
        skin.append(dict(name=name, **seed_fields(seed), params=p, inputs=inputs, line_x=m.first[0], line_y=m.first[1],
                         expected=skin_play(seed, p, inputs)))

    add_skin("traced at the cut's pace", 7, skin_p, skin_bot(7, skin_p))
    add_skin("traced a little behind, seen late", 1 + 7919, skin_p, skin_bot(1 + 7919, skin_p, lead=20, react_ms=300))
    add_skin("a wandering hand", 1 + 2 * 7919, skin_p, skin_bot(1 + 2 * 7919, skin_p, wander=30, rng=random.Random(11)))
    add_skin("a wandering hand that lifts when it tears", 1 + 3 * 7919, skin_p,
             skin_bot(1 + 3 * 7919, skin_p, wander=45, rng=random.Random(12), lift_after=2, react_ms=150))
    add_skin("run ahead of the cut: it tears", 1 + 4 * 7919, skin_p, skin_bot(1 + 4 * 7919, skin_p, lead=160))
    add_skin("pushed just within reach", 1 + 5 * 7919, skin_p, skin_bot(1 + 5 * 7919, skin_p, lead=110))
    m0 = Skin(9, skin_p)
    add_skin("rests on the line's start: no cut, no tear", 9, skin_p, [[0, m0.first[0][0], m0.first[1][0]]])
    add_skin("pressed in the middle of the hide and held", 0, skin_p, [[0, 500, 100]])
    add_skin("nothing pressed", 42, skin_p, [])
    m1 = Skin(13, skin_p)
    x0, y0 = m1.first[0][0], m1.first[1][0]
    wild = [[0, SKIN_LIFT, SKIN_LIFT], [50, x0, y0], [40, 900, 900], [100, 1001, 5], [150, -2, 7], [200, x0, y0 + 5], [200, 700, 700],
            [-5, x0, y0], [400, SKIN_LIFT, 3], [450, SKIN_LIFT, SKIN_LIFT], [500, 300, -1], [20000, 10, 10], [600, x0, y0]]
    add_skin("every kind of input, out of order and out of range", 0x1234567890ABCDEF, skin_p, wild)
    add_skin("still cutting at the end: part of what was cut", 1 + 6 * 7919, dict(skin_p, duration_ms=1500),
             skin_bot(1 + 6 * 7919, dict(skin_p, duration_ms=1500)))
    quick = dict(skin_p, cut_speed=60, near=46)
    add_skin("a quick knife, eased", 1 + 7 * 7919, quick, skin_bot(1 + 7 * 7919, quick, wander=30, rng=random.Random(13)))
    straight = dict(skin_p, points=2, wobble=0)
    add_skin("a straight line", 1 + 8 * 7919, straight, skin_bot(1 + 8 * 7919, straight))
    add_skin("a high-bit seed, a bendy line", 0xFEDCBA9876543210, dict(skin_p, points=9, wobble=250),
             skin_bot(0xFEDCBA9876543210, dict(skin_p, points=9, wobble=250), wander=20, rng=random.Random(14), lift_after=3))
    add_skin("tears cost more than a line is worth", 1 + 9 * 7919, dict(skin_p, tear_pm=400),
             skin_bot(1 + 9 * 7919, dict(skin_p, tear_pm=400), wander=40, rng=random.Random(15)))

    here = os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.join(here, "..", "..", "..", "shared", "golden", "regents")
    os.makedirs(outdir, exist_ok=True)
    for name, cases in (("crack", crack), ("smelt", smelt), ("shape", shape), ("beat", beat), ("carve", carve), ("pull", pull), ("skin", skin)):
        doc = {"_comment": "GENERATED by game/regents/tests/make_skill_goldens.py (%s): for the GDScript model and its "
                           "Rust twin. Do not edit." % name, "cases": cases}
        with open(os.path.join(outdir, name + ".json"), "wb") as f:
            f.write((json.dumps(doc, indent=1) + "\n").encode())
        for c in cases:
            print(name, "|", c["name"], c["expected"])


if __name__ == "__main__":   # importable: the integration hook's cut-line bot uses its Skin (skin_bot.py)
    main()
