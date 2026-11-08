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
var lessons: LessonBook   # 認識派派森林的世界：慢慢館長說故事＋派派兔小測驗
var story_after_library := false   # 派派兔帶派派鼠去圖書館上課：走進去就打開課本
var class_cid := ""                 # 上課表選的課
var class_board: ClassBoard
var exam: ExamPanel      # 三花奶奶的考核／黑貓弟弟的檢討（圖書館閱讀教室）
var store: StoreBook      # 雜貨店的商品清單
var letters: LetterPanel
var town: TownView
var library: LibraryView
var sun_light: DirectionalLight3D
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


var music: Music


func _ready() -> void:
	_setup_environment()
	rig = CameraRig.new()
	add_child(rig)
	room = RoomView.new()
	add_child(room)
	town = TownView.new()
	town.visible = false
	add_child(town)
	library = LibraryView.new()
	library.visible = false
	add_child(library)
	playback = Playback.new()
	add_child(playback)
	music = Music.new()
	add_child(music)

	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	bubbles = BubbleLayer.new()
	bubbles.camera_getter = func(): return rig.cam
	hud = HomeHUD.new()
	panel = TaskPanel.new()
	report = ReportPanel.new()
	book = QuestBook.new()
	lessons = LessonBook.new()
	exam = ExamPanel.new()
	store = StoreBook.new()
	letters = LetterPanel.new()
	ui_layer.add_child(hud)
	ui_layer.add_child(panel)
	ui_layer.add_child(bubbles)
	ui_layer.add_child(report)
	ui_layer.add_child(book)
	ui_layer.add_child(lessons)
	ui_layer.add_child(exam)
	ui_layer.add_child(store)
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
	hud.music_toggled.connect(func(on: bool) -> void:
		save.music_on = on
		music.set_enabled(on)
		_write_save())
	hud.open_book.connect(_open_book)
	hud.open_lessons.connect(func(): _go_story())
	lessons.scene_cast = _lesson_cast
	lessons.scene_layout.connect(_on_lesson_scene)
	lessons.lesson_done.connect(func(cid):
		if not save.has("lessons_done"):
			save.lessons_done = []
		if not save.lessons_done.has(cid):
			save.lessons_done.append(cid)
			HomeHUD.lessons_done = save.lessons_done
			_write_save())
	HomeHUD.lessons_done = save.get("lessons_done", [])
	class_board = ClassBoard.new()
	ui_layer.add_child(class_board)
	class_board.chosen.connect(_start_class)
	lessons.teacher_changed.connect(_on_teacher)
	exam.changed.connect(_write_save)
	hud.help_closed.connect(_start_play)
	hud.town_toggled.connect(func():   # 小鎮場景先不用：這顆按鈕只在圖書館出現，回樹屋
		if mode != "home":
			_enter_home())
	hud.open_library.connect(func():
		if mode == "home" and not intro_running:
			_enter_library(false))
	hud.open_store.connect(_open_store)
	letters.read_letter.connect(func(id):
		if not save.has("letters_read"):
			save.letters_read = []
		if not save.letters_read.has(id):
			save.letters_read.append(id)
		_update_mailbox_flag()
		_write_save())
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
	exam.setup(tasks)
	_load_save()
	UIKit.reduce_motion = save.get("reduce_motion", false)
	music.enabled = save.get("music_on", true)
	hud.set_music_checked(music.enabled)
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
	sun_light = sun
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
		save = {"version": 1, "home": home, "inventory": home.get("inventory", {}), "stars": {}, "codes": {}, "home_rug": false}
	# 樹屋變大了（10x9）：舊存檔的房子撐大，南牆、東牆上的東西跟著牆移過去
	var hsz: Array = save.home.get("size", [8, 8])
	var nw := maxi(int(hsz[0]), 10)
	var nd := maxi(int(hsz[1]), 9)
	if nw != int(hsz[0]) or nd != int(hsz[1]):
		for it in save.home.get("furniture", []):
			var wl: String = it.get("wall", "")
			if wl == "S":
				it.cell = [int(it.cell[0]), nd - 1]
			elif wl == "E":
				it.cell = [nw - 1, int(it.cell[1])]
		save.home.size = [nw, nd]
	# 往天空樹頂的門（暫時封閉）：舊存檔補上北牆的門和堵住門的木箱
	var has_sky := false
	for it in save.home.get("furniture", []):
		if it.get("type", "") == "sky_door":
			has_sky = true
	if not has_sky:
		var used := false
		for it in save.home.get("furniture", []):
			var cl: Array = it.get("cell", [])
			if it.get("wall", "") == "" and it.get("on", "") == "" and cl.size() == 2 and int(cl[0]) == 5 and int(cl[1]) == 0:
				used = true
		save.home.furniture.append({"uid": "h_sky_door", "type": "sky_door", "cell": [5, 0], "wall": "N"})
		if not used:
			save.home.furniture.append({"uid": "h_sky_crates", "type": "sky_crates", "cell": [5, 0]})
	# 森林信箱固定在門口旁邊（屋外）：舊存檔裡擺在屋裡或收在背包的信箱都拿掉
	var furn: Array = save.home.get("furniture", [])
	for i in range(furn.size() - 1, -1, -1):
		if furn[i].get("type", "") == "mailbox":
			furn.remove_at(i)
	save.inventory.erase("mailbox")
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
	music.play("home")
	offer.visible = false
	room.visible = true
	room.scene = "house"
	town.visible = false
	library.visible = false
	sun_light.directional_shadow_max_distance = 40
	hud.set_town_mode(false)
	bubbles.avoid_side_panels = false
	playback.cancel()
	task = {}
	bubbles.clear_all()
	room.show_rug = bool(save.get("home_rug", true))   # 新玩家一開始沒有地毯；舊存檔照舊
	room.build(home_world)
	room.set_grid_visible(false)  # 家裡不顯示格子（⋯ 選單可以打開）
	if not save.has("yard") or int(save.get("yard_v", 0)) < 2:
		save.yard = room.default_yard()  # 前院變大了：重新擺一次
		save.yard_v = 2
	room.yard_items = save.yard
	room.build_outdoor(true)
	room.gopher.bubble_requested.connect(_on_bubble)
	_spawn_visitors(home_world)
	rig.frame_room(home_world.width, home_world.depth)
	# 家：鏡頭往門口挪一點，看得到門口外的派派狼、派派兔和信箱
	rig.home_focus += Vector3(0.4, 0, 3.2)
	rig.home_distance *= 1.18
	rig.reset_view()
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
		play_started = true
		if intro_running:  # 開場演到一半就換成已看過開場的存檔：開場停掉
			intro_gen += 1
			intro_running = false
			Engine.time_scale = 1.0
			if is_instance_valid(intro_skip_btn):
				intro_skip_btn.queue_free()
		_update_task_cue()
		_start_visitor_life()


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


## 派派狼和派派兔是來拜訪的：站在門口正對面的小石路上，面向門
static func visitor_spot(who: String, w: WorldModel) -> Vector3:
	var dx := RoomView.door_x(w)
	return Vector3(dx - 0.6, 0, w.depth + 2.3) if who == "wolf" else Vector3(dx + 0.6, 0, w.depth + 2.45)


## 面向門（稍微朝向門的中間）
static func visitor_look(who: String) -> Vector3:
	return Vector3(0.3, 0, -1.0) if who == "wolf" else Vector3(-0.3, 0, -1.0)


# ---------------- 開始玩 ----------------
var play_started := false  # false：開場剛結束、操作說明還開著，大家先站著不動


func _start_play() -> void:
	if play_started or mode != "home" or intro_running:
		return
	play_started = true
	roam_timer = 3.0
	_start_visitor_life()


# ---------------- 訪客的日常 ----------------
## 派派狼和派派兔平常站在門口的小石路上；過一陣子派派兔會去胡蘿蔔園澆水，
## 派派狼會去溪邊的木平台坐著釣魚，做一會兒再回到門口。
var visitor_gen := 0
var visitor_quick := false  # 截圖用：馬上去做嗜好


func _start_visitor_life() -> void:
	visitor_gen += 1
	for who in ["wolf", "rabbit"]:
		_visitor_loop(who, visitor_gen)


func _visitor_ok(who: String, gen: int) -> bool:
	return gen == visitor_gen and mode == "home" and not intro_running and room.npcs.has(who) and is_instance_valid(room.npcs[who])


func _visitor_wait(sec: float, who: String, gen: int) -> bool:
	var until := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if not _visitor_ok(who, gen):
			return false
	return true


## 嗜好地點：派派狼去溪邊釣魚平台、派派兔去胡蘿蔔園西邊
func _hobby_goal(who: String) -> Vector3:
	if who == "wolf":
		var fs := room.fishing_spot()
		return Vector3(fs.x + 0.3, fs.y, fs.z)
	var gc := room.garden_center()
	return Vector3(gc.x - 2.1, RoomView.GRASS_Y, gc.z - 0.3)


## 訪客沿著前院的路線走（繞過柵欄、擺設和派派鼠）；走不到回傳 false
func _visitor_go(a: GopherActor, who: String, gen: int, goal: Vector3) -> bool:
	for attempt in range(10):
		var route := room.outdoor_route(a.position, goal, a)
		if route.is_empty():
			if a.position.distance_to(goal) < 0.3:
				return true
			if not await _visitor_wait(0.8, who, gen):
				return false
			continue
		var blocked := false
		for p in route:
			var pp: Vector3 = p
			while a.position.distance_to(pp) > 0.05:
				var nxt := a.position.move_toward(pp, 0.5)
				if _blocked_ahead(a, nxt):
					blocked = true
					break
				await _intro_walk(a, nxt)
				if not _visitor_ok(who, gen):
					return false
			if blocked:
				break
		if not blocked:
			return true
		a.moving = false
		if not await _visitor_wait(0.6, who, gen):
			return false
	return false


## 第一個任務（嘿！新來的）做完了沒
func _first_task_done() -> bool:
	return int(save.stars.get("D01_hello", 0)) > 0


func _visitor_loop(who: String, gen: int) -> void:
	var first := true
	while true:
		# 第一個任務做完以前：站在門口等派派鼠，偶爾轉頭看看派派鼠
		while not _first_task_done() and not visitor_quick:
			if not await _visitor_wait(randf_range(3.0, 6.0), who, gen):
				return
			var wa: GopherActor = room.npcs[who]
			if randf() < 0.5 and room.gopher != null and room.gopher.position.distance_to(wa.position) < 9.0:
				wa.face_vector(room.gopher.position - wa.position)
			else:
				wa.face_vector(visitor_look(who))
		if not await _visitor_wait(1.0 if visitor_quick else (randf_range(14.0, 24.0) if first else randf_range(10.0, 18.0)), who, gen):
			return
		first = false
		var a: GopherActor = room.npcs[who]
		# 自由模式：有時候在前院走走、看看，有時候去做喜歡的事
		if randf() < 0.4 and not visitor_quick:
			var spot := room.nearest_free(Vector3(randf_range(room.yard_x0() + 0.8, room.yard_x1() - 0.8), 0, randf_range(home_world.depth + 1.5, room.yard_z1() - 1.0)), a)
			if await _visitor_go(a, who, gen, spot):
				if randf() < 0.5:
					a.say(["今天天氣真好～", "派派鼠的家越來越漂亮了！", "嗯……要做什麼呢？", "（東看看、西看看）"].pick_random(), "say")
				if not await _visitor_wait(randf_range(4.0, 8.0), who, gen):
					return
			if randf() < 0.5:
				continue  # 待在前院，等一下再找事做
			var back := visitor_spot(who, home_world)
			back.y = RoomView.GRASS_Y
			await _visitor_go(a, who, gen, back)
			if not _visitor_ok(who, gen):
				return
			a.face_vector(visitor_look(who))
			continue
		var goal := _hobby_goal(who)
		if not await _visitor_go(a, who, gen, goal):
			if not _visitor_ok(who, gen):
				return
			continue
		if who == "wolf":
			await _wolf_fishing(a, gen)
		else:
			await _rabbit_watering(a, gen)
		if not _visitor_ok(who, gen):
			return
		var home := visitor_spot(who, home_world)
		home.y = RoomView.GRASS_Y
		for tries in range(6):
			if await _visitor_go(a, who, gen, home):
				break
			if not _visitor_ok(who, gen):
				return
			await _visitor_wait(1.5, who, gen)
		a.face_vector(visitor_look(who))


