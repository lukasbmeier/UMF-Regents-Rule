"""THE WORLD IN SQUARES, for the load test's bots: the twin of `foundation/net/cells.gd` (and the module's
`server/src/cell.rs`), held to the same cases (`shared/golden/cells.json`, `tests/load/test_load.py`).
A bot's ring must re-centre exactly where a real client's does, or the harness measures another game.
"""
import math
import struct

GRID = 1024
HALF = GRID // 2


class Cells:
    def __init__(self, cell_m=64.0, ring=1, hysteresis_m=4.0):
        self.cell_m = float(cell_m)
        self.ring_r = int(ring)
        self.hysteresis_m = float(hysteresis_m)

    @staticmethod
    def from_doc(doc):
        """From `shared/rules.json` `cells`, or the interest dump's `cells`."""
        return Cells(doc.get("cell_m", 64.0), doc.get("ring", 1), doc.get("hysteresis_m", 4.0))

    def axis(self, v):
        # In f32, as the module works it out, so a place on an edge is in the same cell on both sides.
        q = struct.unpack("<f", struct.pack("<f", v / self.cell_m))[0]
        return max(-HALF, min(HALF - 1, math.floor(q)))

    @staticmethod
    def at(x, z):
        return (max(-HALF, min(HALF - 1, x)) + HALF) * GRID + (max(-HALF, min(HALF - 1, z)) + HALF)

    def chunk_of(self, x, z):
        return self.at(self.axis(x), self.axis(z))

    @staticmethod
    def squares(chunk):
        return (chunk // GRID - HALF, chunk % GRID - HALF)

    def ring(self, chunk, r=None):
        r = self.ring_r if r is None else r
        cx, cz = self.squares(chunk)
        return [self.at(x, z) for x in range(cx - r, cx + r + 1) for z in range(cz - r, cz + r + 1)
                if -HALF <= x < HALF and -HALF <= z < HALF]

    def recentre(self, centre, x, z):
        """Cells.recentre: the ring's centre moves once `hysteresis_m` inside another cell, at once on a jump."""
        here = self.chunk_of(x, z)
        if centre < 0 or here == centre:
            return here
        m, h = self.cell_m, self.hysteresis_m
        sx, sz = self.squares(here)
        in_x = min(x - sx * m, (sx + 1) * m - x)
        in_z = min(z - sz * m, (sz + 1) * m - z)
        ox, oz = self.squares(centre)
        if abs(sx - ox) > 1 or abs(sz - oz) > 1:
            return here
        deep = (sx == ox or in_x >= h) and (sz == oz or in_z >= h)
        return here if deep else centre
