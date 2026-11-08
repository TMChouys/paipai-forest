class_name LibraryView
extends Node3D
## 派森圖書館（第三版，2026-11-08 重新設計）：和派派鼠的家一樣大小的場景，只是建築物比樹屋寬敞。
## 家具、花草都和家裡同一套、同樣大小（Models.furniture）；只有石柱、石牆、雕像這些建築材料比較大。
## 座標（公尺，和家裡一樣 1 格 = 1 公尺）：館內 x -12..12、z -6..6，大門在南牆中間，館長室（平台）在正中間；
## 2026-11-08 東西各加寬 4 公尺：西邊 x -12..-8 是教室（講台、黑板、課桌椅，派派兔帶大家來上課，館長站在講台上）；
## 東邊 x 8..12 是書庫：往樓上的大樓梯、更多書櫃。
## 門外是小小的前庭（z 6..10.8），矮石牆圍起來，南邊的鐵門回樹屋。
## 派派鼠走進館內時，靠鏡頭那一側的牆會藏起來（和家裡一樣），沒有天花板、沒有吊燈、館內沒有獨立的柱子，鏡頭不會被擋住。

const X0 := -8.0                      # 舊的西牆位置（閱讀區、櫃台書櫃以它為準）
const XW := -12.0                     # 加寬以後真正的西牆（教室在 XW..X0）
const X1 := 8.0                       # 舊的東牆位置（書櫃區以它為準）
const XE := 12.0                      # 加寬以後真正的東牆
const ZN := -6.0
const ZS := 6.0
const WALL_H := 3.2
const WALL_T := 0.35
const DOOR_HALF := 0.9
const PLAZA_Z := 10.8
const PLAT_H := 0.45                  # 館長平台：三階
const PLAT_Z := -3.2                  # 平台前緣
const PLAT_X := 3.2
const STEP_HALF := 1.0
const GRID_ORIGIN := Vector3(-3, 0, -2)   # 任務用的格子區（大廳中間）
const GRID_SIZE := Vector2i(6, 4)

const STONE := Color("ddd3bf")
const STONE_DARK := Color("bcae94")
const STONE_LIGHT := Color("efe7d6")
const WOOD := Color("8a5a3a")
const WOOD_LIGHT := Color("b07a4f")
const GOLD := Color("d9ae52")
const RED := Color("b0483f")
const GRASS := Color("9cc46f")
const LEAF := [Color("7fae5a"), Color("8fbd62"), Color("6f9e4f")]
const GLASS := Color("bfe0f0")
const BOOKS := [Color("b5544a"), Color("4f7a9a"), Color("6f9a5a"), Color("d9a24a"), Color("8a5aa0"), Color("c9b48a")]

const NAMES := {"turtle": "慢慢館長", "rabbit": "派派兔", "gopher": "派派鼠", "calico": "三花奶奶", "blackcat": "黑貓弟弟", "wolf": "派派狼", "crow": "拍拍鳥", "lala": "拉拉老闆", "daya": "大牙師傅"}
const BUBBLE_H := {"turtle": 1.4, "rabbit": 1.6, "gopher": 1.3, "calico": 1.35, "blackcat": 1.15, "wolf": 1.6, "crow": 1.4, "lala": 1.5, "daya": 1.4}
const LINES := {
	"turtle": ["慢慢來，比較快。", "你覺得呢？先猜，再看。", "一個概念一本書，都在右邊的書櫃。", "左邊後面是閱讀教室，可以坐下來慢慢讀。", "樓上還在整理，以後再帶你上去。"],
	"rabbit": ["準備好一起認識派派森林的世界了嗎？", "我們一起去上課吧！", "錯了沒關係，錯了才知道哪裡要注意。", "館長是我的老師，派派森林的故事都是他教我的。"],
	"gopher": ["好寬敞的圖書館！", "書好多喔……"],
	"calico": ["哎呀，真是個好孩子。", "慢慢想，奶奶等你。"],
	"blackcat": ["奶奶不說的，我偷偷告訴你。", "考完試，來找我檢討吧！"],
}

## 點得到的東西：id → {name, pos, text, act}
var hotspots: Dictionary = {}
var npcs: Dictionary = {}
var walls: Dictionary = {}   # "N"/"S"/"E"/"W" → Node3D（派派鼠在館內時，靠鏡頭那面會藏起來）
var inside := false          # 派派鼠在不在館內（走路時會自動更新）
var built := false
var _line_i: Dictionary = {}
var _batches: Dictionary = {}
var _unit_box := BoxMesh.new()
var _unit_prism := PrismMesh.new()
## 點地板讓派派鼠走過去：0.25 公尺一格的找路網格
const CELL := 0.25
const NAV_X0 := -13.0
const NAV_Z0 := -6.5
const NAV_W := 104     # x -13..13
const NAV_H := 72      # z -6.5..11.5
var nav := AStarGrid2D.new()
var _walk_serial := 0
var _walk_tween: Tween


func build() -> void:
	for c in get_children():
		c.queue_free()
	npcs.clear()
	hotspots.clear()
	walls.clear()
	_batches.clear()
	for s in ["N", "S", "E", "W"]:
		walls[s] = _group("Wall" + s)
	_ground()
	_plaza()
	_walls()
	_floor()
	_hall()
	_counter()
	_platform()
	_reading_room()
	_classroom()
	_bookshelves()
	_stairs()
	_flush_batches()
	_build_nav()
	built = true
	_spawn("turtle", Vector3(0, PLAT_H, -4.0), "S")
	_spawn("rabbit", Vector3(-5.0, 0, 1.7), "E")   # 派派兔在借書櫃台後面打工
	_spawn("calico", Vector3(XW + 0.9, 0, 2.2), "E")   # 三花奶奶在教室講台旁邊當考官
	_spawn("blackcat", Vector3(-5.6, 0, -0.7), "S")     # 黑貓弟弟坐在閱讀教室門口，幫忙檢討
	_spawn("gopher", Vector3(0, 0, 9.5), "N")
	set_inside(false)


# ---------------- 小工具 ----------------
func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	add_child(g)
	return g


