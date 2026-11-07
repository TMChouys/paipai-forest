extends Node3D
## 遊戲主控：派派鼠的樹屋（滑鼠擺設、派派鼠閒晃）⇄ 任務（寫程式、演出、交件評分）。
## 派派狼發任務，派派兔跟著他一起來。第一次進遊戲先演開場故事。

const SAVE_PATH := "user://save.json"

var mode := "home"
var save: Dictionary = {}
var tasks: Array = []
var home_world: WorldModel

var room: RoomView
var rig: CameraRig
var ui_layer: CanvasLayer
var bubbles: BubbleLayer
var hud: HomeHUD
var panel: TaskPanel
var report: ReportPanel
var book: QuestBook
var playback: Playback

# 任務狀態
var task: Dictionary = {}
var last_report: Dictionary = {}
var run_id := 0  # 每次重設房間就換號，等 input() 回答的舊執行看到號碼變了就停

# 擺設狀態
var held: Dictionary = {}  # {uid, type, rot, orig(item|null), node, target(item|null), reason}
var roam_timer := 2.0
var roam_busy := false
var uid_counter := 0


func _ready() -> void:
	_setup_environment()
	rig = CameraRig.new()
	add_child(rig)
	room = RoomView.new()
	add_child(room)
	playback = Playback.new()
	add_child(playback)

	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	bubbles = BubbleLayer.new()
	bubbles.camera_getter = func(): return rig.cam
	hud = HomeHUD.new()
	panel = TaskPanel.new()
	report = ReportPanel.new()
	book = QuestBook.new()
	ui_layer.add_child(hud)
	ui_layer.add_child(panel)
	ui_layer.add_child(bubbles)
	ui_layer.add_child(report)
	ui_layer.add_child(book)
	report.visible = false
	panel.visible = false

	hud.take_from_inventory.connect(_take_from_inventory)
	hud.open_board.connect(_open_board)
	hud.grid_toggled.connect(func(): room.set_grid_visible(not room.grid_visible))
	hud.view_reset.connect(func(): rig.reset_view())
	hud.task_chosen.connect(_enter_task)
	hud.reduce_motion_toggled.connect(_set_reduce_motion)
	hud.open_book.connect(_open_book)
	book.task_chosen.connect(func(id):
		book.visible = false
		_enter_task(id))
	panel.grid_toggled.connect(func(): room.set_grid_visible(not room.grid_visible))
	panel.view_reset.connect(func(): rig.reset_view())
	panel.exit_pressed.connect(_exit_task)
	panel.demo_pressed.connect(_demo)
	panel.run_pressed.connect(func(): _run(false))
	panel.step_pressed.connect(_step)
	panel.pause_pressed.connect(func(): playback.toggle_pause())
	panel.speed_changed.connect(func(s): playback.speed = s)
	panel.reset_pressed.connect(_reset_task_room)
	panel.submit_pressed.connect(_submit)
	panel.code.text_changed.connect(_on_code_changed)
	report.retry_pressed.connect(func(): report.visible = false)
	report.accept_pressed.connect(_accept_reward)

	tasks = TaskRunner.list_tasks()
	_load_save()
	UIKit.reduce_motion = save.get("reduce_motion", false)
	hud.set_reduce_motion(UIKit.reduce_motion)
	_enter_home()
	# 自動截圖（開發驗證用）：godot -- --shot=res://…
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_auto_shot(arg.substr(7))


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("9fd3e6")
	sm.sky_horizon_color = Color("fff1d6")
	sm.ground_horizon_color = Color("fff1d6")
	sm.ground_bottom_color = Color("bfe0a5")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff1e0")
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d6")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 40
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)


# ---------------- 存檔 ----------------
func _load_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary and int(data.get("version", 0)) == 1:
			save = data
	if save.is_empty():
		var hf := FileAccess.open("res://data/home.json", FileAccess.READ)
		var home: Dictionary = JSON.parse_string(hf.get_as_text())
		save = {"version": 1, "home": home, "inventory": home.get("inventory", {}), "stars": {}, "codes": {}}
	home_world = WorldModel.from_layout(save.home)
	uid_counter = int(save.get("uid_counter", 100))


func _write_save() -> void:
	if home_world != null:
		save.home = home_world.to_layout()
	save.uid_counter = uid_counter
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save, "  "))


func _total_stars() -> int:
	var n := 0
	for k in save.stars:
		n += int(save.stars[k])
	return n


# ---------------- 家 ----------------
func _enter_home() -> void:
	mode = "home"
	bubbles.avoid_side_panels = false
	playback.cancel()
	task = {}
	bubbles.clear_all()
	room.build(home_world)
	room.set_grid_visible(false)  # 家裡不顯示格子（⋯ 選單可以打開）
	room.build_outdoor()
	room.gopher.bubble_requested.connect(_on_bubble)
	_spawn_visitors(home_world)
	rig.frame_room(home_world.width, home_world.depth)
	rig.screen_offset = 0.0
	rig.follow_target = null
	hud.visible = true
	panel.visible = false
	report.visible = false
	hud.set_inventory(save.inventory)
	hud.set_stars(_total_stars())
	roam_timer = 1.5
	roam_busy = false
	if not save.get("intro_done", false):
		_play_intro()
	else:
		_update_task_cue()


