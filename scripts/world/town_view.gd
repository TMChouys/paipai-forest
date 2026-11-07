class_name TownView
extends Node3D
## 派森小鎮・鎮中心：森林外的小廣場。北邊圖書館、西邊郵局、東邊市集，中間噴水池和任務公告欄，
## 南邊的小路通往派派森林。居民：慢慢館長（圖書館）、拍拍鳥（郵局）、狸老闆（市集）。
## 只是布景與對話，不在格子裡。大小約 16 × 12，中心 (8, 0, 6)。

const W := 16.0
const D := 12.0
const CENTER := Vector3(8, 0, 6)
const KENNEY_TOWN := "res://models/kenney/town/%s.glb"
const KENNEY_NATURE := "res://models/kenney/nature/%s.glb"
const KENNEY_FURN := "res://models/kenney/furniture/%s.glb"

const NAMES := {"gopher": "派派鼠", "tanuki": "狸老闆", "turtle": "慢慢館長", "crow": "拍拍鳥", "rabbit": "派派兔"}
const BUBBLE_H := {"gopher": 1.3, "tanuki": 1.45, "turtle": 1.4, "crow": 1.4, "rabbit": 1.6}
## 點居民會輪流說的話（一句 25 字以內）
const LINES := {
	"tanuki": ["歡迎光臨！今天橡實特價喔。", "每樣東西都有名字和價錢。", "學會整理清單，來幫我寫價目表吧！", "拍拍鳥的話，聽一半就好。"],
	"turtle": ["慢慢來，比較快。", "書和紀錄，都收在這裡。", "你住的樹屋，我很熟喔。", "那個箱子，學得越多就越打得開。"],
	"crow": ["嘎！歡迎來到鎮中心！", "聽說派派狼昨天又走錯岔路了！", "有新信，信箱的紅旗會舉起來。", "要寄信嗎？郵局隨時開著！"],
	"gopher": ["print(\"你好，鎮中心！\")", "好多新朋友！"],
	"rabbit": ["這裡的圖書館，我最喜歡了。", "慢慢逛，不用急喔。"],
}

var npcs: Dictionary = {}  # who → GopherActor
var _line_i: Dictionary = {}
var built := false


func build() -> void:
	for c in get_children():
		c.queue_free()
	npcs.clear()
	_ground()
	_library(Vector3(8, 0, 1.5))
	_post_office(Vector3(2.4, 0, 5.6))
	_market(Vector3(13.4, 0, 5.8))
	_plaza_props()
	_greenery()
	_spawn("turtle", Vector3(8.0, 0, 3.55), "S")
	_spawn("crow", Vector3(5.3, 0, 7.6), "S")
	_spawn("tanuki", Vector3(11.9, 0, 6.2), "W")
	_spawn("rabbit", Vector3(6.4, 0, 8.4), "N")
	_spawn("gopher", Vector3(8.0, 0, 9.0), "N")
	built = true


# ---------------- 小工具 ----------------
func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, line: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Models.mat(color, line)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


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


func _label(parent: Node3D, text: String, pos: Vector3, size: int = 64, color: Color = UIKit.INK) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font = UIKit.font_bold()
	lb.font_size = size
	lb.pixel_size = 0.005
	lb.modulate = color
	lb.outline_size = 0
	lb.position = pos
	lb.double_sided = false
	parent.add_child(lb)
	return lb


## 木頭招牌：一塊木板＋字
func _sign(parent: Node3D, text: String, pos: Vector3, width: float, color: Color = Color("c79a68")) -> void:
	_mesh(parent, Models.box(width, 0.42, 0.06), color, pos)
	_label(parent, text, pos + Vector3(0, 0, 0.035), 64, Color("4a3020"))


