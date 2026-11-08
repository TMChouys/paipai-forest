class_name LibraryView
extends Node3D
## 派森圖書館：一座很老、很高、很多層的大教堂，是派森小鎮的世界奇觀（中古世紀到文藝復興的味道）。設計稿：docs/library_design.md
## 三層：外圍前庭 → 教堂主建物 → 走進去的大廳。裡面的擺設都是固定的，玩家不能移動（和家裡不同）。
## 座標（公尺）：教堂內部 x -13..13、z -18..14（大門在南邊），室內地板高 Y_IN；兩座鐘塔、中央圓頂。
## 前庭 z 18..46，鐵門在 z=46。大廳中間 GRID_ORIGIN 起算 8×6 格是任務用的格子區（每格 1 公尺）。

const X_HALF := 13.0
const Z_N := -18.0
const Z_S := 14.0
const WALL_H := 24.0
const WALL_T := 0.8
const Y_IN := 1.2
const PLAT_H := 1.5                      # 館長平台很高：八階樓梯上去
const NAVE_X := 6.0                      # 兩排大柱子
const GAL_LV := [7.0, 12.0, 17.0]        # 二、三、四樓的迴廊高度
const GRID_ORIGIN := Vector3(-4, Y_IN, -6)
const GRID_SIZE := Vector2i(8, 6)
const GATE_Z := 46.0
const KENNEY_NATURE := "res://models/kenney/nature/%s.glb"
const KENNEY_FURN := "res://models/kenney/furniture/%s.glb"

const STONE := Color("d9cfbb")
const STONE_DARK := Color("b8ab92")
const STONE_IN := Color("efe5d0")
const SLATE := Color("5e6475")
const WOOD := Color("8a5a3a")
const WOOD_LIGHT := Color("b07a4f")
const GOLD := Color("d9ae52")
const RED := Color("a8433c")
const IRON := Color("3c3a40")
const GLASS := [Color("6f8fd0"), Color("d9605a"), Color("e9c25a"), Color("7fb27a"), Color("a77fc9")]
const BOOKS := [Color("b5544a"), Color("4f7a9a"), Color("6f9a5a"), Color("d9a24a"), Color("8a5aa0"), Color("c9b48a"), Color("5a4a7a")]

const NAMES := {"turtle": "慢慢館長", "rabbit": "派派兔", "gopher": "派派鼠"}
const BUBBLE_H := {"turtle": 1.4, "rabbit": 1.6, "gopher": 1.3}
const LINES := {
	"turtle": ["慢慢來，比較快。", "你覺得呢？先猜，再看。", "一個概念一本書，都在右邊的書櫃。", "左邊是閱讀教室，派派兔常在那裡。", "樓上還在整理，以後再帶你上去。"],
	"rabbit": ["歡迎光臨！我在借書櫃台打工～", "小提示：卡住的時候，先把程式一行一行唸出來看看！", "小提示：print() 的括號和引號要成對喔～", "我只能給小提示啦，要弄懂就上樓梯去問館長！", "館長是我的老師，他講得最清楚。"],
	"gopher": ["好高的圖書館！", "書好多喔……"],
}

## 點得到的東西：id → {name, pos, text, side("out"/"in"), act}
var hotspots: Dictionary = {}
var npcs: Dictionary = {}
var walls: Dictionary = {}   # "N"/"S"/"E"/"W" → Node3D（室內時，靠鏡頭那面會藏起來）
var roof: Node3D             # 屋頂、圓頂：室內時藏起來
var upper: Node3D            # 柱子上半段、拱肋、吊燈：室內時藏起來，才不會擋住鏡頭
var inside := false
var built := false
var _line_i: Dictionary = {}
## 很多小方塊（書、彩色玻璃、石板）合併成 MultiMesh：key → {parent, kind, mesh, xf[], col[]}
var _batches: Dictionary = {}
var _unit_box := BoxMesh.new()
var _unit_prism := PrismMesh.new()
## 點地板讓派派鼠走過去：0.5 公尺一格的找路網格（室內和前庭在同一張網格，但中間被牆隔開）
const CELL := 0.5
const NAV_X0 := -24.0
const NAV_Z0 := -18.0
const NAV_W := 96      # x -24..24
const NAV_H := 130     # z -18..47
const STEPS_Z0 := Z_S + WALL_T + 0.3   # 大門外第一階的中心
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
	roof = _group("Roof")
	upper = _group("Upper")
	_ground_and_forecourt()
	_shell()
	_facade()
	_dome()
	_floor()
	_pillars_and_galleries()
	_hall()
	_counter_and_platform()
	_stairs()
	_reading_room()
	_bookshelves()
	_flush_batches()
	_build_nav()
	built = true
	_spawn("turtle", Vector3(0, Y_IN + PLAT_H, -14.0), "S")
	_spawn("rabbit", Vector3(-1.6, Y_IN, -8.75), "S")   # 派派兔在借書櫃台後面打工
	_spawn("gopher", Vector3(1.2, 0, 30.0), "N")
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


## 合併繪製的方塊／三角柱。kind："lit"（一般受光）或 "glow"（彩色玻璃、自己會亮）
func _inst(parent: Node3D, kind: String, base: Transform3D, center: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, prism: bool = false) -> void:
	var key := "%d|%s|%s" % [parent.get_instance_id(), kind, prism]
	if not _batches.has(key):
		_batches[key] = {"parent": parent, "kind": kind, "mesh": _unit_prism if prism else _unit_box, "xf": [], "col": []}
	var b := Basis.from_euler(rot * PI / 180.0) * Basis.from_scale(size)
	_batches[key].xf.append(base * Transform3D(b, center))
	_batches[key].col.append(color)


func _flush_batches() -> void:
	var lit := StandardMaterial3D.new()
	lit.vertex_color_use_as_albedo = true
	lit.roughness = 0.85
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
		mmi.material_override = glow if b.kind == "glow" else lit
		(b.parent as Node3D).add_child(mmi)
	_batches.clear()


func _glb(parent: Node3D, file: String, pos: Vector3, size: float, yaw: float = 0.0) -> Node3D:
	if not ResourceLoader.exists(file):
		return null
	var n := Models.glb(file)
	var wrap := Node3D.new()
	wrap.add_child(n)
	Models.fit(n, Vector3(size, size, size))
	wrap.position = pos
	wrap.rotation_degrees.y = yaw
	parent.add_child(wrap)
	return wrap


func _label(parent: Node3D, text: String, pos: Vector3, size: int = 64, color: Color = UIKit.INK, yaw: float = 0.0, px: float = 0.005) -> Label3D:
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


func _yaw_of(n: Vector3) -> float:
	return atan2(n.x, n.z)


## 尖拱窗（彩色玻璃）：長方形＋尖頂。n = 窗面朝向。
func _lancet(parent: Node3D, center: Vector3, w: float, h: float, n: Vector3, seed_i: int) -> void:
	var base := Transform3D(Basis(Vector3.UP, _yaw_of(n)), center)
	_inst(parent, "lit", base, Vector3.ZERO, Vector3(w + 0.3, h + 0.24, 0.08), STONE_DARK)
	_inst(parent, "lit", base, Vector3(0, h / 2 + w * 0.4 + 0.1, 0), Vector3(w + 0.3, w * 0.8, 0.08), STONE_DARK, Vector3.ZERO, true)
	var cols := 2
	var cw := w / cols
	var rows := maxi(2, int(round(h / cw)))
	var ch := h / rows
	for r in range(rows):
		for c in range(cols):
			var col: Color = GLASS[(r * 3 + c * 2 + seed_i) % GLASS.size()]
			_inst(parent, "glow", base, Vector3(-w / 2 + cw * (c + 0.5), -h / 2 + ch * (r + 0.5), 0.05), Vector3(cw - 0.07, ch - 0.07, 0.04), col)
	_inst(parent, "glow", base, Vector3(0, h / 2 + w * 0.36 + 0.05, 0.05), Vector3(w - 0.08, w * 0.72 - 0.08, 0.04), GLASS[(seed_i + 2) % GLASS.size()], Vector3.ZERO, true)