func _set_reduce_motion(on: bool) -> void:
	UIKit.reduce_motion = on
	save.reduce_motion = on
	_write_save()
	_update_task_cue()


## 有新任務：「派派狼的任務」變成主要按鈕，派派狼頭上冒一個「！」
func _update_task_cue() -> void:
	var has_new := HomeHUD.has_new_task(tasks, save.stars)
	hud.set_task_cue(has_new)
	var wolf: GopherActor = room.npcs.get("wolf")
	if wolf == null or not is_instance_valid(wolf):
		return
	var old := wolf.get_node_or_null("TaskMark")
	if old:
		old.free()
	if not has_new or mode != "home" or intro_running:
		return
	var m := Label3D.new()
	m.name = "TaskMark"
	m.text = "！"
	m.font = UIKit.font_bold()
	m.font_size = 128
	m.outline_size = 36
	m.pixel_size = 0.006
	m.modulate = Color("c8693a")
	m.outline_modulate = Color("fff8ec")
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = 10
	m.position = Vector3(0, wolf.bubble_height + 0.15, 0)
	wolf.add_child(m)
	if not UIKit.reduce_motion:
		var tw := m.create_tween().set_loops()
		tw.tween_property(m, "position:y", m.position.y + 0.08, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(m, "position:y", m.position.y, 0.6).set_trans(Tween.TRANS_SINE)


## 派派狼和派派兔站在屋子西側外面（鏡頭從西南方看，這面牆會自動隱藏，看得到他們）
static func visitor_spot(who: String, w: WorldModel) -> Vector3:
	return Vector3(-1.0, 0, w.depth - 4.6) if who == "wolf" else Vector3(-1.25, 0, w.depth - 3.4)


func _spawn_visitors(w: WorldModel, who_list: Array = ["wolf", "rabbit"]) -> void:
	for who in who_list:
		var a := room.spawn_npc(who, visitor_spot(who, w), "E")
		a.bubble_requested.connect(_on_bubble)


static func _door_x(w: WorldModel) -> float:
	for uid in w.items:
		var it: Dictionary = w.items[uid]
		if it.type == "door" and it.wall == "S":
			return it.cell.x + 0.5
	return w.width / 2.0


## 任務房間：task.room.npcs 有寫就站在房間裡，不然在門口外
func _spawn_task_npcs(w: WorldModel) -> void:
	var list: Array = task.room.get("npcs", [])
	if list.is_empty():
		_spawn_visitors(w)
		return
	for n in list:
		var a := room.spawn_npc(n.who, GopherActor.cell_pos(Vector2i(n.cell[0], n.cell[1])), n.get("dir", "N"))
		a.bubble_requested.connect(_on_bubble)


## 發任務的人（任務的 npc；在家就是派派狼）
func _giver() -> GopherActor:
	var who: String = task.get("npc", "wolf") if not task.is_empty() else "wolf"
	return room.actor(who)


# ---------------- 開場故事 ----------------
var intro_running := false
var intro_advance := false  # 點一下畫面：跳到下一句
var intro_skip := false
var intro_skip_btn: Button


func _play_intro() -> void:
	intro_running = true
	intro_skip = false
	intro_advance = false
	roam_busy = true
	hud.visible = false  # 開場時不顯示工具列，專心看故事
	intro_skip_btn = UIKit.button("略過 ▶▶", func(): intro_skip = true, "直接跳過開場")
	intro_skip_btn.anchor_left = 1
	intro_skip_btn.anchor_right = 1
	intro_skip_btn.anchor_top = 1
	intro_skip_btn.anchor_bottom = 1
	intro_skip_btn.offset_left = -130
	intro_skip_btn.offset_right = -16
	intro_skip_btn.offset_top = -56
	intro_skip_btn.offset_bottom = -16
	intro_skip_btn.theme = UIKit.theme()
	ui_layer.add_child(intro_skip_btn)
	var wolf: GopherActor = room.npcs.wolf
	var rabbit: GopherActor = room.npcs.rabbit
	var g := room.gopher
	var w := home_world
	var wolf_spot := wolf.position
	var rabbit_spot := rabbit.position
	# 兩人從森林小路走過來
	wolf.position = Vector3(_door_x(w), wolf_spot.y, w.depth + 5.0)
	rabbit.position = Vector3(_door_x(w) + 0.8, rabbit_spot.y, w.depth + 6.2)
	# 鏡頭：從南邊低低地看（像舞台側面），屋裡的派派鼠和西牆外的訪客面對面
	rig.target_focus = Vector3(-0.2, 0.3, w.depth - 4.0)
	rig.target_distance = 6.0
	rig.target_yaw = deg_to_rad(8.0)
	rig.target_pitch = deg_to_rad(-22.0)
	g.say("（剛搬進派森小鎮的新家…）", "think")
	# 派派鼠走到西牆邊
	var meet := _nearest_walkable(Vector2i(0, w.depth - 4))
	var path := w.find_path(_nearest_walkable(w.gopher_cell), meet)
	if path.size() > 1:
		await g.walk_path(path)
		w.gopher_cell = meet
	if not is_instance_valid(wolf) or not is_instance_valid(rabbit) or mode != "home":
		_end_intro()
		return  # 開場途中離開或房間重建了
	g.face("W")
	if intro_skip:
		wolf.position = wolf_spot
		rabbit.position = rabbit_spot
		wolf.face("E")
		rabbit.face("E")
	else:
		wolf.walk_to_point(wolf_spot, 1.0, "E")
		await get_tree().create_timer(0.6).timeout
		if is_instance_valid(rabbit):
			await rabbit.walk_to_point(rabbit_spot, 1.0, "E")
		await get_tree().create_timer(0.3).timeout
	var lines := [
		[wolf, "嘿！新來的，以後跟著我混。"],
		[rabbit, "（推推眼鏡）我是派派兔，跟著派派狼一起來的～"],
		[g, "……？"],
		[wolf, "怎麼不說話？在派森小鎮，要用 Python 的 print() 才能說話喔！"],
		[rabbit, "點派派狼接任務，學會 print() 就能跟我們聊天了！"],
	]
	for l in lines:
		if mode != "home" or not is_instance_valid(l[0]) or intro_skip:
			break
		var who: GopherActor = l[0]
		who.say(l[1], "say")
		# 停留時間和氣泡一樣依字數（每字 0.12 秒、至少 2.4 秒）；點畫面可以提早換下一句
		var until := Time.get_ticks_msec() + int((maxf(2.4, 1.0 + String(l[1]).length() * 0.12) + 0.3) * 1000)
		intro_advance = false
		while Time.get_ticks_msec() < until and not intro_advance and not intro_skip:
			await get_tree().process_frame
	if intro_skip:
		bubbles.clear_all()
	save.intro_done = true
	_write_save()
	_end_intro()
	if mode == "home":
		rig.reset_view()


func _end_intro() -> void:
	intro_running = false
	roam_busy = false
	if is_instance_valid(intro_skip_btn):
		intro_skip_btn.queue_free()
	if mode == "home":
		hud.visible = true
		_update_task_cue()


func _on_bubble(actor: Node3D, text: String, kind: String) -> void:
	if kind == "wait":
		bubbles.show_bubble(actor, text, "say", 600.0)
		return
	var secs := maxf(2.4, 1.0 + text.length() * 0.12)
	bubbles.show_bubble(actor, text, kind, maxf(secs, 3.2) if kind == "fail" else secs)


func _open_book() -> void:
	_cancel_held()
	hud.board.visible = false
	book.open(save.stars, func(gid: String) -> bool:
		var t := _task_by_id(gid)
		return not t.is_empty() and HomeHUD.is_unlocked(t, tasks, save.stars))


func _open_board() -> void:
	_cancel_held()
	hud.show_board(tasks, save.stars)
	_giver().say("新來的，來接任務吧！", "say")


# ---------------- 派派鼠閒晃 ----------------
func _process(delta: float) -> void:
	if rig.cam:
		room.update_cutaway(rig.cam.global_position)
	if mode != "home" or roam_busy or room.gopher == null:
		return
	roam_timer -= delta
	if roam_timer <= 0:
		roam_timer = randf_range(2.5, 5.5)
		_roam()


func _roam() -> void:
	roam_busy = true
	var g := room.gopher
	g.speed_scale = 0.8
	var w := home_world
	var start := _nearest_walkable(w.gopher_cell)
	# 40% 去使用家具
	var users: Array = []
	for uid in w.items:
		var it: Dictionary = w.items[uid]
		if it.wall == "" and it.on == "" and WorldModel.def_of(it.type).has("use") and uid != held.get("uid", ""):
			users.append(uid)
	if not users.is_empty() and randf() < 0.45:
		var uid: String = users.pick_random()
		var it2: Dictionary = w.items[uid]
		var best: Array = []
		for c in w.footprint(it2):
			for dn in WorldModel.DIR_ORDER:
				var nb: Vector2i = c + WorldModel.DIRS[dn]
				if w.walkable(nb):
					var p := w.find_path(start, nb)
					if not p.is_empty() and (best.is_empty() or p.size() < best.size()):
						best = p
		if not best.is_empty():
			await g.walk_path(best)
			w.gopher_cell = best[-1]
			await _use_furniture(uid)
			roam_busy = false
			return
	# 隨便走走
	var target := Vector2i(randi_range(0, w.width - 1), randi_range(0, w.depth - 1))
	var path := w.find_path(start, target)
	if path.size() > 1:
		path = path.slice(0, min(path.size(), 5))
		await g.walk_path(path)
		w.gopher_cell = path[-1]
	elif randf() < 0.3:
		await g.hop(0.15)
	roam_busy = false


func _use_furniture(uid: String) -> void:
	if mode != "home" or not home_world.items.has(uid):
		return
	var g := room.gopher
	var it: Dictionary = home_world.items[uid]
	var center := RoomView.item_pos(it, home_world)
	g.face_vector(center - g.position)
	await get_tree().create_timer(0.3).timeout
	var use: String = WorldModel.def_of(it.type).get("use", "")
	var back := g.position
	match use:
		"sit":
			var tw := create_tween()
			tw.tween_property(g, "position", center + Vector3(0, 0.48, 0), 0.35)
			await tw.finished
			g.target_yaw = RoomView.item_yaw(it) + 0.0
			g.set_seated(true)
			g.say("坐一下～", "say")
			await get_tree().create_timer(3.0).timeout
			if is_instance_valid(g):
				g.set_seated(false)
		"sleep":
			var tw2 := create_tween()
			tw2.tween_property(g, "position", center + Vector3(0, 0.5, 0.2), 0.4)
			tw2.parallel().tween_property(g.model, "rotation:x", -PI / 2.2, 0.4)
			await tw2.finished
			g.say("Zzz…", "think")
			await get_tree().create_timer(4.0).timeout
			var tw3 := create_tween()
			tw3.tween_property(g.model, "rotation:x", 0.0, 0.3)
			await tw3.finished
		"read":
			g.say("看書中…", "think")
			await get_tree().create_timer(3.0).timeout
	if mode != "home":
		return
	var tw4 := create_tween()
	tw4.tween_property(g, "position", back, 0.3)
	await tw4.finished


func _nearest_walkable(c: Vector2i) -> Vector2i:
	if home_world.walkable(c):
		return c
	for r in range(1, 10):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var n := c + Vector2i(dx, dz)
				if home_world.walkable(n):
					return n
	return c


# ---------------- 滑鼠擺設 ----------------
func _mouse_ray() -> Dictionary:
	var mp := get_viewport().get_mouse_position()
	return {"from": rig.cam.project_ray_origin(mp), "dir": rig.cam.project_ray_normal(mp)}


## 回傳滑鼠指到的東西：{floor: Vector2i?, wall: "N"…, wall_cell: Vector2i, dist}
func _hit() -> Dictionary:
	var r := _mouse_ray()
	var from: Vector3 = r.from
	var dir: Vector3 = r.dir
	var w := room.world
	var best := {}
	var best_t := INF
	if abs(dir.y) > 0.0001:
		var t: float = -from.y / dir.y
		if t > 0:
			var p := from + dir * t
			var c := Vector2i(floor(p.x), floor(p.z))
			if w.in_room(c):
				best = {"floor": c, "point": p}
				best_t = t
	var planes := {"N": [Vector3(0, 0, 1), 0.0], "S": [Vector3(0, 0, -1), float(w.depth)], "W": [Vector3(1, 0, 0), 0.0], "E": [Vector3(-1, 0, 0), float(w.width)]}
	for side in planes:
		if not room.walls[side].visible:
			continue
		var n: Vector3 = planes[side][0]
		var axis_val: float = planes[side][1]
		var denom := dir.dot(n)
		if abs(denom) < 0.0001:
			continue
		var t2: float
		if side in ["N", "S"]:
			t2 = (axis_val - from.z) / dir.z
		else:
			t2 = (axis_val - from.x) / dir.x
		if t2 <= 0 or t2 >= best_t:
			continue
		var p2 := from + dir * t2
		if p2.y < 0.2 or p2.y > RoomView.WALL_H:
			continue
		var cell := Vector2i(floor(p2.x), 0) if side in ["N", "S"] else Vector2i(0, floor(p2.z))
		if side == "S":
			cell = Vector2i(floor(p2.x), w.depth - 1)
		if side == "E":
			cell = Vector2i(w.width - 1, floor(p2.z))
		if not w.in_room(cell):
			continue
		best = {"wall": side, "wall_cell": cell, "point": p2}
		best_t = t2
	return best


func _item_under_mouse() -> String:
	var h := _hit()
	var w := room.world
	if h.has("wall"):
		for uid in w.items:
			var it: Dictionary = w.items[uid]
			if it.wall == h.wall and _wall_cell_match(it, h.wall_cell):
				return uid
		return ""
	if h.has("floor"):
		var fu := w.floor_item_at(h.floor)
		if fu != "":
			var kids := w.children_of(fu)
			if not kids.is_empty():
				# 點在上半部就拿上面的小東西
				var top_h: float = WorldModel.def_of(w.items[fu].type).get("surface", 1.0)
				if h.point.y >= 0 or true:
					var r := _mouse_ray()
					var t: float = (top_h - r.from.y) / r.dir.y
					var p: Vector3 = r.from + r.dir * t
					if Vector2i(floor(p.x), floor(p.z)) == h.floor or Vector2i(floor(p.x), floor(p.z)) in w.footprint(w.items[fu]):
						return kids[0]
			return fu
		# 地板沒東西：檢查視線在家具高度是否碰到（點到家具側面）
		for hh in [0.4, 0.8]:
			var r2 := _mouse_ray()
			var t3: float = (hh - r2.from.y) / r2.dir.y
			var p3: Vector3 = r2.from + r2.dir * t3
			var c3 := Vector2i(floor(p3.x), floor(p3.z))
			var u3 := w.floor_item_at(c3)
			if u3 != "":
				return u3
	return ""


func _wall_cell_match(it: Dictionary, c: Vector2i) -> bool:
	if it.wall in ["N", "S"]:
		return it.cell.x == c.x
	return it.cell.y == c.y


## Esc 關閉蓋在畫面上的面板（交件報告、任務板）；在 _input 先處理，程式碼區有焦點時也有效
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if report.visible:
		report.visible = false
		get_viewport().set_input_as_handled()
	elif book.visible:
		book.close()
		get_viewport().set_input_as_handled()
	elif hud.board.visible:
		hud.board.visible = false
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode != "home" or hud.board.visible:
		return
	if event is InputEventMouseMotion and not held.is_empty():
		_update_held()
	elif event is InputEventMouseMotion:
		var uid := _item_under_mouse()
		if uid != "":
			var d := WorldModel.def_of(home_world.items[uid].type)
			hud.show_status(d.name + ("（固定）" if d.get("fixed", false) else "　點一下拿起來"), get_viewport().get_mouse_position())
		elif _wolf_under_mouse():
			hud.show_status("派派狼：有任務要給你！", get_viewport().get_mouse_position())
		else:
			hud.show_status("", Vector2.ZERO)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if held.is_empty():
			if intro_running:
				intro_advance = true
				return
			if _wolf_under_mouse():
				_open_board()
				return
			var uid2 := _item_under_mouse()
			if uid2 != "":
				_pick_existing(uid2)
		else:
			_drop_held()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				if not held.is_empty():
					held.rot = (held.rot + 1) % 4
					_update_held()
			KEY_ESCAPE:
				_cancel_held()
			KEY_DELETE, KEY_X, KEY_BACKSPACE:
				_store_held()


func _wolf_under_mouse() -> bool:
	var wolf: GopherActor = room.npcs.get("wolf")
	if wolf == null or not is_instance_valid(wolf):
		return false
	var sp := rig.cam.unproject_position(wolf.global_position + Vector3(0, 0.6, 0))
	return sp.distance_to(get_viewport().get_mouse_position()) < 55


func _new_uid() -> String:
	uid_counter += 1
	return "p%d" % uid_counter


func _pick_existing(uid: String) -> void:
	var it: Dictionary = home_world.items[uid]
	var d := WorldModel.def_of(it.type)
	if d.get("fixed", false):
		room.gopher.say("門和窗戶不能搬喔！", "think")
		return
	held = {"uid": uid, "type": it.type, "rot": it.rot, "orig": it.duplicate(), "target": null, "reason": ""}
	# 從世界中暫時拿掉（上面的小東西一起藏起來）
	home_world.items.erase(uid)
	room.furniture_nodes[uid].visible = false
	for k in _children_in(uid, held.orig):
		room.furniture_nodes[k].visible = false
	_make_held_node()
	_update_held()


func _children_in(uid: String, _item: Dictionary) -> Array:
	var out: Array = []
	for k in home_world.items:
		if home_world.items[k].on == uid:
			out.append(k)
	return out


func _take_from_inventory(type: String) -> void:
	_cancel_held()
	if int(save.inventory.get(type, 0)) <= 0:
		return
	save.inventory[type] = int(save.inventory[type]) - 1
	hud.set_inventory(save.inventory)
	held = {"uid": _new_uid(), "type": type, "rot": 0, "orig": null, "target": null, "reason": ""}
	_make_held_node()
	_update_held()


func _make_held_node() -> void:
	var node := Models.furniture(held.type)
	room.add_child(node)
	held.node = node


func _place_held_at(cell: Vector2i) -> void:
	if held.is_empty():
		return
	_update_held({"floor": cell, "point": Vector3(cell.x + 0.5, 0, cell.y + 0.5)})
	_drop_held()


func _update_held(forced: Dictionary = {}) -> void:
	var h := _hit() if forced.is_empty() else forced
	var d := WorldModel.def_of(held.type)
	var item := {"uid": held.uid, "type": held.type, "cell": Vector2i.ZERO, "rot": held.rot, "on": "", "wall": ""}
	var reason := "移到房間裡"
	if d.kind == "wall":
		if h.has("wall"):
			item.wall = h.wall
			item.cell = h.wall_cell
			reason = home_world.can_place(held.type, item.cell, 0, held.uid, "", h.wall)
		else:
			reason = "掛牆家具：請指著牆壁"
	elif h.has("floor"):
		item.cell = h.floor
		var under := home_world.floor_item_at(h.floor)
		if d.kind == "top" and under != "" and WorldModel.def_of(home_world.items[under].type).has("surface"):
			item.on = under
			item.cell = home_world.items[under].cell
		reason = home_world.can_place(held.type, item.cell, held.rot, held.uid, item.on, "")
		if reason == "" and item.on == "" and item.cell == home_world.gopher_cell:
			reason = ""  # 放上去後派派鼠會自己讓開
	held.target = item
	held.reason = reason
	var node: Node3D = held.node
	var pos := RoomView.item_pos(item, home_world)
	if item.wall == "" and item.on == "" and h.has("floor"):
		pos.y = 0.15
	node.position = pos
	node.rotation.y = RoomView.item_yaw(item)
	RoomView.tint(node, Color(0.45, 0.85, 0.45, 0.6) if reason == "" else Color(0.95, 0.4, 0.35, 0.6))
	var name: String = d.name
	hud.show_status(("%s　左鍵放下・R 旋轉" % name) if reason == "" else ("%s：%s" % [name, reason]), get_viewport().get_mouse_position(), reason != "")


func _drop_held() -> void:
	if held.is_empty() or held.target == null:
		return
	if held.reason != "":
		room.gopher.say(held.reason, "think")
		return
	var item: Dictionary = held.target
	_free_held_node(held.node)
	var uid: String = held.uid
	home_world.items[uid] = item
	if room.furniture_nodes.has(uid):
		room.furniture_nodes[uid].visible = true
		room.refresh_item(uid)
		for k in home_world.children_of(uid):
			room.furniture_nodes[k].visible = true
			home_world.items[k].cell = item.cell
			room.refresh_item(k)
	else:
		room.add_item(uid)
	# 派派鼠被壓到就讓開
	if home_world.floor_item_at(home_world.gopher_cell) != "":
		var free := _nearest_walkable(home_world.gopher_cell)
		home_world.gopher_cell = free
		room.gopher.position = GopherActor.cell_pos(free)
		room.gopher.hop(0.3)
	held = {}
	hud.show_status("", Vector2.ZERO)
	_write_save()


func _cancel_held() -> void:
	if held.is_empty():
		return
	_free_held_node(held.node)
	if held.orig != null:
		var uid: String = held.uid
		home_world.items[uid] = held.orig
		room.furniture_nodes[uid].visible = true
		for k in home_world.children_of(uid):
			room.furniture_nodes[k].visible = true
		room.refresh_item(uid)
	else:
		save.inventory[held.type] = int(save.inventory.get(held.type, 0)) + 1
		hud.set_inventory(save.inventory)
	held = {}
	hud.show_status("", Vector2.ZERO)


func _store_held() -> void:
	if held.is_empty():
		return
	_free_held_node(held.node)
	var uid: String = held.uid
	save.inventory[held.type] = int(save.inventory.get(held.type, 0)) + 1
	if held.orig != null:
		room.remove_item(uid)
		for k in home_world.children_of(uid):
			save.inventory[home_world.items[k].type] = int(save.inventory.get(home_world.items[k].type, 0)) + 1
			home_world.items.erase(k)
			room.remove_item(k)
	held = {}
	hud.set_inventory(save.inventory)
	hud.show_status("", Vector2.ZERO)
	_write_save()


# ---------------- 任務（寫程式模式）----------------
func _task_by_id(id: String) -> Dictionary:
	for t in tasks:
		if t.id == id:
			return t
	return {}


func _enter_task(id: String) -> void:
	task = _task_by_id(id)
	if task.is_empty():
		return
	_cancel_held()
	_write_save()
	mode = "task"
	bubbles.avoid_side_panels = true
	if intro_running:
		intro_skip = true  # 開場還沒演完就進任務：開場直接結束
	if is_instance_valid(intro_skip_btn):
		intro_skip_btn.queue_free()
	hud.board.visible = false
	hud.visible = false
	hud.show_status("", Vector2.ZERO)
	panel.visible = true
	report.visible = false
	panel.load_task(task, save.codes.get(task.id, ""))
	_reset_task_room()
	var tw: WorldModel = room.world
	rig.frame_room(tw.width, tw.depth, 2.15)
	rig.screen_offset = 0.07
	await get_tree().create_timer(0.4).timeout
	if mode == "task":
		_giver().say(task.npc_line, "say")


func _reset_task_room() -> void:
	playback.cancel()
	run_id += 1
	panel.submit_answer("")  # 還在等 input() 回答的執行就此作廢
	bubbles.clear_all()
	var w := WorldModel.from_layout(task.room)
	room.build(w)
	room.set_grid_visible(true)  # 任務用格子座標
	room.build_outdoor()
	room.gopher.bubble_requested.connect(_on_bubble)
	_spawn_task_npcs(w)
	panel.clear_marks()
	panel.show_banner("")
	rig.follow_target = null


func _exit_task() -> void:
	playback.cancel()
	_save_code()
	_write_save()
	_enter_home()


func _on_code_changed() -> void:
	_save_code()


func _save_code() -> void:
	if task.is_empty():
		return
	save.codes[task.id] = panel.code.text


func _wait_playback_stop() -> void:
	playback.cancel()
	while playback.running:
		await get_tree().process_frame


func _play(timeline: Array, demo: bool, highlight: bool) -> bool:
	playback.view = room
	playback.panel = panel
	playback.demo = demo
	playback.highlight = highlight
	playback.speed = panel.speed()
	panel.set_running(true)
	rig.follow_target = room.gopher
	var ok := await playback.play(timeline)
	panel.set_running(false)
	panel.code.clear_executing_lines()
	return ok


func _demo() -> void:
	await _wait_playback_stop()
	_reset_task_room()
	panel.show_banner("示範中：這是派派狼期待的樣子（不是你的程式）")
	panel.log_system("— 示範開始 —", "#9fd3e6")
	var res := TaskRunner.run_case(task, task.reference, task.tests[0])
	var ok := await _play(res.timeline, true, false)
	if ok:
		panel.log_system("— 示範結束：換你寫程式囉！—", "#9fd3e6")
		room.gopher.happy()
	panel.show_banner("")


func _run(step_mode: bool) -> void:
	await _wait_playback_stop()
	_reset_task_room()
	_save_code()
	panel.log_system("— 執行你的程式 —")
	var my_run := run_id
	# input()：程式停在 input() 時先演到那裡，請玩家回答，再帶著回答重跑（前面的部分已經演過了）
	var answers: Array = []
	var played := 0
	var res: Dictionary = {}
	playback.step_mode = step_mode
	while true:
		res = TaskRunner.run_case(task, panel.code.text, {"name": "練習", "vars": {}, "inputs": answers, "interactive": true})
		if res.interp.ast == null:
			panel.log_error(res.interp.error)
			room.gopher.say("看不懂這段程式…", "fail")
			room.gopher.confused()
			return
		var ok := await _play(res.timeline.slice(played), false, true)
		played = res.timeline.size()
		if not ok or mode != "task":
			return
		if res.need_input.is_empty() or answers.size() >= 20:
			break
		var ni: Dictionary = res.need_input
		var asker := room.actor(ni.get("who", "wolf"))
		asker.say(ni.prompt, "wait")  # 問題氣泡留著，直到玩家回答
		panel.highlight_line(ni.line)
		var ans: String = await panel.ask_input(ni.prompt, RoomView.NAMES.get(ni.get("who", "wolf"), ""))
		if mode != "task" or my_run != run_id:  # 等回答的時候離開任務或重新執行了
			return
		answers.append(ans)
		playback.step_mode = step_mode
	if res.interp.ok and res.action_fail.is_empty():
		panel.log_system("程式執行完畢。符合任務單的話，就按「★ 交件」吧！", "#b8e0a5")
		if task.get("print_role", "") == "dialogue":
			room.gopher.happy()
	panel.set_vars(res.interp.env)


func _step() -> void:
	if playback.running:
		playback.step()
	else:
		panel.log_system("單步模式：每按一次「單步」執行一行。")
		_run(true)


func _submit() -> void:
	await _wait_playback_stop()
	_save_code()
	_write_save()
	var code: String = panel.code.text
	var rep := TaskChecker.evaluate(task, code)
	last_report = rep
	panel.log_system("— 交件！派派狼檢查中… —")
	if rep.cases.is_empty():
		# 語法錯誤：程式根本沒辦法跑
		_reset_task_room()
		for f in rep.findings:
			panel.log_error({"kind": f.code.split(".")[1] if f.code.contains(".") else "錯誤", "message": f.message, "hint": f.hint, "line": f.line})
		room.gopher.say("看不懂這段程式…", "fail")
		await room.gopher.confused()
		_show_report(rep)
		return
	# 先演題目看得到的測資，再快速演隱藏測資（失敗的放最後，留下虛線影子）
	var order: Array = []
	for c in rep.cases:
		if not c.hidden:
			order.append(c)
	var hidden_ok: Array = []
	var hidden_bad: Array = []
	for c in rep.cases:
		if c.hidden:
			if c.ok:
				hidden_ok.append(c)
			else:
				hidden_bad.append(c)
	order.append_array(hidden_ok)
	order.append_array(hidden_bad)
	var last_case: Dictionary = {}
	for c in order:
		_reset_task_room()
		var fast: bool = c.hidden
		panel.show_banner(("隱藏測資：" if fast else "題目情境：") + c.name.replace("隱藏測資：", ""))
		var old_speed := panel.speed()
		playback.speed = 4.0 if fast else old_speed
		playback.view = room
		playback.panel = panel
		playback.demo = false
		playback.highlight = not fast
		panel.set_running(true)
		rig.follow_target = room.gopher
		var completed := await playback.play(c.stu.timeline)
		panel.set_running(false)
		if not completed or mode != "task":
			panel.show_banner("")
			return
		last_case = c
		if not c.ok and c.hidden:
			break
	panel.show_banner("")
	# 虛線影子：目標位置
	for f in rep.findings:
		if f.has("ghost") and f.case == last_case.get("name", ""):
			room.show_ghost(f.ghost.uid, Vector2i(f.ghost.cell[0], f.ghost.cell[1]))
	if rep.passed:
		room.gopher.happy()
		_giver().say("不錯嘛，新來的！", "say")
	else:
		_giver().say("嗯…好像哪裡不太對喔？", "think")
	await get_tree().create_timer(0.8).timeout
	_show_report(rep)


func _show_report(rep: Dictionary) -> void:
	var first_clear: bool = rep.passed and int(save.stars.get(task.id, 0)) == 0
	report.show_report(task, rep, first_clear)
	if rep.passed:
		save.stars[task.id] = max(int(save.stars.get(task.id, 0)), rep.stars)
		if first_clear:
			var rt: String = task.reward.furniture
			save.inventory[rt] = int(save.inventory.get(rt, 0)) + 1
		_write_save()


func _accept_reward() -> void:
	report.visible = false
	_exit_task()
	await get_tree().create_timer(0.5).timeout
	room.gopher.say("收藏冊裡有新家具了！", "say")
	room.gopher.happy()


# ---------------- 開發用：自動截圖 ----------------
func _auto_shot(path: String) -> void:
	var steps: Array = path.split(";")
	await get_tree().create_timer(1.5).timeout
	for s in steps:
		if s.begins_with("task:"):
			_enter_task(s.substr(5))
			await get_tree().create_timer(1.5).timeout
		elif s.begins_with("code:"):
			panel.code.text = s.substr(5).replace("\\n", "\n")
		elif s == "run":
			await _run(false)
		elif s == "demo_bg":
			_demo()
		elif s == "run_bg":
			_run(false)
		elif s == "demo":
			await _demo()
		elif s == "submit":
			await _submit()
		elif s == "esc":
			var ev := InputEventKey.new()
			ev.keycode = KEY_ESCAPE
			ev.pressed = true
			Input.parse_input_event(ev)
			await get_tree().create_timer(0.3).timeout
		elif s == "book":
			_open_book()
			await get_tree().create_timer(0.5).timeout
		elif s.begins_with("book_area:"):
			book._show_area(s.substr(10))
			await get_tree().create_timer(0.3).timeout
		elif s.begins_with("book_concept:"):
			book._show_concept(s.substr(13))
			await get_tree().create_timer(0.3).timeout
		elif s == "board":
			_open_board()
			await get_tree().create_timer(0.5).timeout
		elif s == "accept":
			await _accept_reward()
			await get_tree().create_timer(1.0).timeout
		elif s.begins_with("take:"):
			_take_from_inventory(s.substr(5))
		elif s.begins_with("place:"):
			var xz: Array = s.substr(6).split(",")
			_place_held_at(Vector2i(int(xz[0]), int(xz[1])))
		elif s == "fresh" or s == "fresh_intro":
			# fresh：新存檔但跳過開場；fresh_intro：新存檔並演開場
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
			save = {}
			_load_save()
			save.intro_done = s == "fresh"
			_enter_home()
		elif s.begins_with("answer:"):
			panel.submit_answer(s.substr(7))
		elif s.begins_with("look:"):
			# look:wolf|rabbit|gopher,距離,俯角
			var a: Array = s.substr(5).split(",")
			var who: Node3D = room.actor(a[0])
			rig.follow_target = who
			rig.target_distance = float(a[1])
			rig.target_pitch = deg_to_rad(float(a[2]))
		elif s.begins_with("wait:"):
			await get_tree().create_timer(float(s.substr(5))).timeout
		elif s.begins_with("png:"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(s.substr(4))
	get_tree().quit()


## 拿在手上的預覽家具：先隱藏、下一幀再釋放（GL 相容渲染器同一幀釋放描邊材質會報警告）
func _free_held_node(n: Node3D) -> void:
	n.visible = false
	for c in n.find_children("*", "MeshInstance3D", true, false):
		c.material_override = null
	await get_tree().process_frame
	await get_tree().process_frame
	n.queue_free()
