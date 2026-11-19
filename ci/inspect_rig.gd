extends SceneTree

# Debug tool: prints the real bone rest poses and animation poses so the rig can be fixed from numbers.

func _init() -> void:
	var pl: Node = (load("res://assets/player.glb") as PackedScene).instantiate()
	get_root().add_child(pl)
	var psk := _find_skel(pl)
	print("PLAYER scale=", pl.scale, " rot=", pl.rotation_degrees, " skel=", psk != null)
	if psk != null:
		for i in range(4):
			print("PLAYER bone ", i, " = ", psk.get_bone_name(i))
	_dump_rest("PLAYER", psk)
	# the same retarget the game uses, played on the player: prints the lean of the converted pose
	var rinst: Node = (load("res://assets/anims/Running.fbx") as PackedScene).instantiate()
	get_root().add_child(rinst)
	var rap := _find_ap(rinst)
	var rsk := _find_skel(rinst)
	var ra := rap.get_animation(rap.get_animation_list()[0])
	var conv := _retarget(ra, rsk, psk, str(pl.get_path_to(psk)))
	var rlib := AnimationLibrary.new()
	rlib.add_animation("run", conv)
	var ap2 := AnimationPlayer.new()
	pl.add_child(ap2)
	ap2.add_animation_library("", rlib)
	for tt in [0.0, 0.15, 0.3]:
		ap2.play("run")
		ap2.seek(tt, true)
		_lean("RETARGETED-on-PLAYER run t=%.2f " % tt, psk)
	print("RETARGETED tracks=", conv.get_track_count())
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
				print("  rest-vs-pose check t=", tt)
				_lean("  pose at t=%.2f " % tt, ssk)
		inst.queue_free()
	quit()

func _bi(sk: Skeleton3D, nm: String) -> int:
	var i := sk.find_bone("mixamorig:" + nm)
	if i < 0:
		i = sk.find_bone("mixamorig_" + nm)
	return i

func _retarget(an: Animation, ssk: Skeleton3D, psk: Skeleton3D, skel_rel: String) -> Animation:
	var out := an.duplicate() as Animation
	var srcr := {}
	for i in ssk.get_bone_count():
		srcr[_key(ssk.get_bone_name(i))] = ssk.get_bone_rest(i).basis.get_rotation_quaternion()
	var tgtr := {}
	var tgtname := {}
	for i in psk.get_bone_count():
		var k := _key(psk.get_bone_name(i))
		tgtr[k] = psk.get_bone_rest(i).basis.get_rotation_quaternion()
		tgtname[k] = psk.get_bone_name(i)
	for t in range(out.get_track_count() - 1, -1, -1):
		var k := _key(out.track_get_path(t).get_concatenated_subnames())
		if not srcr.has(k) or not tgtr.has(k):
			out.remove_track(t)
			continue
		if out.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			var qm: Quaternion = tgtr[k].inverse() * srcr[k]
			for kk in out.track_get_key_count(t):
				out.track_set_key_value(t, kk, qm * out.track_get_key_value(t, kk))
		else:
			out.remove_track(t)
			continue
		out.track_set_path(t, NodePath(skel_rel + ":" + tgtname[k]))
	return out

func _key(n: String) -> String:
	return n.replace(":", "").replace("_", "").to_lower()

func _lean(label: String, sk: Skeleton3D) -> void:
	var h := _bi(sk, "Hips")
	var hd := _bi(sk, "Head")
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
	for b in ["Hips", "Spine", "Head", "LeftUpLeg", "LeftArm"]:
		var i := _bi(sk, b)
		if i >= 0:
			var q := sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
			print("  ", label, " ", b, " idx=", i, " rest_euler_deg=", q.get_euler() * 57.29578, " origin=", sk.get_bone_global_rest(i).origin)

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
