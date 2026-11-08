class_name FieldView
extends RefCounted
## 派森地下城（野外冒險）的場景：派派森林・溪畔、薰衣草原・花田、螢光寶庫・入口。
## 任務格子是一格一格的「梅花排列」地磚（兩種顏色交錯），方便看座標寫程式；格子外面是各地的風景（只是裝飾）。
## 任務房間的 room.scene 寫 "forest" / "lavender" / "vault" 就會用這裡蓋場景。

const KINDS := ["forest", "lavender", "vault"]
const PLACE := {"forest": "派派森林", "lavender": "薰衣草原", "vault": "螢光寶庫"}
const NATURE := "res://models/kenney/nature/%s.glb"

## 地磚兩種顏色、邊框、外面的地面
const STYLE := {
	"forest": {"a": Color("b4cf86"), "b": Color("9fbf72"), "edge": Color("8a6a4a"), "ground": Color("88aa66")},
	"lavender": {"a": Color("cfe0a4"), "b": Color("bcd28f"), "edge": Color("9a7a5a"), "ground": Color("a4c27e")},
	"vault": {"a": Color("6c7892"), "b": Color("5a6680"), "edge": Color("3b4256"), "ground": Color("2f3546")},
}


static func is_field(scene: String) -> bool:
	return scene in KINDS


# ---------------- 地板：梅花排列的地磚 ----------------
static func build_floor(rv: RoomView, w: WorldModel, kind: String) -> void:
	var st: Dictionary = STYLE[kind]
	var root := Node3D.new()
	root.name = "Floor"
	rv.add_child(root)
	# 格子下面的台座（讓格子區域一眼看得出來）
	var slab := MeshInstance3D.new()
	slab.mesh = Models.box(w.width + 0.36, 0.16, w.depth + 0.36)
	slab.material_override = Models.mat(st.edge, false)
	slab.position = Vector3(w.width / 2.0, -0.1, w.depth / 2.0)
	root.add_child(slab)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tile := Models.box(0.94, 0.08, 0.94)
	for x in range(w.width):
		for z in range(w.depth):
			var c: Color = st.a if (x + z) % 2 == 0 else st.b
			c = c.lightened(rng.randf_range(-0.03, 0.04))
			var mi := MeshInstance3D.new()
			mi.mesh = tile
			mi.material_override = Models.mat(c, false)
			mi.position = Vector3(x + 0.5, -0.04, z + 0.5)
			root.add_child(mi)
	# 不擋路的裝飾（野餐墊、草藥籃）
	for dc in w.decor:
		var n := Models.furniture(dc.type)
		n.position = Vector3(float(dc.cell[0]) + 0.5, 0.0, float(dc.cell[1]) + 0.5)
		root.add_child(n)
	# 外面的地面
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	g.mesh = pm
	g.material_override = Models.mat(st.ground, false)
	g.position = Vector3(w.width / 2.0, -0.17, w.depth / 2.0)
	root.add_child(g)


# ---------------- 格子外面的風景 ----------------
static func build_surround(rv: RoomView, w: WorldModel, kind: String) -> void:
	var holder := Node3D.new()
	holder.name = "Field_" + kind
	rv.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	match kind:
		"forest":
			rv._build_backdrop(holder)
			_forest(holder, w, rng)
		"lavender":
			rv._build_backdrop(holder)
			_lavender(holder, w, rng)
		"vault":
			_vault(holder, w, rng)


## 格子外圍一圈的隨機位置（離格子 m0～m1 公尺）
static func _ring_points(w: WorldModel, rng: RandomNumberGenerator, n: int, m0: float, m1: float) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < n * 30:
		tries += 1
		var p := Vector3(rng.randf_range(-m1, w.width + m1), 0, rng.randf_range(-m1, w.depth + m1))
		var dx := maxf(maxf(-p.x, p.x - w.width), 0.0)
		var dz := maxf(maxf(-p.z, p.z - w.depth), 0.0)
		var d := maxf(dx, dz)
		if d < m0:
			continue
		# 鏡頭在南邊：南側不要放高的東西擋住格子
		if p.z > w.depth + 0.3 and p.z < w.depth + 4.0:
			continue
		out.append(p)
	return out


