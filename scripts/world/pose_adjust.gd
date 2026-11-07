class_name PoseAdjust
extends SkeletonModifier3D
## 在骨架動畫之後疊加「姿勢修正」：把四腳動物改成用後腳站立的人型姿勢。
## rotations：骨頭名稱 → 繞「骨架空間」的軸旋轉（度數，Vector3 = 繞 X/Y/Z）。
## 依骨頭階層由上而下套用，所以子骨頭的修正是在父骨頭修正之後的方向上再轉。

var rotations: Dictionary = {}  # bone name -> Vector3 degrees (skeleton-space axes)
var scales: Dictionary = {}     # bone name -> float
var _order: Array = []          # [bone_idx, Basis]


func setup(skel: Skeleton3D) -> void:
	_order.clear()
	for i in range(skel.get_bone_count()):
		var bn := skel.get_bone_name(i)
		if rotations.has(bn):
			var r: Vector3 = rotations[bn]
			var b := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
			_order.append([i, b])
	# 依深度排序：父骨頭先處理
	_order.sort_custom(func(a, b): return _depth(skel, a[0]) < _depth(skel, b[0]))


## 用靜止姿勢（rest）＋修正，算出每根骨頭在骨架空間的位置（用來把腳對齊地面、置中）
func corrected_rest_positions(skel: Skeleton3D) -> Dictionary:
	var rots := {}
	for entry in _order:
		rots[entry[0]] = entry[1]
	var globals := {}
	for i in range(skel.get_bone_count()):
		var parent := skel.get_bone_parent(i)
		var local := skel.get_bone_rest(i)
		var pg: Transform3D = globals[parent] if parent >= 0 else Transform3D.IDENTITY
		var g := pg * local
		if rots.has(i):
			g.basis = rots[i] * g.basis
		globals[i] = g
	var out := {}
	for i in globals:
		out[skel.get_bone_name(i)] = globals[i].origin
	return out


static func _depth(skel: Skeleton3D, i: int) -> int:
	var d := 0
	var p := skel.get_bone_parent(i)
	while p >= 0:
		d += 1
		p = skel.get_bone_parent(p)
	return d


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for bn in scales:
		var si := skel.find_bone(bn)
		if si >= 0:
			skel.set_bone_pose_scale(si, Vector3.ONE * float(scales[bn]))
	for entry in _order:
		var i: int = entry[0]
		var rot: Basis = entry[1]
		var parent := skel.get_bone_parent(i)
		var parent_basis := skel.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		var local := Basis(skel.get_bone_pose_rotation(i))
		# 想要：新的全域方向 = rot * 舊的全域方向（繞骨頭本身的位置轉）
		var new_local := parent_basis.inverse() * rot * parent_basis * local
		skel.set_bone_pose_rotation(i, new_local.get_rotation_quaternion())
