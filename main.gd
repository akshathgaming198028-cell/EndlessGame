extends Node3D
# LOW POLY RUNNER - v0.1
# Everything is built from code, so the project is only a handful of files.
#
# ASSET HOOKS (optional): make a folder called "assets" and drop files in.
# They are picked up automatically, no code changes needed:
#   assets/sky.png|jpg|webp   -> 360 panorama skybox
#   assets/music.ogg|mp3      -> background music (loops)
#   assets/coin.wav|ogg|mp3   -> coin sound
#   assets/jump.*  assets/hit.*  -> jump / crash sounds
#   assets/player.glb         -> your own character (faces -Z, feet at y=0, ~1.8 m tall,
#                                animations with run / jump / slide / die / idle in the name)

const LANE_W := 2.4
# Kenney CC0 models (see CREDITS.md). Each is scaled to fit the box it replaces.
const TRAIN_MODELS := [
	"res://assets/trains/Locomotive Front/Locomotive_Front.fbx",
	"res://assets/trains/High Speed Front/HighSpeed_Front.fbx",
	"res://assets/trains/Cargo Train Front/CargoTrain_Front.fbx",
]
const BUILDING_MODELS := [
	"res://assets/environment/Building/building_A.fbx",
	"res://assets/environment/Building/building_C.fbx",
	"res://assets/environment/Building/building_D.fbx",
	"res://assets/environment/Building/building_E.fbx",
	"res://assets/environment/Building/building_F.fbx",
	"res://assets/environment/Building B/building_B.fbx",
	"res://assets/environment/Building-otRsYa6pan/building_H.fbx",
	"res://assets/environment/Building-bbH2Bg73qM/building_G.fbx",
]
# --- MAP (Subway Surfers model in assets/map.glb). Tweak these after testing. ---
const MAP_PATH := "res://assets/map.glb"
const MAP_SCALE := 0.4      # the open track between the bush walls is 18 model units wide = 3 lanes
# street measured on the model, in model units (before MAP_SCALE)
const MAP_STREET_CX := 53.0    # centre of the open track (between the bush walls) across its width
const MAP_STREET_Z0 := -950.0  # start of the real track (buildings and bushes present) along its length
const MAP_STREET_Z1 := -40.0   # end of the real track (the last 40 units have almost nothing)
const MAP_WIDTH_SCALE := 1.5   # widens the map sideways so the lanes have room between the walls
const MAP_HEIGHT_SCALE := 1.6  # makes bushes, trains and buildings taller so they read at game size
const MAP_TILES := 3           # copies laid end to end (each is ~358 units long)
const CHUNK_LEN := 30.0
const NUM_CHUNKS := 6
const GRAVITY := 30.0
const JUMP_V := 12.5
const SLIDE_TIME := 0.65
const SWIPE_PX := 30.0
const START_SPEED := 15.0
const MAX_SPEED := 34.0

enum State { MENU, PLAY, DEAD }

var rng := RandomNumberGenerator.new()
var state: State = State.MENU

var speed := 0.0
var dist := 0.0
var coins := 0
var best := 0
var lane := 0
var px := 0.0
var py := 0.0
var vy := 0.0
var on_ground := true
var slide_t := 0.0
var want_slide := false
var jump_buf := 0.0
var run_t := 0.0
var dead_t := 0.0
var shake := 0.0
var next_index := 0
var free_lane := 0
var prev_train := false

var chunks: Array = []
var map_scene: PackedScene = null
var map_tiles: Array = []
var map_period := 0.0
var mat_cache := {}
var m_box: BoxMesh
var m_cone: ArrayMesh
var m_trunk: ArrayMesh
var m_coin: ArrayMesh
var m_disc: ArrayMesh

var player: Node3D
var body: Node3D
var blob: MeshInstance3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var custom_model: Node3D = null
var anim: AnimationPlayer = null

var cam: Camera3D
var cam_pos := Vector3(0, 4.2, 4.6)
var cam_look := Vector3(0, 1.0, -9)

var score_label: Label
var msg_label: Label
var pause_btn: Button
var paused := false
var die_done := false
var sfx_coin: AudioStreamPlayer
var sfx_jump: AudioStreamPlayer
var sfx_hit: AudioStreamPlayer
var music: AudioStreamPlayer

var swipe_start := Vector2.ZERO
var swiping := false
var swipe_used := false

var c_road := Color("3a3f55")
var c_line := Color("e9edf7")
var c_curb := Color("9aa3bd")
var c_ground := Color("6fae5d")
var c_coin := Color("ffc928")
var c_barrier := Color("e8453c")
var c_white := Color("f4f4f4")
var c_post := Color("56607a")
var c_hazard := Color("ffcf2e")
var c_dark := Color("23283a")
var train_colors := [Color("2aa7a0"), Color("e8573f"), Color("4a7bd8"), Color("f08a2c"), Color("8a5cd6")]
var building_colors := [Color("e7806b"), Color("f2c14e"), Color("7fb6d9"), Color("b39ddb"), Color("e9a6b8"), Color("8fd3b0"), Color("d9d4c7")]
var leaf_colors := [Color("3f9a4f"), Color("55b25e"), Color("2f8645")]


func _ready() -> void:
	rng.randomize()
	DisplayServer.screen_set_keep_on(true)
	_load_best()
	_make_meshes()
	_make_environment()
	_make_player()
	_make_camera()
	_make_ui()
	_make_audio()
	_make_map()
	_reset_world()
	_set_state(State.MENU)