static func _nature(parent: Node3D, model: String, pos: Vector3, size: float, yaw: float) -> void:
	var path: String = NATURE % model
	if not ResourceLoader.exists(path):
		return
	var n := Models.glb(path)
	Models.fit(n, Vector3(size, size * 1.6, size))
	n.position = pos + Vector3(0, -0.13, 0)
	n.rotation.y = yaw
	parent.add_child(n)


static func _multi(parent: Node3D, mesh: Mesh, color: Color, xforms: Array, glow: bool = false) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Models.mat(color, false, glow)
	parent.add_child(mmi)


static func _forest(h: Node3D, w: WorldModel, rng: RandomNumberGenerator) -> void:
	# 北邊的小溪（三個老朋友野餐的地方）＋踏腳石
	var water := MeshInstance3D.new()
	water.mesh = Models.box(w.width + 30, 0.04, 1.6)
	water.material_override = Models.mat(Color("8fc7e0"), false)
	water.position = Vector3(w.width / 2.0, -0.13, -1.7)
	h.add_child(water)
	for k in range(7):
		Models.part(h, Models.sphere(0.22), Color("a7a596"), Vector3(w.width / 2.0 - 3 + k * 1.0 + rng.randf_range(-0.2, 0.2), -0.1, -1.7 + rng.randf_range(-0.4, 0.4)), Vector3(1.2, 0.4, 1))
	for k in range(4):
		Models.part(h, Models.box(w.width + 30, 0.06, 0.3), Color("cfe8f2"), Vector3(w.width / 2.0, -0.1, -2.3 + k * 0.4), Vector3.ONE, Vector3.ZERO, false)
	# 樹、蘑菇、木頭、草叢
	var trees := ["tree_oak", "tree_fat", "tree_default", "tree_detailed"]
	for p in _ring_points(w, rng, 26, 1.4, 7.0):
		if p.z < -1.0 and p.z > -2.6:
			continue
		_nature(h, trees[rng.randi() % trees.size()], p, rng.randf_range(1.8, 2.8), rng.randf() * TAU)
	for p in _ring_points(w, rng, 18, 0.4, 2.5):
		if p.z < -0.9 and p.z > -2.6:
			continue
		var m: String = ["mushroom_redGroup", "mushroom_tanGroup", "plant_bush", "rock_smallA", "flower_redA", "flower_yellowA"][rng.randi() % 6]
		_nature(h, m, p, rng.randf_range(0.4, 0.8), rng.randf() * TAU)
	_nature(h, "log", Vector3(w.width + 1.2, 0, w.depth * 0.6), 1.2, 0.4)
	_nature(h, "stump_round", Vector3(-1.1, 0, w.depth * 0.3), 0.7, 0.0)
	# 刻著三個記號的老樹樁（三個老朋友的痕跡）
	var mark := Label3D.new()
	mark.text = "△ ○ ☆"
	mark.font_size = 64
	mark.pixel_size = 0.004
	mark.modulate = Color("5a3d2b")
	mark.position = Vector3(-1.1, 0.55, w.depth * 0.3 + 0.36)
	h.add_child(mark)


