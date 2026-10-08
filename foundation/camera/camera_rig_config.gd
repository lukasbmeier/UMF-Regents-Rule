class_name CameraRigConfig extends Resource
## How a camera sits relative to its entity. FIRST VS THIRD PERSON IS THIS RESOURCE, nothing
## else — swap the `.tres` on a CameraRig and the view changes (ARCHITECTURE §5 cross-cutting).
##
## A genre ships its own presets. The foundation provides `first_person.tres` and
## `third_person.tres` as working defaults.

## True: camera sits at the eye point. False: it pulls back along a boom.
@export var first_person: bool = false
## Height of the pivot above the entity's origin — eye height in first person, the point the
## boom swings around in third.
@export var pivot_height: float = 1.6
## Third person only: how far back the camera sits. The player can zoom between
## `boom_min` and `boom_max` from here; this is where it starts.
@export var boom_length: float = 4.0
## Third person only: how far the wheel may pull the camera in and push it out. Equal values
## disable zooming.
@export var boom_min: float = 1.5
@export var boom_max: float = 7.0
## Metres per wheel notch.
@export var zoom_step: float = 0.5
## How fast the boom follows the wheel. 0 snaps.
@export var zoom_smoothing: float = 12.0
## Third person only: lateral offset, for an over-the-shoulder framing.
@export var shoulder_offset: float = 0.0
## Pull the boom in when the world is in the way, so the camera never ends up inside a wall.
@export var collide_with_world: bool = true
## Keep this much clearance off whatever the boom hits.
@export var collision_padding: float = 0.25
@export var pitch_min_deg: float = -80.0
@export var pitch_max_deg: float = 70.0
@export_range(1.0, 179.0) var fov: float = 75.0
## 0 snaps the camera to the entity; higher values trail it. First person should stay 0.
@export var follow_smoothing: float = 0.0
