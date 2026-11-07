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
var letters: LetterPanel
var town: TownView
var return_to_town := false  # 任務是在鎮上接的：離開任務回鎮上
var offer: PanelContainer  # 鎮上居民的任務邀請
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
	town = TownView.new()
	town.visible = false
	add_child(town)
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
	letters = LetterPanel.new()
	ui_layer.add_child(hud)
	ui_layer.add_child(panel)
	ui_layer.add_child(bubbles)
	ui_layer.add_child(report)
	ui_layer.add_child(book)
	ui_layer.add_child(letters)
	offer = PanelContainer.new()
	offer.theme = UIKit.theme()
	offer.visible = false
	ui_layer.add_child(offer)
	report.visible = false
	panel.visible = false

	hud.take_from_inventory.connect(_take_from_inventory)
	hud.open_board.connect(_open_board)
	hud.grid_toggled.connect(func(): room.set_grid_visible(not room.grid_visible))
	hud.view_reset.connect(func(): rig.reset_view())
	hud.task_chosen.connect(_enter_task)
	hud.reduce_motion_toggled.connect(_set_reduce_motion)
	hud.open_book.connect(_open_book)
	hud.town_toggled.connect(func():
		if mode == "town":
			_enter_home()
		else:
			_enter_town())
	letters.read_letter.connect(func(id):
		if not save.has("letters_read"):
			save.letters_read = []
		if not save.letters_read.has(id):
			save.letters_read.append(id)
		_update_mailbox_flag()
		_write_save())
	letters.move_pressed.connect(func():
		for k in home_world.items:
			if home_world.items[k].type == "mailbox":
				_pick_existing(k)
				return)
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
	sm.sky_top_color = Color("b9cbc4")
	sm.sky_horizon_color = Color("efe2c8")
	sm.ground_horizon_color = Color("efe2c8")
	sm.ground_bottom_color = Color("aab68e")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("f0e0cc")
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe6c4")
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 40
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)
	# 繪本故事書濾鏡：蓋在 3D 畫面上、介面下面（介面的 CanvasLayer 是第 1 層）
	var paper_layer := CanvasLayer.new()
	paper_layer.layer = 0
	add_child(paper_layer)
	var paper := ColorRect.new()
	paper.name = "StorybookPaper"
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://shaders/storybook_paper.gdshader")
	paper.material = pm
	paper_layer.add_child(paper)


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
	# 拍拍鳥的見面禮：舊存檔也補發一次森林信箱
	if not save.has("gift_mailbox"):
		save.gift_mailbox = true
		var placed := false
		for it in save.home.get("furniture", []):
			if it.get("type", "") == "mailbox":
				placed = true
		if not placed and int(save.inventory.get("mailbox", 0)) == 0:
			save.inventory["mailbox"] = 1
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
	offer.visible = false
	room.visible = true
	room.scene = "house"
	town.visible = false
	hud.set_town_mode(false)
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
	_update_mailbox_flag()
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
## 派派鼠帶著行李從外地來到派森小鎮，對照爺爺給的照片找到樹屋，進門打掃，派派狼來敲門。
## 所有角色都從南牆的門洞進出，屋裡沿著格子走（find_path），不穿牆。
var intro_running := false
var intro_advance := false  # 點一下畫面：跳到下一句
var intro_skip := false
var intro_skip_btn: Button
var intro_gen := 0  # 開場重新開始時，舊的開場流程看到編號不同就停
var intro_props: Array = []  # 灰塵、蜘蛛網、防塵布、行李……開場結束就收掉
var intro_dust: Dictionary = {}  # 格子 → 灰塵堆
var intro_card: Control


func _play_intro() -> void:
	intro_gen += 1
	var gen := intro_gen
	intro_running = true
	intro_skip = false
	intro_advance = false
	roam_busy = true
	hud.visible = false  # 開場時不顯示工具列，專心看故事
	if is_instance_valid(intro_skip_btn):
		intro_skip_btn.queue_free()
	if is_instance_valid(intro_card):
		intro_card.queue_free()
	intro_skip_btn = UIKit.button("略過 ▶▶", _skip_intro, "直接跳過開場")
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
	_build_abandoned_props()
	await _intro_story(gen)
	if gen != intro_gen:
		return  # 開場被重新開始了，交給新的流程
	if mode == "home" and is_instance_valid(room.gopher):
		_intro_final_state()
	save.intro_done = true
	_write_save()
	_end_intro()
	if mode == "home":
		rig.reset_view()


