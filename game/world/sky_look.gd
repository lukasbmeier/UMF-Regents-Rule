class_name SkyLook extends Resource
## GENRE CONTENT. How the lakeside looks at one TIME OF DAY (DECISIONS #168): the sun's path through
## a round, its light, the sky, the ambient light and the fog. `SkyDirector` blends to it when a
## round of that time begins. Edit them in `game/world/sky_director.tscn`'s inspector.

## Where the sun is when the round starts and when its PLAYING phase ends, in degrees above the
## horizon (below 0 is under it: the light then reads as the moon's, so give it a cold colour).
@export_range(-30.0, 90.0) var sun_elevation_deg: float = 45.0
@export_range(-30.0, 90.0) var sun_elevation_end_deg: float = 45.0
## The compass direction it shines from (0 = from -Z, 90 = from +X).
@export_range(0.0, 360.0) var sun_azimuth_deg: float = 140.0
@export var sun_color: Color = Color(1.0, 0.96, 0.88)
@export_range(0.0, 4.0) var sun_energy: float = 1.25
@export var sky_top: Color = Color(0.3, 0.5, 0.78)
@export var sky_horizon: Color = Color(0.7, 0.78, 0.86)
@export var ground_horizon: Color = Color(0.62, 0.68, 0.72)
@export_range(0.0, 4.0) var ambient_energy: float = 0.9
@export var fog_color: Color = Color(0.68, 0.76, 0.84)
@export_range(0.0, 0.2) var fog_density: float = 0.0016
