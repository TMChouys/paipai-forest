extends SceneTree
## 開發用：看角色走路動畫裡腿的骨頭擺多大


func _init() -> void:
	var path := "res://models/gopher/gopher_rigged.glb"
	for a in OS.get_cmdline_user_args():
		path = a
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	print("anims ", ap.get_animation_list())
	for bi in skel.get_bone_count():
		print("bone ", bi, " ", skel.get_bone_name(bi), " parent ", skel.get_bone_parent(bi), " rest ", skel.get_bone_rest(bi).origin)
	var an := ap.get_animation("walk")
	print("walk length ", an.length)
	for t in an.get_track_count():
		var p := String(an.track_get_path(t))
		print("track ", t, " ", p, " type ", an.track_get_type(t), " keys ", an.track_get_key_count(t))
		if "leg" in p and an.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			for k in an.track_get_key_count(t):
				var q: Quaternion = an.track_get_key_value(t, k)
				print("   ", snappedf(an.track_get_key_time(t, k), 0.01), " axis ", q.get_axis().snapped(Vector3.ONE * 0.01), " deg ", snappedf(rad_to_deg(q.get_angle()), 0.1))
	quit()