static func _lavender(h: Node3D, w: WorldModel, rng: RandomNumberGenerator) -> void:
	# 一排一排的薰衣草（用 MultiMesh，數量多也不慢）
	var stems: Array = []
	var buds: Array = []
	var bushes: Array = []
	for row in range(-7, w.depth + 8):
		var z := float(row) * 1.1 + 0.4
		for i in range(-10, w.width + 11):
			var x := float(i) * 0.7 + rng.randf_range(-0.15, 0.15)
			var inside := x > -0.8 and x < w.width + 0.8 and z > -0.8 and z < w.depth + 0.8
			if inside or (z > w.depth + 0.8 and z < w.depth + 3.5):
				continue
			if x > w.width + 1.5 and x < w.width + 5.5 and z > 0.0 and z < 4.5:
				continue  # 池塘
			bushes.append(Transform3D(Basis().scaled(Vector3(0.36, 0.2, 0.36)), Vector3(x, 0.02, z)))
			for k in range(5):
				var off := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.16, 0.16))
				buds.append(Transform3D(Basis().scaled(Vector3(0.05, 0.13, 0.05)), Vector3(x, 0.55 + rng.randf() * 0.1, z) + off))
				stems.append(Transform3D(Basis().scaled(Vector3(0.012, 0.22, 0.012)), Vector3(x, 0.3, z) + off))
	_multi(h, SphereMesh.new(), Color("7f9a5a"), bushes)
	_multi(h, CylinderMesh.new(), Color("6f8a4a"), stems)
	_multi(h, SphereMesh.new(), Color("a98bc9"), buds)
	# 東邊的小池塘（爺爺的青蛙傘架就在這附近）
	var pond := MeshInstance3D.new()
	pond.mesh = Models.cyl(1.9, 1.9, 0.04)
	pond.material_override = Models.mat(Color("8fc7e0"), false)
	pond.position = Vector3(w.width + 3.4, -0.13, 2.2)
	pond.scale = Vector3(1, 1, 0.75)
	h.add_child(pond)
	for k in range(5):
		Models.part(h, Models.cyl(0.2, 0.2, 0.02), Color("7cc47a"), Vector3(w.width + 2.6 + rng.randf() * 1.6, -0.1, 1.4 + rng.randf() * 1.6), Vector3.ONE, Vector3.ZERO, false)
	# 小木屋（下雨時躲雨的地方）
	Models.part(h, Models.box(1.8, 1.3, 1.5), Color("c8955f"), Vector3(-2.6, 0.5, 1.2))
	Models.part(h, Models.box(2.1, 0.16, 1.9), Color("b5544a"), Vector3(-2.6, 1.25, 1.2), Vector3.ONE, Vector3(0, 0, 8))
	for p in _ring_points(w, rng, 6, 5.0, 9.0):
		_nature(h, "tree_small", p, 1.8, rng.randf() * TAU)


static func _vault(h: Node3D, w: WorldModel, rng: RandomNumberGenerator) -> void:
	# 洞窟的岩壁一圈＋鐘乳石；螢火蟲把黑暗照得像星空
	var rocks: Array = []
	for p in _ring_points(w, rng, 70, 0.6, 6.0):
		var s := rng.randf_range(0.5, 1.4)
		rocks.append(Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(1.0, 2.2), s)), p + Vector3(0, s * 0.4, 0)))
	_multi(h, SphereMesh.new(), Color("454d63"), rocks)
	var spikes: Array = []
	for p in _ring_points(w, rng, 30, 0.5, 4.0):
		var s := rng.randf_range(0.15, 0.3)
		spikes.append(Transform3D(Basis().scaled(Vector3(s, s * 4.0, s)), p + Vector3(0, s * 1.8, 0)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	_multi(h, cone, Color("525b74"), spikes)
	# 發光的水晶
	for p in _ring_points(w, rng, 14, 0.3, 2.5):
		var c: Color = [Color("7fe0e8"), Color("b9a6f0"), Color("9ff0c0")][rng.randi() % 3]
		for k in range(3):
			Models.part(h, Models.cyl(0.0, 0.08, 0.45), c, p + Vector3(k * 0.12 - 0.12, 0.15, rng.randf() * 0.1), Vector3.ONE, Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-25, 25)), false, true)
	# 螢火蟲
	var flies: Array = []
	for i in range(140):
		var p := Vector3(rng.randf_range(-6, w.width + 6), rng.randf_range(0.4, 3.0), rng.randf_range(-6, w.depth + 3))
		flies.append(Transform3D(Basis().scaled(Vector3.ONE * 0.04), p))
	_multi(h, SphereMesh.new(), Color("fff1a0"), flies, true)
	# 舊書架（寶庫裡也收著書）
	for x in [-1.6, w.width + 1.2]:
		var shelf := Models.furniture("bookshelf")
		shelf.position = Vector3(x, 0, 0.8)
		h.add_child(shelf)
	var light := OmniLight3D.new()
	light.light_color = Color("9ff0e0")
	light.light_energy = 1.2
	light.omni_range = 9.0
	light.position = Vector3(w.width / 2.0, 2.4, w.depth / 2.0 - 1.0)
	h.add_child(light)