func _m(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, line: bool = true, glow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Models.mat(color, line, glow)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


## 車床曲面：把輪廓（x＝半徑、y＝高度）繞 y 軸轉一圈，得到圓滑的形狀
static func _lathe(profile: Array, seg: int = 36) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in range(profile.size() - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			for v in [v00, v11, v10, v00, v01, v11]:
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


static func _ball(r: float) -> SphereMesh:
	var b := SphereMesh.new()
	b.radius = r
	b.height = r * 2
	b.radial_segments = 32
	b.rings = 16
	return b


static func _torus(r: float, thick: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	t.rings = 32
	t.ring_segments = 12
	return t


## 從 a 到 b 的手臂／袖子（a 端粗 r_a、b 端粗 r_b）
func _limb(parent: Node3D, a: Vector3, b: Vector3, r_a: float, r_b: float) -> MeshInstance3D:
	var mi := _m(parent, Models.cyl(r_b, r_a, a.distance_to(b)), STONE_LIGHT, (a + b) / 2)
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return mi


## 一個方塊（box 的中心、大小）
func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color, line: bool = true) -> MeshInstance3D:
	return _m(parent, Models.box(size.x, size.y, size.z), color, center, Vector3.ZERO, line)


## 很多小方塊（書背、石磚）合併成 MultiMesh，畫起來很省
func _inst(parent: Node3D, base: Transform3D, center: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, prism: bool = false) -> void:
	var key := "%d|%s" % [parent.get_instance_id(), prism]
	if not _batches.has(key):
		_batches[key] = {"parent": parent, "mesh": _unit_prism if prism else _unit_box, "xf": [], "col": []}
	var b := Basis.from_euler(rot * PI / 180.0) * Basis.from_scale(size)
	_batches[key].xf.append(base * Transform3D(b, center))
	_batches[key].col.append(color)


func _flush_batches() -> void:
	var lit := StandardMaterial3D.new()
	lit.vertex_color_use_as_albedo = true
	lit.roughness = 0.85
	for key in _batches:
		var b: Dictionary = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = b.mesh
		mm.instance_count = b.xf.size()
		for i in b.xf.size():
			mm.set_instance_transform(i, b.xf[i])
			mm.set_instance_color(i, b.col[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = lit
		(b.parent as Node3D).add_child(mmi)
	_batches.clear()


## 和家裡同一套家具（同樣大小）；yaw 0 = 面向南（+z）
func _furn(parent: Node3D, type: String, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var n := Models.furniture(type)
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	parent.add_child(n)
	return n


func _label(parent: Node3D, text: String, pos: Vector3, size: int = 48, color: Color = UIKit.INK, yaw: float = 0.0, px: float = 0.004) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font = UIKit.font_bold()
	lb.font_size = size
	lb.pixel_size = px
	lb.modulate = color
	lb.outline_size = 0
	lb.position = pos
	lb.rotation_degrees.y = yaw
	lb.double_sided = false
	parent.add_child(lb)
	return lb


func _hot(id: String, name_: String, pos: Vector3, text: String, act: String = "say") -> void:
	hotspots[id] = {"name": name_, "pos": pos, "text": text, "act": act}


## 格子圖案的地板材質（一張小圖重複貼，整片地板只有一個網格）
func _checker_mat(a: Color, b: Color, tile: float) -> StandardMaterial3D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, a)
	img.set_pixel(1, 1, a)
	img.set_pixel(1, 0, b)
	img.set_pixel(0, 1, b)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / (tile * 2.0)
	m.roughness = 0.9
	return m


func _plane(parent: Node3D, x0: float, z0: float, x1: float, z1: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) / 2, y, (z0 + z1) / 2)
	parent.add_child(mi)


## 一座書櫃（和家裡一樣大小）：背靠 -z，書背朝 +z
func _tall_shelf(parent: Node3D, pos: Vector3, yaw_deg: float, rng: RandomNumberGenerator) -> void:
	var h := Node3D.new()
	h.position = pos
	h.rotation_degrees.y = yaw_deg
	parent.add_child(h)
	var I := Transform3D.IDENTITY
	_inst(h, I, Vector3(0, 0.8, -0.18), Vector3(0.96, 1.6, 0.06), WOOD)
	for sx: float in [-0.46, 0.46]:
		_inst(h, I, Vector3(sx, 0.8, 0), Vector3(0.05, 1.6, 0.42), WOOD)
	for k in range(5):
		_inst(h, I, Vector3(0, 0.03 + k * 0.39, 0), Vector3(0.96, 0.04, 0.42), WOOD_LIGHT)
	for k in range(4):
		var x := -0.42
		while x < 0.38:
			var bw := rng.randf_range(0.05, 0.09)
			var bh := rng.randf_range(0.22, 0.31)
			_inst(h, I, Vector3(x + bw / 2, 0.05 + k * 0.39 + bh / 2, 0.02), Vector3(bw - 0.008, bh, 0.28), BOOKS[rng.randi() % BOOKS.size()])
			x += bw


# ---------------- 外面：草地、樹、前庭 ----------------
func _ground() -> void:
	var g := _group("Ground")
	var grass := StandardMaterial3D.new()
	grass.albedo_color = GRASS
	grass.roughness = 1.0
	_plane(g, -20, -12, 20, 16, -0.02, grass)
	# 館外幾棵樹（和家裡差不多大）
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for p: Vector2 in [Vector2(-15, -3), Vector2(-15.5, 3.5), Vector2(15, -2.5), Vector2(15.5, 4), Vector2(-15, 9.5),
			Vector2(15, 9.5), Vector2(-5, -8.8), Vector2(3.5, -8.8), Vector2(12, -8.2), Vector2(-12, -8)]:
		var t := Node3D.new()
		t.position = Vector3(p.x, 0, p.y)
		g.add_child(t)
		var s := rng.randf_range(0.85, 1.15)
		_m(t, Models.cyl(0.18 * s, 0.26 * s, 1.8 * s), WOOD, Vector3(0, 0.9 * s, 0))
		_m(t, Models.sphere(1.25 * s), LEAF[rng.randi() % 3], Vector3(0, 2.4 * s, 0))
		_m(t, Models.sphere(0.85 * s), LEAF[rng.randi() % 3], Vector3(0.35 * s, 3.2 * s, 0.1 * s))


func _plaza() -> void:
	var g := _group("Plaza")
	_plane(g, XW, ZS, XE, PLAZA_Z, 0.0, _checker_mat(STONE_LIGHT, STONE, 0.5))
	# 矮石牆（比家裡的柵欄高一點點）：東、西、南三邊，南邊中間是鐵門
	for sx: float in [-1.0, 1.0]:
		var ex := (XE + 0.3) if sx > 0 else (XW - 0.3)
		_low_wall(g, Vector3(ex, 0, ZS + 0.2), Vector3(ex, 0, PLAZA_Z + 0.2))
		_low_wall(g, Vector3(ex, 0, PLAZA_Z + 0.2), Vector3(sx * 1.2, 0, PLAZA_Z + 0.2))
		_box(g, Vector3(sx * 1.2, 0.55, PLAZA_Z + 0.2), Vector3(0.5, 1.1, 0.5), STONE_DARK)   # 門柱
		_m(g, Models.sphere(0.2), GOLD, Vector3(sx * 1.2, 1.25, PLAZA_Z + 0.2))
		_furn(g, "star_lamp", Vector3(sx * 1.9, 0, PLAZA_Z - 0.4))
		_furn(g, "bench", Vector3(sx * 5.0, 0, 9.4), 180.0)
		_furn(g, "flower_pot", Vector3(sx * 1.6, 0, ZS + 0.6))
		for k in range(3):
			_furn(g, ["yard_flower_red", "yard_flower_yellow", "yard_flower_purple"][k], Vector3(sx * (7.3 - k * 0.7), 0, 7.0))
	# 打開的鐵門（往兩邊開）
	for sx: float in [-1.0, 1.0]:
		var gate := Node3D.new()
		gate.position = Vector3(sx * 0.95, 0, PLAZA_Z + 0.2)
		gate.rotation_degrees.y = sx * -70.0
		g.add_child(gate)
		for k in range(5):
			_box(gate, Vector3(-sx * (0.08 + k * 0.17), 0.5, 0), Vector3(0.04, 1.0, 0.04), Color("3c3a40"), false)
		_box(gate, Vector3(-sx * 0.42, 0.95, 0), Vector3(0.84, 0.05, 0.05), Color("3c3a40"), false)
		_box(gate, Vector3(-sx * 0.42, 0.15, 0), Vector3(0.84, 0.05, 0.05), Color("3c3a40"), false)
	_hot("gate", "鐵門", Vector3(0, 0.8, PLAZA_Z + 0.2), "回樹屋", "town")


## 矮石牆：牆身＋壓頂石，每隔兩公尺一根小方柱
func _low_wall(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var l := a.distance_to(b)
	var w := Node3D.new()
	w.position = (a + b) / 2
	w.rotation.y = atan2(b.x - a.x, b.z - a.z)
	parent.add_child(w)
	var I := Transform3D.IDENTITY
	_inst(w, I, Vector3(0, 0.35, 0), Vector3(0.3, 0.7, l), STONE)
	_inst(w, I, Vector3(0, 0.74, 0), Vector3(0.4, 0.08, l + 0.06), STONE_DARK)
	var n := maxi(1, int(l / 2.0))
	for k in range(n + 1):
		_inst(w, I, Vector3(0, 0.45, -l / 2 + l * k / n), Vector3(0.42, 0.9, 0.42), STONE_DARK)


# ---------------- 建築：石牆、石柱、拱窗 ----------------
func _walls() -> void:
	var I := Transform3D.IDENTITY
	var t := WALL_T
	# 北牆
	var wn: Node3D = walls.N
	var cx := (XW + XE) / 2.0
	_box(wn, Vector3(cx, WALL_H / 2, ZN - t / 2), Vector3(XE - XW + 2 * t, WALL_H, t), STONE)
	# 東、西牆
	for side in ["W", "E"]:
		var ex := (XW - t / 2) if side == "W" else (XE + t / 2)
		_box(walls[side], Vector3(ex, WALL_H / 2, 0), Vector3(t, WALL_H, ZS - ZN), STONE)
	# 南牆：中間是大門（拱門）
	var ws: Node3D = walls.S
	for sx: float in [-1.0, 1.0]:
		var w := ((XE if sx > 0 else -XW) + t) - DOOR_HALF
		_box(ws, Vector3(sx * (DOOR_HALF + w / 2), WALL_H / 2, ZS + t / 2), Vector3(w, WALL_H, t), STONE)
	_box(ws, Vector3(0, 2.6 + (WALL_H - 2.6) / 2, ZS + t / 2), Vector3(DOOR_HALF * 2, WALL_H - 2.6, t), STONE)
	# 大門的石拱框、門口兩根大石柱、山牆、招牌
	for sx: float in [-1.0, 1.0]:
		_box(ws, Vector3(sx * (DOOR_HALF + 0.15), 1.3, ZS + t + 0.05), Vector3(0.3, 2.6, 0.12), STONE_DARK)
		_m(ws, Models.cyl(0.26, 0.3, WALL_H + 0.2), STONE_LIGHT, Vector3(sx * 1.9, (WALL_H + 0.2) / 2, ZS + t + 0.3))
		_box(ws, Vector3(sx * 1.9, WALL_H + 0.25, ZS + t + 0.3), Vector3(0.7, 0.16, 0.7), STONE_DARK)
		_box(ws, Vector3(sx * 1.9, 0.08, ZS + t + 0.3), Vector3(0.7, 0.16, 0.7), STONE_DARK)
	_box(ws, Vector3(0, 2.7, ZS + t + 0.05), Vector3(DOOR_HALF * 2 + 0.6, 0.22, 0.14), STONE_DARK)
	_box(ws, Vector3(0, WALL_H + 0.42, ZS + t + 0.3), Vector3(4.6, 0.18, 0.9), STONE_DARK)
	var ped := _m(ws, _unit_prism, STONE, Vector3(0, WALL_H + 0.95, ZS + t / 2))
	ped.scale = Vector3(4.4, 0.9, 0.5)
	_label(ws, "派森圖書館", Vector3(0, WALL_H + 0.8, ZS + t + 0.01), 64, Color("6a4a30"))
	# 大門的兩扇木門（往裡面打開）
	for sx: float in [-1.0, 1.0]:
		var d := Node3D.new()
		d.position = Vector3(sx * DOOR_HALF, 0, ZS + 0.05)
		d.rotation_degrees.y = sx * 80.0
		ws.add_child(d)
		_box(d, Vector3(-sx * DOOR_HALF / 2, 1.3, 0), Vector3(DOOR_HALF - 0.04, 2.58, 0.08), WOOD)
	# 牆內側的方石柱（壁柱，跟著牆一起藏），牆頂的簷口
	for x: float in [-12.0, -8.0, -4.0, 4.0, 8.0, 12.0]:
		_wall_pillar(walls.N, Vector3(x, 0, ZN + 0.25))
	_wall_pillar(walls.N, Vector3(0, 0, ZN + 0.25))
	for x: float in [-12.0, -8.0, -4.0, 4.0, 8.0, 12.0]:
		_wall_pillar(walls.S, Vector3(x, 0, ZS - 0.25))
	for side in ["W", "E"]:
		var ex := (XW + 0.25) if side == "W" else (XE - 0.25)
		for z: float in [-2.0, 2.0]:
			if side == "W":
				continue   # 西牆是教室的黑板牆，不放壁柱
			_wall_pillar(walls[side], Vector3(ex, 0, z))
	_inst(walls.N, I, Vector3(cx, WALL_H + 0.08, ZN - t / 2), Vector3(XE - XW + 2 * t + 0.3, 0.16, t + 0.3), STONE_DARK)
	_inst(walls.S, I, Vector3(cx, WALL_H + 0.08, ZS + t / 2), Vector3(XE - XW + 2 * t + 0.3, 0.16, t + 0.3), STONE_DARK)
	for side in ["W", "E"]:
		var ex := (XW - t / 2) if side == "W" else (XE + t / 2)
		_inst(walls[side], I, Vector3(ex, WALL_H + 0.08, 0), Vector3(t + 0.3, 0.16, ZS - ZN), STONE_DARK)
	# 拱窗
	for x: float in [-10.0, -6.0, 6.0, 10.0]:
		_arch_window(walls.N, Vector3(x, 1.9, ZN + 0.01), 0.0)
	for side in ["W", "E"]:
		var sx := -1.0 if side == "W" else 1.0
		var ex := (XW + 0.01) if side == "W" else (XE - 0.01)
		for z: float in [-4.0, 0.0, 4.0]:
			if side == "W" and z > -4.5 and z < 0.5:
				continue   # 黑板在這裡
			_arch_window(walls[side], Vector3(ex, 1.9, z), -sx * 90.0)
	for x: float in [-10.0, -6.0, 6.0, 10.0]:
		_arch_window(walls.S, Vector3(x, 1.9, ZS + t + 0.01), 180.0, true)


## 方石柱：底座、柱身、柱頭（建築材料，可以比家具大）
func _wall_pillar(parent: Node3D, base: Vector3) -> void:
	var I := Transform3D(Basis.IDENTITY, base)
	_inst(parent, I, Vector3(0, 0.12, 0), Vector3(0.66, 0.24, 0.66), STONE_DARK)
	_inst(parent, I, Vector3(0, WALL_H / 2, 0), Vector3(0.5, WALL_H, 0.5), STONE_LIGHT)
	_inst(parent, I, Vector3(0, WALL_H - 0.1, 0), Vector3(0.66, 0.2, 0.66), STONE_DARK)


## 拱窗（長方形＋半圓頂）；yaw 0 = 窗面朝南（館內看北牆）
func _arch_window(parent: Node3D, c: Vector3, yaw: float, outside: bool = false) -> void:
	var h := Node3D.new()
	h.position = c
	h.rotation_degrees.y = yaw
	parent.add_child(h)
	var z := 0.02
	_box(h, Vector3(0, 0, z), Vector3(1.0, 1.2, 0.05), STONE_DARK, false)
	_m(h, Models.cyl(0.5, 0.5, 0.05), STONE_DARK, Vector3(0, 0.6, z), Vector3(90, 0, 0), false)
	_m(h, Models.box(0.8, 1.05, 0.04), GLASS, Vector3(0, 0, z + 0.02), Vector3.ZERO, false, true)
	_m(h, Models.cyl(0.4, 0.4, 0.04), GLASS, Vector3(0, 0.55, z + 0.02), Vector3(90, 0, 0), false, true)
	_box(h, Vector3(0, 0.1, z + 0.05), Vector3(0.04, 1.4, 0.03), STONE_DARK, false)
	_box(h, Vector3(0, 0.15, z + 0.05), Vector3(0.8, 0.04, 0.03), STONE_DARK, false)
	if not outside:
		_box(h, Vector3(0, -0.66, 0.12), Vector3(1.1, 0.08, 0.24), STONE_DARK)   # 窗台


# ---------------- 館內 ----------------
func _floor() -> void:
	var g := _group("Floor")
	_plane(g, XW, ZN, XE, ZS, 0.005, _checker_mat(Color("efe3c8"), Color("cdb995"), 0.8))
	# 紅地毯：大門 → 雕像 → 館長平台
	var red := StandardMaterial3D.new()
	red.albedo_color = RED
	red.roughness = 1.0
	_plane(g, -0.7, 2.7, 0.7, ZS - 0.05, 0.015, red)
	_plane(g, -0.7, -2.3, 0.7, 0.5, 0.015, red)
	var rug := _m(g, Models.cyl(1.25, 1.25, 0.01), RED, Vector3(0, 0.015, 1.6), Vector3.ZERO, false)
	rug.name = "StatueRug"
	_m(g, Models.cyl(1.05, 1.05, 0.012), GOLD, Vector3(0, 0.017, 1.6), Vector3.ZERO, false)
	# 任務用的格子區（細細的金框）：平常藏起來，有圖書館任務才打開（set_task_grid）
	task_grid = Node3D.new()
	task_grid.name = "TaskGrid"
	task_grid.visible = false
	g.add_child(task_grid)
	var o := GRID_ORIGIN
	for k in range(GRID_SIZE.x + 1):
		_box(task_grid, Vector3(o.x + k, 0.02, o.z + GRID_SIZE.y / 2.0), Vector3(0.03, 0.01, GRID_SIZE.y), GOLD, false)
	for k in range(GRID_SIZE.y + 1):
		_box(task_grid, Vector3(o.x + GRID_SIZE.x / 2.0, 0.02, o.z + k), Vector3(GRID_SIZE.x, 0.01, 0.03), GOLD, false)


## 大廳：初代大賢者像、門邊的盆栽、角落的燈、沙發
func _hall() -> void:
	var g := _group("Hall")
	var c := Vector3(0, 0, 1.6)
	_m(g, Models.cyl(0.62, 0.7, 0.5), STONE_DARK, c + Vector3(0, 0.25, 0))
	_m(g, Models.cyl(0.55, 0.55, 0.06), STONE, c + Vector3(0, 0.53, 0))
	var s := Node3D.new()
	s.position = c + Vector3(0, 0.56, 0)
	g.add_child(s)
	# 老烏龜賢者（石像，比派派鼠高一點）：寬袖長袍、腰帶、背上的大龜殼、
	# 左手捧著攤開的書、右手拄著長杖，低頭慈祥地看著來的人。用車床曲面（旋轉的輪廓）做出圓滑的形狀
	var robe := _m(s, _lathe([Vector2(0, 0), Vector2(0.45, 0), Vector2(0.47, 0.04), Vector2(0.43, 0.18), Vector2(0.37, 0.4),
		Vector2(0.32, 0.62), Vector2(0.3, 0.78), Vector2(0.3, 0.9), Vector2(0.26, 0.99), Vector2(0.16, 1.05), Vector2(0, 1.07)]), STONE_LIGHT, Vector3.ZERO)
	robe.scale = Vector3(1.0, 1.0, 0.86)
	for k in range(5):                                                                    # 長袍下襬的皺褶
		var ang := deg_to_rad(-60 + k * 30)
		var fold := _m(s, _lathe([Vector2(0, 0), Vector2(0.04, 0), Vector2(0.035, 0.2), Vector2(0.012, 0.36), Vector2(0, 0.38)], 12), STONE_LIGHT, Vector3(sin(ang) * 0.42, 0, cos(ang) * 0.37), Vector3(0, 0, 0), false)
		fold.rotation.z = -sin(ang) * 0.12
	var belt := _m(s, _torus(0.3, 0.035), STONE_DARK, Vector3(0, 0.66, 0), Vector3.ZERO, false)  # 腰帶
	belt.scale = Vector3(1.04, 1.0, 0.9)
	_m(s, _ball(0.05), STONE_DARK, Vector3(0.0, 0.66, 0.28), Vector3.ZERO, false)       # 腰帶結
	_m(s, _torus(0.2, 0.045), STONE, Vector3(0, 1.0, 0.0), Vector3(8, 0, 0), false)       # 領口
	# 背上的大龜殼：圓頂＋外緣＋六角形的殼片
	var sc := Vector3(0, 0.7, -0.24)
	var shell_r := Vector3(0.44, 0.52, 0.24)
	var shell := _m(s, _ball(1.0), STONE, sc)
	shell.scale = shell_r
	var rim := _m(s, _torus(1.0, 0.13), STONE_DARK, sc + Vector3(0, 0, 0.02), Vector3(90, 0, 0), false)
	rim.scale = Vector3(0.44, 0.35, 0.52)
	for d: Vector2 in [Vector2(0, 0), Vector2(0, 0.55), Vector2(0, -0.5), Vector2(0.5, 0.28), Vector2(-0.5, 0.28), Vector2(0.48, -0.3), Vector2(-0.48, -0.3)]:
		var nz := -sqrt(maxf(0.0, 1.0 - d.x * d.x - d.y * d.y))
		var n := Vector3(d.x / shell_r.x, d.y / shell_r.y, nz / shell_r.z).normalized()   # 橢球的法線
		var hex := _m(s, Models.cyl(0.1, 0.11, 0.03), STONE_DARK, sc + Vector3(d.x * shell_r.x, d.y * shell_r.y, nz * shell_r.z), Vector3.ZERO, false)
		hex.mesh.radial_segments = 6
		hex.basis = Basis(Quaternion(Vector3.UP, n)) * Basis.from_scale(Vector3(1.0 + 0.3 * absf(d.x), 1, 1))
	# 頭：烏龜的圓頭、往前的吻部、慈祥的瞇瞇眼、垂下來的長眉毛
	var head := Node3D.new()
	head.position = Vector3(0, 1.2, 0.07)
	head.rotation_degrees = Vector3(12, 0, 0)                                              # 微微低頭
	s.add_child(head)
	var skull := _m(head, _ball(0.2), STONE_LIGHT, Vector3(0, 0.06, 0))
	skull.scale = Vector3(1.0, 0.95, 1.05)
	var muzzle := _m(head, _ball(0.14), STONE_LIGHT, Vector3(0, -0.01, 0.15))
	muzzle.scale = Vector3(1.1, 0.8, 0.9)
	for sx: float in [-1.0, 1.0]:
		for k in [-1.0, 1.0]:                                                             # 瞇起來的眼睛：兩小段組成彎彎的線
			_m(head, Models.capsule(0.009, 0.05), STONE_DARK, Vector3(sx * 0.085 + k * 0.018, 0.095 + 0.006, 0.19), Vector3(0, 0, 90 - k * 25), false)
		var brow := _m(head, _lathe([Vector2(0, 0), Vector2(0.025, 0.01), Vector2(0.02, 0.1), Vector2(0, 0.13)], 10), STONE, Vector3(sx * 0.1, 0.15, 0.17), Vector3.ZERO, false)
		brow.rotation_degrees = Vector3(40, 0, sx * 115)                                   # 往兩邊垂的長眉毛
	var beard := _m(head, _lathe([Vector2(0, 0), Vector2(0.04, 0.05), Vector2(0.08, 0.15), Vector2(0.11, 0.28), Vector2(0.09, 0.37), Vector2(0, 0.4)], 20), STONE, Vector3(0, -0.5, 0.2))
	beard.rotation_degrees = Vector3(14, 0, 0)                                             # 長長的鬍子
	beard.scale = Vector3(1.0, 1.0, 0.7)
	# 左手：寬袖子往前彎，手捧著攤開的書
	_limb(s, Vector3(-0.27, 0.93, 0.0), Vector3(-0.2, 0.72, 0.22), 0.08, 0.13)
	_m(s, _ball(0.065), STONE_LIGHT, Vector3(-0.14, 0.7, 0.32))
	var book := Node3D.new()
	book.position = Vector3(-0.08, 0.75, 0.36)
	book.rotation_degrees = Vector3(-35, 15, 0)
	s.add_child(book)
	for side: float in [-1.0, 1.0]:                                                         # 兩頁攤開成淺淺的 V
		var page := _m(book, Models.box(0.17, 0.025, 0.24), STONE, Vector3(side * 0.085, 0.0, 0), Vector3(0, 0, side * -10), false)
		page.position.y = 0.012
	_m(book, Models.box(0.36, 0.02, 0.26), STONE_DARK, Vector3(0, -0.01, 0), Vector3.ZERO, false)   # 書皮
	# 右手：袖子垂在身側，握著比人還高的長杖，杖頭捲成一圈
	_limb(s, Vector3(0.27, 0.93, 0.0), Vector3(0.36, 0.7, 0.14), 0.08, 0.13)
	_m(s, _ball(0.065), STONE_LIGHT, Vector3(0.39, 0.68, 0.17))
	_m(s, Models.cyl(0.028, 0.034, 1.66), STONE_DARK, Vector3(0.4, 0.83, 0.18), Vector3.ZERO, false)
	_m(s, _torus(0.07, 0.025), STONE_DARK, Vector3(0.4, 1.72, 0.18), Vector3(0, 0, 90), false)
	_m(s, _ball(0.045), STONE, Vector3(0.4, 1.72, 0.18))
	_label(g, "初代大賢者\n知道自己不知道，\n是學習的開始。", c + Vector3(0, 0.27, 0.71), 20, Color("5a4630"))
	_hot("statue", "初代大賢者像", c + Vector3(0, 1.3, 0), "這是我的老師，初代大賢者。派派森林所有的知識，都是從他開始的。底座刻著「知道自己不知道，是學習的開始。」")
	# 門口兩盆植物、角落的落地燈、沙發
	for sx: float in [-1.0, 1.0]:
		_furn(g, "flower_pot", Vector3(sx * 1.6, 0, ZS - 0.6))
	_furn(g, "star_lamp", Vector3(-7.4, 0, ZS - 0.6))
	_furn(g, "star_lamp", Vector3(7.4, 0, ZS - 0.6))
	_furn(g, "sofa", Vector3(6.4, 0, ZS - 0.7), 180.0)
	_furn(g, "side_table", Vector3(4.9, 0, ZS - 0.7))
	_furn(g, "plant_small", Vector3(4.9, 0.6, ZS - 0.7))


## 借書櫃台（西邊、大門進來左手邊），派派兔在後面
func _counter() -> void:
	var g := _group("Counter")
	_box(g, Vector3(-4.1, 0.47, 1.7), Vector3(0.6, 0.94, 3.0), WOOD)
	_box(g, Vector3(-4.1, 0.97, 1.7), Vector3(0.78, 0.06, 3.16), WOOD_LIGHT)
	_box(g, Vector3(-3.79, 0.5, 1.7), Vector3(0.02, 0.5, 2.6), Color("9a6a46"), false)
	_furn(g, "books", Vector3(-4.1, 1.0, 0.6))
	_furn(g, "books", Vector3(-4.1, 1.0, 0.9), 30.0)
	_furn(g, "mushroom_lamp", Vector3(-4.15, 1.0, 2.8))
	_m(g, Models.cyl(0.07, 0.09, 0.08), GOLD, Vector3(-4.0, 1.04, 2.2))   # 服務鈴
	_label(g, "借書櫃台", Vector3(-3.77, 0.6, 1.7), 40, Color("fff4dc"), 90.0)
	# 櫃台後面靠牆的書櫃和還書推車
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for z: float in [0.9, 1.9, 2.9]:
		_tall_shelf(g, Vector3(X0 + 0.3, 0, z), 90.0, rng)
	_furn(g, "crate", Vector3(-5.4, 0, 3.6))
	_hot("counter", "借書櫃台", Vector3(-4.1, 1.2, 1.7), "這是借書櫃台，派派兔在這裡打工。想學東西就上台階來找我。")


## 館長平台（北邊正中間，三階高），書桌、地球儀、燈、後面的書櫃
func _platform() -> void:
	var g := _group("Platform")
	var d := ZN - PLAT_Z
	_box(g, Vector3(0, PLAT_H / 2, (ZN + PLAT_Z) / 2), Vector3(PLAT_X * 2, PLAT_H, -d), STONE)
	_box(g, Vector3(0, PLAT_H + 0.01, (ZN + PLAT_Z) / 2), Vector3(PLAT_X * 2 - 0.2, 0.02, -d - 0.2), Color("8e5a7a"), false)  # 紫色地毯
	for k in range(3):   # 三階樓梯
		var top := PLAT_H * (k + 1) / 3.0
		var z := PLAT_Z + 0.9 - 0.3 * (k + 0.5)
		_box(g, Vector3(0, top / 2, z), Vector3(STEP_HALF * 2, top, 0.3), STONE_LIGHT)
	# 平台前緣、兩側的石欄杆（中間樓梯口打開）
	for sx: float in [-1.0, 1.0]:
		_balustrade(g, Vector3(sx * (STEP_HALF + 0.1), PLAT_H, PLAT_Z + 0.1), Vector3(sx * (PLAT_X - 0.1), PLAT_H, PLAT_Z + 0.1))
		_balustrade(g, Vector3(sx * (PLAT_X - 0.1), PLAT_H, PLAT_Z + 0.1), Vector3(sx * (PLAT_X - 0.1), PLAT_H, ZN + 0.2))
	# 書桌和高背椅
	var y := PLAT_H
	_box(g, Vector3(0, y + 0.74, -5.0), Vector3(2.0, 0.07, 0.85), WOOD_LIGHT)
	for sx: float in [-0.9, 0.9]:
		_box(g, Vector3(sx, y + 0.37, -5.0), Vector3(0.12, 0.72, 0.75), WOOD)
	_box(g, Vector3(0, y + 0.45, -5.38), Vector3(1.7, 0.5, 0.05), WOOD)
	_box(g, Vector3(0, y + 0.5, -5.75), Vector3(0.6, 0.08, 0.55), Color("6a3a5a"))
	_box(g, Vector3(0, y + 1.0, -6.0 + 0.08), Vector3(0.62, 1.0, 0.08), Color("6a3a5a"))
	_furn(g, "books", Vector3(-0.6, y + 0.78, -5.0))
	_furn(g, "mushroom_lamp", Vector3(0.65, y + 0.78, -5.1))
	_box(g, Vector3(0.05, y + 0.79, -4.9), Vector3(0.42, 0.02, 0.3), Color("f4ecd8"), false)   # 攤開的書
	_m(g, Models.cyl(0.008, 0.012, 0.3), Color("f4f0e6"), Vector3(0.32, y + 0.88, -4.85), Vector3(0, 0, -30), false)   # 羽毛筆
	# 地球儀
	_m(g, Models.cyl(0.12, 0.16, 0.05), WOOD, Vector3(-2.5, y + 0.03, -4.5))
	_m(g, Models.cyl(0.025, 0.025, 0.7), WOOD, Vector3(-2.5, y + 0.38, -4.5))
	_m(g, Models.sphere(0.24), Color("6fa3c9"), Vector3(-2.5, y + 0.85, -4.5))
	_m(g, Models.sphere(0.1), Color("8fbd62"), Vector3(-2.42, y + 0.92, -4.32))
	_furn(g, "star_lamp", Vector3(2.5, y, -4.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for x: float in [-2.6, -1.6, 1.6, 2.6]:
		_tall_shelf(g, Vector3(x, y, ZN + 0.3), 0.0, rng)
	_hot("desk", "館長的書桌", Vector3(0, y + 1.0, -5.0), "這是我的書桌。每天都在這裡讀一點、寫一點，慢慢來。")
	_hot("globe", "地球儀", Vector3(-2.5, y + 0.9, -4.5), "派森小鎮在這裡，派派森林在旁邊。世界很大，書裡都有。")


## 石欄杆：上下兩條橫石，中間一排小石柱
func _balustrade(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var l := a.distance_to(b)
	var w := Node3D.new()
	w.position = (a + b) / 2
	w.rotation.y = atan2(b.x - a.x, b.z - a.z)
	parent.add_child(w)
	var I := Transform3D.IDENTITY
	_inst(w, I, Vector3(0, 0.05, 0), Vector3(0.22, 0.1, l), STONE_DARK)
	_inst(w, I, Vector3(0, 0.6, 0), Vector3(0.24, 0.08, l + 0.1), STONE_DARK)
	var n := maxi(2, int(l / 0.3))
	for k in range(n + 1):
		_inst(w, I, Vector3(0, 0.33, -l / 2 + l * k / n), Vector3(0.1, 0.46, 0.1), STONE_LIGHT)


## 閱讀教室（西北角）：兩張長木桌、小椅子、牆上的黑板
func _reading_room() -> void:
	var g := _group("Reading")
	reading_tables = Node3D.new()   # 平常的閱讀長桌；上課時收起來，換成面向黑板的課桌椅
	reading_tables.name = "ReadingTables"
	g.add_child(reading_tables)
	for z: float in [-4.6, -2.4]:
		_furn(reading_tables, "long_table", Vector3(-6.0, 0, z))
		for x: float in [-6.5, -5.5]:
			_furn(reading_tables, "chair_small", Vector3(x, 0, z - 0.75), 0.0)
			_furn(reading_tables, "chair_small", Vector3(x, 0, z + 0.75), 180.0)
		_furn(reading_tables, "books", Vector3(-6.3, 0.75, z))
	_furn(reading_tables, "plant_book", Vector3(-5.6, 0.75, -4.6))



## 教室（2026-11-08 使用者確認）：圖書館往西加寬（x -12..-8），西牆有講台和大黑板，館長站在講台上；
## 台下一排課桌椅面向黑板，派派狼、派派鼠、派派兔坐在中間三個位子
const CLASS_SEATS := {"wolf": Vector3(-8.9, 0, -3.4), "gopher": Vector3(-8.9, 0, -2.0), "rabbit": Vector3(-8.9, 0, -0.6)}
const EMPTY_SEATS := [Vector3(-8.9, 0, -4.8), Vector3(-8.9, 0, 0.8)]
const PODIUM_H := 0.3
const TEACHER_SPOT := Vector3(-11.1, PODIUM_H, -2.0)
const SEAT_Y := 0.42
var classroom: Node3D
var reading_tables: Node3D
var task_grid: Node3D


func set_task_grid(on: bool) -> void:
	if task_grid:
		task_grid.visible = on


func _classroom() -> void:
	classroom = _group("Classroom")
	var g := classroom
	# 講台：靠西牆的木頭台子，前面一階
	_box(g, Vector3(XW + 0.85, PODIUM_H / 2, -2.0), Vector3(1.7, PODIUM_H, 5.0), WOOD)
	_box(g, Vector3(XW + 0.85, PODIUM_H + 0.01, -2.0), Vector3(1.6, 0.02, 4.9), Color("b07a4f"), false)
	_box(g, Vector3(XW + 1.85, PODIUM_H / 4, -2.0), Vector3(0.3, PODIUM_H / 2, 3.0), WOOD_LIGHT)
	# 講桌（在講台的一邊，不擋住館長）
	_box(g, Vector3(XW + 1.1, PODIUM_H + 0.45, -4.0), Vector3(0.5, 0.9, 0.8), WOOD_LIGHT)
	_box(g, Vector3(XW + 1.1, PODIUM_H + 0.92, -4.0), Vector3(0.62, 0.05, 0.92), WOOD)
	_furn(g, "books", Vector3(XW + 1.1, PODIUM_H + 0.95, -4.1), 15.0)
	# 大黑板
	_box(g, Vector3(XW + 0.05, 1.75, -2.0), Vector3(0.08, 1.3, 3.0), Color("8a5a3a"))
	_box(g, Vector3(XW + 0.1, 1.75, -2.0), Vector3(0.03, 1.16, 2.86), Color("3f5a4a"), false)
	_label(g, "派派森林的教室\nprint(\"你好！\")\nname = \"派派鼠\"", Vector3(XW + 0.13, 1.8, -2.0), 40, Color("f2f0e6"), 90.0)
	_box(g, Vector3(XW + 0.14, 1.08, -2.0), Vector3(0.12, 0.04, 2.6), Color("8a5a3a"))   # 粉筆槽
	_hot("blackboard", "黑板", Vector3(XW + 0.2, 1.8, -2.0), "黑板上寫著今天的功課。派派兔會帶大家來這裡上課。")
	# 台下的課桌椅：一排面向黑板
	for p: Vector3 in CLASS_SEATS.values() + EMPTY_SEATS:
		_furn(g, "side_table", p + Vector3(-0.75, 0, 0))
		_furn(g, "chair_small", p, -90.0)
		_furn(g, "books", p + Vector3(-0.75, 0.5, 0.12), 20.0)
	_label(g, "教室", Vector3(-8.0, 2.9, ZN + 0.05), 56, UIKit.INK)


## 平常站的位置（下課回去）；派派狼、拉拉老闆、大牙師傅平常不在圖書館（來上課才出現）
const HOME_SPOTS := {"turtle": [Vector3(0, PLAT_H, -4.0), "S"], "rabbit": [Vector3(-5.0, 0, 1.7), "E"], "calico": [Vector3(XW + 0.9, 0, 2.2), "E"]}
const STUDENTS := ["wolf", "gopher", "rabbit"]
const VISITORS := ["wolf", "lala", "daya"]


## 上課：teacher 站上講台，其他同學（派派狼、派派鼠、派派兔，老師除外）坐在台下；teacher = "" 是下課
func arrange_class(teacher: String) -> void:
	for who in VISITORS:
		if not npcs.has(who):
			_spawn(who, Vector3(XE - 1.0, 0, 5.0), "S").visible = false
	for who in npcs:
		var a: GopherActor = npcs[who]
		a.moving = false
		if teacher != "" and who == teacher:
			a.set_seated(false)
			a.visible = true
			a.position = TEACHER_SPOT
			a.face("E")
		elif teacher != "" and who in STUDENTS:
			a.visible = true
			a.position = CLASS_SEATS[who] + Vector3(0, SEAT_Y, 0.05)
			a.face("W")
			a.set_seated(true)
		else:
			a.set_seated(false)
			if HOME_SPOTS.has(who):
				a.position = HOME_SPOTS[who][0]
				a.face(HOME_SPOTS[who][1])
			elif who in VISITORS:
				a.visible = false
			elif who == "gopher" and teacher == "":
				a.position = Vector3(-7.0, 0, 1.0)   # 下課：站在教室門口
				a.face("E")
		a.model.rotation.y = a.target_yaw


## 書櫃區（東邊）：三排書櫃，照課本的章節排好
func _bookshelves() -> void:
	var g := _group("Shelves")
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var tags := ["第 1–3 章", "第 4–6 章", "第 7–8 章"]
	var zs := [-1.2, 1.2, 3.6]
	for r in range(3):
		var z: float = zs[r]
		for x: float in [4.8, 5.8, 6.8]:
			_tall_shelf(g, Vector3(x, 0, z), 0.0, rng)
		_box(g, Vector3(4.15, 0.55, z + 0.05), Vector3(0.06, 1.1, 0.06), WOOD)
		_box(g, Vector3(4.15, 1.15, z + 0.05), Vector3(0.05, 0.3, 0.6), Color("f4ecd8"))
		_label(g, tags[r], Vector3(4.12, 1.15, z + 0.05), 28, UIKit.INK, -90.0)
	_hot("shelves", "書櫃區", Vector3(5.8, 1.6, 1.2), "一個概念一本書，照課本的章節排好。想學哪一個，就來問我。")
	# 東邊加寬的書庫：再三排書櫃（後面的章節、參考書）
	var tags2 := ["第 9 章", "第 10–11 章", "參考書"]
	for r in range(3):
		var z: float = zs[r]
		for x: float in [9.0, 10.0, 11.0]:
			_tall_shelf(g, Vector3(x, 0, z), 0.0, rng)
		_box(g, Vector3(8.35, 0.55, z + 0.05), Vector3(0.06, 1.1, 0.06), WOOD)
		_box(g, Vector3(8.35, 1.15, z + 0.05), Vector3(0.05, 0.3, 0.6), Color("f4ecd8"))
		_label(g, tags2[r], Vector3(8.32, 1.15, z + 0.05), 28, UIKit.INK, -90.0)
	_label(g, "書庫", Vector3(10.0, 2.9, ZN + 0.05), 56, UIKit.INK)
	# 原本樓梯的位置：新書展示桌和兩張椅子
	_furn(g, "round_table", Vector3(6.0, 0, -4.9))
	_furn(g, "chair_small", Vector3(5.2, 0, -4.9), 90.0)
	_furn(g, "chair_small", Vector3(6.8, 0, -4.9), -90.0)
	_furn(g, "books", Vector3(6.0, 0.75, -4.9), 10.0)
	_hot("newbooks", "新書展示桌", Vector3(6.0, 1.0, -4.9), "這裡放剛整理好的新書，坐下來翻翻看吧。")


## 往樓上的樓梯（東北角），紅繩擋著
func _stairs() -> void:
	var g := _group("Stairs")
	g.position.x = XE - X1   # 2026-11-08：搬到東邊加寬的書庫（東北角），上樓的小門在新的東牆上
	for k in range(6):
		var top := 0.25 * (k + 1)
		_box(g, Vector3(4.75 + k * 0.4, top / 2, -5.0), Vector3(0.4, top, 1.6), STONE_LIGHT)
	_box(g, Vector3(7.4, 1.5 / 2, -5.0), Vector3(0.6, 1.5, 1.6), STONE_LIGHT)
	_box(g, Vector3(X1 - 0.02, 1.5 + 0.7, -5.0), Vector3(0.06, 1.4, 0.8), WOOD)   # 樓上的小門
	_m(g, Models.sphere(0.04), GOLD, Vector3(X1 - 0.06, 1.5 + 0.7, -4.75))
	_label(g, "整理中", Vector3(X1 - 0.06, 1.5 + 1.05, -5.0), 28, Color("fff4dc"), -90.0)
	# 紅繩
	for z: float in [-5.75, -4.25]:
		_m(g, Models.cyl(0.04, 0.06, 0.8), GOLD, Vector3(4.3, 0.4, z))
		_m(g, Models.sphere(0.07), GOLD, Vector3(4.3, 0.83, z))
	_m(g, Models.cyl(0.03, 0.03, 1.5), RED, Vector3(4.3, 0.72, -5.0), Vector3(90, 0, 0), false)
	_hot("stairs", "往樓上的樓梯", Vector3(5.5 + XE - X1, 1.2, -5.0), "樓上還在整理，以後再帶你上去。")


# ---------------- 進出、鏡頭 ----------------
## v = true：派派鼠站在大門裡面；false：站在前庭
func set_inside(v: bool) -> void:
	var g: GopherActor = npcs.get("gopher")
	if g:
		_walk_serial += 1
		if _walk_tween:
			_walk_tween.kill()
		g.moving = false
		g.position = Vector3(0.0, 0.0, ZS - 1.2) if v else Vector3(0.0, 0.0, 9.5)
		g.face("N")
		g.model.rotation.y = g.target_yaw
	inside = v
	for s in walls:
		walls[s].visible = true


## 鏡頭焦點和距離：和家裡一樣（整個場景都看得到）
func view_focus() -> Vector3:
	return global_transform * Vector3(0, 0, 1.5)


func view_distance() -> float:
	return 25.0


## 派派鼠在館內時，靠鏡頭那一側的牆藏起來（和家裡一樣）
func update_cutaway(cam_pos: Vector3) -> void:
	var g: GopherActor = npcs.get("gopher")
	if g:
		inside = g.position.z < ZS and g.position.x > XW and g.position.x < XE
	var to_cam := global_transform.affine_inverse() * cam_pos
	var normals := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0), "E": Vector3(1, 0, 0)}
	# 每面牆離館中心多遠：鏡頭跑到這面牆「外面」才藏（上課時鏡頭在教室裡往西看，黑板那面西牆要留著）
	var plane := {"N": -ZN, "S": ZS, "W": -XW, "E": XE}
	for side in walls:
		var n: Vector3 = normals[side]
		walls[side].visible = not inside or to_cam.dot(n) - float(plane[side]) < 0.3


# ---------------- 居民 ----------------
func _spawn(who: String, pos: Vector3, facing: String) -> GopherActor:
	var a := GopherActor.new()
	a.name = "Lib_" + who
	add_child(a)
	a.setup(Models.character(who))
	a.speaker_name = NAMES.get(who, "")
	a.bubble_height = BUBBLE_H.get(who, 1.4)
	a.position = pos
	a.face(facing)
	a.model.rotation.y = a.target_yaw
	npcs[who] = a
	return a


func actor_at(screen_pos: Vector2, cam: Camera3D) -> String:
	var best := ""
	var best_d := 55.0
	for who in npcs:
		if who == "gopher":
			continue
		var a: GopherActor = npcs[who]
		var p := a.global_position + Vector3(0, 0.6, 0)
		if cam.is_position_behind(p):
			continue
		var dd := cam.unproject_position(p).distance_to(screen_pos)
		if dd < best_d:
			best_d = dd
			best = who
	return best


## 滑鼠指到哪個可以點的東西（螢幕上 50 像素以內）
func hotspot_at(screen_pos: Vector2, cam: Camera3D) -> String:
	var best := ""
	var best_d := 50.0
	for id in hotspots:
		var h: Dictionary = hotspots[id]
		var p: Vector3 = global_transform * (h.pos as Vector3)
		if cam.is_position_behind(p):
			continue
		var dd := cam.unproject_position(p).distance_to(screen_pos)
		if dd < best_d:
			best_d = dd
			best = id
	return best


func talk(who: String) -> void:
	if not npcs.has(who):
		return
	var lines: Array = LINES.get(who, ["……"])
	var i: int = _line_i.get(who, 0)
	_line_i[who] = (i + 1) % lines.size()
	var a: GopherActor = npcs[who]
	a.hop(0.08 if who == "turtle" else 0.12)
	a.say(lines[i], "say")


## 點了某個東西：館長說明（在前庭時派派鼠自己說）
func describe(id: String) -> void:
	var h: Dictionary = hotspots.get(id, {})
	if h.is_empty():
		return
	var who := "turtle" if inside else "gopher"
	var a: GopherActor = npcs.get(who)
	if a:
		a.say(h.text, "say")


# ---------------- 點地板走路（找路網格） ----------------
## 地面高度：館長平台和前面的三階樓梯
func ground_y(x: float, z: float) -> float:
	if absf(x) < PLAT_X and z <= PLAT_Z:
		return PLAT_H
	if absf(x) < STEP_HALF and z < PLAT_Z + 0.9:
		return PLAT_H * clampf((PLAT_Z + 0.9 - z) / 0.9, 0.0, 1.0)
	return 0.0


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - NAV_X0) / CELL)), 0, NAV_W - 1), clampi(int(floor((p.z - NAV_Z0) / CELL)), 0, NAV_H - 1))


