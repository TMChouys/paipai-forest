class_name RoomView
extends Node3D
## 房間畫面：派派鼠的地洞樹屋（棋盤格木地板、原木牆、背後的大樹）、派派森林、
## 格子與座標、家具節點、角色（派派鼠＋來訪的派派狼／派派兔）、虛線影子。

## 屋外草地比室內地板低（站在屋外的角色要踩在這個高度）
const GRASS_Y := -0.11
const WALL_H := 2.4
const WALL_T := 0.14

var world: WorldModel
var furniture_nodes: Dictionary = {}  # uid -> Node3D
var walls: Dictionary = {}  # "N"/"E"/"S"/"W" -> Node3D
var grid_node: Node3D
var ghosts: Node3D
var gopher: GopherActor
## 來訪的角色：who → GopherActor（"wolf"、"rabbit"）
var npcs: Dictionary = {}
const NAMES := {"gopher": "派派鼠", "wolf": "派派狼", "rabbit": "派派兔", "tanuki": "狸老闆", "turtle": "慢慢館長", "crow": "拍拍鳥"}
const BUBBLE_H := {"gopher": 1.3, "wolf": 1.45, "rabbit": 1.6, "tanuki": 1.45, "turtle": 1.4, "crow": 1.4}
var grid_visible := true
## house = 樹屋（木地板、牆）；town = 鎮中心（任務格子放在 town_spot 那棟房子前面）
var scene := "house"
var town_spot := ""
var room_name := ""
## 家門口旁的森林信箱（屋外固定的擺設，不是屋裡的家具）
var mailbox: Node3D = null


func build(w: WorldModel) -> void:
	world = w
	mailbox = null
	cutaway = true  # 開場中途被打斷時，重建房間要恢復成自動隱藏前面的牆
	for c in get_children():
		c.queue_free()
	furniture_nodes.clear()
	walls.clear()
	npcs.clear()
	if scene != "town":
		_build_floor()
		_build_walls()
	_build_grid()
	ghosts = Node3D.new()
	ghosts.name = "Ghosts"
	add_child(ghosts)
	for uid in world.items:
		_spawn_item(uid)
	gopher = GopherActor.new()
	gopher.name = "GopherActor"
	add_child(gopher)
	gopher.setup(Models.gopher())
	gopher.speaker_name = NAMES.gopher
	gopher.bubble_height = BUBBLE_H.gopher
	gopher.position = GopherActor.cell_pos(world.gopher_cell)
	gopher.face(world.gopher_dir)
	gopher.model.rotation.y = gopher.target_yaw
	set_grid_visible(grid_visible)


# ---------------- 木紋 ----------------
static var _wood_cache := {}
static var _wood_img: Image


## 程式產生的木紋（可無縫拼接）：年輪條紋＋細纖維，灰階乘上木條顏色
static func _wood_image() -> Image:
	if _wood_img:
		return _wood_img
	var W := 512
	var Hh := 128
	# 扭動用的雜訊：生成小圖再拉長，變化沿著木紋方向很慢（木紋是長條，不是大理石）
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.05
	n.fractal_octaves = 2
	var warp := n.get_seamless_image(64, 64, false, false, 0.1, true)
	warp.resize(W, Hh, Image.INTERPOLATE_BILINEAR)
	# 纖維：拉長 12 倍的細雜訊 → 細長條紋
	var fine := FastNoiseLite.new()
	fine.seed = 3
	fine.frequency = 0.12
	var fib := fine.get_seamless_image(48, 128, false, false, 0.1, true)
	fib.resize(W, Hh, Image.INTERPOLATE_BILINEAR)
	var img := Image.create(W, Hh, false, Image.FORMAT_RGB8)
	for y in range(Hh):
		for x in range(W):
			var w := warp.get_pixel(x, y).r
			var ring := sin(TAU * (float(y) / Hh * 4.0 + w * 0.9))
			var line := pow(0.5 + 0.5 * ring, 10.0)           # 細細的深色年輪線
			var f := fib.get_pixel(x, y).r
			var v := 1.0 - 0.11 * line - 0.04 * (0.5 + 0.5 * ring) + 0.06 * (f - 0.5)
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.93))
	img.generate_mipmaps()
	_wood_img = img
	return img


## 木條材質：along_z = 木紋沿著 z 方向（拼花地板兩種方向）
static func wood_mat(color: Color, along_z: bool, outline: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), along_z, outline]
	if _wood_cache.has(key):
		return _wood_cache[key]
	var img := _wood_image()
	if along_z:
		img = img.duplicate()
		img.rotate_90(CLOCKWISE)
		img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	# 一張圖：沿木紋 2 格長、橫向 0.5 格（每片木條約 2 條年輪）
	m.uv1_scale = Vector3(0.5, 1.0, 2.0) if not along_z else Vector3(2.0, 1.0, 0.5)
	m.roughness = 0.9
	m.metallic_specular = 0.15
	if outline:
		m.next_pass = Models.mat(Models.INK).next_pass
	_wood_cache[key] = m
	return m


