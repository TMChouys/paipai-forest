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
const NAMES := {"gopher": "派派鼠", "wolf": "派派狼", "rabbit": "派派兔"}
const BUBBLE_H := {"gopher": 1.3, "wolf": 1.45, "rabbit": 1.6}
var grid_visible := true
var room_name := ""


func build(w: WorldModel) -> void:
	world = w
	for c in get_children():
		c.queue_free()
	furniture_nodes.clear()
	walls.clear()
	npcs.clear()
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


# ---------------- 建構 ----------------
func _build_floor() -> void:
	var floor_root := Node3D.new()
	floor_root.name = "Floor"
	add_child(floor_root)
	# 底板（木條之間縫隙的深色）
	var base := MeshInstance3D.new()
	base.mesh = Models.box(world.width, 0.1, world.depth)
	base.material_override = Models.mat(Color("6e4a2e"), false)
	base.position = Vector3(world.width / 2.0, -0.065, world.depth / 2.0)
	floor_root.add_child(base)
	# 棋盤格木地板：深淺兩色交錯，每格三片木條、方向也交錯（拼花）
	var light := [Color("e4b97f"), Color("dcb076"), Color("e8c08a")]
	var dark := [Color("b07a49"), Color("a87243"), Color("b8824f")]
	for x in range(world.width):
		for z in range(world.depth):
			var odd := (x + z) % 2 == 1
			var tones: Array = dark if odd else light
			for k in range(3):
				var plank := MeshInstance3D.new()
				var off := -0.32 + k * 0.32
				if odd:
					plank.mesh = Models.box(0.3, 0.1, 0.955)
					plank.position = Vector3(x + 0.5 + off, -0.05, z + 0.5)
				else:
					plank.mesh = Models.box(0.955, 0.1, 0.3)
					plank.position = Vector3(x + 0.5, -0.05, z + 0.5 + off)
				plank.material_override = Models.mat(tones[(x * 3 + z * 5 + k) % 3], false)
				floor_root.add_child(plank)
	# 屋外：派派森林的草地
	var grass := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(70, 70)
	grass.mesh = pm
	grass.material_override = Models.mat(Color("9cc97e"), false)
	grass.position = Vector3(world.width / 2.0, GRASS_Y, world.depth / 2.0)
	floor_root.add_child(grass)
	# 圓形苔蘚地毯
	var rug := MeshInstance3D.new()
	rug.mesh = Models.cyl(1.4, 1.4, 0.02)
	rug.material_override = Models.mat(Color("b9d48f"), false)
	rug.scale = Vector3(1.2, 1, 0.8)
	rug.position = Vector3(world.width / 2.0, 0.005, world.depth / 2.0 + 0.5)
	floor_root.add_child(rug)


func _build_walls() -> void:
	var specs := {
		"N": {"pos": Vector3(world.width / 2.0, WALL_H / 2, -WALL_T / 2), "size": Vector3(world.width + WALL_T * 2, WALL_H, WALL_T)},
		"S": {"pos": Vector3(world.width / 2.0, WALL_H / 2, world.depth + WALL_T / 2), "size": Vector3(world.width + WALL_T * 2, WALL_H, WALL_T)},
		"W": {"pos": Vector3(-WALL_T / 2, WALL_H / 2, world.depth / 2.0), "size": Vector3(WALL_T, WALL_H, world.depth)},
		"E": {"pos": Vector3(world.width + WALL_T / 2, WALL_H / 2, world.depth / 2.0), "size": Vector3(WALL_T, WALL_H, world.depth)},
	}
	for side in specs:
		var holder := Node3D.new()
		holder.name = "Wall" + side
		add_child(holder)
		var s: Dictionary = specs[side]
		var wall := MeshInstance3D.new()
		wall.mesh = Models.box(s.size.x, s.size.y, s.size.z)
		wall.material_override = Models.mat(Color("d9ab76"))
		wall.position = s.pos
		holder.add_child(wall)
		var ws: Vector3 = s.size
		var along_x: bool = side in ["N", "S"]
		# 原木牆：一圈一圈橫向的木頭（凸出牆面一點點）
		for i in range(6):
			var log_m := MeshInstance3D.new()
			log_m.mesh = Models.box(ws.x + (0.0 if along_x else 0.03), 0.05, ws.z + (0.03 if along_x else 0.0))
			log_m.material_override = Models.mat(Color("b98654"), false)
			log_m.position = Vector3(s.pos.x, 0.62 + i * 0.3, s.pos.z)
			holder.add_child(log_m)
		# 下半截：樹根色的護牆板
		var wain := MeshInstance3D.new()
		wain.mesh = Models.box(ws.x + (0.0 if along_x else 0.02), 0.55, ws.z + (0.02 if along_x else 0.0))
		wain.material_override = Models.mat(Color("8a5a36"), false)
		wain.position = Vector3(s.pos.x, 0.275, s.pos.z)
		holder.add_child(wain)
		# 牆頂的橫樑
		var beam := MeshInstance3D.new()
		beam.mesh = Models.box(ws.x + 0.06, 0.12, ws.z + 0.06)
		beam.material_override = Models.mat(Color("7a4f2f"))
		beam.position = Vector3(s.pos.x, WALL_H, s.pos.z)
		holder.add_child(beam)
		walls[side] = holder


