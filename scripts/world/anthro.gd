class_name Anthro
extends RefCounted
## 獸人角色組合器：人型 Q 版身體（Kenney Mini Characters，CC0，有走路／搬東西／坐下／揮手等動畫）
## ＋ 動物頭（從 Cozy Animals 的綁骨架動物切下來，保留原本的毛皮貼圖）
## ＋ 手腳換成毛色、加尾巴、門牙、腮紅、帽子等小配件。

const BODY_DIR := "res://models/kenney/mini/"
const ANIMAL_DIR := "res://models/cozy/"

## 角色設定
const DEFS := {
	"gopher": {
		"body": "character-male-a",
		"animal": "Otter",
		"texture": "res://models/cozy/groundhog_albedo.png",
		"fur": "#9a7b5c",          # 手、腳的毛色
		"shirt": "#7cc47a",        # 上衣顏色（null = 保留原色）
		"pants": "#6b88c4",
		"head_width": 0.52,        # 頭的寬度（身體約 0.67 高）
		"head_forward": -0.03,     # 頭往前後微調
		"head_up": 0.0,
		"tail": {"from": "Bone_022", "scale": 0.3},
		"feet": "#6e5440",         # 腳掌（原本的鞋子）
		"extras": [
			{"shape": "tooth", "at": Vector3(-0.026, 1.205, 1.45), "size": Vector3(0.048, 0.08, 0.025), "color": "#fffaf0"},
			{"shape": "tooth", "at": Vector3(0.026, 1.205, 1.45), "size": Vector3(0.048, 0.08, 0.025), "color": "#fffaf0"},
			{"shape": "blush", "at": Vector3(-0.2, 1.25, 1.385), "size": Vector3(0.1, 0.06, 0.03), "color": "#f08080"},
			{"shape": "blush", "at": Vector3(0.2, 1.25, 1.385), "size": Vector3(0.1, 0.06, 0.03), "color": "#f08080"},
		],
	},
	# 村長候選與鄰居（tail = "auto"：自動找原模型的尾巴）
	"chief_polarbear": {"body": "character-male-d", "animal": "PolarBear", "fur": "#ece6dc", "feet": "#d9d0c4", "shirt": "#c25b5b", "pants": "#5a6f9a",
		"head_width": 0.56, "tail": {"from": "auto", "scale": 0.5},
		"extras": [{"shape": "hat", "color": "#4a5f86", "band": "#f2c14e"}]},
	"chief_raccoon": {"body": "character-male-b", "animal": "Raccoon", "fur": "#6d6a6e", "feet": "#3d3a3e", "shirt": "#8a6bb5", "pants": "#4a4a5a",
		"head_width": 0.54, "tail": {"from": "auto", "scale": 0.55},
		"extras": [{"shape": "hat", "color": "#3e5c46", "band": "#e8c35a"}]},
	"neighbor_redpanda": {"body": "character-female-b", "animal": "RedPanda", "fur": "#8a3b26", "feet": "#3b2018", "shirt": "#f2c14e", "pants": "#6b8f5a",
		"head_width": 0.54, "tail": {"from": "auto", "scale": 0.55}, "extras": []},
	# 鎮中心的居民
	"tanuki": {"body": "character-male-b", "animal": "Raccoon", "fur": "#7d6047", "feet": "#3d2e22", "shirt": "#d9a35f", "pants": "#6b5a48",
		"head_width": 0.56, "tail": {"from": "auto", "scale": 0.6},
		"extras": [{"shape": "hat", "color": "#9a5b45", "band": "#f2d58a"}]},
	"turtle": {"body": "character-male-c", "proc": "turtle", "fur": "#a3b77f", "feet": "#8a9a6a", "shirt": "#c9b28f", "pants": "#7d725f", "head_width": 0.56},
	"crow": {"body": "character-male-a", "proc": "crow", "fur": "#34465f", "feet": "#c9963f", "shirt": "#d8c7a6", "pants": "#4f5a6b", "head_width": 0.54},
	# 三花奶奶（考官）和孫子黑貓弟弟（暫定名）：程式做的貓頭，模型之後再換
	"calico": {"body": "character-female-a", "proc": "cat", "fur": "#f4eee2", "feet": "#e9dfcf", "shirt": "#9b86b8", "pants": "#6b5a7a", "head_width": 0.56,
		"patch_a": "#e39a4a", "patch_b": "#3a302c", "eyes": "smile"},
	"blackcat": {"body": "character-male-a", "proc": "cat", "fur": "#34303a", "feet": "#2a2630", "shirt": "#e8c35a", "pants": "#4a5f86", "head_width": 0.58,
		"eyes": "round"},
	# 拉拉老闆（雜貨店老闆娘，拉布拉多）、大牙師傅（河狸木匠）：程式做的頭，模型之後再換
	"lala": {"body": "character-female-b", "proc": "dog", "fur": "#e9c27a", "feet": "#d9ad62", "shirt": "#f2e3c4", "pants": "#7a8f5a", "head_width": 0.58},
	"daya": {"body": "character-male-d", "proc": "beaver", "fur": "#8a5a36", "feet": "#5a3a24", "shirt": "#d9b27a", "pants": "#5a6f8a", "head_width": 0.56},
	"neighbor_fox": {"body": "character-female-c", "animal": "Fox", "fur": "#d9672e", "feet": "#3b2018", "shirt": "#7fb7d9", "pants": "#f2efe6",
		"head_width": 0.54, "tail": {"from": "auto", "scale": 0.55}, "extras": []},
}

static var _head_cache: Dictionary = {}


## Blender 做好的獸人（tools/blender/build_gopher.py）：Kenney 人型骨架＋全部動畫，直接載入
const OUTLINE_MATS := ["fur", "cream", "fur_dark", "vest", "leather", "ear_inner"]
const TOON_SHADER := preload("res://shaders/toon.gdshader")
const FACE_SHADER := preload("res://shaders/toon_face.gdshader")


