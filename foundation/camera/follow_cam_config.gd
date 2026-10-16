class_name FollowCamConfig extends Resource
## HOW A CAMERA FOLLOWS SOMETHING THAT IS NOT ITS PLAYER (FOUNDATION_SYSTEMS milestone 14, DECISIONS
## #248): a thrown disc in flight, a ball, another player's throw. Behind it along where it is going,
## a little above, trailing it, looking at it (`CameraRig.watch`). A genre ships its own presets; the
## foundation's is `follow_cam.tres`.

## How far behind what it follows.
@export_range(0.5, 30.0, 0.1, "suffix:m") var distance: float = 4.0
## How far above it.
@export_range(-5.0, 20.0, 0.1, "suffix:m") var height: float = 1.5
## How quickly it catches up (higher: tighter). A fast disc needs some trail or it shakes.
@export_range(0.5, 30.0, 0.1) var follow_rate: float = 6.0
## Slower than this it no longer turns to stay behind (a body bouncing on its spot would spin it round).
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var turn_from_speed: float = 1.0
## How long it takes to go back to the player's own view.
@export_range(0.0, 3.0, 0.05, "suffix:s") var return_s: float = 0.5
## Its width of view (0: the player's own).
@export_range(0.0, 150.0, 1.0) var fov: float = 0.0
