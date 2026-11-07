class_name TaskPanel
extends Control
## 寫程式模式的介面：左邊任務單、右邊程式碼／控制列／輸出視窗／變數。
## 程式執行到 input() 時，畫面中間跳出回答框（ask_input）。

signal demo_pressed
signal run_pressed
signal pause_pressed
signal step_pressed
signal speed_changed(speed: float)
signal submit_pressed
signal reset_pressed
signal exit_pressed
signal grid_toggled
signal view_reset
signal answered(text: String)

const SPEEDS := [1.0, 2.0, 4.0]

var task: Dictionary
var sheet: VBoxContainer  # 任務單：標題＋四段色塊（任務目標／撰寫規定／限制條件／預期演出）
var code: CodeEdit
var console: RichTextLabel
var vars_label: RichTextLabel
var btn_run: Button
var btn_pause: Button
var btn_step: Button
var btn_speed: Button
var btn_submit: Button
var btn_demo: Button
var title_label: Label
var title_sub: Label
var banner: Label
var speed_i := 0
var ask_box: PanelContainer
var ask_label: Label
var ask_edit: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build()


func _build() -> void:
	# ---- 上方標題列 ----
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	top.offset_bottom = 54
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	top.add_child(th)
	title_label = UIKit.label("", 20)
	title_label.add_theme_font_override("font", UIKit.font_bold())
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(title_label)
	title_sub = UIKit.label("", 14, Color("8a6a50"))
	title_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(title_sub)
	th.add_child(UIKit.tertiary(UIKit.button("格子 開／關", func(): grid_toggled.emit(), "顯示或隱藏地板格子與座標")))
	th.add_child(UIKit.tertiary(UIKit.button("視角重設", func(): view_reset.emit(), "右鍵拖曳旋轉、中鍵拖曳平移、滾輪縮放、Q/E 轉 90 度")))
	th.add_child(UIKit.button("離開任務", func(): exit_pressed.emit()))

	# ---- 左：任務單 ----
	var left := PanelContainer.new()
	left.anchor_top = 0
	left.anchor_bottom = 1
	left.offset_left = 10
	left.offset_top = 62
	left.offset_right = 380
	left.offset_bottom = -10
	left.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fff8ec"), 16))
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	sheet = VBoxContainer.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_theme_constant_override("separation", 10)
	scroll.add_child(sheet)
	btn_demo = UIKit.button("▶  看示範（派派鼠演給你看）", func(): demo_pressed.emit(), "用標準答案演一遍，不會顯示程式碼")
	btn_demo.add_theme_font_size_override("font_size", 17)

	# ---- 右：程式碼 ----
	var right := PanelContainer.new()
	right.anchor_left = 1
	right.anchor_right = 1
	right.anchor_bottom = 1
	right.offset_left = -480
	right.offset_right = -10
	right.offset_top = 62
	right.offset_bottom = -10
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	rv.add_child(UIKit.label("程式碼", 16))
	code = CodeEdit.new()
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.size_flags_stretch_ratio = 1.4
	code.gutters_draw_line_numbers = true
	code.indent_use_spaces = true
	code.indent_size = 4
	code.indent_automatic = true
	code.auto_brace_completion_enabled = false
	code.highlight_current_line = true
	code.draw_tabs = true
	code.scroll_past_end_of_file = false
	code.minimap_draw = false
	code.add_theme_font_override("font", UIKit.mono())
	code.add_theme_font_size_override("font_size", 18)
	code.add_theme_constant_override("line_spacing", 6)
	code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var cs := UIKit.panel_style(Color("fffdf6"), 10, UIKit.INK, 2)
	cs.content_margin_left = 4  # 行號靠左，不要空一大格
	code.add_theme_stylebox_override("normal", cs)
	var fs := UIKit.panel_style(Color("fffdf6"), 10, UIKit.ACCENT_LINE, 3)
	fs.content_margin_left = 4
	code.add_theme_stylebox_override("focus", fs)
	# 示範／執行中不能編輯：換成淡一點的紙色，文字顏色不變（原本會變成灰底灰字）
	var ros := UIKit.panel_style(Color("f6efe2"), 10, UIKit.INK, 2)
	ros.content_margin_left = 4
	code.add_theme_stylebox_override("read_only", ros)
	code.add_theme_color_override("font_color", Color("3b2a1e"))
	code.add_theme_color_override("font_readonly_color", Color("3b2a1e"))
	code.add_theme_color_override("current_line_color", Color(1, 0.86, 0.6, 0.25))
	code.add_theme_color_override("line_number_color", Color("bdb5ab"))  # 淡灰色行號
	code.add_theme_color_override("bookmark_color", UIKit.TEXT_RED)
	code.add_theme_color_override("executing_line_color", Color(0.4, 0.75, 1.0, 0.35))
	code.add_theme_color_override("caret_color", UIKit.INK)
	code.add_theme_color_override("selection_color", Color(1, 0.75, 0.45, 0.5))
	code.syntax_highlighter = _highlighter()
	rv.add_child(code)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 6)
	rv.add_child(ctrl)
	btn_run = UIKit.button("▶ 執行", func(): run_pressed.emit(), "執行程式，讓派派鼠演出來（只跑題目給的情境）")
	btn_pause = UIKit.button("Ⅱ 暫停", func(): pause_pressed.emit())
	btn_step = UIKit.button("單步", func(): step_pressed.emit(), "一次執行一行，可以看變數的值")
	btn_speed = UIKit.button("速度 1x", _cycle_speed)
	btn_submit = UIKit.button("★ 交件", func(): submit_pressed.emit(), "交給派派狼檢查（含隱藏測資）")
	UIKit.primary(btn_run)
	UIKit.primary(btn_submit)
	var btn_reset := UIKit.button("重來", func(): reset_pressed.emit(), "房間回到一開始的樣子")
	for b in [btn_run, btn_pause, btn_step, btn_speed, btn_reset, btn_submit]:
		ctrl.add_child(b)
	btn_submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 6)
	rv.add_child(bottom)
	var cons_box := VBoxContainer.new()
	cons_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(cons_box)
	cons_box.add_child(UIKit.label("輸出視窗", 14))
	var cpanel := PanelContainer.new()
	cpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cpanel.add_theme_stylebox_override("panel", UIKit.panel_style(Color("3b2f2a"), 10, UIKit.INK, 2))
	cons_box.add_child(cpanel)
	console = RichTextLabel.new()
	console.bbcode_enabled = true
	console.scroll_following = true
	console.selection_enabled = true
	console.add_theme_color_override("default_color", Color("fff1d6"))
	console.add_theme_font_override("normal_font", UIKit.mono())
	console.add_theme_font_size_override("normal_font_size", 15)
	cpanel.add_child(console)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = 150
	bottom.add_child(vbox)
	vbox.add_child(UIKit.label("變數", 14))
	var vpanel := PanelContainer.new()
	vpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpanel.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fffdf6"), 10, UIKit.INK, 2))
	vbox.add_child(vpanel)
	vars_label = RichTextLabel.new()
	vars_label.bbcode_enabled = true
	vars_label.add_theme_font_override("normal_font", UIKit.mono())
	vars_label.add_theme_font_size_override("normal_font_size", 15)
	vpanel.add_child(vars_label)

	# ---- 中間上方橫幅（隱藏測資、示範中…）----
	banner = UIKit.label("", 20)
	banner.anchor_left = 0
	banner.anchor_right = 1
	banner.offset_left = 400
	banner.offset_right = -500
	banner.offset_top = 70
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bst := UIKit.panel_style(Color("fff1b8"), 14)
	banner.add_theme_stylebox_override("normal", bst)
	banner.visible = false
	add_child(banner)

	# ---- input() 的回答框 ----
	ask_box = PanelContainer.new()
	ask_box.anchor_left = 0
	ask_box.anchor_right = 1
	ask_box.anchor_top = 1.0
	ask_box.anchor_bottom = 1.0
	ask_box.offset_left = 396
	ask_box.offset_right = -496
	ask_box.offset_top = -200
	ask_box.offset_bottom = -40
	ask_box.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fffdf6"), 16, UIKit.ACCENT, 3))
	ask_box.visible = false
	add_child(ask_box)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 8)
	ask_box.add_child(av)
	ask_label = UIKit.label("", 17)
	ask_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	av.add_child(ask_label)
	var ah := HBoxContainer.new()
	av.add_child(ah)
	ask_edit = LineEdit.new()
	ask_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask_edit.placeholder_text = "在這裡輸入回答，按 Enter"
	ask_edit.add_theme_font_size_override("font_size", 18)
	ask_edit.text_submitted.connect(func(t): submit_answer(t))
	ah.add_child(ask_edit)
	ah.add_child(UIKit.primary(UIKit.button("回答", func(): submit_answer(ask_edit.text))))


