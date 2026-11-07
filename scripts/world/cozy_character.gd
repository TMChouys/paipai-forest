class_name CozyCharacter
extends RefCounted
## 用 Cozy Animals（Gamideo，CC0）的綁骨架動物改造成遊戲角色：
## 換貼圖、縮放骨頭（例如把水獺的長尾巴縮短）、在骨頭上掛小配件（門牙、腮紅、帽子）。
## 座標都用模型原始空間（約 1.7 單位高、面向 +Z）。

## 角色設定表
const DEFS := {
	"gopher": {
		"glb": "res://models/cozy/Otter.glb",
		"texture": "res://models/cozy/groundhog_albedo.png",
		"height": 0.95,
		# 尾巴根部：長尾縮成派派鼠的短尾
		"bone_scale": {"Bone_021": 0.42},
		# 站起來：脊椎往上抬，後腿轉回垂直當腳，前腳垂在肚子前當手，頭轉回朝前（骨架空間，度數）
		"stand": {
			"Bone_001": Vector3(-64, 0, 0),
			"Bone_006": Vector3(64, 0, 0), "Bone_011": Vector3(64, 0, 0),
			"Bone_030": Vector3(40, 0, 0), "Bone_035": Vector3(40, 0, 0),
			"Bone_012": Vector3(52, 0, 0),
			"Bone_022": Vector3(50, 0, 0),
		},
		"feet": ["Bone_002", "Bone_007"],
		# 站姿最高點（耳朵尖）
		"top": ["Bone_036", "Bone_038"],
		"attach": [
			{"bone": "Bone_023", "bone2": "Bone_024", "shape": "tooth", "at": Vector3(-0.026, 1.205, 1.45), "size": Vector3(0.048, 0.08, 0.025), "color": "#fffaf0"},
			{"bone": "Bone_023", "bone2": "Bone_024", "shape": "tooth", "at": Vector3(0.026, 1.205, 1.45), "size": Vector3(0.048, 0.08, 0.025), "color": "#fffaf0"},
			{"bone": "Bone_023", "bone2": "Bone_024", "shape": "blush", "at": Vector3(-0.2, 1.25, 1.385), "size": Vector3(0.1, 0.06, 0.03), "color": "#f08080"},
			{"bone": "Bone_023", "bone2": "Bone_024", "shape": "blush", "at": Vector3(0.2, 1.25, 1.385), "size": Vector3(0.1, 0.06, 0.03), "color": "#f08080"},
		],
	},
}


static func build(id: String, node_name: String) -> Node3D:
	var d: Dictionary = DEFS[id]
	var root := Node3D.new()
	root.name = node_name
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var inst: Node3D = (load(d.glb) as PackedScene).instantiate()
	body.add_child(inst)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var k: float = float(d.height) / 1.7
	# 材質：換貼圖 + 繪本描邊
	var tex: Texture2D = load(d.texture) if d.has("texture") and ResourceLoader.exists(d.texture) else null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in range(m.mesh.get_surface_count()):
			var src: BaseMaterial3D = m.get_active_material(s)
			var copy: BaseMaterial3D = src.duplicate()
			if tex:
				copy.albedo_texture = tex
			copy.next_pass = Models.mat(Models.INK, true).next_pass
			m.set_surface_override_material(s, copy)
	# 姿勢修正與骨頭縮放（動畫之後套用）
	var mod := PoseAdjust.new()
	mod.rotations = d.get("stand", {})
	mod.scales = d.get("bone_scale", {})
	skel.add_child(mod)
	mod.setup(skel)
	# 腳踩地、兩腳中間對齊原點
	var pos := mod.corrected_rest_positions(skel)
	var feet: Array = d.get("feet", ["Bone_001"])
	var mid := Vector3.ZERO
	var min_y := INF
	for fb in feet:
		mid += pos.get(fb, Vector3.ZERO)
	mid /= max(feet.size(), 1)
	for fb in feet:
		min_y = min(min_y, pos.get(fb, Vector3.ZERO).y)
	# 依「站起來之後」的高度決定縮放
	if d.has("top"):
		var max_y := -INF
		for tb in d.top:
			max_y = max(max_y, pos.get(tb, Vector3.ZERO).y)
		k = float(d.height) / max(max_y - min_y + 0.08, 0.1)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-mid.x * k, (0.03 - min_y) * k, -mid.z * k)
	# 小配件
	for a in d.get("attach", []):
		var bi2 := skel.find_bone(a.bone)
		if bi2 < 0:
			continue
		var bi3 := skel.find_bone(a.get("bone2", a.bone))
		var ba := BlendAttach.new()
		skel.add_child(ba)
		var mesh_i := MeshInstance3D.new()
		var sz: Vector3 = a.size
		if a.shape == "tooth":
			var bm := BoxMesh.new()
			bm.size = sz
			mesh_i.mesh = bm
			mesh_i.material_override = Models.mat(Color(a.color), true)
		else:
			mesh_i.mesh = Models.sphere(0.5)
			mesh_i.scale = sz
			mesh_i.material_override = Models.mat(Color(a.color), false)
		ba.add_child(mesh_i)
		ba.setup(skel, bi2, bi3 if bi3 >= 0 else bi2, Transform3D(Basis.IDENTITY, a.at))
	# 動畫
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0] if not inst.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	if ap:
		ap.name = "Anim"
		for an in ["idle", "walk"]:
			if ap.has_animation(an):
				ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		root.set_meta("anim", ap)
		if ap.has_animation("idle"):
			ap.play("idle")
	root.set_meta("skeleton", skel)
	return root