# ---------------------------------------------------------------- helpers

func flat(src: Mesh) -> ArrayMesh:
	# turns a smooth primitive into a faceted "low poly" mesh
	var arr := src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if idx == null or idx.size() == 0:
		for i in v.size():
			st.set_smooth_group(-1)
			st.add_vertex(v[i])
	else:
		for i in idx.size():
			st.set_smooth_group(-1)
			st.add_vertex(v[idx[i]])
	st.generate_normals()
	return st.commit()


func make_capsule(r: float, h: float, seg := 6, rings := 2) -> ArrayMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return flat(m)


func make_sphere(r: float, seg := 8, rings := 4) -> ArrayMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return flat(m)


func _make_meshes() -> void:
	m_box = BoxMesh.new()
	m_box.size = Vector3.ONE
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 2.0
	cone.radial_segments = 6
	cone.rings = 1
	cone.cap_top = false
	m_cone = flat(cone)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 1.0
	trunk.bottom_radius = 1.0
	trunk.height = 2.0
	trunk.radial_segments = 5
	trunk.rings = 1
	m_trunk = flat(trunk)
	var coin := CylinderMesh.new()
	coin.top_radius = 0.38
	coin.bottom_radius = 0.38
	coin.height = 0.12
	coin.radial_segments = 10
	coin.rings = 1
	m_coin = flat(coin)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 10
	disc.rings = 1
	m_disc = flat(disc)


func get_mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(), glow]
	if mat_cache.has(key):
		return mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	mat_cache[key] = m
	return m


func add_mesh(parent: Node3D, mesh: Mesh, scl: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = scl
	mi.position = pos
	mi.rotation = rot
	mi.material_override = get_mat(color, glow)
	parent.add_child(mi)
	return mi


func add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow := 0.0) -> MeshInstance3D:
	return add_mesh(parent, m_box, size, pos, color, Vector3.ZERO, glow)


# ---------------------------------------------------------------- scene setup

func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sp := _find_asset("sky", ["png", "jpg", "jpeg", "webp"])
	if sp != "":
		var psm := PanoramaSkyMaterial.new()
		psm.panorama = load(sp)
		sky.sky_material = psm
	else:
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = Color("4aa3ff")
		pm.sky_horizon_color = Color("cfe8ff")
		pm.ground_horizon_color = Color("cfe8ff")
		pm.ground_bottom_color = Color("a9cdea")
		sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color("c9d8ff")
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("cfe8ff")
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = false
	add_child(sun)


func _make_camera() -> void:
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 62.0
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	cam.position = cam_pos
	cam.look_at(cam_look)


func _make_player() -> void:
	player = Node3D.new()
	add_child(player)
	body = Node3D.new()
	player.add_child(body)
	blob = add_mesh(self, m_disc, Vector3(0.5, 1.0, 0.4), Vector3(0, 0.04, 0), Color(0, 0, 0, 0.35))

	if ResourceLoader.exists("res://assets/player.glb"):
		var ps = load("res://assets/player.glb")
		if ps is PackedScene:
			custom_model = ps.instantiate()
			body.add_child(custom_model)
			anim = _find_anim(custom_model)
			_setup_rig(custom_model)
			_load_anims(custom_model)
			return

	# procedural low-poly runner (placeholder until you bring your own model)
	var skin := Color("f1b58f")
	var shirt := Color("ff7a2f")
	var pants := Color("2f4fb3")
	var shoe := Color("f4f4f4")
	var cap_c := Color("d93a3a")
	add_mesh(body, make_capsule(0.30, 0.95), Vector3.ONE, Vector3(0, 1.22, 0), shirt)
	add_box(body, Vector3(0.42, 0.5, 0.22), Vector3(0, 1.3, 0.3), Color("2aa7a0"))
	add_mesh(body, make_sphere(0.26), Vector3.ONE, Vector3(0, 1.9, 0), skin)
	add_mesh(body, make_sphere(0.28, 8, 3), Vector3(1.0, 0.65, 1.0), Vector3(0, 2.02, 0), cap_c)
	add_box(body, Vector3(0.36, 0.04, 0.26), Vector3(0, 1.99, -0.28), cap_c)
	add_box(body, Vector3(0.06, 0.08, 0.04), Vector3(-0.09, 1.9, -0.24), c_dark)
	add_box(body, Vector3(0.06, 0.08, 0.04), Vector3(0.09, 1.9, -0.24), c_dark)
	for si in 2:
		var s: float = -1.0 + 2.0 * si
		var leg := Node3D.new()
		leg.position = Vector3(s * 0.15, 0.88, 0)
		body.add_child(leg)
		add_mesh(leg, make_capsule(0.13, 0.85), Vector3.ONE, Vector3(0, -0.42, 0), pants)
		add_box(leg, Vector3(0.2, 0.12, 0.36), Vector3(0, -0.84, -0.06), shoe)
		var arm := Node3D.new()
		arm.position = Vector3(s * 0.42, 1.52, 0)
		body.add_child(arm)
		add_mesh(arm, make_capsule(0.1, 0.7), Vector3.ONE, Vector3(0, -0.3, 0), shirt)
		add_mesh(arm, make_sphere(0.09, 6, 3), Vector3.ONE, Vector3(0, -0.66, 0), skin)
		if si == 0:
			leg_l = leg
			arm_l = arm
		else:
			leg_r = leg
			arm_r = arm


