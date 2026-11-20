extends Node

# Opening screen: shows your picture (assets/splash.png) or the title, with a loading bar,
# while the game scene loads in the background. Replaces the engine's splash.

const NEXT := "res://main.tscn"
var bar: ColorRect
var bar_bg: ColorRect
var shown := 0.0
var done := false

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("121729")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	if ResourceLoader.exists("res://assets/splash.png"):
		var tr := TextureRect.new()
		tr.texture = load("res://assets/splash.png")
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.add_child(tr)
	else:
		var title := Label.new()
		title.text = "HEIST ESCAPE"
		title.add_theme_font_size_override("font_size", 72)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.position = Vector2(0, 520)
		title.size = Vector2(720, 120)
		layer.add_child(title)
	bar_bg = ColorRect.new()
	bar_bg.color = Color("2b314a")
	bar_bg.position = Vector2(160, 1000)
	bar_bg.size = Vector2(400, 24)
	layer.add_child(bar_bg)
	bar = ColorRect.new()
	bar.color = Color("ff9f1c")
	bar.position = bar_bg.position
	bar.size = Vector2(0, 24)
	layer.add_child(bar)
	ResourceLoader.load_threaded_request(NEXT)

func _notification(what: int) -> void:
	# back is ignored while loading, so it can't close the app before the game is up
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		pass


func _process(delta: float) -> void:
	shown += delta
	if done:
		return
	var prog: Array = []
	var st := ResourceLoader.load_threaded_get_status(NEXT, prog)
	var p := 0.0
	if prog.size() > 0:
		p = float(prog[0])
	bar.size.x = bar_bg.size.x * p
	if st == ResourceLoader.THREAD_LOAD_LOADED and shown > 1.0:
		done = true
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(NEXT))
	elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		done = true
		push_error("could not load the game scene")