## 大圓花窗
func _rose(parent: Node3D, center: Vector3, r: float, n: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = center
	holder.rotation.y = _yaw_of(n)
	parent.add_child(holder)
	_m(holder, Models.cyl(r + 0.4, r + 0.4, 0.14), STONE_DARK, Vector3.ZERO, Vector3(90, 0, 0))
	_m(holder, Models.cyl(r, r, 0.16), Color("3f3a4a"), Vector3(0, 0, 0.02), Vector3(90, 0, 0), false)
	for k in range(16):
		var a := TAU * k / 16.0
		_m(holder, Models.cyl(r * 0.2, r * 0.2, 0.18), GLASS[k % GLASS.size()], Vector3(cos(a), sin(a), 0) * r * 0.72 + Vector3(0, 0, 0.04), Vector3(90, 0, 0), false, true)
	for k in range(8):
		var a := TAU * (k + 0.5) / 8.0
		_m(holder, Models.cyl(r * 0.15, r * 0.15, 0.18), GLASS[(k + 2) % GLASS.size()], Vector3(cos(a), sin(a), 0) * r * 0.4 + Vector3(0, 0, 0.05), Vector3(90, 0, 0), false, true)
	_m(holder, Models.cyl(r * 0.2, r * 0.2, 0.2), GOLD, Vector3(0, 0, 0.06), Vector3(90, 0, 0), false, true)


## 一排書（書背）：在 base 座標裡，沿 x 從 x0 排到 x1，底部 y、深度中心 z
func _book_row(parent: Node3D, base: Transform3D, x0: float, x1: float, y: float, z: float, rng: RandomNumberGenerator) -> void:
	var x := x0
	while x < x1 - 0.08:
		var bw := rng.randf_range(0.07, 0.14)
		var bh := rng.randf_range(0.3, 0.42)
		_inst(parent, "lit", base, Vector3(x + bw / 2, y + bh / 2, z), Vector3(bw - 0.012, bh, 0.26), BOOKS[rng.randi() % BOOKS.size()])
		x += bw


## 一座書櫃（背靠 base 的 -z，書背朝 +z）：寬 w、高 h、層數 shelves
func _bookcase(parent: Node3D, base: Transform3D, w: float, h: float, shelves: int, rng: RandomNumberGenerator, two_sided: bool = false) -> void:
	var d := 0.7 if two_sided else 0.4
	_inst(parent, "lit", base, Vector3(0, h / 2, 0), Vector3(w, h, d), WOOD)
	var gap := (h - 0.2) / shelves
	for face: float in ([-1.0, 1.0] if two_sided else [1.0]):
		for s in range(shelves):
			_book_row(parent, base, -w / 2 + 0.1, w / 2 - 0.1, 0.12 + s * gap, face * (d / 2 - 0.1), rng)


## 和教堂一樣的石牆：矮牆＋壓頂石，每隔幾公尺一根方柱
func _stone_wall(a: Vector3, b: Vector3, h: float = 1.3) -> void:
	var l := a.distance_to(b)
	var w := Node3D.new()
	w.position = (a + b) / 2
	w.rotation.y = atan2(b.x - a.x, b.z - a.z)
	add_child(w)
	var I := Transform3D.IDENTITY
	_inst(w, "lit", I, Vector3(0, h / 2, 0), Vector3(0.6, h, l), STONE)
	_inst(w, "lit", I, Vector3(0, h + 0.08, 0), Vector3(0.8, 0.16, l + 0.1), STONE_DARK)
	var n := maxi(1, int(l / 4.0))
	for k in range(n + 1):
		_inst(w, "lit", I, Vector3(0, (h + 0.4) / 2, -l / 2 + l * k / n), Vector3(0.85, h + 0.4, 0.85), STONE_DARK)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(a.x * 7 + a.z * 13 + b.z))
	for k in range(int(l / 2.0)):   # 石縫的青苔
		_inst(w, "lit", I, Vector3(rng.randf_range(-0.31, 0.31), rng.randf_range(0.1, h - 0.2), rng.randf_range(-l / 2, l / 2)), Vector3(0.02, 0.18, 0.5), Color("8fa86f"))


func _hot(id: String, name_: String, pos: Vector3, text: String, side: String, act: String = "say") -> void:
	hotspots[id] = {"name": name_, "pos": pos, "text": text, "side": side, "act": act}


# ---------------- 外圍：大廣場、老橡樹、日晷、路燈、鐵門 ----------------
func _ground_and_forecourt() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(320, 320)
	g.mesh = pm
	g.material_override = Models.mat(Color("8fae7a"), false)
	g.position = Vector3(0, -0.02, 10)
	add_child(g)
	var Z0 := Z_S + 4.6        # 台階下面
	var depth := GATE_Z - Z0
	_m(self, Models.box(46, 0.04, depth + 0.4), Color("a9b08a"), Vector3(0, 0.0, Z0 + depth / 2), Vector3.ZERO, false)
	# 石板（磨圓的舊石板，石縫長青苔）；中間一條淺色大道
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var stones := [Color("d8cfbd"), Color("cdc3ae"), Color("ddd5c4"), Color("c6bba4")]
	var I := Transform3D.IDENTITY
	for ix in range(46):
		for iz in range(int(depth)):
			var x := -22.5 + ix
			var col: Color = stones[rng.randi() % 4]
			if absf(x) < 2.6:
				col = Color("eee6d4").lerp(col, 0.25)
			_inst(self, "lit", I, Vector3(x + rng.randf_range(-0.05, 0.05), 0.03, Z0 + 0.5 + iz), Vector3(0.92, 0.05, 0.92), col, Vector3(0, rng.randf_range(-4, 4), 0))
	# 寬寬的台階：八階，往上到大門
	for k in range(8):
		var top := Y_IN - k * 0.15
		_m(self, Models.box(20.0 + k * 0.8, top, 0.55), STONE, Vector3(0, top / 2, Z_S + WALL_T + 0.3 + k * 0.55))
	# 一對石頭烏龜守門
	for sx: float in [-1.0, 1.0]:
		var base := Vector3(sx * 11.5, 0, Z_S + 6.0)
		_m(self, Models.box(2.4, 1.8, 2.4), STONE_DARK, base + Vector3(0, 0.9, 0))
		_m(self, Models.box(2.7, 0.3, 2.7), STONE_DARK, base + Vector3(0, 1.9, 0))
		var sh := _m(self, Models.sphere(1.0), Color("bdb39f"), base + Vector3(0, 2.6, 0.1))
		sh.scale = Vector3(1.0, 0.62, 1.15)
		_m(self, Models.sphere(0.4), Color("c9c0ad"), base + Vector3(0, 2.75, 1.25))
		for fx: float in [-1.0, 1.0]:
			for fz: float in [-1.0, 1.0]:
				_m(self, Models.sphere(0.24), Color("c9c0ad"), base + Vector3(fx * 0.7, 2.15, fz * 0.75), Vector3.ZERO, false)
		_hot("guard%d" % int(sx), "石頭烏龜", base + Vector3(0, 2.6, 0), "石頭烏龜，守著圖書館好幾百年了。", "out")
	# 老橡樹、長椅、花圃、修剪整齊的樹籬、路燈
	for sx: float in [-1.0, 1.0]:
		for tz: float in [24.0, 38.0]:
			_glb(self, KENNEY_NATURE % "tree_oak", Vector3(sx * 15.0, 0, tz), 10.0, sx * 40.0 + tz)
		_glb(self, KENNEY_NATURE % "tree_oak", Vector3(sx * 19.5, 0, 31.0), 8.0, sx * 70.0)
		for bz: float in [27.0, 35.0]:
			_glb(self, KENNEY_FURN % "bench", Vector3(sx * 6.5, 0.02, bz), 2.0, 90.0 * sx)
		for k in range(14):
			var flower: String = ["flower_redA", "flower_yellowA", "flower_purpleA"][k % 3]
			_glb(self, KENNEY_NATURE % flower, Vector3(sx * (9.0 + (k % 2) * 0.7), 0, 22.0 + k * 1.6), 0.8, k * 40.0)
		# 前庭四周的石牆（和教堂一樣的石頭）：派派鼠不能走出去
		_stone_wall(Vector3(sx * 23.0, 0, 17.0), Vector3(sx * 23.0, 0, GATE_Z + 0.3))
		_stone_wall(Vector3(sx * (X_HALF + 7.2), 0, 17.0), Vector3(sx * 23.0, 0, 17.0))
		_stone_wall(Vector3(sx * 5.2, 0, GATE_Z + 0.3), Vector3(sx * 23.0, 0, GATE_Z + 0.3))
		for lz: float in [22.0, 28.0, 34.0, 40.0]:
			var lp := Vector3(sx * 3.6, 0, lz)
			_m(self, Models.cyl(0.08, 0.12, 3.2), IRON, lp + Vector3(0, 1.6, 0), Vector3.ZERO, false)
			_m(self, Models.cyl(0.18, 0.12, 0.4), IRON, lp + Vector3(0, 3.3, 0), Vector3.ZERO, false)
			_m(self, Models.sphere(0.2), Color("ffd27a"), lp + Vector3(0, 3.35, 0), Vector3.ZERO, false, true)
	# 日晷（呼應「慢慢來」）：在圓形石台上
	var sd := Vector3(0, 0, 31.0)
	_m(self, Models.cyl(3.0, 3.2, 0.3), STONE_DARK, sd + Vector3(0, 0.15, 0))
	_m(self, Models.cyl(1.0, 1.3, 0.5), STONE_DARK, sd + Vector3(0, 0.55, 0))
	_m(self, Models.cyl(0.5, 0.6, 1.5), STONE, sd + Vector3(0, 1.5, 0))
	_m(self, Models.cyl(1.2, 1.2, 0.12), Color("e5dcc8"), sd + Vector3(0, 2.3, 0))
	for k in range(12):
		var a := TAU * k / 12.0
		_m(self, Models.box(0.06, 0.03, 0.26), Color("6a5a48"), sd + Vector3(cos(a) * 0.98, 2.37, sin(a) * 0.98), Vector3(0, -rad_to_deg(a) + 90, 0), false)
	var gn := PrismMesh.new()
	gn.size = Vector3(0.08, 0.7, 0.9)
	_m(self, gn, Color("8a7a5a"), sd + Vector3(0, 2.7, 0))
	_hot("sundial", "日晷", sd + Vector3(0, 2.4, 0), "日晷：太陽的影子告訴你現在幾點。慢慢來，比較快。", "out")
	# 拱形鐵門：兩根石柱、鐵花拱、木牌
	for sx: float in [-1.0, 1.0]:
		_m(self, Models.box(1.4, 5.6, 1.4), STONE, Vector3(sx * 4.4, 2.8, GATE_Z))
		_m(self, Models.box(1.7, 0.35, 1.7), STONE_DARK, Vector3(sx * 4.4, 5.75, GATE_Z))
		_m(self, Models.sphere(0.45), STONE_DARK, Vector3(sx * 4.4, 6.25, GATE_Z))
		var leaf := Node3D.new()
		leaf.position = Vector3(sx * 3.7, 0, GATE_Z)
		leaf.rotation_degrees.y = sx * 70.0
		add_child(leaf)
		for k in range(12):
			_m(leaf, Models.cyl(0.04, 0.04, 4.0), IRON, Vector3(-sx * (0.15 + k * 0.3), 2.05, 0), Vector3.ZERO, false)
		for ry: float in [0.4, 2.0, 3.8]:
			_m(leaf, Models.box(3.6, 0.1, 0.08), IRON, Vector3(-sx * 1.8, ry, 0), Vector3.ZERO, false)
	var arch := TorusMesh.new()
	arch.inner_radius = 3.5
	arch.outer_radius = 3.72
	var am := _m(self, arch, IRON, Vector3(0, 5.7, GATE_Z), Vector3(90, 0, 0), false)
	am.scale = Vector3(1, 1, 0.7)
	_m(self, Models.box(5.4, 1.1, 0.14), Color("c79a68"), Vector3(0, 7.3, GATE_Z + 0.05))
	_label(self, "派森圖書館", Vector3(0, 7.3, GATE_Z + 0.14), 72, Color("4a3020"), 0.0, 0.011)
	_label(self, "派森圖書館", Vector3(0, 7.3, GATE_Z - 0.04), 72, Color("4a3020"), 180.0, 0.011)
	_hot("gate", "鐵門", Vector3(0, 3.0, GATE_Z), "回樹屋", "out", "town")