# --- Character rig (Mixamo skeleton, no animations in the file, so we pose the bones in code) ---
const PLAYER_HEIGHT := 1.8
# Mixamo animation files in assets/anims/ (see README). Keys are the names the game plays.
const ANIM_FILES := {
	"run": "Running.fbx",
	"jump": "Jump.fbx",
	"idle": "Idle.fbx",
	"die": "Zombie Death.fbx",
	"slide": "Falling To Roll.fbx",
}
var skel: Skeleton3D = null
var bone_ids := {}


func _setup_rig(model: Node3D) -> void:
	# Mixamo models face +Z and come in tiny units: turn to face -Z (our run direction) and fit to player height
	model.rotation_degrees.y = 180.0
	# this rig is 0.74 units tall in its file (measured), so scale it to the player height
	model.scale = Vector3.ONE * (PLAYER_HEIGHT / 0.74) * 2.0
	model.position = Vector3.ZERO
	_matte(model)
	skel = _find_skeleton(model)
	if skel != null:
		for nm in ["Spine", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]:
			bone_ids[nm] = skel.find_bone("mixamorig:" + nm)


# Removes the shiny sky-reflection look: fully rough, non-metal surfaces
func _matte(n: Node) -> void:
	if n is MeshInstance3D and n.mesh != null:
		for si in n.mesh.get_surface_count():
			var m = n.get_active_material(si)
			if m is BaseMaterial3D:
				var d: BaseMaterial3D = m.duplicate()
				d.roughness = 1.0
				d.metallic = 0.0
				d.metallic_specular = 0.0
				n.set_surface_override_material(si, d)
	for c in n.get_children():
		_matte(c)


# Loads each Mixamo animation file and plays it on our character's skeleton.
func _load_anims(model: Node3D) -> void:
	if skel == null:
		return
	# map simplified bone names ("mixamorig:Hips" and "mixamorig_Hips" both become "mixamorighips") to the real ones
	var bones := {}
	for i in skel.get_bone_count():
		bones[_norm(skel.get_bone_name(i))] = skel.get_bone_name(i)
	var skel_rel := str(model.get_path_to(skel))
	var tgtq := {}
	for ti in skel.get_bone_count():
		tgtq[_norm(skel.get_bone_name(ti))] = skel.get_bone_global_rest(ti).basis.get_rotation_quaternion()
	var lib := AnimationLibrary.new()
	for key in ANIM_FILES:
		var path: String = "res://assets/anims/" + ANIM_FILES[key]
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var src := ps.instantiate()
		var sp := _find_anim(src)
		if sp != null and sp.get_animation_list().size() > 0:
			var a: Animation = sp.get_animation(sp.get_animation_list()[0]).duplicate()
			var ssk := _find_skeleton(src)
			var srcq := {}
			if ssk != null:
				for si in ssk.get_bone_count():
					srcq[_norm(ssk.get_bone_name(si))] = ssk.get_bone_global_rest(si).basis.get_rotation_quaternion()
			for t in range(a.get_track_count() - 1, -1, -1):
				var np := a.track_get_path(t)
				var bone := np.get_concatenated_subnames()
				if bone == "" or not bones.has(_norm(bone)):
					a.remove_track(t)
					continue
				var nb := _norm(bone)
				# keep the character in place: drop root movement from the hips
				if a.track_get_type(t) == Animation.TYPE_POSITION_3D and nb == "mixamorighips":
					a.remove_track(t)
					continue
				# re-aim each rotation from the animation's rest pose to this model's rest pose
				if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and srcq.has(nb) and tgtq.has(nb):
					var qs: Quaternion = srcq[nb]
					var qm: Quaternion = tgtq[nb]
					for kk in a.track_get_key_count(t):
						var k: Quaternion = a.track_get_key_value(t, kk)
						a.track_set_key_value(t, kk, qm.inverse() * qs * k * qs.inverse() * qm)
				a.track_set_path(t, NodePath(skel_rel + ":" + bones[nb]))
			# only running and idle repeat; death, jump and slide play once
			a.loop_mode = Animation.LOOP_LINEAR if (key == "run" or key == "idle") else Animation.LOOP_NONE
			lib.add_animation(key, a)
		src.queue_free()
	if lib.get_animation_list().size() == 0:
		return
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.add_animation_library("", lib)
	ap.animation_finished.connect(_on_anim_finished)
	anim = ap


func _on_anim_finished(anim_name: StringName) -> void:
	# death plays once and holds its last frame
	if String(anim_name) == "die" and anim != null:
		die_done = true
		anim.seek(anim.get_animation("die").length, true)
		anim.pause()


func _norm(s: String) -> String:
	return s.replace(":", "").replace("_", "").to_lower()


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


func _bone_q(nm: String, target: Quaternion, k: float) -> void:
	var id: int = bone_ids.get(nm, -1)
	if id < 0:
		return
	skel.set_bone_pose_rotation(id, skel.get_bone_pose_rotation(id).slerp(target, k))