static func from_glb(path: String, node_name: String, height: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	var aabb := AABB()
	for i in meshes.size():
		var mi: MeshInstance3D = meshes[i]
		var b: AABB = mi.get_aabb()
		aabb = b if i == 0 else aabb.merge(b)
	var s: float = height / maxf(aabb.size.y, 0.001)
	inst.scale = Vector3.ONE * s
	# 全部換成卡通著色；臉是 2D 貼圖，可換表情
	var face_mat: ShaderMaterial = null
	var toon_cache: Dictionary = {}
	for mi: MeshInstance3D in meshes:
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m == null:
				continue
			var key := m.resource_name
			if m.albedo_texture != null:
				# 有手繪感貼圖（AI 生成模型）：保留貼圖原本的筆觸，只調成霧面＋細描邊
				if not toon_cache.has(key):
					var tm := m.duplicate() as BaseMaterial3D
					tm.roughness = 1.0
					tm.metallic = 0.0
					tm.metallic_specular = 0.15
					# 毛茸茸：邊緣一圈柔和的亮毛
					tm.rim_enabled = true
					tm.rim = 0.55
					tm.rim_tint = 0.7
					tm.next_pass = Models.outline(0.006, s)
					toon_cache[key] = tm
				mi.set_surface_override_material(si, toon_cache[key])
				continue
			if not toon_cache.has(key):
				var sm := ShaderMaterial.new()
				if key == "face":
					sm.shader = FACE_SHADER
					sm.set_shader_parameter("face", FaceArt.texture("normal"))
					sm.render_priority = 1
					face_mat = sm
				else:
					sm.shader = TOON_SHADER
					sm.set_shader_parameter("albedo", m.albedo_color)
					if key in ["fur", "cream", "fur_dark", "ear_inner"]:
						sm.set_shader_parameter("fur", 1.0)
					if key in OUTLINE_MATS:
						sm.next_pass = Models.outline(0.008, s)
				toon_cache[key] = sm
			mi.set_surface_override_material(si, toon_cache[key])
	if face_mat:
		root.set_meta("face", face_mat)
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap: AnimationPlayer = aps[0]
		ap.name = "Anim"
		for an in ["idle", "walk", "sprint", "holding-both", "sit"]:
			if ap.has_animation(an):
				ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		root.set_meta("anim", ap)
		root.set_meta("anthro", true)
		ap.play("idle")
	if not skels.is_empty():
		root.set_meta("skeleton", skels[0])
	return root


static func build(id: String, node_name: String, height: float = 1.0) -> Node3D:
	var d: Dictionary = DEFS[id]
	if d.has("proc"):
		return build_proc(id, node_name, height)
	var root := Node3D.new()
	root.name = node_name
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var inst: Node3D = (load(BODY_DIR + d.body + ".glb") as PackedScene).instantiate()
	body.add_child(inst)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	# 身體：換色（手腳 → 毛色、衣服顏色），加描邊；隱藏人頭
	var tex := _body_texture(d)
	var body_mats: Array = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if String(m.name).contains("head"):
			m.visible = false
			continue
		var src: BaseMaterial3D = m.get_active_material(0)
		var copy: BaseMaterial3D = src.duplicate()
		copy.albedo_texture = tex
		m.set_surface_override_material(0, copy)
		body_mats.append(copy)
	# 動物頭：掛在 head 骨頭
	var head_info := _animal_head(d)
	var ba := BoneAttachment3D.new()
	ba.bone_name = "head"
	skel.add_child(ba)
	var head_holder := Node3D.new()
	head_holder.name = "Head"
	ba.add_child(head_holder)
	var hb: AABB = head_info.aabb
	var hk: float = float(d.head_width) / hb.size.x
	var head_rest := skel.get_bone_global_rest(skel.find_bone("head"))
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head_info.mesh
	var hm := StandardMaterial3D.new()
	hm.albedo_texture = head_info.texture
	hm.roughness = 1.0
	head_mi.material_override = hm
	head_holder.add_child(head_mi)
	# 頭裡面塞一顆同毛色的「頭骨」，補滿切口與中空內部
	var skull := MeshInstance3D.new()
	skull.mesh = Models.sphere(0.5)
	skull.material_override = Models.mat(head_info.fur_color, false)
	var sc: Vector3 = hb.size * Vector3(0.9, 0.78, 0.66)
	skull.scale = sc
	skull.position = hb.get_center() + Vector3(0, -hb.size.y * 0.1, -hb.size.z * 0.14)
	head_mi.add_child(skull)
	# 動物頭的「下巴底部中心」對到人頭骨的位置
	var anchor := Vector3(hb.get_center().x, hb.position.y, hb.get_center().z + float(d.get("head_forward", 0.0)) / hk)
	head_mi.scale = Vector3.ONE * hk
	head_mi.position = -anchor * hk + Vector3(0, -0.02 + float(d.get("head_up", 0.0)), 0)
	head_holder.transform.origin = Vector3.ZERO
	# 小配件（門牙、腮紅）用動物模型原始座標
	for e in d.get("extras", []):
		var em := MeshInstance3D.new()
		if e.shape == "hat":
			# 小帽子：放在頭頂、稍微往後
			var top := Vector3(hb.get_center().x, hb.end.y - hb.size.y * 0.06, hb.get_center().z - hb.size.z * 0.08)
			var r := hb.size.x * 0.24
			var crown := Models.cyl(r * 0.9, r, r * 1.1)
			em.mesh = crown
			em.material_override = Models.mat(Color(e.color), false)
			em.position = top + Vector3(0, r * 0.55, 0)
			em.rotation_degrees.x = -8
			var brim := MeshInstance3D.new()
			brim.mesh = Models.cyl(r * 1.6, r * 1.6, r * 0.12)
			brim.material_override = Models.mat(Color(e.color), false)
			brim.position = Vector3(0, -r * 0.5, 0)
			em.add_child(brim)
			var band := MeshInstance3D.new()
			band.mesh = Models.cyl(r * 0.93, r * 1.0, r * 0.22)
			band.material_override = Models.mat(Color(e.get("band", "#f2c14e")), false)
			band.position = Vector3(0, -r * 0.3, 0)
			em.add_child(band)
			head_mi.add_child(em)
			continue
		if e.shape == "tooth":
			var bm := BoxMesh.new()
			bm.size = e.size
			em.mesh = bm
			em.material_override = Models.mat(Color(e.color), true)
			em.position = e.at
		else:
			em.mesh = Models.sphere(0.5)
			em.material_override = Models.mat(Color(e.color), false)
			em.position = e.at
			em.scale = e.size
		head_mi.add_child(em)
	# 尾巴：掛在 torso，背後下方
	if d.has("tail"):
		var tail_info := _animal_part(d.animal, d.get("texture", ""), "tail", d.tail.from)
		if not tail_info.is_empty():
			var ta := BoneAttachment3D.new()
			ta.bone_name = "torso"
			skel.add_child(ta)
			var tmi := MeshInstance3D.new()
			tmi.mesh = tail_info.mesh
			tmi.material_override = hm
			var tb: AABB = tail_info.aabb
			var tk: float = hk * float(d.tail.scale)
			tmi.scale = Vector3.ONE * tk
			# 尾巴根部（最前端）接到屁股
			var base := Vector3(tb.get_center().x, tb.position.y + tb.size.y * 0.7, tb.end.z)
			tmi.position = -base * tk + Vector3(0, -0.12, -0.11)
			ta.add_child(tmi)
	# 身體縮放：整體高度
	var total_h := 0.34 + float(d.head_width) * hb.size.y / hb.size.x
	var bs: float = height / total_h
	inst.scale = Vector3.ONE * bs
	# 描邊：世界空間約 0.012 粗，依各自縮放換算
	for bm in body_mats:
		bm.next_pass = Models.outline(0.008, bs)
	hm.next_pass = Models.outline(0.008, bs * hk)
	for c in root.find_children("*", "MeshInstance3D", true, false):
		if c.material_override != null and c.material_override.next_pass != null and c.material_override != hm:
			pass
	# 動畫
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap: AnimationPlayer = aps[0]
		ap.name = "Anim"
		for an in ["idle", "walk", "sprint", "holding-both", "sit"]:
			if ap.has_animation(an):
				ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		root.set_meta("anim", ap)
		root.set_meta("anthro", true)
		ap.play("idle")
	root.set_meta("skeleton", skel)
	return root


# ---------------- 程式拼的頭（沒有現成動物模型的居民：烏龜、烏鴉） ----------------
## Kenney 人型身體＋用球、圓柱拼的頭與配件。頭的單位和 build() 一樣：頭寬 = head_width。
static func build_proc(id: String, node_name: String, height: float = 1.0) -> Node3D:
	var d: Dictionary = DEFS[id]
	var root := Node3D.new()
	root.name = node_name
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var inst: Node3D = (load(BODY_DIR + d.body + ".glb") as PackedScene).instantiate()
	body.add_child(inst)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var tex := _body_texture(d)
	var body_mats: Array = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if String(m.name).contains("head"):
			m.visible = false
			continue
		var copy: BaseMaterial3D = (m.get_active_material(0) as BaseMaterial3D).duplicate()
		copy.albedo_texture = tex
		copy.rim_enabled = true
		copy.rim = 0.4
		copy.rim_tint = 0.7
		m.set_surface_override_material(0, copy)
		body_mats.append(copy)
	var ba := BoneAttachment3D.new()
	ba.bone_name = "head"
	skel.add_child(ba)
	var head := Node3D.new()
	head.name = "Head"
	ba.add_child(head)
	var ta := BoneAttachment3D.new()
	ta.bone_name = "torso"
	skel.add_child(ta)
	var torso := Node3D.new()
	ta.add_child(torso)
	var W: float = d.head_width
	var r := W / 2.0
	var y0 := r * 0.92 - 0.02  # 頭的中心（下巴貼在脖子上）
	var fur := Color(d.fur)
	var parts: Array = []  # 要加描邊的
	var add := func(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, sc: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO, line: bool = true) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = Models.mat(color, false).duplicate()
		mi.position = pos
		mi.scale = sc
		mi.rotation_degrees = rot
		parent.add_child(mi)
		if line:
			parts.append(mi)
		return mi
	match d.proc:
		"turtle":
			# 慢慢館長：圓圓的鼠尾草綠大頭、白眉毛、圓眼鏡、小毛線帽、背上的龜殼
			add.call(head, Models.sphere(r), fur, Vector3(0, y0, 0), Vector3(1, 0.9, 0.95))
			add.call(head, Models.sphere(r * 0.55), Color("cfd8ab"), Vector3(0, y0 - r * 0.32, r * 0.55), Vector3(1.15, 0.7, 0.75), Vector3.ZERO, false)
			for sx in [-1, 1]:
				var e := Vector3(0.36 * r * sx, y0 + r * 0.08, r * 0.86)
				add.call(head, Models.sphere(r * 0.15), Color("2b1d14"), e, Vector3(1, 1.1, 0.7), Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.05), Color("ffffff"), e + Vector3(r * 0.05, r * 0.06, r * 0.08), Vector3.ONE, Vector3.ZERO, false)
				add.call(head, Models.cyl(r * 0.27, r * 0.27, r * 0.03), Color("7a5236"), e + Vector3(0, 0, r * 0.12), Vector3.ONE, Vector3(90, 0, 0), false)  # 鏡框
				add.call(head, Models.cyl(r * 0.22, r * 0.22, r * 0.035), Color("f7f0de"), e + Vector3(0, 0, r * 0.125), Vector3.ONE, Vector3(90, 0, 0), false)  # 鏡片
				add.call(head, Models.sphere(r * 0.16), Color("f4efe4"), e + Vector3(r * 0.03 * sx, r * 0.36, -r * 0.02), Vector3(1.5, 0.55, 0.8), Vector3(0, 0, -12 * sx), false)  # 白眉毛
				add.call(head, Models.sphere(r * 0.12), Color("e9a59a"), Vector3(0.62 * r * sx, y0 - r * 0.22, r * 0.66), Vector3(1, 0.6, 0.4), Vector3.ZERO, false)  # 腮紅
			add.call(head, Models.box(r * 0.18, r * 0.04, r * 0.04), Color("7a5236"), Vector3(0, y0 + r * 0.08, r * 1.08), Vector3.ONE, Vector3.ZERO, false)  # 鼻樑架
			add.call(head, Models.sphere(r * 0.5), Color("b5654f"), Vector3(0, y0 + r * 0.72, -r * 0.08), Vector3(1.5, 0.75, 1.4))  # 小毛線帽
			add.call(head, Models.sphere(r * 0.13), Color("f2e6cc"), Vector3(0, y0 + r * 1.12, -r * 0.08), Vector3.ONE, Vector3.ZERO, false)  # 毛球
			# 龜殼
			add.call(torso, Models.sphere(0.3), Color("8f6e48"), Vector3(0, 0.12, -0.2), Vector3(1.05, 1.15, 0.62))
			add.call(torso, Models.cyl(0.31, 0.31, 0.05), Color("c9a873"), Vector3(0, 0.12, -0.14), Vector3(1.05, 1, 1.15), Vector3(90, 0, 0), false)
			for pp in [Vector3(0, 0.2, -0.36), Vector3(-0.13, 0.05, -0.34), Vector3(0.13, 0.05, -0.34), Vector3(0, -0.08, -0.33)]:
				add.call(torso, Models.sphere(0.085), Color("b08c5c"), pp, Vector3(1, 1, 0.35), Vector3.ZERO, false)
		"crow":
			# 拍拍鳥：炭藍烏鴉、亮晶晶大眼睛、小呆毛、苔綠圍巾、木頭風箱相機
			add.call(head, Models.sphere(r), fur, Vector3(0, y0, 0), Vector3(1, 0.95, 1))
			add.call(head, Models.sphere(r * 0.62), Color("56647a"), Vector3(0, y0 - r * 0.15, r * 0.48), Vector3(1.2, 0.85, 0.6), Vector3.ZERO, false)
			for sx in [-1, 1]:
				var e := Vector3(0.38 * r * sx, y0 + r * 0.1, r * 0.82)
				add.call(head, Models.sphere(r * 0.22), Color("fffaf0"), e, Vector3(1, 1.1, 0.6), Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.14), Color("1e1a18"), e + Vector3(0, -r * 0.02, r * 0.07), Vector3(1, 1.1, 0.6), Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.05), Color("ffffff"), e + Vector3(r * 0.05, r * 0.06, r * 0.13), Vector3.ONE, Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.11), Color("d98a8a"), Vector3(0.62 * r * sx, y0 - r * 0.25, r * 0.62), Vector3(1, 0.6, 0.4), Vector3.ZERO, false)
			add.call(head, Models.cyl(0.0, r * 0.2, r * 0.55), Color("6e7380"), Vector3(0, y0 - r * 0.15, r * 1.12), Vector3(1, 1, 0.75), Vector3(90, 0, 0))  # 嘴
			for i in range(3):
				add.call(head, Models.sphere(r * 0.12), fur, Vector3((i - 1) * r * 0.14, y0 + r * 1.02, r * 0.1 - i * r * 0.05), Vector3(0.6, 1.8, 0.6), Vector3(-20, 0, (i - 1) * 25), false)  # 呆毛
			add.call(head, Models.cyl(r * 0.78, r * 0.86, r * 0.32), Color("7f9a5a"), Vector3(0, -0.01, -r * 0.05))  # 苔綠圍巾
			add.call(head, Models.box(r * 0.3, r * 0.6, r * 0.1), Color("7f9a5a"), Vector3(r * 0.35, -r * 0.4, r * 0.62), Vector3.ONE, Vector3(10, 0, 12))  # 圍巾尾巴
			# 木頭風箱相機（掛在胸前）
			add.call(torso, Models.box(0.2, 0.15, 0.1), Color("b07a4a"), Vector3(0, 0.08, 0.2))
			add.call(torso, Models.box(0.14, 0.12, 0.08), Color("4a3a30"), Vector3(0, 0.08, 0.28), Vector3.ONE, Vector3.ZERO, false)  # 風箱
			add.call(torso, Models.cyl(0.045, 0.045, 0.05), Color("2b2b30"), Vector3(0, 0.08, 0.34), Vector3.ONE, Vector3(90, 0, 0))
			add.call(torso, Models.sphere(0.025), Color("9fd3e6"), Vector3(0, 0.08, 0.365), Vector3(1, 1, 0.4), Vector3.ZERO, false)
		"cat":
			# 貓：圓臉、三角耳朵、白嘴套、粉紅鼻子、鬍鬚；三花奶奶有花斑、瞇瞇眼、珍珠項鍊和披肩，黑貓弟弟是圓圓的金色大眼睛
			add.call(head, Models.sphere(r), fur, Vector3(0, y0, 0), Vector3(1.06, 0.92, 0.95))
			if d.has("patch_a"):
				add.call(head, Models.sphere(r * 0.62), Color(d.patch_a), Vector3(-0.42 * r, y0 + r * 0.42, r * 0.2), Vector3(1, 0.8, 0.9), Vector3(0, 0, 20), false)
				add.call(head, Models.sphere(r * 0.55), Color(d.patch_b), Vector3(0.46 * r, y0 + r * 0.48, r * 0.05), Vector3(1, 0.75, 0.9), Vector3(0, 0, -25), false)
			for sx in [-1, 1]:
				var ear_c := fur
				if d.has("patch_a"):
					ear_c = Color(d.patch_a) if sx < 0 else Color(d.patch_b)
				add.call(head, Models.cyl(0.0, r * 0.34, r * 0.55), ear_c, Vector3(0.56 * r * sx, y0 + r * 0.86, -r * 0.05), Vector3(1, 1, 0.55), Vector3(0, 0, -22 * sx))
				add.call(head, Models.cyl(0.0, r * 0.22, r * 0.36), Color("f0b4b0"), Vector3(0.55 * r * sx, y0 + r * 0.8, r * 0.1), Vector3(1, 1, 0.3), Vector3(0, 0, -22 * sx), false)
				var e := Vector3(0.36 * r * sx, y0 + r * 0.06, r * 0.84)
				if d.get("eyes", "") == "smile":
					# 瞇瞇眼：彎彎的一條線
					add.call(head, Models.capsule(r * 0.045, r * 0.3), Color("2b1d14"), e, Vector3.ONE, Vector3(0, 0, 90 - 14 * sx), false)
				else:
					add.call(head, Models.sphere(r * 0.2), Color("e8c04a"), e, Vector3(1, 1.1, 0.6), Vector3.ZERO, false)
					add.call(head, Models.sphere(r * 0.12), Color("1e1a18"), e + Vector3(0, 0, r * 0.06), Vector3(0.55, 1.2, 0.6), Vector3.ZERO, false)
					add.call(head, Models.sphere(r * 0.05), Color("ffffff"), e + Vector3(r * 0.05, r * 0.07, r * 0.12), Vector3.ONE, Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.12), Color("e9a59a"), Vector3(0.6 * r * sx, y0 - r * 0.2, r * 0.66), Vector3(1, 0.6, 0.4), Vector3.ZERO, false)  # 腮紅
				for k in [-1, 1]:  # 鬍鬚
					add.call(head, Models.box(r * 0.55, r * 0.018, r * 0.018), Color("fffaf0") if fur.v < 0.5 else Color("8a7a6a"),
						Vector3(0.62 * r * sx, y0 - r * (0.22 + 0.07 * k), r * 0.86), Vector3.ONE, Vector3(0, -18 * sx, 8 * k * sx), false)
			add.call(head, Models.sphere(r * 0.38), Color("fbf7ef") if d.has("patch_a") else Color("4a4550"), Vector3(0, y0 - r * 0.3, r * 0.72), Vector3(1.35, 0.72, 0.6), Vector3.ZERO, false)  # 嘴套
			add.call(head, Models.sphere(r * 0.085), Color("e98a92"), Vector3(0, y0 - r * 0.13, r * 0.98), Vector3(1.4, 0.85, 0.7), Vector3.ZERO, false)  # 鼻子
			if d.has("patch_a"):
				# 奶奶：小花髮夾、薰衣草披肩、珍珠項鍊
				add.call(head, Models.sphere(r * 0.12), Color("f3d36b"), Vector3(-0.62 * r, y0 + r * 0.62, r * 0.42), Vector3.ONE, Vector3.ZERO, false)
				for k in range(5):
					var a := TAU * k / 5.0
					add.call(head, Models.sphere(r * 0.1), Color("f4a6b8"), Vector3(-0.62 * r + cos(a) * r * 0.14, y0 + r * 0.62 + sin(a) * r * 0.14, r * 0.38), Vector3(1, 1, 0.5), Vector3.ZERO, false)
				add.call(head, Models.cyl(r * 0.8, r * 0.95, r * 0.3), Color("b9a6d4"), Vector3(0, -0.02, -r * 0.05))
				for k in range(9):
					var a2 := deg_to_rad(-60.0 + k * 15.0)
					add.call(torso, Models.sphere(0.022), Color("fbf8f0"), Vector3(sin(a2) * 0.13, 0.2 - cos(a2) * 0.05, 0.13 + cos(a2) * 0.02), Vector3.ONE, Vector3.ZERO, false)
			else:
				# 弟弟：紅色小領巾
				add.call(head, Models.cyl(r * 0.76, r * 0.84, r * 0.26), Color("d9605a"), Vector3(0, -0.01, -r * 0.05))
				add.call(head, Models.cyl(0.0, r * 0.3, r * 0.4), Color("d9605a"), Vector3(0, -r * 0.3, r * 0.62), Vector3(1, 1, 0.4), Vector3(180, 0, 0))
			# 尾巴：從腰後面往上翹
			for k in range(5):
				var tt := float(k) / 4.0
				add.call(torso, Models.sphere(0.045 - tt * 0.008), fur if k < 4 or not d.has("patch_a") else Color(d.patch_a), Vector3(0, -0.2 + tt * 0.22, -0.16 - sin(tt * PI * 0.8) * 0.12), Vector3.ONE, Vector3.ZERO, k == 4)
		"dog":
			# 拉拉老闆：金黃色拉布拉多、垂耳、長嘴套、黑鼻子、紅頭巾、雜貨店圍裙、粗尾巴
			add.call(head, Models.sphere(r), fur, Vector3(0, y0, 0), Vector3(1.02, 0.95, 0.95))
			add.call(head, Models.sphere(r * 0.5), Color("f4dcae"), Vector3(0, y0 - r * 0.28, r * 0.72), Vector3(1.1, 0.78, 0.95))  # 嘴套
			add.call(head, Models.sphere(r * 0.13), Color("2b2220"), Vector3(0, y0 - r * 0.08, r * 1.16), Vector3(1.4, 1.0, 0.8), Vector3.ZERO, false)  # 鼻子
			add.call(head, Models.capsule(r * 0.03, r * 0.22), Color("6b4a36"), Vector3(0, y0 - r * 0.45, r * 1.1), Vector3.ONE, Vector3(0, 0, 90), false)  # 微笑
			for sx in [-1, 1]:
				add.call(head, Models.sphere(r * 0.42), Color("c99a52"), Vector3(0.9 * r * sx, y0 - r * 0.1, -r * 0.05), Vector3(0.45, 1.25, 0.85), Vector3(0, 0, 14 * sx))  # 垂耳
				var e := Vector3(0.36 * r * sx, y0 + r * 0.16, r * 0.84)
				add.call(head, Models.sphere(r * 0.15), Color("2b1d14"), e, Vector3(1, 1.15, 0.6), Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.05), Color("ffffff"), e + Vector3(r * 0.05, r * 0.06, r * 0.08), Vector3.ONE, Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.1), Color("6b4a36"), e + Vector3(0, r * 0.3, 0), Vector3(1.4, 0.45, 0.6), Vector3.ZERO, false)  # 眉毛
				add.call(head, Models.sphere(r * 0.12), Color("ef9a8a"), Vector3(0.62 * r * sx, y0 - r * 0.24, r * 0.64), Vector3(1, 0.6, 0.4), Vector3.ZERO, false)  # 腮紅
			add.call(head, Models.sphere(r * 0.62), Color("d9605a"), Vector3(0, y0 + r * 0.62, -r * 0.1), Vector3(1.55, 0.6, 1.45))  # 紅頭巾
			add.call(head, Models.sphere(r * 0.16), Color("d9605a"), Vector3(r * 0.5, y0 + r * 0.55, -r * 0.95), Vector3(1, 0.7, 0.6))  # 頭巾結
			# 圍裙＋口袋裡的小筆記本
			add.call(torso, Models.box(0.3, 0.3, 0.03), Color("6f9a5a"), Vector3(0, 0.02, 0.16))
			add.call(torso, Models.box(0.14, 0.08, 0.02), Color("5a8048"), Vector3(0, -0.05, 0.18), Vector3.ONE, Vector3.ZERO, false)
			add.call(torso, Models.box(0.06, 0.08, 0.02), Color("fff8ec"), Vector3(0.04, -0.02, 0.19), Vector3.ONE, Vector3(0, 0, 8), false)
			for k in range(4):
				var tt := float(k) / 3.0
				add.call(torso, Models.sphere(0.055 - tt * 0.012), fur, Vector3(0, -0.2 + tt * 0.12, -0.17 - tt * 0.12), Vector3.ONE, Vector3.ZERO, k == 3)
		"beaver":
			# 大牙師傅：咖啡色河狸、小圓耳、淺色嘴套、兩顆大門牙、耳朵夾鉛筆、工作頭帶、工具腰帶、扁扁的尾巴
			add.call(head, Models.sphere(r), fur, Vector3(0, y0, 0), Vector3(1.05, 0.95, 0.95))
			add.call(head, Models.sphere(r * 0.48), Color("d9b48a"), Vector3(0, y0 - r * 0.3, r * 0.68), Vector3(1.25, 0.8, 0.85))  # 嘴套
			add.call(head, Models.sphere(r * 0.12), Color("3a2418"), Vector3(0, y0 - r * 0.1, r * 1.06), Vector3(1.5, 0.9, 0.8), Vector3.ZERO, false)  # 鼻子
			for sx in [-1, 1]:
				add.call(head, Models.box(r * 0.17, r * 0.26, r * 0.08), Color("fffaf0"), Vector3(0.09 * r * sx, y0 - r * 0.62, r * 1.0), Vector3.ONE, Vector3.ZERO, true)  # 大門牙
				add.call(head, Models.sphere(r * 0.22), fur, Vector3(0.72 * r * sx, y0 + r * 0.66, -r * 0.05), Vector3(1, 1, 0.6))  # 小圓耳
				add.call(head, Models.sphere(r * 0.12), Color("c98a7a"), Vector3(0.72 * r * sx, y0 + r * 0.66, r * 0.04), Vector3(1, 1, 0.4), Vector3.ZERO, false)
				var e := Vector3(0.36 * r * sx, y0 + r * 0.16, r * 0.84)
				add.call(head, Models.sphere(r * 0.14), Color("1e1410"), e, Vector3(1, 1.1, 0.6), Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.05), Color("ffffff"), e + Vector3(r * 0.05, r * 0.06, r * 0.08), Vector3.ONE, Vector3.ZERO, false)
				add.call(head, Models.sphere(r * 0.11), Color("3a2418"), e + Vector3(0, r * 0.28, 0), Vector3(1.6, 0.5, 0.6), Vector3(0, 0, -10 * sx), false)  # 粗眉毛（認真）
				add.call(head, Models.sphere(r * 0.11), Color("e09a84"), Vector3(0.62 * r * sx, y0 - r * 0.26, r * 0.62), Vector3(1, 0.6, 0.4), Vector3.ZERO, false)
			add.call(head, Models.cyl(r * 1.0, r * 1.0, r * 0.2), Color("3f6fa8"), Vector3(0, y0 + r * 0.42, 0), Vector3(1.04, 1, 0.97))  # 工作頭帶
			add.call(head, Models.cyl(r * 0.05, r * 0.05, r * 0.7), Color("f2c14e"), Vector3(r * 0.95, y0 + r * 0.35, r * 0.1), Vector3.ONE, Vector3(70, 0, 10))  # 耳朵上的鉛筆
			add.call(head, Models.cyl(0.0, r * 0.05, r * 0.12), Color("3a2418"), Vector3(r * 0.97, y0 + r * 0.32, r * 0.46), Vector3.ONE, Vector3(70, 0, 10), false)
			# 工具腰帶：小鐵鎚、捲尺
			add.call(torso, Models.cyl(0.25, 0.25, 0.06), Color("8a5a2a"), Vector3(0, -0.13, 0.0), Vector3(1, 1, 0.8))
			add.call(torso, Models.box(0.03, 0.14, 0.03), Color("b07a4a"), Vector3(0.17, -0.2, 0.14), Vector3.ONE, Vector3(0, 0, 10))
			add.call(torso, Models.box(0.09, 0.04, 0.04), Color("6b7480"), Vector3(0.18, -0.13, 0.14), Vector3.ONE, Vector3(0, 0, 10))
			add.call(torso, Models.cyl(0.045, 0.045, 0.03), Color("f2c14e"), Vector3(-0.17, -0.16, 0.15), Vector3.ONE, Vector3(90, 0, 0))
			# 扁扁的大尾巴
			add.call(torso, Models.sphere(0.16), Color("4a3020"), Vector3(0, -0.24, -0.26), Vector3(0.8, 0.2, 1.3), Vector3(-25, 0, 0))
	var head_h := r * 2.0 * 0.95
	var total_h := 0.34 + head_h
	var bs: float = height / total_h
	inst.scale = Vector3.ONE * bs
	for bm in body_mats:
		bm.next_pass = Models.outline(0.008, bs)
	for mi in parts:
		(mi.material_override as BaseMaterial3D).next_pass = Models.outline(0.008, bs)
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap: AnimationPlayer = aps[0]
		ap.name = "Anim"
		for an in ["idle", "walk", "sprint", "holding-both", "sit"]:
			if ap.has_animation(an):
				ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		root.set_meta("anim", ap)
		root.set_meta("anthro", true)
		ap.play("idle")
	root.set_meta("skeleton", skel)
	return root