## 派派狼：坐在木平台邊，拿釣竿，浮標在水上一上一下
func _wolf_fishing(a: GopherActor, gen: int) -> void:
	a.face("W")
	a.set_seated(true)
	var rod := Node3D.new()
	rod.name = "FishingRod"
	a.model.add_child(rod)
	rod.position = Vector3(0.12, 0.32, 0.22)
	var stick := Models.part(rod, Models.cyl(0.008, 0.018, 1.3), Color("8a6646"), Vector3(0, 0, 0))
	stick.rotation_degrees = Vector3(55, 0, 0)
	stick.position = Vector3(0, 0.37, 0.53)
	var fs := room.fishing_spot()
	var bob_pos := Vector3(room.stream_x(fs.z) - 0.1, RoomView.GRASS_Y + 0.04, fs.z + 0.15)
	var bob := Node3D.new()
	room.add_child(bob)
	bob.position = bob_pos
	Models.part(bob, Models.sphere(0.05), Color("e0553e"), Vector3(0, 0.03, 0))
	Models.part(bob, Models.sphere(0.04), Color("f6efe0"), Vector3(0, -0.01, 0), Vector3(1, 0.6, 1), Vector3.ZERO, false)
	await get_tree().process_frame
	var tip := (stick.global_transform * Vector3(0, 0.65, 0))
	var line := MeshInstance3D.new()
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.95, 0.95, 0.9, 0.8)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.mesh = Models.cyl(0.004, 0.004, tip.distance_to(bob_pos))
	line.material_override = lm
	room.add_child(line)
	var up := (tip - bob_pos).normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	line.transform = Transform3D(Basis(side, up, side.cross(up)), (tip + bob_pos) / 2)
	var bt := bob.create_tween().set_loops()
	bt.tween_property(bob, "position:y", bob_pos.y - 0.025, 0.9).set_trans(Tween.TRANS_SINE)
	bt.tween_property(bob, "position:y", bob_pos.y + 0.01, 0.9).set_trans(Tween.TRANS_SINE)
	if randf() < 0.5:
		a.say("（今天會釣到大魚嗎……）", "think")
	await _visitor_wait(randf_range(22.0, 34.0), "wolf", gen)
	if randf() < 0.4 and _visitor_ok("wolf", gen):
		a.hop(0.1)
		a.say("釣到了！……喔，是一隻小鞋子。", "say")
		await _visitor_wait(2.5, "wolf", gen)
	for n in [rod, bob, line]:
		if is_instance_valid(n):
			n.queue_free()
	if is_instance_valid(a):
		a.set_seated(false)


