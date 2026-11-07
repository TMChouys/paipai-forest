class_name BoneScaler
extends SkeletonModifier3D
## 在動畫之後把指定骨頭縮放（例如把長尾巴縮短）。

var scales: Dictionary = {}  # bone index -> float


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for bi in scales:
		skel.set_bone_pose_scale(bi, Vector3.ONE * float(scales[bi]))
