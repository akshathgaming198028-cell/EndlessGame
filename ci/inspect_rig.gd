extends SceneTree

# Debug tool: prints the real bone rest poses and animation poses so the rig can be fixed from numbers.

func _init() -> void:
	var pl: Node = (load("res://assets/player.glb") as PackedScene).instantiate()
	get_root().add_child(pl)
	var psk := _find_skel(pl)
	print("PLAYER scale=", pl.scale, " rot=", pl.rotation_degrees)
	_dump_rest("PLAYER", psk)
	for f in ["Running.fbx", "Zombie Death.fbx", "Idle.fbx", "Jump.fbx", "Falling To Roll.fbx"]:
		var inst: Node = (load("res://assets/anims/" + f) as PackedScene).instantiate()
		get_root().add_child(inst)
		var ssk := _find_skel(inst)
		var ap := _find_ap(inst)
		print("ANIM ", f, " bones=", ssk.get_bone_count(), " clips=", ap.get_animation_list() if ap else "none")
		_dump_rest(f, ssk)
		if ap and ap.get_animation_list().size() > 0:
			var nm: String = ap.get_animation_list()[0]
			var an := ap.get_animation(nm)
			print("  clip ", nm, " length=", an.length, " tracks=", an.get_track_count())
			for t in an.get_track_count():
				var n := str(an.track_get_path(t))
				if n.contains("Hips") and an.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					print("  hips rot track ", n, " key0=", an.track_get_key_value(t, 0), " keyMid=", an.track_get_key_value(t, an.track_get_key_count(t) / 2))
			for tt in [0.0, an.length * 0.5]:
				ap.play(nm)
				ap.seek(tt, true)
				_lean("  pose at t=%.2f " % tt, ssk)
		inst.queue_free()
	quit()

func _lean(label: String, sk: Skeleton3D) -> void:
	var h := sk.find_bone("mixamorig:Hips")
	var hd := sk.find_bone("mixamorig:Head")
	if h < 0 or hd < 0:
		return
	var hp := sk.get_bone_global_pose(h).origin
	var hdp := sk.get_bone_global_pose(hd).origin
	var v := hdp - hp
	print(label, "hips->head vector=", v, " lean_deg_from_up=", rad_to_deg(atan2(absf(v.z), v.y)))

func _dump_rest(label: String, sk: Skeleton3D) -> void:
	if sk == null:
		print(label, " NO SKELETON")
		return
	for b in ["mixamorig:Hips", "mixamorig:Spine", "mixamorig:Head", "mixamorig:LeftUpLeg", "mixamorig:LeftArm"]:
		var i := sk.find_bone(b)
		if i >= 0:
			var q := sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
			print("  ", label, " ", b, " rest_euler_deg=", q.get_euler() * 57.29578, " origin=", sk.get_bone_global_rest(i).origin)

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