## 派派兔：拿著澆水壺，往胡蘿蔔澆水（壺嘴往下、水滴落到菜圃）
func _rabbit_watering(a: GopherActor, gen: int) -> void:
	a.face("E")
	var can := _make_watering_can()
	a.carry_anchor.add_child(can)
	can.position = Vector3.ZERO
	a.carried = can
	if randf() < 0.5:
		a.say("胡蘿蔔快快長大～", "say")
	var spots := [room.garden_center() + Vector3(-2.1, 0, -0.3), room.garden_center() + Vector3(-2.1, 0, 0.6)]
	for i in range(4):
		if not _visitor_ok("rabbit", gen):
			break
		if i == 2:
			var sp: Vector3 = spots[1]
			sp.y = RoomView.GRASS_Y
			await _intro_walk(a, sp, "E")
		var tw := can.create_tween()
		tw.tween_property(can, "rotation:x", 0.65, 0.4).set_trans(Tween.TRANS_SINE)
		await tw.finished
		for k in range(7):
			_water_drop(can)
			if not await _visitor_wait(0.18, "rabbit", gen):
				break
		var tw2 := can.create_tween()
		tw2.tween_property(can, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
		await tw2.finished
		if not await _visitor_wait(randf_range(2.0, 3.5), "rabbit", gen):
			break
	if is_instance_valid(a):
		a.carried = null
	if is_instance_valid(can):
		can.queue_free()


func _water_drop(can: Node3D) -> void:
	if not is_instance_valid(can):
		return
	var spout := can.get_node_or_null("Spout") as Node3D
	var from := spout.global_position if spout else can.global_position
	var drop := MeshInstance3D.new()
	drop.mesh = Models.sphere(0.025)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.82, 0.95, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material_override = m
	room.add_child(drop)
	drop.global_position = from + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
	var to := drop.position + Vector3(0.12, 0, 0)
	to.y = RoomView.GRASS_Y + 0.12
	var tw := drop.create_tween()
	tw.tween_property(drop, "position", to, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(drop.queue_free)


## 澆水壺：壺嘴朝前（+z），名字叫 Spout 的節點是出水口
static func _make_watering_can() -> Node3D:
	var root := Node3D.new()
	root.name = "WateringCan"
	var col := Color("6fa3b3")
	Models.part(root, Models.cyl(0.1, 0.11, 0.2), col, Vector3(0, 0.0, 0))
	Models.part(root, Models.cyl(0.105, 0.105, 0.03), col.darkened(0.15), Vector3(0, 0.1, 0), Vector3.ONE, Vector3.ZERO, false)
	var sp := Models.part(root, Models.cyl(0.015, 0.03, 0.3), col, Vector3(0, 0.07, 0.2))
	sp.rotation_degrees = Vector3(60, 0, 0)
	Models.part(root, Models.box(0.03, 0.18, 0.03), col.darkened(0.2), Vector3(0, 0.12, -0.12), Vector3.ONE, Vector3(-25, 0, 0))
	var spout := Node3D.new()
	spout.name = "Spout"
	spout.position = Vector3(0, 0.16, 0.34)
	root.add_child(spout)
	return root


func _spawn_visitors(w: WorldModel, who_list: Array = ["wolf", "rabbit"]) -> void:
	for who in who_list:
		var a := room.spawn_npc(who, visitor_spot(who, w), "N")
		a.face_vector(visitor_look(who))
		a.model.rotation.y = a.target_yaw
		a.bubble_requested.connect(_on_bubble)


static func _door_x(w: WorldModel) -> float:
	return RoomView.door_x(w)


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
## 派派鼠帶著行李從外地來到派派森林，對照爺爺給的照片找到樹屋，進門打掃，派派狼來敲門。
## 所有角色都從南牆的門洞進出，屋裡沿著格子走（find_path），不穿牆。
var intro_running := false
var intro_advance := false  # 點一下畫面：跳到下一句
var intro_skip := false
var intro_skip_btn: Button
var intro_gen := 0  # 開場重新開始時，舊的開場流程看到編號不同就停
var intro_props: Array = []  # 灰塵、蜘蛛網、防塵布、行李……開場結束就收掉
var intro_dust: Dictionary = {}  # 格子 → 灰塵堆
## 地板上一層髒髒的灰（半透明的貼圖）；掃過的地方會變乾淨
var intro_grime: MeshInstance3D = null
var _grime_img: Image
var _grime_tex: ImageTexture
const GRIME_PPM := 16  # 每公尺幾個像素
var intro_card: Control
var intro_photo: Texture2D  # 爺爺的照片：開場前從門前小路拍的樹屋實景


## 用一台小相機從門前小路拍一張樹屋（不拍角色和信箱，像很久以前的照片）
func _snap_house_photo() -> Texture2D:
	var hidden: Array = []
	for n in [room.gopher, room.npcs.get("wolf"), room.npcs.get("rabbit"), room.mailbox]:
		if n != null and is_instance_valid(n) and n.visible:
			n.visible = false
			hidden.append(n)
	var was := room.cutaway
	room.cutaway = false
	room.update_cutaway(Vector3.ZERO)
	var sv := SubViewport.new()
	sv.size = Vector2i(528, 472)
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.fov = 50
	sv.add_child(cam)
	add_child(sv)
	var dx := _door_x(home_world)
	cam.position = Vector3(dx + 1.2, 1.6, home_world.depth + 10.5)
	cam.look_at(Vector3(dx + 0.6, 2.6, home_world.depth - 2.0), Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	room.cutaway = was
	for n in hidden:
		if is_instance_valid(n):
			n.visible = true
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


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
	intro_photo = await _snap_house_photo()
	if gen != intro_gen:
		return
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
		# 鏡頭停在門口，看得到派派鼠、派派狼、派派兔；不要一下子拉到很遠
		rig.follow_target = null
		rig.target_focus = Vector3(_door_x(home_world) + 0.3, 0.4, home_world.depth + 1.4)
		rig.target_distance = 8.0
		rig.target_yaw = deg_to_rad(-62.0)  # 斜一點，派派狼才不會擋住派派鼠
		rig.target_pitch = deg_to_rad(-34.0)
		await get_tree().create_timer(0.8).timeout
		if mode == "home" and not intro_running:
			hud.show_help()


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
	g.model.add_child(suitcase)  # 右手提著（手垂在身體旁邊），走路時跟著晃
	suitcase.position = Vector3(-0.43, 0.02, 0.02)
	var swing := suitcase.create_tween().set_loops()
	swing.tween_property(suitcase, "rotation:x", 0.1, 0.32).set_trans(Tween.TRANS_SINE)
	swing.tween_property(suitcase, "rotation:x", -0.1, 0.32).set_trans(Tween.TRANS_SINE)
	g.position = Vector3(dx, RoomView.GRASS_Y, w.depth + 10.0)
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
	g.say("（終於到了……派派森林。）", "think")
	await _intro_walk(g, _door_outside(4.5), "N")
	if _intro_stop(gen): return
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
	swing.kill()
	var sgt := suitcase.global_transform
	suitcase.get_parent().remove_child(suitcase)
	room.add_child(suitcase)
	suitcase.global_transform = sgt
	var st2 := suitcase.create_tween().set_parallel()
	st2.tween_property(suitcase, "position", Vector3(side.x + 0.55, 0, side.y + 0.5), 0.3)
	st2.tween_property(suitcase, "rotation", Vector3(0, 0.4, 0), 0.3)
	await st2.finished
	# 從行李裡拿出掃把，雙手握著：握把在手上，刷子碰到身體前面的地板
	var broom := _make_broom(g.carry_anchor.position.y)
	intro_props.append(broom)
	if g.anthro:
		g.play_once(["pick-up"], 0.6)
	g.carry_anchor.add_child(broom)
	broom.position = Vector3.ZERO
	broom.scale = Vector3.ONE * 0.2
	g.carried = broom
	var bt := broom.create_tween()
	bt.tween_property(broom, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await bt.finished
	if _intro_stop(gen): return
	var cur := inside
	for c in [Vector2i(5, 6), Vector2i(3, 3)]:
		await _intro_path(g, cur, c)
		cur = c
		if _intro_stop(gen): return
		await _sweep(g, c)
		if _intro_stop(gen): return
	# 剩下的灰塵、蜘蛛網、防塵布一口氣掃乾淨（掃把收回行李）
	g.carried = null
	_clear_abandoned(0.9)
	for c in [Vector2i(2, 4), Vector2i(5, 2), Vector2i(1, 6), Vector2i(6, 5)]:
		_dust_puff(GopherActor.cell_pos(c))
	await _intro_wait(1.3)
	if _intro_stop(gen): return
	g.happy()
	await _intro_say(g, "（呼～打掃乾淨了！）", "think")
	if _intro_stop(gen): return
	w.gopher_cell = cur
	# ---- 五、打掃完，有人敲門！鏡頭轉到北邊，看得到南牆和門 ----
	var wolf_spot := visitor_spot("wolf", w)
	var rabbit_spot := visitor_spot("rabbit", w)
	wolf_spot.y = RoomView.GRASS_Y
	rabbit_spot.y = RoomView.GRASS_Y
	wolf.position = _door_outside(0.55)
	rabbit.position = rabbit_spot
	wolf.face("N")
	rabbit.face_vector(visitor_look("rabbit"))
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
	await _intro_path(g, cur, inside, "S")
	w.gopher_cell = inside
	if _intro_stop(gen): return
	# 派派鼠開門，派派狼退回小石路上
	await room.swing_door(true)
	if _intro_stop(gen): return
	await _intro_walk(wolf, wolf_spot)
	if _intro_stop(gen): return
	# ---- 六、派派鼠走到門口外，和站在小石路上的兩人隔一段距離說話 ----
	room.cutaway = false
	# 從西南邊斜斜看：派派鼠在門口、兩人在路上，中間空出來，三個人的臉都不會被擋住
	rig.target_focus = Vector3(dx, 0.6, w.depth + 1.6)
	rig.target_distance = 6.4
	rig.target_yaw = deg_to_rad(-55.0)
	rig.target_pitch = deg_to_rad(-20.0)
	var talk_spot := _door_outside(0.85)
	await _intro_walk(g, talk_spot)
	if _intro_stop(gen): return
	g.face("S")
	wolf.face_vector(talk_spot - wolf.position)
	rabbit.face_vector(talk_spot - rabbit.position)
	var lines: Array = []
	var cast := {"wolf": wolf, "rabbit": rabbit, "gopher": g}
	for t in FIRST_MEET.wolf:
		lines.append([cast[t[0]], t[1]])
	for t in FIRST_MEET.rabbit:
		lines.append([cast[t[0]], t[1]])
	lines += [
		[rabbit, "走到派派狼旁邊說說話，就能接任務。學會 print() 就能跟我們聊天了！"],
		[wolf, "我們就在這裡等你，準備好就來找我！"],
	]
	for i in range(lines.size()):
		var l: Array = lines[i]
		if l[0] == g:
			g.confused()
		await _intro_say(l[0], l[1])
		if i == FIRST_MEET.wolf.size() - 1:
			_mark_met("wolf")
		if i == FIRST_MEET.wolf.size() + FIRST_MEET.rabbit.size() - 1:
			_mark_met("rabbit")
		if _intro_stop(gen): return
	# 說完大家都留在原地；派派鼠之後自己走回屋裡
	await _intro_wait(0.6)


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
	var b := g.carried
	if b == null or not is_instance_valid(b):
		b = g.carry_anchor
	# 以握把為軸左右掃：刷子在地上左右刷
	for i in range(3):
		tw.tween_property(b, "rotation:z", 0.5, 0.18).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "rotation:z", -0.5, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "rotation:z", 0.0, 0.12)
	_dust_puff(GopherActor.cell_pos(c))
	_grime_clean(GopherActor.cell_pos(c) + Vector3(0, 0, 0.3), 1.5)
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
		card.photo = intro_photo
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
## 大皮箱：原點在箱子底部；長邊朝前後（提在身體旁邊不會撞到腳），提把在上面
static func _make_suitcase() -> Node3D:
	var root := Node3D.new()
	root.name = "Suitcase"
	var body := Color("b5643c")
	Models.part(root, Models.box(0.17, 0.32, 0.46), body, Vector3(0, 0.17, 0))
	Models.part(root, Models.box(0.18, 0.04, 0.47), Color("8a4a2c"), Vector3(0, 0.22, 0), Vector3.ONE, Vector3.ZERO, false)
	for z in [-0.14, 0.14]:
		Models.part(root, Models.box(0.185, 0.33, 0.035), Color("e8c98a"), Vector3(0, 0.17, z), Vector3.ONE, Vector3.ZERO, false)
	Models.part(root, Models.box(0.05, 0.05, 0.16), Color("5e3d26"), Vector3(0, 0.355, 0))
	Models.part(root, Models.box(0.03, 0.06, 0.03), Color("5e3d26"), Vector3(0, 0.335, -0.07), Vector3.ONE, Vector3.ZERO, false)
	Models.part(root, Models.box(0.03, 0.06, 0.03), Color("5e3d26"), Vector3(0, 0.335, 0.07), Vector3.ONE, Vector3.ZERO, false)
	Models.part(root, Models.sphere(0.04), Color("f6e3b8"), Vector3(0.09, 0.1, 0.12), Vector3(0.3, 1, 1), Vector3.ZERO, false)
	return root


## 掃把：原點是握把（雙手的位置），grip_h 是握把離地的高度。
## 掃把往前斜：上端靠在肩膀後面，刷子在腳前面碰地。
static func _make_broom(grip_h: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Broom"
	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(-20, 0, 0)
	root.add_child(tilt)
	var reach := grip_h / cos(deg_to_rad(20.0))  # 握把沿著掃把到地面的長度
	var head_h := 0.2
	var stick_bottom := -(reach - head_h)
	var stick_top := 0.62
	Models.part(tilt, Models.cyl(0.022, 0.022, stick_top - stick_bottom), Color("b08457"), Vector3(0, (stick_top + stick_bottom) / 2, 0))
	# 扇形的刷子：寬、薄，平的那面朝前
	Models.part(tilt, Models.cyl(0.07, 0.17, head_h), Color("e3c27a"), Vector3(0, stick_bottom - head_h / 2, 0), Vector3(1, 1, 0.35))
	Models.part(tilt, Models.box(0.15, 0.04, 0.07), Color("b5643c"), Vector3(0, stick_bottom + 0.01, 0), Vector3.ONE, Vector3.ZERO, false)
	return root


## 很久沒人住的樣子：地上的灰塵堆、落葉、北邊牆角的蜘蛛網、蓋著防塵布的家具
func _build_abandoned_props() -> void:
	_clear_abandoned(0.0)
	var dust_mat := Color("cbbb98")
	for c in [Vector2i(5, 6), Vector2i(3, 3), Vector2i(1, 4), Vector2i(6, 1), Vector2i(4, 1), Vector2i(1, 7), Vector2i(6, 5)]:
		if not home_world.walkable(c):
			continue
		var pile := Node3D.new()
		var center := GopherActor.cell_pos(c) + Vector3(randf_range(-0.08, 0.08), 0, 0.3)
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
	_build_grime()
	_build_cobwebs()
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


## 地板上的一層灰：雜訊產生灰褐色的髒污，靠牆的地方特別髒，中間有一塊一塊比較淡的灰
func _build_grime() -> void:
	var W := home_world.width * GRIME_PPM
	var H := home_world.depth * GRIME_PPM
	var big := FastNoiseLite.new()
	big.seed = 11
	big.frequency = 0.035
	big.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = 5
	fine.frequency = 0.3
	_grime_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	var dark := Color(0.27, 0.22, 0.16)
	var dusty := Color(0.62, 0.58, 0.5)
	for y in range(H):
		for x in range(W):
			var n := big.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			# 離最近的牆幾公尺：靠牆、牆角最髒
			var d := minf(minf(float(x), float(W - 1 - x)), minf(float(y), float(H - 1 - y))) / GRIME_PPM
			var e := clampf(1.0 - d / 1.4, 0.0, 1.0)
			var al := 0.45 + 0.3 * smoothstep(0.35, 0.8, n) + 0.3 * e * e + 0.3 * (f - 0.5)
			var col := dusty.lerp(dark, clampf(0.2 + 0.6 * smoothstep(0.4, 0.85, n) + 0.45 * e, 0.0, 1.0))
			if f > 0.78:   # 小小的髒點、碎屑
				col = col.darkened(0.35)
				al += 0.2
			col.a = clampf(al, 0.0, 0.9)
			_grime_img.set_pixel(x, y, col)
	_grime_tex = ImageTexture.create_from_image(_grime_img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _grime_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var pm := PlaneMesh.new()
	pm.size = Vector2(home_world.width, home_world.depth)
	intro_grime = MeshInstance3D.new()
	intro_grime.mesh = pm
	intro_grime.material_override = m
	intro_grime.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	intro_grime.position = Vector3(home_world.width / 2.0, 0.012, home_world.depth / 2.0)
	room.add_child(intro_grime)


## 掃過的地方變乾淨：以 at 為中心、半徑 r 公尺，邊緣淡淡地漸變
func _grime_clean(at: Vector3, r: float) -> void:
	if _grime_img == null or not is_instance_valid(intro_grime):
		return
	var cx := at.x * GRIME_PPM
	var cy := at.z * GRIME_PPM
	var rp := r * GRIME_PPM
	for y in range(maxi(0, int(cy - rp)), mini(_grime_img.get_height(), int(cy + rp) + 1)):
		for x in range(maxi(0, int(cx - rp)), mini(_grime_img.get_width(), int(cx + rp) + 1)):
			var t := Vector2(x - cx, y - cy).length() / rp
			if t >= 1.0:
				continue
			var c := _grime_img.get_pixel(x, y)
			c.a *= smoothstep(0.55, 1.0, t)
			_grime_img.set_pixel(x, y, c)
	_grime_tex.update(_grime_img)


## 很久沒人住的蜘蛛網：牆的上角（大）、牆腳（小）、圓窗、牆頂垂下來的蛛絲，還有一隻垂絲的小蜘蛛
## 蜘蛛網都放在牆的節點底下，牆藏起來時（鏡頭那一側）會跟著藏，不會飄在半空中
func _build_cobwebs() -> void:
	var w := home_world
	var H := RoomView.WALL_H
	var wn: Node3D = room.walls.get("N", room)
	_add_web(wn, Vector3(0.03, H - 0.05, 0.03), 0.0, 1.0, -1.0, 1.15)
	_add_web(wn, Vector3(w.width - 0.03, H - 0.05, 0.03), 0.0, -1.0, -1.0, 1.15)
	_add_web(wn, Vector3(0.03, 0.03, 0.03), 0.0, 1.0, 1.0, 0.5)
	_add_web(wn, Vector3(w.width - 0.03, 0.03, 0.03), 0.0, -1.0, 1.0, 0.5)
	for side in ["W", "E"]:
		var holder: Node3D = room.walls.get(side, room)
		var x := 0.03 if side == "W" else w.width - 0.03
		_add_web(holder, Vector3(x, H - 0.05, w.depth - 0.03), PI / 2, 1.0, -1.0, 0.9)    # 南邊的上角
		_add_web(holder, Vector3(x, H - 0.05, 0.03), PI / 2, -1.0, -1.0, 0.8)           # 北邊的上角（側面）
		_add_web(holder, Vector3(x, 0.03, w.depth * 0.55), PI / 2, 1.0, 1.0, 0.3)
	# 圓窗左上角的小網
	for uid in w.items:
		var it: Dictionary = w.items[uid]
		if it.type == "window" and it.wall == "N":
			var cx: float = it.cell.x + 0.5
			_add_web(wn, Vector3(cx - 0.42, 1.8, 0.1), 0.0, 1.0, -1.0, 0.45)
	# 牆頂垂下來、彎彎的蛛絲
	var col := Color("f4efe4")
	for span: Vector2 in [Vector2(1.0, 2.4), Vector2(5.6, 7.3), Vector2(8.1, 9.4)]:
		var prev := Vector3(span.x, H - 0.03, 0.04)
		for k in range(1, 9):
			var t := k / 8.0
			var p := Vector3(lerpf(span.x, span.y, t), H - 0.03 - 0.22 * 4.0 * t * (1.0 - t), 0.04)
			_web_line(wn, prev, p, col)
			prev = p
	# 垂絲的小蜘蛛：慢慢上下晃
	var thread := Node3D.new()
	thread.position = Vector3(4.4, H - 0.02, 0.06)
	wn.add_child(thread)
	_web_line(thread, Vector3.ZERO, Vector3(0, -0.8, 0), col)
	var spider := Node3D.new()
	spider.position = Vector3(0, -0.8, 0)
	thread.add_child(spider)
	var ink := Color("3a2f2a")
	Models.part(spider, Models.sphere(0.045), ink, Vector3.ZERO, Vector3(1, 1.15, 0.9), Vector3.ZERO, false)
	Models.part(spider, Models.sphere(0.03), ink, Vector3(0, 0.05, 0), Vector3.ONE, Vector3.ZERO, false)
	for sx: float in [-1.0, 1.0]:
		for k in range(4):
			var leg := Models.part(spider, Models.box(0.09, 0.008, 0.008), ink, Vector3(sx * 0.06, 0.02 - k * 0.015, 0), Vector3.ONE, Vector3(0, 0, sx * (30.0 - k * 20.0)), false)
			leg.name = "Leg"
	var bob := thread.create_tween().set_loops()
	bob.tween_property(thread, "scale:y", 0.75, 2.4).set_trans(Tween.TRANS_SINE)
	bob.tween_property(thread, "scale:y", 1.0, 2.4).set_trans(Tween.TRANS_SINE)
	intro_props.append(thread)


## 一張扇形的蜘蛛網：從牆角 pos 往 sx（左右）、sy（上下）張開；yaw = 貼在哪面牆（0 = 南北向的牆面，PI/2 = 東西向）
func _add_web(parent: Node3D, pos: Vector3, yaw: float, sx: float, sy: float, size: float) -> void:
	var web := Node3D.new()
	web.position = pos
	web.rotation.y = yaw
	var col := Color("f8f3ea")
	for k in range(5):
		var a := deg_to_rad(k * 22.5)
		_web_line(web, Vector3.ZERO, Vector3(cos(a) * sx, sin(a) * sy, 0) * size, col)
	for r: float in [0.3, 0.55, 0.8]:
		for k in range(4):
			var a1 := deg_to_rad(k * 22.5)
			var a2 := deg_to_rad((k + 1) * 22.5)
			var sag := size * 0.05
			var p1 := Vector3(cos(a1) * sx, sin(a1) * sy, 0) * size * r
			var p2 := Vector3(cos(a2) * sx, sin(a2) * sy, 0) * size * r
			var mid := (p1 + p2) / 2 * (1.0 - sag / maxf(size * r, 0.01))   # 每一段往中心垂一點
			_web_line(web, p1, mid, col)
			_web_line(web, mid, p2, col)
	parent.add_child(web)
	intro_props.append(web)


func _web_line(parent: Node3D, a: Vector3, b: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var ln := a.distance_to(b)
	m.mesh = Models.box(ln, 0.024, 0.012)
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


## 收掉開場道具；fade > 0 就慢慢變小消失（地上的灰慢慢變淡）
func _clear_abandoned(fade: float) -> void:
	if is_instance_valid(intro_grime):
		if fade <= 0.0:
			intro_grime.queue_free()
		else:
			var gm: StandardMaterial3D = intro_grime.material_override
			var gt := intro_grime.create_tween()
			gt.tween_property(gm, "albedo_color:a", 0.0, fade * 1.6).set_trans(Tween.TRANS_SINE)
			gt.tween_callback(intro_grime.queue_free)
	intro_grime = null
	_grime_img = null
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
	var case_in_hand := g.model.get_node_or_null("Suitcase")
	if case_in_hand != null:
		case_in_hand.queue_free()  # 略過開場時行李還提在手上
	g.carried = null
	for c in room.find_children("Suitcase", "", false, false):
		c.queue_free()
	g.carry_anchor.rotation = Vector3.ZERO
	# 說完話派派鼠站在門口外（格子位置記成門內那一格，之後自己從門走回屋裡）
	g.position = _door_outside(0.85)
	g.face("S")
	home_world.gopher_cell = _door_inside()
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
		a.face_vector(visitor_look(who))
	var h := room._door_hinge()
	if h != null:
		h.rotation.y = 0.0
	room.cutaway = true


func _end_intro() -> void:
	Engine.time_scale = 1.0
	intro_running = false
	play_started = false  # 看完操作說明、按「開始玩！」大家才開始動
	roam_busy = false
	roam_timer = 15.0  # 說完話大家留在原地；派派鼠在門口站一陣子，才自己走回屋裡
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
	music.play("town")
	playback.cancel()
	bubbles.clear_all()
	letters.close()
	book.close()
	room.visible = false
	library.visible = false
	sun_light.directional_shadow_max_distance = 40
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
		elif town.library_door_at(mp, rig.cam):
			hud.show_status("圖書館　點一下走進去", mp)
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
		elif town.library_door_at(mp, rig.cam):
			_enter_library(false)
		else:
			offer.visible = false


# ---------------- 圖書館 ----------------
## inside=false：前庭（外面看教堂）；true：走進大廳
func _enter_library(inside: bool) -> void:
	_cancel_held()
	mode = "library"
	music.play("task")
	playback.cancel()
	bubbles.clear_all()
	letters.close()
	book.close()
	offer.visible = false
	room.visible = false
	town.visible = false
	library.visible = true
	if not library.built:
		var t0 := Time.get_ticks_msec()
		library.build()
		print("library build ms: ", Time.get_ticks_msec() - t0)
		for who in library.npcs:
			library.npcs[who].bubble_requested.connect(_on_bubble)
	library.set_inside(inside)
	if inside:
		library.walk_gopher(Vector3(1.5, 0, 3.5))   # 從大門走進大廳
	hud.set_library_mode()
	hud.show_status("", Vector2.ZERO)
	rig.follow_target = null
	rig.screen_offset = 0.0
	rig.home_focus = library.view_focus()
	rig.home_distance = library.view_distance()
	rig.reset_view()   # 和家裡一樣的角度和距離
	await get_tree().create_timer(0.6).timeout
	if mode == "library" and library.inside == inside:
		if inside and story_after_library:
			story_after_library = false
			if mode == "library":
				_open_lessons(class_cid)
		elif inside:
			library.talk("turtle")
		else:
			library.npcs["gopher"].say("到圖書館了！", "say")


func _library_input(event: InputEvent) -> void:
	var mp := get_viewport().get_mouse_position()
	if event is InputEventMouseMotion:
		var who := library.actor_at(mp, rig.cam)
		var hot := library.hotspot_at(mp, rig.cam) if who == "" else ""
		if who != "":
			var act: String = {"turtle": "　點一下看知識地圖", "rabbit": "　點一下聽故事＋小測驗", "calico": "　點一下考試", "blackcat": "　點一下檢討"}.get(who, "　點一下聊天")
			hud.show_status(LibraryView.NAMES[who] + act, mp)
		elif hot != "":
			var h: Dictionary = library.hotspots[hot]
			var tip: String = {"enter": "　點一下走進去", "exit": "　點一下回前庭", "town": "　點一下回樹屋"}.get(h.act, "　點一下看看")
			hud.show_status(h.name + tip, mp)
		else:
			hud.show_status("", Vector2.ZERO)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var who2 := library.actor_at(mp, rig.cam)
		if who2 == "turtle" or who2 == "rabbit":
			if who2 == "rabbit":
				library.npcs["rabbit"].say("準備好一起去上課了嗎？", "say")
				class_board.open(lessons, save.get("lessons_done", []))
			else:
				library.npcs["turtle"].say("慢慢來，比較快。想知道什麼，館長都說給你聽。", "say")
				_open_lessons("", false)
			return
		if who2 == "calico":
			_open_exam()
			return
		if who2 == "blackcat":
			_open_review()
			return
		if who2 != "":
			library.talk(who2)
			return
		var hot2 := library.hotspot_at(mp, rig.cam)
		if hot2 == "":
			var fp = library.floor_point(mp, rig.cam)   # 點地板：派派鼠走過去
			if fp != null:
				_click_marker_at(library, fp)
				rig.follow_target = library.npcs["gopher"]   # 圖書館很大：鏡頭跟著派派鼠
				library.walk_gopher(fp)
			return
		match library.hotspots[hot2].act:
			"enter":
				_enter_library(true)
			"exit":
				_enter_library(false)
			"town":
				_enter_home()
			_:
				library.describe(hot2)


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
	if room.mailbox != null and is_instance_valid(room.mailbox):
		var flag: Node3D = room.mailbox.find_child("Flag", true, false)
		if flag != null:
			flag.rotation_degrees.x = 0.0 if up else 90.0


func _open_board() -> void:
	_cancel_held()
	hud.show_board(tasks, save.stars)
	_giver().say("準備好一起去冒險了嗎？", "say")


# ---------------- 派派鼠閒晃 ----------------
## 玩家一段時間沒動滑鼠鍵盤：鏡頭慢慢跟著派派鼠，看牠自己在家裡做什麼（觀賞模式）
const IDLE_WATCH_SEC := 12.0
var idle_time := 0.0
var idle_watch := false


func _idle_camera(delta: float) -> void:
	var panels: bool = report.visible or book.visible or letters.visible or hud.board.visible or hud.help_panel.visible or store.visible or lessons.visible or class_board.visible
	var can_watch: bool = mode == "home" and play_started and not intro_running and room.gopher != null and not panels and held.is_empty()
	if not can_watch:
		idle_time = 0.0
		if idle_watch:
			_stop_idle_watch()
		return
	idle_time += delta
	if not idle_watch and idle_time > IDLE_WATCH_SEC:
		idle_watch = true
		rig.follow_target = room.gopher
		rig.target_distance = 8.5
		rig.target_pitch = deg_to_rad(-36.0)
	if idle_watch:
		rig.target_yaw += delta * 0.035  # 很慢地繞著看


func _stop_idle_watch() -> void:
	idle_watch = false
	if rig.follow_target == room.gopher and not click_walking:
		rig.follow_target = null  # 鏡頭停在原地，玩家從這裡接手


func _process(delta: float) -> void:
	if rig.cam:
		room.update_cutaway(rig.cam.global_position)
		if mode == "library":
			library.update_cutaway(rig.cam.global_position)
	# 寫程式模式：演出場景放在任務單和程式碼視窗中間；面板收起／加寬時跟著挪
	if mode == "task" and panel.visible:
		var fs := panel.free_span()
		rig.screen_center_x = (fs.x + fs.y) / 2.0
		bubbles.side_left = fs.x + 8.0
		bubbles.side_right = get_viewport().get_visible_rect().size.x - fs.y + 8.0
	elif mode == "library" and lessons.visible and lessons.scene_on:
		rig.screen_center_x = (get_viewport().get_visible_rect().size.x - LessonBook.SCENE_W) / 2.0
	else:
		rig.screen_center_x = -1.0
	_idle_camera(delta)
	if mode != "home" or roam_busy or room.gopher == null or not play_started:
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
	if g.position.z > w.depth:
		# 在屋外：逛逛前院、看看胡蘿蔔、去溪邊，或回屋裡
		var r := randf()
		if r < 0.35:
			await _auto_walk(g, GopherActor.cell_pos(_nearest_walkable(Vector2i(randi_range(1, w.width - 2), randi_range(2, w.depth - 2)))))
		else:
			var spots: Array = [
				Vector3(randf_range(room.yard_x0() + 0.6, room.yard_x1() - 0.6), 0, randf_range(w.depth + 1.0, room.yard_z1() - 0.8)),
				room.garden_center() + Vector3(-2.2, 0, randf_range(-0.8, 0.8)),
				room.fishing_spot() + Vector3(0.35, 0, 0),
				_door_outside(1.4),
			]
			var to: Vector3 = spots[0] if r < 0.7 else spots[randi() % spots.size()]
			await _auto_walk(g, to)
			await _idle_action(g)
		roam_busy = false
		return
	# 在屋裡：偶爾出門走走
	if randf() < 0.2:
		await _auto_walk(g, Vector3(randf_range(room.yard_x0() + 0.6, room.yard_x1() - 0.6), 0, randf_range(w.depth + 1.2, room.yard_z1() - 0.8)))
		await _idle_action(g)
		roam_busy = false
		return
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
	else:
		await _idle_action(g)
	roam_busy = false


## 自己發呆時的小動作
func _idle_action(g: Variant) -> void:
	if click_walking or not is_instance_valid(g):
		return
	var outside: bool = g.position.z > home_world.depth
	var r := randf()
	if r < 0.2:
		await g.hop(0.15)
	elif r < 0.4:
		await g.play_once(["emote-yes", "interact-right"], 1.2)
	elif r < 0.55:
		var lines: Array = ["今天天氣真好～", "嗯……要做什麼呢？", "（伸個懶腰）"]
		if outside:
			lines += ["胡蘿蔔長得好快！", "溪水的聲音好好聽。", "這片森林好大喔。"]
		else:
			lines += ["這個家越來越像樣了。", "爺爺以前也住在這裡呢。"]
		g.say(lines.pick_random(), "think")
		await _roam_pause(2.0)
	elif r < 0.75:
		# 左看看、右看看
		var y0: float = g.target_yaw
		g.target_yaw = y0 + 0.9
		await _roam_pause(0.8)
		if not is_instance_valid(g):
			return
		g.target_yaw = y0 - 0.9
		await _roam_pause(0.8)
		if not is_instance_valid(g):
			return
		g.target_yaw = y0


## 等一下；玩家點地板叫派派鼠走的時候提早結束
func _roam_pause(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < until and not click_walking and mode == "home":
		await get_tree().process_frame


# ---------------- 點哪裡就走去哪裡 ----------------
var click_serial := 0
var click_target := Vector3.ZERO
var click_walking := false


## 滑鼠指到的地面（屋裡是地板高度，屋外是草地高度）；沒有就回傳 null
func _ground_under_mouse() -> Variant:
	var mp := get_viewport().get_mouse_position()
	var o := rig.cam.project_ray_origin(mp)
	var n := rig.cam.project_ray_normal(mp)
	if n.y > -0.001:
		return null
	var w := home_world
	var p := o + n * ((0.0 - o.y) / n.y)
	if p.x >= 0 and p.x < w.width and p.z >= 0 and p.z < w.depth:
		return p
	return o + n * ((RoomView.GRASS_Y - o.y) / n.y)


func _click_walk_to(p: Vector3) -> void:
	if room.gopher == null or intro_running:
		return
	talk_to = ""
	click_target = p
	click_serial += 1
	_click_marker(p)
	if p.z > room.yard_z1() + 0.5:
		rig.follow_target = room.gopher  # 走上森林小徑：鏡頭跟著
		rig.target_distance = 10.0
		rig.target_pitch = deg_to_rad(-55.0)
	elif rig.follow_target == room.gopher:
		rig.follow_target = null
		rig.reset_view()
	if not click_walking:
		_click_walk_loop()


## 雜貨店的商品清單（照知識地圖排；先備的貨沒到就是「還沒到貨」）
func _open_store() -> void:
	hud.show_status("", Vector2.ZERO)
	store.open(tasks, save.stars)


## 三花奶奶的考核：先說一句話，再打開考試說明
func _open_exam(eid: String = "") -> void:
	hud.show_status("", Vector2.ZERO)
	var gm: GopherActor = library.npcs.get("calico")
	var id := eid if eid != "" else exam.current_exam()
	if gm:
		if exam.wait_left(id) > 0:
			gm.say("哎呀，奶奶累了，讓我休息一下……", "say")
		elif exam.is_ready(id):
			gm.say("準備好了嗎？慢慢想，奶奶等你。", "say")
		else:
			gm.say("還差一點點喔。都學完了再來找奶奶。", "say")
	exam.open_intro(save, id)


## 黑貓弟弟的檢討筆記
func _open_review() -> void:
	hud.show_status("", Vector2.ZERO)
	var bc: GopherActor = library.npcs.get("blackcat")
	if bc:
		bc.say("奶奶不說的，我偷偷告訴你！" if exam.has_review() else "你還沒考過試喔～", "say")
	exam.save = save
	exam.open_review(save)


## 派派兔的森林小課
## 派派兔帶來上課：在圖書館西邊的教室演。館長站在講台上，派派狼、派派鼠、派派兔坐在台下面向黑板的課桌椅上；
## 派派兔很認真（常常點頭），派派狼在打瞌睡（輪到他說話才醒過來）
const RABBIT_COUNTER := Vector3(-5.0, 0, 1.7)
var _class_gen := 0


func _lesson_cast() -> Dictionary:
	if mode != "library" or not library.inside:
		return {}
	library.arrange_class("")   # 先把派派狼、拍拍鳥準備好（藏著）
	var cast := {}
	for who in library.npcs:
		var a: GopherActor = library.npcs[who]
		if not a.bubble_requested.is_connected(_on_bubble):
			a.bubble_requested.connect(_on_bubble)
		cast[who] = a
	return cast


## 這一課的老師站上講台，其他同學坐台下；老師說開場白
var class_teacher := ""


func _on_teacher(who: String) -> void:
	if who != class_teacher:
		class_teacher = who
		library.arrange_class(who)
		_class_gen += 1
		_class_life(_class_gen)
	if not library.npcs.has(who):
		return
	var line: String = class_board.cfg.get("teacher_lines", {}).get(who, "大家坐好，我們開始上課囉。")
	var story := ClassBoard.story_of(class_board.cfg, lessons.concept_id)
	var a: GopherActor = library.npcs[who]
	a.say(line, "say")
	if story != "":
		var g := _class_gen
		await get_tree().create_timer(2.6).timeout
		if g == _class_gen and class_teacher == who and is_instance_valid(a):
			a.say("今天的故事：" + story, "say")


## 上課表選了一堂課：派派兔帶大家去圖書館的教室
func _start_class(cid: String) -> void:
	class_cid = cid
	if mode == "library" and library.inside:
		_open_lessons(cid)
		return
	var a: GopherActor = room.npcs.get("rabbit") if mode == "home" else null
	if a != null and is_instance_valid(a) and a.visible:
		a.say("我們一起去上課吧！", "say")
		await get_tree().create_timer(1.8).timeout
	story_after_library = true
	_enter_library(true)


func _on_lesson_scene(on: bool) -> void:
	bubbles.clear_all()
	var vp := get_viewport().get_visible_rect().size
	_class_gen += 1
	if on:
		library._walk_serial += 1   # 派派鼠不要再照之前點的地方走
		if library._walk_tween:
			library._walk_tween.kill()
		class_teacher = ""
		rig.follow_target = null
		rig.home_focus = Vector3(-10.4, 0.4, -2.0)
		rig.home_distance = 10.0
		rig.reset_view()
		rig.target_yaw = deg_to_rad(90.0)   # 從教室後面看：講台、黑板、館長在前面，同學坐成一排面向黑板
		rig.target_pitch = deg_to_rad(-34.0)
		bubbles.avoid_side_panels = true
		bubbles.side_left = 8.0
		bubbles.side_right = LessonBook.SCENE_W + 16.0
	else:
		bubbles.avoid_side_panels = false
		class_teacher = ""
		if mode == "library":
			library.arrange_class("")
			rig.home_focus = library.view_focus()
			rig.home_distance = library.view_distance()
			rig.reset_view()


## 上課時的小動作：派派狼打瞌睡（頭一點一點、閉眼、頭上冒 Zzz；輪到他說話就醒來），派派兔認真點頭
func _class_life(gen: int) -> void:
	var wolf: GopherActor = library.npcs.get("wolf")
	var rab: GopherActor = library.npcs.get("rabbit")
	if wolf == null or class_teacher == "wolf":
		return   # 派派狼自己當老師的時候就不打瞌睡了
	if class_teacher == "rabbit":
		rab = null
	var zzz := Label3D.new()
	zzz.text = "Z z z"
	zzz.font_size = 64
	zzz.pixel_size = 0.004
	zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zzz.modulate = Color("6a7fb0")
	zzz.outline_size = 10
	zzz.outline_modulate = Color("fffdf6")
	zzz.no_depth_test = true
	wolf.add_child(zzz)
	var k := 0.0
	while gen == _class_gen and mode == "library" and is_instance_valid(wolf):
		await get_tree().create_timer(0.1).timeout
		if gen != _class_gen or not is_instance_valid(wolf):
			break
		k += 0.1
		var awake: bool = wolf.t < wolf._talk_until + 1.2
		zzz.visible = not awake
		var hd: Node3D = wolf.head if wolf.head != null else wolf.body
		if awake:
			if hd:
				hd.rotation.x = lerpf(hd.rotation.x, 0.0, 0.4)
		else:
			wolf.set_face("blink", 0.3)
			if hd:
				hd.rotation.x = 0.22 + sin(k * 1.6) * 0.12   # 頭一點一點
			zzz.position = Vector3(0.25, 1.45 + fmod(k * 0.25, 0.3), 0)
		if rab and int(k * 10) % 45 == 0:
			rab.hop(0.06)   # 派派兔認真點頭
			rab.set_face("happy", 0.6)
	if is_instance_valid(zzz):
		zzz.queue_free()
	if is_instance_valid(wolf):
		var hd2: Node3D = wolf.head if wolf.head != null else wolf.body
		if hd2:
			hd2.rotation.x = 0.0


## quiz：true＝派派兔帶來（故事＋小測驗）；false＝點慢慢館長（只有知識地圖和說明）
func _open_lessons(cid: String = "", quiz: bool = true) -> void:
	hud.show_status("", Vector2.ZERO)
	lessons.open(save.get("lessons_done", []), cid, quiz)
	if quiz:
		music.jingle("bell")   # 上課鐘：噹噹噹噹


## 點下去的地方冒一個小圈圈
func _click_marker(p: Vector3) -> void:
	_click_marker_at(room, p)


func _click_marker_at(parent: Node3D, p: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.22
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.95, 0.75, 0.9)
	ring.material_override = m
	parent.add_child(ring)
	ring.position = p + Vector3(0, 0.03, 0)
	ring.scale = Vector3(0.5, 0.3, 0.5)
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(1.4, 0.3, 1.4), 0.5)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)


func _click_walk_loop() -> void:
	click_walking = true
	while roam_busy:  # 正在做別的事（坐著、走到一半）：等它收尾
		await get_tree().process_frame
		if mode != "home":
			click_walking = false
			return
	roam_busy = true
	var g := room.gopher
	var serial := -1
	var steps: Array = []
	var blocked_n := 0
	g.speed_scale = 1.0
	while mode == "home" and is_instance_valid(g) and not intro_running:
		var locked: bool = not steps.is_empty() and steps[0].get("lock", false)
		if serial != click_serial and not locked:
			serial = click_serial
			steps = _route_to(g, click_target)
			if steps.is_empty():
				break
		if steps.is_empty():
			if talk_to != "" and talk_tries < 3:
				var who_a: GopherActor = room.npcs.get(talk_to)
				if who_a != null and is_instance_valid(who_a) and g.position.distance_to(who_a.position) > 1.5:
					talk_tries += 1
					click_target = _near_point(who_a, g)
					click_serial += 1
					continue
			break
		var nx: Dictionary = steps[0]
		if nx.has("pos") and not nx.get("lock", false):
			var goal_p: Vector3 = nx.pos
			var sub := g.position.move_toward(goal_p, 0.5)
			if _blocked_ahead(g, sub):
				blocked_n += 1
				if blocked_n > 8:
					break
				g.moving = false
				await get_tree().create_timer(0.4).timeout
				serial = -1  # 重新找路（避開擋在前面的人）
				continue
			if g.position.distance_to(goal_p) > 0.55:
				await _do_step(g, {"pos": sub})
				continue
		await _do_step(g, steps.pop_front())
	if is_instance_valid(g):
		g.moving = false
		g.speed_scale = 0.8
	roam_busy = false
	roam_timer = randf_range(8.0, 12.0)  # 走到了先站一下，再自己找事做
	click_walking = false
	if mode == "home" and is_instance_valid(g) and g.position.z > room.path_end_z() - 2.0:
		_leave_for_town()
	elif mode == "home" and talk_to != "":
		var who := talk_to
		talk_to = ""
		var ta: GopherActor = room.npcs.get(who)
		if ta != null and is_instance_valid(ta) and is_instance_valid(g) and g.position.distance_to(ta.position) < 1.8:
			_talk(who)


## 走到森林小徑的盡頭：出遠門去派森小鎮
func _leave_for_town() -> void:
	roam_busy = true
	var g := room.gopher
	g.face("S")
	g.say("小鎮還在整理中……先從選單去圖書館或雜貨店吧！", "say")   # 小鎮場景先不用
	await get_tree().create_timer(1.4).timeout
	roam_busy = false


## 自己動的時候走去某個點（屋裡、屋外都可以，會開門）
func _auto_walk(g: GopherActor, to: Vector3) -> void:
	var steps := _route_to(g, to)
	var tries := 0
	while not steps.is_empty():
		if click_walking or mode != "home" or not is_instance_valid(g):
			break
		var st: Dictionary = steps[0]
		if st.has("pos") and not st.get("lock", false):
			var goal_p: Vector3 = st.pos
			var sub := g.position.move_toward(goal_p, 0.5)
			if _blocked_ahead(g, sub):
				tries += 1
				if tries > 4:
					break
				g.moving = false
				await get_tree().create_timer(0.5).timeout
				if not is_instance_valid(g):
					return
				steps = _route_to(g, to)
				continue
			if g.position.distance_to(goal_p) > 0.55:
				await _do_step(g, {"pos": sub})
				continue
		await _do_step(g, steps.pop_front())
	if is_instance_valid(g):
		g.moving = false


## 往 to 走一小步的路上，有沒有別的角色擋著（派派鼠、派派狼、派派兔都算）
func _blocked_ahead(a: GopherActor, to: Vector3) -> bool:
	var actors: Array = [room.gopher]
	actors.append_array(room.npcs.values())
	var p0 := Vector2(a.position.x, a.position.z)
	var p1 := Vector2(to.x, to.z)
	for b in actors:
		if b == null or not is_instance_valid(b) or b == a or not b.visible:
			continue
		var q := Vector2(b.position.x, b.position.z)
		if q.distance_to(p0) < 0.45:
			continue  # 已經貼在一起了：讓它走開，不要卡住
		var seg := p1 - p0
		var t := 0.0 if seg.length_squared() < 0.0001 else clampf((q - p0).dot(seg) / seg.length_squared(), 0.0, 1.0)
		if q.distance_to(p0 + seg * t) < 0.55:
			return true
	return false


## 一步：{"cell"} 屋裡的格子、{"pos"} 屋外的點、{"door"} 開／關門；"lock" 的步驟中途不換路線（門口）
func _do_step(g: GopherActor, st: Dictionary) -> void:
	if st.has("gate"):
		if st.gate:
			g.moving = false
			await room.swing_gate(true)
		else:
			room.swing_gate(false)
		return
	if st.has("door"):
		if st.door:
			g.moving = false
			await room.swing_door(true)
		else:
			room.swing_door(false)
		return
	var to: Vector3
	if st.has("cell"):
		to = GopherActor.cell_pos(st.cell)
	else:
		to = st.pos
	g.moving = true
	g.face_vector(Vector3(to.x - g.position.x, 0, to.z - g.position.z))
	var tw := g.create_tween()
	tw.tween_property(g, "position", to, maxf(0.05, g.position.distance_to(to) * 0.34 / g.speed_scale))
	await tw.finished
	if st.has("cell"):
		home_world.gopher_cell = st.cell


## 從派派鼠現在的位置走到 to 的步驟；走不到回傳空陣列
func _route_to(g: GopherActor, to: Vector3) -> Array:
	var w := home_world
	var inside_now := g.position.z < w.depth
	var to_inside := to.x >= 0 and to.x < w.width and to.z >= 0 and to.z < w.depth
	var steps: Array = []
	var door_out := _door_outside(0.9)
	if inside_now:
		var start := _nearest_walkable(w.gopher_cell)
		if to_inside:
			var tc := _nearest_walkable(Vector2i(clampi(int(floor(to.x)), 0, w.width - 1), clampi(int(floor(to.z)), 0, w.depth - 1)))
			var path := w.find_path(start, tc)
			for c in path.slice(1):
				steps.append({"cell": c})
			return steps
		var target := room.nearest_free(to, g)
		var out_path := w.find_path(start, _door_inside())
		if out_path.is_empty():
			return []
		for c in out_path.slice(1):
			steps.append({"cell": c})
		steps.append({"door": true, "lock": true})
		steps.append({"pos": _door_outside(0.3), "lock": true})
		steps.append({"pos": door_out, "lock": true})
		steps.append({"door": false, "lock": true})
		steps.append_array(_outdoor_steps(door_out, room.outdoor_route(door_out, target, g)))
		return steps
	# 在屋外
	if to_inside:
		var back := room.outdoor_route(g.position, door_out, g)
		if back.is_empty() and g.position.distance_to(door_out) > 0.2:
			return []
		steps.append_array(_outdoor_steps(g.position, back))
		steps.append({"door": true, "lock": true})
		steps.append({"pos": _door_outside(0.3), "lock": true})
		steps.append({"cell": _door_inside(), "lock": true})
		steps.append({"door": false, "lock": true})
		var tc2 := _nearest_walkable(Vector2i(clampi(int(floor(to.x)), 0, w.width - 1), clampi(int(floor(to.z)), 0, w.depth - 1)))
		var path2 := w.find_path(_door_inside(), tc2)
		for c in path2.slice(1):
			steps.append({"cell": c})
		return steps
	steps.append_array(_outdoor_steps(g.position, room.outdoor_route(g.position, room.nearest_free(to, g), g)))
	return steps


## 屋外的點變成步驟；穿過柵欄小門的地方先開門、走過去、再關門
func _outdoor_steps(from: Vector3, pts: Array) -> Array:
	var steps: Array = []
	var z1 := room.yard_z1()
	var prev := from
	for p in pts:
		var pp: Vector3 = p
		if (prev.z < z1) != (pp.z < z1):
			var gx := room.path_x(z1)
			var a := Vector3(gx, RoomView.GRASS_Y, z1 - 0.6)
			var b := Vector3(gx, room.ground_y(gx, z1 + 0.6), z1 + 0.6)
			if prev.z >= z1:
				var tmp := a
				a = b
				b = tmp
			steps.append({"pos": a})
			steps.append({"gate": true, "lock": true})
			steps.append({"pos": b, "lock": true})
			steps.append({"gate": false, "lock": true})
		steps.append({"pos": pp})
		prev = pp
	return steps


func _use_furniture(uid: String) -> void:
	if mode != "home" or not home_world.items.has(uid):
		return
	var g := room.gopher
	var it: Dictionary = home_world.items[uid]
	var center := RoomView.item_pos(it, home_world)
	g.face_vector(center - g.position)
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(g) or mode != "home":
		return  # 等的時候進了任務或換了場景，派派鼠已經換成新的
	var use: String = WorldModel.def_of(it.type).get("use", "")
	var back := g.position
	match use:
		"sit":
			var tw := create_tween()
			tw.tween_property(g, "position", center + Vector3(0, 0.48, 0), 0.35)
			await tw.finished
			if not is_instance_valid(g) or mode != "home":
				return
			g.target_yaw = RoomView.item_yaw(it) + 0.0
			g.set_seated(true)
			g.say("坐一下～", "say")
			await _roam_pause(3.0)
			if is_instance_valid(g):
				g.set_seated(false)
		"sleep":
			# 躺在床的正中間：頭靠枕頭（床的 -z 那頭），腳在床尾，臉朝上
			var bed_yaw := RoomView.item_yaw(it)
			var lie := center + Basis(Vector3.UP, bed_yaw) * Vector3(0, 0.62, 0.42)
			g.target_yaw = bed_yaw
			g.model.rotation.y = bed_yaw
			var tw2 := create_tween()
			tw2.tween_property(g, "position", lie, 0.4)
			tw2.parallel().tween_property(g.model, "rotation:x", -PI / 2.2, 0.4)
			await tw2.finished
			if not is_instance_valid(g) or mode != "home":
				return
			g.say("Zzz…", "think")
			await _roam_pause(4.0)
			if not is_instance_valid(g) or mode != "home":
				return
			var tw3 := create_tween()
			tw3.tween_property(g.model, "rotation:x", 0.0, 0.3)
			await tw3.finished
		"read":
			g.say("看書中…", "think")
			await _roam_pause(3.0)
	if mode != "home" or not is_instance_valid(g):
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
	var moved: bool = event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 1.5
	if moved or event is InputEventMouseButton or event is InputEventKey:
		idle_time = 0.0
		if idle_watch:
			_stop_idle_watch()
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if report.visible:
		report.visible = false
		get_viewport().set_input_as_handled()
	elif book.visible:
		book.close()
		get_viewport().set_input_as_handled()
	elif class_board.visible:
		class_board.close()
		get_viewport().set_input_as_handled()
	elif lessons.visible:
		lessons.close()
		get_viewport().set_input_as_handled()
	elif exam.visible:
		exam.close()
		get_viewport().set_input_as_handled()
	elif store.visible:
		store.close()
		get_viewport().set_input_as_handled()
	elif letters.visible:
		letters.close()
		get_viewport().set_input_as_handled()
	elif hud.board.visible:
		hud.board.visible = false
		get_viewport().set_input_as_handled()
	elif hud.help_panel.visible:
		hud.close_help()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode == "town" and not book.visible:
		_town_input(event)
		return
	if mode == "library" and not book.visible and not lessons.visible and not store.visible and not exam.visible:
		_library_input(event)
		return
	if mode != "home" or hud.board.visible or letters.visible or hud.help_panel.visible or store.visible:
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
		elif _npc_under_mouse() != "":
			var nn := _npc_under_mouse()
			hud.show_status(("派派狼：準備好一起去冒險了嗎？（實作委託、拿獎勵）" if nn == "wolf" else "派派兔：準備好一起去上課了嗎？（選課、去教室上課＋小測驗）") , get_viewport().get_mouse_position())
		elif _yard_under_mouse() != "":
			var yt: String = _yard_item(_yard_under_mouse()).get("type", "")
			hud.show_status(WorldModel.def_of(yt).name + "　點一下拿起來", get_viewport().get_mouse_position())
		elif _mailbox_under_mouse():
			var nm := LetterPanel.unread_count(letters.data, save.stars, save.get("letters_read", []))
			hud.show_status("森林信箱　點一下讀信" + ("（%d 封新信）" % nm if nm > 0 else ""), get_viewport().get_mouse_position())
		else:
			hud.show_status("", Vector2.ZERO)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if held.is_empty():
			if intro_running:
				intro_advance = true
				return
			if _npc_under_mouse() != "":
				_approach(_npc_under_mouse())
				return
			if _mailbox_under_mouse():
				_open_letters()
				return
			var uid2 := _item_under_mouse()
			if uid2 != "" and home_world.items[uid2].type == "mailbox":
				_open_letters()
			elif uid2 != "":
				_pick_existing(uid2)
			elif _yard_under_mouse() != "":
				_pick_yard(_yard_under_mouse())
			else:
				var gp: Variant = _ground_under_mouse()
				if gp != null:
					_click_walk_to(gp)
		else:
			_drop_held()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				if not held.is_empty():
					if held.get("yard", false):
						held.yrot = fmod(float(held.yrot) + 45.0, 360.0)
					else:
						held.rot = (held.rot + 1) % 4
					_update_held()
			KEY_ESCAPE:
				_cancel_held()
			KEY_DELETE, KEY_X, KEY_BACKSPACE:
				_store_held()


# ---------------- 前院擺設（花草、蘑菇、石頭）----------------
func _yard_item(uid: String) -> Dictionary:
	for it in save.get("yard", []):
		if it.uid == uid:
			return it
	return {}


## 滑鼠指著哪一個前院擺設（看螢幕上的距離）
func _yard_under_mouse() -> String:
	if mode != "home":
		return ""
	var mp := get_viewport().get_mouse_position()
	var best := ""
	var best_d := INF
	for uid in room.yard_nodes:
		var n: Node3D = room.yard_nodes[uid]
		if not is_instance_valid(n) or not n.visible:
			continue
		var it := _yard_item(uid)
		if it.is_empty():
			continue
		var r := RoomView.yard_radius(it)
		var p := n.global_position + Vector3(0, r * 0.8, 0)
		if rig.cam.is_position_behind(p):
			continue
		var sp := rig.cam.unproject_position(p)
		var edge := rig.cam.unproject_position(p + rig.cam.global_transform.basis.x * maxf(r, 0.25))
		var dd := sp.distance_to(mp)
		if dd < maxf(sp.distance_to(edge), 18.0) and dd < best_d:
			best_d = dd
			best = uid
	return best


func _pick_yard(uid: String) -> void:
	var it := _yard_item(uid)
	if it.is_empty():
		return
	save.yard.erase(it)
	room.remove_yard_node(uid)
	held = {"uid": uid, "type": it.type, "yard": true, "yrot": float(it.get("rot", 0.0)), "scale": float(it.get("scale", 1.0)), "orig": it, "target": null, "reason": ""}
	held.node = RoomView.yard_node(it.type, held.scale)
	room.add_child(held.node)
	_update_held()


func _update_held_yard() -> void:
	var node: Node3D = held.node
	var d := WorldModel.def_of(held.type)
	var r := float(d.get("block", 0.3)) * float(held.scale)
	var gp: Variant = _ground_under_mouse()
	var reason := "放在前院的地上"
	if gp != null:
		var p: Vector3 = gp
		reason = room.yard_place_ok(p.x, p.z, r)
		node.position = Vector3(p.x, RoomView.GRASS_Y + 0.08, p.z)
		held.target = [p.x, p.z]
	node.rotation_degrees.y = float(held.yrot)
	held.reason = reason
	RoomView.tint(node, Color(0.45, 0.85, 0.45, 0.6) if reason == "" else Color(0.95, 0.4, 0.35, 0.6))
	var nm: String = d.name
	hud.show_status(("%s　左鍵放下・R 旋轉・Del 收起來" % nm) if reason == "" else ("%s：%s" % [nm, reason]), get_viewport().get_mouse_position(), reason != "")


func _drop_held_yard() -> void:
	if held.target == null:
		return
	if held.reason != "":
		room.gopher.say(held.reason, "think")
		return
	var it := {"uid": held.uid, "type": held.type, "pos": held.target, "rot": float(held.yrot), "scale": float(held.scale)}
	_free_held_node(held.node)
	save.yard.append(it)
	room.set_yard_item(it)
	held = {}
	hud.show_status("", Vector2.ZERO)
	_write_save()


func _mailbox_under_mouse() -> bool:
	if room.mailbox == null or not is_instance_valid(room.mailbox):
		return false
	var p := room.mailbox.global_position + Vector3(0, 0.75, 0)
	if rig.cam.is_position_behind(p):
		return false
	return rig.cam.unproject_position(p).distance_to(get_viewport().get_mouse_position()) < 50


## 滑鼠指著哪一個訪客（派派狼／派派兔）
func _npc_under_mouse() -> String:
	var mp := get_viewport().get_mouse_position()
	var best := ""
	var best_d := 55.0
	for who in ["wolf", "rabbit"]:
		var a: GopherActor = room.npcs.get(who)
		if a == null or not is_instance_valid(a) or not a.visible:
			continue
		var p := a.global_position + Vector3(0, 0.6, 0)
		if rig.cam.is_position_behind(p):
			continue
		var dd := rig.cam.unproject_position(p).distance_to(mp)
		if dd < best_d:
			best_d = dd
			best = who
	return best


# ---------------- 跟派派狼、派派兔說話 ----------------
const FIRST_MEET := {
	"wolf": [["wolf", "嘿！新來的，看你的家空空的，我教你怎麼打工拿獎勵。"], ["gopher", "……？"], ["wolf", "........怎麼不說話？"], ["wolf", "喔！你是不會用表達式 print() 吧！"], ["wolf", "我看你甚麼都不會的樣子，沒關係！以後跟著我混，我教你！"]],
	"rabbit": [["rabbit", "你好呀！我是派派兔。"], ["rabbit", "半年前才來到派派森林，跟著慢慢館長學習草藥的知識，"], ["rabbit", "平常會在圖書館打工。"], ["rabbit", "沒有排班的時候都跟著派狼隊長冒險。"], ["rabbit", "你也可以叫我兔兔學姊，以後就跟著我們一起冒險吧！"]],
}
const RABBIT_TIPS := [
	"有不會的就問我喔！",
	"卡住的時候，先看看任務書吧！",
	"print() 括號裡要放字串，字串要用引號包起來喔。",
	"程式一行一行慢慢看，錯誤訊息也是好朋友！",
	"胡蘿蔔今天也很有精神～",
	"派派狼說話很兇，其實人很好喔。",
]
## 派派鼠做完第一個任務、會用 print() 說話以後，點派派兔有機會聊到的小故事（一句一句說）
const RABBIT_STORIES := [
	["你問我為什麼愛吃紅蘿蔔還要戴眼鏡？", "可能是因為我讀書忘記休息了。", "保護眼睛除了要有充足的營養，更重要的是適當的休息喔！", "這是我剛從草藥學的書裡學到的知識喔！"],
]
const RABBIT_STORY_CHANCE := 0.35
var talk_to := ""  # 走過去以後要跟誰說話
var talk_tries := 0


func _mark_met(who: String) -> void:
	if not save.has("met"):
		save.met = {}
	save.met[who] = true


## 點了派派狼或派派兔：派派鼠先走到他旁邊，到了才開始說話
func _approach(who: String) -> void:
	var a: GopherActor = room.npcs.get(who)
	var g := room.gopher
	if a == null or g == null:
		return
	talk_tries = 0
	_click_walk_to(_near_point(a, g))
	talk_to = who  # _click_walk_to 會清掉 talk_to，所以放在後面


func _near_point(a: GopherActor, g: GopherActor) -> Vector3:
	var dir := Vector3(g.position.x - a.position.x, 0, g.position.z - a.position.z)
	if dir.length() < 0.1:
		dir = Vector3(0, 0, 1)
	return a.position + dir.normalized() * 0.85


## 走到了：面對面說話。第一次見面先自我介紹；派派狼接著打開任務板，派派兔打開任務書
func _talk(who: String) -> void:
	var a: GopherActor = room.npcs.get(who)
	var g := room.gopher
	if a == null or g == null or not is_instance_valid(a):
		return
	roam_busy = true
	g.face_vector(a.position - g.position)
	a.face_vector(g.position - a.position)
	if not save.get("met", {}).get(who, false):
		for t in FIRST_MEET[who]:
			var line: String = t[1]
			if t[0] == "gopher":
				g.confused()
				g.say(line, "say")
			else:
				a.say(line, "say")
			await get_tree().create_timer(maxf(2.4, 1.0 + line.length() * 0.12)).timeout
			if mode != "home" or click_walking:
				roam_busy = false
				return
		_mark_met(who)
		_write_save()
	elif who == "rabbit" and _first_task_done() and randf() < RABBIT_STORY_CHANCE:
		# 聊一段小故事，說完才打開任務書
		for line: String in RABBIT_STORIES.pick_random():
			a.say(line, "say")
			await get_tree().create_timer(maxf(2.4, 1.0 + line.length() * 0.12)).timeout
			if mode != "home" or click_walking:
				roam_busy = false
				return
		roam_busy = false
		roam_timer = 10.0
		_go_story(a)
		return
	roam_busy = false
	roam_timer = 10.0
	# 派派狼：冒險（實作任務）；派派兔：認識世界（小課＋選擇題小測驗）
	if who == "wolf":
		_open_board()
	else:
		_go_story(a)


## 派派兔：「準備好一起去上課了嗎？」→ 打開上課表選課 → 「我們一起去上課吧！」→ 圖書館的教室
func _go_story(a: GopherActor = null) -> void:
	if a == null and mode == "home" and room.npcs.has("rabbit"):
		a = room.npcs.get("rabbit")
	if a != null and is_instance_valid(a) and a.visible:
		a.say("準備好一起去上課了嗎？", "say")
	class_board.open(lessons, save.get("lessons_done", []))


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
	if it.type in ["sky_door", "sky_crates"]:
		room.gopher.say("（往天空樹頂的樓梯被木箱堵住了，暫時上不去……）", "think")
		return
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
	if WorldModel.def_of(type).get("kind", "") == "yard":
		held = {"uid": _new_uid(), "type": type, "yard": true, "yrot": 0.0, "scale": 1.0, "orig": null, "target": null, "reason": ""}
		held.node = RoomView.yard_node(type, 1.0)
		room.add_child(held.node)
		_update_held()
		return
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
	if held.get("yard", false):
		_update_held_yard()
		return
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
	if held.get("yard", false):
		_drop_held_yard()
		return
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
	if held.get("yard", false):
		_free_held_node(held.node)
		if held.orig != null:
			save.yard.append(held.orig)
			room.set_yard_item(held.orig)
		else:
			save.inventory[held.type] = int(save.inventory.get(held.type, 0)) + 1
			hud.set_inventory(save.inventory)
		held = {}
		hud.show_status("", Vector2.ZERO)
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
	if held.get("yard", false):
		_free_held_node(held.node)
		save.inventory[held.type] = int(save.inventory.get(held.type, 0)) + 1
		held = {}
		hud.set_inventory(save.inventory)
		hud.show_status("", Vector2.ZERO)
		_write_save()
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
	music.play("task")
	music.jingle("battle")   # 出發冒險：走位、解謎、奪寶，開場要刺激一點
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
	rig.screen_offset = 0.0
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
	room.show_rug = bool(save.get("home_rug", true))
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
		music.jingle()
		save.stars[task.id] = max(int(save.stars.get(task.id, 0)), rep.stars)
		if first_clear:
			var rt: String = task.reward.furniture
			save.inventory[rt] = int(save.inventory.get(rt, 0)) + 1
			if task.reward.get("rug", false):
				save.home_rug = true   # 雜貨店老闆順便把圓地毯鋪好了
		_write_save()


func _accept_reward() -> void:
	report.visible = false
	_exit_task()
	await get_tree().create_timer(0.5).timeout
	room.gopher.say("雜貨店老闆送貨來了！新家具放進收藏冊囉！", "say")
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
			print("gopher ", room.gopher.position, " vis ", room.gopher.visible, " cam ", rig.cam.global_position, " gen ", intro_gen, " idle ", idle_time, " watch ", idle_watch, " play ", play_started, " anim ", room.gopher.anim.current_animation if room.gopher.anim else "-")
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
		elif s == "library" or s == "library_in":
			await _enter_library(s == "library_in")
			await get_tree().create_timer(1.5).timeout
		elif s.begins_with("libtalk:"):
			library.talk(s.substr(8))
			await get_tree().create_timer(0.4).timeout
		elif s == "store":
			_open_store()
			await get_tree().create_timer(0.4).timeout
		elif s.begins_with("storearea:"):
			store.show_area(s.substr(10))
			await get_tree().create_timer(0.3).timeout
		elif s.begins_with("exam:"):   # exam:E1 或 exam:E1:force（不檢查條件）
			var ea: Array = s.substr(5).split(":")
			exam.force = ea.size() > 1
			_open_exam(ea[0])
			await get_tree().create_timer(0.4).timeout
		elif s == "examstart":
			exam._start()
			await get_tree().create_timer(0.4).timeout
		elif s.begins_with("examq:"):
			exam._goto(int(s.substr(6)))
			await get_tree().create_timer(0.3).timeout
		elif s.begins_with("exampick:"):
			exam._pick_mc(int(s.substr(9)))
			await get_tree().create_timer(0.2).timeout
		elif s.begins_with("examcode:"):
			exam.editor.text = s.substr(9).replace("\\n", "\n")
			exam.answers[exam.qi] = exam.editor.text
		elif s == "examrun":
			exam._run_code()
			await get_tree().create_timer(0.2).timeout
		elif s.begins_with("examin:"):
			exam.input_edit.text = s.substr(7)
			exam._send_input()
			await get_tree().create_timer(0.2).timeout
		elif s == "examcheat":   # 開發用：全部填標準答案（檢查標準答案能不能拿滿分）
			for i in exam.questions[exam.eid].size():
				var eq: Dictionary = exam.questions[exam.eid][i]
				exam.answers[i] = eq.answer if eq.kind == "mc" else String(eq.task.reference)
		elif s == "examsubmit":
			exam._grade(false)
			await get_tree().create_timer(0.4).timeout
		elif s == "examreview":
			_open_review()
			await get_tree().create_timer(0.4).timeout
		elif s == "story":
			await _go_story()
			await get_tree().create_timer(1.0).timeout
		elif s.begins_with("classtab:"):
			class_board.set_filter(s.substr(9))
			await get_tree().create_timer(0.3).timeout
		elif s.begins_with("class:"):
			class_board.visible = false
			await _start_class(s.substr(6))
			await get_tree().create_timer(2.5).timeout
		elif s == "lessons":
			_open_lessons()
			await get_tree().create_timer(0.4).timeout
		elif s.begins_with("turtlebook"):
			_open_lessons("print", false)
			await get_tree().create_timer(0.4).timeout
		elif s.begins_with("lesson:"):
			_open_lessons(s.substr(7))
			await get_tree().create_timer(0.4).timeout
		elif s.begins_with("lessonstep:"):
			lessons._go(int(s.substr(11)))
			await get_tree().create_timer(0.3).timeout
		elif s.begins_with("lessonpick:"):
			lessons._pick(int(s.substr(11)))
			await get_tree().create_timer(0.4).timeout
		elif s == "lessonask":
			lessons._asked = true
			lessons._go(0)
			await get_tree().create_timer(0.3).timeout
		elif s.begins_with("libwalk:"):
			var wp: Array = s.substr(8).split(",")
			library.walk_gopher(Vector3(float(wp[0]), 0, float(wp[1])))
		elif s.begins_with("libhot:"):
			library.describe(s.substr(7))
			await get_tree().create_timer(0.4).timeout
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
		elif s.begins_with("click:"):
			var cxz: Array = s.substr(6).split(",")
			_click_walk_to(Vector3(float(cxz[0]), 0, float(cxz[1])))
		elif s.begins_with("yard_move:"):
			# yard_move:uid,x,z（測試用：搬前院擺設）
			var ya: Array = s.substr(10).split(",")
			_pick_yard(ya[0])
			if not held.is_empty():
				var x := float(ya[1])
				var z := float(ya[2])
				held.target = [x, z]
				held.reason = room.yard_place_ok(x, z, RoomView.yard_radius({"type": held.type, "scale": held.scale}))
				print("yard_move reason='", held.reason, "'")
				if held.reason == "":
					_drop_held_yard()
				else:
					_cancel_held()
		elif s.begins_with("yard_store:"):
			_pick_yard(s.substr(11))
			_store_held()
			print("inventory ", save.inventory)
		elif s.begins_with("use:"):
			# use:uid（測試用：派派鼠走到家具旁邊使用）
			while roam_busy or click_walking:
				await get_tree().process_frame
			var uu: String = s.substr(4)
			var it_u: Dictionary = home_world.items[uu]
			for c in home_world.footprint(it_u):
				for dn in WorldModel.DIR_ORDER:
					var nb: Vector2i = c + WorldModel.DIRS[dn]
					if home_world.walkable(nb):
						room.gopher.position = GopherActor.cell_pos(nb)
						home_world.gopher_cell = nb
			roam_busy = true
			_use_furniture(uu)
		elif s == "sheet_close":
			panel.set_sheet_open(false)
		elif s == "sheet_open":
			panel.set_sheet_open(true)
		elif s == "code_wide":
			panel.set_code_wide(not panel.code_wide)
		elif s == "sheet_end":
			# 任務單捲到最下面（測試用）
			var sc: ScrollContainer = panel.sheet.get_parent()
			sc.scroll_vertical = 99999
		elif s.begins_with("trace:"):
			# trace:秒數（測試用：每 0.25 秒印出三個角色的位置和最近距離）
			var until_t := Time.get_ticks_msec() + int(float(s.substr(6)) * 1000)
			while Time.get_ticks_msec() < until_t:
				var gp3 := room.gopher.position
				var wp: Vector3 = room.npcs.wolf.position
				var rp: Vector3 = room.npcs.rabbit.position
				print("t g(%.2f,%.2f) w(%.2f,%.2f) r(%.2f,%.2f) gw=%.2f gr=%.2f roam=%s click=%s" % [gp3.x, gp3.z, wp.x, wp.z, rp.x, rp.z, Vector2(gp3.x, gp3.z).distance_to(Vector2(wp.x, wp.z)), Vector2(gp3.x, gp3.z).distance_to(Vector2(rp.x, rp.z)), roam_busy, click_walking])
				await get_tree().create_timer(0.25).timeout
		elif s.begins_with("star:"):
			save.stars[s.substr(5)] = 1  # 測試用：當作任務做完了
		elif s == "skip":
			_skip_intro()
		elif s.begins_with("approach:"):
			_approach(s.substr(9))
		elif s == "hobbies":
			visitor_quick = true
			_start_visitor_life()
		elif s.begins_with("answer:"):
			panel.submit_answer(s.substr(7))
		elif s.begins_with("orbit:"):
			# orbit:偏航角,俯角,距離（鏡頭繞著目前焦點轉）
			var o: Array = s.substr(6).split(",")
			rig.follow_target = null
			rig.target_yaw = deg_to_rad(float(o[0]))
			rig.target_pitch = deg_to_rad(float(o[1]))
			rig.target_distance = float(o[2])
		elif s.begins_with("look:"):
			# look:wolf|rabbit|gopher,距離,俯角
			var a: Array = s.substr(5).split(",")
			var who: Node3D = town.npcs.get(a[0]) if mode == "town" else (library.npcs.get(a[0]) if mode == "library" else room.actor(a[0]))
			rig.follow_target = who
			rig.target_distance = float(a[1])
			rig.target_pitch = deg_to_rad(float(a[2]))
		elif s.begins_with("cam:"):
			# cam:看的點x,y,z,距離,水平角,俯角（角度）
			var a: Array = Array(s.substr(4).split(",")).map(func(t): return float(t))
			rig.follow_target = null
			rig.target_focus = Vector3(a[0], a[1], a[2])
			rig.target_distance = a[3]
			rig.target_yaw = deg_to_rad(a[4])
			rig.target_pitch = deg_to_rad(a[5])
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
