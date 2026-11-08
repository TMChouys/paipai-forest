class_name HomeHUD
extends Control
## 平常（滑鼠玩）模式的介面：上方精簡工具列（任務、收藏冊、⋯ 更多）、收藏托盤（按了才出現）、任務板。

signal take_from_inventory(type: String)
signal open_board
signal grid_toggled
signal view_reset
signal task_chosen(task_id: String)
signal reduce_motion_toggled(on: bool)
signal open_book
signal open_lessons  # 派派兔帶去圖書館聽慢慢館長說故事
signal town_toggled  # 回樹屋（在圖書館時）
signal open_library  # 功能選單：去圖書館
signal open_store    # 功能選單：雜貨店的商品清單
signal help_closed  # 操作說明關掉了（開場後按「開始玩！」）
signal music_toggled(on: bool)  # ⋯ → 背景音樂 開／關

var title_label: Label
var town_btn: Button
var home_only: Array = []

var tray: PanelContainer
var tray_row: HBoxContainer
var help: Label
var help_panel: PanelContainer
var status: Label
var board: PanelContainer
var board_list: VBoxContainer
var stars_label: Label
var btn_tasks: Button
var more_menu: PopupMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build()


func _build() -> void:
	var top := PanelContainer.new()
	top.position = Vector2(10, 8)
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	top.add_child(th)
	title_label = UIKit.label("派派鼠的樹屋", 22)
	th.add_child(title_label)
	stars_label = UIKit.label("★ 0", 18, UIKit.TEXT_WARN)
	stars_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(stars_label)
	btn_tasks = UIKit.button("派派狼的冒險", func(): open_board.emit(), "準備好一起去冒險了嗎？寫程式完成委託、拿獎勵（要先上過課；也可以直接點屋外的派派狼）")
	th.add_child(btn_tasks)
	th.add_child(UIKit.button("派派兔的上課", func(): open_lessons.emit(), "派派兔：準備好一起去上課了嗎？選一堂課，去圖書館的教室上課（也可以直接點派派兔）"))
	th.add_child(UIKit.button("任務書", func(): open_book.emit(), "派森小鎮所有的任務，用知識地圖排好"))
	var btn_tray := UIKit.button("收藏冊", func(): tray.visible = not tray.visible, "打開／收起收藏的家具")
	th.add_child(btn_tray)
	var btn_lib := UIKit.button("圖書館", func(): open_library.emit(), "去派森圖書館：派派兔在櫃台打工，三花奶奶在閱讀教室考試")
	th.add_child(btn_lib)
	var btn_store := UIKit.button("雜貨店", func(): open_store.emit(), "看看雜貨店的商品清單（照知識地圖排）")
	th.add_child(btn_store)
	town_btn = UIKit.button("回樹屋", func(): town_toggled.emit(), "回派派森林的樹屋")
	town_btn.visible = false
	th.add_child(town_btn)
	home_only = [stars_label, btn_tray, btn_lib]
	# 不常用的功能收進「⋯」選單
	var more := MenuButton.new()
	more.text = "⋯"
	more.tooltip_text = "更多"
	more.flat = false
	more.add_theme_font_size_override("font_size", 18)
	more.theme_type_variation = "Button"  # 和其他按鈕同樣式
	var pm := more.get_popup()
	pm.theme = UIKit.theme()
	pm.add_item("格子 開／關", 0)
	pm.add_item("視角重設", 1)
	pm.add_item("操作說明", 2)
	pm.add_separator()
	pm.add_check_item("減少動態", 3)
	pm.add_check_item("背景音樂", 4)
	pm.set_item_checked(pm.get_item_index(4), true)
	more_menu = pm
	pm.id_pressed.connect(_on_more)
	th.add_child(more)

	tray = PanelContainer.new()
	tray.anchor_top = 1
	tray.anchor_bottom = 1
	tray.anchor_right = 1
	tray.offset_left = 10
	tray.offset_right = -10
	tray.offset_top = -112
	tray.offset_bottom = -40
	tray.visible = false  # 一開始不顯示，按「收藏冊」才打開
	add_child(tray)
	var tv := HBoxContainer.new()
	tv.add_theme_constant_override("separation", 10)
	tray.add_child(tv)
	var tl := UIKit.label("收藏冊\n（點一下拿出來）", 14)
	tl.custom_minimum_size.x = 110
	tv.add_child(tl)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tv.add_child(sc)
	tray_row = HBoxContainer.new()
	tray_row.add_theme_constant_override("separation", 8)
	sc.add_child(tray_row)

	help = UIKit.label("左鍵：拿起／放下家具　R：旋轉　Delete：收回收藏冊　Esc：取消　右鍵拖曳：轉視角　滾輪：縮放　中鍵／WASD：平移", 13, Color(UIKit.INK, 0.8))
	help.anchor_top = 1
	help.anchor_bottom = 1
	help.anchor_right = 1
	help.offset_left = 14
	help.offset_right = -14
	help.offset_top = -34
	help.offset_bottom = -8
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.visible = false  # 舊的一行說明（現在改用 help_panel）
	add_child(help)
	_build_help_panel()

	status = UIKit.label("", 15)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.add_theme_stylebox_override("normal", UIKit.panel_style(Color("fffdf6"), 10, UIKit.INK, 1))
	status.visible = false
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)

	# 任務板
	board = PanelContainer.new()
	board.anchor_left = 0.5
	board.anchor_right = 0.5
	board.anchor_top = 0.5
	board.anchor_bottom = 0.5
	board.offset_left = -300
	board.offset_right = 300
	board.offset_top = -240
	board.offset_bottom = 240
	board.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fff8ec"), 20, UIKit.INK, 3))
	board.visible = false
	add_child(board)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	board.add_child(bv)
	var bh := HBoxContainer.new()
	bv.add_child(bh)
	var pad := Control.new()
	pad.custom_minimum_size.x = 36  # 和右邊 × 一樣寬，標題才會置中
	bh.add_child(pad)
	var bt := UIKit.label("派派狼：準備好一起去冒險了嗎？", 24)
	bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(bt)
	var bx := UIKit.button("×", func(): board.visible = false, "關閉（Esc）")
	bx.custom_minimum_size = Vector2(36, 36)
	bx.add_theme_font_size_override("font_size", 20)
	bh.add_child(bx)
	var bs := ScrollContainer.new()
	bs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(bs)
	board_list = VBoxContainer.new()
	board_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_list.add_theme_constant_override("separation", 8)
	bs.add_child(board_list)
	var close := UIKit.button("關閉", func(): board.visible = false, "也可以按 Esc")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bv.add_child(close)


