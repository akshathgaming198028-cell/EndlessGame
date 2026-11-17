extends Camera3D

# Approved chase camera (tuned in the earlier build, ported to this track).
# The runner moves along +X, so the camera sits behind (-X), above, and looks down the track.
const BEHIND := 6.5       # how far behind the runner
const HEIGHT := 4.5       # height above the runner's origin (origin is about 1 m above the feet)
const LOOK_AHEAD := 15.5  # how far ahead the camera looks
const LOOK_DROP := -4.5   # looks down towards the track
const FOV := 62.0


func _ready() -> void:
	keep_aspect = Camera3D.KEEP_WIDTH
	fov = FOV
	far = 1500.0
	position = Vector3(-BEHIND, HEIGHT, 0.0)
	look_at(global_position + Vector3(LOOK_AHEAD, LOOK_DROP, 0.0), Vector3.UP)