# ---------------- 建構 ----------------
func _build_floor() -> void:
	var floor_root := Node3D.new()
	floor_root.name = "Floor"
	add_child(floor_root)
	# 底板（木條之間縫隙的深色）
	var base := MeshInstance3D.new()
	base.mesh = Models.box(world.width, 0.1, world.depth)
	base.material_override = Models.mat(Color("9a8064"), false)
	base.position = Vector3(world.width / 2.0, -0.065, world.depth / 2.0)
	floor_root.add_child(base)
	# 北歐風淺色橡木長條地板：一排一排橫向木條，長短錯開接縫
	var tones := [Color("dcc4a0"), Color("d3b993"), Color("e2cdaa"), Color("cfb38c")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var rows := int(round(world.depth / 0.25))
	for r in range(rows):
		var z0 := r * 0.25 + 0.125
		var x := -rng.randf_range(0.0, 1.4)  # 每排起點錯開
		while x < world.width:
			var length := rng.randf_range(1.3, 2.6)
			var a := maxf(x, 0.0)
			var b := minf(x + length, float(world.width))
			if b - a > 0.08:
				var plank := MeshInstance3D.new()
				plank.mesh = Models.box(b - a - 0.02, 0.1, 0.235)
				plank.position = Vector3((a + b) / 2.0, -0.05, z0)
				plank.material_override = wood_mat(tones[rng.randi() % tones.size()], false)
				floor_root.add_child(plank)
			x += length
	# 屋外：派派森林的草地
	var grass := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(70, 70)
	grass.mesh = pm
	grass.material_override = Models.mat(Color("8fae7a"), false)
	grass.position = Vector3(world.width / 2.0, GRASS_Y, world.depth / 2.0)
	floor_root.add_child(grass)
	# 圓形苔蘚地毯
	var rug := MeshInstance3D.new()
	rug.mesh = Models.cyl(1.4, 1.4, 0.02)
	rug.material_override = Models.mat(Color("e9dcc2"), false)  # 羊毛圓地毯
	rug.scale = Vector3(1.2, 1, 0.8)
	rug.position = Vector3(world.width / 2.0, 0.005, world.depth / 2.0 + 0.5)
	floor_root.add_child(rug)
	# 地毯上的北歐小花紋：兩圈織紋
	for ring in [[1.15, Color("c9a77c")], [0.75, Color("9fb08a")]]:
		var band := MeshInstance3D.new()
		band.mesh = Models.cyl(ring[0], ring[0], 0.022)
		band.material_override = Models.mat(ring[1], false)
		band.scale = Vector3(1.2, 1, 0.8)
		band.position = rug.position + Vector3(0, 0.002, 0)
		floor_root.add_child(band)
		var inner := MeshInstance3D.new()
		inner.mesh = Models.cyl(ring[0] - 0.08, ring[0] - 0.08, 0.024)
		inner.material_override = Models.mat(Color("e9dcc2"), false)
		inner.scale = Vector3(1.2, 1, 0.8)
		inner.position = rug.position + Vector3(0, 0.003, 0)
		floor_root.add_child(inner)


const DOOR_W := 0.9  # 門洞寬（門板 0.86）
const DOOR_H := 1.92  # 門洞高（木板門 1.9）


## 牆上門的位置（沿著牆的座標），用來在牆上挖門洞：角色真的從門洞走進走出，不穿牆
func _door_spans(side: String) -> Array:
	var out: Array = []
	for uid in world.items:
		var it: Dictionary = world.items[uid]
		if it.type == "door" and it.wall == side:
			var c: Vector2i = it.cell
			var mid: float = (c.x + 0.5) if side in ["N", "S"] else (c.y + 0.5)
			out.append(Vector2(mid - DOOR_W / 2, mid + DOOR_W / 2))
	return out


## 沿著牆蓋一條 y0..y1 高的方塊；碰到門洞（門洞高度以下）就切開
func _wall_strip(holder: Node3D, side: String, s: Dictionary, y0: float, y1: float, grow: float, mat: Material) -> void:
	var along_x: bool = side in ["N", "S"]
	var size: Vector3 = s.size
	var length: float = (size.x if along_x else size.z)
	var lo: float = (s.pos.x if along_x else s.pos.z) - length / 2
	var hi: float = lo + length
	var cuts: Array = []
	for sp in _door_spans(side):
		if y0 < DOOR_H:
			cuts.append(sp)
	var pieces: Array = []
	var cur := lo
	for sp in cuts:
		pieces.append(Vector2(cur, sp.x))
		cur = sp.y
	pieces.append(Vector2(cur, hi))
	# 門洞上面的門楣
	var lintels: Array = []
	if y1 > DOOR_H:
		for sp in cuts:
			lintels.append([sp, maxf(y0, DOOR_H), y1])
	var all: Array = []
	for pc in pieces:
		all.append([pc, y0, y1])
	all += lintels
	for e in all:
		var span: Vector2 = e[0]
		var ya: float = e[1]
		var yb: float = e[2]
		if span.y - span.x < 0.01 or yb - ya < 0.01:
			continue
		var m := MeshInstance3D.new()
		var thick: float = (size.z if along_x else size.x) + grow
		if along_x:
			m.mesh = Models.box(span.y - span.x, yb - ya, thick)
			m.position = Vector3((span.x + span.y) / 2, (ya + yb) / 2, s.pos.z)
		else:
			m.mesh = Models.box(thick, yb - ya, span.y - span.x)
			m.position = Vector3(s.pos.x, (ya + yb) / 2, (span.x + span.y) / 2)
		m.material_override = mat
		holder.add_child(m)


func _build_walls() -> void:
	var specs := {
		"N": {"pos": Vector3(world.width / 2.0, WALL_H / 2, -WALL_T / 2), "size": Vector3(world.width + WALL_T * 2, WALL_H, WALL_T)},
		"S": {"pos": Vector3(world.width / 2.0, WALL_H / 2, world.depth + WALL_T / 2), "size": Vector3(world.width + WALL_T * 2, WALL_H, WALL_T)},
		"W": {"pos": Vector3(-WALL_T / 2, WALL_H / 2, world.depth / 2.0), "size": Vector3(WALL_T, WALL_H, world.depth)},
		"E": {"pos": Vector3(world.width + WALL_T / 2, WALL_H / 2, world.depth / 2.0), "size": Vector3(WALL_T, WALL_H, world.depth)},
	}
	var plaster := Models.mat(Color("f0e5cf"))  # 刷白的灰泥牆
	var board := Models.mat(Color("dcc9a4"), false)  # 淺松木橫板
	for side in specs:
		var holder := Node3D.new()
		holder.name = "Wall" + side
		add_child(holder)
		var s: Dictionary = specs[side]
		var along_x: bool = side in ["N", "S"]
		_wall_strip(holder, side, s, 0.0, WALL_H, 0.0, plaster)
		# 原木牆：一圈一圈橫向的木頭（凸出牆面一點點）
		for i in range(6):
			var y := 0.62 + i * 0.3
			_wall_strip(holder, side, s, y - 0.025, y + 0.025, 0.03, board)
		# 下半截：樹根色的護牆板
		_wall_strip(holder, side, s, 0.0, 0.55, 0.02, wood_mat(Color("b39773"), not along_x))
		# 牆頂的橫樑
		var beam := MeshInstance3D.new()
		beam.mesh = Models.box(s.size.x + 0.06, 0.12, s.size.z + 0.06)
		beam.material_override = wood_mat(Color("9a7b58"), not along_x, true)
		beam.position = Vector3(s.pos.x, WALL_H, s.pos.z)
		holder.add_child(beam)
		# 門框：門洞兩側和上方的木框
		for sp in _door_spans(side):
			var frame_mat := wood_mat(Color("8a6646"), not along_x, true)
			var depth_f: float = WALL_T + 0.34
			var out_n: Vector3 = OUT_N[side]
			for x in [sp.x - 0.04, sp.y + 0.04]:
				var post := MeshInstance3D.new()
				post.mesh = Models.box(0.08, DOOR_H, depth_f) if along_x else Models.box(depth_f, DOOR_H, 0.08)
				post.position = (Vector3(x, DOOR_H / 2, s.pos.z) if along_x else Vector3(s.pos.x, DOOR_H / 2, x)) + out_n * 0.14
				post.material_override = frame_mat
				holder.add_child(post)
			var top := MeshInstance3D.new()
			top.mesh = Models.box(DOOR_W + 0.16, 0.1, depth_f) if along_x else Models.box(depth_f, 0.1, DOOR_W + 0.16)
			var mid: float = (sp.x + sp.y) / 2
			top.position = (Vector3(mid, DOOR_H + 0.05, s.pos.z) if along_x else Vector3(s.pos.x, DOOR_H + 0.05, mid)) + out_n * 0.14
			top.material_override = frame_mat
			holder.add_child(top)
		_treehouse_outside(holder, side, s)
		walls[side] = holder


# ---------------- 樹屋的外觀 ----------------
const OUT_N := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0), "E": Vector3(1, 0, 0)}
const BARK := Color("7d5838")
const LOG_COLS := [Color("86603f"), Color("7a5639"), Color("8f6a47")]
const MOSS := Color("8fae6a")