func _animate_rig(dt: float) -> void:
	var k := 1.0 - exp(-14.0 * dt)
	var sw := sin(run_t)
	var spine := 0.0
	var l_thigh := 0.0
	var r_thigh := 0.0
	var l_knee := 0.0
	var r_knee := 0.0
	var l_arm := Quaternion()
	var r_arm := Quaternion()
	if state == State.DEAD:
		spine = 0.9
		l_thigh = 0.2
		r_thigh = -0.2
		l_arm = Quaternion(Vector3(0, 0, 1), 2.0)
		r_arm = Quaternion(Vector3(0, 0, 1), -2.0)
	elif state == State.MENU:
		var br := sin(Time.get_ticks_msec() * 0.003) * 0.05
		spine = br
		l_arm = Quaternion(Vector3.UP, 0.1 + br)
		r_arm = Quaternion(Vector3.UP, -0.1 - br)
	elif slide_t > 0.0:
		spine = -0.9
		l_thigh = -1.2
		r_thigh = -1.2
		l_knee = 1.3
		r_knee = 1.3
		l_arm = Quaternion(Vector3.UP, 0.4)
		r_arm = Quaternion(Vector3.UP, -0.4)
	elif not on_ground:
		l_thigh = -0.6
		r_thigh = 0.4
		l_knee = 0.9
		r_knee = 0.3
		l_arm = Quaternion(Vector3(0, 0, 1), 2.0)
		r_arm = Quaternion(Vector3(0, 0, 1), -2.0)
	else:
		l_thigh = sw * 0.9
		r_thigh = -sw * 0.9
		l_knee = maxf(0.0, -sw) * 1.1
		r_knee = maxf(0.0, sw) * 1.1
		var arm := -sw * 0.7
		l_arm = Quaternion(Vector3.UP, arm)
		r_arm = Quaternion(Vector3.UP, arm)
		spine = 0.05
	_bone_q("Spine", Quaternion(Vector3.RIGHT, spine), k)
	_bone_q("LeftUpLeg", Quaternion(Vector3.RIGHT, l_thigh), k)
	_bone_q("RightUpLeg", Quaternion(Vector3.RIGHT, r_thigh), k)
	_bone_q("LeftLeg", Quaternion(Vector3.RIGHT, -l_knee), k)
	_bone_q("RightLeg", Quaternion(Vector3.RIGHT, -r_knee), k)
	_bone_q("LeftArm", l_arm, k)
	_bone_q("RightArm", r_arm, k)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for ch in n.get_children():
		var r := _find_anim(ch)
		if r != null:
			return r
	return null


func _play_anim(keyword: String) -> void:
	if anim == null:
		return
	for a in anim.get_animation_list():
		if keyword in String(a).to_lower():
			if anim.current_animation != String(a):
				anim.play(String(a), 0.15)
			anim.speed_scale = _anim_speed(keyword, String(a))
			return


func _anim_speed(keyword: String, name: String) -> float:
	var length := anim.get_animation(name).length
	if length <= 0.0:
		return 1.0
	if keyword == "slide":
		return clampf(length / SLIDE_TIME, 0.5, 1.5)
	if keyword == "die":
		return length / 1.2
	return 1.0


func _label(parent: Node, size_px: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.2))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	score_label = _label(layer, 54)
	score_label.anchor_right = 1.0
	score_label.offset_top = 40.0
	score_label.offset_bottom = 190.0
	score_label.offset_left = 0.0
	score_label.offset_right = -30.0
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	msg_label = _label(layer, 46)
	msg_label.anchor_right = 1.0
	msg_label.anchor_bottom = 1.0
	msg_label.offset_left = 30.0
	msg_label.offset_right = -30.0
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.add_theme_font_size_override("font_size", 40)
	pause_btn.position = Vector2(24, 40)
	pause_btn.size = Vector2(96, 96)
	pause_btn.visible = false
	pause_btn.pressed.connect(_toggle_pause)
	layer.add_child(pause_btn)


# ---------------------------------------------------------------- audio

