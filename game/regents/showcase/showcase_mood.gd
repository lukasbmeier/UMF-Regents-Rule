class_name ShowcaseMood extends Resource
## A TIME OF DAY FOR THE SHOWCASE (2026-11-15): the sun, the sky, the clouds, the air and the little lights of one
## mood (dawn, day, golden hour, dusk, night). A `.tres` in `game/regents/showcase/moods/`; `ShowcaseWorld.mood` takes
## one. Every value is a designer's: change it in the Inspector and look (the vista lab, M cycles the moods).

@export var display_name: String = "Day"

@export_group("Sun")
## How high the sun stands (deg above the horizon; below 0 it has set) and where it stands (deg, 0 = north).
@export_range(-30.0, 90.0, 0.5, "suffix:deg") var sun_elevation: float = 45.0
@export_range(-180.0, 180.0, 0.5, "suffix:deg") var sun_azimuth: float = 30.0
@export var sun_color: Color = Color(1.0, 0.96, 0.9)
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 1.2
## The moon (a second, cool light) and whether it shows in the sky.
@export var moon: bool = false
@export_range(-30.0, 90.0, 0.5, "suffix:deg") var moon_elevation: float = 35.0
@export_range(-180.0, 180.0, 0.5, "suffix:deg") var moon_azimuth: float = -140.0
@export var moon_color: Color = Color(0.62, 0.72, 1.0)
@export_range(0.0, 2.0, 0.01) var moon_energy: float = 0.0

@export_group("Sky")
@export var zenith_color: Color = Color(0.22, 0.42, 0.78)
@export var horizon_color: Color = Color(0.72, 0.8, 0.88)
## The glow round the sun, and how far across the sky it spreads (0-1).
@export var glow_color: Color = Color(1.0, 0.85, 0.6)
@export_range(0.0, 1.0, 0.01) var glow_spread: float = 0.25
@export_range(0.0, 1.0, 0.01) var stars: float = 0.0

@export_group("Clouds")
@export_range(0.0, 1.0, 0.01) var cloud_cover: float = 0.45
@export var cloud_lit_color: Color = Color(1.0, 0.98, 0.95)
@export var cloud_shade_color: Color = Color(0.6, 0.66, 0.76)
@export_range(0.0, 0.1, 0.001) var cloud_speed: float = 0.006

@export_group("Air")
@export var fog_color: Color = Color(0.72, 0.78, 0.84)
@export_range(0.0, 0.05, 0.0005) var fog_density: float = 0.004
## Volumetric fog in the valleys (0 = none): the light shafts through the trees at dawn.
@export_range(0.0, 0.1, 0.001) var mist_density: float = 0.0
@export var mist_color: Color = Color(0.85, 0.85, 0.9)
@export_range(0.0, 4.0, 0.01) var ambient_energy: float = 1.0
@export_range(0.1, 4.0, 0.01) var exposure: float = 1.0
@export_range(0.0, 2.0, 0.01) var glow: float = 0.6

@export_group("Little lights")
## Fireflies over the meadow, embers off the fire (0-1 how many), and how bright the fire burns.
@export_range(0.0, 1.0, 0.01) var fireflies: float = 0.0
@export_range(0.0, 1.0, 0.01) var dust: float = 0.3
@export_range(0.0, 8.0, 0.05) var fire_energy: float = 1.5
## Lit windows in the keep, and the torches on its wall.
@export_range(0.0, 4.0, 0.05) var windows: float = 0.0


## The direction a light of `elevation_deg` and `azimuth_deg` shines FROM (toward the sky, unit).
static func sky_direction(elevation_deg: float, azimuth_deg: float) -> Vector3:
	var el: float = deg_to_rad(elevation_deg)
	var az: float = deg_to_rad(azimuth_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()