func _cell_center(c: Vector2i) -> Vector3:
	var x := NAV_X0 + (c.x + 0.5) * CELL
	var z := NAV_Z0 + (c.y + 0.5) * CELL
	return Vector3(x, ground_y(x, z), z)


func _set_rect(x0: float, z0: float, x1: float, z1: float, solid: bool) -> void:
	var a := _cell_of(Vector3(minf(x0, x1), 0, minf(z0, z1)))
	var b := _cell_of(Vector3(maxf(x0, x1) - 0.001, 0, maxf(z0, z1) - 0.001))
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			nav.set_point_solid(Vector2i(cx, cz), solid)


func _block_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	_set_rect(x0, z0, x1, z1, true)


func _block_round(x: float, z: float, r: float) -> void:
	_block_rect(x - r, z - r, x + r, z + r)


func _build_nav() -> void:
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, NAV_W, NAV_H)
	nav.cell_size = Vector2(CELL, CELL)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	# 先全部擋住，再打開能走的地方：館內、大門、前庭
	nav.fill_solid_region(nav.region, true)
	_set_rect(XW + 0.3, ZN + 0.3, XE - 0.3, ZS - 0.2, false)
	_set_rect(-DOOR_HALF + 0.2, ZS - 0.3, DOOR_HALF - 0.2, ZS + 0.6, false)
	_set_rect(XW + 0.1, ZS + 0.5, XE - 0.1, PLAZA_Z - 0.1, false)
	_set_rect(-0.9, PLAZA_Z - 0.3, 0.9, PLAZA_Z + 0.6, false)
	# ---- 館內 ----
	for x: float in [-4.0, 0.0, 4.0]:          # 壁柱
		_block_rect(x - 0.35, ZN, x + 0.35, ZN + 0.6)
	for x: float in [-4.0, 4.0]:
		_block_rect(x - 0.35, ZS - 0.6, x + 0.35, ZS)
	for z: float in [-2.0, 2.0]:
		_block_rect(XE - 0.6, z - 0.35, XE, z + 0.35)
	for x: float in [-12.0, -8.0, 8.0, 12.0]:
		_block_rect(x - 0.35, ZN, x + 0.35, ZN + 0.6)
		_block_rect(x - 0.35, ZS - 0.6, x + 0.35, ZS)
	# 教室：講台、講桌、課桌椅、三花奶奶
	_block_rect(XW, -4.6, XW + 2.05, 0.6)
	for p: Vector3 in CLASS_SEATS.values() + EMPTY_SEATS:
		_block_rect(p.x - 1.1, p.z - 0.4, p.x + 0.3, p.z + 0.4)
	_block_round(XW + 0.9, 2.2, 0.35)
	_block_round(0.0, 1.6, 0.75)                        # 初代大賢者像
	_block_rect(-4.55, 0.1, -3.65, 3.3)                 # 借書櫃台
	_block_round(-5.0, 1.7, 0.35)                       # 派派兔
	_block_rect(X0, 0.3, X0 + 0.6, 3.4)                 # 櫃台後面的書櫃（舊的西牆位置）
	_block_round(-5.4, 3.6, 0.45)                       # 木箱
	# 館長平台：只能從中間的三階樓梯上去
	_block_rect(-PLAT_X - 0.1, PLAT_Z - 0.1, -STEP_HALF, PLAT_Z + 0.25)
	_block_rect(STEP_HALF, PLAT_Z - 0.1, PLAT_X + 0.1, PLAT_Z + 0.25)
	_block_rect(-PLAT_X - 0.25, ZN, -PLAT_X + 0.1, PLAT_Z + 0.25)
	_block_rect(PLAT_X - 0.1, ZN, PLAT_X + 0.25, PLAT_Z + 0.25)
	_block_rect(-STEP_HALF - 0.1, PLAT_Z, -STEP_HALF + 0.05, PLAT_Z + 0.9)   # 樓梯兩邊
	_block_rect(STEP_HALF - 0.05, PLAT_Z, STEP_HALF + 0.1, PLAT_Z + 0.9)
	_block_rect(-1.1, -5.5, 1.1, -4.5)                  # 書桌
	_block_rect(-0.4, ZN, 0.4, -5.4)                    # 高背椅
	_block_round(-2.5, -4.5, 0.3)                       # 地球儀
	_block_round(2.5, -4.5, 0.3)                        # 燈
	_block_rect(-3.1, ZN, 3.1, ZN + 0.55)               # 平台後面的書櫃
	_block_round(0.0, -4.0, 0.35)                       # 館長
	_block_rect(8.15, ZN, XE, -4.1)                     # 往樓上的樓梯（紅繩）
	_block_rect(4.9, -5.6, 7.1, -4.2)                   # 新書展示桌
	for z: float in [-4.6, -2.4]:                       # 閱讀教室的長桌和椅子
		_block_rect(-7.05, z - 1.05, -4.95, z + 1.05)
	for z: float in [-1.2, 1.2, 3.6]:                   # 書櫃
		_block_rect(4.05, z - 0.25, 7.35, z + 0.25)
		_block_rect(8.25, z - 0.25, 11.55, z + 0.25)
	_block_rect(5.3, ZS - 1.2, 7.5, ZS)                 # 沙發
	_block_round(4.9, ZS - 0.7, 0.35)                   # 小邊桌
	for sx: float in [-1.0, 1.0]:
		_block_round(sx * 1.6, ZS - 0.6, 0.35)          # 門口盆栽
		_block_round(sx * 7.4, ZS - 0.6, 0.35)          # 落地燈
	# ---- 前庭 ----
	for sx: float in [-1.0, 1.0]:
		_block_round(sx * 1.6, ZS + 0.6, 0.35)          # 盆栽
		_block_rect(sx * 5.0 - 1.0, 8.9, sx * 5.0 + 1.0, 9.9)   # 長椅
		_block_round(sx * 1.9, PLAZA_Z - 0.4, 0.3)      # 燈
		_block_round(sx * 1.9, ZS + 0.65, 0.35)         # 門口石柱
		_block_rect(sx * 5.6, 6.6, sx * 7.7, 7.4)       # 花
		_block_rect(sx * 1.2 - 0.3, PLAZA_Z - 0.1, sx * 1.2 + 0.3, PLAZA_Z + 0.6)   # 門柱