func _on_more(id: int) -> void:
	match id:
		0:
			grid_toggled.emit()
		1:
			view_reset.emit()
		2:
			show_help()
		3:
			var i := more_menu.get_item_index(3)
			var on := not more_menu.is_item_checked(i)
			more_menu.set_item_checked(i, on)
			reduce_motion_toggled.emit(on)
		4:
			var i4 := more_menu.get_item_index(4)
			var on4 := not more_menu.is_item_checked(i4)
			more_menu.set_item_checked(i4, on4)
			music_toggled.emit(on4)


func set_music_checked(on: bool) -> void:
	more_menu.set_item_checked(more_menu.get_item_index(4), on)


# ---------------- 怎麼玩（操作說明視窗）----------------
## 開場結束後跳出來一次；之後在「⋯ → 操作說明」打開
func _build_help_panel() -> void:
	help_panel = PanelContainer.new()
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.offset_left = -330
	help_panel.offset_right = 330
	help_panel.offset_top = -270
	help_panel.offset_bottom = 270
	help_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fff8ec"), 20, UIKit.INK, 3))
	help_panel.visible = false
	add_child(help_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	help_panel.add_child(v)
	var title := UIKit.label("歡迎來到派派森林！", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	# 玩法
	var play := UIKit.label("怎麼玩", 18, UIKit.TEXT_INFO)
	v.add_child(play)
	var steps := UIKit.label("1. 找派派兔去上課：選一堂課，到圖書館的教室聽老師說故事，再做選擇題小測驗。
2. 找派派狼一起去冒險：上過課的委託才能接，用 Python 寫程式完成、拿獎勵。
3. 完成任務會拿到新家具，放進收藏冊；把家具拿出來，佈置派派鼠的家！
（所有任務都排在「任務書」裡。）", 16)
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(steps)
	v.add_child(HSeparator.new())
	# 操作
	v.add_child(UIKit.label("操作", 18, UIKit.TEXT_INFO))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var rows := [
		["左鍵點地面", "派派鼠走過去"],
		["左鍵點派派狼／派派兔", "走過去說話：派派狼冒險／派派兔上課"],
		["左鍵點家具、前院花草", "拿起來，再點一下放下"],
		["拿著時  R／Delete／Esc", "旋轉／收進收藏冊／取消"],
		["W A S D", "移動視角"],
		["右鍵拖曳、Q／E", "旋轉視角"],
		["滾輪", "拉近、拉遠"],
		["點信箱", "讀信"],
	]
	for r in rows:
		var k := UIKit.label(r[0], 15, UIKit.INK)
		k.add_theme_font_override("font", UIKit.font_bold())
		grid.add_child(k)
		grid.add_child(UIKit.label(r[1], 15, UIKit.TEXT_MUTED))
	var tip := UIKit.label("這個說明可以在右上角「⋯ → 操作說明」再打開。", 13, UIKit.TEXT_MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)
	var ok := UIKit.button("開始玩！", close_help, "也可以按 Esc")
	ok.theme_type_variation = "PrimaryButton"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size = Vector2(140, 44)
	v.add_child(ok)


func show_help() -> void:
	board.visible = false
	help_panel.visible = true


func close_help() -> void:
	if help_panel.visible:
		help_panel.visible = false
		help_closed.emit()


func set_reduce_motion(on: bool) -> void:
	more_menu.set_item_checked(more_menu.get_item_index(3), on)


## 有還沒接過的任務時，「派派狼的任務」是首頁的主要按鈕
func set_task_cue(has_new: bool) -> void:
	btn_tasks.theme_type_variation = "PrimaryButton" if has_new else ""


## 有沒有解鎖了、但還沒完成的任務
static func has_new_task(tasks: Array, progress: Dictionary) -> bool:
	for t in tasks:
		if progress.get(t.id, 0) == 0 and is_unlocked(t, tasks, progress):
			return true
	return false


func set_inventory(inv: Dictionary) -> void:
	for c in tray_row.get_children():
		c.queue_free()
	var any := false
	for type in inv:
		var n: int = inv[type]
		if n <= 0:
			continue
		any = true
		var d := WorldModel.def_of(type)
		var b := UIKit.button("%s ×%d" % [d.name, n], func(): take_from_inventory.emit(type))
		var swatch := StyleBoxFlat.new()
		b.custom_minimum_size = Vector2(120, 64)
		b.add_theme_font_size_override("font_size", 16)
		var st := UIKit.panel_style(Color(d.get("color", "#ffe2b8")).lightened(0.45), 12, UIKit.INK, 2)
		b.add_theme_stylebox_override("normal", st)
		tray_row.add_child(b)
	if not any:
		tray_row.add_child(UIKit.label("（收藏冊是空的。完成派派狼的任務就能拿到新家具！）", 15))


func set_stars(n: int) -> void:
	stars_label.text = "★ %d" % n


## 在鎮上：標題換成鎮中心，收起只有家裡用得到的按鈕
func set_town_mode(on: bool) -> void:
	title_label.text = "派森小鎮・鎮中心" if on else "派派鼠的樹屋"
	town_btn.visible = on
	for c in home_only:
		c.visible = not on
	if on:
		tray.visible = false
		board.visible = false


## 在圖書館：和鎮上一樣收起家裡的按鈕，按鈕改成回鎮中心
func set_library_mode() -> void:
	set_town_mode(true)
	title_label.text = "派森圖書館"


func show_status(text: String, pos: Vector2, bad: bool = false) -> void:
	status.text = text
	status.visible = text != ""
	status.add_theme_color_override("font_color", UIKit.TEXT_RED if bad else UIKit.INK)
	status.position = pos + Vector2(18, 18)


## tasks：任務清單；progress：{id: stars}
func show_board(tasks: Array, progress: Dictionary) -> void:
	for c in board_list.get_children():
		c.queue_free()
	var first_btn: Button = null
	for t in tasks:
		var unlocked := is_unlocked(t, tasks, progress)
		var stars: int = progress.get(t.id, 0)
		var row := PanelContainer.new()
		var side: bool = t.get("track", "main") == "side"
		var adv: bool = t.get("track", "main") == "adventure"
		row.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fffdf6"), 12, UIKit.INK, 2))
		if not unlocked:
			row.modulate.a = 0.55  # 還沒解鎖：淡一點，不搶眼
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 8)
		info.add_child(th)
		th.add_child(_track_tag(side, adv))
		var tag := "困難" if side else ("出門" if adv else "No.%d" % int(t.order))
		var title_l := UIKit.label("%s　%s" % [tag, t.title], 18)
		title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 長的字自動換行，視窗不會被撐寬
		title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		th.add_child(title_l)
		var reward_name: String = WorldModel.def_of(t.reward.furniture).name
		var sub := "%s　難度 %s　獎勵：%s" % [t.concept, "★".repeat(int(t.difficulty)), reward_name]
		if t.has("place"):
			sub = "地點：%s　%s" % [t.place, sub]
		if not unlocked:
			sub = _lock_reason(t, tasks, progress)
		var sub_l := UIKit.label(sub, 14, Color("8a6a50"))
		sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 「還要先上哪些課」很長時換行
		info.add_child(sub_l)
		if stars > 0:
			h.add_child(_done_stamp())
		var right := VBoxContainer.new()
		h.add_child(right)
		var sl := UIKit.label(("★".repeat(stars) + "☆".repeat(3 - stars)) if stars > 0 else "", 18, UIKit.TEXT_WARN)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(sl)
		var id: String = t.id
		var b := UIKit.focusable(UIKit.button("接受任務" if stars == 0 else "再挑戰", func(): task_chosen.emit(id)))
		if stars == 0 and unlocked:
			UIKit.primary(b)
			if first_btn == null:
				first_btn = b
		b.disabled = not unlocked
		if not unlocked:
			b.text = "未解鎖"
			b.tooltip_text = "先完成前面的任務"
		right.add_child(b)
		board_list.add_child(row)
	board.visible = true
	# 鍵盤可以直接按 Enter 接下一個任務
	if first_btn:
		first_btn.grab_focus.call_deferred()


## 主線／支線標籤（顏色＋文字，色盲也分得出來）
static func _track_tag(side: bool, adv: bool = false) -> Label:
	var l := UIKit.label("冒險" if adv else ("支線" if side else "主線"), 14, UIKit.INK)
	l.add_theme_font_override("font", UIKit.font_bold())
	var st := UIKit.panel_style(Color("c9b3ea") if adv else (Color("9fd18f") if side else Color("ffcf6b")), 8, UIKit.INK, 1)
	st.shadow_size = 0
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", st)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## 「完成！」印章：歪歪地蓋在任務列右邊
static func _done_stamp() -> Label:
	var l := UIKit.label("完成！", 16, Color("2f5f8f"))
	l.add_theme_font_override("font", UIKit.font_bold())
	var st := UIKit.panel_style(Color("dbe4ee"), 8, Color("3a75b0"), 2)
	st.shadow_size = 0
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", st)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.rotation = deg_to_rad(-12)
	l.resized.connect(func(): l.pivot_offset = l.size / 2)
	return l


## 上過的課（main 讀存檔後設定）：委託要先上過對應的課才能接（第一個 print() 任務在家裡就能做，不用先上課）
static var lessons_done: Array = []
static var _task_concepts: Dictionary = {}
static var _concept_names: Dictionary = {}
const NO_LESSON_TASKS := ["D01_hello"]


static func needed_lessons(t: Dictionary) -> Array:
	if t.id in NO_LESSON_TASKS:
		return []
	if _task_concepts.is_empty():
		var km := QuestBook.load_map()
		for kt in km.get("tasks", []):
			if kt.get("game_task", "") != "":
				_task_concepts[kt.game_task] = kt.concepts
		for c in km.get("concepts", []):
			_concept_names[c.id] = c.name
	# 任務 JSON 的 lessons＝任務程式實際用到的課（tools/curriculum/audit.py 檢查、產生）
	var need: Array = t.get("lessons", _task_concepts.get(t.id, []))
	return need.filter(func(c): return not lessons_done.has(c))


static func _lock_reason(t: Dictionary, tasks: Array, progress: Dictionary) -> String:
	if _order_ok(t, tasks, progress):
		var names := needed_lessons(t).map(func(c): return "「%s」" % _concept_names.get(c, c))
		return "先去上課：%s（找派派兔：準備好一起去上課了嗎？）" % "、".join(names)
	var first := 999
	for x in tasks:
		if x.get("track", "main") == "main" and int(x.order) < int(t.order) and progress.get(x.id, 0) == 0:
			first = mini(first, int(x.order))
	return "先完成任務 No.%d" % first


static func is_unlocked(t: Dictionary, tasks: Array, progress: Dictionary) -> bool:
	if progress.get(t.id, 0) > 0:
		return true   # 做過的可以再挑戰
	return _order_ok(t, tasks, progress) and needed_lessons(t).is_empty()


## 順序規則：主線照故事順序一個一個來；支線和野外冒險不看順序，只看上過的課（2026-11-08）
static func _order_ok(t: Dictionary, tasks: Array, progress: Dictionary) -> bool:
	if t.get("track", "main") in ["side", "adventure"]:
		return true
	for x in tasks:
		if x.get("track", "main") == "main" and int(x.order) < int(t.order) and progress.get(x.id, 0) == 0:
			return false
	return true