func _skip_intro() -> void:
	intro_skip = true
	Engine.time_scale = 12.0  # 正在走的路、正在轉的門一下子演完，再擺成結束的樣子


## 停下來嗎？（略過、離開家、或開場重新開始）
func _intro_stop(gen: int) -> bool:
	return intro_skip or gen != intro_gen or mode != "home" or not is_instance_valid(room.gopher)


## 等一下；點畫面可以提早往下
func _intro_wait(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000)
	intro_advance = false
	while Time.get_ticks_msec() < until and not intro_advance and not intro_skip:
		await get_tree().process_frame


## 說一句話，停留時間和氣泡一樣依字數
func _intro_say(a: GopherActor, text: String, kind: String = "say") -> void:
	if not is_instance_valid(a):
		return
	a.say(text, kind)
	await _intro_wait(maxf(2.4, 1.0 + text.length() * 0.12) + 0.3)


## 直直走到一個點（含高度：屋外草地比地板低一點，走過門洞時慢慢踏上來）
func _intro_walk(a: GopherActor, to: Vector3, facing: String = "") -> void:
	if not is_instance_valid(a):
		return
	a.moving = true
	a.face_vector(Vector3(to.x - a.position.x, 0, to.z - a.position.z))
	var tw := a.create_tween()
	tw.tween_property(a, "position", to, maxf(0.05, a.position.distance_to(to) * 0.48 / a.speed_scale))
	await tw.finished
	if is_instance_valid(a):
		a.moving = false
		if facing != "":
			a.face(facing)


## 沿著屋裡的格子走（會繞過家具）
func _intro_path(a: GopherActor, from: Vector2i, to: Vector2i, facing: String = "") -> void:
	var path := home_world.find_path(from, to)
	if path.size() > 1 and is_instance_valid(a):
		await a.walk_path(path)
	if is_instance_valid(a) and facing != "":
		a.face(facing)


func _door_inside() -> Vector2i:
	return Vector2i(int(_door_x(home_world)), home_world.depth - 1)


func _door_outside(dz: float = 0.75) -> Vector3:
	return Vector3(_door_x(home_world), RoomView.GRASS_Y, home_world.depth + dz)


