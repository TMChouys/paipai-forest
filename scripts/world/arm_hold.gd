class_name ArmHold
extends SkeletonModifier3D
## 走路動畫之上，把雙手固定成「捧著」的姿勢（抱家具邊走邊用）。
## 姿勢取自動畫片段（例如 holding-both）第一個關鍵影格。

var poses: Dictionary = {}  # bone idx -> Quaternion


static func from_animation(skel: Skeleton3D, anim: Animation, bone_names: Array) -> ArmHold:
	var m := ArmHold.new()
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bn := String(anim.track_get_path(t).get_concatenated_subnames())
		if bn in bone_names and anim.track_get_key_count(t) > 0:
			var bi := skel.find_bone(bn)
			if bi >= 0:
				m.poses[bi] = anim.track_get_key_value(t, 0)
	m.active = false
	return m


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for bi in poses:
		skel.set_bone_pose_rotation(bi, poses[bi])
