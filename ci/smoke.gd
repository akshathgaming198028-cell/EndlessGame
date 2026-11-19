extends SceneTree

# Starts the real game scene, runs some frames, and prints any script errors.
var frames := 0
var game: Node

func _initialize() -> void:
	var ps := load("res://main.tscn") as PackedScene
	print("SMOKE scene loaded=", ps != null)
	game = ps.instantiate()
	get_root().add_child(game)
	print("SMOKE game added")

func _process(_d: float) -> bool:
	frames += 1
	if frames == 60:
		print("SMOKE ok after 60 frames")
		quit()
	return false