# ---------------- 身體貼圖換色 ----------------
static func _body_texture(d: Dictionary) -> Texture2D:
	# 網頁版沒有原始 png（只有匯入後的貼圖），所以從匯入的貼圖拿圖片來換色
	var src: Texture2D = load(BODY_DIR + "Textures/colormap.png")
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fur := Color(d.fur)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			# 膚色（偏橘、中等飽和）→ 毛色，保留明暗
			if c.h > 0.02 and c.h < 0.075 and c.s > 0.4 and c.s < 0.72 and c.v > 0.45:
				var shade: float = c.v / 0.75
				img.set_pixel(x, y, Color(fur.r * shade, fur.g * shade, fur.b * shade))
			elif d.has("feet") and ((c.h > 0.08 and c.h < 0.14 and c.s > 0.6) or (c.s < 0.12 and c.v > 0.8 and y > 400 and x > 280 and x < 330)):
				var fc := Color(d.feet)
				var sh: float = c.v / 0.9
				img.set_pixel(x, y, Color(fc.r * sh, fc.g * sh, fc.b * sh))
			elif d.get("shirt") != null and c.h > 0.38 and c.h < 0.45 and c.s > 0.4:
				img.set_pixel(x, y, Color(d.shirt) * Color(c.v / 0.75, c.v / 0.75, c.v / 0.75))
			elif d.get("pants") != null and c.h > 0.6 and c.h < 0.68 and c.s > 0.35 and c.s < 0.6:
				img.set_pixel(x, y, Color(d.pants) * Color(c.v / 0.8, c.v / 0.8, c.v / 0.8))
	return ImageTexture.create_from_image(img)