func _intro_story(gen: int) -> void:
	var w := home_world
	var g := room.gopher
	var wolf: GopherActor = room.npcs.get("wolf")
	var rabbit: GopherActor = room.npcs.get("rabbit")
	if wolf == null or rabbit == null:
		return
	wolf.visible = false
	rabbit.visible = false
	var dx := _door_x(w)
	var inside := _door_inside()
	# ---- 一、帶著行李走到門口（鏡頭在屋外，看得到整面南牆和門）----
	room.cutaway = false
	var suitcase := _make_suitcase()
	g.carry_anchor.add_child(suitcase)
	suitcase.position = Vector3.ZERO
	suitcase.scale = Vector3.ONE * 0.6
	g.carried = suitcase
	g.position = Vector3(dx, RoomView.GRASS_Y, w.depth + 6.5)
	g.face("N")
	g.model.rotation.y = g.target_yaw
	rig.follow_target = null
	rig.focus = Vector3(dx, 0.5, w.depth + 3.5)
	rig.target_focus = rig.focus
	rig.yaw = deg_to_rad(12.0)
	rig.target_yaw = rig.yaw
	rig.pitch = deg_to_rad(-14.0)
	rig.target_pitch = rig.pitch
	rig.distance = 8.5
	rig.target_distance = 8.5
	g.say("（終於到了……派森小鎮。）", "think")
	await _intro_walk(g, _door_outside(2.4), "N")
	if _intro_stop(gen): return
	rig.target_focus = Vector3(dx, 0.7, w.depth + 0.9)
	rig.target_distance = 5.5
	await _intro_walk(g, _door_outside(0.75), "N")
	if _intro_stop(gen): return
	# ---- 二、拿出爺爺給的照片對照 ----
	_show_photo_card(true)
	await _intro_wait(1.2)
	if _intro_stop(gen): return
	await _intro_say(g, "（爺爺給的照片……）", "think")
	if _intro_stop(gen): return
	g.confused()
	await _intro_say(g, "（就是這裡了吧？）", "think")
	_show_photo_card(false)
	if _intro_stop(gen): return
	# ---- 三、開門進屋 ----
	await room.swing_door(true)
	if _intro_stop(gen): return
	await _intro_walk(g, GopherActor.cell_pos(inside), "N")
	if _intro_stop(gen): return
	room.cutaway = true
	rig.target_focus = Vector3(w.width / 2.0, 0, w.depth / 2.0 + 0.6)
	rig.target_distance = 9.0
	rig.target_yaw = deg_to_rad(-30.0)
	rig.target_pitch = deg_to_rad(-42.0)
	room.swing_door(false)
	await _intro_wait(0.8)
	if _intro_stop(gen): return
	g.set_face("confused", 2.0)
	await _intro_say(g, "（咳咳……好多灰塵。）", "think")
	if _intro_stop(gen): return
	await _intro_say(g, "（看起來很久很久沒有人住了。）", "think")
	if _intro_stop(gen): return
	await _intro_say(g, "（打掃一下吧！）", "think")
	if _intro_stop(gen): return
	# ---- 四、放下行李，拿掃把打掃 ----
	var side := inside + Vector2i(-1, 0)
	var dropped: Node3D = await g.drop(room, Vector3(side.x + 0.6, 0, side.y + 0.55))
	if dropped != null:
		dropped.rotation.y = 0.3
	var broom := _make_broom()
	room.add_child(broom)
	intro_props.append(broom)
	broom.position = Vector3(side.x + 0.55, 0.3, side.y + 0.4)
	await g.pick(broom)
	if _intro_stop(gen): return
	# 掃把拿在身體側邊、大一點，從後面也看得到
	var bt := broom.create_tween().set_parallel()
	bt.tween_property(broom, "scale", Vector3.ONE * 0.95, 0.2)
	bt.tween_property(broom, "position", Vector3(0.32, -0.2, 0.05), 0.2)
	var cur := inside
	for c in [Vector2i(5, 6), Vector2i(3, 3)]:
		await _intro_path(g, cur, c)
		cur = c
		if _intro_stop(gen): return
		await _sweep(g, c)
		if _intro_stop(gen): return
	w.gopher_cell = cur
	# ---- 五、有人敲門！鏡頭轉到北邊，看得到南牆和門 ----
	wolf.position = _door_outside(0.7)
	rabbit.position = _door_outside(1.5) + Vector3(0.6, 0, 0)
	wolf.face("N")
	rabbit.face("N")
	wolf.model.rotation.y = wolf.target_yaw
	rabbit.model.rotation.y = rabbit.target_yaw
	wolf.visible = true
	rabbit.visible = true
	rig.target_focus = Vector3(dx, 0.3, w.depth - 2.0)
	rig.target_distance = 7.5
	rig.target_yaw = deg_to_rad(160.0)
	rig.target_pitch = deg_to_rad(-30.0)
	_knock_door()
	await _intro_say(wolf, "叩叩叩！有人在嗎？")
	if _intro_stop(gen): return
	g.hop(0.12)
	await _intro_say(g, "（有人來了？）", "think")
	if _intro_stop(gen): return
	var meet := Vector2i(inside.x + 1, inside.y - 1)
	await _intro_path(g, cur, meet, "S")
	w.gopher_cell = meet
	if _intro_stop(gen): return
	await room.swing_door(true)
	if _intro_stop(gen): return
	# 派派狼先進門，派派兔跟在後面
	await _intro_walk(wolf, GopherActor.cell_pos(inside))
	if _intro_stop(gen): return
	await _intro_path(wolf, inside, inside + Vector2i(0, -1), "E")
	if _intro_stop(gen): return
	await _intro_walk(rabbit, GopherActor.cell_pos(inside))
	if _intro_stop(gen): return
	await _intro_path(rabbit, inside, inside + Vector2i(1, 0), "N")
	if _intro_stop(gen): return
	g.face("W")
	rig.target_focus = Vector3(dx + 0.5, 0.4, w.depth - 1.5)
	rig.target_distance = 5.5
	# ---- 六、第一次見面 ----
	var lines := [
		[wolf, "嘿！新來的，以後跟著我混。"],
		[rabbit, "……哇，好多灰塵。你在打掃喔？"],
		[rabbit, "（推推眼鏡）我是派派兔，我們來幫忙吧～"],
		[g, "……？"],
		[wolf, "怎麼不說話？在派森小鎮，要用 Python 的 print() 才能說話喔！"],
		[rabbit, "點派派狼接任務，學會 print() 就能跟我們聊天了！"],
	]
	for l in lines:
		if l[0] == g:
			g.confused()
		await _intro_say(l[0], l[1])
		if _intro_stop(gen): return
	# 大家一起打掃：剩下的灰塵、蜘蛛網、防塵布都清掉
	wolf.happy()
	rabbit.happy()
	g.carried = null  # 掃把收起來（跟著灰塵一起消失）
	g.carry_anchor.rotation = Vector3.ZERO
	_clear_abandoned(0.9)
	await _intro_wait(1.4)
	if _intro_stop(gen): return
	g.happy()
	await _intro_say(wolf, "好啦，我們在外面等你！")
	if _intro_stop(gen): return
	# ---- 七、派派兔、派派狼從門口出去，沿著南牆外面走到西邊等 ----
	rig.reset_view()
	await _intro_path(rabbit, inside + Vector2i(1, 0), inside)
	if _intro_stop(gen): return
	_visitor_leave(rabbit, "rabbit")
	await _intro_wait(0.9)
	if _intro_stop(gen): return
	await _intro_path(wolf, inside + Vector2i(0, -1), inside)
	if _intro_stop(gen): return
	await _visitor_leave(wolf, "wolf")
	if _intro_stop(gen): return
	room.swing_door(false)
	g.face("S")
	await _intro_wait(0.8)


