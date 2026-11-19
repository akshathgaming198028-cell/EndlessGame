extends SceneTree

# Plays each animation on the real character and prints, in world space, how far the body leans
# and how low the feet go. Variant A = what the game does now. Variant B = keeps the hips' motion
# but removes the lean the clip starts with, and places the hips' bounce in the character's frame.

const FILES := {"run": "Running.fbx", "idle": "Idle.fbx", "die": "Zombie Death.fbx", "jump": "Jump.fbx"}
var done := false

func _process(_d: float) -> bool:
	if not done:
		done = true
		_run()
		quit()
	return false

func _run() -> void:
	var pl: Node3D = (load("res://assets/player.glb") as PackedScene).instantiate()
	pl.scale = Vector3.ONE * 2.0
	pl.rotation = Vector3(0, PI, 0)
	get_root().add_child(pl)
	var psk := _find_skel(pl)
	var rel := str(pl.get_path_to(psk))
	var hips := _bi(psk, "Hips")
	var hips_rest: Quaternion = psk.get_bone_rest(hips).basis.get_rotation_quaternion()
	print("HIPS rest_euler_deg=", hips_rest.get_euler() * 57.29578)
	var apa := AnimationPlayer.new()
	pl.add_child(apa)
	var apb := AnimationPlayer.new()
	pl.add_child(apb)
	var la := AnimationLibrary.new()
	var lb := AnimationLibrary.new()
	for key in FILES:
		la.add_animation(key, _make(FILES[key], psk, rel, "A", hips_rest, key))
		lb.add_animation(key, _make(FILES[key], psk, rel, "B", hips_rest, key))
	apa.add_animation_library("", la)
	apb.add_animation_library("", lb)
	for pair in [["A", apa], ["B", apb]]:
		for key in FILES:
			var mn := 99.0
			var mx := -99.0
			var fmn := 99.0
			var fmx := -99.0
			var ap: AnimationPlayer = pair[1]
			var length := ap.get_animation(key).length
			for k in range(9):
				ap.play(key)
				ap.seek(length * float(k) / 8.0, true)
				psk.force_update_all_bone_transforms()
				var hp := psk.global_transform * psk.get_bone_global_pose(hips).origin
				var hd := psk.global_transform * psk.get_bone_global_pose(_bi(psk, "Head")).origin
				var v := (hd - hp).normalized()
				var lean := rad_to_deg(acos(clampf(v.y, -1.0, 1.0)))
				mn = minf(mn, lean)
				mx = maxf(mx, lean)
				var low := 99.0
				for fb in ["LeftFoot", "RightFoot"]:
					var fi := _bi(psk, fb)
					if fi >= 0:
						low = minf(low, (psk.global_transform * psk.get_bone_global_pose(fi).origin).y)
				fmn = minf(fmn, low)
				fmx = maxf(fmx, low)
			print("CHECK ", pair[0], " ", key, " lean_deg min=%.1f max=%.1f" % [mn, mx], " foot_y min=%.3f max=%.3f" % [fmn, fmx])

func _make(file: String, psk: Skeleton3D, rel: String, variant: String, hips_rest: Quaternion, key: String) -> Animation:
	var inst: Node = (load("res://assets/anims/" + file) as PackedScene).instantiate()
	get_root().add_child(inst)
	var sap := _find_ap(inst)
	var an := sap.get_animation(sap.get_animation_list()[0]).duplicate() as Animation
	inst.queue_free()
	var loop_ok := key == "run" or key == "idle"
	an.loop_mode = Animation.LOOP_LINEAR if loop_ok else Animation.LOOP_NONE
	for t in range(an.get_track_count() - 1, -1, -1):
		var pb := _pbone(psk, an.track_get_path(t).get_concatenated_subnames())
		if pb == "":
			an.remove_track(t)
			continue
		var is_hips := pb == "mixamorig_Hips" or pb == "mixamorig:Hips"
		var ty := an.track_get_type(t)
		if ty == Animation.TYPE_ROTATION_3D:
			if is_hips and variant == "A":
				an.remove_track(t)
				continue
			if is_hips and variant == "B" and loop_ok:
				var mean := _mean(an, t)
				for kk in an.track_get_key_count(t):
					an.track_set_key_value(t, kk, mean.inverse() * an.track_get_key_value(t, kk))
		elif ty == Animation.TYPE_POSITION_3D:
			if not is_hips or variant == "A":
				an.remove_track(t)
				continue
			for kk in an.track_get_key_count(t):
				an.track_set_key_value(t, kk, hips_rest * an.track_get_key_value(t, kk))
		an.track_set_path(t, NodePath(rel + ":" + pb))
	return an

func _mean(an: Animation, t: int) -> Quaternion:
	var ref: Quaternion = an.track_get_key_value(t, 0)
	var ax := 0.0
	var ay := 0.0
	var az := 0.0
	var aw := 0.0
	for i in an.track_get_key_count(t):
		var q: Quaternion = an.track_get_key_value(t, i)
		if q.dot(ref) < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		ax += q.x
		ay += q.y
		az += q.z
		aw += q.w
	return Quaternion(ax, ay, az, aw).normalized()

func _pbone(psk: Skeleton3D, bone: String) -> String:
	var k := bone.replace(":", "").replace("_", "").to_lower()
	for i in psk.get_bone_count():
		if psk.get_bone_name(i).replace(":", "").replace("_", "").to_lower() == k:
			return psk.get_bone_name(i)
	return ""

func _bi(sk: Skeleton3D, nm: String) -> int:
	var i := sk.find_bone("mixamorig:" + nm)
	if i < 0:
		i = sk.find_bone("mixamorig_" + nm)
	return i

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null