func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	# 顏色在 #fffdf6 上的對比度都 ≥ 4.5:1
	h.number_color = Color("a8551f")
	h.symbol_color = Color("6b5242")
	h.function_color = Color("2a6fa3")
	h.member_variable_color = Color("7a4fa3")
	for kw in ["if", "elif", "else", "while", "for", "in", "and", "or", "not", "pass", "break", "continue", "import", "from", "def", "return", "as"]:
		h.add_keyword_color(kw, Color("c2407a"))
	for kw in ["True", "False", "None"]:
		h.add_keyword_color(kw, Color("a8551f"))
	for f in ["print", "input", "len", "str", "int", "float", "range", "abs", "min", "max", "round"]:
		h.add_keyword_color(f, Color("2a6fa3"))
	h.add_color_region("\"", "\"", Color("2f7a3f"), true)
	h.add_color_region("'", "'", Color("2f7a3f"), true)
	h.add_color_region("#", "", Color("76644f"), true)
	return h


func _cycle_speed() -> void:
	speed_i = (speed_i + 1) % SPEEDS.size()
	btn_speed.text = "速度 %dx" % int(SPEEDS[speed_i])
	speed_changed.emit(SPEEDS[speed_i])


func speed() -> float:
	return SPEEDS[speed_i]


# ---------------- 內容 ----------------
func load_task(t: Dictionary, saved_code: String) -> void:
	task = t
	var tag := "支線" if t.get("track", "main") == "side" else "任務 No.%d" % int(t.get("order", 0))
	title_label.text = "%s・%s" % [tag, t.title]
	title_sub.text = "%s　難度 %s" % [t.concept, "★".repeat(int(t.get("difficulty", 1)))]
	_fill_sheet(t)
	code.text = saved_code if saved_code != "" else t.get("starter_code", "")
	console.text = ""
	set_vars({})
	clear_marks()
	ask_box.visible = false
	log_system("把程式寫在上面，按「▶ 執行」讓派派鼠演出來；滿意了再按「★ 交件」。")