# ---------------- 從動物模型切出部位 ----------------
static func _animal_head(d: Dictionary) -> Dictionary:
	return _animal_part(d.animal, d.get("texture", ""), "head", "")


## kind = "head"：頭骨（耳朵骨頭的共同父骨）及其子孫＋上一節脖子；
## kind = "tail"：from 骨頭及其子孫。
static func _animal_part(animal: String, tex_path: String, kind: String, from_bone: String) -> Dictionary:
	var key := "%s|%s|%s|%s" % [animal, tex_path, kind, from_bone]
	if _head_cache.has(key):
		return _head_cache[key]
	var n: Node = (load(ANIMAL_DIR + animal + ".glb") as PackedScene).instantiate()
	var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
	var skel: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var src_mat: BaseMaterial3D = mi.get_active_material(0)
	var texture: Texture2D = load(tex_path) if tex_path != "" and ResourceLoader.exists(tex_path) else src_mat.albedo_texture
	var wanted := {}
	var core := {}  # 只有頭骨本身與子孫（不含脖子）
	var head_z := 0.0
	if kind == "head":
		var head := _find_head_bone(skel)
		head_z = skel.get_bone_global_rest(head).origin.z
		for b in _descendants(skel, head):
			wanted[b] = true
			core[b] = true
		var neck := skel.get_bone_parent(head)
		if neck >= 0:
			wanted[neck] = true
	else:
		var tail_root := _find_tail_root(skel) if from_bone == "auto" else skel.find_bone(from_bone)
		if tail_root < 0:
			n.free()
			return {}
		for b in _descendants(skel, tail_root):
			wanted[b] = true
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var nb: int = bones.size() / verts.size()
	# 每個頂點屬於目標部位的權重（skin bind index → 骨頭 index）
	var skin: Skin = mi.skin
	var vw := PackedFloat32Array()
	vw.resize(verts.size())
	var vc := PackedFloat32Array()
	vc.resize(verts.size())
	for i in range(verts.size()):
		var s := 0.0
		for j in range(nb):
			var bind: int = bones[i * nb + j]
			var bi := bind
			if skin:
				var bn := skin.get_bind_name(bind)
				bi = skel.find_bone(bn) if bn != "" else skin.get_bind_bone(bind)
			if wanted.has(bi):
				s += weights[i * nb + j]
			if core.has(bi):
				vc[i] += weights[i * nb + j]
		vw[i] = s
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var remap := {}
	var out_i := 0
	var aabb := AABB()
	var first := true
	for t in range(0, idx.size(), 3):
		var tri := [idx[t], idx[t + 1], idx[t + 2]]
		var avg: float = (vw[tri[0]] + vw[tri[1]] + vw[tri[2]]) / 3.0
		if avg < 0.5:
			continue
		if kind == "head":
			# 臉（頭骨前方）可以含一半脖子權重（嘴巴）；後腦勺只留頭骨本身，避免脖子的尖片
			var cz: float = (verts[tri[0]].z + verts[tri[1]].z + verts[tri[2]].z) / 3.0
			var core_avg: float = (vc[tri[0]] + vc[tri[1]] + vc[tri[2]]) / 3.0
			if cz < head_z + 0.1 and core_avg < 0.5:
				continue
		for v in tri:
			if not remap.has(v):
				remap[v] = out_i
				out_i += 1
				st.set_normal(normals[v])
				st.set_uv(uvs[v])
				st.add_vertex(verts[v])
				if first:
					aabb = AABB(verts[v], Vector3.ZERO)
					first = false
				else:
					aabb = aabb.expand(verts[v])
			st.add_index(remap[v])
	n.free()
	if first:
		return {}
	var result := {"mesh": st.commit(), "aabb": aabb, "texture": texture, "fur_color": _fur_color(texture, uvs, remap.keys())}
	_head_cache[key] = result
	return result