## 有木框（北歐／繪本木筋）的小房子：門朝 +z。回傳房子的 Node3D（可以再轉向）。
func _house(pos: Vector3, yaw: float, w: float, d: float, h: float, wall: Color, roof: Color, title: String) -> Node3D:
	var hn := Node3D.new()
	hn.position = pos
	hn.rotation_degrees.y = yaw
	add_child(hn)
	var timber := Color("8a6a4a")
	_mesh(hn, Models.box(w + 0.2, 0.25, d + 0.2), Color("b8ab95"), Vector3(0, 0.12, 0))  # 石頭地基
	_mesh(hn, Models.box(w, h, d), wall, Vector3(0, 0.25 + h / 2, 0))
	# 木筋：四個角柱＋上下橫樑＋正面兩條斜撐
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_mesh(hn, Models.box(0.14, h, 0.14), timber, Vector3(sx * w / 2, 0.25 + h / 2, sz * d / 2), Vector3.ZERO, false)
	for yy in [0.32, 0.25 + h - 0.05, 0.25 + h * 0.55]:
		_mesh(hn, Models.box(w + 0.04, 0.1, 0.06), timber, Vector3(0, yy, d / 2 + 0.02), Vector3.ZERO, false)
	# 屋頂（三角柱）：屋脊沿 x
	var pm := PrismMesh.new()
	pm.size = Vector3(d + 0.7, h * 0.62, w + 0.5)
	var rf := _mesh(hn, pm, roof, Vector3(0, 0.25 + h + h * 0.31, 0), Vector3(0, 90, 0))
	rf.name = "Roof"
	# 屋脊上的小煙囪
	_mesh(hn, Models.box(0.36, 0.7, 0.36), Color("b07a5a"), Vector3(w * 0.28, 0.25 + h + h * 0.4, -d * 0.15))
	# 門（拱門）
	var door_c := Color("8f5f3c")
	_mesh(hn, Models.box(0.9, 1.25, 0.08), door_c, Vector3(0, 0.25 + 0.62, d / 2 + 0.04))
	var arch := _mesh(hn, Models.cyl(0.45, 0.45, 0.08), door_c, Vector3(0, 0.25 + 1.25, d / 2 + 0.04), Vector3(90, 0, 0))
	arch.scale = Vector3(1, 1, 0.8)
	_mesh(hn, Models.sphere(0.05), Color("f2c14e"), Vector3(0.28, 0.25 + 0.65, d / 2 + 0.1), Vector3.ZERO, false)
	# 兩扇窗＋花箱
	for sx in [-1, 1]:
		var wx: float = sx * (w / 2 - 0.75)
		var wy := 0.25 + h * 0.55
		_mesh(hn, Models.box(0.7, 0.7, 0.06), Color("fff3dc"), Vector3(wx, wy, d / 2 + 0.03))
		_mesh(hn, Models.box(0.56, 0.56, 0.04), Color("9fc0c8"), Vector3(wx, wy, d / 2 + 0.06), Vector3.ZERO, false)
		_mesh(hn, Models.box(0.05, 0.56, 0.06), Color("fff3dc"), Vector3(wx, wy, d / 2 + 0.07), Vector3.ZERO, false)
		_mesh(hn, Models.box(0.8, 0.16, 0.2), Color("a8744f"), Vector3(wx, wy - 0.42, d / 2 + 0.12))
		for k in range(4):
			_mesh(hn, Models.sphere(0.07), [Color("e88b8b"), Color("f2d06b"), Color("b79ad9"), Color("f4a6a6")][k], Vector3(wx - 0.27 + k * 0.18, wy - 0.3, d / 2 + 0.14), Vector3.ZERO, false)
	# 招牌（門上方）
	_sign(hn, title, Vector3(0, 0.25 + h - 0.2, d / 2 + 0.12), 0.32 * title.length() + 0.4)
	return hn