## 任務單的四段：標題色塊＋淡淡同色的底，一眼分得出是哪一段
const SECTIONS := {
	"goal": ["任務目標", Color("cfe5b8"), Color("355e22"), Color("f3f9ec")],
	"write": ["撰寫規定", Color("cfe0f3"), Color("2c5684"), Color("eff5fb")],
	"limit": ["限制條件", Color("f8d3cb"), Color("a63d33"), Color("fdf1ee")],
	"show": ["預期演出", Color("f8e4a8"), Color("7d5a0c"), Color("fdf8e6")],
}


static func _rtl(bb: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("mono_font", UIKit.mono())
	r.add_theme_font_override("bold_font", UIKit.font_bold())
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 16)
	r.add_theme_font_size_override("mono_font_size", 16)
	r.add_theme_color_override("default_color", UIKit.INK)
	r.text = bb
	return r


static func _section(key: String, body: String, extra: Control = null) -> PanelContainer:
	var d: Array = SECTIONS[key]
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = d[3]
	cs.set_corner_radius_all(10)
	cs.border_color = d[1].darkened(0.08)
	cs.set_border_width_all(2)
	cs.content_margin_left = 0
	cs.content_margin_right = 0
	cs.content_margin_top = 0
	cs.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", cs)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var head := PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = d[1]
	hs.corner_radius_top_left = 8
	hs.corner_radius_top_right = 8
	hs.content_margin_left = 12
	hs.content_margin_right = 12
	hs.content_margin_top = 4
	hs.content_margin_bottom = 4
	head.add_theme_stylebox_override("panel", hs)
	var hl := UIKit.label(d[0], 17, d[2])
	hl.add_theme_font_override("font", UIKit.font_bold())
	head.add_child(hl)
	v.add_child(head)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 10)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	m.add_child(mv)
	if body != "":
		mv.add_child(_rtl(body))
	if extra != null:
		mv.add_child(extra)
	v.add_child(m)
	return card