## 從貼圖取樣主要毛色（跳過白色口鼻、黑色眼鼻）
static func _fur_color(tex: Texture2D, uvs: PackedVector2Array, used: Array) -> Color:
	var img := tex.get_image()
	if img == null:
		return Color("a08060")
	if img.is_compressed():
		img.decompress()
	var acc := Color(0, 0, 0)
	var n := 0
	for v in used:
		var uv: Vector2 = uvs[v]
		var c := img.get_pixel(clamp(int(uv.x * img.get_width()), 0, img.get_width() - 1), clamp(int(uv.y * img.get_height()), 0, img.get_height() - 1))
		if c.s > 0.15 and c.v > 0.25 and c.v < 0.85:
			acc += c
			n += 1
	if n == 0:
		return Color("a08060")
	return Color(acc.r / n, acc.g / n, acc.b / n)


## 尾巴根：最後面（z 最小）的末端骨頭，往上找到分岔點的下一節
static func _find_tail_root(skel: Skeleton3D) -> int:
	var best := -1
	var best_z := INF
	for i in range(skel.get_bone_count()):
		if skel.get_bone_children(i).is_empty():
			var z := skel.get_bone_global_rest(i).origin.z
			if z < best_z:
				best_z = z
				best = i
	if best < 0:
		return -1
	var cur := best
	while skel.get_bone_parent(cur) >= 0 and skel.get_bone_children(skel.get_bone_parent(cur)).size() == 1:
		cur = skel.get_bone_parent(cur)
	return cur


