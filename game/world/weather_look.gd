class_name WeatherLook extends Resource
## GENRE CONTENT. What one WEATHER does to the time of day's look (DECISIONS #168): applied on top
## of the `SkyLook`. Edit them in `game/world/sky_director.tscn`'s inspector.

## The sun's light, times this (clouds in front of it).
@export_range(0.0, 2.0) var sun_energy_mult: float = 1.0
## How far the sky and the fog go toward grey, 0..1.
@export_range(0.0, 1.0) var grey: float = 0.0
## How much darker everything is, 0..1.
@export_range(0.0, 1.0) var darken: float = 0.0
## Fog added on top of the time's.
@export_range(0.0, 0.2) var fog_density_add: float = 0.0
## Rain, 0 (none) to 1 (a downpour).
@export_range(0.0, 1.0) var rain: float = 0.0
