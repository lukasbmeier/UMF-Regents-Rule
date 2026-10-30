"""A LEVEL'S BAKE AS THE LOAD TEST READS IT (`shared/world/<level>.json`, template 1.5): its spawn, where its
land is (the depth grid says where the water is), and, when the level bakes its ground
(`LevelInfo.bake_ground`), how high the ground is, so bots walk ON a hilly world instead of through it.

And WHERE EACH BOT LIVES (`homes`): the harness and every bot process compute the same homes from the same
seed, so the harness can cut the region referees where the bots really are (`load_test.regions_by_homes`).
How bots are spread is `shared/load.json` "spread":
  "square"  (the default) every bot anywhere in the `area_cells` square round the origin, walking anywhere in it;
  "level"   homes anywhere on the level's land, each bot walking within `roam_cells` of its home; a share of
            them (`crowd_share`) lives within `crowd_cells` of the spawn instead, a town where you start.
"""
import json
import math
import os
import random
import struct

GROUND_NONE = 65535


class Level:
    def __init__(self, doc, folder):
        self.name = doc["level"]
        self.id = int(doc["id"])
        sp = doc.get("spawn", [0.0, 0.0, 0.0])
        self.spawn = (float(sp[0]), float(sp[1]), float(sp[2]))
        self.water_y = float(doc.get("water_y", 0.0))
        g = doc["depth_grid"]
        self.d_x, self.d_z, self.d_step = float(g["origin_x"]), float(g["origin_z"]), float(g["spacing"])
        self.d_w, self.d_h = int(g["width"]), int(g["height"])
        with open(os.path.join(folder, g["file"]), "rb") as f:
            self.depth = f.read()
        self.ground_grid = None
        gg = doc.get("ground_grid")
        if gg:
            with open(os.path.join(folder, gg["file"]), "rb") as f:
                raw = f.read()
            w, h = int(gg["width"]), int(gg["height"])
            self.ground_grid = {"x": float(gg["origin_x"]), "z": float(gg["origin_z"]), "step": float(gg["spacing"]),
                                "w": w, "h": h, "base": float(gg["base_y"]),
                                "dm": struct.unpack("<%dH" % (w * h), raw[:w * h * 2])}
            self.extent = (self.ground_grid["x"], self.ground_grid["z"],
                           self.ground_grid["x"] + (w - 1) * self.ground_grid["step"],
                           self.ground_grid["z"] + (h - 1) * self.ground_grid["step"])
        else:
            self.extent = (self.d_x, self.d_z, self.d_x + (self.d_w - 1) * self.d_step, self.d_z + (self.d_h - 1) * self.d_step)

    @staticmethod
    def by_id(root, level_id):
        """The bake of level `level_id` in `root`/shared/world, or None (the greybox, 0, has none)."""
        folder = os.path.join(root, "shared", "world")
        if level_id <= 0 or not os.path.isdir(folder):
            return None
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".json"):
                continue
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                doc = json.load(f)
            if int(doc.get("id", -1)) == level_id:
                return Level(doc, folder)
        return None

    def has_ground(self):
        return self.ground_grid is not None

    def depth_dm(self, x, z):
        """The water's depth at (x, z) in decimetres (nearest sample); 0 off the grid (dry, as the server says)."""
        i = int(round((x - self.d_x) / self.d_step))
        j = int(round((z - self.d_z) / self.d_step))
        if i < 0 or j < 0 or i >= self.d_w or j >= self.d_h:
            return 0
        return self.depth[j * self.d_w + i]

    def ground(self, x, z):
        """The ground's height at (x, z), between the four samples round it; None with no ground there."""
        g = self.ground_grid
        if g is None:
            return None
        fx, fz = (x - g["x"]) / g["step"], (z - g["z"]) / g["step"]
        i, j = int(math.floor(fx)), int(math.floor(fz))
        if i < 0 or j < 0 or i + 1 >= g["w"] or j + 1 >= g["h"]:
            return None
        dm = g["dm"]
        q = [dm[j * g["w"] + i], dm[j * g["w"] + i + 1], dm[(j + 1) * g["w"] + i], dm[(j + 1) * g["w"] + i + 1]]
        if GROUND_NONE in q:
            return None
        tx, tz = fx - i, fz - j
        top = q[0] + (q[1] - q[0]) * tx
        bottom = q[2] + (q[3] - q[2]) * tx
        return g["base"] + (top + (bottom - top) * tz) / 10.0

    def dry(self, x, z):
        """Land a bot may stand on: inside the level, no water, and ground under it (when baked)."""
        x0, z0, x1, z1 = self.extent
        if not (x0 <= x <= x1 and z0 <= z <= z1) or self.depth_dm(x, z) > 0:
            return False
        return self.ground_grid is None or self.ground(x, z) is not None

    def segment_dry(self, a, b, step=8.0):
        """Whether the straight walk from a to b stays on land (the server refuses a step into deep water)."""
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(d / step))
        return all(self.dry(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n + 1))

    def random_land(self, rng, rect=None, tries=60):
        """A random dry point in `rect` (x0, z0, x1, z1; the whole level if None), or None."""
        x0, z0, x1, z1 = rect if rect is not None else self.extent
        for _ in range(tries):
            p = (rng.uniform(x0, x1), rng.uniform(z0, z1))
            if self.dry(*p):
                return p
        return None


def spread_of(cfg):
    """The load config's "spread", with its defaults."""
    s = dict(cfg.get("spread") or {})
    s.setdefault("over", "square")
    s.setdefault("crowd_share", 0.0)
    s.setdefault("crowd_cells", 4)
    s.setdefault("roam_cells", 6)
    return s


def home_of(index, seed, spread, level, area_cells, cell_m):
    """Where bot `index` lives: its own random draw (the same in the harness and in its bot process)."""
    rng = random.Random(seed * 7919 + index * 104729 + 17)
    half = area_cells * cell_m / 2.0
    if spread["over"] != "level" or level is None:
        return (rng.uniform(-half, half), rng.uniform(-half, half))
    sx, _, sz = level.spawn
    if rng.random() < float(spread["crowd_share"]):
        r = float(spread["crowd_cells"]) * cell_m / 2.0
        p = level.random_land(rng, (sx - r, sz - r, sx + r, sz + r))
        if p is not None:
            return p
    p = level.random_land(rng, tries=400)
    return p if p is not None else (sx, sz)


def homes(n, seed, spread, level, area_cells, cell_m):
    return [home_of(i, seed, spread, level, area_cells, cell_m) for i in range(n)]


def roam_rect(home, spread, level, area_cells, cell_m):
    """Where a bot from `home` walks: the area's square, or (spread over the level) `roam_cells` round its home."""
    if spread["over"] != "level" or level is None:
        half = area_cells * cell_m / 2.0
        return (-half, -half, half, half)
    r = float(spread["roam_cells"]) * cell_m / 2.0
    return (home[0] - r, home[1] - r, home[0] + r, home[1] + r)