## 頭骨 = 兩個最高的末端骨頭（耳朵尖）的最低共同祖先
static func _find_head_bone(skel: Skeleton3D) -> int:
	# 耳朵：左右對稱（x 一正一負、高度相近）的一對末端骨頭中最高的一對
	var leaves: Array = []
	for i in range(skel.get_bone_count()):
		if skel.get_bone_children(i).is_empty():
			leaves.append(i)
	var best_pair := [-1, -1]
	var best_y := -INF
	var max_y := -INF
	for i in range(skel.get_bone_count()):
		max_y = max(max_y, skel.get_bone_global_rest(i).origin.y)
	for a_i in leaves:
		var pa := skel.get_bone_global_rest(a_i).origin
		if pa.x <= 0.03 or pa.y < max_y * 0.7:
			continue
		for b_i in leaves:
			var pb := skel.get_bone_global_rest(b_i).origin
			if pb.x >= -0.03:
				continue
			if abs(pa.x + pb.x) > 0.12 or abs(pa.y - pb.y) > 0.12 or abs(pa.z - pb.z) > 0.15:
				continue
			var y: float = (pa.y + pb.y) / 2.0
			if y > best_y:
				best_y = y
				best_pair = [a_i, b_i]
	if best_pair[0] < 0:
		# 沒有耳朵骨頭：沿最高的骨頭鏈往下，到分岔點（胸口）為止；頭骨 = 分岔點往上第二節
		var top := -1
		var top_y := -INF
		for l in leaves:
			var ly := skel.get_bone_global_rest(l).origin.y
			if ly > top_y:
				top_y = ly
				top = l
		var chain: Array = [top]
		var cur: int = top
		while skel.get_bone_parent(cur) >= 0 and skel.get_bone_children(skel.get_bone_parent(cur)).size() == 1:
			cur = skel.get_bone_parent(cur)
			chain.push_front(cur)
		return chain[1] if chain.size() > 1 else chain[0]
	var anc := {}
	var p: int = best_pair[0]
	while p >= 0:
		anc[p] = true
		p = skel.get_bone_parent(p)
	p = best_pair[1]
	while p >= 0 and not anc.has(p):
		p = skel.get_bone_parent(p)
	return max(p, 0)


static func _descendants(skel: Skeleton3D, b: int) -> Array:
	var out: Array = [b]
	var i := 0
	while i < out.size():
		for c in skel.get_bone_children(out[i]):
			out.append(c)
		i += 1
	return out
