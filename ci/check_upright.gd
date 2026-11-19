extends SceneTree

# Measures, in world space, how far the character leans and how low his feet go, for each animation,
# with plain rotations and after the upright correction the game uses.

const ANIMS := ["Running.fbx", "Idle.fbx", "Jump.fbx", "Falling To Roll.fbx"]

func _init() -> void:
	var pl: Node3D = (load("res://assets/player.glb") as PackedScene).instantiate()
	pl.scale = Vector3.ONE * 2.0
	pl.rotation = Vector3(0, PI, 0)
	get_root().add_child(pl)
	var psk := _find_skel(pl)
	var base := Basis(Vector3.UP, PI).scaled(Vector3.ONE * 2.0)
	var ap2 := AnimationPlayer.new()
	pl.add_child(ap2)
	var lib := AnimationLibrary.new()
	var names := []
	var rel := str(pl.get_path_to(psk))
	for f in ANIMS:
		var inst: Node = (load("res://assets/anims/" + f) as PackedScene).instantiate()
		get_root().add_child(inst)
		var sap := _find_ap(inst)
		var sk := _find_skel(inst)
		var an := sap.get_animation(sap.get_animation_list()[0]).duplicate() as Animation
		for t in range(an.get_track_count() - 1, -1, -1):
			var bone := an.track_get_path(t).get_concatenated_subnames()
			var pb := _pbone(psk, bone)
			if pb == "" or an.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				an.remove_track(t)
				continue
			an.track_set_path(t, NodePath(rel + ":" + pb))
		an.loop_mode = Animation.LOOP_NONE
		lib.add_animation(f, an)
		names.append(f)
		inst.queue_free()
	ap2.add_animation_library("", lib)
	for f in names:
		for tt in [0.0, 0.25, 0.5, 0.75]:
			var t: float = minf(tt, ap2.get_animation(f).length)
			ap2.play(f)
			ap2.seek(t, true)
			var before := _measure(pl, psk, base, null)
			var a := _correct(pl, psk, base)
			var after := _measure(pl, psk, Basis(Vector3.RIGHT, a) * base, null)
			print("CHECK ", f, " t=%.2f" % t, " lean_plain=%.1f" % before[0], " corr_deg=%.1f" % rad_to_deg(a), " lean_after=%.1f" % after[0], " foot_low_after=%.3f" % after[1])
	quit()

# Returns [lean in degrees from up, lowest foot height in world] for the current pose.
func _measure(pl: Node3D, sk: Skeleton3D, b: Basis, _x) -> Array:
	pl.transform = Transform3D(b, pl.transform.origin)
	sk.force_update_all_bone_transforms()
	var hp := sk.global_transform * sk.get_bone_global_pose(_bi(sk, "Hips")).origin
	var hdp := sk.global_transform * sk.get_bone_global_pose(_bi(sk, "Head")).origin
	var v := (hdp - hp).normalized()
	var lean := rad_to_deg(acos(clampf(v.y, -1.0, 1.0)))
	var low := 1e9
	for fb in ["LeftFoot", "RightFoot"]:
		var fi := _bi(sk, fb)
		if fi >= 0:
			low = minf(low, (sk.global_transform * sk.get_bone_global_pose(fi).origin).y)
	return [lean, low]

# Turns the root so the hips-to-head line is vertical. Measured with the root un-turned first.
func _correct(pl: Node3D, sk: Skeleton3D, base: Basis) -> float:
	pl.transform = Transform3D(base, pl.transform.origin)
	sk.force_update_all_bone_transforms()
	var hp := sk.global_transform * sk.get_bone_global_pose(_bi(sk, "Hips")).origin
	var hdp := sk.global_transform * sk.get_bone_global_pose(_bi(sk, "Head")).origin
	var v := hdp - hp
	var a := -atan2(v.z, v.y)
	pl.transform = Transform3D(Basis(Vector3.RIGHT, a) * base, pl.transform.origin)
	return a

func _pbone(psk: Skeleton3D, bone: String) -> String:
	var k := _key(bone)
	for i in psk.get_bone_count():
		if _key(psk.get_bone_name(i)) == k:
			return psk.get_bone_name(i)
	return ""

func _key(n: String) -> String:
	return n.replace(":", "").replace("_", "").to_lower()

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