func _tone(freq: float, dur: float, vol: float, sweep := 0.0, noise := 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = freq + sweep * t
		phase += TAU * f / float(rate)
		var s: float = sin(phase) * (1.0 - noise) + (rng.randf() * 2.0 - 1.0) * noise
		var env: float = pow(1.0 - t, 2.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _find_asset(base: String, exts: Array) -> String:
	for ext in exts:
		var p := "res://assets/%s.%s" % [base, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


func _sfx(base: String, fallback: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = fallback
	var path := _find_asset(base, ["ogg", "wav", "mp3"])
	if path != "":
		p.stream = load(path)
	add_child(p)
	return p


func _make_audio() -> void:
	sfx_coin = _sfx("coin", _tone(988.0, 0.12, 0.5, 700.0))
	sfx_jump = _sfx("jump", _tone(260.0, 0.18, 0.5, 300.0))
	sfx_hit = _sfx("hit", _tone(120.0, 0.45, 0.8, -60.0, 0.5))
	sfx_coin.volume_db = -6.0
	sfx_jump.volume_db = -8.0
	var mp := _find_asset("music", ["ogg", "mp3", "wav"])
	if mp != "":
		music = AudioStreamPlayer.new()
		music.stream = load(mp)
		if "loop" in music.stream:
			music.stream.set("loop", true)
		music.volume_db = -8.0
		add_child(music)
		music.play()


# ---------------------------------------------------------------- world generation

func _reset_world() -> void:
	for i in map_tiles.size():
		map_tiles[i].position.z = -i * map_period
	for c in chunks:
		var old: Node3D = c["node"]
		old.queue_free()
	chunks.clear()
	next_index = 0
	free_lane = 0
	prev_train = false
	for i in NUM_CHUNKS:
		_spawn_chunk(next_index, 5.0 - i * CHUNK_LEN)
		next_index += 1


func _spawn_chunk(index: int, z: float) -> void:
	var node := Node3D.new()
	node.position = Vector3(0, 0, z)
	add_child(node)
	var items: Array = []
	if map_scene == null:
		_build_scenery(node)
	if index >= 2:
		_build_obstacles(node, items)
	chunks.append({"node": node, "items": items})


func _build_scenery(node: Node3D) -> void:
	add_box(node, Vector3(LANE_W * 3.0 + 0.6, 1.0, CHUNK_LEN), Vector3(0, -0.5, 0), c_road)
	for si in 2:
		var side: float = -1.0 + 2.0 * si
		add_box(node, Vector3(0.5, 0.3, CHUNK_LEN), Vector3(side * (LANE_W * 1.5 + 0.55), 0.0, 0), c_curb)
		add_box(node, Vector3(40.0, 1.0, CHUNK_LEN), Vector3(side * (LANE_W * 1.5 + 0.8 + 20.0), -0.7, 0), c_ground)
		var dx: float = (-0.5 + si) * LANE_W
		for i in 5:
			add_box(node, Vector3(0.12, 0.03, 2.6), Vector3(dx, 0.01, -12.0 + i * 6.0), c_line)
		# buildings
		for j in 3:
			var w: float = rng.randf_range(4.0, 8.0)
			var h: float = rng.randf_range(6.0, 26.0)
			var d: float = rng.randf_range(6.0, 9.0)
			var bx: float = side * (LANE_W * 1.5 + 2.6 + w * 0.5 + rng.randf_range(0.0, 3.0))
			var bz: float = -10.0 + j * 10.0 + rng.randf_range(-1.5, 1.5)
			var col: Color = building_colors[rng.randi() % building_colors.size()]
			if not _fit_model(node, BUILDING_MODELS[rng.randi() % BUILDING_MODELS.size()], Vector3(w, h, d), Vector3(bx, h * 0.5 - 0.3, bz)):
				add_box(node, Vector3(w, h, d), Vector3(bx, h * 0.5 - 0.3, bz), col)
			add_box(node, Vector3(w + 0.3, 0.4, d + 0.3), Vector3(bx, h - 0.1, bz), col.darkened(0.25))
			var rows: int = rng.randi_range(1, 3)
			for r in rows:
				var wy: float = 2.5 + r * 4.0
				if wy < h - 2.0:
					add_box(node, Vector3(0.1, 1.0, d * 0.8), Vector3(bx - side * (w * 0.5), wy, bz), Color("2b3a55"))
		# trees
		if rng.randf() < 0.75:
			var tx: float = side * (LANE_W * 1.5 + 1.9)
			var tz: float = rng.randf_range(-13.0, 13.0)
			var s: float = rng.randf_range(0.8, 1.3)
			add_mesh(node, m_trunk, Vector3(0.16 * s, 0.6 * s, 0.16 * s), Vector3(tx, 0.6 * s, tz), Color("7a5538"))
			var lc: Color = leaf_colors[rng.randi() % leaf_colors.size()]
			add_mesh(node, m_cone, Vector3(s, s, s), Vector3(tx, 2.2 * s, tz), lc)
			add_mesh(node, m_cone, Vector3(0.75 * s, 0.8 * s, 0.75 * s), Vector3(tx, 3.1 * s, tz), lc)


func _build_obstacles(node: Node3D, items: Array) -> void:
	for slot in 3:
		var zc: float = 10.0 - slot * 10.0
		var roll: int = rng.randi_range(0, 9)
		var kind: String = "coins"
		if roll <= 1:
			kind = "coins"
		elif roll <= 4:
			kind = "low"
		elif roll <= 7:
			kind = "train"
		else:
			kind = "mix"
		var has_train: bool = (kind == "train" or kind == "mix")
		# the free lane only wanders when no trains are involved, so the route stays possible
		if not has_train and not prev_train and rng.randf() < 0.5:
			free_lane = clampi(free_lane + (1 if rng.randf() < 0.5 else -1), -1, 1)
		var blocked: Array = []
		for li in 3:
			if li - 1 != free_lane:
				blocked.append(li - 1)
		blocked.shuffle()
		var b0: int = blocked[0]
		var b1: int = blocked[1]
		if kind == "coins":
			_coin_line(node, items, free_lane, zc, 1.0)
		elif kind == "low":
			_add_low(node, items, b0, zc)
			_add_low(node, items, b1, zc)
			if rng.randf() < 0.5:
				_add_low(node, items, free_lane, zc)
			else:
				_coin_line(node, items, free_lane, zc, 1.0)
		elif kind == "train":
			_add_item(node, items, "train", b0 * LANE_W, zc)
			if rng.randf() < 0.6:
				_add_item(node, items, "train", b1 * LANE_W, zc)
			_coin_line(node, items, free_lane, zc, 1.0)
		else:
			_add_item(node, items, "train", b0 * LANE_W, zc)
			_add_low(node, items, b1, zc)
			if rng.randf() < 0.4:
				_add_low(node, items, free_lane, zc)
			else:
				_coin_line(node, items, free_lane, zc, 1.0)
		prev_train = has_train


func _coin_line(node: Node3D, items: Array, lane_i: int, zc: float, y: float) -> void:
	var x: float = lane_i * LANE_W
	for i in 5:
		_add_item(node, items, "coin", x, zc - 4.0 + i * 2.0, y)


func _add_low(node: Node3D, items: Array, lane_i: int, zc: float) -> void:
	var z: float = zc + rng.randf_range(-3.0, 3.0)
	var x: float = lane_i * LANE_W
	if rng.randf() < 0.55:
		_add_item(node, items, "barrier", x, z)
		if rng.randf() < 0.6:
			for i in 5:
				var tt: float = i / 4.0
				_add_item(node, items, "coin", x, z - 3.0 + i * 1.5, 1.0 + sin(tt * PI) * 1.4)
	else:
		_add_item(node, items, "overhead", x, z)


func _add_item(node: Node3D, items: Array, type: String, x: float, z: float, y := 0.0) -> void:
	var n := Node3D.new()
	n.position = Vector3(x, y, z)
	node.add_child(n)
	if type == "coin":
		add_mesh(n, m_coin, Vector3.ONE, Vector3.ZERO, c_coin, Vector3(PI * 0.5, 0, 0), 0.6)
	elif type == "barrier":
		add_box(n, Vector3(2.0, 0.9, 0.4), Vector3(0, 0.45, 0), c_barrier)
		add_box(n, Vector3(2.04, 0.2, 0.44), Vector3(0, 0.62, 0), c_white)
	elif type == "overhead":
		add_box(n, Vector3(0.2, 2.4, 0.3), Vector3(-0.95, 1.2, 0), c_post)
		add_box(n, Vector3(0.2, 2.4, 0.3), Vector3(0.95, 1.2, 0), c_post)
		add_box(n, Vector3(2.1, 0.5, 0.35), Vector3(0, 1.4, 0), c_hazard)
		add_box(n, Vector3(2.12, 0.12, 0.37), Vector3(0, 1.4, 0), c_dark)
	elif type == "train":
		if not _fit_model(n, TRAIN_MODELS[rng.randi() % TRAIN_MODELS.size()], Vector3(2.0, 2.6, 8.0), Vector3(0, 1.3, 0)):
			var tc: Color = train_colors[rng.randi() % train_colors.size()]
			add_box(n, Vector3(1.8, 0.35, 7.4), Vector3(0, 0.3, 0), c_dark)
			add_box(n, Vector3(2.0, 2.3, 8.0), Vector3(0, 1.6, 0), tc)
			add_box(n, Vector3(2.04, 0.4, 7.2), Vector3(0, 1.2, 0), tc.lightened(0.35))
			add_box(n, Vector3(2.04, 0.55, 6.4), Vector3(0, 2.1, 0), Color("1d2a3f"))
			add_box(n, Vector3(1.8, 0.2, 7.6), Vector3(0, 2.85, 0), c_white.darkened(0.15))
			add_box(n, Vector3(1.5, 0.8, 0.06), Vector3(0, 2.1, 4.02), Color("1d2a3f"))
			add_box(n, Vector3(0.3, 0.3, 0.08), Vector3(-0.6, 0.85, 4.02), c_hazard, 1.0)
			add_box(n, Vector3(0.3, 0.3, 0.08), Vector3(0.6, 0.85, 4.02), c_hazard, 1.0)
	items.append({"type": type, "x": x, "z": z, "y": y, "node": n, "alive": true})


func _recycle_chunks() -> void:
	while chunks.size() > 0:
		var first: Node3D = chunks[0]["node"]
		if first.position.z <= 40.0:
			break
		first.queue_free()
		chunks.remove_at(0)
	while chunks.size() < NUM_CHUNKS:
		var last: Node3D = chunks[chunks.size() - 1]["node"]
		_spawn_chunk(next_index, last.position.z - CHUNK_LEN)
		next_index += 1


# ---------------------------------------------------------------- game flow

func _make_map() -> void:
	if not ResourceLoader.exists(MAP_PATH):
		return
	map_scene = load(MAP_PATH) as PackedScene
	if map_scene == null:
		return
	map_period = (MAP_STREET_Z1 - MAP_STREET_Z0) * MAP_SCALE
	for i in MAP_TILES:
		var tile := Node3D.new()
		add_child(tile)
		var inst: Node3D = map_scene.instantiate()
		inst.rotation_degrees.y = -90.0
		inst.scale = Vector3(MAP_SCALE, MAP_SCALE * MAP_HEIGHT_SCALE, MAP_SCALE * MAP_WIDTH_SCALE)
		# street centre goes to x=0 (lanes), street end goes to z=0, street surface stays at y=0
		inst.position = Vector3(-MAP_STREET_CX * MAP_SCALE * MAP_WIDTH_SCALE, 0.0, -MAP_STREET_Z1 * MAP_SCALE)
		tile.add_child(inst)
		_prepare_map_meshes(inst)
		tile.position.z = -i * map_period
		map_tiles.append(tile)


func _map_box(root: Node3D, rel_to: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = []
	_collect_meshes(root, meshes)
	for mi in meshes:
		var b: AABB = rel_to.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _prepare_map_meshes(root: Node) -> void:
	var meshes: Array = []
	_collect_meshes(root, meshes)
	for mi in meshes:
		# never let the engine cull a map piece by its bounding box
		mi.extra_cull_margin = 100000.0
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m = mi.get_active_material(si)
			if m is BaseMaterial3D:
				var d: BaseMaterial3D = m.duplicate()
				# draw both sides of every face so nothing vanishes at close range
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(si, d)


# Loads a model, scales it uniformly to fit `size`, and centres it on `at` (bottom at at.y - size.y/2).
# Returns false if the model is missing, so the caller can draw a box instead.
func _fit_model(parent: Node3D, path: String, size: Vector3, at: Vector3) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var root := Node3D.new()
	parent.add_child(root)
	root.add_child(ps.instantiate())
	var box := _model_box(root, parent)
	# our trains and buildings run along Z, so turn models that are long along X
	if box.size.x > box.size.z * 1.2 and size.z > size.x:
		root.rotation_degrees.y = 90.0
		box = _model_box(root, parent)
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		root.queue_free()
		return false
	var k := minf(size.x / box.size.x, minf(size.y / box.size.y, size.z / box.size.z))
	var c := box.get_center()
	root.scale = Vector3.ONE * k
	root.position = Vector3(at.x - k * c.x, at.y - size.y * 0.5 - k * box.position.y, at.z - k * c.z)
	return true


func _model_box(root: Node3D, parent: Node3D) -> AABB:
	var meshes: Array = []
	_collect_meshes(root, meshes)
	var box := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = parent.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func _move_map(dt: float) -> void:
	if map_tiles.size() < 2:
		return
	for t in map_tiles:
		t.position.z += speed * dt
	for t in map_tiles:
		if t.position.z > 40.0:
			var min_z := INF
			for o in map_tiles:
				if o != t:
					min_z = minf(min_z, o.position.z)
			t.position.z = min_z - map_period


func _score() -> int:
	return int(dist) + coins * 10


func _set_state(s: State) -> void:
	state = s
	if pause_btn != null:
		pause_btn.visible = s == State.PLAY
	if s == State.MENU:
		msg_label.text = "TAP TO RUN\n\nswipe left / right: change lane\nswipe up: jump\nswipe down: slide"
	elif s == State.PLAY:
		msg_label.text = ""
	else:
		msg_label.text = "CRASH!\n%d points\nBest %d\n\ntap to run again" % [_score(), best]


func _toggle_pause() -> void:
	if state != State.PLAY:
		return
	paused = not paused
	pause_btn.text = "GO" if paused else "II"
	msg_label.text = "PAUSED\n\ntap GO to resume" if paused else ""


func _start_game() -> void:
	_reset_world()
	dist = 0.0
	coins = 0
	speed = START_SPEED
	lane = 0
	px = 0.0
	py = 0.0
	vy = 0.0
	on_ground = true
	slide_t = 0.0
	want_slide = false
	jump_buf = 0.0
	run_t = 0.0
	paused = false
	die_done = false
	pause_btn.text = "II"
	player.position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO
	_set_state(State.PLAY)


func _die() -> void:
	if state != State.PLAY:
		return
	shake = 0.6
	dead_t = 0.0
	sfx_hit.play()
	var sc: int = _score()
	if sc > best:
		best = sc
		_save_best()
	_set_state(State.DEAD)


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://save.cfg") == OK:
		best = int(cf.get_value("game", "best", 0))


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "best", best)
	cf.save("user://save.cfg")


# ---------------------------------------------------------------- input

func _tap() -> void:
	if state == State.MENU:
		_start_game()
	elif state == State.DEAD and dead_t > 0.6:
		_start_game()


func _move_lane(d: int) -> void:
	if state != State.PLAY:
		return
	lane = clampi(lane + d, -1, 1)


func _jump() -> void:
	if state != State.PLAY:
		return
	if on_ground:
		vy = JUMP_V
		on_ground = false
		slide_t = 0.0
		sfx_jump.play()
	else:
		jump_buf = 0.2


func _slide() -> void:
	if state != State.PLAY:
		return
	if on_ground:
		slide_t = SLIDE_TIME
	else:
		vy = -26.0
		want_slide = true


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			swipe_start = e.position
			swiping = true
			swipe_used = false
			_tap()
		else:
			swiping = false
			swipe_used = false
	elif e is InputEventScreenDrag:
		if swiping and not swipe_used and state == State.PLAY and not paused:
			var d: Vector2 = e.position - swipe_start
			if d.length() >= SWIPE_PX:
				swipe_used = true
				if absf(d.x) > absf(d.y):
					_move_lane(1 if d.x > 0.0 else -1)
				elif d.y < 0.0:
					_jump()
				else:
					_slide()
	elif e is InputEventKey:
		if e.pressed and not e.echo and not paused:
			if e.keycode == KEY_LEFT or e.keycode == KEY_A:
				_move_lane(-1)
			elif e.keycode == KEY_RIGHT or e.keycode == KEY_D:
				_move_lane(1)
			elif e.keycode == KEY_UP or e.keycode == KEY_W or e.keycode == KEY_SPACE:
				_jump()
				_tap()
			elif e.keycode == KEY_DOWN or e.keycode == KEY_S:
				_slide()


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	if paused:
		return
	if state == State.PLAY:
		_update_play(dt)
	elif state == State.DEAD:
		dead_t += dt
		_update_dead(dt)
	_spin_coins(dt)
	_animate_player(dt)
	_update_camera(dt)
	_update_ui()


func _update_play(dt: float) -> void:
	speed = minf(MAX_SPEED, START_SPEED + dist * 0.006)
	dist += speed * dt
	run_t += dt * speed * 0.8
	if jump_buf > 0.0:
		jump_buf -= dt
	var tx: float = lane * LANE_W
	px = lerpf(px, tx, 1.0 - exp(-16.0 * dt))
	if not on_ground:
		vy -= GRAVITY * dt
		py += vy * dt
		if py <= 0.0 and vy <= 0.0:
			py = 0.0
			vy = 0.0
			on_ground = true
			if want_slide:
				slide_t = SLIDE_TIME
				want_slide = false
			if jump_buf > 0.0:
				jump_buf = 0.0
				vy = JUMP_V
				on_ground = false
				sfx_jump.play()
	if slide_t > 0.0:
		slide_t -= dt
	player.position = Vector3(px, py, 0.0)
	player.rotation.y = clampf(-(tx - px) * 0.22, -0.5, 0.5)
	for c in chunks:
		var n: Node3D = c["node"]
		n.position.z += speed * dt
	_move_map(dt)
	_recycle_chunks()
	_check_collisions()


func _update_dead(dt: float) -> void:
	if not on_ground:
		vy -= GRAVITY * dt
		py += vy * dt
		if py <= 0.0:
			py = 0.0
			vy = 0.0
			on_ground = true
		player.position.y = py


func _check_collisions() -> void:
	var h: float = 0.8 if slide_t > 0.0 else 1.8
	for c in chunks:
		var cn: Node3D = c["node"]
		var cz: float = cn.position.z
		if absf(cz) > 22.0:
			continue
		for it in c["items"]:
			if not it["alive"]:
				continue
			var dz: float = absf(cz + float(it["z"]))
			if dz > 5.0:
				continue
			var dx: float = absf(px - float(it["x"]))
			var t: String = it["type"]
			if t == "coin":
				if dz < 0.9 and dx < 1.0 and absf((py + 0.9) - float(it["y"])) < 1.1:
					_collect(it)
			elif t == "barrier":
				if dz < 0.5 and dx < 1.0 and py < 0.8:
					_die()
					return
			elif t == "overhead":
				if dz < 0.5 and dx < 1.0 and py < 1.6 and py + h > 1.15:
					_die()
					return
			elif t == "train":
				if dz < 4.3 and dx < 1.15 and py < 2.7:
					_die()
					return


func _collect(it: Dictionary) -> void:
	it["alive"] = false
	var n: Node3D = it["node"]
	n.visible = false
	coins += 1
	sfx_coin.pitch_scale = 1.0 + float(coins % 10) * 0.03
	sfx_coin.play()


func _spin_coins(dt: float) -> void:
	for c in chunks:
		for it in c["items"]:
			if it["type"] == "coin" and it["alive"]:
				var n: Node3D = it["node"]
				n.rotation.y += dt * 4.0


func _animate_player(dt: float) -> void:
	blob.position = Vector3(px, 0.04, 0.0)
	var bs: float = 0.5 / (1.0 + py * 0.4)
	blob.scale = Vector3(bs, 1.0, bs * 0.8)
	blob.visible = state != State.DEAD or py > 0.0

	if custom_model != null:
		var kw := "run"
		if state == State.DEAD:
			kw = "die"
		elif state == State.MENU:
			kw = "idle"
		elif slide_t > 0.0:
			kw = "slide"
		elif not on_ground:
			kw = "jump"
		if kw == "die" and die_done:
			return
		_play_anim(kw)
		return

	var k: float = 1.0 - exp(-18.0 * dt)
	var t_rot: float = -0.14
	var t_y: float = 0.0
	var ll: float = 0.0
	var lr: float = 0.0
	var al: float = 0.0
	var ar: float = 0.0
	if state == State.DEAD:
		t_rot = -1.45
		t_y = 0.22
		ll = 0.5
		lr = -0.3
		al = 1.0
		ar = 1.2
	elif state == State.MENU:
		var s: float = sin(Time.get_ticks_msec() * 0.003)
		al = s * 0.08
		ar = -s * 0.08
		t_rot = 0.0
	elif slide_t > 0.0:
		t_rot = 1.15
		t_y = 0.1
		ll = 0.25
		lr = 0.1
		al = 1.3
		ar = 1.3
	elif not on_ground:
		ll = 1.0
		lr = -0.6
		al = 2.3
		ar = -1.0
	else:
		var sw: float = sin(run_t)
		ll = sw
		lr = -sw
		al = -sw * 1.1
		ar = sw * 1.1
		t_y = absf(cos(run_t)) * 0.07
	leg_l.rotation.x = lerpf(leg_l.rotation.x, ll, k)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, lr, k)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, al, k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, k)
	body.rotation.x = lerpf(body.rotation.x, t_rot, k)
	body.position.y = lerpf(body.position.y, t_y, k)


func _update_camera(dt: float) -> void:
	var k: float = 1.0 - exp(-8.0 * dt)
	var target := Vector3(px * 0.5, 4.2 + py * 0.12, 4.6)
	cam_pos = cam_pos.lerp(target, k)
	cam_look = cam_look.lerp(Vector3(px * 0.4, 1.0 + py * 0.08, -9.0), k)
	var off := Vector3.ZERO
	if shake > 0.0:
		off = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 0.0) * shake * 0.4
		shake = maxf(0.0, shake - dt * 2.0)
	cam.position = cam_pos + off
	cam.look_at(cam_look)
	var t_fov: float = 62.0
	if state == State.PLAY:
		t_fov = 62.0 + (speed - START_SPEED) * 0.2
	cam.fov = lerpf(cam.fov, t_fov, k)


func _update_ui() -> void:
	var t := ""
	if state == State.PLAY:
		t = "%d\nCOINS  %d" % [_score(), coins]
		if map_tiles.size() > 0:
			var zs := ""
			for tile in map_tiles:
				zs += " %.0f" % tile.position.z
			t += "\nmap z:" + zs + "  cam z: %.0f" % cam.position.z
	elif state == State.MENU:
		t = "BEST  %d" % best
	if score_label.text != t:
		score_label.text = t