func _build_grid() -> void:
	grid_node = Node3D.new()
	grid_node.name = "Grid"
	add_child(grid_node)
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.45, 0.3, 0.2, 0.45)
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
	["tree_detailed", 13.5, 7.5, 3.0, 80], ["tree_small", -2.0, 10.5, 2.2, 0], ["tree_oak", 9.5, 12.0, 3.2, 120],
	["tree_detailed", -5.5, 13.5, 3.8, 0], ["tree_fat", 15.0, 2.0, 2.8, 0], ["tree_default", 4.0, -7.5, 3.0, 200],
	["tree_oak", -6.5, 1.0, 3.6, 60], ["tree_default", -7.0, 8.0, 3.4, 150], ["tree_small", -4.8, -4.5, 2.4, 20],
	["tree_detailed", 16.5, 11.5, 3.4, 10], ["tree_oak", 17.0, -2.5, 3.6, 90], ["tree_small", 11.5, 15.5, 2.4, 0],
	["tree_fat", 0.5, 16.0, 3.0, 30], ["tree_default", 7.5, 17.5, 3.4, 0], ["tree_detailed", -3.0, 17.5, 3.6, 70],
	["tree_oak", 14.0, 15.5, 3.2, 200], ["tree_small", 10.8, -5.5, 2.4, 0], ["tree_fat", -8.5, 12.5, 3.0, 0],
	["plant_bushLarge", -1.3, 1.2, 1.1, 0], ["plant_bush", -2.4, 7.4, 0.8, 30], ["plant_bush", 9.4, 3.0, 0.9, 0],
	["plant_bushLarge", 10.0, 9.5, 1.2, 0], ["plant_bush", 1.2, 12.5, 0.9, 0], ["plant_bushLarge", 6.0, 13.5, 1.0, 50],
	["flower_redA", -0.8, 8.6, 0.5, 0], ["flower_yellowA", 1.0, 9.1, 0.5, 40], ["flower_purpleA", 6.0, 8.8, 0.5, 0],
	["flower_yellowA", 7.2, 9.3, 0.5, 70], ["flower_redA", -1.6, 3.0, 0.5, 20], ["flower_purpleA", 9.3, 7.8, 0.5, 0],
	["mushroom_redGroup", -1.5, 9.8, 0.6, 0], ["mushroom_tanGroup", 9.8, 10.2, 0.6, 0], ["stump_round", -3.8, 7.5, 0.7, 0],
	["mushroom_redGroup", 11.0, 4.5, 0.6, 30], ["mushroom_tanGroup", -2.5, -0.2, 0.6, 0],
	["log", -4.2, 9.0, 1.6, 30], ["rock_smallA", 8.8, 11.0, 0.6, 0], ["rock_smallA", -1.0, 12.0, 0.5, 40],
	["path_stone", 3.5, 8.8, 1.0, 0], ["path_stone", 3.6, 9.9, 1.0, 15], ["path_stone", 3.4, 11.0, 1.0, 0],
	["path_stone", 3.7, 12.1, 1.0, 30], ["path_stone", 3.5, 13.2, 1.0, 10],
]