# ---------------- 教堂的牆、扶壁、飛扶壁、屋頂 ----------------
func _shell() -> void:
	var d := Z_S - Z_N
	var zc := (Z_S + Z_N) / 2.0
	_m(self, Models.box(X_HALF * 2 + 2.0, Y_IN, d + 2.0), STONE_DARK, Vector3(0, Y_IN / 2, zc))
	var win_z := [-14.0, -8.0, -2.0, 4.0, 10.0]
	for side in ["E", "W"]:
		var sx := 1.0 if side == "E" else -1.0
		var holder: Node3D = walls[side]
		var wx := sx * (X_HALF + WALL_T / 2)
		_m(holder, Models.box(WALL_T, WALL_H, d + WALL_T * 2), STONE, Vector3(wx, Y_IN + WALL_H / 2, zc))
		_m(holder, Models.box(WALL_T + 0.4, 0.5, d + WALL_T * 2 + 0.4), STONE_DARK, Vector3(wx, Y_IN + WALL_H, zc))
		var i := 0
		for z: float in win_z:
			for face: float in [-1.0, 1.0]:   # 裡面、外面都畫上玻璃
				var x := sx * (X_HALF + WALL_T / 2 + face * (WALL_T / 2 + 0.03))
				var n := Vector3(sx * face, 0, 0)
				_lancet(holder, Vector3(x, Y_IN + 3.6, z), 1.4, 3.0, n, i)
				_lancet(holder, Vector3(x, Y_IN + 9.4, z), 1.2, 2.2, n, i + 1)
				_lancet(holder, Vector3(x, Y_IN + 14.4, z), 1.2, 2.2, n, i + 2)
				_lancet(holder, Vector3(x, Y_IN + 19.8, z), 1.4, 2.8, n, i + 3)
			i += 1
		# 扶壁＋飛扶壁（外面）：牆邊的扶壁、外面一排石墩、斜斜的石拱撐住高牆，石墩上有小尖塔
		for bz: float in [-17.0, -11.0, -5.0, 1.0, 7.0, 13.0]:
			_m(holder, Models.box(1.4, WALL_H + 1.0, 1.2), STONE_DARK, Vector3(sx * (X_HALF + WALL_T + 0.7), Y_IN + (WALL_H + 1.0) / 2, bz))
			var px := sx * (X_HALF + 6.0)
			_m(holder, Models.box(1.6, 17.0, 1.4), STONE_DARK, Vector3(px, 8.5, bz))
			_m(holder, Models.cyl(0.0, 0.9, 3.4), SLATE, Vector3(px, 18.7, bz))
			_m(holder, Models.sphere(0.25), GOLD, Vector3(px, 20.5, bz), Vector3.ZERO, false)
			var a := Vector3(sx * (X_HALF + WALL_T + 1.2), Y_IN + WALL_H - 3.0, bz)
			var b := Vector3(px - sx * 0.6, 15.0, bz)
			var fb := _m(holder, Models.box(0.7, 0.9, a.distance_to(b)), STONE, (a + b) / 2, Vector3.ZERO)
			fb.look_at_from_position((a + b) / 2, b, Vector3.UP)
	# 北牆：高處一個大圓花窗（在館長平台上面）
	var nh: Node3D = walls["N"]
	_m(nh, Models.box(X_HALF * 2 + WALL_T * 2, WALL_H, WALL_T), STONE, Vector3(0, Y_IN + WALL_H / 2, Z_N - WALL_T / 2))
	_rose(nh, Vector3(0, Y_IN + 19.0, Z_N + 0.04), 3.6, Vector3(0, 0, 1))
	_rose(nh, Vector3(0, Y_IN + 19.0, Z_N - WALL_T - 0.04), 3.6, Vector3(0, 0, -1))
	var gable := PrismMesh.new()
	gable.size = Vector3(X_HALF * 2 + WALL_T * 2, 10.0, WALL_T)
	_m(nh, gable, STONE, Vector3(0, Y_IN + WALL_H + 5.0, Z_N - WALL_T / 2))
	# 屋頂：深色石板瓦的雙坡屋頂，屋脊上一排小尖塔
	var pm := PrismMesh.new()
	pm.size = Vector3(X_HALF * 2 + 2.4, 10.0, d + 1.6)
	_m(roof, pm, SLATE, Vector3(0, Y_IN + WALL_H + 5.0, zc))
	for z: float in [-15.0, -10.0, 6.0, 11.0]:
		_m(roof, Models.cyl(0.0, 0.5, 2.6), SLATE, Vector3(0, Y_IN + WALL_H + 11.2, z))
		_m(roof, Models.sphere(0.18), GOLD, Vector3(0, Y_IN + WALL_H + 12.6, z), Vector3.ZERO, false)


# ---------------- 中央的大圓頂（世界奇觀的地標） ----------------
func _dome() -> void:
	var c := Vector3(0, Y_IN + WALL_H + 3.0, -2.0)
	var drum := _m(roof, Models.cyl(6.4, 6.6, 9.0), STONE, c + Vector3(0, 4.5, 0))
	drum.mesh.radial_segments = 16
	_m(roof, Models.cyl(7.0, 7.0, 0.6), STONE_DARK, c + Vector3(0, 9.2, 0))
	for k in range(16):
		var a := TAU * (k + 0.5) / 16.0
		var n := Vector3(sin(a), 0, cos(a))
		_lancet(roof, c + n * 6.55 + Vector3(0, 4.4, 0), 0.9, 3.6, n, k)
	var dm := _m(roof, Models.sphere(6.6), Color("7d8aa0"), c + Vector3(0, 9.4, 0))
	dm.scale = Vector3(1, 1.15, 1)
	for k in range(8):   # 圓頂上的金色肋
		var a := TAU * k / 8.0
		var rib := TorusMesh.new()
		rib.inner_radius = 6.55
		rib.outer_radius = 6.8
		var ri := _m(roof, rib, GOLD, c + Vector3(0, 9.4, 0), Vector3(0, rad_to_deg(a), 90), false)
		ri.scale = Vector3(1.15, 1, 1)
	_m(roof, Models.cyl(1.3, 1.5, 3.4), STONE, c + Vector3(0, 17.7, 0))
	for k in range(6):
		var a := TAU * k / 6.0
		_m(roof, Models.box(0.4, 1.6, 0.1), Color("ffe9a8"), c + Vector3(sin(a) * 1.42, 17.8, cos(a) * 1.42), Vector3(0, rad_to_deg(a), 0), false, true)
	_m(roof, Models.cyl(0.0, 1.5, 3.0), Color("7d8aa0"), c + Vector3(0, 20.9, 0))
	_m(roof, Models.sphere(0.45), GOLD, c + Vector3(0, 22.7, 0), Vector3.ZERO, false, true)
	_m(roof, Models.cyl(0.06, 0.06, 2.0), GOLD, c + Vector3(0, 23.9, 0), Vector3.ZERO, false)