## 牆外面：一根一根橫放的圓木（帶樹皮），牆頂長青苔，南牆有垂下來的藤蔓、牆腳有小蘑菇；
## 每個牆角是一根樹幹（後面兩根比較高、頂上有葉子），整間屋子像是蓋在樹裡面。
func _treehouse_outside(holder: Node3D, side: String, s: Dictionary) -> void:
	var along_x: bool = side in ["N", "S"]
	var n: Vector3 = OUT_N[side]
	var size: Vector3 = s.size
	var length: float = (size.x if along_x else size.z) + 0.2
	var lo: float = (s.pos.x if along_x else s.pos.z) - length / 2
	var hi: float = lo + length
	var log_mats: Array = []
	for col in LOG_COLS:
		log_mats.append(Models.mat(col))
	var end_mat := Models.mat(Color("d9b98a"), false)
	var r := 0.13
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(side + str(world.width) + str(world.depth))
	for i in range(8):
		var y := 0.13 + i * 0.27
		var pieces: Array = []
		var cur := lo
		if y - r < DOOR_H:
			for sp in _door_spans(side):
				pieces.append(Vector2(cur, sp.x - 0.1))
				cur = sp.y + 0.1
		pieces.append(Vector2(cur, hi))
		for pc in pieces:
			var a: float = pc.x
			var b: float = pc.y
			if b - a < 0.05:
				continue
			var m := MeshInstance3D.new()
			m.mesh = Models.cyl(r, r, b - a)
			m.material_override = log_mats[(i + rng.randi_range(0, 1)) % log_mats.size()]
			var mid := (a + b) / 2
			var base := Vector3(mid, y, s.pos.z) if along_x else Vector3(s.pos.x, y, mid)
			m.position = base + n * (WALL_T / 2 + r * 0.55)
			m.rotation_degrees = Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0)
			holder.add_child(m)
	# 牆頂的青苔
	for k in range(4):
		var t := rng.randf_range(0.1, 0.9)
		var along := lo + (hi - lo) * t
		var moss := MeshInstance3D.new()
		moss.mesh = Models.sphere(0.35)
		moss.material_override = Models.mat(MOSS.darkened(rng.randf_range(0.0, 0.12)), false)
		var top := Vector3(along, WALL_H + 0.06, s.pos.z) if along_x else Vector3(s.pos.x, WALL_H + 0.06, along)
		moss.position = top
		moss.scale = Vector3(1.4, 0.22, 0.45) if along_x else Vector3(0.45, 0.22, 1.4)
		holder.add_child(moss)
	# 南牆（有門的那面）：藤蔓從牆頂垂下來，牆腳長小蘑菇
	if side == "S":
		var spans := _door_spans(side)
		for vx in [0.7, 2.2, world.width - 1.6, world.width - 0.5]:
			var blocked := false
			for sp in spans:
				if vx > sp.x - 0.25 and vx < sp.y + 0.25:
					blocked = true
			if blocked:
				continue
			var drop := rng.randf_range(0.7, 1.3)
			var steps := int(drop / 0.13)
			for j in range(steps):
				var leaf := MeshInstance3D.new()
				leaf.mesh = Models.sphere(0.075)
				leaf.material_override = Models.mat(Color("6f9a52") if j % 2 == 0 else Color("85ad5f"), false)
				leaf.position = Vector3(vx + sin(j * 1.7) * 0.06, WALL_H - j * 0.13, s.pos.z) + n * (WALL_T / 2 + 0.25)
				leaf.scale = Vector3(1.2, 0.8, 0.6)
				holder.add_child(leaf)
		for mx in [0.4, 1.3, world.width - 0.9, world.width - 0.3]:
			var blocked2 := false
			for sp in spans:
				if mx > sp.x - 0.3 and mx < sp.y + 0.3:
					blocked2 = true
			if blocked2:
				continue
			var cap := MeshInstance3D.new()
			cap.mesh = Models.sphere(0.09)
			cap.material_override = Models.mat(Color("d9644a"))
			cap.scale = Vector3(1, 0.6, 1)
			var foot := Vector3(mx, GRASS_Y, s.pos.z) + n * (WALL_T / 2 + 0.33)
			cap.position = foot + Vector3(0, 0.14, 0)
			holder.add_child(cap)
			var stem := MeshInstance3D.new()
			stem.mesh = Models.cyl(0.03, 0.04, 0.12)
			stem.material_override = Models.mat(Color("f2e6cf"), false)
			stem.position = foot + Vector3(0, 0.07, 0)
			holder.add_child(stem)
	# 牆角的樹幹：每面牆負責一個角（北牆：西北、東北兩個高的；南牆：西南；東牆：東南）
	var corners: Array = []
	match side:
		"N": corners = [[Vector3(-WALL_T, 0, -WALL_T), true], [Vector3(world.width + WALL_T, 0, -WALL_T), true]]
		"S": corners = [[Vector3(-WALL_T, 0, world.depth + WALL_T), false]]
		"E": corners = [[Vector3(world.width + WALL_T, 0, world.depth + WALL_T), false]]
	for cn in corners:
		_corner_trunk(holder, cn[0], cn[1], rng)


func _corner_trunk(holder: Node3D, p: Vector3, tall: bool, rng: RandomNumberGenerator) -> void:
	var h := WALL_H + (1.5 if tall else 0.45)
	var trunk := MeshInstance3D.new()
	trunk.mesh = Models.cyl(0.22, 0.32, h)
	trunk.material_override = Models.mat(BARK)
	trunk.position = p + Vector3(0, GRASS_Y + h / 2, 0)
	holder.add_child(trunk)
	# 樹皮的直紋
	for k in range(7):
		var a := k * TAU / 7.0 + rng.randf() * 0.3
		var st := MeshInstance3D.new()
		st.mesh = Models.box(0.05, h * 0.85, 0.05)
		st.material_override = Models.mat(BARK.darkened(0.22), false)
		st.position = p + Vector3(cos(a) * 0.27, GRASS_Y + h * 0.45, sin(a) * 0.27)
		holder.add_child(st)
	# 樹根：往屋子外面張開
	var out := Vector3(signf(p.x - world.width / 2.0), 0, signf(p.z - world.depth / 2.0)).normalized()
	for k in [-0.9, 0.0, 0.9]:
		var dir := out.rotated(Vector3.UP, k)
		var root := MeshInstance3D.new()
		root.mesh = Models.cyl(0.05, 0.13, 0.7)
		root.material_override = Models.mat(BARK)
		root.position = p + dir * 0.38 + Vector3(0, GRASS_Y + 0.1, 0)
		root.look_at_from_position(root.position, root.position + dir, Vector3.UP)
		root.rotate_object_local(Vector3.RIGHT, deg_to_rad(-75))
		holder.add_child(root)
	# 頂上：高的樹幹長出一團葉子，矮的樹幹頂著一圈青苔
	if tall:
		for c in [[Vector3(0, h + 0.15, 0), 0.65], [Vector3(0.45, h - 0.1, 0.1), 0.45], [Vector3(-0.4, h - 0.05, -0.15), 0.5], [Vector3(0.05, h + 0.55, -0.1), 0.42]]:
			var ball := MeshInstance3D.new()
			ball.mesh = Models.sphere(c[1])
			ball.material_override = Models.mat(Color("7fa25a").darkened(rng.randf_range(0.0, 0.15)))
			ball.position = p + Vector3(0, GRASS_Y, 0) + c[0]
			holder.add_child(ball)
	else:
		var moss := MeshInstance3D.new()
		moss.mesh = Models.sphere(0.3)
		moss.material_override = Models.mat(MOSS, false)
		moss.scale = Vector3(1.1, 0.35, 1.1)
		moss.position = p + Vector3(0, GRASS_Y + h, 0)
		holder.add_child(moss)
		var sprout := MeshInstance3D.new()
		sprout.mesh = Models.sphere(0.14)
		sprout.material_override = Models.mat(Color("85ad5f"))
		sprout.position = p + Vector3(0.05, GRASS_Y + h + 0.15, 0.02)
		holder.add_child(sprout)


