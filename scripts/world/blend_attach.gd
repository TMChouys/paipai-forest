class_name BlendAttach
extends Node3D
## 掛在「兩根骨頭的中間」的小配件（門牙、腮紅）。
## 嘴巴的皮膚一半跟頭骨、一半跟上一節骨頭動，只跟其中一根會錯位。

var skel: Skeleton3D
var bone_a := -1
var bone_b := -1
var weight := 0.5
var offset := Transform3D.IDENTITY  # 在「混合後骨頭空間」的位置


func setup(s: Skeleton3D, a: int, b: int, at_skeleton_space: Transform3D, w: float = 0.5) -> void:
	skel = s
	bone_a = a
	bone_b = b
	weight = w
	var rest := _blend(skel.get_bone_global_rest(a), skel.get_bone_global_rest(b))
	offset = rest.affine_inverse() * at_skeleton_space
	skel.skeleton_updated.connect(_update)
	_update()


func _blend(ta: Transform3D, tb: Transform3D) -> Transform3D:
	return ta.interpolate_with(tb, weight)


func _update() -> void:
	if skel == null:
		return
	transform = _blend(skel.get_bone_global_pose(bone_a), skel.get_bone_global_pose(bone_b)) * offset
