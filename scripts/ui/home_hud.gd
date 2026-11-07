class_name HomeHUD
extends Control
## 平常（滑鼠玩）模式的介面：上方精簡工具列（任務、收藏冊、⋯ 更多）、收藏托盤（按了才出現）、任務板。

signal take_from_inventory(type: String)
signal open_board
signal grid_toggled
signal view_reset
signal task_chosen(task_id: String)

var tray: PanelContainer
var tray_row: HBoxContainer
var help: Label
var status: Label
var board: PanelContainer
var board_list: VBoxContainer
var stars_label: Label


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
	th.add_child(UIKit.label("派派鼠的樹屋", 22))
	stars_label = UIKit.label("★ 0", 18, UIKit.TEXT_WARN)
	stars_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(stars_label)
	var bq := UIKit.button("派派狼的任務", func(): open_board.emit(), "也可以直接點屋外的派派狼")
	bq.add_theme_color_override("font_color", Color("8a3b1a"))
	th.add_child(bq)
	th.add_child(UIKit.button("收藏冊", func(): tray.visible = not tray.visible, "打開／收起收藏的家具"))
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
	help.visible = false  # 「⋯ → 操作說明」才顯示
	add_child(help)

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
	var bt := UIKit.label("派派狼的任務板", 24)
	bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(bt)
	var bs := ScrollContainer.new()
	bs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(bs)
	board_list = VBoxContainer.new()
	board_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_list.add_theme_constant_override("separation", 8)
	bs.add_child(board_list)
	var close := UIKit.button("關閉", func(): board.visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bv.add_child(close)


func _on_more(id: int) -> void:
	match id:
		0:
			grid_toggled.emit()
		1:
			view_reset.emit()
		2:
			help.visible = not help.visible


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


func show_status(text: String, pos: Vector2, bad: bool = false) -> void:
	status.text = text
	status.visible = text != ""
	status.add_theme_color_override("font_color", UIKit.TEXT_RED if bad else UIKit.INK)
	status.position = pos + Vector2(18, 18)


## tasks：任務清單；progress：{id: stars}
func show_board(tasks: Array, progress: Dictionary) -> void:
	for c in board_list.get_children():
		c.queue_free()
	for t in tasks:
		var unlocked := is_unlocked(t, tasks, progress)
		var stars: int = progress.get(t.id, 0)
		var row := PanelContainer.new()
		var side: bool = t.get("track", "main") == "side"
		row.add_theme_stylebox_override("panel", UIKit.panel_style(Color("f3eaff") if side else Color("fffdf6"), 12, UIKit.INK, 2))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var tag := "支線・困難" if side else "任務 No.%d" % int(t.order)
		info.add_child(UIKit.label("%s　%s" % [tag, t.title], 18))
		var reward_name: String = WorldModel.def_of(t.reward.furniture).name
		info.add_child(UIKit.label("%s　難度 %s　獎勵：%s" % [t.concept, "★".repeat(int(t.difficulty)), reward_name], 14, Color("8a6a50")))
		var right := VBoxContainer.new()
		h.add_child(right)
		var sl := UIKit.label(("★".repeat(stars) + "☆".repeat(3 - stars)) if stars > 0 else "", 18, UIKit.TEXT_WARN)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(sl)
		var id: String = t.id
		var b := UIKit.button("接受任務" if stars == 0 else "再挑戰", func(): task_chosen.emit(id))
		if stars == 0:
			UIKit.primary(b)
		b.disabled = not unlocked
		if not unlocked:
			b.text = "未解鎖"
			b.tooltip_text = "先完成前面的任務"
		right.add_child(b)
		board_list.add_child(row)
	board.visible = true


static func is_unlocked(t: Dictionary, tasks: Array, progress: Dictionary) -> bool:
	if t.get("track", "main") == "side":
		# 支線：完成 2 個主線任務後解鎖
		var done := 0
		for x in tasks:
			if x.get("track", "main") == "main" and progress.get(x.id, 0) > 0:
				done += 1
		return done >= int(t.get("unlock_after_main", 2))
	for x in tasks:
		if x.get("track", "main") == "main" and int(x.order) < int(t.order) and progress.get(x.id, 0) == 0:
			return false
	return true