# ---------------- 地面 ----------------
func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	g.mesh = pm
	g.material_override = Models.mat(Color("8fae7a"), false)
	g.position = CENTER + Vector3(0, -0.02, 0)
	add_child(g)
	# 圓形石板廣場
	var plaza := _mesh(self, Models.cyl(4.8, 4.8, 0.04), Color("e3d6bd"), CENTER + Vector3(0, 0.0, 0.4), Vector3.ZERO, false)
	plaza.scale = Vector3(1.15, 1, 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var stones := [Color("d6ccb8"), Color("cfc4ae"), Color("dcd3c1"), Color("c8bca4")]
	for i in range(90):
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 4.6
		var p := CENTER + Vector3(cos(a) * rr * 1.15, 0.025, 0.4 + sin(a) * rr * 0.95)
		var st := _mesh(self, Models.cyl(0.22, 0.24, 0.03), stones[i % 4], p, Vector3(0, rng.randf() * 90, 0), false)
		st.scale = Vector3(rng.randf_range(0.8, 1.4), 1, rng.randf_range(0.7, 1.1))
	# 往南的森林小路
	for i in range(8):
		_glb(self, KENNEY_NATURE % "path_stone", Vector3(8.0 + sin(i * 0.9) * 0.3, -0.05, 11.0 + i * 1.05), 1.0, i * 23.0)


# ---------------- 圖書館（北） ----------------
func _library(pos: Vector3) -> void:
	var h := _house(pos, 0, 4.8, 2.8, 2.9, Color("efe3c9"), Color("6f8f9a"), "圖書館")
	# 山牆上的圓窗
	_mesh(h, Models.cyl(0.42, 0.42, 0.08), Color("fff3dc"), Vector3(0, 3.55, 1.0), Vector3(90, 0, 0))
	_mesh(h, Models.cyl(0.32, 0.32, 0.1), Color("9fc0c8"), Vector3(0, 3.55, 1.02), Vector3(90, 0, 0), false)
	# 門口的書本標誌與台階
	_mesh(h, Models.box(0.34, 0.46, 0.08), Color("c96f5a"), Vector3(-1.75, 1.35, 1.6), Vector3(0, 0, 8))
	_mesh(h, Models.box(0.34, 0.46, 0.08), Color("6f9a8a"), Vector3(-1.45, 1.35, 1.6), Vector3(0, 0, -6), false)
	for i in range(2):
		_mesh(h, Models.box(1.6 - i * 0.3, 0.12, 0.45), Color("c9bba3"), Vector3(0, 0.06 + i * 0.12, 1.65 - i * 0.2))
	# 門口一疊書
	_glb(h, KENNEY_FURN % "books", Vector3(1.05, 0.0, 1.75), 0.5)


# ---------------- 郵局（西） ----------------
func _post_office(pos: Vector3) -> void:
	var h := _house(pos, 90, 3.2, 2.6, 2.4, Color("f0d9b5"), Color("b5654f"), "郵局")
	# 山牆上的大信封標誌
	_mesh(h, Models.box(0.9, 0.56, 0.06), Color("fffaf0"), Vector3(0, 3.05, 1.12))
	var flap := PrismMesh.new()
	flap.size = Vector3(0.9, 0.3, 0.04)
	_mesh(h, flap, Color("e9dcc2"), Vector3(0, 3.17, 1.16), Vector3(180, 0, 0), false)
	_mesh(h, Models.sphere(0.07), Color("c94f4a"), Vector3(0, 3.04, 1.18), Vector3.ZERO, false)
	# 門前的紅色郵筒
	var bx := pos + Vector3(1.9, 0, 1.1)
	_mesh(self, Models.cyl(0.24, 0.24, 1.0), Color("c95a4f"), bx + Vector3(0, 0.5, 0))
	_mesh(self, Models.sphere(0.24), Color("c95a4f"), bx + Vector3(0, 1.0, 0))
	_mesh(self, Models.box(0.26, 0.04, 0.1), Color("3b2a1e"), bx + Vector3(0.2, 0.82, 0), Vector3(0, 90, 0), false)
	# 一袋信
	_mesh(self, Models.sphere(0.25), Color("d8c7a6"), pos + Vector3(1.75, 0.22, -0.9))
	_mesh(self, Models.box(0.2, 0.03, 0.14), Color("fffaf0"), pos + Vector3(1.75, 0.45, -0.9), Vector3(0, 20, 15), false)


# ---------------- 市集（東） ----------------
func _market(pos: Vector3) -> void:
	_glb(self, KENNEY_TOWN % "stall-red", pos + Vector3(0, 0, -1.2), 2.2, -90)
	_glb(self, KENNEY_TOWN % "stall-red", pos + Vector3(0.2, 0, 1.4), 2.2, -90)
	_glb(self, KENNEY_TOWN % "cart", pos + Vector3(1.0, 0, 3.4), 1.6, -60)
	# 一箱一箱的貨：橡實、胡蘿蔔、蘋果
	var goods := [["acorn", Vector3(-1.0, 0, -0.1)], ["carrot", Vector3(-1.0, 0, 0.75)], ["apple", Vector3(-0.9, 0, 2.55)]]
	for gd in goods:
		var p: Vector3 = pos + gd[1]
		_mesh(self, Models.box(0.62, 0.38, 0.62), Color("c8955f"), p + Vector3(0, 0.19, 0))
		for k in range(5):
			var o := Vector3((k % 3 - 1) * 0.16, 0.42, -0.1 if k < 3 else 0.12)
			match gd[0]:
				"acorn":
					_mesh(self, Models.sphere(0.08), Color("a8743f"), p + o, Vector3.ZERO, false)
					_mesh(self, Models.sphere(0.06), Color("6e4a2e"), p + o + Vector3(0, 0.06, 0), Vector3.ZERO, false)
				"carrot":
					_mesh(self, Models.cyl(0.05, 0.0, 0.26), Color("e8894a"), p + o + Vector3(0, 0.02, 0), Vector3(80, k * 30, 0), false)
				"apple":
					_mesh(self, Models.sphere(0.085), Color("d9605a"), p + o, Vector3.ZERO, false)
	# 價目表（給以後的字典任務）
	var board := Vector3(pos.x - 1.4, 0, pos.z + 1.55)
	for sx in [-1, 1]:
		_mesh(self, Models.box(0.08, 1.4, 0.08), Color("8a6a4a"), board + Vector3(0, 0.7, sx * 0.55))
	var bp := board + Vector3(0, 1.15, 0)
	_mesh(self, Models.box(0.06, 0.95, 1.3), Color("3f4a3c"), bp)  # 小黑板
	var lines := ["狸老闆雜貨攤", "橡實　3", "胡蘿蔔　5", "蘋果　4"]
	for i in range(lines.size()):
		var lb := _label(self, lines[i], bp + Vector3(-0.04, 0.3 - i * 0.2, 0), 40 if i > 0 else 46, Color("f4efe2"))
		lb.rotation_degrees.y = -90


# ---------------- 廣場上的東西 ----------------
func _plaza_props() -> void:
	_glb(self, KENNEY_TOWN % "fountain-round", CENTER + Vector3(0, 0, 0.3), 2.4)
	# 任務公告欄
	var nb := Vector3(5.2, 0, 3.7)
	var bn := Node3D.new()
	bn.position = nb
	bn.rotation_degrees.y = 25
	add_child(bn)
	for sx in [-1, 1]:
		_mesh(bn, Models.box(0.1, 1.6, 0.1), Color("8a6a4a"), Vector3(sx * 0.6, 0.8, 0))
	_mesh(bn, Models.box(1.4, 0.9, 0.08), Color("c79a68"), Vector3(0, 1.2, 0))
	var pap := [Color("fffaf0"), Color("f7eccf"), Color("fff3dc")]
	for k in range(3):
		_mesh(bn, Models.box(0.34, 0.42, 0.02), pap[k], Vector3(-0.42 + k * 0.42, 1.18 + (k % 2) * 0.06, 0.05), Vector3(0, 0, (k - 1) * 6), false)
		_mesh(bn, Models.sphere(0.03), Color("d9605a"), Vector3(-0.42 + k * 0.42, 1.36 + (k % 2) * 0.06, 0.07), Vector3.ZERO, false)
	_mesh(bn, Models.box(1.6, 0.12, 0.2), Color("8a6a4a"), Vector3(0, 1.72, 0))
	_label(bn, "任務公告", Vector3(0, 1.88, 0.0), 44)
	# 路燈
	for p in [Vector3(3.2, 0, 2.8), Vector3(12.8, 0, 2.8), Vector3(3.6, 0, 9.4), Vector3(12.4, 0, 9.4)]:
		_glb(self, KENNEY_TOWN % "lantern", p, 1.8)
	# 往派派森林的路牌
	var sp := Vector3(9.2, 0, 11.0)
	_mesh(self, Models.box(0.1, 1.5, 0.1), Color("8a6a4a"), sp + Vector3(0, 0.75, 0))
	var arrow := Node3D.new()
	arrow.position = sp + Vector3(0.45, 1.25, 0)
	arrow.rotation_degrees.y = -10
	add_child(arrow)
	_sign(arrow, "往派派森林", Vector3.ZERO, 1.4)
	var tip := PrismMesh.new()
	tip.size = Vector3(0.42, 0.3, 0.06)
	_mesh(arrow, tip, Color("c79a68"), Vector3(0.84, 0, 0), Vector3(0, 0, -90))


func _greenery() -> void:
	var trees := [
		["tree-high-round", Vector3(-0.5, 0, 1.0), 3.4, KENNEY_TOWN], ["tree", Vector3(16.6, 0, 1.2), 3.0, KENNEY_TOWN],
		["tree_oak", Vector3(-1.2, 0, 9.5), 3.6, KENNEY_NATURE], ["tree_fat", Vector3(17.2, 0, 10.0), 3.0, KENNEY_NATURE],
		["tree_default", Vector3(3.0, 0, -1.6), 3.2, KENNEY_NATURE], ["tree_detailed", Vector3(13.4, 0, -1.4), 3.4, KENNEY_NATURE],
		["tree_small", Vector3(4.6, 0, 12.6), 2.4, KENNEY_NATURE], ["tree_oak", Vector3(12.0, 0, 13.0), 3.4, KENNEY_NATURE],
		["tree_default", Vector3(1.0, 0, 13.4), 3.0, KENNEY_NATURE], ["tree-high-round", Vector3(15.2, 0, 13.6), 3.2, KENNEY_TOWN],
	]
	for t in trees:
		_glb(self, t[3] % t[0], t[1], t[2], randf() * 360.0)
	for p in [Vector3(5.6, 0, 0.6), Vector3(10.4, 0, 0.6), Vector3(0.8, 0, 3.4), Vector3(0.8, 0, 7.8)]:
		_glb(self, KENNEY_TOWN % "hedge", p, 1.2)
	var flowers := ["flower_redA", "flower_yellowA", "flower_purpleA"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(18):
		var p := Vector3(rng.randf_range(0.5, 15.5), 0, rng.randf_range(10.0, 12.8))
		if absf(p.x - 8.0) < 1.2:
			continue
		_glb(self, KENNEY_NATURE % flowers[i % 3], p, 0.45, rng.randf() * 360.0)
	for p in [Vector3(1.4, 0, 10.4), Vector3(14.8, 0, 9.0), Vector3(6.0, 0, 12.2)]:
		_glb(self, KENNEY_NATURE % "plant_bushLarge", p, 1.1)


# ---------------- 居民 ----------------
func _spawn(who: String, pos: Vector3, facing: String) -> GopherActor:
	var a := GopherActor.new()
	a.name = "Town_" + who
	add_child(a)
	a.setup(Models.character(who))
	a.speaker_name = NAMES.get(who, "")
	a.bubble_height = BUBBLE_H.get(who, 1.4)
	a.position = pos
	a.face(facing)
	a.model.rotation.y = a.target_yaw
	npcs[who] = a
	return a


## 滑鼠指到哪個居民（螢幕上離頭部附近 55 像素以內）
func actor_at(screen_pos: Vector2, cam: Camera3D) -> String:
	var best := ""
	var best_d := 55.0
	for who in npcs:
		var a: GopherActor = npcs[who]
		var p := a.global_position + Vector3(0, 0.6, 0)
		if cam.is_position_behind(p):
			continue
		var dd := cam.unproject_position(p).distance_to(screen_pos)
		if dd < best_d:
			best_d = dd
			best = who
	return best


func talk(who: String) -> void:
	if not npcs.has(who):
		return
	var lines: Array = LINES.get(who, ["……"])
	var i: int = _line_i.get(who, 0)
	_line_i[who] = (i + 1) % lines.size()
	var a: GopherActor = npcs[who]
	a.hop(0.12)
	a.say(lines[i], "say")