# ---------------- 正面：三座拱門、雕像迴廊、大圓花窗、兩座鐘塔 ----------------
func _facade() -> void:
	var sh: Node3D = walls["S"]
	var zf := Z_S + WALL_T / 2
	var front := zf + WALL_T / 2
	_m(sh, Models.box(X_HALF * 2 + WALL_T * 2, WALL_H, WALL_T), STONE, Vector3(0, Y_IN + WALL_H / 2, zf))
	var gable := PrismMesh.new()
	gable.size = Vector3(X_HALF * 2 + WALL_T * 2, 10.0, WALL_T)
	_m(sh, gable, STONE, Vector3(0, Y_IN + WALL_H + 5.0, zf))
	_m(sh, Models.cyl(0.0, 0.5, 3.0), STONE_DARK, Vector3(0, Y_IN + WALL_H + 11.2, zf))
	_m(sh, Models.sphere(0.4), GOLD, Vector3(0, Y_IN + WALL_H + 12.9, zf), Vector3.ZERO, false, true)
	_rose(sh, Vector3(0, Y_IN + 18.6, front + 0.05), 4.4, Vector3(0, 0, 1))
	_rose(sh, Vector3(0, Y_IN + 18.6, zf - WALL_T / 2 - 0.05), 4.4, Vector3(0, 0, -1))
	for sx: float in [-1.0, 1.0]:
		_lancet(sh, Vector3(sx * 9.0, Y_IN + 18.2, front + 0.03), 1.4, 4.0, Vector3(0, 0, 1), 2 + int(sx))
		_lancet(sh, Vector3(sx * 9.0, Y_IN + 18.2, zf - WALL_T / 2 - 0.03), 1.4, 4.0, Vector3(0, 0, -1), 2 + int(sx))
	# 雕像迴廊：一排小壁龕，每格站著一位古代學者
	_m(sh, Models.box(X_HALF * 2, 0.4, 0.8), STONE_DARK, Vector3(0, Y_IN + 11.4, front + 0.3))
	_m(sh, Models.box(X_HALF * 2, 0.4, 0.8), STONE_DARK, Vector3(0, Y_IN + 14.6, front + 0.3))
	var robes := [Color("d6cdb9"), Color("cfc6b2"), Color("dbd3c1")]
	for k in range(11):
		var x := -11.0 + k * 2.2
		_m(sh, Models.box(1.5, 2.8, 0.12), Color("a69a82"), Vector3(x, Y_IN + 13.0, front + 0.02), Vector3.ZERO, false)
		_m(sh, Models.cyl(0.22, 0.38, 2.0), robes[k % 3], Vector3(x, Y_IN + 12.6, front + 0.35))
		_m(sh, Models.sphere(0.24), robes[(k + 1) % 3], Vector3(x, Y_IN + 13.85, front + 0.35))
	# 三座拱門：中間的大門可以進去，兩側是裝飾的小門
	for p in [[0.0, 3.0, 9.0], [-8.5, 1.8, 6.0], [8.5, 1.8, 6.0]]:
		var px: float = p[0]
		var r: float = p[1]
		var ph: float = p[2]
		for j in range(3):   # 一圈一圈往裡縮的拱門框
			var rr := r + 1.2 - j * 0.4
			_m(sh, Models.box(rr * 2, ph - r, 0.3), [STONE_DARK, STONE, STONE_DARK][j], Vector3(px, Y_IN + (ph - r) / 2, front + 0.15 + j * 0.0 - j * 0.05 + 0.3 - j * 0.1))
			_m(sh, Models.cyl(rr, rr, 0.3), [STONE_DARK, STONE, STONE_DARK][j], Vector3(px, Y_IN + ph - r, front + 0.45 - j * 0.15), Vector3(90, 0, 0))
		for dsx: float in [-1.0, 1.0]:
			_m(sh, Models.box(r - 0.06, ph - r, 0.16), WOOD, Vector3(px + dsx * r / 2, Y_IN + (ph - r) / 2, front + 0.55))
			for ry: float in [0.2, 0.5, 0.8]:
				_m(sh, Models.box(r - 0.3, 0.12, 0.05), IRON, Vector3(px + dsx * r / 2, Y_IN + (ph - r) * ry, front + 0.65), Vector3.ZERO, false)
		_m(sh, Models.cyl(r - 0.05, r - 0.05, 0.16), Color("e6dcc6"), Vector3(px, Y_IN + ph - r, front + 0.55), Vector3(90, 0, 0))
		for bsx: float in [-1.0, 1.0]:   # 半圓浮雕：一本打開的書
			_m(sh, Models.box(r * 0.6, r * 0.42, 0.08), Color("fffaf0"), Vector3(px + bsx * r * 0.32, Y_IN + ph - r + r * 0.32, front + 0.66), Vector3(0, bsx * -12, bsx * -8))
	_m(sh, Models.cyl(0.14, 0.14, 0.08), GOLD, Vector3(-0.4, Y_IN + 3.0, front + 0.66), Vector3(90, 0, 0), false)
	_m(sh, Models.cyl(0.14, 0.14, 0.08), GOLD, Vector3(0.4, Y_IN + 3.0, front + 0.66), Vector3(90, 0, 0), false)
	_hot("door_out", "大門", Vector3(0, Y_IN + 3.0, front + 0.7), "走進圖書館", "out", "enter")
	# 兩座鐘塔：很高的方塔、鐘樓、尖頂、四角小尖塔、風向雞
	for sx: float in [-1.0, 1.0]:
		var tx := sx * (X_HALF + 3.6)
		var tz := Z_S - 0.6
		var th := 36.0
		_m(sh, Models.box(7.2, th, 7.2), STONE, Vector3(tx, th / 2, tz))
		for lv: float in [10.0, 20.0, 28.0]:
			_m(sh, Models.box(7.6, 0.5, 7.6), STONE_DARK, Vector3(tx, lv, tz))
		for row in range(3):
			for face: float in [-1.0, 1.0]:
				_lancet(sh, Vector3(tx, 4.8 + row * 7.2, tz + 3.62), 1.2, 3.0, Vector3(0, 0, 1), row + 1)
				_lancet(sh, Vector3(tx + face * 3.62, 4.8 + row * 7.2, tz), 1.2, 3.0, Vector3(face, 0, 0), row + 3)
		# 鐘樓：每面兩個深色的開口，看得到裡面的金色大鐘
		for face in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)]:
			for k: float in [-1.0, 1.0]:
				var side := Vector3(face.z, 0, -face.x)
				_m(sh, Models.box(1.2, 4.2, 0.1) if face.z != 0 else Models.box(0.1, 4.2, 1.2), Color("3f3a4a"), Vector3(tx, 32.0, tz) + face * 3.62 + side * k * 1.4, Vector3.ZERO, false)
		_m(sh, Models.cyl(0.9, 1.5, 2.0), GOLD, Vector3(tx, 32.0, tz), Vector3.ZERO, false)
		var spire := _m(sh, Models.cyl(0.0, 4.4, 16.0), SLATE, Vector3(tx, th + 8.0, tz))
		spire.mesh.radial_segments = 8
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				_m(sh, Models.cyl(0.0, 0.6, 3.6), SLATE, Vector3(tx + cx * 3.2, th + 1.8, tz + cz * 3.2))
		_m(sh, Models.cyl(0.08, 0.08, 2.4), IRON, Vector3(tx, th + 17.0, tz), Vector3.ZERO, false)
		_m(sh, Models.box(1.0, 0.6, 0.1), GOLD, Vector3(tx + 0.3, th + 17.8, tz), Vector3.ZERO, false)
	# 常春藤：正面兩側爬上來；幾塊剝落的石頭
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ivy := [Color("6f9a5a"), Color("5f8a4f"), Color("7fa866")]
	var I := Transform3D.IDENTITY
	for sx: float in [-1.0, 1.0]:
		for k in range(70):
			var p := Vector3(sx * rng.randf_range(10.6, 13.2), Y_IN + pow(rng.randf(), 1.6) * 10.0, front + 0.08)
			var s := rng.randf_range(0.35, 0.7)
			_inst(sh, "lit", I, p, Vector3(s * 1.2, s, 0.12), ivy[k % 3], Vector3(0, 0, rng.randf_range(-30, 30)))
		for k in range(6):
			_inst(sh, "lit", I, Vector3(sx * rng.randf_range(4.0, 12.0), Y_IN + rng.randf_range(2.0, 22.0), front + 0.03), Vector3(rng.randf_range(0.5, 1.0), rng.randf_range(0.3, 0.6), 0.04), Color("c4b89d"))