## 從門口出去 → 沿著南牆外 → 走到西牆外的老位置
func _visitor_leave(a: GopherActor, who: String) -> void:
	var spot := visitor_spot(who, home_world)
	spot.y = RoomView.GRASS_Y
	await _intro_walk(a, _door_outside(0.75))
	await _intro_walk(a, Vector3(spot.x, RoomView.GRASS_Y, home_world.depth + 0.75))
	await _intro_walk(a, spot, "E")


## 敲門：門板抖三下
func _knock_door() -> void:
	var h := room._door_hinge()
	if h == null:
		return
	var tw := h.create_tween()
	for i in range(3):
		tw.tween_property(h, "rotation:y", deg_to_rad(-2.5), 0.06)
		tw.tween_property(h, "rotation:y", 0.0, 0.08)
		tw.tween_interval(0.12)


## 掃地：掃把左右揮、揚起一陣灰，灰塵堆變小消失
func _sweep(g: GopherActor, c: Vector2i) -> void:
	g.face("S")
	var tw := g.create_tween()
	for i in range(3):
		tw.tween_property(g.carry_anchor, "rotation:z", 0.45, 0.16)
		tw.tween_property(g.carry_anchor, "rotation:z", -0.45, 0.16)
	tw.tween_property(g.carry_anchor, "rotation:z", 0.0, 0.12)
	_dust_puff(GopherActor.cell_pos(c))
	if intro_dust.has(c):
		var pile: Node3D = intro_dust[c]
		intro_dust.erase(c)
		var t2 := pile.create_tween()
		t2.tween_property(pile, "scale", Vector3(1.3, 0.01, 1.3), 0.9)
		t2.tween_callback(pile.queue_free)
	await tw.finished


func _dust_puff(at: Vector3) -> void:
	for i in range(6):
		var p := MeshInstance3D.new()
		p.mesh = Models.sphere(0.09)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.86, 0.8, 0.68, 0.7)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p.material_override = m
		room.add_child(p)
		var a := i * TAU / 6.0
		p.position = at + Vector3(cos(a) * 0.15, 0.1, sin(a) * 0.15)
		var tw := p.create_tween()
		tw.set_parallel()
		tw.tween_property(p, "position", at + Vector3(cos(a) * 0.5, 0.45 + randf() * 0.25, sin(a) * 0.5), 1.0)
		tw.tween_property(p, "scale", Vector3.ONE * 2.4, 1.0)
		tw.tween_property(m, "albedo_color:a", 0.0, 1.0)
		tw.chain().tween_callback(p.queue_free)


