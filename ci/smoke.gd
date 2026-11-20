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
	var sp := load("res://splash.tscn") as PackedScene
	print("SMOKE splash loaded=", sp != null)
	var splash := sp.instantiate()
	get_root().add_child(splash)
	print("SMOKE splash added")

func _process(_d: float) -> bool:
	frames += 1
	if frames == 30:
		game.call("_start_game")
	if frames == 35:
		game.call("_die", -3.0)
		print("SMOKE died state=", game.get("state"), " lives=", game.get("lives"))
	if frames == 60:
		print("SMOKE quit_on_go_back=", ProjectSettings.get_setting("application/config/quit_on_go_back"))
		print("SMOKE ok after 60 frames")
		quit()
	return false