func _build_grid() -> void:
	grid_node = Node3D.new()
	grid_node.name = "Grid"
	add_child(grid_node)
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.36, 0.24, 0.15, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	for x in range(world.width + 1):
		im.surface_add_vertex(Vector3(x, 0.012, 0))
		im.surface_add_vertex(Vector3(x, 0.012, world.depth))
	for z in range(world.depth + 1):
		im.surface_add_vertex(Vector3(0, 0.012, z))
		im.surface_add_vertex(Vector3(world.width, 0.012, z))
	im.surface_end()
	grid_node.add_child(mi)
	for x in range(world.width):
		for z in range(world.depth):
			var lb := Label3D.new()
			lb.text = "%d,%d" % [x, z]
			lb.font_size = 40
			lb.pixel_size = 0.004
			lb.modulate = Color(0.42, 0.28, 0.18, 0.55)
			lb.outline_size = 0
			lb.rotation_degrees = Vector3(-90, 0, 0)
			lb.position = Vector3(x + 0.5, 0.015, z + 0.82)
			lb.double_sided = false
			grid_node.add_child(lb)


## 派派森林（Kenney Nature Kit，CC0）。只是裝飾，不在格子裡。
## 每項：[模型, 位置 x, z, 目標大小(最長邊/高度), 旋轉度數]
const OUTDOOR := [
	["tree_oak", -2.6, -1.5, 3.4, 0], ["tree_fat", 12.0, -3.0, 2.8, 40], ["tree_default", -3.2, 4.0, 3.2, 10],
	["tree_detailed", 13.5, 7.5, 3.0, 80], ["tree_small", -2.0, 10.5, 2.2, 0], ["tree_oak", 11.6, 12.4, 3.2, 120],
	["tree_detailed", -5.5, 11.8, 3.8, 0], ["tree_fat", 15.0, 2.0, 2.8, 0], ["tree_default", 4.0, -7.5, 3.0, 200],
	["tree_oak", -6.5, 1.0, 3.6, 60], ["tree_default", -7.0, 8.0, 3.4, 150], ["tree_small", -4.8, -4.5, 2.4, 20],
	["tree_detailed", 16.5, 11.5, 3.4, 10], ["tree_oak", 17.0, -2.5, 3.6, 90], ["tree_small", 12.0, 16.8, 2.4, 0],
	["tree_fat", -0.5, 17.6, 3.0, 30], ["tree_default", 7.5, 17.5, 3.4, 0], ["tree_detailed", -3.0, 17.5, 3.6, 70],
	["tree_oak", 14.5, 16.6, 3.2, 200], ["tree_small", 10.8, -5.5, 2.4, 0], ["tree_fat", -8.5, 12.5, 3.0, 0],
	["plant_bushLarge", -1.3, 1.2, 1.1, 0], ["plant_bush", -2.4, 7.4, 0.8, 30], ["plant_bush", 9.4, 3.0, 0.9, 0],
	["plant_bushLarge", 10.0, 9.5, 1.2, 0], ["plant_bush", 0.4, 11.8, 0.9, 0], ["plant_bushLarge", 10.8, 10.6, 1.0, 50],
	["flower_redA", -0.8, 8.6, 0.5, 0], ["flower_yellowA", 0.3, 9.7, 0.5, 40], ["flower_purpleA", 6.0, 8.8, 0.5, 0],
	["flower_yellowA", 7.2, 9.3, 0.5, 70], ["flower_redA", -1.6, 3.0, 0.5, 20], ["flower_purpleA", 9.3, 7.8, 0.5, 0],
	["mushroom_redGroup", -0.9, 10.2, 0.6, 0], ["mushroom_tanGroup", 9.8, 10.2, 0.6, 0], ["stump_round", -3.8, 7.5, 0.7, 0],
	["mushroom_redGroup", 11.0, 4.5, 0.6, 30], ["mushroom_tanGroup", -2.5, -0.2, 0.6, 0],
	["log", -4.2, 9.0, 1.6, 30], ["rock_smallA", 8.8, 11.0, 0.6, 0], ["rock_smallA", -1.0, 12.0, 0.5, 40],
	["path_stone", 3.5, 8.8, 1.0, 0], ["path_stone", 3.6, 9.9, 1.0, 15], ["path_stone", 3.4, 11.0, 1.0, 0],
	["path_stone", 3.7, 12.1, 1.0, 30], ["path_stone", 3.5, 13.2, 1.0, 10],
]


## 南牆上門的中心 x（沒有門就用牆中間）
static func door_x(w: WorldModel) -> float:
	for uid in w.items:
		var it: Dictionary = w.items[uid]
		if it.type == "door" and it.wall == "S":
			return it.cell.x + 0.5
	return w.width / 2.0


## with_mailbox：家裡才有門口的信箱（任務房間沒有）
func build_outdoor(with_mailbox: bool = false) -> void:
	if with_mailbox and scene != "town":
		mailbox = Models.furniture("mailbox")
		mailbox.name = "Mailbox"
		add_child(mailbox)
		mailbox.position = Vector3(door_x(world) + 2.2, GRASS_Y, world.depth + 2.7)
		mailbox.rotation.y = 0.0
	if scene == "town":
		# 鎮中心當背景：把整個鎮中心挪過來，讓任務格子剛好在 town_spot 前面
		var tv := TownView.new()
		tv.name = "TownBackdrop"
		tv.backdrop = true
		add_child(tv)
		tv.build()
		var anchor: Vector3 = TownView.SPOTS.get(town_spot, TownView.CENTER)
		tv.position = Vector3(world.width / 2.0, 0, world.depth / 2.0) - anchor
		return
	var holder := Node3D.new()
	holder.name = "Outdoor"
	add_child(holder)
	for e in OUTDOOR:
		var path := "res://models/kenney/nature/%s.glb" % e[0]
		if not ResourceLoader.exists(path):
			continue
		var n := Models.glb(path)
		var wrap := Node3D.new()
		wrap.add_child(n)
		var s: float = e[3]
		Models.fit(n, Vector3(s, s, s))
		wrap.position = Vector3(e[1], -0.1, e[2])
		wrap.rotation_degrees.y = e[4]
		holder.add_child(wrap)
	_build_big_tree(holder)
	_build_front_yard(holder)