# ---------------- 室內地板：石磚格子 ----------------
func _floor() -> void:
	_m(self, Models.box(X_HALF * 2, 0.04, Z_S - Z_N), Color("9c8c72"), Vector3(0, Y_IN - 0.01, (Z_S + Z_N) / 2), Vector3.ZERO, false)
	var cols := [Color("efe6d2"), Color("dccfb3")]
	var I := Transform3D.IDENTITY
	for ix in range(int(X_HALF * 2)):
		for iz in range(int(Z_S - Z_N)):
			_inst(self, "lit", I, Vector3(-X_HALF + ix + 0.5, Y_IN + 0.01, Z_N + iz + 0.5), Vector3(0.94, 0.04, 0.94), cols[(ix + iz) % 2])
	# 大廳的格子區：金色細框
	var g0 := GRID_ORIGIN
	var gw := float(GRID_SIZE.x)
	var gd := float(GRID_SIZE.y)
	for k: float in [0.0, 1.0]:
		_m(self, Models.box(gw + 0.1, 0.02, 0.08), Color("b8933f"), Vector3(g0.x + gw / 2, Y_IN + 0.04, g0.z + k * gd), Vector3.ZERO, false)
		_m(self, Models.box(0.08, 0.02, gd + 0.1), Color("b8933f"), Vector3(g0.x + k * gw, Y_IN + 0.04, g0.z + gd / 2), Vector3.ZERO, false)
	# 從大門到雕像的紅地毯（金邊）
	var cz := (Z_S + 6.2) / 2.0
	_m(self, Models.box(2.6, 0.03, Z_S - 6.2), Color("c9a24a"), Vector3(0, Y_IN + 0.035, cz), Vector3.ZERO, false)
	_m(self, Models.box(2.3, 0.04, Z_S - 6.2), RED, Vector3(0, Y_IN + 0.04, cz), Vector3.ZERO, false)