## 照片小卡：從畫面右邊浮上來
func _show_photo_card(on: bool) -> void:
	if on:
		if is_instance_valid(intro_card):
			intro_card.queue_free()
		var card := PhotoCard.new()
		card.anchor_left = 0.5
		card.anchor_right = 0.5
		card.anchor_top = 0.5
		card.anchor_bottom = 0.5
		card.offset_left = 150
		card.offset_top = -230
		card.offset_right = 150 + PhotoCard.SIZE.x
		card.offset_bottom = -230 + PhotoCard.SIZE.y
		ui_layer.add_child(card)
		intro_card = card
		card.modulate.a = 0.0
		card.rotation = -0.2
		card.scale = Vector2.ONE * 0.7
		var tw := card.create_tween().set_parallel()
		tw.tween_property(card, "modulate:a", 1.0, 0.35)
		tw.tween_property(card, "rotation", -0.06, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif is_instance_valid(intro_card):
		var card2 := intro_card
		intro_card = null
		var tw2 := card2.create_tween()
		tw2.tween_property(card2, "modulate:a", 0.0, 0.3)
		tw2.tween_callback(card2.queue_free)


# ---- 開場的道具 ----
static func _make_suitcase() -> Node3D:
	var root := Node3D.new()
	root.name = "Suitcase"
	var body := Color("b5643c")
	Models.part(root, Models.box(0.55, 0.4, 0.22), body, Vector3(0, 0.2, 0))
	Models.part(root, Models.box(0.57, 0.05, 0.24), Color("8a4a2c"), Vector3(0, 0.26, 0), Vector3.ONE, Vector3.ZERO, false)
	for x in [-0.17, 0.17]:
		Models.part(root, Models.box(0.04, 0.42, 0.235), Color("e8c98a"), Vector3(x, 0.2, 0), Vector3.ONE, Vector3.ZERO, false)
	Models.part(root, Models.box(0.2, 0.05, 0.05), Color("5e3d26"), Vector3(0, 0.44, 0))
	Models.part(root, Models.sphere(0.05), Color("f6e3b8"), Vector3(0.12, 0.12, 0.115), Vector3(1, 1, 0.3), Vector3.ZERO, false)
	return root


static func _make_broom() -> Node3D:
	var root := Node3D.new()
	root.name = "Broom"
	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(0, 0, 35)
	root.add_child(tilt)
	Models.part(tilt, Models.cyl(0.025, 0.025, 1.1), Color("b08457"), Vector3(0, 0.25, 0))
	Models.part(tilt, Models.cyl(0.07, 0.17, 0.32), Color("e3c27a"), Vector3(0, -0.42, 0))
	Models.part(tilt, Models.cyl(0.075, 0.075, 0.05), Color("b5643c"), Vector3(0, -0.27, 0), Vector3.ONE, Vector3.ZERO, false)
	return root


## 很久沒人住的樣子：地上的灰塵堆、落葉、北邊牆角的蜘蛛網、蓋著防塵布的家具
func _build_abandoned_props() -> void:
	_clear_abandoned(0.0)
	var dust_mat := Color("cbbb98")
	for c in [Vector2i(5, 6), Vector2i(3, 3), Vector2i(1, 4), Vector2i(6, 1), Vector2i(4, 1), Vector2i(1, 7), Vector2i(6, 5)]:
		if not home_world.walkable(c):
			continue
		var pile := Node3D.new()
		var center := GopherActor.cell_pos(c) + Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.12, 0.12))
		pile.position = center
		Models.part(pile, Models.sphere(0.24), dust_mat, Vector3(0, 0.01, 0), Vector3(1.2, 0.18, 1.0), Vector3.ZERO, false)
		Models.part(pile, Models.sphere(0.1), dust_mat.lightened(0.08), Vector3(0.2, 0.01, 0.12), Vector3(1, 0.3, 1), Vector3.ZERO, false)
		Models.part(pile, Models.sphere(0.07), dust_mat.darkened(0.06), Vector3(-0.18, 0.01, -0.1), Vector3(1, 0.3, 1), Vector3.ZERO, false)
		room.add_child(pile)
		intro_props.append(pile)
		intro_dust[c] = pile
	# 被風吹進來的落葉
	for i in range(9):
		var leaf := Node3D.new()
		leaf.position = Vector3(randf_range(0.4, home_world.width - 0.4), 0.012, randf_range(home_world.depth - 2.6, home_world.depth - 0.3))
		leaf.rotation.y = randf() * TAU
		Models.part(leaf, Models.sphere(0.07), [Color("c48a4a"), Color("a9743e"), Color("d2a05a")][i % 3], Vector3.ZERO, Vector3(1.6, 0.08, 0.8), Vector3.ZERO, false)
		room.add_child(leaf)
		intro_props.append(leaf)
	# 蜘蛛網：北牆兩個上角
	for corner in [0, 1]:
		var web := Node3D.new()
		var sx := 1.0 if corner == 0 else -1.0
		web.position = Vector3(0.0 if corner == 0 else float(home_world.width), RoomView.WALL_H - 0.06, 0.03)
		var col := Color("f8f3ea")
		for k in range(5):
			var a := deg_to_rad(-90.0 + k * 22.5)
			var dir := Vector3(cos(a) * sx, sin(a), 0)
			_web_line(web, Vector3.ZERO, dir * 0.6, col)
		for r in [0.2, 0.36, 0.52]:
			for k in range(4):
				var a1 := deg_to_rad(-90.0 + k * 22.5)
				var a2 := deg_to_rad(-90.0 + (k + 1) * 22.5)
				_web_line(web, Vector3(cos(a1) * sx, sin(a1), 0) * r, Vector3(cos(a2) * sx, sin(a2), 0) * (r - 0.03), col)
		room.add_child(web)
		intro_props.append(web)
	# 防塵布：蓋住落地家具（信箱是拍拍鳥剛送的，不蓋）
	for uid in home_world.items:
		var it: Dictionary = home_world.items[uid]
		if it.wall != "" or it.on != "" or it.type == "mailbox" or not room.furniture_nodes.has(uid):
			continue
		var box := _node_aabb(room.furniture_nodes[uid])
		for child in home_world.children_of(uid):
			if room.furniture_nodes.has(child):
				box = box.merge(_node_aabb(room.furniture_nodes[child]))
		if box.size == Vector3.ZERO:
			continue
		var sheet := Node3D.new()
		var sz := box.size + Vector3(0.08, 0.05, 0.08)
		var cloth := Color("eee6d6")
		Models.part(sheet, Models.box(sz.x, sz.y, sz.z), cloth, Vector3(0, sz.y / 2, 0))
		Models.part(sheet, Models.box(sz.x + 0.08, 0.14, sz.z + 0.08), cloth.darkened(0.04), Vector3(0, 0.07, 0), Vector3.ONE, Vector3.ZERO, false)
		Models.part(sheet, Models.sphere(minf(sz.x, sz.z) * 0.45), cloth, Vector3(0, sz.y, 0), Vector3(1, 0.18, 1), Vector3.ZERO, false)
		sheet.position = Vector3(box.get_center().x, 0, box.get_center().z)
		room.add_child(sheet)
		intro_props.append(sheet)