func _fill_sheet(t: Dictionary) -> void:
	if btn_demo.get_parent() != null:
		btn_demo.get_parent().remove_child(btn_demo)
	for c in sheet.get_children():
		c.queue_free()
	var parts := build_sheet(t)
	sheet.add_child(_rtl(parts.head))
	sheet.add_child(_section("goal", parts.goal))
	sheet.add_child(_section("write", parts.write))
	sheet.add_child(_section("limit", parts.limit))
	sheet.add_child(_section("show", parts.show, btn_demo))


## 任務單內容：{head, goal, write, limit, show}（BBCode）
static func build_sheet(t: Dictionary) -> Dictionary:
	var sh: Dictionary = t.get("sheet", {})
	var role: String = t.get("print_role", "action")
	var giver: String = RoomView.NAMES.get(t.get("npc", "wolf"), "派派狼")
	var head := "[font_size=20][b]%s的任務單[/b][/font_size]\n" % giver
	head += "[color=#8a6a50]%s・難度 %s[/color]" % [UIKit.esc(t.get("concept", "")), "★".repeat(int(t.get("difficulty", 1)))]
	var hidden := 0
	for test in t.get("tests", []):
		if test.get("hidden", false):
			hidden += 1
	# 1. 任務目標
	var goal := "%s" % sh.get("story", "")
	for g in sh.get("given", []):
		goal += "\n・%s" % UIKit.esc(g)
	# 2. 撰寫規定
	var s := ""
	if role == "dialogue":
		# 對話任務：說話的方式（不用句型表）
		if not sh.get("howto", []).is_empty():
			s += "[b]怎麼說話[/b]\n"
			for h in sh.howto:
				# 程式一行、說明下一行縮排（表格太窄會把字串從中間切斷）
				s += "[code]%s[/code]\n[indent][color=#6b5242]%s[/color][/indent]\n" % [UIKit.esc(h[0]), UIKit.esc(h[1])]
		s += "[color=#8a6a50]程式裡的 # 註解寫著每一句要說的話。說錯一個字，大家就聽不懂喔！[/color]\n"
	else:
		s += "[b]派派鼠聽得懂的話（句型表）[/b]\n"
		s += "[table=2]"
		s += "[cell][color=#8a6a50]你寫的程式[/color]  [/cell][cell][color=#8a6a50]派派鼠會…[/color][/cell]"
		for p in t.get("patterns", []):
			var say: String = p.say
			s += "[cell][code]print(\"%s\")[/code]  [/cell][cell]%s[/cell]" % [UIKit.esc(say), UIKit.esc(p.get("desc", ""))]
		s += "[/table]\n"
		if role == "mixed":
			s += "[color=#8a6a50]不符合句型的 print() 會變成對派派兔說的話，例如「%s」。[/color]\n" % UIKit.esc(t.get("speech_example", ""))
	var i := 1
	for r in sh.get("rules", []):
		s += "\n%d. %s" % [i, UIKit.esc(r)]
		i += 1
	# 3. 限制條件
	var lim := ""
	for r in sh.get("limits", []):
		lim += ("\n" if lim != "" else "") + "・%s" % UIKit.esc(r)
	if hidden > 0:
		lim += ("\n" if lim != "" else "") + "・交件時還有 %d 組隱藏測資（%s會換別的情況再檢查）" % [hidden, giver]
	if lim == "":
		lim = "・沒有特別的限制，照撰寫規定寫就可以。"
	# 4. 預期演出（看示範按鈕放在這一段）
	var show := UIKit.esc(sh.get("expected", ""))
	return {"head": head, "goal": goal, "write": s.strip_edges(), "limit": lim, "show": show}