# ---------------- 柱子、上層迴廊（看得到很多層，但上不去）、吊燈 ----------------
func _pillars_and_galleries() -> void:
	var I := Transform3D.IDENTITY
	for sx: float in [-1.0, 1.0]:
		var side: String = "E" if sx > 0 else "W"
		for z: float in [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0]:
			var p := Vector3(sx * NAVE_X, Y_IN, z)
			_m(self, Models.box(1.4, 0.6, 1.4), STONE_DARK, p + Vector3(0, 0.3, 0))
			_m(self, Models.cyl(0.5, 0.55, 4.4), STONE_IN, p + Vector3(0, 0.6 + 2.2, 0))
			_m(self, Models.cyl(0.66, 0.66, 0.35), STONE_DARK, p + Vector3(0, 5.0, 0))   # 柱子中段的石環
			_m(upper, Models.cyl(0.46, 0.5, WALL_H - 5.6), STONE_IN, p + Vector3(0, 5.1 + (WALL_H - 5.6) / 2, 0))
			_m(upper, Models.box(1.3, 0.6, 1.3), STONE_DARK, p + Vector3(0, WALL_H - 0.3, 0))
			if sx > 0:   # 橫跨中殿的拱肋
				_m(upper, Models.box(NAVE_X * 2, 0.6, 0.6), STONE_DARK, Vector3(0, Y_IN + WALL_H - 0.3, z))
		_m(upper, Models.box(0.7, 0.8, 26.0), STONE_DARK, Vector3(sx * NAVE_X, Y_IN + WALL_H - 0.4, -2.5))
		# 沿著東西牆的窄迴廊（二、三、四樓）：地板、欄杆、靠牆的書櫃
		var holder: Node3D = walls[side]
		var gx: float = sx * (X_HALF - 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 30 + int(sx)
		for lv: float in GAL_LV:
			_m(holder, Models.box(2.0, 0.35, Z_S - Z_N), WOOD, Vector3(gx, Y_IN + lv, (Z_S + Z_N) / 2))
			_m(holder, Models.box(0.1, 0.1, Z_S - Z_N), WOOD_LIGHT, Vector3(gx - sx * 0.95, Y_IN + lv + 1.0, (Z_S + Z_N) / 2), Vector3.ZERO, false)
			var zz := Z_N + 0.4
			while zz < Z_S:
				_inst(holder, "lit", I, Vector3(gx - sx * 0.95, Y_IN + lv + 0.55, zz), Vector3(0.07, 0.9, 0.07), WOOD_LIGHT)
				zz += 0.6
			for bz: Vector2 in [Vector2(-11, 3.6), Vector2(-5, 3.6), Vector2(1, 3.6), Vector2(7, 3.6), Vector2(-16.4, 2.2), Vector2(12.6, 2.2)]:
				var base := Transform3D(Basis(Vector3.UP, -PI / 2 * sx), Vector3(sx * (X_HALF - 0.22), Y_IN + lv + 0.18, bz.x))
				_bookcase(holder, base, bz.y, 3.0, 5, rng)
	# 北牆的迴廊（二、三樓），館長平台上面
	var nh: Node3D = walls["N"]
	for lv: float in [GAL_LV[0], GAL_LV[1]]:
		_m(nh, Models.box(X_HALF * 2, 0.35, 2.0), WOOD, Vector3(0, Y_IN + lv, Z_N + 1.0))
		_m(nh, Models.box(X_HALF * 2, 0.1, 0.1), WOOD_LIGHT, Vector3(0, Y_IN + lv + 1.0, Z_N + 1.95), Vector3.ZERO, false)
		var xx := -X_HALF + 0.4
		while xx < X_HALF:
			_inst(nh, "lit", I, Vector3(xx, Y_IN + lv + 0.55, Z_N + 1.95), Vector3(0.07, 0.9, 0.07), WOOD_LIGHT)
			xx += 0.6
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = int(lv)
		for bx: float in [-9.5, -4.5, 4.5, 9.5]:
			_bookcase(nh, Transform3D(Basis(), Vector3(bx, Y_IN + lv + 0.18, Z_N + 0.22)), 4.0, 3.0, 5, rng2)
	# 三盞大吊燈
	for z: float in [-4.0, 2.0, 8.0]:
		_m(upper, Models.cyl(0.05, 0.05, 8.0), IRON, Vector3(0, Y_IN + WALL_H - 4.3, z), Vector3.ZERO, false)
		for rr: float in [1.6, 1.0]:
			var ring := TorusMesh.new()
			ring.inner_radius = rr - 0.1
			ring.outer_radius = rr
			_m(upper, ring, Color("6a5236"), Vector3(0, Y_IN + 15.6 + (1.6 - rr), z))
			var nk := 12 if rr > 1.2 else 8
			for k in range(nk):
				var a := TAU * k / nk
				var cp := Vector3(cos(a) * rr, Y_IN + 15.85 + (1.6 - rr), z + sin(a) * rr)
				_m(upper, Models.cyl(0.06, 0.06, 0.3), Color("fff3dc"), cp, Vector3.ZERO, false)
				_m(upper, Models.sphere(0.08), Color("ffd27a"), cp + Vector3(0, 0.22, 0), Vector3.ZERO, false, true)
	for z: float in [-10.0, -2.0, 6.0]:
		var ol := OmniLight3D.new()
		ol.position = Vector3(0, Y_IN + 11.0, z)
		ol.light_color = Color("ffd9a0")
		ol.light_energy = 1.4
		ol.omni_range = 16.0
		add_child(ol)


# ---------------- 大廳：哲學家雕像 ----------------
func _hall() -> void:
	var c := Vector3(0, Y_IN, 3.5)
	_m(self, Models.box(3.0, 0.4, 3.0), STONE_DARK, c + Vector3(0, 0.2, 0))
	_m(self, Models.box(2.2, 1.8, 2.2), STONE, c + Vector3(0, 1.3, 0))
	_m(self, Models.box(2.6, 0.25, 2.6), STONE_DARK, c + Vector3(0, 2.32, 0))
	_label(self, "初代大賢者\n知道自己不知道，\n是學習的開始。", c + Vector3(0, 1.35, 1.12), 34, Color("5a4a38"))
	# 初代大賢者（慢慢館長的老師、派派森林知識的起源）：石頭雕的老烏龜，一手捧書、一手指著天空
	var s := Node3D.new()
	s.position = c + Vector3(0, 2.44, 0)
	s.scale = Vector3.ONE * 1.9
	add_child(s)
	var stone := Color("cfc7b6")
	var shell := _m(s, Models.sphere(0.62), Color("c4bba8"), Vector3(0, 1.0, -0.22))
	shell.scale = Vector3(1.0, 1.05, 0.62)
	var body := _m(s, Models.cyl(0.42, 0.55, 1.3), stone, Vector3(0, 0.7, 0.05))
	body.scale = Vector3(1, 1, 0.85)
	_m(s, Models.sphere(0.36), stone, Vector3(0, 1.62, 0.12))
	var beard := _m(s, Models.cyl(0.18, 0.02, 0.6), Color("ddd6c8"), Vector3(0, 1.3, 0.38), Vector3(-8, 0, 0))
	beard.scale = Vector3(1.2, 1, 0.6)
	_m(s, Models.box(0.5, 0.36, 0.12), Color("bdb39f"), Vector3(-0.42, 0.95, 0.42), Vector3(10, 30, 0))
	_m(s, Models.cyl(0.08, 0.1, 0.6), stone, Vector3(0.5, 1.55, 0.18), Vector3(0, 0, -25))
	_m(s, Models.sphere(0.1), stone, Vector3(0.63, 1.85, 0.18))
	_m(s, Models.cyl(0.03, 0.04, 0.22), stone, Vector3(0.66, 2.0, 0.18), Vector3(0, 0, -10))
	_hot("statue", "初代大賢者像", c + Vector3(0, 4.5, 0), "這是我的老師，初代大賢者。派派森林所有的知識，都是從他開始的。底座刻著「知道自己不知道，是學習的開始。」", "in")
	_hot("door_in", "大門", Vector3(0, Y_IN + 2.0, Z_S - 0.4), "回前庭", "in", "exit")


# ---------------- 借書櫃台＋館長平台 ----------------
func _counter_and_platform() -> void:
	var cz := -7.8
	_m(self, Models.box(8.0, 1.05, 0.9), WOOD, Vector3(0, Y_IN + 0.52, cz))
	_m(self, Models.box(8.3, 0.1, 1.1), WOOD_LIGHT, Vector3(0, Y_IN + 1.1, cz))
	for k in range(7):
		_m(self, Models.box(0.9, 0.62, 0.04), Color("7a4c30"), Vector3(-3.3 + k * 1.1, Y_IN + 0.52, cz + 0.47), Vector3.ZERO, false)
	_glb(self, KENNEY_FURN % "books", Vector3(-2.6, Y_IN + 1.15, cz), 0.6, 20)
	_m(self, Models.box(0.45, 0.24, 0.3), Color("c9b48a"), Vector3(-1.2, Y_IN + 1.27, cz))      # 借書卡盒
	_m(self, Models.cyl(0.05, 0.07, 0.16), WOOD_LIGHT, Vector3(0.2, Y_IN + 1.23, cz), Vector3.ZERO, false)   # 印章
	_m(self, Models.sphere(0.06), RED, Vector3(0.2, Y_IN + 1.34, cz), Vector3.ZERO, false)
	_m(self, Models.cyl(0.02, 0.02, 0.38), GOLD, Vector3(1.8, Y_IN + 1.34, cz), Vector3.ZERO, false)       # 綠色檯燈
	_m(self, Models.cyl(0.07, 0.22, 0.15), Color("3f7a5a"), Vector3(1.8, Y_IN + 1.55, cz), Vector3.ZERO, true, true)
	_m(self, Models.sphere(0.09), GOLD, Vector3(3.0, Y_IN + 1.22, cz + 0.2))                      # 小鈴鐺
	_hot("counter", "借書櫃台", Vector3(0, Y_IN + 1.5, cz), "借書櫃台：借書、還書都在這裡登記。", "in")
	# 館長平台（開放空間）：比櫃台遠、高八階，前面一道寬樓梯、木欄杆
	var z0 := -12.6
	var z1 := Z_N + 0.3
	var top := Y_IN + PLAT_H
	_m(self, Models.box(10.4, PLAT_H, z0 - z1), Color("cbbd9f"), Vector3(0, Y_IN + PLAT_H / 2, (z0 + z1) / 2))
	_m(self, Models.box(10.2, 0.02, z0 - z1 - 0.2), Color("9a6a48"), Vector3(0, top + 0.01, (z0 + z1) / 2), Vector3.ZERO, false)
	var nst := 8
	for k in range(nst):
		var hh := PLAT_H * (k + 1) / nst
		_m(self, Models.box(3.0, hh, 0.35), STONE_IN, Vector3(0, Y_IN + hh / 2, z0 + 0.35 * (nst - k) - 0.175))
	for sx: float in [-1.0, 1.0]:   # 樓梯兩旁的石頭扶牆
		var a := Vector3(sx * 1.6, Y_IN + 0.6, z0 + 0.35 * nst)
		var b := Vector3(sx * 1.6, Y_IN + PLAT_H + 0.6, z0)
		var wall := _m(self, Models.box(0.25, 0.5, a.distance_to(b)), STONE_DARK, (a + b) / 2)
		wall.look_at_from_position((a + b) / 2, b, Vector3.UP)
	_m(self, Models.box(10.4, 0.25, 0.3), STONE_DARK, Vector3(0, top - 0.12, z0 + 0.1))   # 平台邊緣
	for sx: float in [-1.0, 1.0]:   # 平台兩側的石頭矮牆（不能從旁邊掉下去）
		_m(self, Models.box(0.35, 0.9, z0 - z1), STONE, Vector3(sx * 5.25, top + 0.45, (z0 + z1) / 2))
		_m(self, Models.box(0.5, 0.12, z0 - z1 + 0.1), STONE_DARK, Vector3(sx * 5.25, top + 0.96, (z0 + z1) / 2))
	var I := Transform3D.IDENTITY
	for sx: float in [-1.0, 1.0]:
		_m(self, Models.box(3.6, 0.1, 0.1), WOOD_LIGHT, Vector3(sx * 3.4, top + 0.9, z0 - 0.05), Vector3.ZERO, false)
		var xx := 1.6
		while xx < 5.2:
			_inst(self, "lit", I, Vector3(sx * xx, top + 0.45, z0 - 0.05), Vector3(0.07, 0.85, 0.07), WOOD_LIGHT)
			xx += 0.3
	# 大書桌（攤開的書、羽毛筆、墨水瓶）、高背椅、地球儀、燭台、背後的矮書櫃
	var dz := -15.4
	_m(self, Models.box(2.8, 0.08, 1.3), WOOD_LIGHT, Vector3(0, top + 0.82, dz))
	_m(self, Models.box(2.7, 0.78, 1.2), WOOD, Vector3(0, top + 0.39, dz))
	for sx: float in [-1.0, 1.0]:
		_m(self, Models.box(0.46, 0.03, 0.6), Color("fffaf0"), Vector3(sx * 0.24, top + 0.88, dz + 0.1), Vector3(0, 0, sx * -6), false)
	_m(self, Models.cyl(0.07, 0.08, 0.12), Color("2f3a5a"), Vector3(0.9, top + 0.92, dz - 0.2), Vector3.ZERO, false)
	_m(self, Models.cyl(0.01, 0.02, 0.42), Color("f4efe2"), Vector3(0.93, top + 1.08, dz - 0.2), Vector3(0, 0, -20), false)
	_m(self, Models.box(1.0, 0.1, 0.9), RED, Vector3(0, top + 0.52, dz - 1.1))
	_m(self, Models.box(1.0, 1.9, 0.14), WOOD, Vector3(0, top + 1.4, dz - 1.55))
	_m(self, Models.sphere(0.12), GOLD, Vector3(0, top + 2.4, dz - 1.55), Vector3.ZERO, false)
	_m(self, Models.cyl(0.06, 0.08, 1.0), WOOD, Vector3(-3.4, top + 0.5, -15.0), Vector3.ZERO, false)
	_m(self, Models.sphere(0.45), Color("6f9ac0"), Vector3(-3.4, top + 1.4, -15.0))
	_m(self, Models.sphere(0.25), Color("7fb27a"), Vector3(-3.25, top + 1.55, -14.65), Vector3.ZERO, false)
	_m(self, Models.cyl(0.05, 0.14, 1.7), GOLD, Vector3(3.4, top + 0.85, -15.0), Vector3.ZERO, false)
	for k in range(3):
		_m(self, Models.cyl(0.04, 0.04, 0.22), Color("fff3dc"), Vector3(3.2 + k * 0.2, top + 1.8, -15.0), Vector3.ZERO, false)
		_m(self, Models.sphere(0.045), Color("ffd27a"), Vector3(3.2 + k * 0.2, top + 1.96, -15.0), Vector3.ZERO, false, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for bx: float in [-3.4, 0.0, 3.4]:
		_bookcase(self, Transform3D(Basis(), Vector3(bx, top, Z_N + 0.6)), 3.2, 1.8, 2, rng)
	_hot("desk", "館長的書桌", Vector3(0, top + 1.3, dz), "館長的書桌：攤開的書、羽毛筆、墨水瓶。", "in")


# ---------------- 櫃台後面往上層的樓梯（紅龍圍起來） ----------------
func _stairs() -> void:
	var x0 := 7.2
	var x1 := 10.2
	var zs := -9.6
	var n := 16
	var rise: float = GAL_LV[0] / n
	var run := (zs - (Z_N + 1.0)) / n
	for k in range(n):
		var h := rise * (k + 1)
		_m(self, Models.box(x1 - x0, h, run), STONE_IN, Vector3((x0 + x1) / 2, Y_IN + h / 2, zs - run * (k + 0.5)))
	_m(self, Models.box(X_HALF - x0, 0.35, 2.0), STONE_IN, Vector3((x0 + X_HALF) / 2, Y_IN + GAL_LV[0], Z_N + 1.0))   # 樓梯頂的平台
	# 扶手：從樓梯口斜斜往上到二樓迴廊
	var a := Vector3(x0 - 0.05, Y_IN + 1.0, zs)
	var b := Vector3(x0 - 0.05, Y_IN + GAL_LV[0] + 1.0, zs - run * n)
	var rail := _m(self, Models.box(0.12, 0.12, a.distance_to(b)), WOOD_LIGHT, (a + b) / 2, Vector3.ZERO, false)
	rail.look_at_from_position((a + b) / 2, b, Vector3.UP)
	for k in range(0, n + 1, 2):
		var pp := a.lerp(b, float(k) / n)
		_m(self, Models.box(0.07, 1.0, 0.07), WOOD_LIGHT, pp - Vector3(0, 0.5, 0), Vector3.ZERO, false)
	# 紅龍：兩根金色柱子＋紅絨繩＋牌子
	var rz := zs + 0.5
	for xx: float in [x0 + 0.1, x1 - 0.1]:
		_m(self, Models.cyl(0.07, 0.14, 1.0), GOLD, Vector3(xx, Y_IN + 0.5, rz), Vector3.ZERO, false)
		_m(self, Models.sphere(0.1), GOLD, Vector3(xx, Y_IN + 1.04, rz), Vector3.ZERO, false)
	_m(self, Models.cyl(0.04, 0.04, x1 - x0 - 0.2), Color("b5303a"), Vector3((x0 + x1) / 2, Y_IN + 0.88, rz), Vector3(0, 0, 90), false)
	_m(self, Models.box(1.1, 0.46, 0.03), Color("fff3dc"), Vector3((x0 + x1) / 2, Y_IN + 0.6, rz + 0.03))
	_label(self, "整理中\n暫不開放", Vector3((x0 + x1) / 2, Y_IN + 0.6, rz + 0.05), 28, Color("8a2f2a"))
	_hot("stairs", "往上層的樓梯", Vector3((x0 + x1) / 2, Y_IN + 1.3, zs), "往上層的樓梯：整理中，暫不開放。", "in")


# ---------------- 左邊：閱讀教室 ----------------
func _reading_room() -> void:
	var bx := -X_HALF + 0.08
	_m(self, Models.box(0.1, 2.6, 5.4), WOOD, Vector3(bx, Y_IN + 3.0, 2.5))
	_m(self, Models.box(0.08, 2.3, 5.1), Color("3f4a3c"), Vector3(bx + 0.05, Y_IN + 3.0, 2.5), Vector3.ZERO, false)
	_label(self, "看 → 猜 → 改 → 寫", Vector3(bx + 0.11, Y_IN + 3.4, 2.5), 64, Color("f4efe2"), 90.0, 0.008)
	_label(self, "print(\"你好\")", Vector3(bx + 0.11, Y_IN + 2.6, 2.5), 48, Color("f2d06b"), 90.0, 0.008)
	# 四張長桌（沿 z），學生坐東邊、面向黑板
	for z: float in [-4.0, 0.5, 5.0, 9.5]:
		_m(self, Models.box(1.3, 0.08, 3.2), WOOD_LIGHT, Vector3(-10.0, Y_IN + 0.8, z))
		for dz: float in [-1.4, 1.4]:
			for dx: float in [-0.5, 0.5]:
				_m(self, Models.box(0.09, 0.78, 0.09), WOOD, Vector3(-10.0 + dx, Y_IN + 0.39, z + dz), Vector3.ZERO, false)
		_m(self, Models.box(0.45, 0.08, 3.0), WOOD, Vector3(-8.8, Y_IN + 0.48, z))
		for dz: float in [-1.2, 1.2]:
			_m(self, Models.box(0.34, 0.46, 0.09), WOOD, Vector3(-8.8, Y_IN + 0.23, z + dz), Vector3.ZERO, false)
		for lz: float in [-0.8, 0.8]:
			_m(self, Models.cyl(0.03, 0.03, 0.42), GOLD, Vector3(-10.35, Y_IN + 1.05, z + lz), Vector3.ZERO, false)
			_m(self, Models.cyl(0.08, 0.2, 0.14), Color("3f7a5a"), Vector3(-10.35, Y_IN + 1.28, z + lz), Vector3.ZERO, true, true)
		_m(self, Models.box(0.44, 0.03, 0.56), Color("fffaf0"), Vector3(-9.8, Y_IN + 0.86, z), Vector3(0, 10, 0), false)
	_label(self, "閱讀教室", Vector3(-9.5, Y_IN + 5.2, Z_S - 0.05), 96, Color("5a4a38"), 180.0, 0.01)
	_hot("classroom", "閱讀教室", Vector3(-10.0, Y_IN + 1.8, 2.5), "閱讀教室：讀書照「看 → 猜 → 改 → 寫」一步一步來。", "in")


# ---------------- 右邊：一排排的高書櫃 ----------------
func _bookshelves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var i := 0
	for z: float in [-4.5, -1.5, 1.5, 4.5, 7.5, 10.5]:
		_bookcase(self, Transform3D(Basis(), Vector3(10.0, Y_IN, z)), 5.0, 4.4, 7, rng, true)
		# 書櫃側面（朝大廳）的章節牌
		_m(self, Models.box(0.05, 0.42, 0.62), Color("e9d9b0"), Vector3(7.47, Y_IN + 3.6, z))
		_label(self, "第 %d 章" % (i + 1), Vector3(7.43, Y_IN + 3.6, z), 48, Color("5a3d2b"), -90.0)
		i += 1
	# 可以滑動的梯子
	var lad := Node3D.new()
	lad.position = Vector3(10.6, Y_IN, 0.05)
	lad.rotation_degrees.x = -12
	add_child(lad)
	for sx: float in [-0.35, 0.35]:
		_m(lad, Models.box(0.07, 4.6, 0.07), WOOD_LIGHT, Vector3(sx, 2.3, 0), Vector3.ZERO, false)
	for k in range(13):
		_m(lad, Models.box(0.7, 0.05, 0.05), WOOD_LIGHT, Vector3(0, 0.3 + k * 0.33, 0), Vector3.ZERO, false)
	# 窗邊的閱讀椅
	_glb(self, KENNEY_FURN % "loungeSofa", Vector3(11.4, Y_IN, 12.9), 1.3, 180)
	_glb(self, KENNEY_FURN % "pottedPlant", Vector3(8.6, Y_IN, 13.0), 1.1)
	_label(self, "書櫃區", Vector3(9.8, Y_IN + 5.2, Z_S - 0.05), 96, Color("5a4a38"), 180.0, 0.01)
	_hot("shelves", "書櫃", Vector3(10.0, Y_IN + 2.4, 1.5), "書櫃：一個概念一本書，照章節排好。", "in")


# ---------------- 室內／室外 ----------------
func set_inside(v: bool) -> void:
	inside = v
	roof.visible = not v
	upper.visible = not v
	for s in walls:
		walls[s].visible = true
	var g: GopherActor = npcs.get("gopher")
	if g:
		_walk_serial += 1
		if _walk_tween:
			_walk_tween.kill()
		g.moving = false
		g.position = Vector3(0.0, Y_IN, Z_S - 1.0) if v else Vector3(0.0, 0.0, 26.0)
		g.face("N" if v else "S")
		g.model.rotation.y = g.target_yaw


## 鏡頭焦點和距離（室內／室外）
func view_focus() -> Vector3:
	return global_transform * (Vector3(0, Y_IN + 1.0, -9.5) if inside else Vector3(0, 4.0, 21.0))


## 和家裡差不多的距離：人物看得清楚，教堂顯得很大
func view_distance() -> float:
	return 15.0 if inside else 24.0


## 室內：靠鏡頭那一側的牆（連同迴廊）藏起來，才看得到裡面
func update_cutaway(cam_pos: Vector3) -> void:
	if not inside:
		return
	var center := global_transform * Vector3(0, 0, (Z_S + Z_N) / 2)
	var to_cam := cam_pos - center
	var normals := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0), "E": Vector3(1, 0, 0)}
	for side in walls:
		var n: Vector3 = normals[side]
		var half: float = ((Z_S - Z_N) if side in ["N", "S"] else X_HALF * 2) / 2.0
		walls[side].visible = to_cam.dot(n) < half * 0.6


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
	if not inside:
		return ""   # 館長和派派兔都在裡面
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