func _web_line(parent: Node3D, a: Vector3, b: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var ln := a.distance_to(b)
	m.mesh = Models.box(ln, 0.014, 0.01)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.position = (a + b) / 2
	m.rotation.z = atan2(b.y - a.y, b.x - a.x)
	parent.add_child(m)


func _node_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := room.global_transform.affine_inverse()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var b: AABB = inv * m.global_transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## 收掉開場道具；fade > 0 就慢慢變小消失
func _clear_abandoned(fade: float) -> void:
	for p in intro_props:
		if not is_instance_valid(p):
			continue
		if fade <= 0.0:
			p.queue_free()
		else:
			var tw: Tween = p.create_tween()
			tw.tween_interval(randf() * 0.4)
			tw.tween_property(p, "scale", Vector3(1.05, 0.01, 1.05), fade).set_trans(Tween.TRANS_SINE)
			tw.tween_callback(p.queue_free)
	intro_props.clear()
	intro_dust.clear()


## 略過或演完：擺成開場結束的樣子
func _intro_final_state() -> void:
	Engine.time_scale = 1.0
	if intro_skip:
		bubbles.clear_all()
	_clear_abandoned(0.0)
	_show_photo_card(false)
	var g := room.gopher
	if g.carried != null and is_instance_valid(g.carried):
		g.carried.queue_free()
	g.carried = null
	for c in room.find_children("Suitcase", "", false, false):
		c.queue_free()
	g.carry_anchor.rotation = Vector3.ZERO
	if not home_world.in_room(Vector2i(floor(g.position.x), floor(g.position.z))) or g.position.y < 0:
		var c := _nearest_walkable(_door_inside() + Vector2i(1, -1))
		g.position = GopherActor.cell_pos(c)
		home_world.gopher_cell = c
	g.moving = false
	for who in ["wolf", "rabbit"]:
		var a: GopherActor = room.npcs.get(who)
		if a == null or not is_instance_valid(a):
			continue
		var spot := visitor_spot(who, home_world)
		spot.y = RoomView.GRASS_Y
		a.position = spot
		a.moving = false
		a.visible = true
		a.face("E")
	var h := room._door_hinge()
	if h != null:
		h.rotation.y = 0.0
	room.cutaway = true


func _end_intro() -> void:
	Engine.time_scale = 1.0
	intro_running = false
	roam_busy = false
	if is_instance_valid(intro_skip_btn):
		intro_skip_btn.queue_free()
	if is_instance_valid(intro_card):
		intro_card.queue_free()
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


# ---------------- 鎮中心 ----------------
func _enter_town() -> void:
	_cancel_held()
	mode = "town"
	playback.cancel()
	bubbles.clear_all()
	letters.close()
	book.close()
	room.visible = false
	town.visible = true
	if not town.built:
		town.build()
		for who in town.npcs:
			town.npcs[who].bubble_requested.connect(_on_bubble)
	hud.set_town_mode(true)
	hud.show_status("", Vector2.ZERO)
	for who in town.npcs:
		var todo := false
		for t in _town_tasks(who):
			if int(save.stars.get(t.id, 0)) == 0:
				todo = true
		town.set_mark(who, todo)
	rig.follow_target = null
	rig.screen_offset = 0.0
	rig.frame_room(int(TownView.W), int(TownView.D), 0.95)
	await get_tree().create_timer(0.6).timeout
	if mode == "town":
		town.talk("crow")


func _town_input(event: InputEvent) -> void:
	var mp := get_viewport().get_mouse_position()
	if event is InputEventMouseMotion:
		var who := town.actor_at(mp, rig.cam)
		if who != "":
			var tip := "　有任務！" if not _town_tasks(who).is_empty() else "　點一下聊天"
			hud.show_status(TownView.NAMES[who] + tip, mp)
		elif town.board_at(mp, rig.cam):
			hud.show_status("任務公告　點一下打開任務書", mp)
		else:
			hud.show_status("", Vector2.ZERO)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var who2 := town.actor_at(mp, rig.cam)
		if who2 != "":
			var list := _town_tasks(who2)
			if list.is_empty():
				town.talk(who2)
			else:
				_show_offer(who2, list)
		elif town.board_at(mp, rig.cam):
			_open_book()
		else:
			offer.visible = false


## 這位居民可以給的任務（已解鎖的）
func _town_tasks(who: String) -> Array:
	var out: Array = []
	for t in tasks:
		if t.get("npc", "") == who and t.get("room", {}).get("scene", "") == "town" and HomeHUD.is_unlocked(t, tasks, save.stars):
			out.append(t)
	return out


## 居民邀請接任務：說出任務的開場白，下方出現小卡片
func _show_offer(who: String, list: Array) -> void:
	var a: GopherActor = town.npcs[who]
	var first: Dictionary = list[0]
	for t in list:
		if int(save.stars.get(t.id, 0)) == 0:
			first = t
			break
	a.hop(0.12)
	a.say(first.npc_line, "say")
	for c in offer.get_children():
		c.queue_free()
	offer.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PAPER, 16, UIKit.INK, 2))
	offer.anchor_left = 0.5
	offer.anchor_right = 0.5
	offer.anchor_top = 1.0
	offer.anchor_bottom = 1.0
	offer.offset_left = -230
	offer.offset_right = 230
	offer.offset_top = -60 - 46 * list.size()
	offer.offset_bottom = -20
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	offer.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tl := UIKit.label(TownView.NAMES[who] + "的任務", 20)
	tl.add_theme_font_override("font", UIKit.font_bold())
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var x := UIKit.focusable(UIKit.button("×", func(): offer.visible = false, "下次再說"))
	head.add_child(x)
	for t in list:
		var st := int(save.stars.get(t.id, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var info := UIKit.label("%s　%s" % [t.title, "★".repeat(int(t.difficulty))], 17)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		if st > 0:
			row.add_child(UIKit.label("完成！", 15, UIKit.TEXT_GREEN))
		var tid: String = t.id
		var b := UIKit.focusable(UIKit.button("再挑戰" if st > 0 else "接下任務", func():
			offer.visible = false
			_enter_task(tid)))
		if st == 0:
			UIKit.primary(b)
		row.add_child(b)
	offer.visible = true


func _hide_offer() -> void:
	offer.visible = false


func _open_letters() -> void:
	_cancel_held()
	hud.show_status("", Vector2.ZERO)
	if not save.has("letters_read"):
		save.letters_read = []
	letters.open(save.stars, save.letters_read)


## 信箱的紅旗：有沒讀的信就舉起來，讀完就放下
func _update_mailbox_flag() -> void:
	if room == null or home_world == null:
		return
	var up := LetterPanel.unread_count(letters.data, save.stars, save.get("letters_read", [])) > 0
	for k in home_world.items:
		if home_world.items[k].type == "mailbox" and room.furniture_nodes.has(k):
			var flag: Node3D = room.furniture_nodes[k].find_child("Flag", true, false)
			if flag != null:
				flag.rotation_degrees.x = 0.0 if up else 90.0


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
	elif letters.visible:
		letters.close()
		get_viewport().set_input_as_handled()
	elif hud.board.visible:
		hud.board.visible = false
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode == "town" and not book.visible:
		_town_input(event)
		return
	if mode != "home" or hud.board.visible or letters.visible:
		return
	if event is InputEventMouseMotion and not held.is_empty():
		_update_held()
	elif event is InputEventMouseMotion:
		var uid := _item_under_mouse()
		if uid != "":
			var d := WorldModel.def_of(home_world.items[uid].type)
			var tip := "（固定）" if d.get("fixed", false) else "　點一下拿起來"
			if d.get("builder", "") == "mailbox":
				var n := LetterPanel.unread_count(letters.data, save.stars, save.get("letters_read", []))
				tip = "　點一下讀信" + ("（%d 封新信）" % n if n > 0 else "")
			hud.show_status(d.name + tip, get_viewport().get_mouse_position())
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
			if uid2 != "" and home_world.items[uid2].type == "mailbox":
				_open_letters()
			elif uid2 != "":
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
	_update_mailbox_flag()
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
	return_to_town = mode == "town"
	offer.visible = false
	room.visible = true
	town.visible = false
	hud.set_town_mode(false)
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
	room.scene = task.room.get("scene", "house")
	room.town_spot = task.room.get("spot", "")
	room.build(w)
	room.set_grid_visible(room.scene != "town")  # 任務用格子座標；鎮上的對話任務不需要
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
	if return_to_town:
		return_to_town = false
		_enter_town()
	else:
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
	panel.show_banner("示範中：這是%s期待的樣子（不是你的程式）" % RoomView.NAMES.get(task.get("npc", "wolf"), "派派狼"))
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
	panel.log_system("— 交件！%s檢查中… —" % RoomView.NAMES.get(task.get("npc", "wolf"), "派派狼"))
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
		elif s == "pos":
			print("gopher ", room.gopher.position, " vis ", room.gopher.visible, " cam ", rig.cam.global_position, " gen ", intro_gen)
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
		elif s.begins_with("star:"):
			save.stars[s.substr(5)] = 3
		elif s == "town":
			await _enter_town()
			await get_tree().create_timer(1.5).timeout
		elif s.begins_with("talk:"):
			var who_t: String = s.substr(5)
			if _town_tasks(who_t).is_empty():
				town.talk(who_t)
			else:
				_show_offer(who_t, _town_tasks(who_t))
			await get_tree().create_timer(0.4).timeout
		elif s == "home":
			_enter_home()
			await get_tree().create_timer(0.5).timeout
		elif s == "letters":
			_open_letters()
			await get_tree().create_timer(0.5).timeout
		elif s.begins_with("letter:"):
			letters._select(s.substr(7))
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
			var who: Node3D = town.npcs.get(a[0]) if mode == "town" else room.actor(a[0])
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
