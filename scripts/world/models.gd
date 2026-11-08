class_name Models
extends RefCounted
## 繪本風佔位模型：用基本形狀拼出家具與角色，外加描邊（inverted hull）。
## 之後有正式 GLB 時，在 furniture.json 填 "model": "res://models/xxx.glb" 就會改用模型。

const INK := Color("5a3d2b")
static var _mat_cache: Dictionary = {}


static func mat(color: Color, outline: bool = true, glow: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), outline, glow]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.metallic_specular = 0.2
	storybook_texture(m)
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.8
	if outline:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = 0.018
		o.albedo_color = INK
		m.next_pass = o
	_mat_cache[key] = m
	return m


## 繪本材質：木頭色的東西加上北歐淺木紋，其他東西加上毛氈／紙張的細纖維
static var _felt_tex: Texture2D
static var _wood_tex: Texture2D


static func is_wood(c: Color) -> bool:
	return c.h > 0.03 and c.h < 0.13 and c.s > 0.22 and c.s < 0.72 and c.v > 0.35 and c.v < 0.93


static func storybook_texture(m: BaseMaterial3D) -> void:
	if m.albedo_texture != null:
		return
	if is_wood(m.albedo_color):
		if _wood_tex == null:
			_wood_tex = ImageTexture.create_from_image(RoomView._wood_image())
		m.albedo_texture = _wood_tex
		m.uv1_scale = Vector3(2.0, 2.0, 2.0)
	else:
		if _felt_tex == null:
			var n := FastNoiseLite.new()
			n.seed = 11
			n.frequency = 0.09
			n.fractal_octaves = 3
			var img := n.get_seamless_image(128, 128, false, false, 0.15, true)
			img.convert(Image.FORMAT_RGB8)
			for y in range(128):
				for x in range(128):
					var v := 0.9 + 0.1 * img.get_pixel(x, y).r
					img.set_pixel(x, y, Color(v, v, v * 0.98))
			img.generate_mipmaps()
			_felt_tex = ImageTexture.create_from_image(img)
		m.albedo_texture = _felt_tex
		m.uv1_scale = Vector3(3, 3, 3)
	m.uv1_triplanar = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## 指定粗細的描邊材質（模型被縮放時用，讓線條看起來一樣粗）
static var _outline_cache: Dictionary = {}
static func outline(world_width: float, scale: float) -> Material:
	var g := snappedf(world_width / max(scale, 0.0001), 0.0005)
	if _outline_cache.has(g):
		return _outline_cache[g]
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = g
	o.albedo_color = INK
	_outline_cache[g] = o
	return o


static func part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scale: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO, outline: bool = true, glow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, outline, glow)
	mi.position = pos
	mi.scale = scale
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Kenney 材質名稱 → 繪本風色票（沒列到的就用轉換後的原色）
const KENNEY_PALETTE := {
	"leafsGreen": Color("7cbf5e"), "leafsDark": Color("5e9e4a"), "leafsFall": Color("e8a04a"),
	"grass": Color("8cc66a"), "plant": Color("7cbf5e"), "woodBark": Color("9a6a45"), "woodBarkDark": Color("7a5236"),
	"stone": Color("cfc6b8"), "stoneDark": Color("ada393"), "dirt": Color("c9955f"), "metal": Color("c4c0ba"), "metalMedium": Color("9a958e"), "metalDark": Color("7f7a73"),
}


## 載入 GLB，並幫每個材質加上繪本描邊
static func glb(path: String, tint: Color = Color.WHITE) -> Node3D:
	var scene: PackedScene = load(path)
	var inst: Node3D = scene.instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in range(m.mesh.get_surface_count()):
			var src: Material = m.get_active_material(s)
			if src is BaseMaterial3D:
				var copy: BaseMaterial3D = src.duplicate()
				if path.contains("/kenney/") and copy.albedo_texture == null:
					# Kenney 的單色材質匯入後偏亮偏白：轉回線性色彩，再套繪本色票
					copy.albedo_color = KENNEY_PALETTE.get(String(src.resource_name), copy.albedo_color.srgb_to_linear())
				copy.albedo_color *= tint
				storybook_texture(copy)
				copy.next_pass = mat(INK, true).next_pass
				m.set_surface_override_material(s, copy)
	return inst


## 依整體外框把模型縮放到 target（x 寬, y 最大高, z 深）以內，底部貼地、水平置中
static func fit(node: Node3D, target: Vector3) -> void:
	var box_all := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var xf := _rel_xform(m, node)
		var bb: AABB = xf * m.get_aabb()
		box_all = bb if first else box_all.merge(bb)
		first = false
	if first or box_all.size.length() < 0.0001:
		return
	var k := minf(target.x / maxf(box_all.size.x, 0.001), target.z / maxf(box_all.size.z, 0.001))
	k = minf(k, target.y * 1.4 / maxf(box_all.size.y, 0.001))
	node.scale = Vector3.ONE * k
	var c := box_all.get_center()
	node.position = Vector3(-c.x * k, -box_all.position.y * k, -c.z * k)