## 滑鼠指到哪個可以點的東西（螢幕上 60 像素以內，只算目前這一側：室外／室內）
func hotspot_at(screen_pos: Vector2, cam: Camera3D) -> String:
	var best := ""
	var best_d := 60.0
	for id in hotspots:
		var h: Dictionary = hotspots[id]
		if (h.side == "in") != inside:
			continue
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


## 點了某個東西：室內由館長說明，室外由派派鼠說
func describe(id: String) -> void:
	var h: Dictionary = hotspots.get(id, {})
	if h.is_empty():
		return
	var who := "turtle" if inside else "gopher"
	var a: GopherActor = npcs.get(who)
	if a:
		a.say(h.text, "say")


# ---------------- 點地板走路（找路網格） ----------------
## 地面高度：館長平台、平台前的樓梯、大門外的台階
func ground_y(x: float, z: float) -> float:
	if z > Z_S:   # 前庭：台階往下到廣場
		return clampf(Y_IN - (z - STEPS_Z0) / 0.55 * 0.15, 0.0, Y_IN)
	if absf(x) < 5.2 and z <= -12.6:
		return Y_IN + PLAT_H
	if absf(x) < 1.5 and z < -9.8:
		return Y_IN + PLAT_H * clampf((-9.8 - z) / 2.8, 0.0, 1.0)
	return Y_IN


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - NAV_X0) / CELL)), 0, NAV_W - 1), clampi(int(floor((p.z - NAV_Z0) / CELL)), 0, NAV_H - 1))


