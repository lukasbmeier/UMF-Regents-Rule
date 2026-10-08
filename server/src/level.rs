//! Level bakes: what the module knows about a level's geography — where players appear, where
//! the water is and how deep, which named spots it holds. One per `shared/world/<level>.json`,
//! compiled in by build.rs (the JSON's numbers become the statics at the bottom of this file,
//! its depth grid is `include_bytes!`d).
//!
//! The bake is WRITTEN BY THE LEVEL'S GENERATOR from the terrain itself
//! (`tools/world/build_lakeside.gd`), so it describes the ground players actually walk on. The
//! module never loads a scene; this is all it will ever know about the level.
//!
//! PARITY. `foundation/sim/level_bake.gd` answers the same questions from the same files, and
//! must give the same answer for every point: a float the client's aim ring shows landing in the
//! water has to be a float the server accepts. So the lookup is nearest-cell on an integer grid,
//! done in f64 on both sides (GDScript's float is f64; an f32 subtraction here could round a
//! point sitting exactly on a cell edge into the neighbouring cell), and "is this water" compares
//! whole decimetres. No tolerance is involved anywhere, so there is nothing to drift.
//!
//! NO `spacetimedb` DEPENDENCY, like `sim` and `challenge`: native tests link this module
//! (DECISIONS #27).

/// A named piece of water: a loot table's worth of lake.
#[derive(Debug)]
pub struct Spot {
    pub id: &'static str,
    pub name: &'static str,
    pub x: f64,
    pub z: f64,
    pub radius: f64,
}

/// A named point a level designer placed (`LevelPoint`, DECISIONS #175): a basket, a tee, a coop, a
/// goal. Its `kind` says what it is to a genre; the foundation only carries it.
#[derive(Debug)]
pub struct Point {
    pub id: &'static str,
    pub kind: &'static str,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub radius: f64,
    pub tags: &'static [&'static str],
}

#[derive(Debug)]
pub struct LevelBake {
    pub name: &'static str,
    /// Its number: what a world's `world_level` row says it runs.
    pub id: u8,
    pub water_y: f32,
    /// Where a new player appears, feet on the ground.
    pub spawn: [f32; 3],
    /// The deepest a player may wade (the level's invisible barrier follows this contour).
    pub wade_depth: f32,
    /// A float needs at least this much water under it, in decimetres.
    pub min_cast_dm: u8,
    /// World X/Z of cell (0, 0)'s centre, and metres per cell.
    pub origin_x: f64,
    pub origin_z: f64,
    pub spacing: f64,
    pub width: usize,
    pub height: usize,
    /// Water depth per cell in decimetres, 0 = dry. Row-major, row 0 at `origin_z`.
    pub depth_dm: &'static [u8],
    /// Smallest first, so the first spot containing a point is the most specific one.
    pub spots: &'static [Spot],
    /// Everything else the designer marked, by kind.
    pub points: &'static [Point],
}

impl LevelBake {
    /// The grid cell whose centre is nearest (x, z), or None off the grid.
    pub fn cell(&self, x: f32, z: f32) -> Option<(usize, usize)> {
        let i = ((x as f64 - self.origin_x) / self.spacing + 0.5).floor();
        let j = ((z as f64 - self.origin_z) / self.spacing + 0.5).floor();
        // NaN fails every comparison below, and `NaN as usize` is 0: without this a NaN
        // position would read cell (0, 0) instead of being off the grid.
        if !i.is_finite() || !j.is_finite() {
            return None;
        }
        if i < 0.0 || j < 0.0 || i >= self.width as f64 || j >= self.height as f64 {
            return None;
        }
        Some((i as usize, j as usize))
    }

    /// Water depth at a point in whole decimetres; 0 on land and off the grid.
    pub fn depth_dm_at(&self, x: f32, z: f32) -> u8 {
        match self.cell(x, z) {
            Some((i, j)) => self.depth_dm[j * self.width + i],
            None => 0,
        }
    }

    /// Water depth at a point in metres.
    pub fn depth_at(&self, x: f32, z: f32) -> f32 {
        self.depth_dm_at(x, z) as f32 / 10.0
    }

    /// Deep enough for a float.
    pub fn is_water(&self, x: f32, z: f32) -> bool {
        self.depth_dm_at(x, z) >= self.min_cast_dm
    }

    /// Somewhere a player may stand (REVIEW 0.23.1 B2): land, water shallow enough to wade, a
    /// deck (the bake reads the dock's planks as dry), or off the grid. Deeper than `wade_depth`
    /// counts only when the point's cell AND its eight neighbours all are: the barrier follows the
    /// terrain, not this grid, so a player against it stands up to a cell from one that reads too
    /// deep. `apply_client_trust` refuses a Tier A claim that leaves standable ground. Twin:
    /// `LevelBake.can_stand` (the probes check both).
    pub fn can_stand(&self, x: f32, z: f32) -> bool {
        let Some((ci, cj)) = self.cell(x, z) else { return true };
        let wade_dm = (self.wade_depth * 10.0).round() as u8;
        for dj in -1i64..=1 {
            for di in -1i64..=1 {
                let (i, j) = (ci as i64 + di, cj as i64 + dj);
                if i < 0 || j < 0 || i >= self.width as i64 || j >= self.height as i64
                    || self.depth_dm[j as usize * self.width + i as usize] <= wade_dm
                {
                    return true;
                }
            }
        }
        false
    }

    /// Every point of one kind (a genre's baskets, its coops), in the bake's order.
    pub fn points_of<'a>(&'a self, kind: &'a str) -> impl Iterator<Item = &'static Point> + 'a {
        self.points.iter().filter(move |p| p.kind == kind)
    }

    /// The named spot containing a point, if any.
    pub fn spot_at(&self, x: f32, z: f32) -> Option<&'static Spot> {
        let (px, pz) = (x as f64, z as f64);
        self.spots.iter().find(|s| {
            let dx = px - s.x;
            let dz = pz - s.z;
            dx * dx + dz * dz <= s.radius * s.radius
        })
    }
}

include!(concat!(env!("OUT_DIR"), "/levels.rs"));