func build_outdoor() -> void:
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


## 地洞樹屋：房子蓋在一棵大樹的樹根底下。樹幹在北牆後面，粗樹根沿著兩側牆外伸出來。
func _build_big_tree(holder: Node3D) -> void:
	var bark := Models.mat(Color("7a5234"))
	var bark_dark := Models.mat(Color("5e3d26"), false)
	var w := float(world.width)
	var r_top := w * 0.3
	var r_bot := w * 0.38
	var center := Vector3(w / 2.0, 0, -r_bot - 0.25)  # 整棵樹都在北牆後面，不會擋到房間
	var trunk := MeshInstance3D.new()
	trunk.mesh = Models.cyl(r_top, r_bot, 7.0)
	trunk.material_override = bark
	trunk.position = center + Vector3(0, 3.4, 0)
	holder.add_child(trunk)
	# 樹皮紋路
	for i in range(12):
		var a := float(i) / 12.0 * TAU
		var r := (r_top + r_bot) / 2.0 + 0.02
		if sin(a) > 0.3:
			continue  # 靠房子那一側看不到，不用做
		var stripe := MeshInstance3D.new()
		stripe.mesh = Models.box(0.14, 6.6, 0.14)
		stripe.material_override = bark_dark
		stripe.position = center + Vector3(cos(a) * r, 3.2, sin(a) * r)
		holder.add_child(stripe)
	# 樹冠
	var leaf := Models.mat(Color("6fae5a"))
	var leaf2 := Models.mat(Color("82c06a"))
	var crown := [[0, 8.2, 0, 4.2], [-3.2, 7.4, 1.0, 3.0], [3.4, 7.6, 0.6, 3.2], [-1.5, 9.6, -0.8, 2.8], [1.8, 9.4, 1.4, 2.6], [0, 7.0, 2.6, 2.6]]
	for i in range(crown.size()):
		var c: Array = crown[i]
		var ball := MeshInstance3D.new()
		ball.mesh = Models.sphere(c[3])
		ball.material_override = leaf if i % 2 == 0 else leaf2
		ball.position = center + Vector3(c[0], c[1], c[2])
		holder.add_child(ball)
	# 粗樹根：從樹幹沿著東西兩側牆外伸出來
	for sx in [-1, 1]:
		for j in range(2):
			var root := MeshInstance3D.new()
			var length := 3.6 - j * 1.0
			root.mesh = Models.cyl(0.3 - j * 0.06, 0.1, length)
			root.material_override = bark
			var x0: float = w / 2.0 + sx * (w / 2.0 + 0.35 + j * 0.25)
			root.position = Vector3(x0, GRASS_Y + 0.12, length / 2.0 - 0.6 + j * 1.6)
			root.rotation_degrees = Vector3(90, 0, 0)
			holder.add_child(root)
	# 房子上方：從大樹延伸出來的木頭屋簷
	var eave := MeshInstance3D.new()
	eave.mesh = Models.box(w + 0.6, 0.18, 0.9)
	eave.material_override = Models.mat(Color("8f5f38"))
	eave.position = Vector3(w / 2.0, WALL_H + 0.25, -0.25)
	holder.add_child(eave)


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
		# 掛牆裝飾跟著牆一起隱藏（門窗一直顯示，方便看出門口在哪）
		node.reparent(walls[item.wall])
	return node


static func _hides_with_wall(item: Dictionary) -> bool:
	return item.wall != "" and not WorldModel.def_of(item.type).get("fixed", false)


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
func update_cutaway(cam_pos: Vector3) -> void:
	var center := Vector3(world.width / 2.0, 0, world.depth / 2.0)
	var to_cam := cam_pos - center
	var normals := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0), "E": Vector3(1, 0, 0)}
	for side in walls:
		var n: Vector3 = normals[side]
		var half: float = (world.depth if side in ["N", "S"] else world.width) / 2.0
		walls[side].visible = to_cam.dot(n) < half * 0.6


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