static func _rel_xform(n: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


static func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	s.radial_segments = 24
	s.rings = 12
	return s


static func cyl(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 24
	return c


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


# ---------------- 家具 ----------------
## 回傳的 Node3D 原點 = 佔地範圍的中心、地面高度
static func furniture(type: String) -> Node3D:
	var d := WorldModel.def_of(type)
	if d.get("kind", "") == "yard":
		return RoomView.yard_node(type, 1.0)
	var root := Node3D.new()
	root.name = type
	if d.has("model") and ResourceLoader.exists(d.model):
		var inst := glb(d.model, Color(d.get("model_tint", "#ffffff")))
		root.add_child(inst)
		var sz0: Array = d.size
		# 自動縮放到佔地範圍（留一點邊），底部貼地、置中
		fit(inst, Vector3(float(sz0[0]) * d.get("model_fill", 0.9), float(d.get("height", 1.0)), float(sz0[1]) * d.get("model_fill", 0.9)))
		inst.rotation_degrees.y += float(d.get("model_yaw", 0))
		return root
	var c := Color(d.get("color", "#cccccc"))
	var a := Color(d.get("accent", "#ffffff"))
	var sz: Array = d.size
	var w := float(sz[0])
	var dp := float(sz[1])
	match d.get("builder", "crate"):
		"chair":
			part(root, box(0.62, 0.1, 0.6), c, Vector3(0, 0.45, 0))
			part(root, box(0.62, 0.55, 0.1), c, Vector3(0, 0.75, -0.26))
			part(root, box(0.5, 0.06, 0.48), a, Vector3(0, 0.52, 0.02))  # 坐墊
			for x in [-0.25, 0.25]:
				for z in [-0.24, 0.24]:
					part(root, cyl(0.045, 0.05, 0.42), c.darkened(0.15), Vector3(x, 0.21, z))
		"table":
			part(root, box(w * 0.94, 0.1, dp * 0.86), c, Vector3(0, 0.72, 0))
			part(root, box(w * 0.86, 0.04, dp * 0.78), a, Vector3(0, 0.78, 0), Vector3.ONE, Vector3.ZERO, false)
			for x in [-w * 0.4, w * 0.4]:
				for z in [-dp * 0.34, dp * 0.34]:
					part(root, cyl(0.05, 0.06, 0.68), c.darkened(0.15), Vector3(x, 0.34, z))
		"round_table":
			part(root, cyl(0.42, 0.42, 0.08), c, Vector3(0, 0.58, 0))
			part(root, cyl(0.08, 0.12, 0.56), c.darkened(0.2), Vector3(0, 0.28, 0))
			part(root, cyl(0.26, 0.3, 0.05), a, Vector3(0, 0.03, 0))
		"bed":
			part(root, box(0.9, 0.3, 1.9), c.darkened(0.25), Vector3(0, 0.2, 0))
			part(root, box(0.86, 0.14, 1.5), Color("fff7ee"), Vector3(0, 0.42, 0.18))
			part(root, box(0.88, 0.16, 1.1), c, Vector3(0, 0.46, 0.36))  # 被子
			part(root, box(0.6, 0.14, 0.32), Color("ffffff"), Vector3(0, 0.5, -0.62))  # 枕頭
			part(root, sphere(0.5), c, Vector3(0, 0.55, -0.95), Vector3(1.0, 0.75, 0.25))  # 蘑菇床頭
			for p in [Vector3(-0.2, 0.75, -0.88), Vector3(0.18, 0.66, -0.86)]:
				part(root, sphere(0.07), Color("fff7ee"), p, Vector3(1, 1, 0.4), Vector3.ZERO, false)
		"shelf":
			part(root, box(0.86, 1.56, 0.42), c, Vector3(0, 0.78, -0.18))
			for y in [0.4, 0.85, 1.3]:
				part(root, box(0.76, 0.05, 0.36), c.lightened(0.2), Vector3(0, y - 0.18, -0.14), Vector3.ONE, Vector3.ZERO, false)
				var colors := [Color("f28b82"), Color("7fb7a4"), Color("f6c85f"), Color("9fd3e6")]
				for i in range(4):
					part(root, box(0.12, 0.3, 0.26), colors[(i + int(y * 10)) % 4], Vector3(-0.27 + i * 0.17, y - 0.01, -0.12), Vector3.ONE, Vector3(0, 0, 4 if i == 3 else 0), false)
			part(root, sphere(0.2), Color("c98d5b"), Vector3(0, 1.62, -0.18), Vector3(1.6, 0.5, 0.9))  # 橡實帽
		"plant":
			part(root, cyl(0.24, 0.17, 0.34), c, Vector3(0, 0.17, 0))
			part(root, cyl(0.26, 0.26, 0.06), c.lightened(0.15), Vector3(0, 0.34, 0))
			part(root, sphere(0.22), a, Vector3(0, 0.52, 0))
			part(root, sphere(0.15), a.lightened(0.1), Vector3(0.12, 0.62, 0.05))
			part(root, sphere(0.06), Color("f28b82"), Vector3(-0.05, 0.72, 0.12), Vector3.ONE, Vector3.ZERO, false)
		"umbrella":
			part(root, cyl(0.24, 0.2, 0.55), c, Vector3(0, 0.28, 0))
			for x in [-0.1, 0.1]:
				part(root, sphere(0.08), Color("ffffff"), Vector3(x, 0.58, 0.14))
				part(root, sphere(0.04), INK, Vector3(x, 0.6, 0.2), Vector3.ONE, Vector3.ZERO, false)
			part(root, cyl(0.025, 0.025, 0.7), a.darkened(0.3), Vector3(0.06, 0.75, -0.05), Vector3.ONE, Vector3(0, 0, -6))
			part(root, sphere(0.16), a, Vector3(0.1, 1.05, -0.05), Vector3(1, 1.6, 1))
			part(root, cyl(0.025, 0.025, 0.6), Color("f28b82"), Vector3(-0.08, 0.7, -0.02), Vector3.ONE, Vector3(0, 0, 8))
			part(root, sphere(0.14), Color("f28b82"), Vector3(-0.15, 0.98, -0.02), Vector3(1, 1.6, 1))
		"mailbox":
			# 森林信箱：木柱＋圓頂信箱，門朝前（+z），右邊有紅色小旗，門縫露出一封信
			part(root, cyl(0.22, 0.26, 0.08), a.darkened(0.15), Vector3(0, 0.04, 0))  # 底座
			part(root, box(0.12, 0.72, 0.12), a, Vector3(0, 0.44, 0))  # 木柱
			part(root, box(0.42, 0.26, 0.6), c, Vector3(0, 0.93, 0))  # 信箱身體
			part(root, cyl(0.21, 0.21, 0.6), c, Vector3(0, 1.06, 0), Vector3.ONE, Vector3(90, 0, 0))  # 圓頂
			part(root, cyl(0.2, 0.2, 0.02), c.lightened(0.2), Vector3(0, 1.0, 0.305), Vector3(1, 1, 1), Vector3(90, 0, 0), false)  # 門
			part(root, box(0.4, 0.13, 0.02), c.lightened(0.2), Vector3(0, 0.88, 0.305), Vector3.ONE, Vector3.ZERO, false)
			part(root, sphere(0.03), Color("f6c85f"), Vector3(0, 0.98, 0.33), Vector3.ONE, Vector3.ZERO, false)  # 門把
			part(root, box(0.26, 0.02, 0.14), Color("fff7ee"), Vector3(0.02, 1.16, 0.3), Vector3.ONE, Vector3(-20, 0, 6))  # 露出的信
			# 紅旗：有沒讀的信就舉起來（main 會轉 Flag 的 rotation）
			var flag := Node3D.new()
			flag.name = "Flag"
			flag.position = Vector3(0.24, 0.94, 0.12)
			root.add_child(flag)
			part(flag, box(0.03, 0.34, 0.03), INK, Vector3(0, 0.16, 0), Vector3.ONE, Vector3.ZERO, false)  # 旗桿
			part(flag, box(0.02, 0.12, 0.16), Color("e5534b"), Vector3(0.005, 0.27, 0.08))  # 紅旗
			part(root, sphere(0.06), Color("7cc47a"), Vector3(-0.1, 1.27, -0.12), Vector3(1.4, 0.5, 1))  # 屋頂上的葉子
		"photo":
			# 合照：木框裡有郵局的紅屋頂和三顆小頭
			part(root, box(0.62, 0.5, 0.05), a, Vector3(0, 1.4, 0.03))
			part(root, box(0.52, 0.4, 0.02), c, Vector3(0, 1.4, 0.06), Vector3.ONE, Vector3.ZERO, false)
			part(root, box(0.52, 0.12, 0.022), Color("b5654f"), Vector3(0, 1.54, 0.065), Vector3.ONE, Vector3.ZERO, false)
			for k in range(3):
				var hc: Color = [Color("c98d5b"), Color("f3dcb8"), Color("8a8f99")][k]
				part(root, sphere(0.06), hc, Vector3(-0.15 + k * 0.15, 1.33, 0.075), Vector3(1, 1, 0.3), Vector3.ZERO, false)
		"jar":
			part(root, cyl(0.09, 0.09, 0.2), c, Vector3(0, 0.1, 0))
			part(root, cyl(0.075, 0.075, 0.05), Color("c8955f"), Vector3(0, 0.225, 0))  # 軟木塞
			for p in [Vector3(-0.03, 0.05, 0.03), Vector3(0.035, 0.05, -0.01), Vector3(0, 0.11, 0.02), Vector3(-0.02, 0.15, -0.03)]:
				part(root, sphere(0.032), a, p, Vector3.ONE, Vector3.ZERO, false)
		"book":
			part(root, box(0.3, 0.07, 0.22), c, Vector3(0, 0.035, 0), Vector3.ONE, Vector3(0, 12, 0))
			part(root, box(0.28, 0.055, 0.2), a, Vector3(0.01, 0.036, 0), Vector3.ONE, Vector3(0, 12, 0), false)
			part(root, sphere(0.035), Color("f2c14e"), Vector3(0.0, 0.072, 0.0), Vector3(1, 0.2, 1), Vector3.ZERO, false)
		"crate":
			part(root, box(0.78, 0.66, 0.78), c, Vector3(0, 0.33, 0))
			for y in [0.12, 0.54]:
				part(root, box(0.8, 0.07, 0.8), a, Vector3(0, y, 0), Vector3.ONE, Vector3.ZERO, false)
			part(root, box(0.08, 0.6, 0.8), a, Vector3(0, 0.33, 0), Vector3.ONE, Vector3(0, 0, 40), false)
		"lamp":
			part(root, cyl(0.2, 0.24, 0.06), a, Vector3(0, 0.03, 0))
			part(root, cyl(0.035, 0.035, 1.1), a.darkened(0.2), Vector3(0, 0.6, 0))
			var star := part(root, sphere(0.22), c, Vector3(0, 1.28, 0), Vector3(1, 1, 0.5), Vector3.ZERO, true, true)
			star.name = "Glow"
			var light := OmniLight3D.new()
			light.light_color = Color("ffe6a8")
			light.light_energy = 0.8
			light.omni_range = 3.0
			light.position = Vector3(0, 1.2, 0)
			root.add_child(light)
		"mini_lamp":
			part(root, cyl(0.04, 0.06, 0.2), a, Vector3(0, 0.1, 0))
			part(root, sphere(0.16), c, Vector3(0, 0.26, 0), Vector3(1, 0.6, 1), Vector3.ZERO, true, true)
			for p in [Vector3(0.07, 0.33, 0.06), Vector3(-0.06, 0.32, -0.05)]:
				part(root, sphere(0.03), Color("ffffff"), p, Vector3.ONE, Vector3.ZERO, false)
			var l2 := OmniLight3D.new()
			l2.light_color = Color("ffd6c8")
			l2.light_energy = 0.5
			l2.omni_range = 2.0
			l2.position = Vector3(0, 0.3, 0)
			root.add_child(l2)
		"cup":
			part(root, cyl(0.08, 0.065, 0.12), c, Vector3(0, 0.06, 0))
			part(root, cyl(0.12, 0.12, 0.015), a, Vector3(0, 0.005, 0))
		"picture":
			part(root, box(0.6, 0.48, 0.05), a, Vector3(0, 1.4, 0.03))
			part(root, box(0.5, 0.38, 0.02), c, Vector3(0, 1.4, 0.06), Vector3.ONE, Vector3.ZERO, false)
			part(root, sphere(0.06), Color("f28b82"), Vector3(0.14, 1.48, 0.075), Vector3(1, 1, 0.2), Vector3.ZERO, false)
		"clock":
			part(root, cyl(0.24, 0.24, 0.06), a, Vector3(0, 1.5, 0.04), Vector3.ONE, Vector3(90, 0, 0))
			part(root, cyl(0.2, 0.2, 0.02), c, Vector3(0, 1.5, 0.08), Vector3.ONE, Vector3(90, 0, 0), false)
			part(root, box(0.02, 0.14, 0.01), INK, Vector3(0, 1.55, 0.095), Vector3.ONE, Vector3.ZERO, false)
			part(root, box(0.1, 0.02, 0.01), INK, Vector3(0.04, 1.5, 0.095), Vector3.ONE, Vector3.ZERO, false)
		"window":
			# 圓窗：木頭圓框、十字窗櫺
			part(root, cyl(0.46, 0.46, 0.08), c, Vector3(0, 1.4, 0.02), Vector3.ONE, Vector3(90, 0, 0))
			part(root, cyl(0.37, 0.37, 0.04), a, Vector3(0, 1.4, 0.05), Vector3.ONE, Vector3(90, 0, 0), false)
			part(root, box(0.05, 0.74, 0.06), c, Vector3(0, 1.4, 0.07), Vector3.ONE, Vector3.ZERO, false)
			part(root, box(0.74, 0.05, 0.06), c, Vector3(0, 1.4, 0.07), Vector3.ONE, Vector3.ZERO, false)
			part(root, box(0.7, 0.07, 0.14), c.darkened(0.1), Vector3(0, 0.92, 0.07))
		"door":
			# 長方形的木板門（剛好塞滿門洞）：直木板、上下兩條橫木、斜撐，裡外兩面都有門把
			part(root, box(0.84, 1.9, 0.07), c, Vector3(0, 0.95, 0.03))
			for gx in [-0.21, 0.0, 0.21]:
				part(root, box(0.014, 1.86, 0.074), c.darkened(0.28), Vector3(gx, 0.95, 0.03), Vector3.ONE, Vector3.ZERO, false)
			var brace_len := sqrt(0.62 * 0.62 + 1.1 * 1.1)
			var brace_deg := rad_to_deg(atan2(0.62, 1.1))
			for side_z in [-1.0, 1.0]:
				var zf: float = 0.03 + side_z * 0.045
				part(root, box(0.78, 0.1, 0.025), c.darkened(0.12), Vector3(0, 0.38, zf), Vector3.ONE, Vector3.ZERO, false)
				part(root, box(0.78, 0.1, 0.025), c.darkened(0.12), Vector3(0, 1.52, zf), Vector3.ONE, Vector3.ZERO, false)
				part(root, box(0.08, brace_len, 0.022), c.darkened(0.12), Vector3(0, 0.95, zf), Vector3.ONE, Vector3(0, 0, brace_deg), false)
				part(root, sphere(0.045), a, Vector3(0.3, 0.98, 0.03 + side_z * 0.075))
				for hy in [0.38, 1.52]:
					part(root, box(0.16, 0.05, 0.03), Color("4a3a30"), Vector3(-0.34, hy, 0.03 + side_z * 0.06), Vector3.ONE, Vector3.ZERO, false)
		"sky_door":
			# 樹幹裡的圓頂小門（往上是螺旋樓梯），現在用兩塊木板釘成 X 封起來
			# 樹幹上的橢圓門洞：裡面塞滿石頭，外面釘了三塊木板（往天空樹頂的樓梯暫時封住）
			var bark := Color("5e3d26")
			part(root, cyl(0.52, 0.52, 0.08), bark, Vector3(0, 1.0, 0.01), Vector3(1, 1, 1.9), Vector3(90, 0, 0))
			part(root, cyl(0.43, 0.43, 0.06), Color("3b3029"), Vector3(0, 1.0, 0.03), Vector3(1, 1, 1.9), Vector3(90, 0, 0), false)
			for st in [[-0.2, 0.4], [0.15, 0.5], [-0.05, 0.75], [0.22, 0.95], [-0.22, 1.05], [0.02, 1.25], [0.2, 1.45], [-0.15, 1.55], [0.05, 1.75], [0.0, 0.28]]:
				part(root, sphere(0.13), Color("8d8679").lerp(Color("6f6a60"), absf(st[0]) * 2.0), Vector3(st[0], st[1], 0.06), Vector3(1.1, 0.85, 0.5))
			for bd in [[0.62, 18.0], [1.05, -12.0], [1.5, 8.0]]:
				part(root, box(0.95, 0.14, 0.04), Color("c9a274"), Vector3(0, bd[0], 0.13), Vector3.ONE, Vector3(0, 0, bd[1]))
				for nx in [-0.38, 0.38]:
					part(root, sphere(0.02), Color("4a3a30"), Vector3(nx, bd[0] + nx * tan(deg_to_rad(bd[1])), 0.16), Vector3.ONE, Vector3.ZERO, false)
			# 小木牌：暫時封閉
			part(root, box(0.6, 0.24, 0.03), Color("efe2c4"), Vector3(0, 2.0, 0.13))
			var lbl := Label3D.new()
			lbl.text = "暫時封閉"
			lbl.font = UIKit.font_bold()
			lbl.font_size = 44
			lbl.pixel_size = 0.0032
			lbl.modulate = Color("8a3b2a")
			lbl.outline_size = 0
			lbl.position = Vector3(0, 2.0, 0.15)
			root.add_child(lbl)
		"sky_crates":
			# 疊在樓梯門前面的木箱
			for cb in [[Vector3(-0.12, 0.25, 0.05), 0.5, 8.0], [Vector3(0.18, 0.22, 0.0), 0.44, -12.0], [Vector3(0.0, 0.72, 0.02), 0.42, 20.0]]:
				var cpos: Vector3 = cb[0]
				var cs: float = cb[1]
				var holder := Node3D.new()
				holder.position = cpos
				holder.rotation_degrees.y = cb[2]
				root.add_child(holder)
				part(holder, box(cs, cs, cs), c, Vector3.ZERO)
				for sy in [-0.3, 0.0, 0.3]:
					part(holder, box(cs + 0.01, 0.05, cs + 0.01), a, Vector3(0, sy * cs, 0), Vector3.ONE, Vector3.ZERO, false)
		# ---------- 野外冒險的東西 ----------
		"rock_big":
			# 長青苔的大石頭（重，只有派派狼搬得動）
			part(root, sphere(0.42), c, Vector3(0, 0.3, 0), Vector3(1.05, 0.78, 0.95))
			part(root, sphere(0.26), c.lightened(0.08), Vector3(0.18, 0.5, 0.1), Vector3(1, 0.7, 0.9), Vector3.ZERO, false)
			part(root, sphere(0.3), a, Vector3(-0.08, 0.56, -0.06), Vector3(1.2, 0.35, 1.0), Vector3.ZERO, false)  # 青苔
		"cave_rock":
			# 洞窟的岩壁
			part(root, box(0.98, 1.5, 0.9), c, Vector3(0, 0.75, 0), Vector3.ONE, Vector3(0, 8, 0))
			part(root, sphere(0.42), c.lightened(0.1), Vector3(0.1, 1.45, 0.05), Vector3(1.1, 0.6, 1.0), Vector3.ZERO, false)
			part(root, cyl(0.0, 0.07, 0.3), a, Vector3(-0.3, 0.3, 0.42), Vector3.ONE, Vector3(20, 0, 15), false, true)  # 小水晶
		"gate":
			# 螢光寶庫的石門：石框＋門板＋發光的密碼刻紋
			for x in [-0.42, 0.42]:
				part(root, box(0.16, 1.9, 0.5), c.darkened(0.15), Vector3(x, 0.95, 0))
			part(root, box(1.0, 0.22, 0.55), c.darkened(0.15), Vector3(0, 1.95, 0))
			part(root, box(0.68, 1.8, 0.2), c, Vector3(0, 0.9, 0))
			for k in range(5):
				part(root, sphere(0.05), a, Vector3(-0.2 + k * 0.1, 1.2 + (k % 2) * 0.12, 0.11), Vector3(1, 1, 0.3), Vector3.ZERO, false, true)
			part(root, cyl(0.16, 0.16, 0.03), a, Vector3(0, 0.75, 0.11), Vector3.ONE, Vector3(90, 0, 0), false, true)
		"glow_stone":
			# 爺爺的發光石：石台上的一顆會發光的石頭（星星落地燈的燈罩原件）
			part(root, cyl(0.24, 0.3, 0.42), Color("8a8f9c"), Vector3(0, 0.21, 0))
			part(root, sphere(0.17), c, Vector3(0, 0.6, 0), Vector3(1, 1.15, 1), Vector3.ZERO, false, true)
			part(root, sphere(0.07), Color("ffffff"), Vector3(0.06, 0.68, 0.1), Vector3.ONE, Vector3.ZERO, false, true)
		"lavender":
			# 一叢薰衣草
			part(root, sphere(0.34), Color("7f9a5a"), Vector3(0, 0.2, 0), Vector3(1.1, 0.6, 1.1))
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for k in range(9):
				var ang := TAU * k / 9.0
				var rr := 0.12 + rng.randf() * 0.16
				var px := Vector3(cos(ang) * rr, 0.0, sin(ang) * rr)
				part(root, cyl(0.012, 0.012, 0.42), Color("6f8a4a"), px + Vector3(0, 0.42, 0), Vector3.ONE, Vector3.ZERO, false)
				part(root, capsule(0.045, 0.22), c.lightened(rng.randf() * 0.15), px + Vector3(0, 0.68, 0), Vector3.ONE, Vector3.ZERO, false)
		"basket":
			# 草藥籃
			part(root, cyl(0.26, 0.2, 0.26), c, Vector3(0, 0.13, 0))
			part(root, cyl(0.27, 0.27, 0.04), a, Vector3(0, 0.26, 0), Vector3.ONE, Vector3.ZERO, false)
			part(root, Models.torus_mesh(0.2, 0.025), c.darkened(0.2), Vector3(0, 0.3, 0), Vector3.ONE, Vector3(90, 0, 0))
		"picnic_mat":
			# 野餐墊（紅白格子）
			for x in range(4):
				for z in range(4):
					part(root, box(0.2, 0.02, 0.2), (c if (x + z) % 2 == 0 else a), Vector3(-0.3 + x * 0.2, 0.01, -0.3 + z * 0.2), Vector3.ONE, Vector3.ZERO, false)
		_:
			part(root, box(0.8 * w, float(d.height), 0.8 * dp), c, Vector3(0, float(d.height) / 2, 0))
	if d.get("old", false):
		tint_old(root)
	return root


## 舊舊的、蒙上灰塵的爺爺的東西：顏色淡一點、偏灰
static func tint_old(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var m2: StandardMaterial3D = m.duplicate()
			m2.albedo_color = m2.albedo_color.lerp(Color("b8ab98"), 0.45)
			(mi as MeshInstance3D).material_override = m2


static func torus_mesh(r: float, thick: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	return t


# ---------------- 角色 ----------------
## 派派鼠：子節點 Body / Head / ArmL / ArmR / FootL / FootR 讓動畫程式可以擺動
static func gopher() -> Node3D:
	if ResourceLoader.exists("res://models/gopher/gopher_rigged.glb"):
		return Anthro.from_glb("res://models/gopher/gopher_rigged.glb", "Gopher", 1.0)
	if ResourceLoader.exists("res://models/gopher_anthro.glb"):
		return Anthro.from_glb("res://models/gopher_anthro.glb", "Gopher", 1.0)
	if ResourceLoader.exists("res://models/kenney/mini/character-male-a.glb") and ResourceLoader.exists("res://models/cozy/Otter.glb"):
		return Anthro.build("gopher", "Gopher", 1.0)
	if ResourceLoader.exists("res://models/cozy/Otter.glb") and ResourceLoader.exists("res://models/cozy/groundhog_albedo.png"):
		return CozyCharacter.build("gopher", "Gopher")
	if ResourceLoader.exists("res://models/gopher.glb"):
		return character_glb("res://models/gopher.glb", "Gopher", 0.95)
	var root := Node3D.new()
	root.name = "Gopher"
	var fur := Color("b98552")
	var light_fur := Color("f3dcb8")
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	part(body, sphere(0.27), fur, Vector3(0, 0.33, 0), Vector3(1, 1.15, 0.95))
	part(body, sphere(0.2), light_fur, Vector3(0, 0.3, 0.1), Vector3(1, 1.15, 0.7), Vector3.ZERO, false)
	part(body, sphere(0.07), fur.darkened(0.1), Vector3(0, 0.15, -0.25))  # 尾巴
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.66, 0.02)
	body.add_child(head)
	part(head, sphere(0.24), fur, Vector3.ZERO, Vector3(1.08, 0.95, 1.0))
	part(head, sphere(0.14), light_fur, Vector3(0, -0.06, 0.15), Vector3(1.1, 0.8, 0.7), Vector3.ZERO, false)
	for s in [-1, 1]:
		part(head, sphere(0.07), fur, Vector3(0.19 * s, 0.16, -0.02), Vector3(1, 0.8, 0.6))  # 耳朵
		part(head, sphere(0.04), Color("f2a7a0"), Vector3(0.19 * s, 0.16, 0.02), Vector3(1, 0.8, 0.4), Vector3.ZERO, false)
		part(head, sphere(0.04), Color("2b1d14"), Vector3(0.09 * s, 0.04, 0.2), Vector3(1, 1.15, 0.7), Vector3.ZERO, false)  # 眼睛
		part(head, sphere(0.013), Color("ffffff"), Vector3(0.09 * s + 0.012, 0.06, 0.232), Vector3.ONE, Vector3.ZERO, false)
		part(head, sphere(0.045), Color("f4a6a6"), Vector3(0.15 * s, -0.04, 0.16), Vector3(1, 0.6, 0.4), Vector3.ZERO, false)  # 腮紅
	part(head, sphere(0.03), Color("7a4a3a"), Vector3(0, -0.02, 0.245), Vector3(1.2, 0.9, 0.8), Vector3.ZERO, false)  # 鼻子
	part(head, box(0.045, 0.06, 0.02), Color("ffffff"), Vector3(-0.024, -0.1, 0.225))  # 門牙
	part(head, box(0.045, 0.06, 0.02), Color("ffffff"), Vector3(0.024, -0.1, 0.225))
	for side in ["L", "R"]:
		var s2 := -1 if side == "L" else 1
		var arm := Node3D.new()
		arm.name = "Arm" + side
		arm.position = Vector3(0.22 * s2, 0.45, 0.06)
		body.add_child(arm)
		part(arm, capsule(0.055, 0.2), fur, Vector3(0, -0.07, 0.02), Vector3.ONE, Vector3(20, 0, 0))
		var foot := Node3D.new()
		foot.name = "Foot" + side
		foot.position = Vector3(0.11 * s2, 0.05, 0.05)
		root.add_child(foot)
		part(foot, sphere(0.075), fur.darkened(0.08), Vector3.ZERO, Vector3(1, 0.6, 1.3))
	return root


## 把 Thrixel 多部件角色包成動畫程式要的結構：Body（整個模型）底下找出 Head / ArmL / ArmR / FootL / FootR。
## 部件名稱用關鍵字比對（head、arm+left…），找不到的部件就不做那個動作。
const PART_KEYS := {
	"Head": [["head"]],
	"ArmL": [["arm", "left"], ["arm", "_l"], ["arm", ".l"], ["hand", "left"]],
	"ArmR": [["arm", "right"], ["arm", "_r"], ["arm", ".r"], ["hand", "right"]],
	"FootL": [["foot", "left"], ["leg", "left"], ["foot", "_l"], ["leg", "_l"]],
	"FootR": [["foot", "right"], ["leg", "right"], ["foot", "_r"], ["leg", "_r"]],
}


static func character_glb(path: String, name: String, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var inst := glb(path)
	body.add_child(inst)
	fit(inst, Vector3(height, height, height))
	var taken := {}
	for role in PART_KEYS:
		for n in inst.find_children("*", "Node3D", true, false):
			if taken.has(n):
				continue
			var lname := String(n.name).to_lower()
			var hit := false
			for keys in PART_KEYS[role]:
				var all := true
				for k in keys:
					if not lname.contains(k):
						all = false
				if all:
					hit = true
					break
			if hit:
				taken[n] = true
				n.name = role
				break
	return root


## 派派森林的角色（混元 3D 生成＋rig_hy3d.py 上骨架）。who = gopher / rabbit / wolf
static func character(who: String) -> Node3D:
	match who:
		"gopher":
			return gopher()
		"rabbit":
			return village_chief()
		"tanuki":
			return Anthro.build("tanuki", "Tanuki", 1.1)
		"turtle":
			if ResourceLoader.exists("res://models/turtle/turtle_rigged.glb"):
				# 慢慢館長：老陸龜，背著大龜殼（fix_turtle.py 修過再上骨架）；走路很慢、很小心
				var tm := Anthro.from_glb("res://models/turtle/turtle_rigged.glb", "Turtle", 1.2)
				tm.set_meta("speed", 0.5)
				return tm
			return Anthro.build("turtle", "Turtle", 1.05)
		"crow":
			return Anthro.build("crow", "Crow", 1.05)
		"calico":
			return Anthro.build("calico", "Calico", 1.0)
		"blackcat":
			return Anthro.build("blackcat", "BlackCat", 0.82)
		"wolf":
			if ResourceLoader.exists("res://models/wolf/wolf_rigged.glb"):
				return Anthro.from_glb("res://models/wolf/wolf_rigged.glb", "Wolf", 1.2)  # 高度含耳朵
	return village_chief()


static func village_chief() -> Node3D:
	# 派派兔學姊：高度含耳朵
	if ResourceLoader.exists("res://models/rabbit/rabbit_rigged.glb"):
		return Anthro.from_glb("res://models/rabbit/rabbit_rigged.glb", "Rabbit", 1.3)
	if ResourceLoader.exists("res://models/village_chief.glb"):
		return character_glb("res://models/village_chief.glb", "VillageChief", 1.05)
	var root := Node3D.new()
	root.name = "VillageChief"
	var fur := Color("e0a85a")
	var cream := Color("fff1d6")
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	part(body, sphere(0.28), fur, Vector3(0, 0.36, 0), Vector3(1, 1.2, 0.95))
	part(body, sphere(0.2), cream, Vector3(0, 0.32, 0.11), Vector3(1, 1.2, 0.7), Vector3.ZERO, false)
	part(body, box(0.5, 0.08, 0.06), Color("d95f5f"), Vector3(0, 0.52, 0.18), Vector3.ONE, Vector3(0, 0, -25))  # 綬帶
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.74, 0.02)
	body.add_child(head)
	part(head, sphere(0.26), fur, Vector3.ZERO, Vector3(1.05, 0.95, 1))
	part(head, sphere(0.13), cream, Vector3(0, -0.07, 0.17), Vector3(1.1, 0.8, 0.8), Vector3.ZERO, false)
	part(head, sphere(0.045), Color("2b1d14"), Vector3(0, -0.01, 0.28), Vector3.ONE, Vector3.ZERO, false)
	for s in [-1, 1]:
		part(head, sphere(0.1), fur.darkened(0.2), Vector3(0.24 * s, 0.0, 0), Vector3(0.5, 1.4, 0.8), Vector3(0, 0, 15 * s))  # 垂耳
		part(head, sphere(0.04), Color("2b1d14"), Vector3(0.1 * s, 0.07, 0.22), Vector3(1, 1.15, 0.7), Vector3.ZERO, false)
		part(head, sphere(0.013), Color("ffffff"), Vector3(0.1 * s + 0.012, 0.09, 0.252), Vector3.ONE, Vector3.ZERO, false)
		part(head, sphere(0.045), Color("f4a6a6"), Vector3(0.16 * s, -0.05, 0.17), Vector3(1, 0.6, 0.4), Vector3.ZERO, false)
	# 小帽子
	part(head, cyl(0.12, 0.13, 0.14), Color("5a7d9a"), Vector3(0, 0.27, -0.02))
	part(head, cyl(0.2, 0.2, 0.02), Color("5a7d9a"), Vector3(0, 0.2, -0.02))
	part(head, cyl(0.125, 0.135, 0.03), Color("f6c85f"), Vector3(0, 0.23, -0.02), Vector3.ONE, Vector3.ZERO, false)
	for s in [-1, 1]:
		var foot := Node3D.new()
		foot.name = "Foot" + ("L" if s < 0 else "R")
		foot.position = Vector3(0.12 * s, 0.05, 0.05)
		root.add_child(foot)
		part(foot, sphere(0.08), fur.darkened(0.1), Vector3.ZERO, Vector3(1, 0.6, 1.3))
	return root