## 滑鼠指到的地板位置（打不到地板就回傳 null）
func floor_point(screen_pos: Vector2, cam: Camera3D) -> Variant:
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.y) < 0.001:
		return null
	var p := global_transform.affine_inverse() * o
	var dl := global_transform.basis.inverse() * d
	var tp := (PLAT_H - p.y) / dl.y   # 先試館長平台的高度
	if tp > 0:
		var hp := p + dl * tp
		if absf(ground_y(hp.x, hp.z) - PLAT_H) < 0.01:
			return hp
	var t := -p.y / dl.y
	if t <= 0:
		return null
	var hit := p + dl * t
	hit.y = ground_y(hit.x, hit.z)
	return hit


## 派派鼠走到某個點（找路、避開擋路的東西，上平台會跟著升高）
func walk_gopher(to: Vector3) -> void:
	var g: GopherActor = npcs.get("gopher")
	if g == null:
		return
	_walk_serial += 1
	var my := _walk_serial
	if _walk_tween:
		_walk_tween.kill()
	var a := _nearest_open(_cell_of(g.position))
	var b := _nearest_open(_cell_of(to))
	if a.x < 0 or b.x < 0:
		return
	var ids := nav.get_id_path(a, b)
	if ids.size() < 2:
		g.moving = false
		return
	# 把同一個方向的格子合併，走起來比較順
	var pts: Array = []
	var last_dir := Vector2i.ZERO
	for i in range(1, ids.size()):
		var dir_i: Vector2i = ids[i] - ids[i - 1]
		if dir_i != last_dir and i > 1:
			pts.append(_cell_center(ids[i - 1]))
		last_dir = dir_i
	pts.append(_cell_center(ids[ids.size() - 1]))
	g.moving = true
	for q in pts:
		if my != _walk_serial:
			return
		var target: Vector3 = q
		var start := g.position
		var dist := Vector2(start.x, start.z).distance_to(Vector2(target.x, target.z))
		g.face_vector(Vector3(target.x - start.x, 0, target.z - start.z))
		_walk_tween = g.create_tween()
		_walk_tween.tween_method(func(f: float):
			var pp: Vector3 = start.lerp(target, f)
			pp.y = ground_y(pp.x, pp.z)
			g.position = pp, 0.0, 1.0, maxf(0.05, dist * 0.42))
		await _walk_tween.finished
		if my != _walk_serial:
			return
		g.position = target
	g.moving = false


## 離目標最近的能走的格子（點到桌子上，就走到桌邊）
func _nearest_open(c: Vector2i) -> Vector2i:
	if not nav.is_point_solid(c):
		return c
	for r in range(1, 16):
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var q := c + Vector2i(dx, dz)
				if nav.is_in_boundsv(q) and not nav.is_point_solid(q):
					var dd := float(dx * dx + dz * dz)
					if dd < bd:
						bd = dd
						best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)
