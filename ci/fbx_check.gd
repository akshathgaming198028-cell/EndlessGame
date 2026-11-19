extends SceneTree

# Plain check of the Mixamo FBX: no corrections. Prints its size and, per animation, the lean and foot heights.

const FILES := {"run": "Running.fbx", "idle": "Idle.fbx", "die": "Zombie Death.fbx", "jump": "Jump.fbx", "slide": "Falling To Roll.fbx"}
var done := false

func _process(_d: float) -> bool:
	if not done:
		done = true
		_run()
		quit()
	return false

func _run() -> void:
	var pl: Node3D = (load("res://assets/playercriminal.fbx") as PackedScene).instantiate()
	get_root().add_child(pl)
	var psk := _find_skel(pl)
	var rel := str(pl.get_path_to(psk))
	print("MODEL bones=", psk.get_bone_count(), " scale=", pl.scale, " rot=", pl.rotation_degrees)
	var hips := _bi(psk, "Hips")
	psk.force_update_all_bone_transforms()
	var top := 0.0
	var bottom := 99.0
	var hd := _bi(psk, "Head")
	var lf := _bi(psk, "LeftFoot")
	var rf := _bi(psk, "RightFoot")
	print("MODEL head_y=%.3f leftfoot_y=%.3f hips_y=%.3f" % [(psk.global_transform * psk.get_bone_global_pose(hd).origin).y, (psk.global_transform * psk.get_bone_global_pose(lf).origin).y, (psk.global_transform * psk.get_bone_global_pose(hips).origin).y])
	var ap := AnimationPlayer.new()
	pl.add_child(ap)
	var lib := AnimationLibrary.new()
	for key in FILES:
		lib.add_animation(key, _clip(FILES[key], psk, rel))
	ap.add_animation_library("", lib)
	for key in FILES:
		var mn := 99.0
		var mx := -99.0
		var fmn := 99.0
		var fmx := -99.0
		var length := ap.get_animation(key).length
		for k in range(9):
			ap.play(key)
			ap.seek(length * float(k) / 8.0, true)
			psk.force_update_all_bone_transforms()
			var hp := psk.global_transform * psk.get_bone_global_pose(hips).origin
			var hdp := psk.global_transform * psk.get_bone_global_pose(hd).origin
			var lean := rad_to_deg(acos(clampf((hdp - hp).normalized().y, -1.0, 1.0)))
			mn = minf(mn, lean)
			mx = maxf(mx, lean)
			var low := minf((psk.global_transform * psk.get_bone_global_pose(lf).origin).y, (psk.global_transform * psk.get_bone_global_pose(rf).origin).y)
			fmn = minf(fmn, low)
			fmx = maxf(fmx, low)
		print("CHECK ", key, " lean_deg min=%.1f max=%.1f" % [mn, mx], " foot_y min=%.3f max=%.3f" % [fmn, fmx])

func _clip(file: String, psk: Skeleton3D, rel: String) -> Animation:
	var inst: Node = (load("res://assets/anims/" + file) as PackedScene).instantiate()
	get_root().add_child(inst)
	var sap := _find_ap(inst)
	var an := sap.get_animation(sap.get_animation_list()[0]).duplicate() as Animation
	inst.queue_free()
	for t in range(an.get_track_count() - 1, -1, -1):
		var pb := _pbone(psk, an.track_get_path(t).get_concatenated_subnames())
		if pb == "" or an.track_get_type(t) == Animation.TYPE_POSITION_3D:
			an.remove_track(t)
			continue
		an.track_set_path(t, NodePath(rel + ":" + pb))
	return an

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
