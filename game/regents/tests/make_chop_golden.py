"""WOODCUTTING'S BRANCH DODGE, A THIRD TIME: the golden vectors for `ChopModel` (GDScript) and
`genre::regents::chop` (Rust), made by this independent Python version so neither twin checks
itself. Both twins must reproduce every case exactly (integers: nothing to round).

    python game/regents/tests/make_chop_golden.py      (from the repo root)

writes shared/golden/regents/chop.json. Change the model's rules here AND in both twins, run this,
and commit the new file with the change. A seed is two 32-bit halves (`seed_hi`, `seed_lo`), since
JSON numbers lose a u64's low bits and GDScript holds a u64 as a wrapped int64.
"""
import json
import os
import random

M32 = 0xFFFFFFFF
NONE, LEFT, RIGHT = 0, 1, 2
VIEW_SEGMENTS = 8


def next_u32(x):
    x &= M32
    x ^= (x << 13) & M32
    x ^= x >> 17
    x ^= (x << 5) & M32
    return x


def seed_state(seed):
    s = (seed ^ (seed >> 32)) & M32
    return 1 if s == 0 else s


def max_chops(p):
    return p["duration_ms"] // p["swing_ms"] + 1


def branches(seed, p, n):
    out = []
    st = seed_state(seed)
    for i in range(n):
        if i < p["safe_segments"]:
            out.append(NONE)
            continue
        st = next_u32(st)
        if ((st >> 8) * 1000) >> 24 >= p["branch_permille"]:
            out.append(NONE)
            continue
        st = next_u32(st)
        out.append(RIGHT if (st >> 31) & 1 == 1 else LEFT)
    return out


class Chop:
    """A press during a swing is HELD (the latest one) and lands the moment the swing ends; a press while
    staggered is lost."""

    def __init__(self, seed, p):
        self.p = p
        self.seg = branches(seed, p, max_chops(p) + 2 + VIEW_SEGMENTS)
        self.cut = self.clean = self.hits = self.combo = self.best = 0
        self.next_ok, self.last_t, self.staggered, self.held = 0, -1, False, None

    def act(self, t, s):
        head = self.seg[self.cut + 1] if self.cut + 1 < len(self.seg) else NONE
        if head == s:
            self.hits += 1
            self.combo = 0
            self.next_ok, self.staggered = t + self.p["stagger_ms"], True
            return 2
        self.cut += 1
        self.clean += 1
        self.combo += 1
        self.best = max(self.best, self.combo)
        self.next_ok, self.staggered = t + self.p["swing_ms"], False
        return 1

    def settle(self, t):
        if self.held is not None and self.held[0] <= t:
            at, s = self.held
            self.held = None
            if at <= self.p["duration_ms"]:
                return self.act(at, s)
        return 0

    def chop(self, t, s):
        if t < self.last_t:
            return 0
        self.last_t = t
        self.settle(t)
        if t < 0 or t > self.p["duration_ms"] or s not in (LEFT, RIGHT):
            return 0
        if t < self.next_ok:
            if self.staggered:
                return 0
            self.held = (self.next_ok, s)
            return 3
        return self.act(t, s)

    def result(self):
        self.settle(self.p["duration_ms"])
        return {"clean": self.clean, "hits": self.hits, "best_combo": self.best,
                "score_pm": min(1000, self.clean * 1000 // self.p["target_chops"])}


def play(seed, p, inputs):
    m = Chop(seed, p)
    for t, s in inputs:
        m.chop(t, s)
    return m.result(), m.seg


def perfect(seed, p):
    seg = branches(seed, p, max_chops(p) + 2 + VIEW_SEGMENTS)
    out, cut, side, t = [], 0, LEFT, 0
    while t <= p["duration_ms"]:
        head = seg[cut + 1]
        side = RIGHT if head == LEFT else (LEFT if head == RIGHT else side)
        out.append([t, side])
        cut += 1
        t += p["swing_ms"]
    return out


def params(**kw):
    p = {"duration_ms": 10000, "swing_ms": 300, "stagger_ms": 800, "branch_permille": 450,
         "safe_segments": 2, "target_chops": 22}
    p.update(kw)
    return p


def main():
    rng = random.Random(20261018)
    cases = []

    def add(name, seed, p, inputs):
        r, seg = play(seed, p, inputs)
        cases.append({"name": name, "seed_hi": (seed >> 32) & M32, "seed_lo": seed & M32, "params": p,
                      "inputs": inputs, "segments": seg[:40], "expected": r})

    p = params()
    add("perfect player, the tree", 99, p, perfect(99, p))
    add("perfect player, a high-bit seed", 0xFEDCBA9876543210, p, perfect(0xFEDCBA9876543210, p))
    add("seed 0 folds to state 1", 0, p, perfect(0, p))
    add("always the left, branchy", 5, params(branch_permille=600), [[k * 300, LEFT] for k in range(34)])
    messy = []
    t = -50
    for _ in range(160):
        messy.append([t, rng.choice([LEFT, RIGHT, LEFT, RIGHT, 0, 3])])
        t += rng.randint(-60, 240)
    add("messy: early, out of order, no side, staggered, late", 0x1234567890ABCDEF, params(branch_permille=500), messy)
    add("no branches at all", 7, params(branch_permille=0), [[k * 250, RIGHT] for k in range(45)])
    add("every piece branched, nothing safe", 0xFFFFFFFFFFFFFFFF, params(branch_permille=1000, safe_segments=0),
        [[k * 300, LEFT if k % 2 == 0 else RIGHT] for k in range(30)])
    add("a yew, quick swings", 31337, params(branch_permille=620, target_chops=28, swing_ms=220, stagger_ms=1000),
        perfect(31337, params(branch_permille=620, target_chops=28, swing_ms=220, stagger_ms=1000)))
    add("the round's last millisecond and after", 11, params(branch_permille=0, duration_ms=1000, swing_ms=100),
        [[1000, LEFT], [1001, LEFT], [999, RIGHT]])
    add("quick side switches: presses mid-swing land when it ends", 2024, params(branch_permille=0),
        [[k * 120, LEFT if k % 2 == 0 else RIGHT] for k in range(60)])
    add("a press mid-swing after a stagger is lost; the latest held press wins", 77, params(branch_permille=700),
        [[0, LEFT], [40, RIGHT], [90, LEFT], [400, RIGHT], [450, LEFT], [460, RIGHT], [2000, LEFT], [2100, RIGHT]])
    add("a press held past the round's end never lands", 12, params(branch_permille=0, duration_ms=1000, swing_ms=300),
        [[0, LEFT], [300, LEFT], [600, LEFT], [900, RIGHT], [950, LEFT]])
    add("nothing pressed", 42, p, [])

    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "..", "..", "shared", "golden", "regents", "chop.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    doc = {"_comment": "GENERATED by game/regents/tests/make_chop_golden.py: woodcutting's branch dodge, "
                       "for ChopModel (GDScript) and genre::regents::chop (Rust). Do not edit.",
           "cases": cases}
    with open(out, "wb") as f:
        f.write((json.dumps(doc, indent=1) + "\n").encode())
    for c in cases:
        print(c["name"], c["expected"])


main()