## 地洞樹屋：房子蓋在一棵大樹的樹根底下。樹幹在北牆後面，粗樹根沿著兩側牆外伸出來。
func _build_big_tree(holder: Node3D) -> void:
	# 神木：好幾根樹幹長在一起的巨大老樹，板根往四面八方張開，樹冠又高又寬。
	# 整棵樹在北牆後面；樹屋的北牆就靠在樹幹上（往天空樹頂的門通到樹幹裡）。
	var w := float(world.width)
	var center := Vector3(w / 2.0, 0, -4.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261107
	var barks: Array = [Models.mat(Color("6e4a30")), Models.mat(Color("7a5436")), Models.mat(Color("64432c"))]
	var groove := Models.mat(Color("4a3020"), false)
	var moss := Models.mat(Color("7f9e5c"), false)
	# 主幹
	var main_h := 11.0
	_cyl_between(holder, center + Vector3(0, GRASS_Y, 0), center + Vector3(0, main_h, 0), 3.5, 2.3, barks[0])
	# 長在一起的副幹（讓樹幹表面一條一條鼓起來，像老神木）
	for i in range(8):
		var ang := i * TAU / 8.0 + rng.randf_range(-0.15, 0.15)
		var off := Vector3(cos(ang), 0, sin(ang)) * 2.6
		var top_off := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(1.2, 1.8)
		var hh := rng.randf_range(8.5, 12.5)
		_cyl_between(holder, center + off + Vector3(0, GRASS_Y, 0), center + top_off + Vector3(0, hh, 0), 1.25, 0.6, barks[i % barks.size()])
	# 深深的樹皮溝
	for i in range(22):
		var ang2 := i * TAU / 22.0
		var gp := center + Vector3(cos(ang2), 0, sin(ang2)) * 3.15
		var st := MeshInstance3D.new()
		st.mesh = Models.box(0.16, rng.randf_range(5.0, 8.5), 0.16)
		st.material_override = groove
		st.position = gp + Vector3(0, 3.4, 0)
		st.rotation.y = -ang2
		holder.add_child(st)
	# 樹幹上的青苔
	for i in range(10):
		var ang3 := rng.randf() * TAU
		var mp := center + Vector3(cos(ang3), 0, sin(ang3)) * 3.2 + Vector3(0, rng.randf_range(0.5, 6.0), 0)
		var mm := MeshInstance3D.new()
		mm.mesh = Models.sphere(rng.randf_range(0.4, 0.7))
		mm.material_override = moss
		mm.position = mp
		mm.scale = Vector3(1.0, 0.6, 0.35)
		mm.rotation.y = -ang3 + PI / 2
		holder.add_child(mm)
	# 板根：從樹幹底部張開，貼著地面伸出去（不伸進屋子）
	var ends := [Vector3(-3.4, 0, -0.7), Vector3(w + 3.4, 0, -0.7), Vector3(-5.0, 0, -1.6), Vector3(w + 5.0, 0, -1.6),
		Vector3(-5.5, 0, -6.8), Vector3(w + 5.5, 0, -6.8), Vector3(-2.0, 0, -10.5), Vector3(w + 2.0, 0, -10.5), Vector3(w / 2.0, 0, -11.5)]
	for e in ends:
		var dir: Vector3 = (e - center)
		dir.y = 0
		dir = dir.normalized()
		var start := center + dir * 2.8 + Vector3(0, 1.4, 0)
		var mid := center + dir * 4.2 + Vector3(0, 0.45, 0)
		var fin: Vector3 = e + Vector3(0, GRASS_Y + 0.05, 0)
		_cyl_between(holder, start, mid, 0.95, 0.7, barks[0], Vector3(1, 1, 0.6))
		_cyl_between(holder, mid, fin, 0.7, 0.12, barks[1], Vector3(1, 1, 0.7))
	# 粗樹枝
	var branches := [[Vector3(-1, 0, 0.1), 9.0], [Vector3(1, 0, 0.0), 9.6], [Vector3(-0.5, 0, -1), 10.2], [Vector3(0.6, 0, -0.9), 8.6], [Vector3(0, 0, -1), 11.0]]
	for br in branches:
		var bd: Vector3 = br[0].normalized()
		var by: float = br[1]
		var b0 := center + bd * 1.6 + Vector3(0, by, 0)
		var b1 := center + bd * 6.0 + Vector3(0, by + 3.2, 0)
		_cyl_between(holder, b0, b1, 0.75, 0.32, barks[2])
	# 樹冠：好幾層大團的葉子（不蓋到房子上面）
	var leaves: Array = [Models.mat(Color("5f8f4a")), Models.mat(Color("6e9e52")), Models.mat(Color("7fae5c")), Models.mat(Color("557f43"))]
	var crown := [
		[0.0, 14.5, -1.0, 4.6], [-5.2, 13.2, -0.6, 3.6], [5.4, 13.4, -0.4, 3.8], [-3.0, 16.4, -2.0, 3.4], [3.2, 16.2, -1.8, 3.4],
		[0.0, 17.6, -3.2, 3.2], [-6.8, 12.0, -3.8, 3.2], [6.8, 12.2, -3.8, 3.3], [-2.5, 12.6, 1.2, 3.0], [2.8, 12.8, 1.0, 3.0],
		[0.0, 13.0, -6.5, 4.0], [-4.5, 15.0, -5.2, 3.2], [4.6, 15.2, -5.0, 3.2], [-8.0, 10.6, -1.2, 2.4], [8.2, 10.8, -1.4, 2.4],
	]
	for i in range(crown.size()):
		var c: Array = crown[i]
		var ball := MeshInstance3D.new()
		ball.mesh = Models.sphere(c[3])
		ball.material_override = leaves[i % leaves.size()]
		ball.position = center + Vector3(c[0], c[1], c[2])
		ball.scale = Vector3(1.0, 0.78, 1.0)
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 樹冠太大，影子會把整間屋子蓋暗
		holder.add_child(ball)
	# 房子上方：從大樹延伸出來的木頭屋簷
	var eave := MeshInstance3D.new()
	eave.mesh = Models.box(w + 0.6, 0.18, 0.9)
	eave.material_override = Models.mat(Color("8f5f38"))
	eave.position = Vector3(w / 2.0, WALL_H + 0.25, -0.25)
	holder.add_child(eave)
	# 北牆後面：樹幹和牆之間塞滿樹皮（從屋裡往北看，門後面就是樹幹）
	_cyl_between(holder, Vector3(w / 2.0, GRASS_Y, -1.75), Vector3(w / 2.0, WALL_H + 0.4, -1.7), 1.4, 1.2, barks[1], Vector3(2.4, 1, 0.75))


# ---------------- 前院和溪流 ----------------
## 溪流的中心線（z 隨 x 彎彎的）
func stream_z(x: float) -> float:
	return world.depth + 6.6 + 0.5 * sin(x * 0.35)


func _build_front_yard(holder: Node3D) -> void:
	var w := float(world.width)
	var d := float(world.depth)
	var dx := door_x(world)
	var wood := Models.mat(Color("b88c5e"))
	var wood_dark := Models.mat(Color("9a7048"))
	# 前院的矮木柵欄：西、南、東三邊，南邊中間是小門口（小石路穿過去）
	var fz := d + 4.6
	var fx0 := -1.6
	var fx1 := w + 1.6
	var runs := [[Vector3(fx0, 0, d + 0.4), Vector3(fx0, 0, fz)], [Vector3(fx1, 0, d + 0.4), Vector3(fx1, 0, fz)],
		[Vector3(fx0, 0, fz), Vector3(dx - 0.7, 0, fz)], [Vector3(dx + 0.7, 0, fz), Vector3(fx1, 0, fz)]]
	for r in runs:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var ln := a.distance_to(b)
		var n := maxi(1, int(ln / 0.75))
		for i in range(n + 1):
			var p := a.lerp(b, float(i) / n)
			var post := MeshInstance3D.new()
			post.mesh = Models.box(0.1, 0.62, 0.1)
			post.material_override = wood
			post.position = p + Vector3(0, GRASS_Y + 0.31, 0)
			holder.add_child(post)
			var cap := MeshInstance3D.new()
			cap.mesh = Models.box(0.13, 0.05, 0.13)
			cap.material_override = wood_dark
			cap.position = p + Vector3(0, GRASS_Y + 0.64, 0)
			holder.add_child(cap)
		for ry in [0.22, 0.46]:
			_cyl_between(holder, a + Vector3(0, GRASS_Y + ry, 0), b + Vector3(0, GRASS_Y + ry, 0), 0.03, 0.03, wood_dark)
	# 柵欄門口兩邊的高柱子
	for gx in [dx - 0.7, dx + 0.7]:
		var gp := MeshInstance3D.new()
		gp.mesh = Models.box(0.14, 0.9, 0.14)
		gp.material_override = wood_dark
		gp.position = Vector3(gx, GRASS_Y + 0.45, fz)
		holder.add_child(gp)
	# 胡蘿蔔園：東邊的一塊菜圃，三排胡蘿蔔
	var soil := Models.mat(Color("54402e"), false)
	var gc := Vector3(w - 0.4, 0, d + 2.9)
	var bed := MeshInstance3D.new()
	bed.mesh = Models.box(2.4, 0.12, 1.7)
	bed.material_override = soil
	bed.position = gc + Vector3(0, GRASS_Y + 0.04, 0)
	holder.add_child(bed)
	for side_x in [-1.25, 1.25]:
		var edge := MeshInstance3D.new()
		edge.mesh = Models.box(0.1, 0.18, 1.8)
		edge.material_override = wood
		edge.position = gc + Vector3(side_x, GRASS_Y + 0.07, 0)
		holder.add_child(edge)
	for side_z in [-0.9, 0.9]:
		var edge2 := MeshInstance3D.new()
		edge2.mesh = Models.box(2.6, 0.18, 0.1)
		edge2.material_override = wood
		edge2.position = gc + Vector3(0, GRASS_Y + 0.07, side_z)
		holder.add_child(edge2)
	var carrot := Models.mat(Color("e98a3a"))
	var leaf := Models.mat(Color("6f9e48"), false)
	for row in range(3):
		for k in range(5):
			var cp := gc + Vector3(-0.9 + k * 0.45, GRASS_Y + 0.1, -0.5 + row * 0.5)
			var top := MeshInstance3D.new()
			top.mesh = Models.sphere(0.07)
			top.material_override = carrot
			top.position = cp + Vector3(0, 0.03, 0)
			holder.add_child(top)
			for t in range(3):
				var lf := MeshInstance3D.new()
				lf.mesh = Models.cyl(0.005, 0.03, 0.22)
				lf.material_override = leaf
				lf.position = cp + Vector3(0, 0.15, 0)
				lf.rotation_degrees = Vector3(18, t * 120 + k * 30, 0)
				holder.add_child(lf)
	# 菜園的小木牌
	var sign := MeshInstance3D.new()
	sign.mesh = Models.box(0.5, 0.28, 0.05)
	sign.material_override = wood
	sign.position = gc + Vector3(-1.45, GRASS_Y + 0.55, -0.95)
	sign.rotation.y = 0.3
	holder.add_child(sign)
	var stake := MeshInstance3D.new()
	stake.mesh = Models.box(0.05, 0.45, 0.05)
	stake.material_override = wood_dark
	stake.position = gc + Vector3(-1.45, GRASS_Y + 0.22, -0.95)
	holder.add_child(stake)
	var lbl := Label3D.new()
	lbl.text = "胡蘿蔔園"
	lbl.font = UIKit.font_bold()
	lbl.font_size = 40
	lbl.pixel_size = 0.0035
	lbl.modulate = Color("5a3d2b")
	lbl.outline_size = 0
	lbl.position = gc + Vector3(-1.45, GRASS_Y + 0.55, -0.92) + Vector3(sin(0.3), 0, cos(0.3)) * 0.03
	lbl.rotation.y = 0.3
	holder.add_child(lbl)
	# 溪流：彎彎的一條，從西流到東；兩岸是泥土和小石頭，水面慢慢流動
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("8fc3cf")
	water.roughness = 0.25
	water.metallic_specular = 0.6
	Models.storybook_texture(water)
	var bank := Models.mat(Color("8a8f6a"), false)
	var x := -14.0
	var step := 0.9
	while x < w + 14.0:
		var z0 := stream_z(x)
		var z1 := stream_z(x + step)
		var mid := Vector3(x + step / 2, 0, (z0 + z1) / 2)
		var ang := atan2(z1 - z0, step)
		var bk := MeshInstance3D.new()
		bk.mesh = Models.box(step + 0.12, 0.02, 2.2)
		bk.material_override = bank
		bk.position = mid + Vector3(0, GRASS_Y + 0.004, 0)
		bk.rotation.y = -ang
		holder.add_child(bk)
		var wt := MeshInstance3D.new()
		wt.mesh = Models.box(step + 0.12, 0.02, 1.5)
		wt.material_override = water
		wt.position = mid + Vector3(0, GRASS_Y + 0.016, 0)
		wt.rotation.y = -ang
		holder.add_child(wt)
		x += step
	if not UIKit.reduce_motion:
		var tw := holder.create_tween().set_loops()
		tw.tween_property(water, "uv1_offset", Vector3(1.0, 0, 0), 9.0).from(Vector3.ZERO)
	# 岸邊的小石頭和蘆葦
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stone := Models.mat(Color("a39d8e"))
	var reed := Models.mat(Color("7c9a55"), false)
	for i in range(34):
		var sx := rng.randf_range(-12.0, w + 12.0)
		if absf(sx - dx) < 1.0:
			continue
		var bank_side := 1.0 if i % 2 == 0 else -1.0
		var sp := Vector3(sx, GRASS_Y, stream_z(sx) + bank_side * rng.randf_range(0.8, 1.05))
		if i % 3 == 0:
			for k in range(3):
				var rd := MeshInstance3D.new()
				rd.mesh = Models.cyl(0.012, 0.025, rng.randf_range(0.45, 0.7))
				rd.material_override = reed
				rd.position = sp + Vector3(k * 0.08, 0.28, k * 0.05)
				rd.rotation_degrees = Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
				holder.add_child(rd)
		else:
			var st := MeshInstance3D.new()
			st.mesh = Models.sphere(rng.randf_range(0.1, 0.2))
			st.material_override = stone
			st.position = sp + Vector3(0, 0.03, 0)
			st.scale = Vector3(1.3, 0.55, 1.0)
			holder.add_child(st)
	# 小木橋：小石路跨過溪流的地方
	var bz := stream_z(dx)
	for i in range(9):
		var t := float(i) / 8.0
		var pz := bz - 1.25 + t * 2.5
		var py := GRASS_Y + 0.08 + sin(t * PI) * 0.22
		var plank := MeshInstance3D.new()
		plank.mesh = Models.box(1.15, 0.06, 0.26)
		plank.material_override = wood if i % 2 == 0 else wood_dark
		plank.position = Vector3(dx, py, pz)
		plank.rotation.x = -cos(t * PI) * 0.28
		holder.add_child(plank)
	for side_x in [-0.6, 0.6]:
		for i in range(3):
			var t2 := float(i) / 2.0
			var rp := MeshInstance3D.new()
			rp.mesh = Models.box(0.07, 0.5, 0.07)
			rp.material_override = wood_dark
			rp.position = Vector3(dx + side_x, GRASS_Y + 0.33 + sin(t2 * PI) * 0.22, bz - 1.1 + t2 * 2.2)
			holder.add_child(rp)
		var r0 := Vector3(dx + side_x, GRASS_Y + 0.55, bz - 1.1)
		var r1 := Vector3(dx + side_x, GRASS_Y + 0.77, bz)
		var r2 := Vector3(dx + side_x, GRASS_Y + 0.55, bz + 1.1)
		_cyl_between(holder, r0, r1, 0.035, 0.035, wood)
		_cyl_between(holder, r1, r2, 0.035, 0.035, wood)
	# 溪畔釣魚角：西邊岸上的小木平台、釣竿和水桶（派派狼常來釣魚）
	var fx := dx - 3.6
	var fzb := stream_z(fx) - 0.95
	var deck := MeshInstance3D.new()
	deck.mesh = Models.box(1.3, 0.08, 1.0)
	deck.material_override = wood
	deck.position = Vector3(fx, GRASS_Y + 0.1, fzb + 0.15)
	holder.add_child(deck)
	for k in range(4):
		var lg := MeshInstance3D.new()
		lg.mesh = Models.cyl(0.05, 0.05, 0.3)
		lg.material_override = wood_dark
		lg.position = Vector3(fx - 0.55 + (k % 2) * 1.1, GRASS_Y + 0.02, fzb - 0.3 + (1 if k >= 2 else 0) * 0.9)
		holder.add_child(lg)
	_cyl_between(holder, Vector3(fx + 0.4, GRASS_Y + 0.15, fzb - 0.2), Vector3(fx + 0.6, GRASS_Y + 1.25, fzb + 1.0), 0.025, 0.012, wood_dark)
	var bucket := MeshInstance3D.new()
	bucket.mesh = Models.cyl(0.16, 0.13, 0.26)
	bucket.material_override = Models.mat(Color("6f8fa8"))
	bucket.position = Vector3(fx - 0.35, GRASS_Y + 0.27, fzb - 0.05)
	holder.add_child(bucket)


## 在兩點之間放一根圓柱（r0 在 a 端、r1 在 b 端）；squash 可以把截面壓扁
func _cyl_between(holder: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var ln := a.distance_to(b)
	m.mesh = Models.cyl(r1, r0, ln)  # cyl(上半徑, 下半徑)：下端對著 a
	m.material_override = mat
	holder.add_child(m)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	m.transform = Transform3D(Basis(side * squash.x, up * squash.y, fwd * squash.z), (a + b) / 2)
	return m


## 來訪的角色。站在屋外就踩在草地高度。
func spawn_npc(who: String, pos: Vector3, facing: String) -> GopherActor:
	if npcs.has(who) and is_instance_valid(npcs[who]):
		npcs[who].queue_free()
	var a := GopherActor.new()
	a.name = "NPC_" + who
	add_child(a)
	a.setup(Models.character(who))
	a.speaker_name = NAMES.get(who, "")
	a.bubble_height = BUBBLE_H.get(who, 1.4)
	a.position = pos
	if world != null and not world.in_room(Vector2i(floor(pos.x), floor(pos.z))):
		a.position.y = GRASS_Y
	a.face(facing)
	a.model.rotation.y = a.target_yaw
	npcs[who] = a
	return a


func actor(who: String) -> GopherActor:
	if who == "gopher" or not npcs.has(who):
		return gopher
	return npcs[who]


static func talk_time(text: String) -> float:
	return clampf(0.7 + text.length() * 0.09, 1.2, 3.6)


func set_grid_visible(v: bool) -> void:
	grid_visible = v
	if grid_node:
		grid_node.visible = v


# ---------------- 家具 ----------------
static func item_pos(item: Dictionary, w: WorldModel) -> Vector3:
	var d := WorldModel.def_of(item.type)
	if item.wall != "":
		var c: Vector2i = item.cell
		match item.wall:
			"N": return Vector3(c.x + 0.5, 0, 0)
			"S": return Vector3(c.x + 0.5, 0, w.depth)
			"W": return Vector3(0, 0, c.y + 0.5)
			"E": return Vector3(w.width, 0, c.y + 0.5)
	if item.on != "" and w.items.has(item.on):
		var parent: Dictionary = w.items[item.on]
		var pd := WorldModel.def_of(parent.type)
		var base := item_pos(parent, w)
		return Vector3(base.x, float(pd.get("surface", pd.height)), base.z)
	var sz := WorldModel.footprint_size(item.type, item.rot)
	return Vector3(item.cell.x + sz.x / 2.0, 0, item.cell.y + sz.y / 2.0)


static func item_yaw(item: Dictionary) -> float:
	if item.wall != "":
		return {"N": 0.0, "S": PI, "W": PI / 2, "E": -PI / 2}[item.wall]
	return -item.rot * PI / 2


func _spawn_item(uid: String) -> Node3D:
	var item: Dictionary = world.items[uid]
	var node := Models.furniture(item.type)
	node.name = "F_" + uid
	add_child(node)
	furniture_nodes[uid] = node
	_place_node(uid)
	if _hides_with_wall(item):
		# 掛牆裝飾、門窗都跟著牆一起隱藏
		node.reparent(walls[item.wall])
	return node


static func _hides_with_wall(item: Dictionary) -> bool:
	return item.wall != ""  # 牆上的東西（包括門）跟著牆一起隱藏，不會剩一扇門站在那裡


func _place_node(uid: String) -> void:
	var item: Dictionary = world.items[uid]
	var node: Node3D = furniture_nodes[uid]
	node.position = item_pos(item, world)
	node.rotation.y = item_yaw(item)


func add_item(uid: String) -> void:
	_spawn_item(uid)


func remove_item(uid: String) -> void:
	if furniture_nodes.has(uid):
		furniture_nodes[uid].queue_free()
		furniture_nodes.erase(uid)


func refresh_item(uid: String) -> void:
	if not furniture_nodes.has(uid):
		return
	var item: Dictionary = world.items[uid]
	var node: Node3D = furniture_nodes[uid]
	var want_parent: Node3D = walls[item.wall] if _hides_with_wall(item) else self
	if node.get_parent() != want_parent:
		node.reparent(want_parent, false)
	_place_node(uid)
	for child in world.children_of(uid):
		refresh_item(child)


## 整個房間依照 world 重新擺好（任務重來時用）
func reset_to(w: WorldModel) -> void:
	build(w)


# ---------------- 虛線影子 ----------------
func clear_ghosts() -> void:
	for c in ghosts.get_children():
		c.queue_free()


func show_ghost(uid: String, cell: Vector2i) -> void:
	if not world.items.has(uid):
		return
	var item: Dictionary = world.items[uid].duplicate()
	item.cell = cell
	item.on = ""
	var node := Models.furniture(item.type)
	_make_ghost(node, Color(0.35, 0.75, 1.0, 0.35))
	node.position = item_pos(item, world)
	node.rotation.y = item_yaw(item)
	ghosts.add_child(node)
	var ring := MeshInstance3D.new()
	var sz := WorldModel.footprint_size(item.type, item.rot)
	ring.mesh = Models.box(sz.x - 0.08, 0.02, sz.y - 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.3, 0.7, 1.0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	ring.position = node.position + Vector3(0, 0.02, 0)
	ghosts.add_child(ring)
	var tw := create_tween().set_loops()
	tw.tween_property(node, "position:y", 0.12, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)


static var _ghost_mats: Dictionary = {}


static func _make_ghost(node: Node, color: Color) -> void:
	# 同一種顏色共用一個材質（拖曳時每次滑鼠移動都會呼叫，避免一直新建／釋放）
	var key := color.to_html()
	if not _ghost_mats.has(key):
		var nm := StandardMaterial3D.new()
		nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nm.albedo_color = color
		nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mats[key] = nm
	var m: StandardMaterial3D = _ghost_mats[key]
	for c in node.find_children("*", "MeshInstance3D", true, false):
		if c.material_override != m:
			c.material_override = m
	for l in node.find_children("*", "OmniLight3D", true, false):
		l.visible = false


static func tint(node: Node, color: Color) -> void:
	_make_ghost(node, color)


# ---------------- 鏡頭相關 ----------------
## false：每面牆都顯示（開場從屋外看門口時用）
var cutaway := true


func update_cutaway(cam_pos: Vector3) -> void:
	if not cutaway:
		for side in walls:
			walls[side].visible = true
		return
	var center := Vector3(world.width / 2.0, 0, world.depth / 2.0)
	var to_cam := cam_pos - center
	var normals := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0), "E": Vector3(1, 0, 0)}
	for side in walls:
		var n: Vector3 = normals[side]
		var half: float = (world.depth if side in ["N", "S"] else world.width) / 2.0
		walls[side].visible = to_cam.dot(n) < half * 0.6


# ---------------- 門 ----------------
## 門板裝在一個鉸鏈節點上，開門就是轉鉸鏈（往屋裡開）
func _door_hinge(side: String = "S") -> Node3D:
	for uid in world.items:
		var it: Dictionary = world.items[uid]
		if it.type != "door" or it.wall != side or not furniture_nodes.has(uid):
			continue
		var node: Node3D = furniture_nodes[uid]
		var h := node.get_node_or_null("Hinge") as Node3D
		if h == null:
			h = Node3D.new()
			h.name = "Hinge"
			h.position = Vector3(-0.43, 0, 0.03)
			var kids := node.get_children()
			node.add_child(h)
			for k in kids:
				k.reparent(h, true)
		return h
	return null


func swing_door(open: bool, side: String = "S") -> void:
	var h := _door_hinge(side)
	if h == null:
		return
	var tw := create_tween()
	tw.tween_property(h, "rotation:y", deg_to_rad(-95.0) if open else 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	await tw.finished


# ---------------- 任務演出 ----------------
## 演出一個動作結果（由 TaskRunner 先算好）。回傳後畫面狀態 = 動作後。
func play_result(res: Dictionary, speed: float) -> void:
	gopher.speed_scale = speed
	match res.act:
		"walk_to", "forward":
			await gopher.walk_path(res.get("path", []), null)
			if res.has("dir"):
				await gopher.turn_to(res.dir)
			if not res.ok:
				await gopher.confused()
		"turn_left", "turn_right":
			await gopher.turn_to(res.dir)
		"pick_up":
			if res.ok:
				await gopher.pick(furniture_nodes[res.uid])
			else:
				await gopher.confused()
		"put_down":
			if res.ok:
				var item: Dictionary = world.items[res.uid]
				item.cell = res.cell
				var node := await gopher.drop(self, item_pos(item, world))
				node.rotation.y = item_yaw(item)
			else:
				await gopher.confused()
		"push":
			var steps: int = res.get("steps", 0)
			if steps > 0:
				var node2: Node3D = furniture_nodes[res.uid]
				var d: Vector2i = WorldModel.DIRS[gopher.dir]
				var cells: Array = [world.gopher_cell]
				var c: Vector2i = world.gopher_cell
				for i in range(steps):
					c += d
					cells.append(c)
				gopher.pushing = true
				await gopher.walk_path(cells, node2)
				gopher.pushing = false
				world.gopher_cell = c
				world.items[res.uid].cell += d * steps
			if not res.ok:
				await gopher.confused()
		"say":
			var sp := actor(res.get("who", "gopher"))
			sp.say(res.text, "say")
			await get_tree().create_timer((talk_time(res.text) if res.has("who") else 1.1) / speed).timeout
		"ask":
			# 對話任務的 input()：問的人說出問題，派派鼠說出回答
			var asker := actor(res.who)
			asker.say(res.text, "say")
			await get_tree().create_timer(talk_time(res.text) / speed).timeout
			if res.has("answer"):
				gopher.say(res.answer, "say")
				await get_tree().create_timer(talk_time(res.answer) / speed).timeout
		"dlg_fail":
			# 說錯了：聽的人聽不懂
			var lis := actor(res.get("who", "wolf"))
			var said: String = res.get("text", "")
			if res.get("by_gopher", false) and said != "":
				gopher.say(said, "say")  # 派派鼠說錯的那句留著，和「聽不懂」並排對照
			if said.length() > 12:
				said = said.substr(0, 12) + "…"
			lis.say(("蛤？「%s」？聽不懂…" % said) if said != "" else "嗯？還沒說完喔…", "fail")
			gopher.set_face("confused", 2.2)
			await lis.confused()
			return
		"confused":
			await gopher.confused()
	if not res.ok:
		gopher.say(res.get("reason", "咦？"), "fail")
	# 同步畫面用的世界狀態（只有位置與方向）
	if res.act in ["walk_to", "forward"] and res.has("path") and not res.path.is_empty():
		world.gopher_cell = res.path[-1]
	if res.has("dir"):
		world.gopher_dir = res.dir
	world.gopher_dir = gopher.dir