func log_output(text: String, demo: bool = false) -> void:
	var prefix := "[color=#9fd3e6]（示範）[/color]" if demo else ""
	console.append_text(prefix + UIKit.esc(text) + "\n")


## input()：問題和回答印在同一行（像真的終端機）
func log_input(prompt: String, value: String, demo: bool = false) -> void:
	var prefix := "[color=#9fd3e6]（示範）[/color]" if demo else ""
	console.append_text(prefix + UIKit.esc(prompt) + "[color=#b8e0a5]" + UIKit.esc(value) + "[/color]\n")


## 程式停在 input()：跳出回答框，等玩家輸入（回傳回答）
func ask_input(prompt: String, asker: String) -> String:
	ask_label.text = "%s問：「%s」\n派派鼠要怎麼回答？（這就是 input() 讀到的文字）" % [asker, prompt]
	ask_edit.text = ""
	ask_box.visible = true
	ask_edit.grab_focus()
	var ans: String = await answered
	return ans


func submit_answer(text: String) -> void:
	if not ask_box.visible:
		return
	ask_box.visible = false
	answered.emit(text)


func log_system(text: String, color: String = "#f6c85f") -> void:
	console.append_text("[color=%s]» %s[/color]\n" % [color, UIKit.esc(text)])


func log_error(err: Dictionary) -> void:
	var line := int(err.get("line", 0))
	var where := ("第 %d 行：" % line) if line > 0 else ""
	console.append_text("[color=#ff8a80]× %s%s：%s[/color]\n" % [where, UIKit.esc(err.get("kind", "錯誤")), UIKit.esc(err.get("message", ""))])
	if err.get("hint", "") != "":
		console.append_text("[color=#ffd59a]  提示：%s[/color]\n" % UIKit.esc(err.hint))
	mark_error(int(err.get("line", 0)))


func set_vars(v: Dictionary) -> void:
	var s := ""
	for k in v:
		var val = v[k]
		s += "[color=#7a4fa3]%s[/color] = %s\n" % [UIKit.esc(str(k)), UIKit.esc(PyInterp.py_repr(val))]
	vars_label.text = s if s != "" else "[color=#7a6a5a]（還沒有變數）[/color]"


func highlight_line(line: int) -> void:
	code.clear_executing_lines()
	if line >= 1 and line <= code.get_line_count():
		code.set_line_as_executing(line - 1, true)


func mark_error(line: int) -> void:
	if line >= 1 and line <= code.get_line_count():
		code.set_line_background_color(line - 1, Color(0.85, 0.28, 0.25, 0.22))
		code.set_caret_line(line - 1)
		code.set_caret_column(0)
		code.center_viewport_to_caret()


func clear_marks() -> void:
	code.clear_executing_lines()
	for i in range(code.get_line_count()):
		code.set_line_background_color(i, Color(0, 0, 0, 0))


func set_running(running: bool, paused: bool = false) -> void:
	btn_run.disabled = running and not paused
	btn_demo.disabled = running
	btn_submit.disabled = running
	code.editable = not running
	btn_pause.text = "▶ 繼續" if paused else "Ⅱ 暫停"
	btn_pause.disabled = not running


func show_banner(text: String) -> void:
	banner.text = text
	banner.visible = text != ""