func _cell_center(c: Vector2i) -> Vector3:
	var x := NAV_X0 + (c.x + 0.5) * CELL
	var z := NAV_Z0 + (c.y + 0.5) * CELL
	return Vector3(x, ground_y(x, z), z)


func _block_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	var a := _cell_of(Vector3(minf(x0, x1), 0, minf(z0, z1)))
	var b := _cell_of(Vector3(maxf(x0, x1) - 0.001, 0, maxf(z0, z1) - 0.001))
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			nav.set_point_solid(Vector2i(cx, cz), true)


func _block_round(x: float, z: float, r: float) -> void:
	_block_rect(x - r, z - r, x + r, z + r)


func _build_nav() -> void:
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, NAV_W, NAV_H)
	nav.cell_size = Vector2(CELL, CELL)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	# 先全部擋住，再打開能走的地方（室內、前庭、台階）
	nav.fill_solid_region(nav.region, true)
	nav.fill_solid_region(Rect2i(_cell_of(Vector3(-X_HALF + 0.4, 0, Z_N + 0.4)), _cell_of(Vector3(X_HALF - 0.4, 0, Z_S - 0.4)) - _cell_of(Vector3(-X_HALF + 0.4, 0, Z_N + 0.4))), false)
	nav.fill_solid_region(Rect2i(_cell_of(Vector3(-9.6, 0, Z_S + WALL_T + 0.1)), _cell_of(Vector3(9.6, 0, 19.4)) - _cell_of(Vector3(-9.6, 0, Z_S + WALL_T + 0.1))), false)
	nav.fill_solid_region(Rect2i(_cell_of(Vector3(-22.4, 0, 17.6)), _cell_of(Vector3(22.4, 0, GATE_Z - 0.3)) - _cell_of(Vector3(-22.4, 0, 17.6))), false)
	# ---- 室內的擋路物 ----
	for sx: float in [-1.0, 1.0]:
		for z: float in [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0]:
			_block_round(sx * NAVE_X, z, 0.8)
	_block_rect(-1.8, 1.7, 1.8, 5.3)                    # 初代大賢者像
	_block_rect(-4.4, -8.4, 4.4, -7.2)                  # 借書櫃台
	_block_round(-1.6, -8.75, 0.5)                      # 派派兔
	_block_rect(-5.6, -12.75, -1.5, -9.8)               # 館長平台前面的高台（只能走中間的樓梯）
	_block_rect(1.5, -12.75, 5.6, -9.8)
	_block_rect(-5.6, -12.75, -1.5, -12.5)
	_block_rect(-5.6, Z_N, -5.0, -12.5)                 # 平台兩側的矮牆
	_block_rect(5.0, Z_N, 5.6, -12.5)
	_block_rect(-1.6, -16.2, 1.6, -14.6)                # 書桌
	_block_rect(-0.7, -17.2, 0.7, -16.3)                # 高背椅
	_block_round(-3.4, -15.0, 0.6)                      # 地球儀
	_block_round(3.4, -15.0, 0.5)                       # 燭台
	_block_rect(-5.2, Z_N, 5.2, -17.0)                  # 平台後面的矮書櫃
	_block_round(0.0, -14.0, 0.55)                      # 館長
	_block_rect(6.9, Z_N, 10.5, -9.0)                   # 往上層的樓梯（紅龍）
	for z: float in [-4.0, 0.5, 5.0, 9.5]:              # 閱讀教室的長桌和長椅
		_block_rect(-10.8, z - 1.7, -8.5, z + 1.7)
	_block_rect(-X_HALF, 0.0, -X_HALF + 0.5, 5.0)       # 黑板
	for z: float in [-4.5, -1.5, 1.5, 4.5, 7.5, 10.5]:  # 高書櫃
		_block_rect(7.4, z - 0.5, 12.7, z + 0.5)
	_block_rect(10.1, -0.6, 11.1, 0.7)                  # 梯子
	_block_round(11.4, 12.9, 1.0)                       # 閱讀椅
	_block_round(8.6, 13.0, 0.5)                        # 盆栽
	# ---- 前庭的擋路物 ----
	_block_rect(-X_HALF - 8.0, Z_S, -9.6, 19.4)         # 鐘塔前面
	_block_rect(9.6, Z_S, X_HALF + 8.0, 19.4)
	for sx: float in [-1.0, 1.0]:
		_block_rect(sx * 11.5 - 1.5, Z_S + 4.4, sx * 11.5 + 1.5, Z_S + 7.6)   # 石頭烏龜
		for tz: float in [24.0, 38.0]:
			_block_round(sx * 15.0, tz, 1.0)                                  # 老橡樹
		_block_round(sx * 19.5, 31.0, 1.0)
		for bz: float in [27.0, 35.0]:
			_block_rect(sx * 6.5 - 0.7, bz - 1.1, sx * 6.5 + 0.7, bz + 1.1)  # 長椅
		_block_rect(sx * 8.6, 21.4, sx * 10.2, 44.0)                          # 花圃
		for lz: float in [22.0, 28.0, 34.0, 40.0]:
			_block_round(sx * 3.6, lz, 0.3)                                   # 路燈
	_block_round(0.0, 31.0, 3.3)                        # 日晷


## 滑鼠指到的地板位置（打不到地板就回傳 null）
func floor_point(screen_pos: Vector2, cam: Camera3D) -> Variant:
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.y) < 0.001:
		return null
	var p := global_transform.affine_inverse() * o
	var dl := global_transform.basis.inverse() * d
	if inside:   # 先試館長平台的高度，不在平台上就用大廳地板
		var tp := (Y_IN + PLAT_H - p.y) / dl.y
		if tp > 0:
			var hp := p + dl * tp
			if absf(ground_y(hp.x, hp.z) - (Y_IN + PLAT_H)) < 0.05:
				return hp
	var t := ((Y_IN if inside else 0.0) - p.y) / dl.y
	if t <= 0:
		return null
	var hit := p + dl * t
	hit.y = ground_y(hit.x, hit.z)
	return hit


## 派派鼠走到某個點（找路、避開擋路的東西，平台和台階會跟著升降）
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
		var dist := g.position.distance_to(target)
		g.face_vector(Vector3(target.x - g.position.x, 0, target.z - g.position.z))
		_walk_tween = g.create_tween()
		_walk_tween.tween_method(func(f: float):
			var pp: Vector3 = g.position.lerp(target, f)
			pp.y = ground_y(pp.x, pp.z)
			g.position = pp, 0.0, 1.0, dist * 0.3)
		await _walk_tween.finished
		if my != _walk_serial:
			return
		g.position = target
	g.moving = false


## 離目標最近的能走的格子（點到桌子上，就走到桌邊）
func _nearest_open(c: Vector2i) -> Vector2i:
	if not nav.is_point_solid(c):
		return c
	for r in range(1, 12):
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
